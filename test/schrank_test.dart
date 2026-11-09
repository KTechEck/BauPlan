import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/schrank.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schrank_models.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/verteiler/schrank_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ProjectStore store;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bauspur_sk_');
    store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'S');
  });
  tearDown(() {
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  Schrank schrank(String id) => store.schraenke().firstWhere((s) => s.id == id);

  test('Belegung, freie Plätze und Kennzeichen', () {
    final id = store.schrankAnlegen(name: 'UV Küche', kennzeichen: 'UV1', reihen: 2, teJeReihe: 12);
    final rcd = store.geraetAnlegen(schrankId: id, reihe: 0, position: 0, art: GeraeteArt.rcd, pole: 4, kennzeichen: '-F1');
    store.geraetAnlegen(schrankId: id, reihe: 0, position: 4, art: GeraeteArt.ls, kennzeichen: '-F2', vorgeschaltetId: rcd, phase: 'L1');
    final s = schrank(id);
    final g = store.schrankGeraete(id);
    final b = belegung(s, g);
    expect((b.gesamt, b.belegt, b.frei), (24, 5, 19));
    expect(platzFrei(s, g, 0, 3, 1), isFalse);
    expect(platzFrei(s, g, 0, 5, 7), isTrue);
    expect(platzFrei(s, g, 0, 6, 7), isFalse); // ragt über die Reihe
    expect(freierPlatz(s, g, 8), (1, 0));
    expect(naechstesKennzeichen(GeraeteArt.ls, g), '-F3');
    expect(naechstesKennzeichen(GeraeteArt.knx, g), '-K1');
    expect(betriebsmittel(s, g.last), '=UV1-F2');
    expect(g.first.kurz, '40 A 30 mA');
  });

  test('Phasenlast und Hinweise', () {
    final id = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1', reihen: 1, teJeReihe: 12);
    final rcd = store.geraetAnlegen(schrankId: id, reihe: 0, position: 0, art: GeraeteArt.rcd, pole: 4, kennzeichen: '-F1', nennstrom: 40, fehlerstrom: 30);
    final ls1 = store.geraetAnlegen(
        schrankId: id, reihe: 0, position: 4, art: GeraeteArt.ls, kennzeichen: '-F2', nennstrom: 20, phase: 'L1', vorgeschaltetId: rcd);
    final ls2 = store.geraetAnlegen(schrankId: id, reihe: 0, position: 5, art: GeraeteArt.ls, kennzeichen: '-F3', nennstrom: 16);
    final herd = store.geraetAnlegen(
        schrankId: id, reihe: 0, position: 6, art: GeraeteArt.ls, pole: 3, kennzeichen: '-F4', nennstrom: 16, phase: '3P', vorgeschaltetId: rcd);
    store.stromkreisAnlegen(schrankId: id, nummer: '1', bezeichnung: 'Küche', schutzId: ls1, querschnitt: 150, leistung: 7000);
    store.stromkreisAnlegen(schrankId: id, nummer: '2', bezeichnung: 'Licht', schutzId: ls2);
    store.stromkreisAnlegen(schrankId: id, nummer: '3', bezeichnung: 'Herd', schutzId: herd, querschnitt: 250, leistung: 9000);
    store.stromkreisAnlegen(schrankId: id, nummer: '4', bezeichnung: 'ohne');
    final s = schrank(id);
    final g = store.schrankGeraete(id);
    final k = store.stromkreise(id);
    expect(k.map((e) => e.nummer), ['1', '2', '3', '4']);
    final last = phasenLast(k, g);
    expect(last['L1'], 7000 + 3000);
    expect(last['L2'], 3000);
    final h = schrankHinweise(s, g, k).join('\n');
    expect(h, contains('-F3 (B16) hat keinen vorgeschalteten FI/RCD'));
    expect(h, contains('-F3: keine Phase'));
    expect(h, contains('Stromkreis 4 ohne: kein Schutzorgan'));
    expect(h, contains('Stromkreis 1: B20 ist für 1,5 mm² zu groß'));
    expect(h, contains('geschätzte Last 30,4 A über 20 A'));
    expect(h, contains('Schieflast'));
    expect(maxNennstrom(250), 20);
  });

  test('Beschriftungsstreifen mit Lücken und Stromkreisnamen', () {
    final id = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1', reihen: 1, teJeReihe: 12);
    final ls = store.geraetAnlegen(schrankId: id, reihe: 0, position: 2, art: GeraeteArt.ls, kennzeichen: '-F1');
    store.stromkreisAnlegen(schrankId: id, nummer: '1', bezeichnung: 'Bad', schutzId: ls);
    final st = beschriftung(schrank(id), store.schrankGeraete(id), store.stromkreise(id));
    expect(st.single, [(0, 2, ''), (2, 1, '-F1 Bad'), (3, 9, '')]);
  });

  test('Objekte im Stromkreis über eigenschaften.stromkreis', () {
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final id = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1');
    final k = store.stromkreisAnlegen(schrankId: id, nummer: '1', bezeichnung: 'Steckdosen');
    final sd = store.objekttypen().firstWhere((t) => t.kuerzel == 'SD');
    final o = store.objektAnlegen(geschossId: g, typ: sd, punkte: const [Punkt(0, 0)]);
    store.objektAendern(o, {'eigenschaften': jsonEncode({'stromkreis': k})});
    expect(store.objekteImStromkreis(k).single.id, o);
  });

  testWidgets('Modul Verteiler: Schrank zeigen, Gerät setzen, Stromkreisliste', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final id = store.schrankAnlegen(name: 'UV Erdgeschoss', kennzeichen: 'UV1', reihen: 3, teJeReihe: 12);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))..store = store;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: SchrankPage(state: state))));
    await tester.pump();
    expect(find.text('UV Erdgeschoss'), findsWidgets);
    expect(find.textContaining('0 von 36 TE belegt'), findsOneWidget);

    // schematische Darstellung für feste Klickpositionen
    await tester.tap(find.text('Echte Darstellung'));
    await tester.pump();
    await tester.tap(find.text('Leitungsschutzschalter').first);
    await tester.pumpAndSettle();
    final flaeche = find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_SchrankPainter');
    await tester.tapAt(tester.getTopLeft(flaeche) + const Offset(50, 60));
    await tester.pump();
    final g = store.schrankGeraete(id);
    expect(g.single.art, GeraeteArt.ls);
    expect(g.single.kennzeichen, '-F1');
    expect(g.single.phase, 'L1');
    expect(find.text('=UV1-F1'), findsOneWidget);

    await tester.tap(find.text('Stromkreise').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Stromkreis'));
    await tester.pump();
    expect(store.stromkreise(id).single.nummer, '1');

    await tester.tap(find.text('Übersichtsschaltbild'));
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_UebersichtPainter'), findsOneWidget);
  });
}
