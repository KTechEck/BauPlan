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
