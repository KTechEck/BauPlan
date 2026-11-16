import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/dach.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/floorplan/geschoss_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final form in [Dachform.sattel, Dachform.walm, Dachform.mansard, Dachform.krueppelwalm, Dachform.pult, Dachform.zelt]) {
    testWidgets('Dach ${form.name} in 3D', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tmp = Directory.systemTemp.createTempSync('bauspur_dach_');
      final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'D');
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      for (final (x1, y1, x2, y2) in [(0, 0, 10000, 0), (10000, 0, 10000, 8000), (10000, 8000, 0, 8000), (0, 8000, 0, 0)]) {
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 300);
      }
      store.einstellungSetzen('dach_$g', DachEinstellung(form: form, neigung: 38, kniestock: 800, kehlbalken: form == Dachform.sattel ? 2600 : 0).toJson());
      final d = DachEinstellung(form: form, neigung: 38, kniestock: 800);
      final teile = dachstuhl(d, (x0: -150.0, y0: -150.0, x1: 10150.0, y1: 8150.0));
      expect(teile, isNotEmpty);
      expect(holzliste(teile).keys.any((k) => k.contains('Sparren')), isTrue);
      final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: RepaintBoundary(key: key, child: Geschoss3d(state: state, geschossId: g)))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final out = Platform.environment['BAUSPUR_DACH'];
      if (out != null) {
        await tester.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/dach_${form.name}.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
  }
}
