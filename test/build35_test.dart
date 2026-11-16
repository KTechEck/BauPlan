import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/dach.dart';
import 'package:bauspur/core/gelaende.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/sonne.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/bauphysik/sonne_dialog.dart';
import 'package:bauspur/ui/floorplan/gelaende_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sonnenstand und PV', () {
    // Berlin, 21.6. 11:15 UTC (13:15 MESZ): Sonne im Süden, ~61° hoch
    final st = sonnenstand(52.52, 13.4, DateTime.utc(2026, 6, 21, 11, 15));
    expect(st.hoehe, closeTo(60.9, 1.5));
    expect(st.azimut, closeTo(180, 6));
    final winter = sonnenstand(52.52, 13.4, DateTime.utc(2026, 12, 21, 11, 15));
    expect(winter.hoehe, closeTo(14, 1.5));
    expect(pvFaktor(51, 10, 35, 180), closeTo(1, 1e-9));
    expect(pvFaktor(51, 10, 35, 90), inInclusiveRange(0.7, 0.92));
    expect(pvFaktor(51, 10, 35, 0), lessThan(0.7));
    // Südfenster ohne Hindernis: Sonne im Winter, Nordfenster keine
    final sued = sonnenstunden(breite: 51, laenge: 10, tag: DateTime(2026, 12, 21), nordGrad: 0, px: 0, py: 0, nx: 0, ny: 1, z: 1500);
    final nord = sonnenstunden(breite: 51, laenge: 10, tag: DateTime(2026, 12, 21), nordGrad: 0, px: 0, py: 0, nx: 0, ny: -1, z: 1500);
    expect(sued, greaterThan(5));
    expect(nord, 0);
    // hohe Wand 2 m vor dem Südfenster verschattet im Winter
    final zu = sonnenstunden(breite: 51, laenge: 10, tag: DateTime(2026, 12, 21), nordGrad: 0, px: 0, py: 0, nx: 0, ny: 1, z: 1500, hindernisse: [(ax: -20000, ay: 2000, bx: 20000, by: 2000, oben: 9000)]);
    expect(zu, lessThan(sued));
  });

  test('Gelände: Interpolation, Höhenlinien, Hinweise', () {
    const p = [Hoehenpunkt(0, 0, -300), Hoehenpunkt(10000, 0, -300), Hoehenpunkt(0, 10000, -300), Hoehenpunkt(10000, 10000, -300), Hoehenpunkt(5000, -6000, 500)];
    expect(gelaendeHoehe(p, 0, 0), -300);
    expect(gelaendeHoehe(p, 5000, -5000)!, greaterThan(0));
    expect(hoehenlinien(p, -2000, -8000, 12000, 12000), isNotEmpty);
    final h = gelaendeHinweise(p, 2000, 2000, 8000, 8000);
    expect(h.any((x) => x.contains('Nordseite')), isTrue, reason: 'Hang oben fällt zum Haus');
  });

  test('Dachformen: Höhen und Dachstuhl', () {
    const g = (x0: 0.0, y0: 0.0, x1: 10000.0, y1: 8000.0);
    const walm = DachEinstellung(form: Dachform.walm, neigung: 30, kniestock: 500);
    // Walm: am Giebelrand niedrig, in der Mitte hoch
    expect(dachFlaecheHoehe(walm, g, const Punkt(100, 4000)), lessThan(dachFlaecheHoehe(walm, g, const Punkt(5000, 4000))));
    const sattel = DachEinstellung(form: Dachform.sattel, neigung: 30, kniestock: 500);
    expect(dachFlaecheHoehe(sattel, g, const Punkt(100, 4000)), closeTo(dachFlaecheHoehe(sattel, g, const Punkt(5000, 4000)), 1));
    const mans = DachEinstellung(form: Dachform.mansard, neigung: 20, neigungUnten: 70, knick: 2000, kniestock: 300);
    expect(dachFlaecheHoehe(mans, g, const Punkt(5000, 4000)), greaterThan(2300));
    final teile = dachstuhl(walm, g);
    expect(teile.where((t) => t.name == 'Gratsparren'), hasLength(4));
    expect(holzliste(teile).keys.any((k) => k.startsWith('Fußpfette')), isTrue);
  });

  testWidgets('Sonne- und Gelände-Dialog öffnen, Wand teilen', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_b35_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'S');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final w = store.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 9000, y2: 0, dicke: 300);
    final neu = store.wandTeilen(w, 4000)!;
    expect(store.waende(g).firstWhere((x) => x.id == w).x2, 4000);
    expect(store.waende(g).firstWhere((x) => x.id == neu).x1, 4000);
    store.einstellungSetzen('gelaende', gelaendeJson(const [Hoehenpunkt(-3000, -3000, -400), Hoehenpunkt(12000, 3000, -800)]));
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))
      ..store = store
      ..geschossId = g;
    await tester.pumpWidget(MaterialApp(
      theme: bauSpurTheme(),
      home: Scaffold(body: Builder(builder: (c) => Column(children: [
            TextButton(onPressed: () => sonneDialog(c, state), child: const Text('S')),
            TextButton(onPressed: () => gelaendeDialog(c, state), child: const Text('G')),
          ]))),
    ));
    await tester.tap(find.text('S'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sonnenbahn'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hang als Vorlage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
