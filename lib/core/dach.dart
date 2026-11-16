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
  pult('Pultdach'),
  walm('Walmdach'),
  krueppelwalm('Krüppelwalmdach'),
  zelt('Zeltdach'),
  mansard('Mansarddach');

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
    this.neigungUnten = 70,
    this.knick = 2300,
    this.krueppel = 1500,
    this.ueberstand = 500,
  });

  /// Mansarddach: Neigung des steilen unteren Teils (°) und Höhe des Knicks über dem Kniestock.
  final double neigungUnten;
  final int knick;

  /// Krüppelwalm: Höhe über dem Kniestock, ab der der Giebel abgewalmt ist.
  final int krueppel;

  /// Dachüberstand an Traufe und Ortgang (mm, waagrecht).
  final int ueberstand;

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
        'neigung_unten': neigungUnten,
        'knick': knick,
        'krueppel': krueppel,
        'ueberstand': ueberstand,
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
      neigungUnten: d('neigung_unten', 70),
      knick: i('knick', 2300),
      krueppel: i('krueppel', 1500),
      ueberstand: i('ueberstand', 500),
    );
  }
}

/// Umgrenzung des Gebäudes (Außenkanten) als Rechteck in mm: minX, minY, maxX, maxY.
typedef Gebaeuderahmen = ({double x0, double y0, double x1, double y1});

double _tan(DachEinstellung d) => math.tan(d.neigung.clamp(1, 80) * math.pi / 180);

/// Abstand von der (niedrigen) Traufe quer zum First.
double _vonTraufe(DachEinstellung d, Gebaeuderahmen g, Punkt p) {
  final (a, b, v) = d.firstInX ? (g.y0, g.y1, p.y) : (g.x0, g.x1, p.x);
  final (c, e, w) = d.firstInX ? (g.x0, g.x1, p.x) : (g.y0, g.y1, p.y);
  return switch (d.form) {
    Dachform.sattel || Dachform.mansard || Dachform.krueppelwalm => math.min(v - a, b - v),
    Dachform.pult => d.hochSeiteVorne ? b - v : v - a,
    Dachform.walm || Dachform.zelt => math.min(math.min(v - a, b - v), math.min(w - c, e - w)),
    Dachform.keins => double.infinity,
  };
}

/// Höhe der Dachfläche über dem Kniestock bei waagrechtem Abstand [x] zur Traufe.
double _anstieg(DachEinstellung d, double x) {
  if (d.form != Dachform.mansard) return x * _tan(d);
  final tu = math.tan(d.neigungUnten.clamp(1, 85) * math.pi / 180);
  final xk = d.knick / tu;
  return x <= xk ? x * tu : d.knick + (x - xk) * _tan(d);
}

/// Höhe der Dachfläche (Unterseite Sparren) über FFB an [p], ohne Kehlbalken;
/// auch außerhalb des Gebäudes (Überstand, dort unter dem Kniestock).
double dachFlaecheHoehe(DachEinstellung d, Gebaeuderahmen g, Punkt p) {
  final k = kniestockBei(d, g, p).toDouble();
  final x = _vonTraufe(d, g, p);
  var h = k + (x >= 0 ? _anstieg(d, x) : x * _tan(d));
  if (d.form == Dachform.krueppelwalm) {
    final (c, e, w) = d.firstInX ? (g.x0, g.x1, p.x) : (g.y0, g.y1, p.y);
    final giebel = math.min(w - c, e - w);
    h = math.min(h, k + d.krueppel + giebel * _tan(d));
  }
  return h;
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
  final h = math.max(kniestockBei(d, g, p).toDouble(), dachFlaecheHoehe(d, g, p));
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
    _ => const [],
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
    const {Dachform.sattel, Dachform.mansard, Dachform.krueppelwalm, Dachform.walm}.contains(d.form) ? (d.firstInX ? (g.y0 + g.y1) / 2 : (g.x0 + g.x1) / 2) : null;

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


/// Ein Holzteil des Dachstuhls: Strecke im Raum (Grundriss x/y, z über FFB des
/// Dachgeschosses), Querschnitt b×h, Name (Sparren, Gratsparren, Pfette …).
typedef Holzteil = ({String name, double x1, double y1, double z1, double x2, double y2, double z2, int b, int h});

/// Dachstuhl aus Dachform und Gebäuderahmen: Sparren (mit Überstand), Grat-
/// sparren, Fuß-, Mittel- und Firstpfetten, Kehlbalken. Vereinfacht für die
/// Mengen (Holzliste) und die 3D-Ansicht – keine Statik.
List<Holzteil> dachstuhl(DachEinstellung d, Gebaeuderahmen g) {
  if (!d.aktiv) return const [];
  final u = d.ueberstand.toDouble();
  final aus = <Holzteil>[];
  double z(double x, double y) => dachFlaecheHoehe(d, g, Punkt(x, y)) + d.sparrenHoehe;
  void teil(String n, double x1, double y1, double x2, double y2, {int? b, int? h, double? z1, double? z2}) =>
      aus.add((name: n, x1: x1, y1: y1, z1: z1 ?? z(x1, y1), x2: x2, y2: y2, z2: z2 ?? z(x2, y2), b: b ?? d.sparrenBreite, h: h ?? d.sparrenHoehe));
  final fx = d.firstInX;
  // längs = entlang First, quer = Richtung der Neigung
  final (l0, l1) = fx ? (g.x0, g.x1) : (g.y0, g.y1);
  final (q0, q1) = fx ? (g.y0, g.y1) : (g.x0, g.x1);
  (double, double) pt(double laengs, double quer) => fx ? (laengs, quer) : (quer, laengs);
  final qm = (q0 + q1) / 2;
  final walm = d.form == Dachform.walm || d.form == Dachform.zelt;
  final halb = (q1 - q0) / 2;
  for (final s in sparrenLagen(d, g)) {
    if (walm && (s - l0 < halb || l1 - s < halb)) {
      // Schifter: vom Grat zur Traufe
      final abstand = math.min(s - l0, l1 - s);
      for (final (von, bis) in [(q0 - u, q0 + abstand), (q1 + u, q1 - abstand)]) {
        final a = pt(s, von), b = pt(s, bis);
        teil('Schiftersparren', a.$1, a.$2, b.$1, b.$2);
      }
      continue;
    }
    if (d.form == Dachform.pult) {
      final a = pt(s, q0 - u), b = pt(s, q1 + u);
      teil('Sparren', a.$1, a.$2, b.$1, b.$2);
      continue;
    }
    for (final (von, bis) in [(q0 - u, qm), (q1 + u, qm)]) {
      final a = pt(s, von), b = pt(s, bis);
      teil('Sparren', a.$1, a.$2, b.$1, b.$2);
    }
  }
  // Walm: Schifter an den Walmseiten (quer zum First) und Gratsparren
  if (walm) {
    final grenze = math.min(halb, (l1 - l0) / 2);
    for (var q = q0 + d.sparrenBreite / 2 + d.sparrenVersatz; q <= q1 - d.sparrenBreite / 2 + 1; q += d.sparrenAbstand) {
      final tief = math.min(q - q0, q1 - q);
      for (final (von, bis) in [(l0 - u, l0 + math.min(tief, grenze)), (l1 + u, l1 - math.min(tief, grenze))]) {
        final a = pt(von, q), b = pt(bis, q);
        teil('Schiftersparren', a.$1, a.$2, b.$1, b.$2);
      }
    }
    final ra = l0 + grenze, re = l1 - grenze;
    for (final (ex, ey, fx2, fy2) in [
      (pt(l0, q0), pt(ra, qm)),
      (pt(l0, q1), pt(ra, qm)),
      (pt(l1, q0), pt(re, qm)),
      (pt(l1, q1), pt(re, qm)),
    ].map((e) => (e.$1.$1, e.$1.$2, e.$2.$1, e.$2.$2))) {
      teil('Gratsparren', ex, ey, fx2, fy2, b: d.sparrenBreite + 20, h: d.sparrenHoehe + 40);
    }
    if (re > ra + 1) {
      final a = pt(ra, qm), b = pt(re, qm);
      teil('Firstpfette', a.$1, a.$2, b.$1, b.$2, b: 120, h: 200);
    }
  } else if (d.form != Dachform.pult) {
    final a = pt(l0 - u, qm), b = pt(l1 + u, qm);
    teil('Firstpfette', a.$1, a.$2, b.$1, b.$2, b: 120, h: 200);
  }
  // Fußpfetten auf den Traufwänden (Höhe Kniestock)
  final k = d.kniestock.toDouble();
  for (final q in d.form == Dachform.pult ? [q0, q1] : [q0, q1]) {
    final a = pt(l0, q), b = pt(l1, q);
    teil('Fußpfette', a.$1, a.$2, b.$1, b.$2, b: 140, h: 140, z1: k, z2: k);
  }
  if (walm) {
    for (final l in [l0, l1]) {
      final a = pt(l, q0), b = pt(l, q1);
      teil('Fußpfette', a.$1, a.$2, b.$1, b.$2, b: 140, h: 140, z1: k, z2: k);
    }
  }
  // Mittelpfetten bei langen Sparren (> 4,5 m waagrecht)
  final spann = d.form == Dachform.pult ? (q1 - q0) : halb;
  if (spann > 4500 && !walm) {
    for (final q in d.form == Dachform.pult ? [(q0 + q1) / 2] : [q0 + halb / 2, q1 - halb / 2]) {
      final a = pt(l0, q), b = pt(l1, q);
      teil('Mittelpfette', a.$1, a.$2, b.$1, b.$2, b: 120, h: 200);
    }
  }
  // Kehlbalken
  if (d.kehlbalken > 0 && d.form != Dachform.pult) {
    final x = (d.kehlbalken - k) / _tan(d);
    if (x > 0 && x < halb) {
      for (final s in sparrenLagen(d, g)) {
        final a = pt(s, q0 + x), b = pt(s, q1 - x);
        teil('Kehlbalken', a.$1, a.$2, b.$1, b.$2, b: 80, h: 160, z1: d.kehlbalken.toDouble(), z2: d.kehlbalken.toDouble());
      }
    }
  }
  return aus;
}

/// Holzliste: Name, Querschnitt → (Anzahl, Gesamtlänge m).
Map<String, ({int anzahl, double meter})> holzliste(List<Holzteil> teile) {
  final m = <String, ({int anzahl, double meter})>{};
  for (final t in teile) {
    final l = math.sqrt(math.pow(t.x2 - t.x1, 2) + math.pow(t.y2 - t.y1, 2) + math.pow(t.z2 - t.z1, 2)) / 1000;
    final k = '${t.name} ${t.b}/${t.h}';
    final a = m[k];
    m[k] = (anzahl: (a?.anzahl ?? 0) + 1, meter: (a?.meter ?? 0) + l);
  }
  return m;
}
