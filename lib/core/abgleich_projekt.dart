import '../data/models.dart';
import '../data/project_store.dart';
import 'fbh.dart';
import 'hydraulik.dart';
import 'raumerkennung.dart';
import 'verteiler.dart';

/// Einstellungen des hydraulischen Abgleichs (Projekteinstellung `abgleich`).
AbgleichEinstellung abgleichEinstellung(ProjectStore store) => AbgleichEinstellung.ausJson(store.einstellung<Map>('abgleich'));

/// Heizlast je Raum in W: von der Bauphysik zwischengespeichert
/// (Einstellung `heizlast_raeume`), von Hand je Raum (`raum.eigenschaften.heizlast_w`) geht vor.
Map<String, double> heizlastJeRaum(ProjectStore store) {
  final m = <String, double>{
    for (final e in (store.einstellung<Map>('heizlast_raeume') ?? const {}).entries)
      if (e.value is num) '${e.key}': (e.value as num).toDouble(),
  };
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      for (final r in store.raeume(g.id)) {
        final h = r.eigenschaften['heizlast_w'];
        if (h is num) m[r.id] = h.toDouble();
      }
    }
  }
  return m;
}

/// Heizkreise eines Verteilers in Abgangsreihenfolge, fertig für den Abgleich.
List<AbgleichKreis> abgleichKreise(ProjectStore store, Objekt verteiler, {AbgleichEinstellung? einstellung}) {
  final e = einstellung ?? abgleichEinstellung(store);
  final d = VerteilerDaten.ausJson(verteiler.eigenschaften);
  final alle = {for (final o in store.alleObjekte()) o.id: o};
  final raumName = {
    for (final geb in store.gebaeude())
      for (final g in store.geschosse(geb.id))
        for (final r in store.raeume(g.id)) r.id: r.name,
  };
  final belegt = <(int, Objekt)>[
    for (var i = 0; i < d.kreise.length; i++)
      if (alle[d.kreise[i]] case final hk? when hk.punkte.length >= 3) (i + 1, hk),
  ];
  final leistung = leistungAufteilen([
    for (final (_, hk) in belegt)
      (id: hk.id, raum: hk.raumId, flaeche: polygonFlaeche(hk.punkte).abs() / 1e6, vonHand: (hk.eigenschaften['leistung_w'] as num?)?.toDouble()),
  ], heizlastJeRaum(store), e.spezLeistung);
  return [
    for (final (abgang, hk) in belegt)
      AbgleichKreis(
        id: hk.id,
        name: hk.kennung,
        raum: raumName[hk.raumId] ?? '',
        flaeche: polygonFlaeche(hk.punkte).abs() / 1e6,
        rohrlaenge: rohrlaenge(hk.punkte, FbhEinstellung.ausJson(hk.eigenschaften)) / 1000,
        leistung: leistung[hk.id] ?? 0,
        abgang: abgang,
        istLMin: (hk.eigenschaften['ist_l_min'] as num?)?.toDouble(),
        istStufe: (hk.eigenschaften['ist_stufe'] as num?)?.toInt(),
        leistungVonHand: hk.eigenschaften['leistung_w'] is num,
      ),
  ];
}

/// Abgleich für einen Verteiler.
Abgleich abgleichFuerVerteiler(ProjectStore store, Objekt verteiler) {
  final e = abgleichEinstellung(store);
  return abgleichBerechnen(abgleichKreise(store, verteiler, einstellung: e), e);
}

/// Kurzfassung für Listen/Planstand: Abgang, Kreis, Soll l/min, Stufe.
List<Map<String, dynamic>> abgleichKurz(Abgleich a) => [
      for (final r in a.kreise)
        {
          'abgang': r.kreis.abgang,
          'kreis': r.kreis.id,
          'kennung': r.kreis.name,
          'raum': r.kreis.raum,
          'soll_l_min': double.parse(r.lMin.toStringAsFixed(2)),
          if (r.stufe != null) 'stufe': r.stufe,
          if (r.kreis.istLMin != null) 'ist_l_min': r.kreis.istLMin,
          if (r.kreis.istStufe != null) 'ist_stufe': r.kreis.istStufe,
        }
    ];

