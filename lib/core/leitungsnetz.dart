import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../data/models.dart';

/// Leitungen hängen über ihre Enden zusammen: `eigenschaften.anfang` und
/// `eigenschaften.ende` halten einen Bezug `{leitung: id}` (Fortsetzung einer
/// anderen Leitung, z. B. aus der Wand unter den Estrich oder um die Ecke)
/// oder `{objekt: id, anschluss: name}` (Anschluss an einem Gerät).
Map<String, dynamic>? leitungsBezug(Objekt o, String ende) {
  final b = o.eigenschaften[ende];
  return b is Map ? Map<String, dynamic>.from(b) : null;
}

/// Alle Leitungen, die mit [id] über Fortsetzungen verbunden sind (inkl. [id]).
Set<String> leitungsZug(String id, Iterable<Objekt> objekte) {
  final nachbarn = <String, Set<String>>{};
  for (final o in objekte) {
    for (final ende in const ['anfang', 'ende']) {
      final andere = leitungsBezug(o, ende)?['leitung'];
      if (andere is String) {
        nachbarn.putIfAbsent(o.id, () => {}).add(andere);
        nachbarn.putIfAbsent(andere, () => {}).add(o.id);
      }
    }
  }
  final zug = <String>{id};
  final offen = [id];
  while (offen.isNotEmpty) {
    for (final n in nachbarn[offen.removeLast()] ?? const <String>{}) {
      if (zug.add(n)) offen.add(n);
    }
  }
  return zug;
}

/// Bündel: Für Strecken verschiedener Leitungen, die deckungsgleich verlaufen
/// (gleiche Richtung, Abstand ≤ [toleranz], überlappend), einen seitlichen
/// Versatz in Vielfachen (… −1, 0, 1 …) bestimmen, damit jede Leitung sichtbar
/// bleibt. Schlüssel: (Leitung, Strecke).
Map<(int, int), double> buendelVersatz(List<List<Offset>> zuege, {double toleranz = 5}) {
  final strecken = <(int, int, Offset, Offset)>[];
  for (var i = 0; i < zuege.length; i++) {
    for (var j = 0; j + 1 < zuege[i].length; j++) {
      if ((zuege[i][j + 1] - zuege[i][j]).distance >= 1) strecken.add((i, j, zuege[i][j], zuege[i][j + 1]));
    }
  }
  bool gemeinsam((int, int, Offset, Offset) s, (int, int, Offset, Offset) t) {
    if (s.$1 == t.$1) return false;
    final d = s.$4 - s.$3;
    final l = d.distance;
    final u = d / l;
    final e = t.$4 - t.$3;
    if ((u.dx * e.dy - u.dy * e.dx).abs() > 0.02 * e.distance) return false; // nicht parallel
    double quer(Offset p) => ((p - s.$3).dx * u.dy - (p - s.$3).dy * u.dx).abs();
    if (quer(t.$3) > toleranz || quer(t.$4) > toleranz) return false;
    double laengs(Offset p) => (p - s.$3).dx * u.dx + (p - s.$3).dy * u.dy;
    final a = math.min(laengs(t.$3), laengs(t.$4)), b = math.max(laengs(t.$3), laengs(t.$4));
    return math.min(b, l) - math.max(a, 0) > toleranz; // echte Überlappung
  }

  final ergebnis = <(int, int), double>{};
  final gruppe = List<int>.generate(strecken.length, (i) => i);
  int wurzel(int i) => gruppe[i] == i ? i : (gruppe[i] = wurzel(gruppe[i]));
  for (var a = 0; a < strecken.length; a++) {
    for (var b = a + 1; b < strecken.length; b++) {
      if (gemeinsam(strecken[a], strecken[b])) gruppe[wurzel(a)] = wurzel(b);
    }
  }
  final gruppen = <int, List<int>>{};
  for (var i = 0; i < strecken.length; i++) {
    gruppen.putIfAbsent(wurzel(i), () => []).add(i);
  }
  for (final g in gruppen.values) {
    final leitungen = (g.map((i) => strecken[i].$1).toSet().toList()..sort());
    if (leitungen.length < 2) continue;
    for (final i in g) {
      final k = leitungen.indexOf(strecken[i].$1) - (leitungen.length - 1) / 2;
      ergebnis[(strecken[i].$1, strecken[i].$2)] = k;
    }
  }
  return ergebnis;
}

/// Linienzug mit Bündelversatz: jede Strecke wird um `k × abstand` quer
/// verschoben (Bildschirmkoordinaten); die Ecken verbinden sich von selbst.
List<Offset> versetzterZug(List<Offset> pts, int zug, Map<(int, int), double> versatz, double abstand) {
  if (versatz.isEmpty || pts.length < 2) return pts;
  final out = <Offset>[];
  for (var j = 0; j + 1 < pts.length; j++) {
    final k = versatz[(zug, j)] ?? 0;
    final d = pts[j + 1] - pts[j];
    final l = d.distance;
    final n = l < 1e-6 ? Offset.zero : Offset(-d.dy / l, d.dx / l) * (k * abstand);
    out
      ..add(pts[j] + n)
      ..add(pts[j + 1] + n);
  }
  return out;
}

/// Lagen, in die eine Leitung am Ende übergehen kann.
const uebergangsLagen = ['unter Estrich', 'im Estrich', 'in Decke', 'in Beton', 'auf RFB', 'in Nachbarwand (Ecke)', 'durch Wand'];

/// Symbol für einen Übergang: nach unten, nach oben oder seitlich.
String uebergangsPfeil(String lage) => switch (lage) {
      'in Decke' || 'in Beton' => '↑',
      'in Nachbarwand (Ecke)' => '↱',
      'durch Wand' => '⊙',
      _ => '↓',
    };
