import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/fassade.dart';
import '../../core/gebaeude.dart' show GegBauteil, GegBauteilText;
import '../../core/heizlast.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../bauphysik/bauphysik_page.dart' show lambdaVon;
import '../widgets.dart';

/// Außenseite je Außenwand: +1 = links der Zeichenrichtung, −1 = rechts.
Map<String, double> aussenSeiten(List<Wand> waende, List<Raum> raeume) {
  final hl = [
    for (final r in raeume)
      if (r.umriss != null && r.umriss!.length >= 3 && r.art == RaumArt.raum) HlRaum(id: r.id, name: r.name, umriss: r.umriss!, hoehe: 2500),
  ];
  final aus = <String, double>{};
  for (final w in waende) {
    if (w.teilhoch) continue;
    final hw = HlWand(id: w.id, a: Punkt(w.x1.toDouble(), w.y1.toDouble()), b: Punkt(w.x2.toDouble(), w.y2.toDouble()), dicke: w.dicke, u: 1);
    var links = 0.0, rechts = 0.0;
    for (final (von, bis, l, r) in wandSeiten(hw, hl, schritt: 250)) {
      if (l == null && r != null) links += bis - von;
      if (r == null && l != null) rechts += bis - von;
    }
    if (links > w.laenge * 0.5) aus[w.id] = 1;
    if (rechts > w.laenge * 0.5) aus[w.id] = -1;
  }
  return aus;
}

/// Dämmschicht des WDVS im Plan (außen an den Außenwänden).
class WdvsPainter extends CustomPainter {
  WdvsPainter({required this.waende, required this.seiten, required this.dicke, required this.massstab, required this.verschiebung});
  final List<Wand> waende;
  final Map<String, double> seiten;
  final int dicke;
  final double massstab;
  final Offset verschiebung;

  @override
  void paint(Canvas canvas, Size size) {
    final f = Paint()..color = const Color(0x66F59F00);
    final r = Paint()
      ..color = const Color(0xFFE67700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    Offset s(double x, double y) => Offset(x, y) * massstab + verschiebung;
    for (final w in waende) {
      final seite = seiten[w.id];
      if (seite == null || w.laenge < 1) continue;
      final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge;
      final nx = uy * seite, ny = -ux * seite; // links der Richtung = (uy, -ux) auf dem Bildschirm
      final a = w.dicke / 2, b = w.dicke / 2 + dicke;
      final ext = dicke.toDouble();
      final p = Path()
        ..addPolygon([
          s(w.x1 - ux * ext + nx * a, w.y1 - uy * ext + ny * a),
          s(w.x2 + ux * ext + nx * a, w.y2 + uy * ext + ny * a),
          s(w.x2 + ux * ext + nx * b, w.y2 + uy * ext + ny * b),
          s(w.x1 - ux * ext + nx * b, w.y1 - uy * ext + ny * b),
        ], true);
      canvas.drawPath(p, f);
      canvas.drawPath(p, r);
    }
  }

  @override
  bool shouldRepaint(WdvsPainter o) => true;
}

String _z(double v, [int n = 1]) => v.toStringAsFixed(n).replaceAll('.', ',');

/// WDVS-, Fassaden- und Balkonplanung für das aktuelle Geschoss.
Future<void> fassadeDialog(BuildContext context, AppState s) => showDialog<void>(context: context, builder: (_) => _FassadeDialog(state: s));

class _FassadeDialog extends StatefulWidget {
  const _FassadeDialog({required this.state});
  final AppState state;
  @override
  State<_FassadeDialog> createState() => _FassadeDialogState();
}

class _FassadeDialogState extends State<_FassadeDialog> {
  AppState get _s => widget.state;

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final gid = _s.geschossId!;
    final g = store.geschoss(gid)!;
    final v = WdvsVorgaben.ausJson(store.einstellung<Map>('wdvs'));
    void setzen(Map<String, Object?> w) {
      store.einstellungSetzen('wdvs', {...v.toJson(), ...w});
      _s.geaendert();
      setState(() {});
    }

    final waende = store.waende(gid);
    final raeume = store.raeume(gid);
    final seiten = aussenSeiten(waende, raeume);
    final oeff = store.oeffnungen(gid);
    final hoehe = (g.hoehen.rohdecke - g.hoehen.rfb + 200).toDouble();
    final fassaden = <Fassadenseite>[
      for (final w in waende)
        if (seiten.containsKey(w.id))
          (
            name: w.id,
            laenge: w.laenge + w.dicke,
            hoehe: hoehe,
            oeffnungen: [
              for (final o in oeff)
                if (o.wandId == w.id && o.art != OeffnungsArt.nische) (b: o.breite.toDouble(), h: o.hoehe.toDouble(), tuer: o.art != OeffnungsArt.fenster),
            ],
          ),
    ];
    final e = wdvsBerechnen(fassaden, v, ecken: math.max(4, fassaden.length));
    // U-Werte vorher/nachher je Außenwandtyp
    final mat = {for (final m in store.materialien()) m.id: m};
    double lam(String id) => mat[id] == null ? 0.8 : lambdaVon(mat[id]!);
    final uZeilen = <(String, double, double)>[];
    for (final t in {for (final w in waende) if (seiten.containsKey(w.id)) w.wandtypId}) {
      final typ = t == null ? null : store.wandtyp(t);
      final u = typ == null || typ.schichten.isEmpty ? 1.4 : 1 / (0.17 + typ.schichten.fold<double>(0, (a, x) => a + x.dicke / 1000 / lam(x.materialId)));
      uZeilen.add((typ?.name ?? 'Außenwand ohne Wandtyp (Richtwert)', u, uMitWdvs(u, v)));
    }
    // Anbauteile außen und Durchdringungen
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final anbau = <String>[];
    final durch = <String>[];
    for (final o in store.objekte(gid)) {
      final k = typen[o.typId]?.kuerzel;
      if (o.punkte.length == 1) {
        final q = o.punkte.first;
        for (final w in waende) {
          final sd = seiten[w.id];
          if (sd == null || w.laenge < 1) continue;
          final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge;
          final t = (q.x - w.x1) * ux + (q.y - w.y1) * uy;
          if (t < 0 || t > w.laenge) continue;
          final quer = ((q.x - w.x1) * uy - (q.y - w.y1) * ux) * sd; // >0 außen
          if (k == 'WD' && quer.abs() <= w.dicke / 2 + 50) durch.add('${o.kennung} Wanddurchbruch');
          if (k != 'WD' && quer > w.dicke / 2 - 30 && quer < w.dicke / 2 + v.dicke + 400) anbau.add('${o.kennung} (${typen[o.typId]?.name}): ${montageteil(typen[o.typId]?.name ?? '')}');
        }
      } else if (o.punkte.length >= 2 && typen[o.typId]?.geometrie == Geometrieart.linie) {
        for (final w in waende.where((w) => seiten.containsKey(w.id))) {
          for (var i = 0; i + 1 < o.punkte.length; i++) {
            if (_schneiden(o.punkte[i], o.punkte[i + 1], Punkt(w.x1.toDouble(), w.y1.toDouble()), Punkt(w.x2.toDouble(), w.y2.toDouble()))) {
              durch.add('${o.kennung} (${typen[o.typId]?.name}) durch die Außenwand – Manschette/Durchführung');
            }
          }
        }
      }
    }
    final balkone = [for (final r in raeume) if (r.art != RaumArt.raum && r.umriss != null) r];

    return AlertDialog(
      title: Text('WDVS, Fassade und Balkon · ${g.kuerzel}'),
      content: SizedBox(
        width: 820,
        height: 600,
        child: ListView(children: [
          Wrap(spacing: 10, runSpacing: 8, children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: v.daemmstoff,
                decoration: const InputDecoration(labelText: 'Dämmstoff', isDense: true),
                items: [for (final d in wdvsDaemmstoffe) DropdownMenuItem(value: d, child: Text(d))],
                onChanged: (d) => setzen({'daemmstoff': d}),
              ),
            ),
            for (final (k, l, w) in [
              ('dicke', 'Dämmdicke mm', v.dicke),
              ('platten_b', 'Platte Breite', v.plattenB),
              ('platten_h', 'Platte Höhe', v.plattenH),
              ('sockel', 'Sockelhöhe', v.sockelHoehe),
              ('duebel', 'Dübel/m²', v.duebelProM2.round()),
              ('duebel_rand', 'Dübel/m² Rand', v.duebelRand.round()),
            ])
              SizedBox(
                width: 110,
                child: SpeicherFeld(
                  key: ValueKey('wd-$k-$w'),
                  initialValue: '$w',
                  decoration: InputDecoration(labelText: l, isDense: true),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onFieldSubmitted: (t) => setzen({k: int.tryParse(t) ?? w}),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          if (fassaden.isEmpty) const Text('Keine Außenwände erkannt (Räume im Grundriss nötig).'),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Chip(label: Text('Dämmfläche ${_z(e.flaeche)} m²')),
            Chip(label: Text('${e.platten} Platten ${v.plattenB}×${v.plattenH}')),
            Chip(label: Text('${e.duebel} Dübel')),
            Chip(label: Text('Sockel ${_z(e.sockelM2)} m², Sockelschiene ${_z(e.sockelschiene)} m')),
            Chip(label: Text('Laibungen ${_z(e.laibungM2)} m²')),
            Chip(label: Text('Kantenprofil ${_z(e.kantenprofil)} m')),
            Chip(label: Text('Anputzleiste ${_z(e.anputzleiste)} m')),
            Chip(label: Text('Tropfkante ${_z(e.tropfkante)} m')),
            Chip(label: Text('Armierungsgewebe ${_z(e.armierung)} m²')),
          ]),
          const SizedBox(height: 8),
          const Text('U-Wert der Außenwände', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final (n, a, b) in uZeilen)
            Text('$n: ${_z(a, 2)} → ${_z(b, 2)} W/(m²K) ${b <= GegBauteil.aussenwand.uMax ? '✓ GEG' : '– GEG ${_z(GegBauteil.aussenwand.uMax, 2)} nicht erreicht'}'),
          const SizedBox(height: 8),
          Text('Montageblöcke für Anbauteile (${anbau.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (anbau.isEmpty) const Text('Keine Anbauteile an den Außenwänden im Plan (Leuchten, Kameras, Steckdosen außen …).', style: TextStyle(fontSize: 12)),
          for (final a in anbau) Text('• $a', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Text('Durchdringungen (${durch.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final d in durch) Text('• $d', style: const TextStyle(fontSize: 12)),
          const Text('Durchdringungen vor dem Dämmen setzen und luftdicht/schlagregendicht einbinden (Manschette, Kompriband).', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          const Divider(height: 24),
          Text('Balkone und Terrassen (${balkone.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final b in balkone) ...[
            Text('${b.name} · ${_z(polygonFlaeche(b.umriss!).abs() / 1e6)} m²', style: const TextStyle(fontWeight: FontWeight.w500)),
            for (final h in balkonHinweise(flaecheM2: polygonFlaeche(b.umriss!).abs() / 1e6, auskragend: b.art.name == 'balkon'))
              Text('• $h', style: const TextStyle(fontSize: 12)),
          ],
          if (balkone.isEmpty) const Text('Keine Balkone/Terrassen (Bodenplatte anlegen) in diesem Geschoss.', style: TextStyle(fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            final d = _s.settings.darstellung;
            d['wdvs_zeigen'] = d['wdvs_zeigen'] != true;
            _s.settings.speichern();
            _s.geaendert();
            setState(() {});
          },
          icon: const Icon(Icons.layers_outlined, size: 18),
          label: Text(_s.settings.darstellung['wdvs_zeigen'] == true ? 'WDVS im Plan ausblenden' : 'WDVS im Plan zeigen'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
      ],
    );
  }
}

bool _schneiden(Punkt a, Punkt b, Punkt c, Punkt d) {
  double k(Punkt p, Punkt q, Punkt r) => (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
  final d1 = k(c, d, a), d2 = k(c, d, b), d3 = k(a, b, c), d4 = k(a, b, d);
  return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0);
}
