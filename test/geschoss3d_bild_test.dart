import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/floorplan/geschoss_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('3D-Bild erzeugen', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_3db_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'D');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final ids = <String>[];
    for (final (x1, y1, x2, y2) in [(0, 0, 6000, 0), (6000, 0, 6000, 4000), (6000, 4000, 0, 4000), (0, 4000, 0, 0), (3500, 0, 3500, 4000)]) {
      ids.add(store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: x1 == 3500 ? 115 : 365));
    }
    store.oeffnungAnlegen(wandId: ids[0], art: OeffnungsArt.fenster, abstand: 1000, breite: 1200, hoehe: 1300, bruestung: 900);
    store.oeffnungAnlegen(wandId: ids[4], art: OeffnungsArt.tuer, abstand: 1500, breite: 885, hoehe: 2010, bruestung: 0);
    final fl = store.flaechenErkennen(g);
    store.raumAnlegen(geschossId: g, name: 'Wohnen', kuerzel: 'WO', flaeche: fl[0]);
    store.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BA', flaeche: fl[1]);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: RepaintBoundary(key: key, child: Geschoss3d(state: state, geschossId: g)))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final out = Platform.environment['BAUSPUR_BILD'];
    if (out != null) {
      await tester.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File(out).writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });
}
