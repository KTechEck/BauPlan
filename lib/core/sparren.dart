import 'dart:math' as math;

import '../data/models.dart';
import '../data/project_store.dart';
import 'ids.dart';

/// Sparrenlage (Dachsparren oder Sparren-/Balkendecke) als Feld: Bezugslinie
/// A→B (meist entlang der Traufwand), die Sparren stehen senkrecht dazu und
/// laufen [laenge] mm (Grundriss-Projektion) zur Seite [seite] (+1 links,
/// −1 rechts der Linie). Weil Linie und Länge frei sind, dürfen Sparren über
/// Außenwände hinausragen (Dachüberstand, über Balkon oder Terrasse).
/// Ein Feld gilt für einen Raum oder das ganze Geschoss ([raumId] = null).
/// Abstände regelmäßig ([erster] + k·[achsabstand]) oder einzeln gemessen ([positionen]).
class Sparrenfeld {
  Sparrenfeld({
    required this.id,
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    this.seite = 1,
    this.laenge = 4000,
    this.achsabstand = 750,
    this.erster = 0,
    this.breite = 80,
    this.hoehe = 180,
    this.neigung = 0,
    this.raumId,
    this.art = 'Dachsparren',
    this.positionen = const [],
  });

  final String id;
  final double ax, ay, bx, by;
  final int seite;
  final double laenge, achsabstand, erster, breite, hoehe, neigung;
  final String? raumId;
  final String art;
  final List<double> positionen;

  double get linienlaenge => math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));

  /// Lage der Sparren entlang der Bezugslinie (mm ab A).
  List<double> get lagen {
    if (positionen.isNotEmpty) return [...positionen]..sort();
    if (achsabstand <= 0) return const [];
    return [for (var t = erster; t <= linienlaenge + 1; t += achsabstand) t];
  }

  /// Sparren als Strecken im Grundriss (mm).
  List<((double, double), (double, double))> get strecken {
    final l = math.max(1.0, linienlaenge);
    final ux = (bx - ax) / l, uy = (by - ay) / l;
    final nx = uy * seite, ny = -ux * seite;
    return [
      for (final t in lagen) ((ax + ux * t, ay + uy * t), (ax + ux * t + nx * laenge, ay + uy * t + ny * laenge)),
    ];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'a': [ax.round(), ay.round()],
        'b': [bx.round(), by.round()],
        'seite': seite,
        'laenge': laenge.round(),
        'achsabstand': achsabstand.round(),
        'erster': erster.round(),
        'breite': breite.round(),
        'hoehe': hoehe.round(),
        'neigung': neigung,
        if (raumId != null) 'raum': raumId,
        'art': art,
        if (positionen.isNotEmpty) 'positionen': [for (final p in positionen) p.round()],
      };

  static Sparrenfeld ausJson(Map m) {
    double z(Object? v, double d) => (v as num?)?.toDouble() ?? d;
    final a = m['a'] as List? ?? const [0, 0], b = m['b'] as List? ?? const [0, 0];
    return Sparrenfeld(
      id: '${m['id']}',
      ax: z(a[0], 0),
      ay: z(a[1], 0),
      bx: z(b[0], 0),
      by: z(b[1], 0),
      seite: (m['seite'] as num?)?.toInt() ?? 1,
      laenge: z(m['laenge'], 4000),
      achsabstand: z(m['achsabstand'], 750),
      erster: z(m['erster'], 0),
      breite: z(m['breite'], 80),
      hoehe: z(m['hoehe'], 180),
      neigung: z(m['neigung'], 0),
      raumId: m['raum'] as String?,
      art: '${m['art'] ?? 'Dachsparren'}',
      positionen: [for (final p in (m['positionen'] as List? ?? const [])) (p as num).toDouble()],
    );
  }

  Sparrenfeld mitWert(String feld, num wert) {
    final m = toJson();
    if (feld.startsWith('pos_')) {
      final i = int.tryParse(feld.substring(4)) ?? 0;
      final l = [...lagen];
      while (l.length <= i) {
        l.add(l.isEmpty ? 0 : l.last + achsabstand);
      }
      l[i] = wert.toDouble();
      m['positionen'] = [for (final p in l) p.round()];
    } else {
      m[feld] = wert;
    }
    return ausJson(m);
  }
}

const sparrenFelder = {
  'achsabstand': 'Achsabstand (Mitte–Mitte)',
  'erster': 'Erster Sparren ab Linienanfang',
  'breite': 'Sparrenbreite',
  'hoehe': 'Sparrenhöhe',
  'laenge': 'Länge (waagrecht, inkl. Überstand)',
  'neigung': 'Dachneigung (°)',
};

String _schluessel(String geschossId) => 'sparren_$geschossId';

List<Sparrenfeld> sparrenfelder(ProjectStore store, String geschossId) =>
    [for (final m in store.einstellung<List>(_schluessel(geschossId)) ?? const []) Sparrenfeld.ausJson(m as Map)];

void sparrenfelderSetzen(ProjectStore store, String geschossId, List<Sparrenfeld> l) =>
    store.einstellungSetzen(_schluessel(geschossId), [for (final f in l) f.toJson()]);

/// Neues Feld an einer Wand: Linie = Wandachse (ganzes Geschoss) oder nur das
/// Stück [von]–[bis] (je Raum); Sparren laufen zur Seite [links].
Sparrenfeld sparrenfeldAnWand(Wand w, {required bool links, double? von, double? bis, String? raumId, double laenge = 4000, String art = 'Dachsparren'}) {
  final l = math.max(1.0, w.laenge);
  final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
  final t1 = von ?? 0, t2 = bis ?? w.laenge;
  return Sparrenfeld(
    id: neueId(),
    ax: w.x1 + ux * t1,
    ay: w.y1 + uy * t1,
    bx: w.x1 + ux * t2,
    by: w.y1 + uy * t2,
    seite: links ? 1 : -1,
    laenge: laenge,
    raumId: raumId,
    art: art,
  );
}

/// Sparrenlage über das ganze Geschoss: Sparren laufen in Richtung [richtung]
/// (Einheitsvektor im Grundriss) über alle Wände hinweg, mit [ueberstand] an
/// beiden Enden und an den Seiten. Bezugslinie quer dazu am Gebäuderand.
Sparrenfeld sparrenlageGeschoss(List<Wand> waende, {required double rx, required double ry, double ueberstand = 500, double achsabstand = 750, String art = 'Dachsparren'}) {
  final l = math.max(1e-9, math.sqrt(rx * rx + ry * ry));
  final nx = rx / l, ny = ry / l; // Sparrenrichtung
  final ux = -ny, uy = nx; // Bezugslinie
  var uMin = double.infinity, uMax = -double.infinity, nMin = double.infinity, nMax = -double.infinity;
  for (final w in waende) {
    if (w.istKante && !w.gelaender) continue;
    for (final (x, y) in [(w.x1, w.y1), (w.x2, w.y2)]) {
      final u = x * ux + y * uy, n = x * nx + y * ny, h = w.dicke / 2;
      uMin = math.min(uMin, u - h);
      uMax = math.max(uMax, u + h);
      nMin = math.min(nMin, n - h);
      nMax = math.max(nMax, n + h);
    }
  }
  if (!uMin.isFinite) {
    uMin = 0;
    uMax = 4000;
    nMin = 0;
    nMax = 4000;
  }
  final u0 = uMin - ueberstand, u1 = uMax + ueberstand, n0 = nMin - ueberstand;
  final ax = ux * u0 + nx * n0, ay = uy * u0 + ny * n0;
  final bx = ux * u1 + nx * n0, by = uy * u1 + ny * n0;
  // Seite so, dass die Sparren in +n laufen: n = (uy·s, −ux·s)
  final s = (uy * nx - ux * ny) >= 0 ? 1 : -1;
  return Sparrenfeld(id: neueId(), ax: ax, ay: ay, bx: bx, by: by, seite: s, laenge: nMax - nMin + 2 * ueberstand, achsabstand: achsabstand, erster: ueberstand, art: art);
}

/// Nächstes Sparrenfeld zu einem Punkt (Abstand zu einem Sparren ≤ [toleranz]).
String? sparrenfeldBei(List<Sparrenfeld> felder, double x, double y, double toleranz) {
  String? best;
  var bd = toleranz;
  for (final f in felder) {
    for (final (a, b) in f.strecken) {
      final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
      final l2 = dx * dx + dy * dy;
      final t = l2 == 0 ? 0.0 : (((x - a.$1) * dx + (y - a.$2) * dy) / l2).clamp(0.0, 1.0);
      final d = math.sqrt(math.pow(x - (a.$1 + dx * t), 2) + math.pow(y - (a.$2 + dy * t), 2));
      if (d < bd) {
        bd = d;
        best = f.id;
      }
    }
  }
  return best;
}
