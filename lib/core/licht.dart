import 'dart:math' as math;

import 'raumerkennung.dart';

/// Lichtplaner – vereinfachte Abschätzung zum Vergleichen von Varianten,
/// keine lichttechnische Berechnung (kein Reflexionsanteil der Flächen außer
/// einem pauschalen Zuschlag für indirektes Licht).

/// Leuchte für die Rechnung: Lage (mm), Höhe über FFB (mm), Lichtstrom (lm),
/// Abstrahlwinkel (voller Kegel, Grad).
typedef LichtQuelle = ({double x, double y, double hoehe, double lumen, double winkel});

/// Lichtstärke-Verteilung: gleichmäßig im Kegel mit weichem Rand (10 % des Winkels).
double _lichtstaerke(LichtQuelle l, double theta) {
  final halb = l.winkel.clamp(10, 180) * math.pi / 360;
  final raumwinkel = 2 * math.pi * (1 - math.cos(halb));
  final i0 = l.lumen / raumwinkel; // cd
  final rand = halb * 0.1;
  if (theta <= halb - rand) return i0;
  if (theta >= halb + rand) return 0;
  return i0 * (halb + rand - theta) / (2 * rand);
}

/// Beleuchtungsstärke (lx) im Punkt [p] auf der Arbeitsebene [arbeitsebene] (mm über FFB).
double beleuchtungsstaerke(Punkt p, Iterable<LichtQuelle> leuchten, {double arbeitsebene = 750}) {
  var e = 0.0;
  for (final l in leuchten) {
    final h = (l.hoehe - arbeitsebene) / 1000; // m
    if (h <= 0) continue;
    final dx = (p.x - l.x) / 1000, dy = (p.y - l.y) / 1000;
    final d2 = dx * dx + dy * dy + h * h;
    final cos = h / math.sqrt(d2);
    e += _lichtstaerke(l, math.acos(cos)) * cos / d2;
  }
  return e;
}

/// Ergebnis der Rasterrechnung in einem Raum.
class LichtErgebnis {
  LichtErgebnis(this.zellen, this.raster);
  final List<(Punkt, double)> zellen; // Zellmitte, lx
  final double raster;

  double get mittel => zellen.isEmpty ? 0 : zellen.fold<double>(0, (s, z) => s + z.$2) / zellen.length;
  double get minimum => zellen.isEmpty ? 0 : zellen.map((z) => z.$2).reduce(math.min);
  double get maximum => zellen.isEmpty ? 0 : zellen.map((z) => z.$2).reduce(math.max);

  /// Gleichmäßigkeit U0 = Emin / Em.
  double get gleichmaessigkeit => mittel <= 0 ? 0 : minimum / mittel;

  /// Anteil der Fläche unter [ziel] lx.
  double anteilUnter(double ziel) => zellen.isEmpty ? 0 : zellen.where((z) => z.$2 < ziel).length / zellen.length;
}

/// Beleuchtungsstärke im Raster über den Raumumriss. [indirektLumen] (z. B.
/// LED-Streifen in einer Voute) wird mit [indirektFaktor] gleichmäßig über
/// die Fläche verteilt.
LichtErgebnis lichtraster(
  List<Punkt> umriss,
  List<LichtQuelle> leuchten, {
  double raster = 200,
  double arbeitsebene = 750,
  double indirektLumen = 0,
  double indirektFaktor = 0.5,
  double randabstand = 0,
}) {
  final xs = umriss.map((p) => p.x), ys = umriss.map((p) => p.y);
  final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max), y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
  final flaeche = polygonFlaeche(umriss).abs() / 1e6; // m²
  final indirekt = flaeche <= 0 ? 0.0 : indirektLumen * indirektFaktor / flaeche;
  final zellen = <(Punkt, double)>[];
  for (var y = y0 + raster / 2; y < y1; y += raster) {
    for (var x = x0 + raster / 2; x < x1; x += raster) {
      final p = Punkt(x, y);
      if (!punktInPolygon(p, umriss)) continue;
      if (randabstand > 0 && _randDistanz(p, umriss) < randabstand) continue;
      zellen.add((p, beleuchtungsstaerke(p, leuchten, arbeitsebene: arbeitsebene) + indirekt));
    }
  }
  return LichtErgebnis(zellen, raster);
}

double _randDistanz(Punkt p, List<Punkt> umriss) {
  var best = double.infinity;
  for (var i = 0; i < umriss.length; i++) {
    final a = umriss[i], b = umriss[(i + 1) % umriss.length];
    final ab = b - a;
    final l2 = ab.x * ab.x + ab.y * ab.y;
    final t = l2 == 0 ? 0.0 : (((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2).clamp(0.0, 1.0);
    best = math.min(best, (p - Punkt(a.x + ab.x * t, a.y + ab.y * t)).laenge);
  }
  return best;
}

/// Empfohlene mittlere Beleuchtungsstärke (lx) nach Raumname (Richtwerte für
/// Wohnräume, frei überschreibbar).
int zielBeleuchtung(String raumname) {
  final n = raumname.toLowerCase();
  if (n.contains('küche') || n.contains('kueche')) return 300;
  if (n.contains('büro') || n.contains('arbeit') || n.contains('werk')) return 500;
  if (n.contains('bad') || n.contains('wc') || n.contains('dusch')) return 200;
  if (n.contains('flur') || n.contains('diele') || n.contains('treppe') || n.contains('abstell')) return 100;
  if (n.contains('schlaf') || n.contains('kind')) return 150;
  if (n.contains('technik') || n.contains('keller') || n.contains('hwr') || n.contains('heiz')) return 200;
  return 200; // Wohnen, Essen …
}

/// Farbe der Lichtverteilung: Anteil am Zielwert → dunkelblau … gelb … weiß (als ARGB).
int lichtFarbe(double lux, double ziel) {
  final t = ziel <= 0 ? 0.0 : (lux / ziel).clamp(0.0, 2.0) / 2;
  // 0 … 0.5: blau → gelb, 0.5 … 1: gelb → weiß
  int mix(int a, int b, double f) => (a + (b - a) * f).round();
  if (t < 0.5) {
    final f = t / 0.5;
    return 0xA0000000 | (mix(0x1C, 0xFF, f) << 16) | (mix(0x3D, 0xD4, f) << 8) | mix(0x8C, 0x3B, f);
  }
  final f = (t - 0.5) / 0.5;
  return 0xA0000000 | (0xFF << 16) | (mix(0xD4, 0xFF, f) << 8) | mix(0x3B, 0xF5, f);
}

// ---------------------------------------------------------------- LED-Streifen

/// Netzteilgrößen (W), aufsteigend.
const netzteilGroessen = [15, 30, 60, 100, 150, 240, 320, 480, 600];

/// Größte sinnvolle Streifenlänge je Einspeisung (mm) nach Spannung
/// (Spannungsabfall bei üblichen 10–20 W/m).
int maxStreifenlaenge(String spannung) => switch (spannung) {
      '12 V' => 5000,
      '24 V' => 10000,
      '48 V' => 20000,
      '230 V' => 50000,
      _ => 10000,
    };

/// Prüfung eines LED-Streifens: Leistung, Netzteil mit 20 % Reserve,
/// nötige Einspeisungen und Hinweise.
({double leistung, int netzteil, int einspeisungen, List<String> hinweise}) ledPruefung(
    double laengeMm, double wattProMeter, String spannung) {
  final leistung = laengeMm / 1000 * wattProMeter;
  final noetig = leistung * 1.2;
  final netzteil = netzteilGroessen.firstWhere((g) => g >= noetig, orElse: () => netzteilGroessen.last);
  final max = maxStreifenlaenge(spannung);
  final einspeisungen = math.max(1, (laengeMm / max).ceil());
  return (
    leistung: leistung,
    netzteil: netzteil,
    einspeisungen: einspeisungen,
    hinweise: [
      if (laengeMm > max)
        'Streifen ${(laengeMm / 1000).toStringAsFixed(1).replaceAll('.', ',')} m länger als ${max ~/ 1000} m bei $spannung: $einspeisungen Einspeisungen vorsehen (Spannungsabfall).',
      if (noetig > netzteilGroessen.last) 'Leistung zu groß für ein Netzteil – auf mehrere aufteilen.',
      if (spannung != '230 V') 'Netzteil zugänglich einbauen (Revisionsöffnung oder Verteiler).',
    ],
  );
}

// ---------------------------------------------------------------- Melder

/// Erfassungsdurchmesser (mm) eines Decken-Präsenzmelders je Bewegungsart
/// aus der Montagehöhe über FFB (Richtwerte, ersetzt nicht das Datenblatt).
({double praesenz, double quer, double frontal}) erfassung(double montagehoeheMm) {
  final h = math.max(0.0, montagehoeheMm);
  return (
    praesenz: math.max(0.0, (h - 800) * 1.5 + 800),
    quer: h * 3.5,
    frontal: h * 2.2,
  );
}

/// Rasterpunkte im Raum, die kein Melder (Mitte, Radius) erfasst.
List<Punkt> nichtErfasst(List<Punkt> umriss, List<(Punkt, double)> melder, {double raster = 250}) {
  final xs = umriss.map((p) => p.x), ys = umriss.map((p) => p.y);
  final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max), y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
  final frei = <Punkt>[];
  for (var y = y0 + raster / 2; y < y1; y += raster) {
    for (var x = x0 + raster / 2; x < x1; x += raster) {
      final p = Punkt(x, y);
      if (!punktInPolygon(p, umriss)) continue;
      if (!melder.any((m) => (m.$1 - p).laenge <= m.$2)) frei.add(p);
    }
  }
  return frei;
}
