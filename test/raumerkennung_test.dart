import 'package:bauspur/core/raumerkennung.dart';
import 'package:flutter_test/flutter_test.dart';

WandAchse w(num x1, num y1, num x2, num y2, [int d = 200]) =>
    WandAchse(Punkt(x1.toDouble(), y1.toDouble()), Punkt(x2.toDouble(), y2.toDouble()), d);

/// Rechteck aus vier Wänden, Achsmaß b × h.
List<WandAchse> rechteck(num x, num y, num b, num h, [int d = 200]) => [
      w(x, y, x + b, y, d),
      w(x + b, y, x + b, y + h, d),
      w(x + b, y + h, x, y + h, d),
      w(x, y + h, x, y, d),
    ];

void main() {
  test('Rechteck: lichte Fläche und Umfang', () {
    // Achsmaß 4200 × 3200, Wände 200 → licht 4000 × 3000
    final r = raeumeErkennen(rechteck(0, 0, 4200, 3200));
    expect(r.length, 1);
    expect(r.single.flaeche, closeTo(12e6, 1));
    expect(r.single.umfang, closeTo(14000, 0.01));
    expect(r.single.enthaelt(const Punkt(2100, 1600)), isTrue);
  });

  test('Zeichenrichtung egal (gegen den Uhrzeigersinn)', () {
    final r = raeumeErkennen([
      w(0, 0, 0, 3200),
      w(0, 3200, 4200, 3200),
      w(4200, 3200, 4200, 0),
      w(4200, 0, 0, 0),
    ]);
    expect(r.single.flaeche, closeTo(12e6, 1));
  });

  test('Offener Wandzug ergibt keinen Raum', () {
    expect(raeumeErkennen(rechteck(0, 0, 4000, 3000).take(3).toList()), isEmpty);
  });

  test('Innenwand mit T-Stößen teilt in zwei Räume', () {
    // Außen 6200 × 3200 (Achse), Innenwand bei x = 3100 von oben bis unten
    final r = raeumeErkennen([...rechteck(0, 0, 6200, 3200), w(3100, 0, 3100, 3200, 100)]);
    expect(r.length, 2);
    // links: licht x 100 … 3050, y 100 … 3100 → 2950 × 3000
    final flaechen = r.map((e) => e.flaeche.round()).toList()..sort();
    expect(flaechen, [8850000, 8850000]);
  });

  test('Lange Außenwand über mehrere Räume (Wand nicht geteilt gezeichnet)', () {
    // Außenwände als je eine Linie, Trennwand trifft mittendrin
    final r = raeumeErkennen([
      w(0, 0, 8000, 0),
      w(8000, 0, 8000, 4000),
      w(8000, 4000, 0, 4000),
      w(0, 4000, 0, 0),
      w(5000, 0, 5000, 4000, 100),
    ]);
    expect(r.length, 2);
  });

  test('Kreuzende Wände werden geteilt', () {
    final r = raeumeErkennen([
      ...rechteck(0, 0, 6000, 6000),
      w(3000, -500, 3000, 6500, 100), // ragt beidseitig über
      w(-500, 3000, 6500, 3000, 100),
    ]);
    expect(r.length, 4);
  });

  test('Wandstummel im Raum stört nicht', () {
    final r = raeumeErkennen([...rechteck(0, 0, 4200, 3200), w(2000, 0, 2000, 1000, 100)]);
    expect(r.length, 1);
    expect(r.single.flaeche, closeTo(12e6, 1));
  });

  test('L-förmiger Raum: Innenpunkt liegt im Raum', () {
    final r = raeumeErkennen([
      w(0, 0, 6000, 0),
      w(6000, 0, 6000, 2000),
      w(6000, 2000, 2000, 2000),
      w(2000, 2000, 2000, 6000),
      w(2000, 6000, 0, 6000),
      w(0, 6000, 0, 0),
    ]);
    expect(r.length, 1);
    final e = r.single;
    expect(e.enthaelt(e.innenpunkt), isTrue);
    // licht: (100…5900 × 100…1900) + (100…1900 × 1900…5900)
    expect(e.flaeche, closeTo(5800 * 1800 + 1800 * 4000, 1));
  });

  test('Unterschiedliche Wanddicken', () {
    final r = raeumeErkennen([
      w(0, 0, 4000, 0, 400), // Außenwand dick
      w(4000, 0, 4000, 3000, 100),
      w(4000, 3000, 0, 3000, 100),
      w(0, 3000, 0, 0, 100),
    ]);
    // licht x 50 … 3950, y 200 … 2950
    expect(r.single.flaeche, closeTo(3900 * 2750, 1));
  });

  test('Überlappend doppelt gezeichnete Wand', () {
    final r = raeumeErkennen([...rechteck(0, 0, 4200, 3200), w(1000, 0, 3000, 0)]);
    expect(r.length, 1);
    expect(r.single.flaeche, closeTo(12e6, 1));
  });

  test('Zwei getrennte Gebäudeteile', () {
    final r = raeumeErkennen([...rechteck(0, 0, 4200, 3200), ...rechteck(10000, 0, 2200, 2200)]);
    expect(r.length, 2);
  });
}
