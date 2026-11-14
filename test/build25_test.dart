import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/hydraulik_schema.dart';
import 'package:bauspur/core/klima_lueftung.dart';
import 'package:bauspur/core/ta_regler.dart';
import 'package:bauspur/core/technikbereich.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/haustechnik/haustechnik_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Taupunkt, Kühllast, Lüftung', () {
    expect(taupunkt(26, 60), closeTo(17.6, 0.2));
    expect(minKuehlVorlauf(26, 60), closeTo(19.6, 0.2));
    expect(kondensatGefahr(16, 26, 60), isTrue);
    expect(kuehllast(flaeche: 20), 400);
    expect(klimageraetGroesse(2300), 2.5);
    expect(luftArtVorschlag('Bad'), LuftArt.abluft);
    expect(luftArtVorschlag('Flur'), LuftArt.ueberstroem);
    expect(luftArtVorschlag('Kinderzimmer'), LuftArt.zuluft);
    expect(nennlueftung(100), closeTo(125, 0.1));
    final v = lueftungVerteilen([
      (id: 'w', name: 'Wohnen', flaeche: 40, art: LuftArt.zuluft, vonHand: null),
      (id: 's', name: 'Schlafen', flaeche: 15, art: LuftArt.zuluft, vonHand: null),
      (id: 'k', name: 'Küche', flaeche: 12, art: LuftArt.abluft, vonHand: null),
      (id: 'b', name: 'Bad', flaeche: 8, art: LuftArt.abluft, vonHand: null),
      (id: 'f', name: 'Flur', flaeche: 10, art: LuftArt.ueberstroem, vonHand: null),
    ]);
    final zu = v.raeume.where((r) => r.art == LuftArt.zuluft).fold<double>(0, (s, r) => s + r.volumenstrom);
    final ab = v.raeume.where((r) => r.art == LuftArt.abluft).fold<double>(0, (s, r) => s + r.volumenstrom);
    expect(zu, closeTo(v.gesamt, 1e-6));
    expect(ab, closeTo(v.gesamt, 1e-6));
    expect(v.gesamt, closeTo(nennlueftung(85), 1e-6));
    expect(ueberstroemQuerschnitt(36), closeTo(100, 1e-6));
    expect(luftrohrVorschlag(60), 90);
    expect(druckbedarf(strangPa: 50, komponenten: const [(name: 'F7', druckverlust: 40, leistungW: null, art: 'filter')]), 160);
    expect(daemmHinweise(kuehlung: true).length, 3);
  });

  test('TA-Regler: Kapazität, Kabelweg, TAPPS2, C.M.I.-Antwort', () {
    final b = TaBelegung(
      [TaGeraet(id: 'r', typ: 'UVR610', name: 'Heizung')],
      [
        for (var i = 1; i <= 7; i++) TaKanal(nr: i, regler: 'r', eingang: true, typ: 'PT1000', name: i == 1 ? 'Außentemperatur' : (i == 2 ? 'Vorlauf HK1' : 'Fühler $i')),
        TaKanal(nr: 1, regler: 'r', eingang: false, typ: 'Pumpe (Relais)', name: 'Pumpe HK1'),
        TaKanal(nr: 2, regler: 'r', eingang: false, typ: 'Mischer auf', name: 'Mischer HK1'),
      ],
    );
    final k = taKapazitaet(b);
    expect(k.any((h) => h.contains('7 Eingänge belegt, nur 6')), isTrue);
    expect(taKabelweg((0, 0), (3000, 4000)), closeTo(7 + 2.5 + 1, 1e-9));
    expect(taKabeltyp('PT1000'), 'LiYY 2×0,5');
    final v = tapps2Vorlage(b);
    expect(v, contains('E2   PT1000'));
    expect(v, contains('Heizkreisregler: Außentemp E1, Vorlauf E2, Pumpe A1, Mischer A2'));
    final c = cmiAntwortLesen('{"Header":{},"Data":{"Inputs":[{"Number":1,"AD":"A","Value":{"Value":21.4,"Unit":"1"}}],"Outputs":[{"Number":2,"Value":{"Value":1,"Unit":"43"}}]},"Status":"OK"}');
    expect(c['E1'], '21,4 °C');
    expect(c['A2'], '1');
  });

  test('Hydraulikschema: Speichern, Weg, SVG mit Platzhalter', () {
    final s = HydraulikSchema([
      SchemaSymbol(id: 'a', art: 'waermepumpe', x: 100, y: 100, name: 'WP'),
      SchemaSymbol(id: 'b', art: 'puffer', x: 300, y: 150),
    ], [SchemaLinie(id: 'l', von: 'a', bis: 'b', art: 'vl')]);
    final j = HydraulikSchema.ausJson(s.toJson());
    expect(j.symbole.length, 2);
    expect(j.linien.single.art, 'vl');
    expect(schemaWeg(s.symbole[0], s.symbole[1]).length, 4);
    final svg = schemaSvg(s, platzhalter: {'b': 'E3'}, titel: 'Test');
    expect(svg, contains('<polyline'));
    expect(svg, contains('E3'));
    expect(svg, contains('WP'));
  });

  test('Technikbereiche: automatisch erkannt, lösbar, eigene Technikwand', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_b25_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'T');
    try {
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      for (final (x1, y1, x2, y2) in [(0, 0, 3000, 0), (3000, 0, 3000, 3000), (3000, 3000, 0, 3000), (0, 3000, 0, 0)]) {
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
      }
      final r = store.raumAnlegen(geschossId: g, name: 'Technikraum', kuerzel: 'TR', flaeche: store.flaechenErkennen(g).single);
      expect(technikbereiche(store).single.automatisch, isTrue);
      technikbereichAutoLoesen(store, r, true);
      expect(technikbereiche(store), isEmpty);
      technikbereicheSpeichern(store, [Technikbereich(id: 'x', name: 'Technikwand Büro', raumId: r, wandId: 'wand', schraenke: const ['s1'])]);
      final b = technikbereiche(store).single;
      expect(b.istWand, isTrue);
      expect(b.schraenke, ['s1']);
    } finally {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    }
  });

  testWidgets('Haustechnik: alle Reiter öffnen', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_b25w_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'H');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    for (final (x1, y1, x2, y2) in [(0, 0, 4000, 0), (4000, 0, 4000, 3000), (4000, 3000, 0, 3000), (0, 3000, 0, 0)]) {
      store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
    }
    store.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: store.flaechenErkennen(g).single);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))
      ..store = store
      ..geschossId = g;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: HaustechnikPage(state: state))));
    await tester.pump();
    for (final t in ['Hydraulikschema', 'Regelung (TA)', 'Lüftung', 'Kühlung & Klima', 'Technikbereiche']) {
      await tester.ensureVisible(find.text(t));
      await tester.tap(find.text(t));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: t);
    }
    await tester.tap(find.text('Lüftung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nennlüftung'), findsWidgets);
    await tester.tap(find.text('Hydraulikschema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pumpe'));
    await tester.pump();
    final flaeche = find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_SchemaPainter');
    await tester.tapAt(tester.getCenter(flaeche));
    await tester.pump();
    expect(HydraulikSchema.ausJson(store.einstellung<Map>('hydraulikschema')).symbole.single.art, 'pumpe');
  });
}
