/// Dachgeschoss: Dachform und Neigung, Kniestock, Sparrenlage, Zwischen- und
/// Untersparrendämmung, Kehlbalken und Dachfenster. Daraus: Höhe der Dachschräge
/// an jedem Punkt, Linien 1 m / 2 m im Grundriss, Wohnfläche nach WoFlV und der
/// U-Wert des Dachs.
library;

import 'dart:math' as math;

import 'raumerkennung.dart';

enum Dachform {
  keins('kein Dach / Flachdecke'),
  sattel('Satteldach'),
  pult('Pultdach');

  const Dachform(this.label);
  final String label;
}

class Dachfenster {
  const Dachfenster({required this.x, required this.y, this.breite = 780, this.hoehe = 1180, this.name = ''});
  final double x, y; // Mitte im Grundriss (mm)
  final int breite, hoehe; // Breite quer, Länge in Dachneigung
  final String name;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'b': breite, 'h': hoehe, if (name.isNotEmpty) 'name': name};
  static Dachfenster ausJson(Map<String, dynamic> m) => Dachfenster(
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        breite: (m['b'] as num?)?.toInt() ?? 780,
        hoehe: (m['h'] as num?)?.toInt() ?? 1180,
        name: m['name'] as String? ?? '',
      );
}

class DachEinstellung {
  const DachEinstellung({
    this.form = Dachform.keins,
    this.neigung = 40,
    this.firstInX = true,
    this.hochSeiteVorne = false,
    this.kniestock = 1000,
    this.sparrenAbstand = 700,
    this.sparrenBreite = 80,
    this.sparrenHoehe = 180,
    this.zwischenDicke = 180,
    this.zwischenLambda = 0.035,
    this.unterDicke = 0,
    this.unterLambda = 0.035,
    this.kehlbalken = 0,
    this.sparrenVersatz = 0,
    this.dachfenster = const [],
    this.abschnitte = const [],
  });

  /// Kniestock abschnittsweise entlang des Firsts (ab Giebel), je Traufseite.
  final List<KniestockAbschnitt> abschnitte;

  final Dachform form;
  final double neigung; // Grad
  /// First parallel zur x-Achse (Schräge steigt in y-Richtung), sonst parallel zu y.
  final bool firstInX;

  /// Pultdach: hohe Seite bei kleinem y bzw. x.
  final bool hochSeiteVorne;

  /// Höhe der Dachschräge an der Außenwand über FFB (Kniestock + Pfette), mm.
  final int kniestock;
  final int sparrenAbstand, sparrenBreite, sparrenHoehe;
  final int zwischenDicke;
  final double zwischenLambda;
  final int unterDicke;
  final double unterLambda;

  /// Kehlbalkenlage (Unterkante über FFB), 0 = offen bis zum First.
  final int kehlbalken;

  /// Verschiebung des Sparrenrasters (erster Sparren ab Giebel), mm.
  final int sparrenVersatz;
  final List<Dachfenster> dachfenster;

  bool get aktiv => form != Dachform.keins;

  Map<String, dynamic> toJson() => {
        'form': form.name,
        'neigung': neigung,
        'first_x': firstInX,
        'hoch_vorne': hochSeiteVorne,
        'kniestock': kniestock,
        'sp_abstand': sparrenAbstand,
        'sp_breite': sparrenBreite,
        'sp_hoehe': sparrenHoehe,
        'zw_dicke': zwischenDicke,
        'zw_lambda': zwischenLambda,
        'unter_dicke': unterDicke,
        'unter_lambda': unterLambda,
        'kehlbalken': kehlbalken,
        'sp_versatz': sparrenVersatz,
        'fenster': [for (final f in dachfenster) f.toJson()],
        'abschnitte': [for (final a in abschnitte) a.toJson()],
      };

  static DachEinstellung ausJson(Map<String, dynamic>? m) {
    if (m == null) return const DachEinstellung();
    double d(String k, double v) => (m[k] as num?)?.toDouble() ?? v;
    int i(String k, int v) => (m[k] as num?)?.toInt() ?? v;
    return DachEinstellung(
      form: Dachform.values.where((f) => f.name == m['form']).firstOrNull ?? Dachform.keins,
      neigung: d('neigung', 40),
      firstInX: m['first_x'] != false,
      hochSeiteVorne: m['hoch_vorne'] == true,
      kniestock: i('kniestock', 1000),
      sparrenAbstand: i('sp_abstand', 700),
      sparrenBreite: i('sp_breite', 80),
      sparrenHoehe: i('sp_hoehe', 180),
      zwischenDicke: i('zw_dicke', 180),
      zwischenLambda: d('zw_lambda', 0.035),
      unterDicke: i('unter_dicke', 0),
      unterLambda: d('unter_lambda', 0.035),
      kehlbalken: i('kehlbalken', 0),
      sparrenVersatz: i('sp_versatz', 0),
      dachfenster: [for (final f in (m['fenster'] as List? ?? const [])) Dachfenster.ausJson(Map<String, dynamic>.from(f as Map))],
      abschnitte: [for (final a in (m['abschnitte'] as List? ?? const [])) KniestockAbschnitt.ausJson(Map<String, dynamic>.from(a as Map))],
    );
  }
}

/// Umgrenzung des Gebäudes (Außenkanten) als Rechteck in mm: minX, minY, maxX, maxY.
typedef Gebaeuderahmen = ({double x0, double y0, double x1, double y1});

double _tan(DachEinstellung d) => math.tan(d.neigung.clamp(1, 80) * math.pi / 180);

/// Abstand von der (niedrigen) Traufe quer zum First.
double _vonTraufe(DachEinstellung d, Gebaeuderahmen g, Punkt p) {
  final (a, b, v) = d.firstInX ? (g.y0, g.y1, p.y) : (g.x0, g.x1, p.x);
  return switch (d.form) {
    Dachform.sattel => math.min(v - a, b - v),
    Dachform.pult => d.hochSeiteVorne ? b - v : v - a,
    Dachform.keins => double.infinity,
  };
}

/// Kniestock an [p]: Abschnitt entlang des Firsts und Traufseite (vorne = kleine Koordinate).
int kniestockBei(DachEinstellung d, Gebaeuderahmen g, Punkt p) {
  final laengs = d.firstInX ? p.x - g.x0 : p.y - g.y0;
  final (a, b, v) = d.firstInX ? (g.y0, g.y1, p.y) : (g.x0, g.x1, p.x);
  final vorne = d.form == Dachform.pult ? !d.hochSeiteVorne : v < (a + b) / 2;
  for (final s in d.abschnitte) {
    if (laengs >= s.von && laengs <= s.bis) return vorne ? s.vorne : s.hinten;
  }
  return d.kniestock;
}

/// Lichte Höhe unter der Dachschräge (bzw. Kehlbalken) über FFB an [p]; null ohne Dach.
double? dachHoehe(DachEinstellung d, Gebaeuderahmen g, Punkt p) {
  if (!d.aktiv) return null;
  final h = kniestockBei(d, g, p) + math.max(0.0, _vonTraufe(d, g, p)) * _tan(d);
  return d.kehlbalken > 0 ? math.min(h, d.kehlbalken.toDouble()) : h;
}

/// Lage der Linien, an denen die Schräge die Höhe [h] (mm über FFB) erreicht:
/// Koordinate quer zum First (y bei firstInX, sonst x). Ohne Abschnitte.
List<double> hoehenLinie(DachEinstellung d, Gebaeuderahmen g, double h, {int? vorne, int? hinten}) {
  if (!d.aktiv) return const [];
  final kv = vorne ?? d.kniestock, kh = hinten ?? d.kniestock;
  final (a, b) = d.firstInX ? (g.y0, g.y1) : (g.x0, g.x1);
  final av = (h - kv) / _tan(d), ah = (h - kh) / _tan(d);
  return switch (d.form) {
    Dachform.sattel => [if (h > kv && a + av < (a + b) / 2) a + av, if (h > kh && b - ah > (a + b) / 2) b - ah],
    Dachform.pult => [if (h > kv && av < b - a) (d.hochSeiteVorne ? b - av : a + av)],
    Dachform.keins => const [],
  };
}

/// Höhenlinien abschnittsweise: (längs von, längs bis, quer) in Plankoordinaten.
List<(double, double, double)> hoehenLinienAbschnitte(DachEinstellung d, Gebaeuderahmen g, double h) {
  if (!d.aktiv) return const [];
  final (l0, l1) = d.firstInX ? (g.x0, g.x1) : (g.y0, g.y1);
  // Grenzen der Abschnitte (relativ zum Giebel) in Plankoordinaten
  final grenzen = <double>{l0, l1};
  for (final s in d.abschnitte) {
    grenzen.add((l0 + s.von).clamp(l0, l1).toDouble());
    grenzen.add((l0 + s.bis).clamp(l0, l1).toDouble());
  }
  final g2 = grenzen.toList()..sort();
  final aus = <(double, double, double)>[];
  for (var i = 0; i + 1 < g2.length; i++) {
    final a = g2[i], b = g2[i + 1];
    if (b - a < 1) continue;
    final m = (a + b) / 2;
    final (qa, qb) = d.firstInX ? (g.y0, g.y1) : (g.x0, g.x1);
    Punkt bei(double quer) => d.firstInX ? Punkt(m, quer) : Punkt(quer, m);
    final kv = kniestockBei(d, g, bei(qa + 1)), kh = kniestockBei(d, g, bei(qb - 1));
    for (final q in hoehenLinie(d, g, h, vorne: kv, hinten: kh)) {
      aus.add((a, b, q));
    }
  }
  return aus;
}

/// Sparrenachsen entlang des Firsts (x bei firstInX, sonst y).
List<double> sparrenLagen(DachEinstellung d, Gebaeuderahmen g) {
  if (!d.aktiv || d.sparrenAbstand < 200) return const [];
  final (a, b) = d.firstInX ? (g.x0, g.x1) : (g.y0, g.y1);
  final l = <double>[];
  for (var v = a + d.sparrenBreite / 2 + d.sparrenVersatz; v <= b - d.sparrenBreite / 2 + 1; v += d.sparrenAbstand) {
    l.add(v);
  }
  return l;
}

/// Firstlinie (Koordinate quer zum First), null beim Pultdach.
double? firstLage(DachEinstellung d, Gebaeuderahmen g) =>
    d.form == Dachform.sattel ? (d.firstInX ? (g.y0 + g.y1) / 2 : (g.x0 + g.x1) / 2) : null;

/// Wohnfläche nach WoFlV: unter 1 m nicht, 1–2 m zur Hälfte, ab 2 m voll (m²).
({double grund, double wohn, double unter1, double zwischen}) wohnflaeche(List<Punkt> umriss, DachEinstellung d, Gebaeuderahmen g, {double raster = 100}) {
  final grund = polygonFlaeche(umriss).abs() / 1e6;
  if (!d.aktiv || umriss.length < 3) return (grund: grund, wohn: grund, unter1: 0, zwischen: 0);
  final xs = umriss.map((p) => p.x), ys = umriss.map((p) => p.y);
  final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max), y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
  var voll = 0.0, halb = 0.0, null1 = 0.0;
  final zelle = raster * raster / 1e6;
  for (var y = y0 + raster / 2; y < y1; y += raster) {
    for (var x = x0 + raster / 2; x < x1; x += raster) {
      final p = Punkt(x, y);
      if (!punktInPolygon(p, umriss)) continue;
      final h = dachHoehe(d, g, p)!;
      if (h >= 2000) {
        voll += zelle;
      } else if (h >= 1000) {
        halb += zelle;
      } else {
        null1 += zelle;
      }
    }
  }
  // auf die genaue Grundfläche skalieren (Rasterfehler)
  final summe = voll + halb + null1;
  final k = summe > 0 ? grund / summe : 1;
  return (grund: grund, wohn: (voll + halb / 2) * k, unter1: null1 * k, zwischen: halb * k);
}

/// U-Wert des Dachs (vereinfacht, Parallelschaltung Sparren/Gefach, Rsi 0,10, Rse 0,04
/// bei belüftetem Dach mit Hinterlüftung).
double uDach(DachEinstellung d) {
  const rsi = 0.10, rse = 0.04, lambdaHolz = 0.13;
  final anteil = (d.sparrenBreite / math.max(1, d.sparrenAbstand)).clamp(0.0, 1.0);
  final unter = d.unterDicke / 1000 / d.unterLambda;
  final dZw = math.min(d.zwischenDicke, d.sparrenHoehe) / 1000;
  final rGefach = rsi + rse + unter + dZw / d.zwischenLambda;
  final rSparren = rsi + rse + unter + d.sparrenHoehe / 1000 / lambdaHolz;
  return anteil / rSparren + (1 - anteil) / rGefach;
}

/// Dachfläche über einer Grundfläche (geneigt), m².
double dachflaecheUeber(double grundM2, DachEinstellung d) => d.aktiv ? grundM2 / math.cos(d.neigung.clamp(0, 80) * math.pi / 180) : grundM2;

/// Kniestock-Abschnitt entlang des Firsts (mm ab Giebel), Höhe je Traufseite.
class KniestockAbschnitt {
  const KniestockAbschnitt({required this.von, required this.bis, required this.vorne, required this.hinten});
  final double von, bis;
  final int vorne, hinten;

  Map<String, dynamic> toJson() => {'von': von, 'bis': bis, 'vorne': vorne, 'hinten': hinten};
  static KniestockAbschnitt ausJson(Map<String, dynamic> m) => KniestockAbschnitt(
        von: (m['von'] as num?)?.toDouble() ?? 0,
        bis: (m['bis'] as num?)?.toDouble() ?? 0,
        vorne: (m['vorne'] as num?)?.toInt() ?? 1000,
        hinten: (m['hinten'] as num?)?.toInt() ?? (m['vorne'] as num?)?.toInt() ?? 1000,
      );
}
