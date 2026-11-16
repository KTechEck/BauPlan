/// Gelände um das Haus: Höhenpunkte (mm, Höhe relativ zu ±0 = Fertigfußboden
/// Erdgeschoss), dazwischen weich interpoliert. Daraus Höhenlinien, Gefälle
/// und Hinweise zur Entwässerung (Gelände muss vom Haus weg fallen) und zum
/// Sockel (Spritzwasserbereich). Gespeichert in der Projekteinstellung `gelaende`.
library;

import 'dart:math' as math;

class Hoehenpunkt {
  const Hoehenpunkt(this.x, this.y, this.z, {this.name = ''});
  final double x, y, z;
  final String name;

  Map<String, dynamic> toJson() => {'x': x.round(), 'y': y.round(), 'z': z.round(), if (name.isNotEmpty) 'name': name};
  static Hoehenpunkt ausJson(Map m) => Hoehenpunkt((m['x'] as num).toDouble(), (m['y'] as num).toDouble(), (m['z'] as num).toDouble(), name: '${m['name'] ?? ''}');
}

List<Hoehenpunkt> gelaendeLesen(Object? v) => [
      for (final m in ((v is Map ? v['punkte'] : null) as List? ?? const []))
        if (m is Map) Hoehenpunkt.ausJson(m),
    ];

Map<String, dynamic> gelaendeJson(List<Hoehenpunkt> p) => {'punkte': [for (final x in p) x.toJson()]};

/// Höhe an (x, y): gewichtetes Mittel der Höhenpunkte (inverse Distanz²).
double? gelaendeHoehe(List<Hoehenpunkt> p, double x, double y) {
  if (p.isEmpty) return null;
  var sw = 0.0, sz = 0.0;
  for (final q in p) {
    final d2 = (q.x - x) * (q.x - x) + (q.y - y) * (q.y - y);
    if (d2 < 1) return q.z;
    final w = 1 / d2;
    sw += w;
    sz += w * q.z;
  }
  return sz / sw;
}

/// Gefälle an (x, y) in % und Richtung bergab (Einheitsvektor im Grundriss).
({double prozent, double dx, double dy}) gefaelle(List<Hoehenpunkt> p, double x, double y, {double h = 250}) {
  final zx1 = gelaendeHoehe(p, x + h, y) ?? 0, zx0 = gelaendeHoehe(p, x - h, y) ?? 0;
  final zy1 = gelaendeHoehe(p, x, y + h) ?? 0, zy0 = gelaendeHoehe(p, x, y - h) ?? 0;
  final gx = (zx1 - zx0) / (2 * h), gy = (zy1 - zy0) / (2 * h);
  final l = math.sqrt(gx * gx + gy * gy);
  return (prozent: l * 100, dx: l < 1e-9 ? 0 : -gx / l, dy: l < 1e-9 ? 0 : -gy / l);
}

/// Höhenlinien (Marching Squares) im Rechteck, Abstand [stufe] mm.
List<(double, (double, double), (double, double))> hoehenlinien(List<Hoehenpunkt> p, double x0, double y0, double x1, double y1, {double raster = 500, double stufe = 250}) {
  if (p.length < 2) return const [];
  final nx = math.max(2, ((x1 - x0) / raster).ceil()), ny = math.max(2, ((y1 - y0) / raster).ceil());
  final dx = (x1 - x0) / nx, dy = (y1 - y0) / ny;
  final z = [
    for (var j = 0; j <= ny; j++) [for (var i = 0; i <= nx; i++) gelaendeHoehe(p, x0 + i * dx, y0 + j * dy)!],
  ];
  final zs = [for (final r in z) ...r];
  final lo = (zs.reduce(math.min) / stufe).ceil(), hi = (zs.reduce(math.max) / stufe).floor();
  final aus = <(double, (double, double), (double, double))>[];
  for (var k = lo; k <= hi; k++) {
    final h = k * stufe;
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        final ecken = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)];
        final pts = <(double, double)>[];
        for (var e = 0; e < 4; e++) {
          final (ai, aj) = ecken[e];
          final (bi, bj) = ecken[(e + 1) % 4];
          final za = z[aj][ai], zb = z[bj][bi];
          if ((za < h) != (zb < h)) {
            final t = (h - za) / (zb - za);
            pts.add((x0 + (ai + (bi - ai) * t) * dx, y0 + (aj + (bj - aj) * t) * dy));
          }
        }
        if (pts.length >= 2) aus.add((h, pts[0], pts[1]));
        if (pts.length == 4) aus.add((h, pts[2], pts[3]));
      }
    }
  }
  return aus;
}

/// Hinweise zu Entwässerung und Sockel rund um das Gebäude (Rechteck x0…y1).
List<String> gelaendeHinweise(List<Hoehenpunkt> p, double x0, double y0, double x1, double y1) {
  if (p.isEmpty) return const [];
  final aus = <String>[];
  for (final (seite, nx, ny, mx, my) in [
    ('Nordseite (oben)', 0.0, -1.0, (x0 + x1) / 2, y0),
    ('Südseite (unten)', 0.0, 1.0, (x0 + x1) / 2, y1),
    ('Westseite (links)', -1.0, 0.0, x0, (y0 + y1) / 2),
    ('Ostseite (rechts)', 1.0, 0.0, x1, (y0 + y1) / 2),
  ]) {
    final nah = gelaendeHoehe(p, mx + nx * 500, my + ny * 500)!, fern = gelaendeHoehe(p, mx + nx * 3000, my + ny * 3000)!;
    final prozent = (nah - fern) / 2500 * 100;
    if (prozent < 2) {
      aus.add('$seite: Gelände fällt nur ${prozent.toStringAsFixed(1).replaceAll('.', ',')} % vom Haus weg – mind. 2 % auf den ersten 3 m (besser 5 %), sonst läuft Wasser ans Haus; ggf. Rinne/Drainage.');
    }
    if (nah > -150) {
      aus.add('$seite: Gelände nur ${(-nah).round()} mm unter Fertigfußboden – Sockel/Spritzwasserbereich mind. 150 mm (DIN 18533 30 cm über Gelände abdichten), Türschwellen prüfen.');
    }
  }
  return aus;
}
