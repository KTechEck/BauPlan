import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/raumbild.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/raumbild_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Prompt, Antworten lesen, multipart, Anbieterwahl', () {
    final d = (
      raum: 'Bad OG',
      flaecheM2: 8.0,
      breiteM: 2.5,
      tiefeM: 3.2,
      hoeheM: 2.5,
      fenster: 1,
      tueren: 1,
      ausstattung: ['1× Dusche / Duschfläche', '1× WC'],
      oberflaechen: ['Wände: Fliesen weiß'],
    );
    final p = raumbildPrompt(d, stil: 'skandinavisch', wuensche: 'Holzwaschtisch');
    expect(p, contains('bathroom'));
    expect(p, contains('Scandinavian'));
    expect(p, contains('1× WC'));
    expect(p, contains('Holzwaschtisch'));
    expect(p, contains('floor plan sketch'));
    expect(raumbildPrompt(d, mitVorlage: false), isNot(contains('floor plan sketch')));
    final png = [137, 80, 78, 71];
    expect(openAiAntwortLesen(jsonEncode({'data': [{'b64_json': base64Encode(png)}]})), png);
    expect(geminiAntwortLesen(jsonEncode({'candidates': [{'content': {'parts': [{'text': 'x'}, {'inlineData': {'mimeType': 'image/png', 'data': base64Encode(png)}}]}}]})), png);
    expect(() => geminiAntwortLesen('{"candidates": []}'), throwsA(isA<RaumbildFehler>()));
    final m = multipart({'model': 'gpt-image-1'}, {'image': ('plan.png', 'image/png', png)});
    expect(m.typ, startsWith('multipart/form-data; boundary='));
    expect(utf8.decode(m.body, allowMalformed: true), contains('name="image"; filename="plan.png"'));
    expect(raumbildAnbieter({'anbieter': 'gemini'}), isA<GeminiBild>());
    expect(raumbildAnbieter(null), isA<OpenAiBild>());
    expect(raumbildAnbieter({'anbieter': 'comfyui'}).kosten('hoch'), 0);
  });

  test('OpenAI ohne Schlüssel meldet sich verständlich', () async {
    expect(() => OpenAiBild('').erzeugen(prompt: 'x'), throwsA(isA<RaumbildFehler>()));
    expect(() => GeminiBild(' ').erzeugen(prompt: 'x'), throwsA(isA<RaumbildFehler>()));
  });

  testWidgets('Raumbild-Dialog zeigt Skizze und Kostenhinweis', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_b31_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'R');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    for (final (x1, y1, x2, y2) in [(0, 0, 4000, 0), (4000, 0, 4000, 3000), (4000, 3000, 0, 3000), (0, 3000, 0, 0)]) {
      store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
    }
    store.raumAnlegen(geschossId: g, name: 'Wohnen', kuerzel: 'WO', flaeche: store.flaechenErkennen(g).single);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))
      ..store = store
      ..geschossId = g;
    await tester.pumpWidget(MaterialApp(
      theme: bauSpurTheme(),
      home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => raumbildDialog(c, state), child: const Text('R')))),
    ));
    await tester.tap(find.text('R'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('living room'), findsOneWidget);
    await tester.drag(find.text('Raum'), const Offset(0, -600));
    await tester.pump();
    expect(find.textContaining('Kosten ca.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

