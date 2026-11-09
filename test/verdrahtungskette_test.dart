import 'package:bauspur/core/verdrahtungskette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Kettenglied g(String id, String k, {String? von, int? adern}) =>
      (id: id, kennung: id, kuerzel: k, gespeistVon: von, adern: adern, querschnitt: 1.5, leistung: k == 'SD' ? 200 : 0);

  test('Aderbedarf: Schalter + Steckdose mit 3x1,5 nur, wenn die Leuchte ab hier versorgt wird', () {
    expect(aderBedarfRahmen(['TA', 'SD']), 3);
    expect(aderBedarfRahmen(['TA', 'SD'], leuchteAbHier: false), 4);
    expect(aderBedarf('TA', schaltung: Schaltung.wechsel), 5);
  });

  test('Kette: weitergeschleift, Hinweis auf zu wenig Adern', () {
    final alle = [g('a', 'SD'), g('b', 'SD', von: 'a'), g('c', 'TA', von: 'b', adern: 3)];
    expect(ketten(alle).single.map((x) => x.id), ['a', 'b', 'c']);
    final h = kettenHinweise(geraet: alle[2], imRahmen: ['TA', 'SD'], alle: alle, leuchteAbHier: false);
    expect(h.any((t) => t.contains('mindestens 4')), isTrue);
    expect(kettenHinweise(geraet: alle[0], imRahmen: ['SD'], alle: alle).any((t) => t.contains('Speist weiter: b, c')), isTrue);
  });
}
