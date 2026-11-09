import 'raumerkennung.dart';

/// Wo die beiden Wandseiten (Flanken) beginnen und enden, als Parameter
/// entlang der Achse ab A (0 … Achslänge, an Ecken auch darüber hinaus).
/// An einer Ecke ist die Innenseite kürzer, die Außenseite länger als die
/// Achse (Gehrung); an einem T-Stoß enden beide Seiten an der Oberfläche
/// der durchlaufenden Wand; freie Enden schließen rechtwinklig ab.
///
/// „links“ ist links der Zeichenrichtung auf dem Bildschirm (y nach unten),
/// also die Normale (u.y, −u.x) – wie bei der Schichtdarstellung.
({double linksA, double linksB, double rechtsA, double rechtsB}) flankenGrenzen(
    WandAchse w, Iterable<WandAchse> andere) {
  final d = w.b - w.a;
  final l = d.laenge;
  if (l < 1) return (linksA: 0, linksB: l, rechtsA: 0, rechtsB: l);
  final u = d * (1 / l);
  final nl = Punkt(u.y, -u.x);
  final h = w.dicke / 2;
  final nachbarnA = <WandAchse>[];
  final nachbarnB = <WandAchse>[];
  for (final o in andere) {
    if (identical(o, w)) continue;
    if (_beruehrt(o, w.a)) nachbarnA.add(o);
    if (_beruehrt(o, w.b)) nachbarnB.add(o);
  }
  return (
    linksA: _ende(w, u, nl, 1, h, l, w.a, nachbarnA, amAnfang: true),
    linksB: _ende(w, u, nl, 1, h, l, w.b, nachbarnB, amAnfang: false),
    rechtsA: _ende(w, u, nl, -1, h, l, w.a, nachbarnA, amAnfang: true),
    rechtsB: _ende(w, u, nl, -1, h, l, w.b, nachbarnB, amAnfang: false),
  );
}

/// Längen der beiden Wandseiten (siehe [flankenGrenzen]).
(double links, double rechts) flankenLaengen(WandAchse w, Iterable<WandAchse> andere) {
  final g = flankenGrenzen(w, andere);
  return (g.linksB - g.linksA, g.rechtsB - g.rechtsA);
}

/// Umriss der Wand als Viereck mit sauber verschnittenen Ecken:
/// links-Anfang, links-Ende, rechts-Ende, rechts-Anfang.
List<Punkt> wandUmriss(WandAchse w, Iterable<WandAchse> andere) {
  final d = w.b - w.a;
  final l = d.laenge;
  if (l < 1) return [w.a, w.b, w.b, w.a];
  final u = d * (1 / l);
  final nl = Punkt(u.y, -u.x);
  final h = w.dicke / 2;
  final g = flankenGrenzen(w, andere);
  final links = w.a + nl * h, rechts = w.a - nl * h;
  return [links + u * g.linksA, links + u * g.linksB, rechts + u * g.rechtsB, rechts + u * g.rechtsA];
}

const _toleranz = 1.0; // mm

bool _beruehrt(WandAchse o, Punkt p) {
  final d = o.b - o.a;
  final l2 = d.skalar(d);
  if (l2 == 0) return (o.a - p).laenge <= _toleranz;
  var t = (p - o.a).skalar(d) / l2;
  t = t.clamp(0.0, 1.0);
  return (o.a + d * t - p).laenge <= _toleranz;
}

/// Parameter t (entlang der Achse ab A), an dem die Flanke an einem Ende aufhört.
double _ende(WandAchse w, Punkt u, Punkt nl, double s, double h, double l, Punkt p, List<WandAchse> nachbarn,
    {required bool amAnfang}) {
  final grund = amAnfang ? 0.0 : l;
  if (nachbarn.isEmpty) return grund;
  bool endetBei(WandAchse o) => (o.a - p).laenge <= _toleranz || (o.b - p).laenge <= _toleranz;
  bool parallel(WandAchse a, WandAchse b) {
    final da = a.b - a.a, db = b.b - b.a;
    final la = da.laenge, lb = db.laenge;
    if (la < 1 || lb < 1) return false;
    return (da.kreuz(db) / (la * lb)).abs() < 1e-3;
  }

  // T-Stoß aus zwei Wandstücken: läuft diese Wand an P in einer gleich
  // gerichteten Wand weiter, ist der abzweigende Nachbar für dieses Ende
  // ohne Bedeutung – die Wand endet gerade und geht nahtlos weiter.
  if (nachbarn.any((o) => endetBei(o) && parallel(o, w))) return grund;
  final ursprung = w.a + nl * (s * h);
  double? ergebnis;
  for (final o in nachbarn) {
    final od = o.b - o.a;
    final ol = od.laenge;
    if (ol < 1) continue;
    final ou = od * (1 / ol);
    final onl = Punkt(ou.y, -ou.x);
    final ts = <double>[];
    for (final os in [1.0, -1.0]) {
      final q = o.a + onl * (os * o.dicke / 2);
      final nenner = u.kreuz(ou);
      if (nenner.abs() < 1e-9) continue; // parallel: läuft gerade weiter
      final t = (q - ursprung).kreuz(ou) / nenner;
      if ((t - grund).abs() <= 10 * (w.dicke + o.dicke) + 1) ts.add(t);
    }
    if (ts.isEmpty) continue;
    ts.sort();
    // Liegt der Nachbar (ganz oder teilweise) auf der Seite dieser Flanke,
    // stößt sie an ihn (innen); sonst läuft sie bis zur Gehrung (außen).
    final endetBeiP = (o.a - p).laenge <= _toleranz || (o.b - p).laenge <= _toleranz;
    bool aufDieserSeite;
    // Endet der Nachbar an P, läuft aber in einem gleich gerichteten Stück
    // weiter, ist er eine durchgehende Wand (T-Stoß): beide Seiten stoßen an.
    final durchgehend = endetBeiP && nachbarn.any((o2) => !identical(o2, o) && endetBei(o2) && parallel(o2, o));
    if (durchgehend) {
      aufDieserSeite = true;
    } else if (endetBeiP) {
      final fern = (o.a - p).laenge <= _toleranz ? o.b : o.a;
      aufDieserSeite = (fern - p).skalar(nl) * s > 0;
    } else {
      aufDieserSeite = true; // läuft durch: beide Seiten stoßen an
    }
    final innen = amAnfang ? ts.last : ts.first;
    final aussen = amAnfang ? ts.first : ts.last;
    final t = aufDieserSeite ? innen : aussen;
    ergebnis = ergebnis == null ? t : (amAnfang ? (t > ergebnis ? t : ergebnis) : (t < ergebnis ? t : ergebnis));
  }
  return ergebnis ?? grund;
}
