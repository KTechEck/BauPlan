import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../core/oberflaechen.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Lichte Höhe eines Raums (mm), Vorgabe 2500.
int lichteHoeheVon(Raum r, Geschoss? g) {
  if (g == null) return 2500;
  final h = r.hoehen(g);
  return math.max(1000, (r.ukDecke ?? h.rohdecke) - h.ffb);
}

/// Oberflächen beschichten: je Raum Wände, Boden und Decke mit Schichtsystem und Bedarf.
class OberflaechenAnsicht extends StatefulWidget {
  const OberflaechenAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<OberflaechenAnsicht> createState() => _OberflaechenAnsichtState();
}

class _OberflaechenAnsichtState extends State<OberflaechenAnsicht> {
  String? _raumId;
  AppState get _s => widget.state;

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final gid = _s.geschossId;
    if (gid == null) return const Center(child: Text('Kein Geschoss gewählt.'));
    final raeume = [for (final r in store.raeume(gid)) if (r.umriss != null) r];
    final r = raeume.where((x) => x.id == _raumId).firstOrNull ?? raeume.firstOrNull;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 240,
        child: Material(
          color: Colors.white,
          child: ListView(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Räume', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final x in raeume)
              ListTile(
                dense: true,
                selected: x.id == r?.id,
                selectedTileColor: BsFarben.akzentHell,
                title: Text(x.name),
                subtitle: Text([
                  for (final a in Flaechenart.values)
                    if (beschichtungen(x.eigenschaften, a).isNotEmpty) a.label,
                ].join(', ')),
                onTap: () => setState(() => _raumId = x.id),
              ),
          ]),
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: r == null
            ? const Center(child: Text('Keine verorteten Räume in diesem Geschoss.'))
            : ListView(padding: const EdgeInsets.all(20), children: [
                Text('${r.name} – Oberflächen', style: Theme.of(context).textTheme.titleLarge),
                const Text('Schichtsysteme je Fläche. Der Bedarf läuft in die Besorgungsliste, wenn ein Material aus der Bibliothek gewählt ist.',
                    style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                const SizedBox(height: 12),
                for (final a in Flaechenart.values) _flaeche(r, a),
              ]),
      ),
    ]);
  }

  double _flaecheM2(Raum r, Flaechenart a) {
    final store = _s.store!;
    final g = store.geschoss(r.geschossId);
    final h = lichteHoeheVon(r, g);
    // Öffnungen in den Wänden des Raums grob abziehen (Fenster/Türen, deren Wand am Raum liegt)
    var oeff = 0.0;
    if (a == Flaechenart.waende && r.umriss != null) {
      final waende = {for (final w in store.waende(r.geschossId)) w.id: w};
      for (final o in store.oeffnungen(r.geschossId)) {
        final w = waende[o.wandId];
        if (w == null) continue;
        final t = (o.abstand + o.breite / 2) / math.max(1, math.sqrt(math.pow(w.x2 - w.x1, 2) + math.pow(w.y2 - w.y1, 2)));
        final m = Punkt(w.x1 + (w.x2 - w.x1) * t, w.y1 + (w.y2 - w.y1) * t);
        var nah = double.infinity;
        final u = r.umriss!;
        for (var i = 0; i < u.length; i++) {
          final p = u[i], q = u[(i + 1) % u.length];
          final d = q - p;
          final l2 = d.skalar(d);
          if (l2 < 1) continue;
          final s = ((m - p).skalar(d) / l2).clamp(0.0, 1.0);
          nah = math.min(nah, (p + d * s - m).laenge);
        }
        if (nah <= w.dicke / 2 + 30) oeff += o.breite * o.hoehe;
      }
    }
    return raumFlaeche(a, grundflaecheMm2: r.flaeche ?? 0, umfangMm: r.umfang ?? 0, lichteHoeheMm: h, oeffnungenMm2: oeff);
  }

  void _speichern(Raum r, Flaechenart a, List<Beschichtung> l) {
    _s.store!.raumEigenschaftenSetzen(r.id, beschichtungenSetzen(r.eigenschaften, a, l));
    _s.geaendert();
    setState(() {});
  }

  Widget _flaeche(Raum r, Flaechenart a) {
    final l = beschichtungen(r.eigenschaften, a);
    final m2 = _flaecheM2(r, a);
    final store = _s.store!;
    final materialien = [
      for (final k in const [BauelementKategorie.baustoff, BauelementKategorie.dichtstoff, BauelementKategorie.daemmstoff, BauelementKategorie.kleinmaterial])
        ..._s.bibliothek.auswahl(store, k),
    ];
    String zahl(double v) => v.toStringAsFixed(v < 10 ? 2 : 1).replaceAll('.', ',');
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(a.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 10),
            Text('${zahl(m2)} m²${a == Flaechenart.waende ? ' (ohne Fenster/Türen)' : ''}', style: const TextStyle(color: BsFarben.textLeise)),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: 'Schichtsystem aus Vorlage',
              onSelected: (v) => _speichern(r, a, [...l, ...beschichtungsVorlagen[v]!]),
              itemBuilder: (_) => [for (final k in beschichtungsVorlagen.keys) PopupMenuItem(value: k, child: Text(k))],
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome_outlined, size: 18), SizedBox(width: 4), Text('Vorlage')]),
              ),
            ),
            IconButton(
              tooltip: 'Schicht hinzufügen',
              onPressed: () => _speichern(r, a, [...l, const Beschichtung(text: 'Neue Schicht')]),
              icon: const Icon(Icons.add),
            ),
          ]),
          if (l.isEmpty) const Text('Keine Beschichtung.', style: TextStyle(color: BsFarben.textLeise)),
          for (final (i, b) in l.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                SizedBox(width: 22, child: Text('${i + 1}.', style: const TextStyle(color: BsFarben.textLeise))),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('ob-${r.id}-${a.name}-$i-${b.material}'),
                    isExpanded: true,
                    initialValue: materialien.any((x) => x.id == b.material) ? b.material : null,
                    decoration: InputDecoration(isDense: true, labelText: b.text.isEmpty ? 'Material' : b.text),
                    items: [
                      DropdownMenuItem(value: null, child: Text(b.text.isEmpty ? '– frei –' : '${b.text} (ohne Bibliothek)')),
                      for (final x in materialien) DropdownMenuItem(value: x.id, child: Text(x.anzeige, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (id) {
                      final x = materialien.where((e) => e.id == id).firstOrNull;
                      final v = x?.zahl('verbrauch_m2')?.toDouble();
                      final neu = [...l];
                      neu[i] = b.mit(material: id, text: x?.name, verbrauch: v, einheit: x?.daten['einheit'] as String?);
                      _speichern(r, a, neu);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _zahlFeld('ver-${r.id}-${a.name}-$i-${b.verbrauch}', 'je m² und Lage', b.verbrauch, b.einheit, (v) {
                  final neu = [...l];
                  neu[i] = b.mit(verbrauch: v);
                  _speichern(r, a, neu);
                }),
                const SizedBox(width: 8),
                _zahlFeld('lag-${r.id}-${a.name}-$i-${b.lagen}', 'Lagen', b.lagen.toDouble(), '', (v) {
                  final neu = [...l];
                  neu[i] = b.mit(lagen: math.max(1, v.round()));
                  _speichern(r, a, neu);
                }, breite: 70),
                const SizedBox(width: 8),
                _zahlFeld('ant-${r.id}-${a.name}-$i-${b.anteil}', 'Anteil', b.anteil * 100, '%', (v) {
                  final neu = [...l];
                  neu[i] = b.mit(anteil: (v / 100).clamp(0.01, 1.0).toDouble());
                  _speichern(r, a, neu);
                }, breite: 80),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: Text('${zahl(b.bedarf(m2))} ${b.einheit}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Schicht entfernen',
                  onPressed: () => _speichern(r, a, [...l]..removeAt(i)),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _zahlFeld(String key, String label, double wert, String einheit, void Function(double) setzen, {double breite = 120}) => SizedBox(
        width: breite,
        child: SpeicherFeld(
          key: ValueKey(key),
          initialValue: (wert == wert.roundToDouble() ? wert.toInt().toString() : wert.toString()).replaceAll('.', ','),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          decoration: InputDecoration(isDense: true, labelText: label, suffixText: einheit),
          onFieldSubmitted: (v) {
            final z = double.tryParse(v.replaceAll(',', '.'));
            if (z != null) setzen(z);
          },
        ),
      );
}
