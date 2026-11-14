import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/bad.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// Abdichtung aller Nassräume eines Geschosses (DIN 18534, Planungshilfe).
/// Nassräume werden am Namen oder an Dusche/Wanne erkannt; je Raum lässt sich
/// das umschalten (`raum.eigenschaften.nassraum`).
Future<void> badDialogZeigen(BuildContext context, AppState s, {String? raumId}) async {
  final store = s.store!;
  final gid = s.geschossId;
  if (gid == null) return;
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      final g = store.geschoss(gid);
      final typen = {for (final t in store.objekttypen()) t.id: t};
      final objekte = store.objekte(gid);
      final oeffnungen = store.oeffnungen(gid);
      final waende = {for (final w in store.waende(gid)) w.id: w};
      final raeume = [for (final r in store.raeume(gid)) if (r.umriss != null && r.art == RaumArt.raum) r];
      String z(double v) => v.toStringAsFixed(v >= 10 ? 1 : 2).replaceAll('.', ',');

      List<BadFlaeche> flaechenIn(Raum r) => [
            for (final o in objekte)
              if ((typen[o.typId]?.kuerzel == 'DU' || typen[o.typId]?.kuerzel == 'WA') && o.punkte.length >= 3 && _imRaum(o, r))
                BadFlaeche(
                  umriss: o.punkte,
                  wanne: typen[o.typId]?.kuerzel == 'WA',
                  bodengleich: o.eigenschaften['bodengleich'] != false,
                  brause: o.eigenschaften['brause'] != false,
                  hoehe: (o.eigenschaften['abdichtung_hoehe'] as num?)?.toInt() ?? 2000,
                ),
          ];

      final karten = <Widget>[];
      for (final r in raeume) {
        final fl = flaechenIn(r);
        final nass = istNassraum(r.name, r.eigenschaften, hatDuscheOderWanne: fl.isNotEmpty);
        if (!nass && raumId != r.id && r.eigenschaften['nassraum'] == null && fl.isEmpty) continue;
        final rh = g == null ? 2500 : ((r.rohdecke ?? g.hoehen.rohdecke) - (r.ffb ?? g.hoehen.ffb));
        // Nischen in Wänden dieses Raums (Mitte der Nische nahe am Raumumriss)
        final nischen = <BadNische>[];
        for (final o in oeffnungen.where((o) => o.art == OeffnungsArt.nische)) {
          final w = waende[o.wandId];
          if (w == null || w.laenge < 1) continue;
          final t = (o.abstand + o.breite / 2) / w.laenge;
          final p = Punkt(w.x1 + (w.x2 - w.x1) * t, w.y1 + (w.y2 - w.y1) * t);
          if (!_nahAmUmriss(p, r.umriss!, w.dicke / 2 + 60)) continue;
          final spritz = fl.any((f) => f.umriss.any((q) => (q.x - p.x).abs() + (q.y - p.y).abs() < 2500)) && o.bruestung < 2000;
          nischen.add((breite: o.breite.toDouble(), hoehe: o.hoehe.toDouble(), tiefe: ((o.eigenschaften['tiefe'] as num?) ?? 100).toDouble(), imSpritzbereich: spritz));
        }
        final e = nass
            ? abdichtungBerechnen(umriss: r.umriss!, flaechen: fl, nischen: nischen, raumhoehe: rh, bodenablauf: r.eigenschaften['bodenablauf'] == true)
            : null;
        final badObj = [
          for (final o in objekte)
            if (badObjektMasse.containsKey(typen[o.typId]?.kuerzel) && _imRaum(o, r))
              (kuerzel: typen[o.typId]!.kuerzel, kennung: o.kennung, mitte: o.punkte.first),
        ];
        final abst = badAbstaende(badObj);
        karten.add(Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                const Text('Nassraum', style: TextStyle(fontSize: 12)),
                Switch(
                  value: nass,
                  onChanged: (v) {
                    store.raumEigenschaftenSetzen(r.id, {...r.eigenschaften, 'nassraum': v});
                    s.geaendert();
                    setD(() {});
                  },
                ),
                if (r.eigenschaften['nassraum'] != null)
                  TextButton(
                    onPressed: () {
                      store.raumEigenschaftenSetzen(r.id, {...r.eigenschaften}..remove('nassraum'));
                      s.geaendert();
                      setD(() {});
                    },
                    child: const Text('automatisch'),
                  ),
              ]),
              if (e == null)
                const Text('Kein Nassraum – keine Abdichtung nach DIN 18534 nötig.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise))
              else ...[
                Row(children: [
                  Checkbox(
                    value: r.eigenschaften['bodenablauf'] == true,
                    onChanged: (v) {
                      store.raumEigenschaftenSetzen(r.id, {...r.eigenschaften, 'bodenablauf': v == true});
                      s.geaendert();
                      setD(() {});
                    },
                  ),
                  const Text('Bodenablauf im Raum (auch ohne bodengleiche Dusche)', style: TextStyle(fontSize: 12)),
                ]),
                Table(columnWidths: const {0: FlexColumnWidth(4), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)}, children: [
                  for (final f in e.flaechen)
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(f.bezeichnung)),
                      Text(f.klasse, style: TextStyle(fontWeight: FontWeight.w600, color: f.klasse == 'W1-I' ? BsFarben.akzentDunkel : null)),
                      Text('${z(f.m2)} m²', textAlign: TextAlign.right),
                    ]),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  Chip(label: Text('Dichtband ${z(e.dichtband)} m')),
                  Chip(label: Text('${e.innenecken} Innenecken')),
                  if (e.wandmanschetten > 0) Chip(label: Text('${e.wandmanschetten} Wandmanschetten')),
                  if (e.bodenmanschetten > 0) Chip(label: Text('${e.bodenmanschetten} Bodenmanschette/Dichtflansch')),
                  Chip(label: Text('Flüssigabdichtung ca. ${e.verbrauchKg().ceil()} kg (2 Lagen)')),
                ]),
                for (final hw in [...e.hinweise, ...abst])
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.info_outline, size: 15, color: BsFarben.textLeise),
                      const SizedBox(width: 6),
                      Expanded(child: Text(hw, style: const TextStyle(fontSize: 12))),
                    ]),
                  ),
              ],
            ]),
          ),
        ));
      }
      return AlertDialog(
        title: const Text('Bad und Abdichtung (DIN 18534)'),
        content: SizedBox(
          width: 720,
          height: 560,
          child: karten.isEmpty
              ? const Center(
                  child: Text('Kein Nassraum in diesem Geschoss.\nRäume mit „Bad“ oder „Dusche“ im Namen oder mit Dusche/Wanne werden erkannt.',
                      textAlign: TextAlign.center))
              : ListView(children: [
                  const Text(
                      'Dusche und Wanne setzt du in der Installation (Gewerk Sanitär) als Fläche. W1-I: Boden mit Ablauf, Wände in Dusche und über Wanne mit Brause '
                      '(bis 2 m, 20 cm seitlich darüber hinaus). W0-I: übrige Flächen, Sockelstreifen empfohlen. Planungshilfe, keine Fachplanung.',
                      style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                  const SizedBox(height: 8),
                  ...karten,
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
      );
    }),
  );
}

bool _imRaum(Objekt o, Raum r) {
  if (o.raumId != null) return o.raumId == r.id;
  if (o.punkte.isEmpty) return false;
  var sx = 0.0, sy = 0.0;
  for (final p in o.punkte) {
    sx += p.x;
    sy += p.y;
  }
  return punktInPolygon(Punkt(sx / o.punkte.length, sy / o.punkte.length), r.umriss!);
}

bool _nahAmUmriss(Punkt p, List<Punkt> u, double max) {
  for (var i = 0; i < u.length; i++) {
    final a = u[i], b = u[(i + 1) % u.length];
    final dx = b.x - a.x, dy = b.y - a.y;
    final l2 = dx * dx + dy * dy;
    if (l2 == 0) continue;
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
    final qx = a.x + dx * t - p.x, qy = a.y + dy * t - p.y;
    if (qx * qx + qy * qy <= max * max) return true;
  }
  return false;
}
