import 'package:bauspur/core/oberflaechen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bedarf aus Fläche, Verbrauch, Lagen und Anteil', () {
    final eig = beschichtungenSetzen(const {}, Flaechenart.waende, beschichtungsVorlagen['Anstrich (Grund + 2 × Farbe)']!);
    final l = beschichtungen(eig, Flaechenart.waende);
    expect(l.length, 2);
    // 4 × 3 m Raum, 2,5 m hoch: Umfang 14 m → 35 m² Wand
    final m2 = raumFlaeche(Flaechenart.waende, grundflaecheMm2: 12e6, umfangMm: 14000, lichteHoeheMm: 2500);
    expect(m2, closeTo(35, 1e-9));
    expect(l[1].bedarf(m2), closeTo(35 * 0.15 * 2, 1e-9));
    expect(const Beschichtung(verbrauch: 1.5, lagen: 2, anteil: 0.5).bedarf(10), closeTo(15, 1e-9));
  });
}
