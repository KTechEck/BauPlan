import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/tagebuch_models.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/tagebuch/tagebuch_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ProjectStore store;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bauspur_tb_');
    store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'T');
  });
  tearDown(() {
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Tagebuch: anlegen, sortiert, Stunden', () {
    store.tagebuchAnlegen(datum: DateTime(2026, 11, 5), text: 'Leerrohre Bad', stunden: 3.5);
    store.tagebuchAnlegen(datum: DateTime(2026, 11, 7), text: 'Estrich', stunden: 1);
    final t = store.tagebuch();
    expect(t.first.text, 'Estrich');
    expect(t.last.stunden, 3.5);
    store.tagebuchLoeschen(t.first.id);
    expect(store.tagebuch().length, 1);
  });

  test('Aufgaben: Abhängigkeit und Wartung', () {
    final foto = store.aufgabeAnlegen(titel: 'Leerrohre fotografieren');
    final estrich = store.aufgabeAnlegen(titel: 'Estrich', abhaengigVon: foto, faellig: DateTime(2026, 12, 1));
    final wartung = store.aufgabeAnlegen(titel: 'Wärmepumpe warten', intervallTage: 365, faellig: DateTime(2026, 11, 1));
    var alle = store.aufgaben();
    expect(aufgabeFrei(alle.firstWhere((a) => a.id == estrich), alle), isFalse);
    store.aufgabeErledigen(foto, am: DateTime(2026, 11, 7));
    alle = store.aufgaben();
    expect(aufgabeFrei(alle.firstWhere((a) => a.id == estrich), alle), isTrue);
    expect(alle.last.status, AufgabenStatus.erledigt); // erledigte zuletzt
    store.aufgabeErledigen(wartung, am: DateTime(2026, 11, 7));
    final w = store.aufgaben().firstWhere((a) => a.id == wartung);
    expect(w.status, AufgabenStatus.offen);
    expect(w.faellig, DateTime(2027, 11, 7));
    expect(w.erledigtAm, DateTime(2026, 11, 7));
  });

  test('Prüfprotokoll und Statusverlauf', () {
    store.pruefprotokollAnlegen(art: 'Druckprobe Heizung/FBH', datum: DateTime(2026, 11, 7), messwerte: {'Prüfdruck bar': '6'});
    expect(store.pruefprotokolle().single.messwerte['Prüfdruck bar'], '6');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final sd = store.objekttypen().firstWhere((t) => t.kuerzel == 'SD');
    final o = store.objektAnlegen(geschossId: g, typ: sd, punkte: const [Punkt(0, 0)]);
    store.objektAendern(o, {'status': ObjektStatus.verlegt.name});
    store.objektAendern(o, {'status': ObjektStatus.verdeckt.name});
    final v = store.statusVerlauf();
    expect(v.map((e) => e.$4), ['verdeckt', 'verlegt']);
    expect(v.first.$3, o);
  });

  testWidgets('Modul Bautagebuch: Aufgaben und Verlauf anzeigen', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.tagebuchAnlegen(datum: DateTime(2026, 11, 7), text: 'Heizkreise verlegt', stunden: 6);
    final a = store.aufgabeAnlegen(titel: 'Druckprobe machen');
    store.aufgabeAnlegen(titel: 'Estrich bestellen', abhaengigVon: a);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: TagebuchPage(state: state))));
    expect(find.text('Heizkreise verlegt'), findsOneWidget);
    expect(find.textContaining('6,0 Stunden'), findsOneWidget);
    await tester.tap(find.text('Aufgaben'));
    await tester.pump();
    expect(find.textContaining('wartet auf „Druckprobe machen“'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(store.aufgaben().firstWhere((x) => x.id == a).status, AufgabenStatus.erledigt);
    await tester.tap(find.text('Verlauf'));
    await tester.pump();
    expect(find.textContaining('Noch keine Statuswechsel'), findsOneWidget);
  });
}
