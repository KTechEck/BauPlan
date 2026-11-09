import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/wandmasse.dart';
import 'package:flutter_test/flutter_test.dart';

WandAchse w(num x1, num y1, num x2, num y2, [int d = 200]) =>
    WandAchse(Punkt(x1.toDouble(), y1.toDouble()), Punkt(x2.toDouble(), y2.toDouble()), d);

void main() {
  test('Freie Wand: beide Seiten so lang wie die Achse', () {
    final a = w(0, 0, 3000, 0);
    expect(flankenLaengen(a, [a]), (3000.0, 3000.0));
  });

  test('L-Ecke: außen länger, innen kürzer', () {
    final a = w(0, 0, 4000, 0);
    final b = w(4000, 0, 4000, 3000);
    // Ecke geht nach unten (rechts der Zeichenrichtung) → rechts innen
    final (links, rechts) = flankenLaengen(a, [a, b]);
    expect(links, closeTo(4100, 0.01));
    expect(rechts, closeTo(3900, 0.01));
  });

  test('Geschlossenes Rechteck: jede Wand innen −200, außen +200', () {
    final ws = [w(0, 0, 4200, 0), w(4200, 0, 4200, 3200), w(4200, 3200, 0, 3200), w(0, 3200, 0, 0)];
    final (l, r) = flankenLaengen(ws.first, ws);
    expect({l.round(), r.round()}, {4000, 4400});
  });

  test('T-Stoß: beide Seiten enden an der Oberfläche der durchlaufenden Wand', () {
    final aussen = w(0, 0, 6000, 0, 300);
    final innen = w(3000, 0, 3000, 2000, 100); // stößt mittig an
    final (l, r) = flankenLaengen(innen, [aussen, innen]);
    expect(l, closeTo(1850, 0.01));
    expect(r, closeTo(1850, 0.01));
  });

  test('Schräge Ecke (135°)', () {
    final a = w(0, 0, 3000, 0);
    final b = w(3000, 0, 5000, 2000); // 45° nach unten abknickend
    final (l, r) = flankenLaengen(a, [a, b]);
    expect(l, greaterThan(3000));
    expect(r, lessThan(3000));
    expect(l - 3000, closeTo(3000 - r, 0.01));
  });

  test('Umriss an einer L-Ecke: Außenecke trifft sich in einem Punkt (Gehrung)', () {
    final a = w(0, 0, 4000, 0);
    final b = w(4000, 0, 4000, 3000);
    final ua = wandUmriss(a, [a, b]);
    final ub = wandUmriss(b, [a, b]);
    // Außenecke (4100 | −100) bei beiden Wänden, Innenecke (3900 | 100)
    bool hat(List<Punkt> p, double x, double y) => p.any((e) => (e.x - x).abs() < 0.01 && (e.y - y).abs() < 0.01);
    expect(hat(ua, 4100, -100) && hat(ub, 4100, -100), isTrue);
    expect(hat(ua, 3900, 100) && hat(ub, 3900, 100), isTrue);
  });

  test('Umriss an schräger Ecke: Außenecke gemeinsam', () {
    final a = w(0, 0, 3000, 0);
    final b = w(3000, 0, 5000, 2000);
    final ua = wandUmriss(a, [a, b]);
    final ub = wandUmriss(b, [a, b]);
    final gemeinsam = ua.where((p) => ub.any((q) => (p - q).laenge < 0.01)).length;
    expect(gemeinsam, 2); // Außen- und Innenecke
  });

  test('T-Stoß aus zwei Wandstücken: Durchgang bleibt gerade, Abzweig stößt nur an', () {
    final links = w(0, 0, 3000, 0, 300), rechts = w(3000, 0, 6000, 0, 300), abzweig = w(3000, 0, 3000, 4000, 200);
    final alle = [links, rechts, abzweig];
    // Die beiden Stücke enden gerade an der Stoßstelle – keine Gehrung, keine Kerbe
    final gl = flankenGrenzen(links, alle);
    expect(gl.linksB, 3000);
    expect(gl.rechtsB, 3000);
    final gr = flankenGrenzen(rechts, alle);
    expect(gr.linksA, 0);
    expect(gr.rechtsA, 0);
    // Der Abzweig endet beidseitig an der Oberfläche der durchgehenden Wand (150 mm)
    final ga = flankenGrenzen(abzweig, alle);
    expect(ga.linksA, closeTo(150, 0.01));
    expect(ga.rechtsA, closeTo(150, 0.01));
  });
}
