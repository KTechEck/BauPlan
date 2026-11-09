import 'package:bauspur/core/fbh.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const raum = [Punkt(0, 0), Punkt(4000, 0), Punkt(4000, 3000), Punkt(0, 3000)];

  test('Rohrlänge entspricht etwa Fläche / Verlegeabstand', () {
    for (final m in Verlegemuster.values) {
      final e = FbhEinstellung(abstand: 150, rand: 100, muster: m);
      // verlegte Fläche 3,8 × 2,8 m = 10,64 m² → ≈ 70,9 m
      final l = rohrlaenge(raum, e) / 1000;
      expect(l, inInclusiveRange(62, 80), reason: m.name);
    }
  });

  test('Zuleitung zählt doppelt (Vor- und Rücklauf)', () {
    const e0 = FbhEinstellung(abstand: 200);
    const e1 = FbhEinstellung(abstand: 200, zuleitung: 5000);
    expect(rohrlaenge(raum, e1) - rohrlaenge(raum, e0), closeTo(10000, 0.01));
  });

  test('Nach innen versetzen verkleinert das Rechteck allseitig', () {
    final p = polygonNachInnen(raum, 100);
    expect(polygonFlaeche(p).abs(), closeTo(3800 * 2800, 1));
  });

  test('Mäander liefert Bahnen im Verlegeabstand', () {
    final b = verlegebild(raum, const FbhEinstellung(abstand: 200, muster: Verlegemuster.maeander));
    expect(b.length, 2); // Vorlauf und Rücklauf
    expect(b.first.length, greaterThan(20)); // 14 Bahnen à 2 Punkte
  });
}
