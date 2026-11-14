import 'dart:math' as math;

import '../data/models.dart';
import '../data/project_store.dart';
import 'leitung_wand.dart';
import 'raumerkennung.dart';

/// Objekte über mehrere Geschosse: Steigleitungen, Fallrohre, Kamine,
/// Treppen. Ein Objekt mit `eigenschaften['bis_geschoss']` erscheint in allen
/// Geschossen zwischen seinem eigenen und dem Zielgeschoss (gleiches Gebäude).
List<Objekt> durchgehendeObjekte(ProjectStore store, String geschossId) {
  final aus = <Objekt>[];
  for (final geb in store.gebaeude()) {
    final gs = store.geschosse(geb.id);
    final hier = gs.indexWhere((g) => g.id == geschossId);
    if (hier < 0) continue;
    for (var i = 0; i < gs.length; i++) {
      if (i == hier) continue;
      for (final o in store.objekte(gs[i].id)) {
        final ziel = gs.indexWhere((g) => g.id == o.eigenschaften['bis_geschoss']);
        if (ziel < 0) continue;
        if (hier >= math.min(i, ziel) && hier <= math.max(i, ziel)) aus.add(o);
      }
    }
  }
  return aus;
}

/// Treppe (Typ TR, Lauflinie): Steigungen, Steigung, Auftritt, Schrittmaß.
/// Höhe FFB→FFB aus `eigenschaften['hoehe']` (Vorgabe 2800 mm), Podest nach
/// Stufe `podest_nach` mit Tiefe `podest_tiefe` (zählt nicht als Auftritt).
({int steigungen, double steigung, double auftritt, double schrittmass, String bewertung}) treppeBerechnen(Objekt o) {
  final e = o.eigenschaften;
  int zahl(String k, int d) => (e[k] as num?)?.round() ?? int.tryParse('${e[k]}') ?? d;
  final h = zahl('hoehe', 2800);
  final n = zahl('steigungen', (h / 175).round()).clamp(2, 40);
  final s = h / n;
  final podest = zahl('podest_nach', 0) > 0 ? zahl('podest_tiefe', 1000) : 0;
  final auftritte = math.max(1, n - 1 - (podest > 0 ? 1 : 0));
  final a = math.max(0.0, o.laenge - podest) / auftritte;
  final sm = 2 * s + a;
  final bewertung = (s > 190 || s < 140)
      ? 'Steigung ungewöhnlich (üblich 160–190 mm)'
      : (sm < 590 || sm > 650)
          ? 'Schrittmaß ${sm.round()} mm außerhalb 590–650 mm'
          : 'bequem (Schrittmaß ${sm.round()} mm)';
  return (steigungen: n, steigung: s, auftritt: a, schrittmass: sm, bewertung: bewertung);
}

/// Deckendicke über einem Geschoss (Einstellung `deckendicke` {geschossId: mm}, Vorgabe 200 mm).
int deckendicke(ProjectStore store, Geschoss g) =>
    ((store.einstellung<Map>('deckendicke') ?? const {})[g.id] as num?)?.round() ?? 200;

/// Leitungen aus anderen Geschossen desselben Gebäudes, die mit ihren Höhen
/// (`z_abs`, in der Wandansicht gezeichnet) in dieses Geschoss hineinreichen –
/// z. B. ein Rohr, das in der Wand vom EG ins OG steigt. Höhen umgerechnet auf
/// dieses Geschoss (absolut, Nullpunkt = Rohfußboden-Bezug dieses Geschosses).
List<(Objekt, List<(Punkt, double)>)> leitungenAusAnderenGeschossen(ProjectStore store, String geschossId) {
  final aus = <(Objekt, List<(Punkt, double)>)>[];
  for (final geb in store.gebaeude()) {
    final gs = store.geschosse(geb.id);
    final hier = gs.where((g) => g.id == geschossId).firstOrNull;
    if (hier == null) continue;
    final sockel = geschossSockel(gs, decke: (g) => deckendicke(store, g));
    final unten = hier.hoehen.rfb.toDouble(), oben = (hier.hoehen.rohdecke + deckendicke(store, hier)).toDouble();
    for (final g in gs) {
      if (g.id == geschossId) continue;
      final versatz = sockel[g.id]! - sockel[geschossId]!;
      for (final o in store.objekte(g.id)) {
        if (o.zPunkte == null || o.punkte.length < 2) continue;
        for (final stueck in leitungImGeschoss(o, versatz, unten, oben)) {
          aus.add((o, stueck));
        }
      }
    }
  }
  return aus;
}
