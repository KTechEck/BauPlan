import 'package:bauspur/core/kennung.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('erste Kennung ist 01', () {
    expect(naechsteKennung(geschoss: 'EG', raum: 'BAD', typ: 'SD', vorhandene: const []), 'EG-BAD-SD-01');
  });

  test('nimmt die nächste freie Nummer nach der höchsten', () {
    expect(
      naechsteKennung(
        geschoss: 'eg',
        raum: 'bad',
        typ: 'sd',
        vorhandene: const ['EG-BAD-SD-01', 'EG-BAD-SD-03', 'EG-BAD-LE-07', 'OG-BAD-SD-09'],
      ),
      'EG-BAD-SD-04',
    );
  });

  test('Kürzelvorschläge', () {
    expect(kuerzelVorschlag('Wohnen'), 'WOH');
    expect(kuerzelVorschlag('Bad'), 'BAD');
    expect(kuerzelVorschlag('Bad oben'), 'BO');
    expect(kuerzelVorschlag('Küche'), 'KUE');
  });
}
