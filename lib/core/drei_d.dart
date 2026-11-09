import 'dart:math' as math;

/// Einfache 3D-Geometrie für die Raumansicht (mm): Punkte, Quader, Leitungen
/// und Kollisionsprüfung – ohne Grafikbibliothek.

class V3 {
  const V3(this.x, this.y, this.z);
  final double x, y, z;
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double f) => V3(x * f, y * f, z * f);
  double skalar(V3 o) => x * o.x + y * o.y + z * o.z;
  double get laenge => math.sqrt(skalar(this));
  @override
  String toString() => '(${x.round()}, ${y.round()}, ${z.round()})';
}

/// Gerät als gedrehter Quader: Mitte der Grundfläche (x, y), Unterkante z.
class Quader {
  const Quader({required this.name, required this.x, required this.y, required this.z, required this.b, required this.t, required this.h, this.drehung = 0, this.id = ''});
  final String id, name;
  final double x, y, z, b, t, h;
  final int drehung;

  List<V3> get ecken {
    final w = drehung * math.pi / 180;
    final c = math.cos(w), s = math.sin(w);
    V3 p(double u, double v, double hz) => V3(x + u * c - v * s, y + u * s + v * c, z + hz);
    return [
      for (final hz in [0.0, h]) ...[p(-b / 2, -t / 2, hz), p(b / 2, -t / 2, hz), p(b / 2, t / 2, hz), p(-b / 2, t / 2, hz)],
    ];
  }

  /// Liegt ein Punkt (mit Zuschlag [r]) im Quader?
  bool enthaelt(V3 q, {double r = 0}) {
    final w = -drehung * math.pi / 180;
    final c = math.cos(w), s = math.sin(w);
    final dx = q.x - x, dy = q.y - y;
    final u = dx * c - dy * s, v = dx * s + dy * c;
    return u.abs() <= b / 2 + r && v.abs() <= t / 2 + r && q.z >= z - r && q.z <= z + h + r;
  }
}

/// Leitung/Rohr als 3D-Linienzug mit Außendurchmesser.
class Leitung3d {
  const Leitung3d({required this.name, required this.punkte, this.durchmesser = 20, this.id = '', this.gewerk = ''});
  final String id, name, gewerk;
  final List<V3> punkte;
  final double durchmesser;
}

/// Kleinster Abstand zweier Strecken im Raum.
double streckenAbstand(V3 p1, V3 q1, V3 p2, V3 q2) {
  final d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2;
  final a = d1.skalar(d1), e = d2.skalar(d2), f = d2.skalar(r);
  double s, t;
  if (a <= 1e-9 && e <= 1e-9) return r.laenge;
  if (a <= 1e-9) {
    s = 0;
    t = (f / e).clamp(0.0, 1.0);
  } else {
    final c = d1.skalar(r);
    if (e <= 1e-9) {
      t = 0;
      s = (-c / a).clamp(0.0, 1.0);
    } else {
      final b = d1.skalar(d2);
      final nenner = a * e - b * b;
      s = nenner != 0 ? ((b * f - c * e) / nenner).clamp(0.0, 1.0) : 0;
      t = (b * s + f) / e;
      if (t < 0) {
        t = 0;
        s = (-c / a).clamp(0.0, 1.0);
      } else if (t > 1) {
        t = 1;
        s = ((b - c) / a).clamp(0.0, 1.0);
      }
    }
  }
  return ((p1 + d1 * s) - (p2 + d2 * t)).laenge;
}

/// Kollisionen: Leitungen untereinander (Abstand < Summe der Radien + [luft])
/// und Leitungen durch Geräte. Liefert lesbare Hinweise und die betroffenen IDs.
({List<String> hinweise, Set<String> ids}) kollisionen3d(List<Quader> geraete, List<Leitung3d> leitungen, {double luft = 10}) {
  final h = <String>[];
  final ids = <String>{};
  for (var i = 0; i < leitungen.length; i++) {
    final a = leitungen[i];
    for (var j = i + 1; j < leitungen.length; j++) {
      final b = leitungen[j];
      var min = double.infinity;
      for (var m = 0; m + 1 < a.punkte.length; m++) {
        for (var n = 0; n + 1 < b.punkte.length; n++) {
          min = math.min(min, streckenAbstand(a.punkte[m], a.punkte[m + 1], b.punkte[n], b.punkte[n + 1]));
        }
      }
      final soll = (a.durchmesser + b.durchmesser) / 2 + luft;
      if (min < soll) {
        h.add('${a.name} und ${b.name} kreuzen sich (Abstand ${min.round()} mm, nötig ${soll.round()} mm)');
        ids.addAll([a.id, b.id]);
      }
    }
    for (final g in geraete) {
      var treffer = false;
      for (var m = 0; m + 1 < a.punkte.length && !treffer; m++) {
        final p = a.punkte[m], q = a.punkte[m + 1];
        final n = math.max(1, ((q - p).laenge / 20).ceil());
        for (var k = 1; k < n; k++) {
          if (g.enthaelt(p + (q - p) * (k / n), r: a.durchmesser / 2)) {
            treffer = true;
            break;
          }
        }
      }
      if (treffer) {
        h.add('${a.name} läuft durch ${g.name}');
        ids.addAll([a.id, g.id]);
      }
    }
  }
  return (hinweise: h, ids: ids);
}

/// Kamera für die Orbit-Ansicht: Drehung um die Hochachse ([azimut]) und
/// Neigung ([neigung]), Abstand [abstand], Ziel [ziel].
class Kamera {
  const Kamera({this.azimut = -0.7, this.neigung = 0.6, this.abstand = 9000, this.ziel = const V3(0, 0, 1200), this.brennweite = 900});
  final double azimut, neigung, abstand, brennweite;
  final V3 ziel;

  /// Projektion in Bildschirmkoordinaten (Mitte = 0,0) und Tiefe.
  (double, double, double) projizieren(V3 p) {
    final d = p - ziel;
    final ca = math.cos(azimut), sa = math.sin(azimut);
    final x1 = d.x * ca - d.y * sa, y1 = d.x * sa + d.y * ca;
    final cn = math.cos(neigung), sn = math.sin(neigung);
    final y2 = y1 * cn - d.z * sn, z2 = y1 * sn + d.z * cn;
    final tiefe = abstand + y2;
    final f = brennweite / math.max(100, tiefe);
    return (x1 * f, -z2 * f, tiefe);
  }

  Kamera mit({double? azimut, double? neigung, double? abstand, V3? ziel}) => Kamera(
        azimut: azimut ?? this.azimut,
        neigung: (neigung ?? this.neigung).clamp(0.05, 1.5),
        abstand: (abstand ?? this.abstand).clamp(1500, 60000),
        ziel: ziel ?? this.ziel,
        brennweite: brennweite,
      );
}
