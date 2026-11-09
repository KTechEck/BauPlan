import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/ki_einrichtung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/assistent/ki_einrichtung_karte.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Modell passend zur Hardware', () {
    expect(modellEmpfehlen((ramGb: 32, grafik: 'RTX 4090', vramGb: 24)).modell, 'qwen2.5:14b');
    expect(modellEmpfehlen((ramGb: 16, grafik: 'RTX 3070', vramGb: 8)).modell, 'llama3.1:8b');
    expect(modellEmpfehlen((ramGb: 16, grafik: 'Intel UHD', vramGb: 1)).modell, 'llama3.2:3b');
    final klein = modellEmpfehlen((ramGb: 8, grafik: 'Intel UHD 620', vramGb: 2));
    expect(klein.modell, 'llama3.2:1b');
    expect(klein.grund, contains('stärkeren PC'));
    expect(vramAusName('NVIDIA GeForce RTX 4070 Ti SUPER'), 16);
    expect(vramAusName('AMD Radeon RX 6700 XT'), 12);
    expect(vramAusName('Intel(R) UHD Graphics 620'), isNull);
  });

  test('Ollama: installierte Modelle und Laden mit Fortschritt', () async {
    final vorher = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = vorher);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      if (req.uri.path == '/api/tags') {
        req.response.write(jsonEncode({
          'models': [
            {'name': 'llama3.2:1b'}
          ]
        }));
      } else if (req.uri.path == '/api/pull') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        req.response.writeln(jsonEncode({'status': 'pulling ${body['name']}', 'total': 100, 'completed': 50}));
        req.response.writeln(jsonEncode({'status': 'success', 'total': 100, 'completed': 100}));
      }
      await req.response.close();
    });
    final adresse = 'http://localhost:${server.port}';
    expect(await ollamaModelle(adresse), ['llama3.2:1b']);
    expect(await ollamaModelle('http://localhost:1'), isNull);
    final schritte = await ollamaLaden(adresse, 'llama3.1:8b').toList();
    expect(schritte.first, (0.5, 'pulling llama3.1:8b'));
    expect(schritte.last.$1, 1);
  });

  testWidgets('Einrichtung zeigt Schritte und Empfehlung', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_kie_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')));
    await tester.pumpWidget(MaterialApp(
      theme: bauSpurTheme(),
      home: Scaffold(
        body: KiEinrichtungKarte(
          state: state,
          hardware: () async => (ramGb: 32.0, grafik: 'NVIDIA GeForce RTX 3070', vramGb: 8.0),
          modelle: (_) async => null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Wo soll die KI laufen?'), findsOneWidget);
    expect(find.text('Alles einrichten (installieren, starten, Modelle laden)'), findsOneWidget);
    expect(find.textContaining('32 GB Arbeitsspeicher'), findsOneWidget);
    expect(find.text('Ausgewogen (empfohlen)'), findsOneWidget);
    expect(find.text('läuft, aber langsam'), findsWidgets);
    expect(modelleVorschlagen((ramGb: 32.0, grafik: 'RTX 3070', vramGb: 8.0)), ['llama3.1:8b']);
    expect(modelleVorschlagen((ramGb: 8.0, grafik: 'UHD', vramGb: 1.0)), ['llama3.2:3b']);
    expect(serverBefehl(ServerArt.synology), contains('ollama/ollama'));

    await tester.pumpWidget(MaterialApp(
      theme: bauSpurTheme(),
      home: Scaffold(
        body: KiEinrichtungKarte(
          key: const ValueKey(2),
          state: state,
          hardware: () async => (ramGb: 32.0, grafik: 'RTX 3070', vramGb: 8.0),
          modelle: (_) async => ['llama3.1:8b'],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bereit: llama3.1:8b auf diesem PC'), findsOneWidget);
    expect(find.text('vorhanden'), findsOneWidget);
  });
}
