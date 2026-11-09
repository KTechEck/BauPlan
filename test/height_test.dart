import 'package:bauspur/core/height.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const eg = Bezugshoehen(rfb: 0, ffb: 135, rohdecke: 2635, meterriss: 1135);

  test('Steckdose 300 über FFB liegt 435 über RFB', () {
    expect(umrechnen(300, Hoehenbezug.ffb, Hoehenbezug.rfb, eg), 435);
  });

  test('1100 über FFB entspricht 100 über Meterriss', () {
    expect(umrechnen(1100, Hoehenbezug.ffb, Hoehenbezug.meterriss, eg), 100);
  });

  test('Unter Rohdecke wird nach unten gemessen', () {
    // Leuchtenauslass 2500 über FFB → 2635 - (135 + 2500) = 0 unter Rohdecke
    expect(umrechnen(2500, Hoehenbezug.ffb, Hoehenbezug.rohdecke, eg), 0);
    expect(umrechnen(200, Hoehenbezug.rohdecke, Hoehenbezug.ffb, eg), 2300);
  });

  test('Hin- und Rückrechnung ergibt den Ausgangswert', () {
    for (final von in Hoehenbezug.values) {
      for (final nach in Hoehenbezug.values) {
        final hin = umrechnen(777, von, nach, eg);
        expect(umrechnen(hin, nach, von, eg), 777, reason: '$von → $nach');
      }
    }
  });

  test('Raum mit höherem FFB verschiebt den Meterriss mit', () {
    final bad = eg.mitRaum(ffb: 155);
    expect(bad.ffb, 155);
    expect(bad.meterriss, 1155);
    expect(bad.rohdecke, 2635);
  });
}
