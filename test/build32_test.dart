import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/drei_d_szene.dart';
import 'package:bauspur/core/einkaufslisten.dart';
import 'package:bauspur/core/glossar.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/wandmasse.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/einkauf/einkauf_page.dart';
import 'package:bauspur/ui/hilfe_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Glossar: Feldbeschriftung findet den Begriff', () {
    expect(begriffZuFeld('Spreizung (K)')?.name, 'Spreizung');
    expect(begriffZuFeld('Uw')?.name, startsWith('Uw'));
    expect(begriffZuFeld('Ug Glas')?.name, startsWith('Ug'));
    expect(begriffZuFeld('kv-Wert')?.name, 'kv-Wert');
    expect(begriffZuFeld('Name'), isNull);
    expect(glossar.where((b) => b.passt('Spreizung')), isNotEmpty);
  });

  test('3D-Szene: Öffnungen, Böden, Material je Raum, nicht gespiegelt', () {
    const ecken = [Punkt(0, 0), Punkt(4000, 0), Punkt(4000, 3000), Punkt(0, 3000)];
    final achsen = [for (var i = 0; i < 4; i++) WandAchse(ecken[i], ecken[(i + 1) % 4], 240)];
    final waende = [
      for (var i = 0; i < 4; i++) Wand3d(id: 'w$i', a: achsen[i].a, b: achsen[i].b, dicke: 240, umriss: wandUmriss(achsen[i], achsen), hoehe: 2500, materialLinks: 'klinker', materialRechts: 'klinker'),
    ];
    const raum = (id: 'r', name: 'Bad', umriss: [Punkt(120, 120), Punkt(3880, 120), Punkt(3880, 2880), Punkt(120, 2880)], boden: 'fliesen_grau', waende: 'fliesen_weiss', aussen: false);
    final mitFenster = geschossSzene(
      waende: waende,
      oeffnungen: [(wandId: 'w0', von: 1000.0, bis: 2000.0, unten: 900.0, oben: 2100.0, fenster: true)],
      raeume: [raum],
    );
    final ohne = geschossSzene(waende: waende, oeffnungen: const [], raeume: [raum]);
    expect(mitFenster.where((f) => f.art == 'glas'), hasLength(1));
    expect(mitFenster.where((f) => f.art == 'boden').length, greaterThan(4));
    // Innen Fliesen, außen Klinker
    expect(mitFenster.where((f) => f.material == 'fliesen_weiss'), isNotEmpty);
    expect(mitFenster.where((f) => f.material == 'klinker'), isNotEmpty);
    expect(ohne.where((f) => f.art == 'glas'), isEmpty);
    // y gespiegelt: Grundriss-y 3000 liegt bei 3D-y −3000
    expect(mitFenster.where((f) => f.art == 'boden').expand((f) => f.ecken).every((e) => e.y <= 0), isTrue);
    expect(dreieckeZerlegen(const [Punkt(0, 0), Punkt(4, 0), Punkt(4, 4), Punkt(2, 2), Punkt(0, 4)]), hasLength(3));
    expect(oberflaecheAusText('Feinsteinzeug grau'), 'fliesen_grau');
    expect(bodenAusRaumname('Balkon'), 'wpc');
  });

  test('Einkaufslisten: zuordnen, verschieben, App-IDs, abhaken', () {
    final l = [Einkaufsliste(id: 'a', name: 'Bauhaus', erstellt: DateTime(2026)), Einkaufsliste(id: 'b', name: 'Großhandel', erstellt: DateTime(2026))];
    inListeLegen(l, 'a', [ListenPosition(schluessel: 'e:x', text: 'Dose'), ListenPosition(schluessel: 'l:NYM', text: 'NYM', menge: 50, einheit: 'm')]);
    inListeLegen(l, 'b', [ListenPosition(schluessel: 'e:x', text: 'Dose', menge: 3)]);
    expect(l[0].positionen.map((p) => p.schluessel), ['l:NYM']);
    expect(zuordnung(l)['e:x'], 'Großhandel');
    expect(schluesselAusAppId('b-x'), 'e:x');
    expect(appIdAusSchluessel('m:7'), 'm-7');
    expect(schluesselAusAppId('pos1'), 'k:pos1');
    expect(listenAbhaken(l, 'e:x', true), isTrue);
    expect(l[1].offen, 0);
    final json = [for (final x in l) x.toJson()];
    final zurueck = listenLesen((k) => json);
    expect(zurueck[1].positionen.single.abgehakt, isTrue);
    expect(einkaufszettelHtml(l[0]), contains('NYM'));
  });

  testWidgets('Einkauf-Seite, Hilfe-Panel und offene Kante', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_b32_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'E');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final ids = <String>[];
    for (final (x1, y1, x2, y2) in [(0, 0, 3000, 0), (3000, 0, 3000, 1500), (3000, 1500, 0, 1500), (0, 1500, 0, 0)]) {
      ids.add(store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 200));
    }
    store.wandEigenschaftenSetzen(ids[1], {'art': 'kante', 'gelaender': true});
    final w = store.waende(g).firstWhere((x) => x.id == ids[1]);
    expect(w.istKante, isTrue);
    expect(w.teilhoch, isFalse);
    expect(store.flaechenErkennen(g), hasLength(1), reason: 'offene Kante begrenzt den Raum weiter');
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;
    listenSchreiben((k, v) => store.einstellungSetzen(k, v), [
      Einkaufsliste(id: 'a', name: 'Bauhaus Samstag', erstellt: DateTime(2026), positionen: [ListenPosition(schluessel: 'm:1', text: 'Silikon weiß', menge: 2)]),
    ]);
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: Row(children: [Expanded(child: EinkaufPage(state: state)), HilfePanel(state: state)]))));
    await tester.pump();
    expect(find.text('Bauhaus Samstag'), findsOneWidget);
    expect(find.textContaining('Silikon weiß  (von Hand)'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(listenLesen((k) => store.einstellung<Object>(k)).single.positionen.single.abgehakt, isTrue);
    await tester.enterText(find.widgetWithText(TextField, 'Begriff nachschlagen, z. B. kv, Uw'), 'Uw');
    await tester.pump();
    await tester.tap(find.text('Uw (Fenster gesamt)'));
    await tester.pump();
    expect(find.textContaining('Was eingeben'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
