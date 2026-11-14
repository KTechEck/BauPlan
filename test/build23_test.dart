import 'dart:io';

import 'package:bauspur/core/gebaeude.dart';
import 'package:bauspur/core/heizlast.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/wasser.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GEG, Schall, Sonnenschutz', () {
    expect(GegBauteil.aussenwand.uMax, 0.24);
    // U 1,4 → 0,24: R fehlt 1/0,24 − 1/1,4 = 3,452 → ×0,035 = 121 mm
    expect(gegZusatzDaemmung(1.4, GegBauteil.aussenwand), closeTo(120.8, 0.5));
    expect(gegZusatzDaemmung(0.2, GegBauteil.aussenwand), 0);
    // 17,5 cm KS (1800) + 2×1 cm Putz (1400) = 315 + 28 = 343 kg/m² → ca. 56 dB
    final m = flaechenMasse([(175, 1800), (10, 1400), (10, 1400)]);
    expect(m, closeTo(343, 0.5));
    expect(schalldaemmmass(m), closeTo(56.1, 0.3));
    expect(schallEmpfehlung('Schlafzimmer', 'Bad'), 47);
    expect(schallEmpfehlung('Flur', 'Wohnen'), isNull);
    expect(himmelsrichtung(0, 1), 'S'); // Normale nach unten auf dem Plan = Süden (Norden oben)
    expect(himmelsrichtung(1, 0), 'O');
    expect(himmelsrichtung(0, -1, nordGrad: 90), 'W');
    expect(fcSonnenschutz('Rollladen Alu'), 0.30);
    expect(sonneneintrag([(flaeche: 2, g: 0.6, fc: 1, richtung: 'S'), (flaeche: 2, g: 0.6, fc: 1, richtung: 'N')], 20), closeTo(0.06, 1e-9));
  });

  test('Treppe, Geländer, Sturz', () {
    final t = treppeAuslegen(geschosshoehe: 2800, lauflaenge: 3600);
    expect(t.stufen, 16);
    expect(t.steigung, 175);
    expect(t.auftritt, 240);
    expect(t.hinweise, isEmpty);
    final steil = treppeAuslegen(geschosshoehe: 2800, stufen: 12, lauflaenge: 2200);
    expect(steil.hinweise.any((h) => h.contains('Steigung')), isTrue);
    expect(gelaenderHinweise(absturzhoehe: 2800).single, contains('Geländer'));
    expect(gelaenderHinweise(absturzhoehe: 2800, hoehe: 850, stababstand: 150).length, 2);
    final s = sturzRichtwert(885);
    expect(s.laenge, 885 + 230);
    expect(sturzRichtwert(3000).art, contains('Statiker'));
  });

  test('Geschosse verknüpfen: Wand steht auf Wand, lösbar', () {
    final oben = [(id: 'o1', a: const Punkt(0, 0), b: const Punkt(4000, 0), dicke: 240), (id: 'o2', a: const Punkt(2000, 500), b: const Punkt(2000, 3000), dicke: 115)];
    final unten = [(id: 'u1', a: const Punkt(-100, 10), b: const Punkt(4100, 10), dicke: 240)];
    final v = wandVerknuepfungen(oben, unten);
    expect(v, {'o1': 'u1'});
    expect(wandVerknuepfungen(oben, unten, geloest: {'o1|u1'}), isEmpty);
  });

  test('Heizlast: Infiltration n50, Wärmerückgewinnung, Aufheizen', () {
    final r = HlRaum(id: 'r', name: 'Wohnen', umriss: const [Punkt(0, 0), Punkt(5000, 0), Punkt(5000, 4000), Punkt(0, 4000)], hoehe: 2500);
    // V = 50 m³, ΔT = 32 K
    expect(lueftungsLeistung(r, const HlParameter()), closeTo(0.34 * 25 * 32, 1e-6));
    // n50 = 6 → Infiltration 2·50·6·0,02 = 12 m³/h < 25 → Mindestluftwechsel bleibt
    expect(lueftungsLeistung(r, const HlParameter(n50: 6)), closeTo(0.34 * 25 * 32, 1e-6));
    // WRG 80 %: 12 (n50 6) + 25·0,2 = 17 m³/h
    expect(lueftungsLeistung(r, const HlParameter(n50: 6, wrg: 0.8)), closeTo(0.34 * 17 * 32, 1e-6));
    final e = heizlastBerechnen([r], const [], const [], const HlParameter(aufheiz: 10));
    expect(e.single.aufheiz, closeTo(200, 1e-6));
  });

  test('Wasser: Abwasser, Hausanschluss, Wassermelder-YAML, neue Typen', () {
    // Bad: WC 2,0 + WT 0,5 + Dusche 0,8 → Qww = max(0,5·√3,3; 2,0) = 2,0 → mit WC DN 90
    final a = abwasserPruefen(laengeM: 3, du: [2.0, 0.5, 0.8], mitWc: true, gefaelleProzent: 1, dn: 70);
    expect(a.qww, 2.0);
    expect(a.dnSoll, 90);
    expect(a.hoehenunterschied, 30);
    expect(a.hinweise.any((h) => h.contains('DN 70 zu klein')), isTrue);
    expect(abwasserNennweite(0.5), 50);
    expect(abwasserNennweite(3.0, fallleitung: true, mitWc: true), 100);
    final ha = hausanschluss(entnahmenAusObjekten(['WT', 'WT', 'DU', 'WA', 'WC']));
    expect(ha.summeVr, closeTo(0.07 * 4 + 0.15 * 2 + 0.15 * 2 + 0.13, 1e-9));
    expect(ha.zaehler, contains('Q3 = 4'));
    final y = wassermelderYaml('Haus', ['binary_sensor.wm_bad'], 'valve.haupt');
    expect(y, contains('valve.close_valve'));
    expect(y, contains('binary_sensor.wm_bad'));
    final tmp = Directory.systemTemp.createTempSync('bauspur_b23_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'W');
    try {
      final k = {for (final t in store.objekttypen()) t.kuerzel};
      expect(k.containsAll(['HA', 'TV', 'WM']), isTrue);
    } finally {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    }
  });
}
