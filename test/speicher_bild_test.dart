// Bildschirmfotos zu „Speicher und Abgleich“ (PC) und „Verbindung“ (App).
// Läuft nur mit gesetzter Umgebungsvariable BAUSPUR_BILD (Zielordner).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/speicher.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/mobil/ordner.dart';
import 'package:bauspur/mobil/verbindung.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/speicher_einstellungen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _ziel = Platform.environment['BAUSPUR_BILD'];
final _rahmen = GlobalKey();

Future<void> _schriften() async {
  final mf = '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/tkuns/dev/flutter'}/bin/cache/artifacts/material_fonts';
  for (final e in {
    'Roboto': ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf'],
    'MaterialIcons': ['materialicons-regular.otf']
  }.entries) {
    final l = FontLoader(e.key);
    for (final d in e.value) {
      l.addFont(Future.value(ByteData.sublistView(File('$mf/$d').readAsBytesSync())));
    }
    await l.load();
  }
}

Future<void> _foto(WidgetTester tester, String name) async {
  await tester.pump();
  final ro = _rahmen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_ziel/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _app(Widget kind) => RepaintBoundary(key: _rahmen, child: MaterialApp(debugShowCheckedModeBanner: false, theme: bauSpurTheme(), home: kind));

void main() {
  testWidgets('Speicher-Bilder', (tester) async {
    if (_ziel == null) return;
    await tester.runAsync(_schriften);
    final tmp = Directory.systemTemp.createTempSync('bauspur_bild_');
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;

    tester.view.physicalSize = const Size(1000, 1000);
    final settings = AppSettings.inDatei(File('${tmp.path}/e.json'))..speicher = {'art': 'netz', 'code': '482913', 'netz_pfad': r'\\NAS\BauSpur'};
    final state = AppState(settings);
    await tester.pumpWidget(_app(Scaffold(body: SpeicherEinstellungenAnsicht(state: state))));
    await _foto(tester, 'speicher_pc');

    tester.view.physicalSize = const Size(390, 800);
    final e = await tester.runAsync(() => MobilEinstellungen.laden(ordner: tmp));
    final ordner = FernOrdner(e!, tmp, suche: () async => <GefundenerPc>[(adresse: '192.168.178.20:47824', name: 'DESKTOP-TIM', projekt: 'Wohnhaus')]);
    await tester.pumpWidget(_app(VerbindungSeite(ordner: ordner, fertig: () async {})));
    await tester.pump(const Duration(milliseconds: 100));
    await _foto(tester, 'speicher_app');
  });
}
