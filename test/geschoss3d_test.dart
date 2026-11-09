import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/floorplan/geschoss_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Geschoss in 3D mit Wänden, Gerät, Leitung und eigener Verlegeebene', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_3d_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'D');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    const e = [(0, 0), (4000, 0), (4000, 3000), (0, 3000)];
    for (var i = 0; i < 4; i++) {
      store.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 240);
    }
    final sd = store.objekttypen().firstWhere((t) => t.kuerzel == 'SD');
    final lr = store.objekttypen().firstWhere((t) => t.kuerzel == 'LR');
    store.objektAnlegen(geschossId: g, typ: sd, punkte: const [Punkt(500, 130)]);
    final l = store.objektAnlegen(geschossId: g, typ: lr, punkte: const [Punkt(500, 500), Punkt(3000, 500)], lage: 'Dämmlage');
    store.objektAendern(l, {'eigenschaften': jsonEncode({'breite_mm': 25})});
    store.einstellungSetzen('verlegeebenen', [
      {'name': 'Dämmlage', 'von_mm': 20, 'bis_mm': 60, 'bezug': 'über Rohdecke', 'farbe': 0xFF1098AD},
    ]);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: Geschoss3d(state: state, geschossId: g))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Kollision'), findsOneWidget);
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });
}
