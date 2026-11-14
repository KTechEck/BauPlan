import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/gebaeude.dart';
import '../../core/heizlast.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import 'bauphysik_page.dart' show lambdaVon, aufbauten;

const _gruen = Color(0xFF2F9E44);
const _rot = Color(0xFFB91C1C);
String _z(double v, [int n = 2]) => v.toStringAsFixed(n).replaceAll('.', ',');

/// Rohdichte eines Baustoffs: hinterlegt oder Richtwert nach Name.
double rhoVon(Baustoff m) {
  final r = (m.eigenschaften['rho'] as num?)?.toDouble();
  if (r != null) return r;
  final n = m.name.toLowerCase();
  if (n.contains('stahlbeton') || n.contains('beton')) return n.contains('poren') ? 500 : 2400;
  if (n.contains('kalksand') || RegExp(r'\bks\b').hasMatch(n)) return 1800;
  if (n.contains('ziegel')) return n.contains('voll') ? 1800 : 900;
  if (n.contains('poren') || n.contains('ytong')) return 500;
  if (n.contains('gips')) return 850;
  if (n.contains('putz')) return 1400;
  if (n.contains('estrich')) return 2000;
  if (RegExp(r'dämm|eps|xps|wolle|holzfaser|pur|pir').hasMatch(n)) return 60;
  if (n.contains('holz') || n.contains('osb')) return 550;
  return 1000;
}

/// Raum-Hülle für Seitenprüfungen (Name, Umriss).
List<HlRaum> _raeume(AppState s, Geschoss g) => [
      for (final r in s.store!.raeume(g.id))
        if (r.umriss != null && r.umriss!.length >= 3 && r.art == RaumArt.raum) HlRaum(id: r.id, name: r.name, umriss: r.umriss!, hoehe: 2500),
    ];

Geschoss? _geschoss(AppState s) {
  final gs = [for (final geb in s.store!.gebaeude()) ...s.store!.geschosse(geb.id)];
  return gs.where((x) => x.id == s.geschossId).firstOrNull ?? gs.firstOrNull;
}

// ------------------------------------------------------------------- GEG

/// Dämmung nach GEG: U-Werte der Außenbauteile gegen die Höchstwerte bei Änderung.
class GegAnsicht extends StatelessWidget {
  const GegAnsicht({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final store = state.store!;
    final g = _geschoss(state);
    if (g == null) return const Center(child: Text('Noch kein Geschoss.'));
    final mat = {for (final m in store.materialien()) m.id: m};
    double lam(String id) => mat[id] == null ? 0.8 : lambdaVon(mat[id]!);
    final raeume = _raeume(state, g);
    final zeilen = <(String, GegBauteil, double, String)>[]; // Name, Art, U, Herkunft
    // Außenwände je Wandtyp
    final gesehen = <String>{};
    for (final w in store.waende(g.id)) {
      if (w.teilhoch) continue;
      final hw = HlWand(id: w.id, a: Punkt(w.x1.toDouble(), w.y1.toDouble()), b: Punkt(w.x2.toDouble(), w.y2.toDouble()), dicke: w.dicke, u: 1);
      final aussen = wandSeiten(hw, raeume, schritt: 250).any((s) => (s.$3 == null) != (s.$4 == null));
      if (!aussen) continue;
      final typ = w.wandtypId == null ? null : store.wandtyp(w.wandtypId!);
      final key = typ?.id ?? 'frei-${w.dicke}';
      if (!gesehen.add(key)) continue;
      final u = typ == null || typ.schichten.isEmpty
          ? (w.dicke >= 300 ? 1.0 : 1.4)
          : 1 / (0.13 + 0.04 + typ.schichten.fold<double>(0, (s, x) => s + x.dicke / 1000 / lam(x.materialId)));
      zeilen.add((typ?.name ?? 'Wand ohne Wandtyp (${w.dicke} mm, Richtwert)', GegBauteil.aussenwand, u, 'Wandtyp'));
    }
    // Boden-/Deckenaufbauten, die an Erdreich, außen oder unbeheizt grenzen
    for (final a in aufbauten(store)) {
      if (a.art == Gegen.beheizt) continue;
      final art = switch (a.art) {
        Gegen.erdreich => GegBauteil.bodenErdreich,
        Gegen.unbeheizt => GegBauteil.kellerdecke,
        _ => a.name.toLowerCase().contains('flach') ? GegBauteil.flachdach : GegBauteil.oberstGeschossdecke,
      };
      zeilen.add((a.name, art, a.uWert(lam, alsDecke: art != GegBauteil.bodenErdreich), 'Aufbau'));
    }
    // Fenster und Türen aus der Bibliothek
    final fenster = <String, (GegBauteil, double)>{};
    for (final o in store.oeffnungen(g.id)) {
      if (o.art == OeffnungsArt.durchbruch || o.art == OeffnungsArt.nische) continue;
      final be = state.bibliothek.fuerProjekt(store, o.eigenschaften['bauelement'] as String?);
      final u = be?.zahl(o.art.verglast ? 'uw' : 'ud')?.toDouble();
      if (u == null) continue;
      fenster[be!.anzeige] = (o.art.verglast ? GegBauteil.fenster : GegBauteil.tuer, u);
    }
    for (final e in fenster.entries) {
      zeilen.add((e.key, e.value.$1, e.value.$2, 'Bibliothek'));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${g.kuerzel} · GEG Anlage 7 – Höchstwerte bei Erneuerung oder Ersatz von Außenbauteilen. '
          'Fehlende Dämmstärke mit λ = 0,035 W/(mK). Richtwerte zur Planung, kein Energieausweis.',
          style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      if (zeilen.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Text('Keine Außenbauteile erkannt (Wandtypen, Aufbauten, Fenster mit U-Wert).')),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: const [
            DataColumn(label: Text('Bauteil')),
            DataColumn(label: Text('Art')),
            DataColumn(label: Text('U'), numeric: true),
            DataColumn(label: Text('GEG max'), numeric: true),
            DataColumn(label: Text('Ergebnis')),
          ], rows: [
            for (final (name, art, u, her) in zeilen)
              DataRow(cells: [
                DataCell(Text('$name\n$her', style: const TextStyle(fontSize: 12))),
                DataCell(Text(art.label)),
                DataCell(Text(_z(u))),
                DataCell(Text(_z(art.uMax))),
                DataCell(u <= art.uMax
                    ? const Text('erfüllt', style: TextStyle(color: _gruen, fontWeight: FontWeight.w600))
                    : Text(
                        art == GegBauteil.fenster || art == GegBauteil.tuer || art == GegBauteil.dachfenster
                            ? 'zu hoch – besseres Bauteil'
                            : 'ca. ${gegZusatzDaemmung(u, art).ceil()} mm Dämmung fehlen',
                        style: const TextStyle(color: _rot, fontWeight: FontWeight.w600))),
              ]),
          ]),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ Schall

/// Schallschutz-Richtwerte zwischen Räumen (Massekurve, Empfehlung EFH).
class SchallAnsicht extends StatelessWidget {
  const SchallAnsicht({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final store = state.store!;
    final g = _geschoss(state);
    if (g == null) return const Center(child: Text('Noch kein Geschoss.'));
    final mat = {for (final m in store.materialien()) m.id: m};
    final raeume = _raeume(state, g);
    final name = {for (final r in raeume) r.id: r.name};
    final zeilen = <(String, String, String, double, int?)>[];
    for (final w in store.waende(g.id)) {
      if (w.teilhoch) continue;
      final hw = HlWand(id: w.id, a: Punkt(w.x1.toDouble(), w.y1.toDouble()), b: Punkt(w.x2.toDouble(), w.y2.toDouble()), dicke: w.dicke, u: 1);
      final typ = w.wandtypId == null ? null : store.wandtyp(w.wandtypId!);
      final masse = typ == null || typ.schichten.isEmpty
          ? w.dicke / 1000 * 1400
          : flaechenMasse([for (final x in typ.schichten) (x.dicke, mat[x.materialId] == null ? 1000.0 : rhoVon(mat[x.materialId]!))]);
      for (final (_, _, a, b) in wandSeiten(hw, raeume, schritt: 250)) {
        if (a == null || b == null || a == b) continue;
        final paar = ([name[a]!, name[b]!]..sort()).join(' | ');
        if (zeilen.any((z) => z.$1 == paar && z.$2 == (typ?.name ?? '${w.dicke} mm'))) continue;
        zeilen.add((paar, typ?.name ?? 'Wand ${w.dicke} mm (ohne Wandtyp)', '${masse.round()} kg/m²', schalldaemmmass(masse), schallEmpfehlung(name[a]!, name[b]!)));
      }
    }
    zeilen.sort((x, y) => (y.$5 ?? 0).compareTo(x.$5 ?? 0));
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
          'Innenwände zwischen Räumen: R\'w aus der flächenbezogenen Masse (Massekurve, einschalig massiv, Richtwert). Empfehlung für ein Einfamilienhaus: '
          'Schlafräume zu Bad/Küche/Technik 47 dB, zwischen Schlafräumen 40 dB. Leichtbauwände (Ständerwerk mit Dämmung) erreichen oft mehr als die Masse sagt – '
          'Herstellerwert nehmen. Abwasserleitungen nicht in Wänden zu Schlafräumen führen.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: const [
            DataColumn(label: Text('Räume')),
            DataColumn(label: Text('Wand')),
            DataColumn(label: Text('m\''), numeric: true),
            DataColumn(label: Text('R\'w ca.'), numeric: true),
            DataColumn(label: Text('Empfehlung')),
          ], rows: [
            for (final (paar, wand, m, rw, soll) in zeilen)
              DataRow(cells: [
                DataCell(Text(paar)),
                DataCell(Text(wand)),
                DataCell(Text(m)),
                DataCell(Text('${rw.round()} dB')),
                DataCell(soll == null
                    ? const Text('–')
                    : Text('$soll dB ${rw >= soll ? '✓' : '– zu wenig'}', style: TextStyle(color: rw >= soll ? _gruen : _rot, fontWeight: FontWeight.w600))),
              ]),
          ]),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------ Sonnenschutz

/// Sommerlicher Wärmeschutz: Sonneneintragskennwert je Raum (vereinfacht).
class SonnenschutzAnsicht extends StatefulWidget {
  const SonnenschutzAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<SonnenschutzAnsicht> createState() => _SonnenschutzAnsichtState();
}

class _SonnenschutzAnsichtState extends State<SonnenschutzAnsicht> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final store = s.store!;
    final g = _geschoss(s);
    if (g == null) return const Center(child: Text('Noch kein Geschoss.'));
    final nord = (store.einstellung<num>('norden_grad') ?? 0).toDouble();
    final raeume = _raeume(s, g);
    final waende = {for (final w in store.waende(g.id)) w.id: w};
    final jeRaum = <String, List<({double flaeche, double g, double fc, String richtung})>>{};
    final details = <String, List<String>>{};
    for (final o in store.oeffnungen(g.id)) {
      if (!o.art.verglast) continue;
      final w = waende[o.wandId];
      if (w == null || w.laenge < 1) continue;
      final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge;
      final t = o.abstand + o.breite / 2;
      final mx = w.x1 + ux * t, my = w.y1 + uy * t;
      final d = w.dicke / 2 + 60;
      String? raumAn(double x, double y) => raeume.where((r) => punktInPolygon(Punkt(x, y), r.umriss)).firstOrNull?.id;
      final links = raumAn(mx - uy * d, my + ux * d), rechts = raumAn(mx + uy * d, my - ux * d);
      final innen = links ?? rechts;
      if (innen == null || (links != null && rechts != null)) continue;
      // Außennormale zeigt zur raumlosen Seite
      final nx = links == null ? -uy : uy, ny = links == null ? ux : -ux;
      final richtung = himmelsrichtung(nx, ny, nordGrad: nord);
      final be = s.bibliothek.fuerProjekt(store, o.eigenschaften['bauelement'] as String?);
      final ss = s.bibliothek.fuerProjekt(store, o.eigenschaften['sonnenschutz'] as String?);
      final gw = be?.zahl('g')?.toDouble() ?? 0.6;
      final fc = (ss?.zahl('fc')?.toDouble()) ?? fcSonnenschutz(ss == null ? null : '${ss.name} ${ss.daten['art'] ?? ''}');
      final a = o.breite * o.hoehe / 1e6 * 0.7; // Glasanteil ca. 70 %
      (jeRaum[innen] ??= []).add((flaeche: a, g: gw, fc: fc, richtung: richtung));
      (details[innen] ??= []).add('$richtung ${_z(a, 1)} m² Glas · g ${_z(gw)} · Fc ${_z(fc)}${ss == null ? ' (ohne Sonnenschutz)' : ''}');
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Expanded(
          child: Text(
              'Sonneneintragskennwert S = Σ(Glasfläche · g · Fc) / Grundfläche, ohne Nordfenster (DIN 4108-2 vereinfacht). '
              'Über etwa 0,07–0,10 wird es im Sommer warm – außenliegender Sonnenschutz (Raffstore Fc 0,25, Rollladen 0,30) hilft am meisten.',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 180,
          child: SpeicherFeld(
            key: ValueKey('nord-$nord'),
            initialValue: '${nord.round()}',
            decoration: const InputDecoration(labelText: 'Norden im Plan', suffixText: '° (0 = oben)', isDense: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))],
            onFieldSubmitted: (t) {
              store.einstellungSetzen('norden_grad', int.tryParse(t) ?? 0);
              s.geaendert();
              setState(() {});
            },
          ),
        ),
      ]),
      const SizedBox(height: 8),
      for (final r in raeume)
        if (jeRaum[r.id] != null)
          () {
            final sw = sonneneintrag(jeRaum[r.id]!, r.flaeche);
            final ok = sw <= 0.08;
            return Card(
              child: ListTile(
                leading: Icon(ok ? Icons.check_circle : Icons.wb_sunny_outlined, color: ok ? _gruen : const Color(0xFFE67700)),
                title: Text('${r.name} · S = ${_z(sw, 3)}'),
                subtitle: Text(details[r.id]!.join('\n'), style: const TextStyle(fontSize: 12)),
                trailing: Text(ok ? 'unkritisch' : 'Sonnenschutz prüfen', style: TextStyle(color: ok ? _gruen : const Color(0xFFE67700))),
              ),
            );
          }(),
      if (jeRaum.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Keine Fenster in Außenwänden erkannt.')),
    ]);
  }
}
