import 'package:bauspur/core/drei_d.dart';
import 'package:bauspur/core/einkauf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Strecken im Raum: Abstand und Kollisionen', () {
    expect(streckenAbstand(const V3(0, 0, 0), const V3(1000, 0, 0), const V3(500, -500, 100), const V3(500, 500, 100)), closeTo(100, 1e-6));
    const a = Leitung3d(id: 'a', name: 'HZ-VL', punkte: [V3(0, 0, 300), V3(2000, 0, 300)], durchmesser: 20);
    const b = Leitung3d(id: 'b', name: 'TW', punkte: [V3(1000, -500, 310), V3(1000, 500, 310)], durchmesser: 22);
    const c = Leitung3d(id: 'c', name: 'Abwasser', punkte: [V3(1000, -500, 600), V3(1000, 500, 600)], durchmesser: 110);
    const speicher = Quader(id: 'q', name: 'Speicher', x: 1800, y: 0, z: 0, b: 600, t: 600, h: 1700);
    final k = kollisionen3d([speicher], [a, b, c]);
    expect(k.hinweise.any((h) => h.contains('HZ-VL und TW')), isTrue);
    expect(k.hinweise.any((h) => h.contains('Abwasser')), isFalse);
    expect(k.hinweise.any((h) => h.contains('läuft durch Speicher')), isTrue);
    expect(k.ids, containsAll(['a', 'b', 'q']));
    const kam = Kamera(azimut: 0, neigung: 0, ziel: V3(0, 0, 0));
    final (x, y, t) = kam.projizieren(const V3(1000, 0, 0));
    expect(x, greaterThan(0));
    expect(y, closeTo(0, 1e-9));
    expect(t, kam.abstand);
  });

  test('Formteile aus dem Leitungsverlauf schätzen', () {
    final m = formteileSchaetzen([
      (punkte: const [(0.0, 0.0), (2000.0, 0.0), (2000.0, 1500.0), (3000.0, 2500.0)], dimension: '16×2', anderLeitung: true),
    ]);
    expect(m['Winkel 90° · 16×2'], 1);
    expect(m['Winkel 45° · 16×2'], 1);
    expect(m['T-Stück · 16×2'], 1);
    expect(m['Rohrschelle · 16×2'], greaterThanOrEqualTo(5));
  });
}
