import '../data/models.dart';
import '../data/project_store.dart';
import 'auslegung_projekt.dart';
import 'leitung_wand.dart';
import 'leitungsnetz.dart';

/// Ein Kabelweg: zusammenhängende Leitungsstücke (auch über Geschosse, verbunden
/// über Fortsetzungen oder eine gemeinsame Steigleitung SR), mit Länge, Start
/// und Ziel. Daraus entsteht die Kabelzugliste.
class Kabelweg {
  Kabelweg({required this.nr, required this.leitungen, required this.kabel, required this.von, required this.nach, required this.geschosse, required this.meter, required this.senkrecht, this.stromkreis, this.geschaetzt = false});
  final String nr;
  final List<String> leitungen; // Objekt-IDs (zum Hervorheben)
  final String kabel, von, nach;
  final List<String> geschosse;
  final double meter; // Gesamtlänge inkl. Senkrechte und Reserve
  final double senkrecht; // davon zwischen Geschossen
  final String? stromkreis;
  final bool geschaetzt;
}

/// Kürzel von Leitungen, die als Kabel zählen (Elektro, Netzwerk, Bus, Signal, Außen).
const kabelKuerzel = {'LT', 'BL', 'SL', 'NK', 'EK', 'AK', 'LB'};

/// Kabelwege des ganzen Projekts plus geschätzte Kabel je Stromkreis ohne
/// gezeichnete Leitung. [name] löst Bibliotheks-IDs in Anzeigenamen auf.
List<Kabelweg> kabelwege(ProjectStore store, {String? Function(String id)? name, double reserveM = 1.0}) {
  final gs = [for (final geb in store.gebaeude()) ...store.geschosse(geb.id)];
  final geschossName = {for (final g in gs) g.id: g.name};
  final sockel = geschossSockel(gs);
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final alle = store.alleObjekte();
  final nachId = {for (final o in alle) o.id: o};
  final raumName = <String, String>{for (final g in gs) for (final r in store.raeume(g.id)) r.id: r.name};
  final leitungen = [
    for (final o in alle)
      if (typen[o.typId]?.geometrie == Geometrieart.linie && o.punkte.length >= 2 && (kabelKuerzel.contains(typen[o.typId]?.kuerzel) || o.eigenschaften['kabel'] != null || (o.eigenschaften['kabel_liste'] as List? ?? const []).isNotEmpty)) o
  ];
  // Union-Find über Fortsetzungen und gemeinsame Steigleitungen
  final eltern = {for (final o in leitungen) o.id: o.id};
  String wurzel(String x) {
    while (eltern[x] != x) {
      x = eltern[x] = eltern[eltern[x]!]!;
    }
    return x;
  }

  void verbinden(String a, String b) {
    if (!eltern.containsKey(a) || !eltern.containsKey(b)) return;
    eltern[wurzel(a)] = wurzel(b);
  }

  final anSteigleitung = <String, List<Objekt>>{};
  for (final o in leitungen) {
    for (final ende in const ['anfang', 'ende']) {
      final b = leitungsBezug(o, ende);
      if (b == null) continue;
      if (b['leitung'] is String) verbinden(o.id, b['leitung'] as String);
      final obj = nachId[b['objekt']];
      if (obj != null && typen[obj.typId]?.kuerzel == 'SR') (anSteigleitung[obj.id] ??= []).add(o);
    }
  }
  final senkrechtJe = <String, double>{};
  for (final l in anSteigleitung.values) {
    for (var i = 1; i < l.length; i++) {
      verbinden(l[0].id, l[i].id);
    }
  }
  final gruppen = <String, List<Objekt>>{};
  for (final o in leitungen) {
    (gruppen[wurzel(o.id)] ??= []).add(o);
  }
  // Senkrechte: je Steigleitung Höhenunterschied der beteiligten Geschosse
  for (final l in anSteigleitung.values) {
    final h = [for (final o in l) sockel[o.geschossId] ?? 0]..sort();
    if (h.length < 2) continue;
    final w = wurzel(l.first.id);
    senkrechtJe[w] = (senkrechtJe[w] ?? 0) + (h.last - h.first) / 1000;
  }
  String ort(Objekt o) => [o.kennung, if (raumName[o.raumId] != null) raumName[o.raumId]!, geschossName[o.geschossId] ?? ''].where((x) => x.isNotEmpty).join(' · ');
  final aus = <Kabelweg>[];
  var nr = 1;
  for (final e in gruppen.entries) {
    final l = e.value;
    final enden = <Objekt>[];
    String? kabel, kreis;
    for (final o in l) {
      kabel ??= o.eigenschaften['kabel'] as String?;
      for (final k in (o.eigenschaften['kabel_liste'] as List? ?? const [])) {
        kabel ??= name?.call('$k') ?? '$k';
      }
      kreis ??= o.eigenschaften['stromkreis'] as String?;
      for (final ende in const ['anfang', 'ende']) {
        final obj = nachId[leitungsBezug(o, ende)?['objekt']];
        if (obj != null && typen[obj.typId]?.kuerzel != 'SR') {
          enden.add(obj);
          kreis ??= obj.eigenschaften['stromkreis'] as String?;
        }
      }
    }
    // Start bevorzugt am Verteiler
    enden.sort((a, b) => (typen[a.typId]?.kuerzel == 'VT' ? 0 : 1).compareTo(typen[b.typId]?.kuerzel == 'VT' ? 0 : 1));
    final senk = senkrechtJe[e.key] ?? 0;
    final waagerecht = l.fold<double>(0, (s, o) => s + o.laenge / 1000);
    aus.add(Kabelweg(
      nr: 'K${nr++}',
      leitungen: [for (final o in l) o.id],
      kabel: kabel ?? typen[l.first.typId]?.name ?? 'Leitung',
      von: enden.isEmpty ? ort(l.first) : ort(enden.first),
      nach: enden.length < 2 ? (enden.isEmpty ? ort(l.last) : '–') : enden.skip(1).map(ort).join(', '),
      geschosse: {for (final o in l) geschossName[o.geschossId] ?? ''}.toList(),
      meter: waagerecht + senk + reserveM,
      senkrecht: senk,
      stromkreis: kreis,
    ));
  }
  // Stromkreise ohne gezeichnete Leitung: geschätzte Länge (inkl. Geschosswechsel)
  final gezeichnet = {for (final k in aus) if (k.stromkreis != null) k.stromkreis!};
  for (final sch in store.schraenke()) {
    for (final k in kreiseAuslegen(store, sch)) {
      if (gezeichnet.contains(k.kreis.id) || k.objekte.isEmpty) continue;
      final ziele = [for (final o in k.objekte) if (typen[o.typId]?.geometrie == Geometrieart.punkt) o];
      aus.add(Kabelweg(
        nr: '${sch.kennzeichen}.${k.kreis.nummer}',
        leitungen: [for (final o in ziele) o.id],
        kabel: k.kreis.leitung.isEmpty ? 'NYM-J ${k.vorschlag.querschnitt.toString().replaceAll('.', ',')} mm²' : k.kreis.leitung,
        von: '${sch.kennzeichen} ${sch.name}',
        nach: {for (final o in ziele) raumName[o.raumId] ?? geschossName[o.geschossId] ?? ''}.where((x) => x.isNotEmpty).join(', '),
        geschosse: {for (final o in ziele) geschossName[o.geschossId] ?? ''}.toList(),
        meter: k.laenge,
        senkrecht: 0,
        stromkreis: k.kreis.id,
        geschaetzt: k.laengeGeschaetzt,
      ));
    }
  }
  return aus;
}

/// Kabelzugliste als CSV (Semikolon, für Excel).
String kabelzuglisteCsv(List<Kabelweg> l) {
  String f(String s) => '"${s.replaceAll('"', '""')}"';
  final b = StringBuffer('Nr;Kabel;von;nach;Geschosse;Länge m;davon senkrecht m;Hinweis\n');
  for (final k in l) {
    b.writeln([f(k.nr), f(k.kabel), f(k.von), f(k.nach), f(k.geschosse.join(', ')), k.meter.toStringAsFixed(1).replaceAll('.', ','), k.senkrecht.toStringAsFixed(1).replaceAll('.', ','), f(k.geschaetzt ? 'Länge geschätzt' : '')].join(';'));
  }
  return b.toString();
}
