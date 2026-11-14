import 'dart:math' as math;

import '../data/models.dart';
import 'raumerkennung.dart';

/// Lagen, in denen ein Objekt nach dem Verkleiden nicht mehr sichtbar ist.
const verdeckteLagen = {'in Decke', 'an Decke', 'in Vorwand', 'hinter Verkleidung', 'in Wand', 'im Estrich'};

/// Muss das Objekt nach dem Verkleiden zugänglich bleiben? Ausdrücklich
/// (`eigenschaften['zugaenglich']`), Brandschutzklappen und Absperrarmaturen
/// immer, Abzweigdosen und Netzteile, wenn sie verdeckt liegen.
bool mussZugaenglich(Objekt o, Objekttyp? t) {
  final z = o.eigenschaften['zugaenglich'];
  if (z is bool) return z;
  final k = t?.kuerzel ?? '';
  if (k == 'BK' || k == 'AV') return true;
  final verdeckt = verdeckteLagen.contains(o.lage) && o.lage != 'in Wand';
  if (k == 'DO' && verdeckt && (t?.name.contains('Abzweig') ?? false)) return true;
  if (k == 'DO' && o.lage == 'in Decke') return true;
  if (o.eigenschaften['netzteil'] != null && verdeckt) return true;
  return false;
}

/// Abstand (mm, waagerecht im Grundriss) von [p] zum Rand einer
/// Revisionsöffnung (0 = innerhalb).
double abstandZuOeffnung(Punkt p, List<Punkt> oeffnung) {
  if (oeffnung.length < 3) return double.infinity;
  if (punktInPolygon(p, oeffnung)) return 0;
  var best = double.infinity;
  for (var i = 0; i < oeffnung.length; i++) {
    final a = oeffnung[i], b = oeffnung[(i + 1) % oeffnung.length];
    final d = b - a;
    final l2 = d.skalar(d);
    final t = l2 < 1e-9 ? 0.0 : ((p - a).skalar(d) / l2).clamp(0.0, 1.0);
    best = math.min(best, (a + d * t - p).laenge);
  }
  return best;
}

/// Ergebnis je zugänglich zu haltendem Objekt: nächste Revisionsöffnung und Abstand.
typedef RevisionsPruefung = ({Objekt objekt, Objekt? oeffnung, double abstand, bool erreichbar});

/// Prüft für ein Geschoss, ob jedes zugänglich zu haltende Objekt eine
/// Revisionsöffnung (Typ RO) in Reichweite [reichweite] (mm) hat. Öffnungen
/// in der Decke zählen für Objekte an/in der Decke, sonst alle.
List<RevisionsPruefung> revisionPruefen(List<Objekt> objekte, Map<String, Objekttyp> typen, {double reichweite = 400}) {
  final oeffnungen = [for (final o in objekte) if (typen[o.typId]?.kuerzel == 'RO' && o.punkte.length >= 3) o];
  final aus = <RevisionsPruefung>[];
  for (final o in objekte) {
    if (o.punkte.isEmpty || !mussZugaenglich(o, typen[o.typId])) continue;
    final p = o.punkte.first;
    final decke = o.lage == 'in Decke' || o.lage == 'an Decke';
    Objekt? beste;
    var abst = double.infinity;
    for (final r in oeffnungen) {
      final rDecke = r.lage == 'in Decke' || r.lage == 'an Decke' || r.lage == null;
      if (decke && !rDecke) continue;
      final d = abstandZuOeffnung(p, r.punkte);
      if (d < abst) {
        abst = d;
        beste = r;
      }
    }
    aus.add((objekt: o, oeffnung: beste, abstand: abst, erreichbar: abst <= reichweite));
  }
  return aus;
}
