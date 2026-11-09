import 'dart:math' as math;

import 'raumerkennung.dart';

/// Fußbodenheizung: Verlegebild und Rohrlänge eines Heizkreises.
enum Verlegemuster {
  schnecke('Schnecke (bifilar)'),
  maeander('Mäander'),
  doppelmaeander('Doppelmäander');

  const Verlegemuster(this.label);
  final String label;
}

class FbhEinstellung {
  const FbhEinstellung({
    this.abstand = 150,
    this.rand = 100,
    this.muster = Verlegemuster.schnecke,
    this.zuleitung = 0,
    this.zugang = 0,
    this.randzone = 0,
    this.abstandRand = 100,
    this.sperren = const [],
  });

  /// Sperrflächen (Umrisse in mm), unter denen kein Rohr liegt – z. B. Küchenzeile, Dusche, Technikgerät.
  final List<List<Punkt>> sperren;

  final int abstand; // Verlegeabstand VA in mm
  final int rand; // Randabstand zur Wand in mm
  final Verlegemuster muster;
  final int zuleitung; // Zuleitung (einfach) in mm, wird doppelt gerechnet (Vor- und Rücklauf)
  final double zugang; // Lage des Zugangs als Anteil 0 … 1 entlang des Umrisses
  final int randzone; // Breite der Randzone mit engerem Abstand (0 = keine)
  final int abstandRand; // Verlegeabstand in der Randzone

  static FbhEinstellung ausJson(Map<String, dynamic> m) => FbhEinstellung(
        abstand: (m['va_mm'] as num?)?.toInt() ?? 150,
        rand: (m['rand_mm'] as num?)?.toInt() ?? 100,
        muster: Verlegemuster.values.where((v) => v.name == m['muster']).firstOrNull ?? Verlegemuster.schnecke,
        zuleitung: (m['zuleitung_mm'] as num?)?.toInt() ?? 0,
        zugang: (m['zugang'] as num?)?.toDouble() ?? 0,
        randzone: (m['randzone_mm'] as num?)?.toInt() ?? 0,
        abstandRand: (m['va_rand_mm'] as num?)?.toInt() ?? 100,
        sperren: [
          for (final k in (m['sperren'] as List? ?? const []))
            [for (final q in (k as List)) Punkt(((q as List)[0] as num).toDouble(), (q[1] as num).toDouble())],
        ],
      );
}

/// Richtwert für die maximale Kreislänge (inkl. Zuleitung).
const maxKreislaenge = 120000; // mm

/// Verschiebt alle Kanten eines Polygons um [d] nach innen (gleich für alle Kanten).
List<Punkt> polygonNachInnen(List<Punkt> umriss, double d) {
  var p = List<Punkt>.of(umriss);
  if (polygonFlaeche(p) < 0) p = p.reversed.toList();
  final n = p.length;
  if (n < 3) return const [];
  Punkt normale(int i) {
    final e = p[(i + 1) % n] - p[i];
    final l = e.laenge;
    return l < 1e-9 ? const Punkt(0, 0) : Punkt(-e.y / l, e.x / l);
  }

  final ergebnis = <Punkt>[];
  for (var i = 0; i < n; i++) {
    final vor = (i - 1 + n) % n;
    final n1 = normale(vor), n2 = normale(i);
    final a1 = p[vor] + n1 * d, r1 = p[i] - p[vor];
    final a2 = p[i] + n2 * d, r2 = p[(i + 1) % n] - p[i];
    final nenner = r1.kreuz(r2);
    if (nenner.abs() < 1e-9 * math.max(1, r1.laenge * r2.laenge)) {
      ergebnis.add(a2);
    } else {
      final t = (a2 - a1).kreuz(r2) / nenner;
      ergebnis.add(a1 + r1 * t);
    }
  }
  return ergebnis;
}

/// Verlegeplan eines Heizkreises: Vorlauf (vom Zugang hinein) und Rücklauf
/// (heraus zum Zugang) als Linienzüge in mm.
class Verlegeplan {
  const Verlegeplan(this.vl, this.rl);
  final List<Punkt> vl, rl;
  bool get leer => vl.length < 2;
  Punkt? get anschlussVl => vl.isEmpty ? null : vl.first;
  Punkt? get anschlussRl => rl.isEmpty ? null : rl.last;
}

/// Ring (versetzter Umriss) mit Längenparametrisierung.
class _Ring {
  _Ring(this.p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      kum.add(s);
      s += (p[(i + 1) % p.length] - p[i]).laenge;
    }
    laenge = s;
  }
  final List<Punkt> p;
  final List<double> kum = [];
  late final double laenge;

  Punkt bei(double s) {
    var r = ((s % laenge) + laenge) % laenge;
    for (var i = 0; i < p.length; i++) {
      final l = (p[(i + 1) % p.length] - p[i]).laenge;
      if (r <= l || i == p.length - 1) return l < 1e-9 ? p[i] : p[i] + (p[(i + 1) % p.length] - p[i]) * (r / l);
      r -= l;
    }
    return p.first;
  }

  double projektion(Punkt q) {
    var best = double.infinity, bs = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      final d = b - a;
      final l2 = d.skalar(d);
      if (l2 < 1e-9) continue;
      final t = ((q - a).skalar(d) / l2).clamp(0.0, 1.0);
      final abst = (a + d * t - q).laenge;
      if (abst < best) {
        best = abst;
        bs = kum[i] + t * math.sqrt(l2);
      }
    }
    return bs;
  }

  /// Punkte von s1 bis s2 (s2 > s1, darf über eine Runde hinausgehen).
  List<Punkt> abschnitt(double s1, double s2) {
    final l = <Punkt>[bei(s1)];
    for (var runde = 0; runde < 2; runde++) {
      for (var i = 0; i < p.length; i++) {
        final s = kum[i] + runde * laenge;
        if (s > s1 + 1e-6 && s < s2 - 1e-6) l.add(p[i]);
      }
    }
    l.add(bei(s2));
    return l;
  }
}

_Ring? _ringBei(List<Punkt> innen, double d, double vorherFlaeche, {List<List<Punkt>> sperren = const [], double rand = 0}) {
  var r = d <= 0 ? innen : polygonNachInnen(innen, d);
  if (r.length < 3) return null;
  // Sperrflächen: um den gleichen Versatz vergrößert aussparen (Ring läuft um sie herum)
  if (sperren.isNotEmpty) {
    if (polygonFlaeche(r) <= 1e4) return null;
    r = flaecheOhneSperren(r, sperren, rand: rand + d);
    if (r.length < 3) return null;
  }
  final f = polygonFlaeche(r);
  if (f <= 1e4 || f > vorherFlaeche + 1) return null; // kleiner als 1 dm² oder umgeklappt
  return _Ring(r);
}

/// Verlegeplan berechnen. Schnecke: bifilar (Vor- und Rücklauf laufen als
/// Band nebeneinander nach innen, in der Mitte die Umkehr) – Vor- und
/// Rücklauf liegen dadurch immer abwechselnd nebeneinander. Mäander: Bahnen
/// parallel zur längsten Kante, Rücklauf am Rand zurück. Doppelmäander: Vor-
/// und Rücklauf als Band im Mäander. Randzone: engerer Abstand am Rand.
Verlegeplan verlegeplan(List<Punkt> umriss, FbhEinstellung e) {
  if (umriss.length < 3 || e.abstand < 30) return const Verlegeplan([], []);
  var basis = List<Punkt>.of(umriss);
  if (polygonFlaeche(basis) < 0) basis = basis.reversed.toList();
  final innen = polygonNachInnen(basis, e.rand.toDouble());
  if (innen.length < 3 || polygonFlaeche(innen) <= 0) return const Verlegeplan([], []);
  final zugang = heizkreisZugang(basis, e.zugang, abstand: 0).mitte;
  // Mit Sperrflächen wird schneckenförmig um sie herum verlegt (Mäander-Reihen ließen sich nicht in einem Zug führen).
  if (e.sperren.isNotEmpty) return _schnecke(innen, zugang, e);
  return switch (e.muster) {
    Verlegemuster.schnecke => _schnecke(innen, zugang, e),
    Verlegemuster.maeander => _maeander(innen, zugang, e, doppelt: false),
    Verlegemuster.doppelmaeander => _maeander(innen, zugang, e, doppelt: true),
  };
}

double _va(FbhEinstellung e, double abstandVomRand) => e.randzone > 0 && abstandVomRand < e.randzone ? e.abstandRand.toDouble() : e.abstand.toDouble();

Verlegeplan _schnecke(List<Punkt> innen, Punkt zugang, FbhEinstellung e) {
  final a = <Punkt>[], b = <Punkt>[];
  var oA = 0.0;
  var flaeche = polygonFlaeche(innen) + 1;
  Punkt? endeA, endeB;
  var startA = zugang;
  for (var j = 0; j < 300; j++) {
    final va = _va(e, oA);
    final ringA = _ringBei(innen, oA, flaeche, sperren: e.sperren, rand: e.rand.toDouble());
    final ringB = ringA == null ? null : _ringBei(innen, oA + va, polygonFlaeche(ringA.p) + 1, sperren: e.sperren, rand: e.rand.toDouble());
    if (ringA == null || ringB == null) break;
    final w = math.min(2 * va, ringB.laenge / 4);
    // Startpunkt nahe am Start der vorigen Runde (folgt dem Zugang auch in verwinkelten Flächen)
    final sA = ringA.projektion(startA), sB = ringB.projektion(ringA.bei(sA));
    // zerfällt die Restfläche (z. B. zwischen zwei Sperrflächen), hier aufhören statt quer zu springen
    if (endeA != null && (ringA.bei(sA) - endeA).laenge > 3.5 * va) break;
    if (endeB != null && (ringB.bei(sB) - endeB).laenge > 3.5 * va) break;
    startA = ringB.bei(sB);
    // ohne Übergang ins Nächste: diese Runde bis kurz vor den Start
    final teilA = ringA.abschnitt(sA, sA + ringA.laenge - w);
    final teilB = ringB.abschnitt(sB, sB + ringB.laenge - w);
    a.addAll(teilA);
    b.addAll(teilB);
    endeA = teilA.last;
    endeB = teilB.last;
    flaeche = polygonFlaeche(ringB.p) + 1;
    oA += 2 * va;
  }
  if (a.isEmpty || endeA == null || endeB == null) return const Verlegeplan([], []);
  // Liegt das Ende des Rücklaufs weit weg (verwinkelte Restfläche), den Rücklauf
  // an der Stelle kürzen, die dem Ende des Vorlaufs am nächsten ist.
  if ((endeB - endeA).laenge > 2.5 * e.abstand && b.length >= 2) {
    var best = double.infinity, bi = b.length - 1;
    Punkt bp = b.last;
    for (var i = math.max(0, b.length - 60); i + 1 < b.length; i++) {
      final p0 = b[i], d = b[i + 1] - p0;
      final l2 = d.skalar(d);
      final t = l2 < 1e-9 ? 0.0 : ((endeA - p0).skalar(d) / l2).clamp(0.0, 1.0);
      final q = p0 + d * t;
      final ab = (q - endeA).laenge;
      if (ab < best) {
        best = ab;
        bi = i;
        bp = q;
      }
    }
    b
      ..removeRange(bi + 1, b.length)
      ..add(bp);
    endeB = bp;
  }
  // Umkehr in der Mitte: Vorlauf geht in den Rücklauf über
  final vl = [...a, endeB];
  final rl = b.reversed.toList();
  return Verlegeplan(vl, rl);
}

Verlegeplan _maeander(List<Punkt> innen, Punkt zugang, FbhEinstellung e, {required bool doppelt}) {
  // längste Kante waagerecht drehen
  var lang = 0.0, winkel = 0.0;
  for (var i = 0; i < innen.length; i++) {
    final d = innen[(i + 1) % innen.length] - innen[i];
    if (d.laenge > lang) {
      lang = d.laenge;
      winkel = math.atan2(d.y, d.x);
    }
  }
  final c = math.cos(-winkel), s = math.sin(-winkel);
  Punkt drehen(Punkt p, double c, double s) => Punkt(p.x * c - p.y * s, p.x * s + p.y * c);
  var poly = [for (final p in innen) drehen(p, c, s)];
  var z = drehen(zugang, c, s);
  // Zugang soll unten links liegen: notfalls spiegeln
  final xs0 = poly.map((p) => p.x), ys0 = poly.map((p) => p.y);
  final mx = (xs0.reduce(math.min) + xs0.reduce(math.max)) / 2, my = (ys0.reduce(math.min) + ys0.reduce(math.max)) / 2;
  final spiegelX = z.x > mx, spiegelY = z.y > my;
  Punkt sp(Punkt p) => Punkt(spiegelX ? 2 * mx - p.x : p.x, spiegelY ? 2 * my - p.y : p.y);
  poly = [for (final p in poly) sp(p)];
  z = sp(z);
  final minY = poly.map((p) => p.y).reduce(math.min), maxY = poly.map((p) => p.y).reduce(math.max);
  (double, double)? spanne(double y) {
    final xs = <double>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      if ((a.y > y) != (b.y > y)) xs.add(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y));
    }
    if (xs.length < 2) return null;
    xs.sort();
    return (xs.first, xs[1]);
  }

  final va = e.abstand.toDouble();
  final vl = <Punkt>[], rl = <Punkt>[];
  if (doppelt) {
    // Band aus Vorlauf (A) und Rücklauf (B), Reihen im Abstand 2·VA
    final a = <Punkt>[], b = <Punkt>[];
    // Reihen sammeln: (yA, yB, lo, hi)
    final reihen = <(double, double, double, double)>[];
    var k = 0;
    for (var y = minY + va / 2; y + va < maxY; y += 2 * va, k++) {
      final yA = k.isEven ? y : y + va, yB = k.isEven ? y + va : y;
      final sa = spanne(yA), sb = spanne(yB);
      if (sa == null || sb == null) break;
      final lo = math.max(sa.$1, sb.$1), hi = math.min(sa.$2, sb.$2);
      if (hi - lo < 3 * va) break;
      reihen.add((yA, yB, lo, hi));
    }
    for (var i = 0; i < reihen.length; i++) {
      final r = reihen[i];
      // Wenden liegen senkrecht: gemeinsame Kante mit der Nachbarreihe der jeweiligen Wende
      final nl = i.isOdd ? i + 1 : i - 1, nr = i.isEven ? i + 1 : i - 1;
      var lo = r.$3, hi = r.$4;
      if (nl >= 0 && nl < reihen.length) lo = math.max(lo, reihen[nl].$3);
      if (nr >= 0 && nr < reihen.length) hi = math.min(hi, reihen[nr].$4);
      // verschachtelte Bögen: rechts liegt A außen, links B außen
      final loA = i == 0 ? lo : lo + va;
      if (i.isEven) {
        a.addAll([Punkt(loA, r.$1), Punkt(hi, r.$1)]);
        b.addAll([Punkt(lo, r.$2), Punkt(hi - va, r.$2)]);
      } else {
        a.addAll([Punkt(hi, r.$1), Punkt(loA, r.$1)]);
        b.addAll([Punkt(hi - va, r.$2), Punkt(lo, r.$2)]);
      }
    }
    if (a.length < 2) return const Verlegeplan([], []);
    // Umkehr am Ende ohne Schräge
    final ecke = reihen.length.isOdd ? Punkt(a.last.x, b.last.y) : Punkt(b.last.x, a.last.y);
    vl.addAll([...a, ecke, b.last]);
    rl.addAll(b.reversed);
  } else {
    // einfacher Mäander: Bahnen im Abstand VA ab Spalte x0 + VA, Rücklauf am linken Rand zurück
    var k = 0;
    double? letzteY;
    final x0 = poly.map((p) => p.x).reduce(math.min);
    for (var y = minY + va / 2; y < maxY; y += va, k++) {
      final sp1 = spanne(y);
      if (sp1 == null) continue;
      final lo = math.max(sp1.$1, x0 + va), hi = sp1.$2;
      if (hi - lo < va) continue;
      vl.addAll(k.isEven ? [Punkt(lo, y), Punkt(hi, y)] : [Punkt(hi, y), Punkt(lo, y)]);
      letzteY = y;
    }
    if (vl.length < 2 || letzteY == null) return const Verlegeplan([], []);
    // Rücklauf: vom Ende zurück an den linken Rand und daran entlang zum Zugang
    final ende = vl.last;
    final xr = x0 + va / 2;
    // über eine eigene Bahn oberhalb der letzten Reihe und dann am Rand entlang
    rl.addAll([ende, Punkt(ende.x, ende.y + va / 2), Punkt(xr, ende.y + va / 2), Punkt(xr, minY + va / 2)]);
  }
  final cz = math.cos(winkel), sz = math.sin(winkel);
  List<Punkt> zurueck(List<Punkt> l) => [for (final p in l) drehen(sp(p), cz, sz)];
  return Verlegeplan(zurueck(vl), zurueck(rl));
}

/// Verlegebild als Linienzüge (Vorlauf, Rücklauf).
List<List<Punkt>> verlegebild(List<Punkt> umriss, FbhEinstellung e) {
  final p = verlegeplan(umriss, e);
  return p.leer ? const [] : [p.vl, p.rl];
}

/// Rohrlänge in mm: Verlegebild plus Vor- und Rücklauf der Zuleitung.
double rohrlaenge(List<Punkt> umriss, FbhEinstellung e) {
  var l = 0.0;
  for (final zug in verlegebild(umriss, e)) {
    for (var i = 0; i + 1 < zug.length; i++) {
      l += (zug[i + 1] - zug[i]).laenge;
    }
  }
  return l + 2 * e.zuleitung;
}

/// Zugang des Heizkreises (wo Vor- und Rücklauf in die Fläche gehen) als
/// Anteil 0 … 1 entlang des Umrisses. Liefert den Punkt auf dem Umriss und
/// die beiden Anschlusspunkte VL/RL im Abstand [abstand] links/rechts davon.
({Punkt mitte, Punkt vl, Punkt rl}) heizkreisZugang(List<Punkt> umriss, double anteil, {double abstand = 75}) {
  final n = umriss.length;
  var gesamt = 0.0;
  for (var i = 0; i < n; i++) {
    gesamt += (umriss[(i + 1) % n] - umriss[i]).laenge;
  }
  Punkt bei(double s) {
    var rest = ((s % gesamt) + gesamt) % gesamt;
    for (var i = 0; i < n; i++) {
      final a = umriss[i], b = umriss[(i + 1) % n];
      final l = (b - a).laenge;
      if (rest <= l || i == n - 1) return l < 1e-9 ? a : a + (b - a) * (rest / l);
      rest -= l;
    }
    return umriss.first;
  }

  if (n < 2 || gesamt <= 0) return (mitte: umriss.first, vl: umriss.first, rl: umriss.first);
  final s = anteil.clamp(0.0, 1.0) * gesamt;
  return (mitte: bei(s), vl: bei(s - abstand), rl: bei(s + abstand));
}

/// Anteil des Umrisses, der einem Punkt am nächsten liegt (für „Zugang hier“).
double zugangAnteil(List<Punkt> umriss, Punkt p) {
  final n = umriss.length;
  var gesamt = 0.0, bester = double.infinity, besterS = 0.0;
  for (var i = 0; i < n; i++) {
    final a = umriss[i], b = umriss[(i + 1) % n];
    final d = b - a;
    final l = d.laenge;
    if (l < 1e-9) continue;
    final t = ((p - a).skalar(d) / (l * l)).clamp(0.0, 1.0);
    final q = a + d * t;
    final abstand = (q - p).laenge;
    if (abstand < bester) {
      bester = abstand;
      besterS = gesamt + t * l;
    }
    gesamt += l;
  }
  return gesamt == 0 ? 0 : besterS / gesamt;
}

/// Anschlusspunkte Vor- und Rücklauf eines Heizkreises (Rohranfang/-ende im Verlegeplan).
({Punkt vl, Punkt rl})? heizkreisAnschluesse(List<Punkt> umriss, Map<String, dynamic> eigenschaften) {
  final p = verlegeplan(umriss, FbhEinstellung.ausJson(eigenschaften));
  if (p.leer || p.rl.isEmpty) return null;
  return (vl: p.vl.first, rl: p.rl.last);
}

/// Materialfelder eines Heizkreises (Schlüssel in den Eigenschaften, Bezeichnung).
const fbhMaterialFelder = [
  ('heizrohr', 'Heizrohr'),
  ('systemplatte', 'Systemplatte / Tackerplatte'),
  ('befestigung', 'Rohrhalter / Tackernadeln'),
  ('randstreifen', 'Randdämmstreifen'),
  ('verschraubung', 'Klemmringverschraubung'),
];

/// Bedarf eines Heizkreises je Materialfeld: (Schlüssel, Menge, Einheit).
/// Rohr aus dem Verlegebild + Zuleitung (+5 %), Platte nach Fläche (+5 %),
/// Halter alle 50 cm Rohr, Randstreifen am Umfang (+10 %), 2 Verschraubungen.
List<(String, double, String)> fbhBedarf(List<Punkt> umriss, Map<String, Object?> eig) {
  if (umriss.length < 3) return const [];
  final e = FbhEinstellung.ausJson(eig);
  final rohr = rohrlaenge(umriss, e) / 1000;
  var umfang = 0.0;
  for (var i = 0; i < umriss.length; i++) {
    umfang += (umriss[(i + 1) % umriss.length] - umriss[i]).laenge;
  }
  return [
    ('heizrohr', (rohr * 1.05 * 10).ceilToDouble() / 10, 'm'),
    ('systemplatte', (polygonFlaeche(umriss).abs() / 1e6 * 1.05 * 10).ceilToDouble() / 10, 'm²'),
    ('befestigung', (rohr * 2).ceilToDouble(), 'Stk'),
    ('randstreifen', (umfang / 1000 * 1.1 * 10).ceilToDouble() / 10, 'm'),
    ('verschraubung', 2, 'Stk'),
  ];
}

/// Polygon auf die Seite x <= c (bzw. x >= c bei [rechts]) beschneiden.
List<Punkt> _schneiden(List<Punkt> p, double c, {required bool rechts}) {
  bool drin(Punkt q) => rechts ? q.x >= c : q.x <= c;
  final aus = <Punkt>[];
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    final da = drin(a), db = drin(b);
    if (da) aus.add(a);
    if (da != db && (b.x - a.x).abs() > 1e-9) {
      final t = (c - a.x) / (b.x - a.x);
      aus.add(Punkt(c, a.y + (b.y - a.y) * t));
    }
  }
  return aus;
}

/// Fläche in [n] Streifen gleicher Fläche teilen, quer zur längsten Kante.
List<List<Punkt>> flaecheTeilen(List<Punkt> umriss, int n) {
  if (n <= 1 || umriss.length < 3) return [umriss];
  var lang = 0.0, winkel = 0.0;
  for (var i = 0; i < umriss.length; i++) {
    final d = umriss[(i + 1) % umriss.length] - umriss[i];
    if (d.laenge > lang) {
      lang = d.laenge;
      winkel = math.atan2(d.y, d.x);
    }
  }
  final c = math.cos(-winkel), s = math.sin(-winkel);
  final poly = [for (final p in umriss) Punkt(p.x * c - p.y * s, p.x * s + p.y * c)];
  final gesamt = polygonFlaeche(poly).abs();
  final x0 = poly.map((p) => p.x).reduce(math.min), x1 = poly.map((p) => p.x).reduce(math.max);
  // Schnittlinien so suchen, dass links davon k/n der Fläche liegt
  final schnitte = <double>[];
  for (var k = 1; k < n; k++) {
    var lo = x0, hi = x1;
    for (var it = 0; it < 50; it++) {
      final m = (lo + hi) / 2;
      final l = _schneiden(poly, m, rechts: false);
      final f = l.length < 3 ? 0.0 : polygonFlaeche(l).abs();
      if (f < gesamt * k / n) {
        lo = m;
      } else {
        hi = m;
      }
    }
    schnitte.add((lo + hi) / 2);
  }
  final cz = math.cos(winkel), sz = math.sin(winkel);
  final teile = <List<Punkt>>[];
  for (var k = 0; k < n; k++) {
    var t = poly;
    if (k > 0) t = _schneiden(t, schnitte[k - 1], rechts: true);
    if (k < n - 1) t = _schneiden(t, schnitte[k], rechts: false);
    if (t.length < 3) continue;
    teile.add([for (final p in t) Punkt((p.x * cz - p.y * sz).roundToDouble(), (p.x * sz + p.y * cz).roundToDouble())]);
  }
  return teile;
}

/// Vorschlag für einen Raum: so viele Kreise, dass keiner länger als
/// [maxLaenge] (mm, inkl. Zuleitung) wird; Zugang jeweils zum [ziel] hin
/// (Heizkreisverteiler). Zuleitung grob als Luftlinie Zugang → Ziel.
List<(List<Punkt>, Map<String, Object?>)> heizkreiseVorschlagen(List<Punkt> raum, FbhEinstellung e,
    {Punkt? ziel, double maxLaenge = 100000, Map<String, Object?> basis = const {}}) {
  if (raum.length < 3) return const [];
  for (var n = 1; n <= 12; n++) {
    final teile = flaecheTeilen(raum, n);
    final aus = <(List<Punkt>, Map<String, Object?>)>[];
    var ok = true;
    for (final t in teile) {
      final zugang = ziel == null ? e.zugang : zugangAnteil(t, ziel);
      final zm = heizkreisZugang(t, zugang, abstand: 0).mitte;
      final zul = ziel == null ? e.zuleitung : ((zm.x - ziel.x).abs() + (zm.y - ziel.y).abs()).round();
      final eig = <String, Object?>{
        ...basis,
        'va_mm': e.abstand,
        'rand_mm': e.rand,
        'muster': e.muster.name,
        'randzone_mm': e.randzone,
        'va_rand_mm': e.abstandRand,
        'zugang': double.parse(zugang.toStringAsFixed(3)),
        'zuleitung_mm': zul,
      };
      final l = rohrlaenge(t, FbhEinstellung.ausJson(eig));
      if (l > maxLaenge) ok = false;
      aus.add((t, eig));
    }
    if (ok || n == 12) return aus;
  }
  return const [];
}

/// Tür als Durchgang für Anbindeleitungen: Mitte, Wandrichtung (Einheit), Wanddicke.
typedef Durchgang = ({Punkt mitte, Punkt richtung, double dicke});

List<Punkt> _rechtwinklig(Punkt a, Punkt b) => (a.x - b.x).abs() < 1 || (a.y - b.y).abs() < 1 ? [a, b] : [a, Punkt(b.x, a.y), b];

List<Punkt> _bereinigen(List<Punkt> l) {
  final aus = <Punkt>[];
  for (final p in l) {
    if (aus.isNotEmpty && (aus.last - p).laenge < 1) continue;
    // kollineare Zwischenpunkte entfernen
    if (aus.length >= 2) {
      final a = aus[aus.length - 2], b = aus.last;
      final k = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
      if (k.abs() < 1e-3 * (b - a).laenge * (p - a).laenge + 1e-6) aus.removeLast();
    }
    aus.add(p);
  }
  return aus;
}

/// Weg einer Anbindeleitung vom Zugang [start] zum Verteiler [ziel], rechtwinklig.
/// Liegt das Ziel außerhalb des [raum]s, führt der Weg durch die Tür, die den
/// kürzesten Gesamtweg ergibt; [versatz] verschiebt den Durchgang entlang der
/// Wand (Vor- und Rücklauf nebeneinander).
List<Punkt> anbindeweg(Punkt start, Punkt ziel, {List<Punkt>? raum, List<Durchgang> tueren = const [], double versatz = 0}) {
  if (raum == null || raum.length < 3 || punktInPolygon(ziel, raum) || tueren.isEmpty) {
    return _bereinigen(_rechtwinklig(start, ziel));
  }
  double randAbstand(Punkt q) {
    var best = double.infinity;
    for (var i = 0; i < raum.length; i++) {
      final a = raum[i], b = raum[(i + 1) % raum.length];
      final d = b - a;
      final l2 = d.skalar(d);
      if (l2 < 1e-9) continue;
      final t = ((q - a).skalar(d) / l2).clamp(0.0, 1.0);
      best = math.min(best, (a + d * t - q).laenge);
    }
    return best;
  }

  List<Punkt>? bester;
  var bestL = double.infinity;
  for (final t in tueren) {
    if (randAbstand(t.mitte) > t.dicke + 50) continue; // Tür gehört nicht zu diesem Raum
    final m = t.mitte + t.richtung * versatz;
    final n = Punkt(-t.richtung.y, t.richtung.x);
    final s = t.dicke / 2 + 250;
    var pin = m + n * s, pout = m - n * s;
    if (!punktInPolygon(pin, raum)) (pin, pout) = (pout, pin);
    final weg = _bereinigen([..._rechtwinklig(start, pin), pout, ..._rechtwinklig(pout, ziel).skip(1)]);
    var l = 0.0;
    for (var i = 0; i + 1 < weg.length; i++) {
      l += (weg[i + 1] - weg[i]).laenge;
    }
    if (l < bestL) {
      bestL = l;
      bester = weg;
    }
  }
  return bester ?? _bereinigen(_rechtwinklig(start, ziel));
}

/// Fläche ohne Sperrflächen (mit Randabstand [rand]) als einfacher, rechtwinklig
/// gerasterter Umriss: Rasterzellen im Umriss und außerhalb der Sperren bleiben;
/// eingeschlossene Sperren werden über einen schmalen Schlitz mit dem Rand
/// verbunden, damit das Rohr in einem Zug um sie herum läuft.
List<Punkt> flaecheOhneSperren(List<Punkt> umriss, List<List<Punkt>> sperren, {double rand = 100, double raster = 50}) {
  if (umriss.length < 3) return umriss;
  final xs = umriss.map((p) => p.x), ys = umriss.map((p) => p.y);
  final x0 = xs.reduce(math.min), y0 = ys.reduce(math.min);
  final nx = ((xs.reduce(math.max) - x0) / raster).ceil(), ny = ((ys.reduce(math.max) - y0) / raster).ceil();
  if (nx <= 0 || ny <= 0 || nx * ny > 400000) return umriss;

  final drin = List.generate(ny, (_) => List.filled(nx, false));
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      final q = Punkt(x0 + (i + 0.5) * raster, y0 + (j + 0.5) * raster);
      if (!punktInPolygon(q, umriss)) continue;
      var frei = true;
      for (final sp in sperren) {
        if (sp.length < 3) continue;
        // rechteckig vergrößert (Sperrflächen sind meist rechteckig: Küchenzeile, Dusche, Gerät)
        final sx = sp.map((p) => p.x), sy = sp.map((p) => p.y);
        if (q.x > sx.reduce(math.min) - rand && q.x < sx.reduce(math.max) + rand && q.y > sy.reduce(math.min) - rand && q.y < sy.reduce(math.max) + rand) {
          frei = false;
          break;
        }
      }
      drin[j][i] = frei;
    }
  }
  // größte zusammenhängende Fläche behalten
  final comp = List.generate(ny, (_) => List.filled(nx, -1));
  var besteId = -1, besteN = 0, id = 0;
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      if (!drin[j][i] || comp[j][i] >= 0) continue;
      var n = 0;
      final stapel = [(i, j)];
      comp[j][i] = id;
      while (stapel.isNotEmpty) {
        final (a, b) = stapel.removeLast();
        n++;
        for (final (da, db) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final c = a + da, d = b + db;
          if (c < 0 || d < 0 || c >= nx || d >= ny || !drin[d][c] || comp[d][c] >= 0) continue;
          comp[d][c] = id;
          stapel.add((c, d));
        }
      }
      if (n > besteN) {
        besteN = n;
        besteId = id;
      }
      id++;
    }
  }
  if (besteId < 0) return umriss;
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      drin[j][i] = comp[j][i] == besteId;
    }
  }
  // Löcher (leere Zellen, die nicht mit außen verbunden sind) per Schlitz nach links öffnen
  final aussen = List.generate(ny, (_) => List.filled(nx, false));
  final st = <(int, int)>[];
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      if ((i == 0 || j == 0 || i == nx - 1 || j == ny - 1) && !drin[j][i]) {
        aussen[j][i] = true;
        st.add((i, j));
      }
    }
  }
  while (st.isNotEmpty) {
    final (a, b) = st.removeLast();
    for (final (da, db) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final c = a + da, d = b + db;
      if (c < 0 || d < 0 || c >= nx || d >= ny || drin[d][c] || aussen[d][c]) continue;
      aussen[d][c] = true;
      st.add((c, d));
    }
  }
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      if (drin[j][i] || aussen[j][i]) continue;
      // Loch gefunden: ganze Lochfläche sammeln
      final loch = <(int, int)>[];
      final f = [(i, j)];
      aussen[j][i] = true;
      while (f.isNotEmpty) {
        final (a, b) = f.removeLast();
        loch.add((a, b));
        for (final (da, db) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final c = a + da, d = b + db;
          if (c < 0 || d < 0 || c >= nx || d >= ny || drin[d][c] || aussen[d][c]) continue;
          aussen[d][c] = true;
          f.add((c, d));
        }
      }
      // Insel bis zur nächsten Seite aussparen (volle Breite bzw. Höhe der Insel):
      // so entsteht eine Einbuchtung, um die das Rohr in einem Zug herum läuft.
      final i0 = loch.map((c) => c.$1).reduce(math.min), i1 = loch.map((c) => c.$1).reduce(math.max);
      final j0 = loch.map((c) => c.$2).reduce(math.min), j1 = loch.map((c) => c.$2).reduce(math.max);
      int weit(int di, int dj) {
        var n = 0;
        var ci = di < 0 ? i0 - 1 : (di > 0 ? i1 + 1 : (i0 + i1) ~/ 2);
        var cj = dj < 0 ? j0 - 1 : (dj > 0 ? j1 + 1 : (j0 + j1) ~/ 2);
        while (ci >= 0 && cj >= 0 && ci < nx && cj < ny && drin[cj][ci]) {
          n++;
          ci += di;
          cj += dj;
        }
        return n;
      }
      final richtungen = [(-1, 0), (1, 0), (0, -1), (0, 1)];
      final (di, dj) = richtungen.reduce((a, b) => weit(a.$1, a.$2) <= weit(b.$1, b.$2) ? a : b);
      void frei(int a, int b) {
        if (a < 0 || b < 0 || a >= nx || b >= ny) return;
        drin[b][a] = false;
        aussen[b][a] = true;
      }
      if (di != 0) {
        for (var b = j0; b <= j1; b++) {
          for (var a = di < 0 ? i0 - 1 : i1 + 1; a >= 0 && a < nx && drin[b][a]; a += di) {
            frei(a, b);
          }
        }
      } else {
        for (var a = i0; a <= i1; a++) {
          for (var b = dj < 0 ? j0 - 1 : j1 + 1; b >= 0 && b < ny && drin[b][a]; b += dj) {
            frei(a, b);
          }
        }
      }
    }
  }
  // Randkanten sammeln (Fläche links der Kante, Bildschirmkoordinaten)
  final naechste = <(int, int), (int, int)>{};
  bool z(int i, int j) => i >= 0 && j >= 0 && i < nx && j < ny && drin[j][i];
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      if (!drin[j][i]) continue;
      if (!z(i, j - 1)) naechste[(i, j)] = (i + 1, j); // oben: nach rechts
      if (!z(i + 1, j)) naechste[(i + 1, j)] = (i + 1, j + 1); // rechts: nach unten
      if (!z(i, j + 1)) naechste[(i + 1, j + 1)] = (i, j + 1); // unten: nach links
      if (!z(i - 1, j)) naechste[(i, j + 1)] = (i, j); // links: nach oben
    }
  }
  if (naechste.isEmpty) return umriss;
  final start = naechste.keys.first;
  final ring = <(int, int)>[start];
  var cur = naechste[start]!;
  var schutz = 0;
  while (cur != start && schutz++ < 1000000) {
    ring.add(cur);
    final n = naechste[cur];
    if (n == null) break;
    cur = n;
  }
  // kollineare Punkte weglassen
  final pts = <Punkt>[];
  for (var k = 0; k < ring.length; k++) {
    final a = ring[(k - 1 + ring.length) % ring.length], b = ring[k], c = ring[(k + 1) % ring.length];
    final kreuz = (b.$1 - a.$1) * (c.$2 - b.$2) - (b.$2 - a.$2) * (c.$1 - b.$1);
    if (kreuz != 0) pts.add(Punkt(x0 + b.$1 * raster, y0 + b.$2 * raster));
  }
  if (pts.length < 3) return umriss;
  return polygonFlaeche(pts) < 0 ? pts.reversed.toList() : pts;
}

/// Kreuzt sich das Rohr (Vorlauf → Umkehr → Rücklauf)? Für Hinweise in der Oberfläche.
int verlegeplanKreuzungen(Verlegeplan p) {
  final z = [...p.vl, ...p.rl];
  bool schneiden(Punkt a, Punkt b, Punkt c, Punkt d) {
    double k(Punkt o, Punkt p, Punkt q) => (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x);
    final d1 = k(c, d, a), d2 = k(c, d, b), d3 = k(a, b, c), d4 = k(a, b, d);
    return ((d1 > 1e-6 && d2 < -1e-6) || (d1 < -1e-6 && d2 > 1e-6)) && ((d3 > 1e-6 && d4 < -1e-6) || (d3 < -1e-6 && d4 > 1e-6));
  }
  var n = 0;
  for (var i = 0; i + 1 < z.length; i++) {
    for (var j = i + 2; j + 1 < z.length; j++) {
      if (schneiden(z[i], z[i + 1], z[j], z[j + 1])) n++;
    }
  }
  return n;
}

/// Aufstellfläche eines Geräts (Mitte, Breite b, Tiefe t, Drehung in Grad) als Umriss.
List<Punkt> aufstellflaeche(Punkt mitte, double b, double t, num drehungGrad) {
  final w = drehungGrad * math.pi / 180;
  final c = math.cos(w), s = math.sin(w);
  Punkt p(double u, double v) => Punkt(mitte.x + u * c - v * s, mitte.y + u * s + v * c);
  return [p(-b / 2, -t / 2), p(b / 2, -t / 2), p(b / 2, t / 2), p(-b / 2, t / 2)];
}

List<List<double>> _alsJson(List<Punkt> l) => [for (final q in l) [q.x.roundToDouble(), q.y.roundToDouble()]];

/// Sperrflächen als JSON für die Eigenschaften eines Heizkreises.
List<List<List<double>>> sperrenJson(List<List<Punkt>> l) => [for (final k in l) _alsJson(k)];
