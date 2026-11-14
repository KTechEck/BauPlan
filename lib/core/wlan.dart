import 'dart:math' as math;

import 'raumerkennung.dart';

/// WLAN-Abdeckung als Planungshilfe (ähnlich einem Ausleuchtungsplaner):
/// Pegel je Rasterpunkt aus Sendeleistung, Freiraumdämpfung und Wänden im
/// Weg. Richtwerte – echte Messung (z. B. Site-Survey-App) ersetzt das nicht.

enum WlanBand { g24, g5, g6 }

extension WlanBandText on WlanBand {
  String get label => switch (this) { WlanBand.g24 => '2,4 GHz', WlanBand.g5 => '5 GHz', WlanBand.g6 => '6 GHz' };
  double get mhz => switch (this) { WlanBand.g24 => 2437, WlanBand.g5 => 5500, WlanBand.g6 => 6100 };
  /// Faktor auf die Wanddämpfung (höhere Frequenz → mehr Dämpfung).
  double get wandFaktor => switch (this) { WlanBand.g24 => 1.0, WlanBand.g5 => 1.5, WlanBand.g6 => 1.7 };
}

/// Freiraumdämpfung in dB für Abstand [m] und Frequenz [mhz].
double freiraumDaempfung(double m, double mhz) => 20 * math.log(math.max(0.5, m)) / math.ln10 + 20 * math.log(mhz) / math.ln10 - 27.55;

/// Dämpfung einer Wand bei 2,4 GHz (dB) aus Wandtyp-Namen bzw. Dicke.
double wandDaempfung(String wandtyp, int dicke) {
  final n = wandtyp.toLowerCase();
  if (n.contains('beton') || n.contains('stahl')) return 15;
  if (n.contains('kalksand') || RegExp(r'\bks\b').hasMatch(n)) return 12;
  if (n.contains('ziegel') || n.contains('poroton') || n.contains('mauer')) return 9;
  if (n.contains('poren') || n.contains('ytong')) return 7;
  if (n.contains('gips') || n.contains('trocken') || n.contains('holz') || n.contains('ständer')) return 4;
  if (n.contains('glas')) return 3;
  return dicke >= 240 ? 12 : (dicke >= 115 ? 8 : 4);
}

/// Wandstück für die Dämpfung.
typedef WlanWand = ({Punkt a, Punkt b, double db});

/// Access Point: Lage (mm), Sendeleistung EIRP (dBm).
typedef WlanAp = ({String id, Punkt p, double dbm});

bool _schneidet(Punkt a, Punkt b, Punkt c, Punkt d) {
  double k(Punkt p, Punkt q, Punkt r) => (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
  final d1 = k(c, d, a), d2 = k(c, d, b), d3 = k(a, b, c), d4 = k(a, b, d);
  return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
}

/// Pegel (dBm) an [q]: bester Access Point.
double wlanPegel(Punkt q, List<WlanAp> aps, List<WlanWand> waende, WlanBand band) {
  var best = -120.0;
  for (final ap in aps) {
    final d = (q - ap.p).laenge / 1000;
    var pegel = ap.dbm - freiraumDaempfung(d, band.mhz);
    for (final w in waende) {
      if (_schneidet(ap.p, q, w.a, w.b)) pegel -= w.db * band.wandFaktor;
    }
    if (pegel > best) best = pegel;
  }
  return best;
}

/// Bewertung eines Pegels.
String wlanStufe(double dbm) => dbm >= -60 ? 'sehr gut' : (dbm >= -67 ? 'gut (Video/Telefonie)' : (dbm >= -75 ? 'schwach' : 'kein Empfang'));

/// Farbe (ARGB) je Pegel: grün → gelb → orange → rot.
int wlanFarbe(double dbm) => dbm >= -60 ? 0x6640C057 : (dbm >= -67 ? 0x66FAB005 : (dbm >= -75 ? 0x66FD7E14 : 0x55E03131));

/// Rasterpunkte (Mitte, Pegel) über einem Rechteck.
List<(Punkt, double)> wlanRaster(double x0, double y0, double x1, double y1, List<WlanAp> aps, List<WlanWand> waende, WlanBand band, {double raster = 500}) => [
      for (var y = y0 + raster / 2; y < y1; y += raster)
        for (var x = x0 + raster / 2; x < x1; x += raster) (Punkt(x, y), wlanPegel(Punkt(x, y), aps, waende, band)),
    ];

/// Raum-Auswertung: Anteil gut versorgter Fläche (≥ −67 dBm) und schwächster Punkt.
({double anteilGut, double minimum}) wlanRaum(List<Punkt> umriss, List<WlanAp> aps, List<WlanWand> waende, WlanBand band, {double raster = 400}) {
  final xs = umriss.map((p) => p.x), ys = umriss.map((p) => p.y);
  var n = 0, gut = 0;
  var minimum = 0.0;
  for (var y = ys.reduce(math.min) + raster / 2; y < ys.reduce(math.max); y += raster) {
    for (var x = xs.reduce(math.min) + raster / 2; x < xs.reduce(math.max); x += raster) {
      final q = Punkt(x, y);
      if (!punktInPolygon(q, umriss)) continue;
      final pg = wlanPegel(q, aps, waende, band);
      n++;
      if (pg >= -67) gut++;
      if (n == 1 || pg < minimum) minimum = pg;
    }
  }
  return (anteilGut: n == 0 ? 0 : gut / n, minimum: n == 0 ? -120 : minimum);
}
