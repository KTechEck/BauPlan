import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/ki.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/assistent/assistent_page.dart';
import 'package:bauspur/ui/assistent/projektpruefung.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeKi implements KiAnbieter {
  _FakeKi(this.antwort);
  final String antwort;
  @override
  bool get extern => false;
  String? letzteFrage;
  @override
  String get name => 'Test';
  @override
  Future<String> fragen(String system, String frage) async {
    letzteFrage = frage;
    return antwort;
  }
}

void main() {
  test('Heimnetz erkennen', () {
    expect(adresseLokal('http://localhost:11434'), isTrue);
    expect(adresseLokal('http://192.168.178.20:11434'), isTrue);
    expect(adresseLokal('http://10.0.0.5'), isTrue);
    expect(adresseLokal('http://172.20.1.1'), isTrue);
    expect(adresseLokal('http://ki-rechner.local:11434'), isTrue);
    expect(adresseLokal('https://api.example.com'), isFalse);
    expect(adresseLokal('http://172.40.1.1'), isFalse);
  });

  test('Antwort zerlegen, Stichwortsuche, Regelwerte', () {
    final h = kiHinweiseLesen('Einleitung\n- Erster Punkt\n2) Zweiter Punkt\n* Dritter');
    expect(h.map((e) => e.text), ['Erster Punkt', 'Zweiter Punkt', 'Dritter']);
    expect(h.every((e) => e.ki), isTrue);
    expect(kiHinweiseLesen('Nur ein Satz.').single.text, 'Nur ein Satz.');
    final t = stichwortSuche('Welche Stromkreise gehen ins Bad?', {
      'stromkreis Steckdosen Bad': 'A',
      'raum Bad EG': 'B',
      'stromkreis Küche': 'C',
      'Leuchte Flur': 'D',
    });
    expect(t.first, 'A');
    expect(t, containsAll(['A', 'B', 'C']));
    expect(t, isNot(contains('D')));
    final r = Regelwerte.ausJson(const Regelwerte(maxKreislaengeM: 100).toJson());
    expect(r.maxKreislaengeM, 100);
    expect(r.minReserveSchrank, 20);
  });

  test('Ollama-Anbieter spricht /api/chat; Cloud ohne Erlaubnis gesperrt', () async {
    final vorher = HttpOverrides.current;
    HttpOverrides.global = null; // echte Verbindung zum Testserver auf localhost
    addTearDown(() => HttpOverrides.global = vorher);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'message': {'role': 'assistant', 'content': ' Antwort zu ${(body['messages'] as List).last['content']} mit ${body['model']} '},
      }));
      await req.response.close();
    });
    final a = OllamaAnbieter(KiEinstellung(adresse: 'http://localhost:${server.port}', modell: 'test-modell'));
    expect(a.extern, isFalse);
    expect(await a.fragen('sys', 'Hallo'), 'Antwort zu Hallo mit test-modell');
    final cloud = OllamaAnbieter(const KiEinstellung(adresse: 'https://api.example.com'));
    expect(cloud.extern, isTrue);
    expect(() => cloud.fragen('s', 'f'), throwsStateError);
  });

  group('Projekt', () {
    late Directory tmp;
    late ProjectStore store;
    late String g;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('bauspur_ki_');
      store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'K');
      g = store.geschosse(store.gebaeude().single.id).single.id;
      for (final (x1, y1, x2, y2) in [(0, 0, 4400, 0), (4400, 0, 4400, 3400), (4400, 3400, 0, 3400), (0, 3400, 0, 0)]) {
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
      }
      store.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: store.flaechenErkennen(g).single);
    });
    tearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });

    test('Feste Regeln über das Projekt', () {
      final typen = {for (final t in store.objekttypen()) t.kuerzel: t};
      store.objektAnlegen(geschossId: g, typ: typen['SD']!, punkte: const [Punkt(100, 100)]); // ohne Raum
      // sehr großer Heizkreis
      store.objektAnlegen(geschossId: g, typ: typen['HK']!, punkte: const [Punkt(0, 0), Punkt(20000, 0), Punkt(20000, 20000), Punkt(0, 20000)]);
      store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1', reihen: 1, teJeReihe: 2);
      final h = projektPruefen(store, const Regelwerte());
      final text = h.map((e) => '[${e.bereich}] ${e.text}').join('\n');
      expect(text, contains('[Installation]'));
      expect(text, contains('ohne Raum'));
      expect(text, contains('[Fußbodenheizung]'));
      expect(text, contains('Kreislänge'));
      expect(text, contains('[Elektro]'));
      expect(h.every((e) => !e.ki), isTrue);
      final steckbrief = projektSteckbrief(store, h);
      expect(steckbrief, contains('Bad'));
      expect(steckbrief, contains('Bereits von festen Regeln gefunden'));
    });

    testWidgets('Modul KI-Assistent: Status setzen und Einschätzung holen', (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final typen = {for (final t in store.objekttypen()) t.kuerzel: t};
      store.objektAnlegen(geschossId: g, typ: typen['SD']!, punkte: const [Punkt(100, 100)]);
      final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))
        ..store = store
        ..geschossId = g;
      final ki = _FakeKi('- Im Bad fehlt ein Präsenzmelder\n- Steckdose am Waschtisch prüfen');
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: AssistentPage(state: state, anbieter: ki))));
      await tester.pump();
      expect(find.textContaining('ohne Raum'), findsOneWidget);
      expect(find.textContaining('1 offen'), findsOneWidget);

      // Status „bewusst so geplant“
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('bewusst so geplant').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('0 offen'), findsOneWidget);
      expect((store.einstellung<Map>('pruefung_status') ?? const {}).values, contains('bewusst'));

      await tester.tap(find.text('KI-Prüfung (Einschätzung)'));
      await tester.pumpAndSettle();
      expect(find.text('Im Bad fehlt ein Präsenzmelder'), findsOneWidget);
      expect(find.text('Einschätzungen des Sprachmodells'), findsOneWidget);
      expect(ki.letzteFrage, contains('Bad'));

      // Fragen ohne Sprachmodell
      await tester.tap(find.text('Fragen'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Steckdose');
      await tester.tap(find.text('Suchen'));
      await tester.pump();
      expect(find.textContaining('Treffer im Projekt'), findsOneWidget);
    });
  });
}
