import 'dart:convert';
import 'dart:io';

import 'package:bauspur/core/auslegung.dart';
import 'package:bauspur/core/auslegung_projekt.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schrank_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kabel: Belastbarkeit, Faktoren, Spannungsfall, Vorschlag', () {
    expect(belastbarkeit(Verlegeart.c, 1.5, drehstrom: false), 19.5);
    expect(belastbarkeit(Verlegeart.b2, 2.5, drehstrom: true), 20);
    expect(haeufungsFaktor(3), 0.70);
    expect(haeufungsFaktor(10), 0.50);
    expect(temperaturFaktor(30), 1.0);
    expect(temperaturFaktor(35), closeTo(0.94, 1e-9));
    expect(betriebsstrom(2300), closeTo(10, 1e-9));
    // 10 A über 20 m auf 1,5 mm²: 2·20·10/(56·1,5)/230 = 2,07 %
    expect(spannungsfall(10, 20, 1.5), closeTo(2.07, 0.01));

    // Steckdosenkreis 3,5 kW, 25 m, C, B16 auf 1,5 mm² → passt nicht (ΔU), Vorschlag 2,5 mm²
    const e = KabelEingabe(leistungW: 3500, laengeM: 25, nennstrom: 16, querschnitt: 1.5);
    final ist = kabelPruefen(e);
    expect(ist.ok, isFalse);
    final v = kabelVorschlag(const KabelEingabe(leistungW: 3500, laengeM: 25, nennstrom: 16));
    expect(v.querschnitt, 2.5);
    expect(v.ok, isTrue);
    // Häufung 6 in B2 → 1,5 mm² trägt 16 A nicht
    final h = kabelPruefen(const KabelEingabe(leistungW: 2000, laengeM: 10, nennstrom: 16, querschnitt: 1.5, art: Verlegeart.b2, haeufung: 6));
    expect(h.hinweise.any((t) => t.contains('Belastbarkeit')), isTrue);
    // Drehstrom-Herd 11 kW, 15 m im Rohr (B2) → 5x2,5 mit 16 A
    final herd = kabelVorschlag(const KabelEingabe(leistungW: 11000, laengeM: 15, drehstrom: true, art: Verlegeart.b2));
    expect(herd.nennstrom, 16);
    expect(herd.querschnitt, 2.5);
    expect(querschnittAusText('NYM-J 5x2,5'), 2.5);
    expect(adernAusText('NYM-J 5x2,5'), 5);
    expect(leitungText(2.5, drehstrom: true), 'NYM-J 5x2,5');
  });

  test('Rohre: Spitzendurchfluss und Dimension', () {
    expect(spitzendurchfluss(0.15), 0.15);
    // Bad: WT, Dusche, WC kalt = 0,35 l/s → 1,48·0,35^0,19 − 0,94 ≈ 0,27 l/s
    expect(spitzendurchfluss(0.35), closeTo(0.272, 0.002));
    final heiz = rohrVorschlag(const RohrEingabe(medium: Medium.heizung, laengeM: 10, leistungW: 8000, spreizungK: 10));
    expect(heiz.durchflussLh, closeTo(688, 1));
    expect(heiz.v, lessThanOrEqualTo(0.7));
    expect(heiz.rProM, lessThanOrEqualTo(150));
    expect(heiz.mass.name, '32×3');
    final tw = rohrVorschlag(const RohrEingabe(medium: Medium.trinkwasser, laengeM: 8, summeVr: 0.35));
    expect(tw.mass.name, '20×2');
    final klein = rohrPruefen(const RohrEingabe(medium: Medium.heizung, laengeM: 10, leistungW: 8000, innen: 16));
    expect(klein.ok, isFalse);
  });

  test('Kabel-/Rohrliste: Summen, Zuschlag, Ringe', () {
    final l = leitungsliste([
      (art: 'Kabel', bezeichnung: 'NYM-J 3x1,5', laengeM: 80, woher: 'A', geschaetzt: false),
      (art: 'Kabel', bezeichnung: 'NYM-J 3x1,5', laengeM: 40, woher: 'B', geschaetzt: true),
      (art: 'Rohr', bezeichnung: 'MV 16×2', laengeM: 12, woher: 'C', geschaetzt: false),
    ]);
    expect(l.length, 2);
    final nym = l.firstWhere((s) => s.art == 'Kabel');
    expect(nym.summe, 120);
    expect(nym.einkauf(10), 132);
    expect(nym.ringe(10, ringGroessen('Kabel', 'NYM-J 3x1,5')), [(1, 100), (1, 50)]);
    expect(stromkreisLaengeSchaetzen(verteiler: (0, 0), geraete: const [(3000, 0, 300), (3000, 2000, 300)], raumhoeheMm: 2500, reserveM: 1.5),
        closeTo(3 + 2 + 2 * 1.9 * 2 + 1.5, 1e-9));
  });

  test('Projekt: Stromkreis auslegen, Liste mit geschätzten Längen', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_ausl_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'A');
    try {
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      final typ = {for (final t in store.objekttypen()) t.kuerzel: t};
      final vt = store.objektAnlegen(geschossId: g, typ: typ['VT']!, punkte: const [Punkt(0, 0)]);
      final s = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1', geschossId: g, objektId: vt);
      final ls = store.geraetAnlegen(schrankId: s, reihe: 0, position: 0, art: GeraeteArt.ls, kennzeichen: '-F1', nennstrom: 16, charakteristik: 'B');
      final k = store.stromkreisAnlegen(schrankId: s, nummer: '1', schutzId: ls, leistung: 3000);
      for (final x in [4000.0, 6000.0]) {
        final o = store.objektAnlegen(geschossId: g, typ: typ['SD']!, punkte: [Punkt(x, 0)]);
        store.objektAendern(o, {'eigenschaften': jsonEncode({'stromkreis': k})});
      }
      final a = kreiseAuslegen(store, store.schraenke().single).single;
      expect(a.laengeGeschaetzt, isTrue);
      expect(a.laenge, greaterThan(6));
      expect(a.ist.nennstrom, 16);
      expect(a.ist.querschnitt, 1.5);
      kreisAngabenSetzen(store, k, {'laenge_m': 60.0});
      final b = kreiseAuslegen(store, store.schraenke().single).single;
      expect(b.laenge, 60);
      expect(b.ist.ok, isFalse); // 60 m auf 1,5 mm² mit 13 A: ΔU zu hoch
      expect(b.vorschlag.querschnitt, greaterThan(1.5));
      final liste = leitungsliste(leitungsStuecke(store));
      expect(liste.single.bezeichnung, 'NYM-J 3x1,5');
      expect(liste.single.summe, 60);
      // Leitung gezeichnet: keine Schätzung mehr, gezeichnete Länge zählt
      final lt = store.objektAnlegen(geschossId: g, typ: typ['LT']!, punkte: const [Punkt(0, 0), Punkt(5000, 0)]);
      store.objektAendern(lt, {'eigenschaften': jsonEncode({'stromkreis': k})});
      kreisAngabenSetzen(store, k, {'laenge_m': null});
      final c = leitungsliste(leitungsStuecke(store)).single;
      expect(c.gezeichnet, 5);
      expect(c.geschaetzt, 0);
      leitungGekauftSetzen(store, leitungSchluessel(c), 10);
      expect(leitungGekauft(store)[leitungSchluessel(c)], 10);
    } finally {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    }
  });
}
