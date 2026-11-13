// Bildschirmfotos der wichtigsten Ansichten zur Sichtprüfung. Läuft nur mit
// gesetzter Umgebungsvariable BAUSPUR_BILD (Zielordner), sonst übersprungen.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schrank_models.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _ziel = Platform.environment['BAUSPUR_BILD'];
final _rahmen = GlobalKey();

Future<void> _schriften() async {
  Future<void> laden(String familie, List<String> dateien) async {
    final l = FontLoader(familie);
    for (final d in dateien) {
      if (File(d).existsSync()) l.addFont(Future.value(ByteData.sublistView(File(d).readAsBytesSync())));
    }
    await l.load();
  }

  final flutter = Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/tkuns/dev/flutter';
  final mf = '$flutter/bin/cache/artifacts/material_fonts';
  await laden('Roboto', ['$mf/roboto-regular.ttf', '$mf/roboto-medium.ttf', '$mf/roboto-bold.ttf']);
  await laden('MaterialIcons', ['$mf/materialicons-regular.otf']);
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

void main() {
  testWidgets('Bildschirmfotos', (tester) async {
    if (_ziel == null) return;
    final alt = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) alt?.call(d);
    };
    addTearDown(() => FlutterError.onError = alt);
    await tester.runAsync(_schriften);
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_bild_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Musterhaus');
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    state.geschossId = g;
    // Zwei Räume mit T-Stoß aus zwei Wandstücken
    for (final (x1, y1, x2, y2, d) in [
      (0, 0, 4000, 0, 365), (4000, 0, 8000, 0, 365), (8000, 0, 8000, 5000, 365), (8000, 5000, 4000, 5000, 365),
      (4000, 5000, 0, 5000, 365), (0, 5000, 0, 0, 365), (4000, 0, 4000, 5000, 115),
    ]) {
      store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: d, zustand: WandZustand.bestand);
    }
    store.waendeZusammenfuehren(g); // wie beim Öffnen: geteilte Stücke werden eine Wand
    for (final (f, name) in ProjectStore.erkenneAusWaenden(store.waende(g)).indexed.map((e) => (e.$2, ['Wohnen', 'Bad'][e.$1 % 2]))) {
      store.raumAnlegen(geschossId: g, name: name, kuerzel: name.substring(0, 2).toUpperCase(), flaeche: f);
    }
    final w = store.waende(g).first;
    store.oeffnungAnlegen(wandId: w.id, art: OeffnungsArt.fenster, abstand: 1200, breite: 1230, hoehe: 1480, bruestung: 900);
    final sid = store.schrankAnlegen(name: 'UV EG', kennzeichen: 'UV1', reihen: 4, teJeReihe: 12);
    final fi = store.geraetAnlegen(schrankId: sid, reihe: 0, position: 0, art: GeraeteArt.rcd, kennzeichen: '-F1', pole: 4, nennstrom: 40, fehlerstrom: 30);
    store.geraetAnlegen(schrankId: sid, reihe: 0, position: 4, art: GeraeteArt.ls, kennzeichen: '-F2', nennstrom: 16, charakteristik: 'B', phase: 'L1', vorgeschaltetId: fi);

    final theme = bauSpurTheme().copyWith(textTheme: bauSpurTheme().textTheme.apply(fontFamily: 'Roboto'));
    await tester.pumpWidget(RepaintBoundary(key: _rahmen, child: MaterialApp(theme: theme, home: ListenableBuilder(listenable: state, builder: (_, __) => Shell(state: state)))));
    for (final (modul, name) in [
      (Modul.grundriss, 'grundriss'),
      (Modul.installation, 'installation'),
      (Modul.verteiler, 'schrank'),
      (Modul.bauteile, 'bauteile'),
      (Modul.bauphysik, 'heizlast'),
    ]) {
      state.modulWaehlen(modul);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      if (modul == Modul.verteiler) {
        final t = find.text('UV EG');
        if (t.evaluate().isNotEmpty) await tester.tap(t.first);
        await tester.pump();
      }
      if (modul == Modul.bauphysik) {
        final t = find.text('Wohnen');
        if (t.evaluate().isNotEmpty) await tester.tap(t.first);
        await tester.pump();
      }
      await _foto(tester, name);
    }
    if (_ziel != null) File('$_ziel/bild_ok.txt').writeAsStringSync(jsonEncode({'ok': true}));
    store.schliessen();
  });
}
