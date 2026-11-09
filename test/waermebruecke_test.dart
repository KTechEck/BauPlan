import 'package:bauspur/core/waermebruecke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const wdvs = [
    WbSchicht('Außenputz', 10, 0.7),
    WbSchicht('EPS', 140, 0.035),
    WbSchicht('Kalksandstein', 175, 0.99),
    WbSchicht('Innenputz', 15, 0.7),
  ];

  test('U-Wert der Wand und Ersatz-λ', () {
    const d = EinbauDetail(schichten: wdvs);
    expect(d.wanddicke, 340);
    expect(d.uWand, closeTo(0.232, 0.005));
    expect(d.lambdaRahmen, closeTo(0.0991, 0.002));
  });

  test('Laibungsdämmung senkt Ψ und hebt fRsi', () {
    const ohne = EinbauDetail(schichten: wdvs, einbaulage: 160, laibungDaemmung: 0);
    const mit = EinbauDetail(schichten: wdvs, einbaulage: 160, laibungDaemmung: 40);
    final a = waermebrueckeBerechnen(ohne, h: 10);
    final b = waermebrueckeBerechnen(mit, h: 10);
    expect(a.psi, greaterThan(b.psi));
    expect(b.fRsi, greaterThanOrEqualTo(a.fRsi - 0.001));
    expect(b.psi, inInclusiveRange(-0.05, 0.12));
    expect(a.fRsi, inInclusiveRange(0.5, 1.0));
    expect(b.schimmelOk, isTrue);
  });

  test('Einbau in der Dämmebene ist besser als außen bündig im Mauerwerk', () {
    final daemmebene = waermebrueckeBerechnen(const EinbauDetail(schichten: wdvs, einbaulage: 110, laibungDaemmung: 40), h: 10);
    final mauerwerkInnen = waermebrueckeBerechnen(const EinbauDetail(schichten: wdvs, einbaulage: 230, laibungDaemmung: 0), h: 10);
    expect(daemmebene.psi, lessThan(mauerwerkInnen.psi));
  });

  test('Uw eingebaut und λ-Vorschläge', () {
    expect(uwEingebaut(uw: 0.8, breite: 1230, hoehe: 1480, psi: 0.04), closeTo(0.8 + 0.04 * 5.42 / 1.8204, 1e-6));
    expect(uwEingebaut(uw: 0.8, breite: 1230, hoehe: 1480, psi: 0.04, psiKasten: 0.1), greaterThan(uwEingebaut(uw: 0.8, breite: 1230, hoehe: 1480, psi: 0.04)));
    expect(lambdaVorschlag('EPS 035', 'Dämmung'), 0.035);
    expect(lambdaVorschlag('Kalksandstein', 'Mauerwerk'), 0.99);
    expect(lambdaVorschlag('Stahlbeton', 'Beton'), 2.3);
  });

  test('Beratung: schlechter Einbau bekommt Warnung mit umsetzbarem Vorschlag', () {
    const schlecht = EinbauDetail(schichten: wdvs, einbaulage: 230, laibungDaemmung: 0);
    final r = waermebrueckeBerechnen(schlecht, h: 10);
    final rat = waermebrueckeBeratung(schlecht, r);
    expect(rat.any((x) => x.stufe == 2 && x.aenderung != null), isTrue);
    expect(rat.any((x) => x.titel.contains('hinter der Dämmebene')), isTrue);
    const gut = EinbauDetail(schichten: wdvs, einbaulage: 110, laibungDaemmung: 40);
    final rg = waermebrueckeBeratung(gut, waermebrueckeBerechnen(gut, h: 10));
    expect(rg.where((x) => x.stufe == 2), isEmpty);
    expect(wbErklaerungen.length, 4);
  });
}
