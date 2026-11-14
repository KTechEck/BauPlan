import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/auslegung.dart';
import 'package:bauspur/core/auslegung_projekt.dart';
import 'package:bauspur/core/aussen.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/wlan.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/installation/wlan_aussen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WLAN: Freiraum, Wände, Raumauswertung', () {
    expect(freiraumDaempfung(1, 2437), closeTo(40.2, 0.1));
    expect(wandDaempfung('Stahlbeton 200', 200), 15);
    expect(wandDaempfung('', 100), 4);
    const ap = (id: 'a', p: Punkt(0, 0), dbm: 20.0);
    final ohne = wlanPegel(const Punkt(5000, 0), const [ap], const [], WlanBand.g24);
    final mitWand = wlanPegel(const Punkt(5000, 0), const [ap], const [(a: Punkt(2500, -1000), b: Punkt(2500, 1000), db: 12.0)], WlanBand.g24);
    expect(ohne - mitWand, closeTo(12, 1e-9));
    expect(wlanPegel(const Punkt(5000, 0), const [ap], const [(a: Punkt(2500, -1000), b: Punkt(2500, 1000), db: 12.0)], WlanBand.g5), lessThan(mitWand));
    expect(wlanStufe(-55), 'sehr gut');
    expect(wlanStufe(-80), 'kein Empfang');
    final r = wlanRaum(const [Punkt(0, 0), Punkt(4000, 0), Punkt(4000, 3000), Punkt(0, 3000)], const [(id: 'a', p: Punkt(2000, 1500), dbm: 20.0)], const [], WlanBand.g5);
    expect(r.anteilGut, 1);
  });

  test('Außen: Regenwasser, Zisterne, Rigole, Bewässerung, Licht, Kabel', () {
    expect(regenabfluss(120, 1.0), closeTo(3.6, 1e-9));
    expect(fallrohrDn(1.8), 80);
    expect(fallrohrDn(3.0), 100);
    final z = zisterne(dachM2: 120, c: 1.0, personen: 4, gartenM2: 200);
    expect(z.ertrag, closeTo(120 * 0.75 * 0.9, 1e-9));
    expect(z.bedarf, closeTo(4 * 34 * 365 / 1000 + 12, 1e-9));
    expect(z.volumen, closeTo(z.bedarf * 21 / 365, 1e-9));
    expect(rigole(100, 1.0).speicher, closeTo(1.5, 1e-9));
    const garten = [Punkt(0, 0), Punkt(8000, 0), Punkt(8000, 4000), Punkt(0, 4000)];
    final regner = [(p: const Punkt(2000, 2000), radius: 4000.0, lmin: 15.0, ventil: 'A'), (p: const Punkt(6000, 2000), radius: 4000.0, lmin: 15.0, ventil: 'A')];
    expect(bewaesserungAbdeckung(const [garten], regner), greaterThan(0.95));
    expect(bewaesserungZonen(regner, verfuegbarLmin: 25).single, contains('Zone A'));
    expect(lichtRadius('PO', hoehe: 800), closeTo(1860, 1e-9));
    expect(erdkabelMengen(10).first.menge, closeTo(1.8, 1e-9));
    expect(aufputzAussenMengen(4)[1].menge, 12);
    expect(aussenKabelHinweise('NYM-J 3x1,5', erdverlegt: true).first, contains('nicht für das Erdreich'));
  });

  testWidgets('Außenanlagen-Gewerk, Kabelliste, Außen-Dialog', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_b30_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'A');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final au = {for (final gw in store.gewerke()) gw.kuerzel: gw.id}['AU']!;
    final typ = {for (final t in store.objekttypen()) if (t.gewerkId == au) t.kuerzel: t};
    expect(typ.keys, containsAll(['EK', 'AK', 'RF', 'ZS', 'RE', 'AS', 'AE']));
    final ek = store.objektAnlegen(geschossId: g, typ: typ['EK']!, punkte: const [Punkt(0, 0), Punkt(10000, 0)]);
    store.objektAendern(ek, {'eigenschaften': jsonEncode({'kabel': 'NYY-J 5x2,5'})});
    store.objektAnlegen(geschossId: g, typ: typ['RG']!, punkte: const [Punkt(0, 0), Punkt(0, 5000)]);
    final l = leitungsliste(leitungsStuecke(store));
    expect(l.any((x) => x.bezeichnung == 'NYY-J 5x2,5' && x.summe == 10), isTrue);
    expect(l.any((x) => x.bezeichnung.contains('Kabelschutzrohr')), isTrue);
    expect(l.any((x) => x.bezeichnung.contains('KG-Rohr')), isTrue);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))
      ..store = store
      ..geschossId = g;
    await tester.pumpWidget(MaterialApp(
      theme: bauSpurTheme(),
      home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => aussenDialog(c, state), child: const Text('A')))),
    ));
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Regenabfluss'), findsOneWidget);
    for (final t in ['Bewässerung', 'Licht und Strom', 'Kabel außen']) {
      await tester.tap(find.text(t));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: t);
    }
    expect(find.textContaining('Kabelgraben'), findsOneWidget);
  });
}
