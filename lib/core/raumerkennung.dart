import 'dart:math' as math;

/// Punkt in Weltkoordinaten (mm). Rein rechnerisch, ohne Flutter.
class Punkt {
  const Punkt(this.x, this.y);
  final double x;
  final double y;

  Punkt operator +(Punkt o) => Punkt(x + o.x, y + o.y);
  Punkt operator -(Punkt o) => Punkt(x - o.x, y - o.y);
  Punkt operator *(double f) => Punkt(x * f, y * f);
  double get laenge => math.sqrt(x * x + y * y);
  double kreuz(Punkt o) => x * o.y - y * o.x;
  double skalar(Punkt o) => x * o.x + y * o.y;

  @override
  bool operator ==(Object other) => other is Punkt && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => '($x|$y)';
}

/// Eine Wand, wie die Raumerkennung sie braucht: Achse und Dicke.
class WandAchse {
  const WandAchse(this.a, this.b, this.dicke);
  final Punkt a;
  final Punkt b;
  final int dicke;
}

/// Ein erkannter Raum: Achsumriss (Wandmitten) und lichter Umriss
/// (Innenkante der Wände). Fläche in mm², Umfang in mm, beides licht.
class ErkannterRaum {
  ErkannterRaum({required this.achse, required this.licht});

  final List<Punkt> achse;
  final List<Punkt> licht;

  late final double flaeche = polygonFlaeche(licht).abs();
  late final double umfang = polygonUmfang(licht);
  late final Punkt innenpunkt = punktImInneren(licht);

  bool enthaelt(Punkt p) => punktInPolygon(p, licht);
}

// ------------------------------------------------------------- Polygone

/// Vorzeichenbehaftete Fläche (Gaußsche Trapezformel).
double polygonFlaeche(List<Punkt> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s / 2;
}

double polygonUmfang(List<Punkt> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    s += (p[(i + 1) % p.length] - p[i]).laenge;
  }
  return s;
}

bool punktInPolygon(Punkt q, List<Punkt> p) {
  var innen = false;
  for (var i = 0, j = p.length - 1; i < p.length; j = i++) {
    final a = p[i], b = p[j];
    if ((a.y > q.y) != (b.y > q.y) && q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x) {
      innen = !innen;
    }
  }
  return innen;
}

/// Ein Punkt sicher im Inneren (auch bei L- oder U-förmigen Räumen):
/// Schwerpunkt, wenn er innen liegt, sonst Mitte des breitesten Abschnitts
/// einer waagerechten Linie durch die Mitte der Höhe.
Punkt punktImInneren(List<Punkt> p) {
  if (p.isEmpty) return const Punkt(0, 0);
  final a = polygonFlaeche(p);
  if (a.abs() > 1e-9) {
    var cx = 0.0, cy = 0.0;
    for (var i = 0; i < p.length; i++) {
      final u = p[i], v = p[(i + 1) % p.length];
      final f = u.x * v.y - v.x * u.y;
      cx += (u.x + v.x) * f;
      cy += (u.y + v.y) * f;
    }
    final s = Punkt(cx / (6 * a), cy / (6 * a));
    if (punktInPolygon(s, p)) return s;
  }
  // Waagerechte Linien zwischen benachbarten Eckhöhen probieren.
  final ys = p.map((e) => e.y).toSet().toList()..sort();
  Punkt? bester;
  var breite = -1.0;
  for (var k = 0; k + 1 < ys.length; k++) {
    final y = (ys[k] + ys[k + 1]) / 2;
    final xs = <double>[];
    for (var i = 0; i < p.length; i++) {
      final u = p[i], v = p[(i + 1) % p.length];
      if ((u.y > y) != (v.y > y)) {
        xs.add(u.x + (y - u.y) * (v.x - u.x) / (v.y - u.y));
      }
    }
    xs.sort();
    for (var i = 0; i + 1 < xs.length; i += 2) {
      final b = xs[i + 1] - xs[i];
      final h = ys[k + 1] - ys[k];
      final mass = math.min(b, h * 4); // eher in breiten, hohen Bereichen
      if (mass > breite) {
        breite = mass;
        bester = Punkt((xs[i] + xs[i + 1]) / 2, y);
      }
    }
  }
  return bester ?? p.first;
}

// ------------------------------------------------------- Raumerkennung

/// Findet alle geschlossenen Flächen, die von Wandachsen umschlossen werden.
///
/// 1. Wände an allen Schnitt- und Stoßpunkten teilen (auch T-Stöße).
/// 2. Lose Enden entfernen (Wandstummel ohne Anschluss).
/// 3. Flächen des ebenen Graphen ablaufen; die Außenfläche fällt weg.
/// 4. Lichten Umriss bilden: jede Kante um die halbe Wanddicke nach innen.
List<ErkannterRaum> raeumeErkennen(List<WandAchse> waende, {double mindestFlaeche = 10000}) {
  final graph = _Graph();
  final segmente = waende.where((w) => (w.b - w.a).laenge >= 1).toList();

  // 1. Teilungspunkte je Wand sammeln (als Parameter t entlang der Achse).
  final teilung = [for (final _ in segmente) <double>{0, 1}];
  for (var i = 0; i < segmente.length; i++) {
    for (var j = i + 1; j < segmente.length; j++) {
      final (ti, tj) = _teilpunkte(segmente[i], segmente[j]);
      teilung[i].addAll(ti);
      teilung[j].addAll(tj);
    }
  }
  for (var i = 0; i < segmente.length; i++) {
    final w = segmente[i];
    final ts = teilung[i].toList()..sort();
    for (var k = 0; k + 1 < ts.length; k++) {
      final p = w.a + (w.b - w.a) * ts[k];
      final q = w.a + (w.b - w.a) * ts[k + 1];
      graph.kante(p, q, w.dicke);
    }
  }

  // 2. Lose Enden abschneiden.
  graph.loseEndenEntfernen();

  // 3. Flächen ablaufen.
  final raeume = <ErkannterRaum>[];
  for (final flaeche in graph.flaechen()) {
    final pts = [for (final k in flaeche) graph.knoten[k.$1]];
    final dicken = [for (final k in flaeche) k.$2];
    if (polygonFlaeche(pts) <= 0) continue; // Außenfläche je Zusammenhang
    final (achse, dk) = _geradeZusammenfassen(pts, dicken);
    if (achse.length < 3) continue;
    final licht = _nachInnenVersetzen(achse, dk);
    if (licht.length < 3 || polygonFlaeche(licht) < mindestFlaeche) continue;
    raeume.add(ErkannterRaum(achse: achse, licht: licht));
  }
  return raeume;
}

const _eps = 0.5; // mm

/// Teilungspunkte zweier Wandachsen als Parameter (auf a, auf b).
/// Kreuzungen, T-Stöße und Endberührungen zählen; liegen beide Wände auf
/// derselben Linie und überlappen, wird jede an den Enden der anderen geteilt.
(List<double>, List<double>) _teilpunkte(WandAchse a, WandAchse b) {
  final r = a.b - a.a;
  final s = b.b - b.a;
  final nenner = r.kreuz(s);
  final qp = b.a - a.a;
  final la = r.laenge, lb = s.laenge;
  final ta = _eps / la, tb = _eps / lb;
  if (nenner.abs() < 1e-9 * la * lb) {
    if (qp.kreuz(r).abs() / la > _eps) return (const [], const []); // parallel versetzt
    double aufA(Punkt p) => (p - a.a).skalar(r) / (la * la);
    double aufB(Punkt p) => (p - b.a).skalar(s) / (lb * lb);
    final ti = [aufA(b.a), aufA(b.b)].where((t) => t > -ta && t < 1 + ta).map((t) => t.clamp(0.0, 1.0));
    final tj = [aufB(a.a), aufB(a.b)].where((t) => t > -tb && t < 1 + tb).map((t) => t.clamp(0.0, 1.0));
    return (ti.toList(), tj.toList());
  }
  final t = qp.kreuz(s) / nenner;
  final u = qp.kreuz(r) / nenner;
  if (t < -ta || t > 1 + ta || u < -tb || u > 1 + tb) return (const [], const []);
  return ([t.clamp(0.0, 1.0)], [u.clamp(0.0, 1.0)]);
}

class _Graph {
  final knoten = <Punkt>[];
  final _index = <(int, int), int>{};
  final nachbarn = <int, Map<int, int>>{}; // knoten → (nachbar → dicke)

  int _knoten(Punkt p) {
    final key = (p.x.round(), p.y.round());
    return _index.putIfAbsent(key, () {
      knoten.add(Punkt(key.$1.toDouble(), key.$2.toDouble()));
      return knoten.length - 1;
    });
  }

  void kante(Punkt p, Punkt q, int dicke) {
    final a = _knoten(p), b = _knoten(q);
    if (a == b) return;
    final alt = nachbarn[a]?[b];
    final d = alt == null ? dicke : math.max(alt, dicke);
    (nachbarn[a] ??= {})[b] = d;
    (nachbarn[b] ??= {})[a] = d;
  }

  void loseEndenEntfernen() {
    var weiter = true;
    while (weiter) {
      weiter = false;
      for (final k in nachbarn.keys.toList()) {
        final n = nachbarn[k]!;
        if (n.length <= 1) {
          for (final m in n.keys) {
            nachbarn[m]?.remove(k);
          }
          nachbarn.remove(k);
          weiter = true;
        }
      }
    }
  }

  /// Alle Flächen als Liste (Startknoten, Dicke der Kante zum nächsten).
  List<List<(int, int)>> flaechen() {
    // Ausgehende Kanten je Knoten nach Winkel sortieren.
    final sortiert = <int, List<int>>{};
    nachbarn.forEach((k, n) {
      final p = knoten[k];
      sortiert[k] = n.keys.toList()
        ..sort((a, b) {
          final wa = math.atan2(knoten[a].y - p.y, knoten[a].x - p.x);
          final wb = math.atan2(knoten[b].y - p.y, knoten[b].x - p.x);
          return wa.compareTo(wb);
        });
    });
    final besucht = <(int, int)>{};
    final ergebnis = <List<(int, int)>>[];
    for (final u in sortiert.keys) {
      for (final v in sortiert[u]!) {
        if (besucht.contains((u, v))) continue;
        final flaeche = <(int, int)>[];
        var a = u, b = v;
        var schutz = 0;
        while (!besucht.contains((a, b)) && schutz++ < 100000) {
          besucht.add((a, b));
          flaeche.add((a, nachbarn[a]![b]!));
          // Am Knoten b: von der Rückkante (b→a) aus die nächste im Uhrzeigersinn
          // (vorherige im Winkel) nehmen – so liegt die Fläche links.
          final liste = sortiert[b]!;
          final i = liste.indexOf(a);
          final naechster = liste[(i - 1 + liste.length) % liste.length];
          a = b;
          b = naechster;
        }
        ergebnis.add(flaeche);
      }
    }
    return ergebnis;
  }
}

/// Fasst gerade durchlaufende Ecken gleicher Wanddicke zusammen.
(List<Punkt>, List<int>) _geradeZusammenfassen(List<Punkt> p, List<int> d) {
  var pts = List<Punkt>.of(p);
  var dk = List<int>.of(d);
  var geaendert = true;
  while (geaendert && pts.length > 3) {
    geaendert = false;
    for (var i = 0; i < pts.length; i++) {
      final vor = (i - 1 + pts.length) % pts.length;
      final nach = (i + 1) % pts.length;
      final e1 = pts[i] - pts[vor];
      final e2 = pts[nach] - pts[i];
      final gerade = e1.kreuz(e2).abs() <= 1e-6 * e1.laenge * e2.laenge && e1.skalar(e2) > 0;
      if (gerade && dk[vor] == dk[i]) {
        pts.removeAt(i);
        dk.removeAt(i);
        geaendert = true;
        break;
      }
    }
  }
  return (pts, dk);
}

/// Versetzt jede Kante um die halbe Wanddicke nach innen (links der
/// Laufrichtung) und schneidet benachbarte Kanten.
List<Punkt> _nachInnenVersetzen(List<Punkt> p, List<int> d) {
  final n = p.length;
  Punkt normale(int i) {
    final e = p[(i + 1) % n] - p[i];
    final l = e.laenge;
    return Punkt(-e.y / l, e.x / l);
  }

  final ergebnis = <Punkt>[];
  for (var i = 0; i < n; i++) {
    final vor = (i - 1 + n) % n;
    final n1 = normale(vor), n2 = normale(i);
    final a1 = p[vor] + n1 * (d[vor] / 2), r1 = p[i] - p[vor];
    final a2 = p[i] + n2 * (d[i] / 2), r2 = p[(i + 1) % n] - p[i];
    final nenner = r1.kreuz(r2);
    if (nenner.abs() < 1e-9 * r1.laenge * r2.laenge) {
      // gerade weiter mit anderer Dicke: kleiner Versatz
      ergebnis.add(p[i] + n1 * (d[vor] / 2));
      ergebnis.add(a2);
    } else {
      final t = (a2 - a1).kreuz(r2) / nenner;
      ergebnis.add(a1 + r1 * t);
    }
  }
  return ergebnis;
}
