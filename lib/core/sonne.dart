/// Sonnenstand (NOAA-Näherung, auf etwa 0,5° genau) und einfache Verschattung:
/// Besonnung von Fenstern durch die eigenen Wände, Einstrahlung auf
/// Dachflächen für PV. Richtungen im Grundriss: Winkel im Uhrzeigersinn ab
/// „oben“; Norden liegt bei [nordGrad] (Projekteinstellung `norden_grad`).
library;

import 'dart:math' as math;

double _rad(double g) => g * math.pi / 180;
double _grad(double r) => r * 180 / math.pi;

/// Sonnenstand: Azimut (° ab Nord im Uhrzeigersinn) und Höhe (° über Horizont).
({double azimut, double hoehe}) sonnenstand(double breite, double laenge, DateTime zeit) {
  final u = zeit.toUtc();
  final tag = u.difference(DateTime.utc(u.year, 1, 1)).inMinutes / 1440.0; // Tage seit 1.1.
  final stunde = u.hour + u.minute / 60 + u.second / 3600;
  final g = 2 * math.pi / 365 * (tag + (stunde - 12) / 24);
  final zgl = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g) - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g));
  final dekl = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g) + 0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g);
  final wahreZeit = stunde * 60 + zgl + 4 * laenge; // Minuten (UTC → wahre Ortszeit)
  final ha = _rad(wahreZeit / 4 - 180);
  final phi = _rad(breite);
  final cosZ = (math.sin(phi) * math.sin(dekl) + math.cos(phi) * math.cos(dekl) * math.cos(ha)).clamp(-1.0, 1.0);
  final zenit = math.acos(cosZ);
  var az = _grad(math.atan2(math.sin(ha), math.cos(ha) * math.sin(phi) - math.tan(dekl) * math.cos(phi))) + 180;
  az = (az % 360 + 360) % 360;
  return (azimut: az, hoehe: 90 - _grad(zenit));
}

/// Richtung zur Sonne im Grundriss (Einheitsvektor, y nach unten) und Höhe.
({double x, double y, double hoehe}) sonnenRichtungPlan(double azimut, double hoehe, double nordGrad) {
  final w = _rad(azimut + nordGrad);
  return (x: math.sin(w), y: -math.cos(w), hoehe: hoehe);
}

/// Wand als Hindernis: Strecke im Grundriss und Oberkante (mm über FFB).
typedef Hindernis = ({double ax, double ay, double bx, double by, double oben});

bool _verschattet(double px, double py, double z, ({double x, double y, double hoehe}) s, List<Hindernis> h) {
  final tanH = math.tan(_rad(s.hoehe));
  for (final w in h) {
    // Strahl p + t·s schneidet Strecke a–b?
    final ex = w.bx - w.ax, ey = w.by - w.ay;
    final nenner = s.x * ey - s.y * ex;
    if (nenner.abs() < 1e-9) continue;
    final qx = w.ax - px, qy = w.ay - py;
    final t = (qx * ey - qy * ex) / nenner;
    final u = (qx * s.y - qy * s.x) / nenner;
    if (t <= 1 || u < 0 || u > 1) continue;
    if (z + t * tanH < w.oben) return true;
  }
  return false;
}

/// Sonnenstunden eines Fensters an einem Tag (Viertelstundenschritte): Sonne
/// über dem Horizont, vor dem Fenster und nicht hinter einer Wand.
/// [nx]/[ny] = Außennormale, [z] = Höhe der Fenstermitte über FFB.
double sonnenstunden({required double breite, required double laenge, required DateTime tag, required double nordGrad, required double px, required double py, required double nx, required double ny, required double z, List<Hindernis> hindernisse = const []}) {
  var n = 0;
  for (var m = 0; m < 24 * 60; m += 15) {
    final t = DateTime(tag.year, tag.month, tag.day).add(Duration(minutes: m));
    final st = sonnenstand(breite, laenge, t);
    if (st.hoehe < 3) continue;
    final s = sonnenRichtungPlan(st.azimut, st.hoehe, nordGrad);
    if (s.x * nx + s.y * ny < 0.08) continue; // streifend oder von hinten
    if (_verschattet(px + nx * 50, py + ny * 50, z, s, hindernisse)) continue;
    n++;
  }
  return n / 4;
}

/// Relative Einstrahlung auf eine geneigte Fläche (Neigung [neigung] °,
/// Ausrichtung [richtung] ° ab Nord) über ein Jahr (je Monat ein Tag),
/// bezogen auf die beste Ausrichtung Süd 35° = 100 %.
double pvFaktor(double breite, double laenge, double neigung, double richtung) {
  double summe(double ng, double ri) {
    var s = 0.0;
    final nb = _rad(ng), ra = _rad(ri);
    final n = (x: math.sin(nb) * math.sin(ra), y: math.sin(nb) * math.cos(ra), z: math.cos(nb)); // x = Ost, y = Nord
    for (var monat = 1; monat <= 12; monat++) {
      for (var m = 0; m < 24 * 60; m += 30) {
        final t = DateTime.utc(2026, monat, 15).add(Duration(minutes: m - 60));
        final st = sonnenstand(breite, laenge, t);
        if (st.hoehe <= 0) continue;
        final h = _rad(st.hoehe), a = _rad(st.azimut);
        final sx = math.cos(h) * math.sin(a), sy = math.cos(h) * math.cos(a), sz = math.sin(h);
        final cos = n.x * sx + n.y * sy + n.z * sz;
        // klare Luft, grob: Strahlung ~ sin(h)^0,3 (Luftmasse)
        if (cos > 0) s += cos * math.pow(math.sin(h), 0.3);
        // diffuses Himmelslicht (Anteil je nach Neigung sichtbarer Himmel)
        s += 0.3 * math.sin(h) * (1 + math.cos(nb)) / 2;
      }
    }
    return s;
  }

  final best = summe(35, 180);
  return best <= 0 ? 0 : summe(neigung, richtung) / best;
}

/// Kompassrichtung (° ab Nord) einer Außennormalen im Grundriss.
double kompass(double nx, double ny, double nordGrad) {
  final w = _grad(math.atan2(nx, -ny)) - nordGrad;
  return (w % 360 + 360) % 360;
}
