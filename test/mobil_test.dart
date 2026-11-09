import 'dart:io';

import 'package:bauspur/data/austausch.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/mobil/mobil_app.dart';
import 'package:bauspur/mobil/ordner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App: Messwert im Raum erfassen → Eingang → PC übernimmt', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_mob_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'M');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    const e = [(0, 0), (4000, 0), (4000, 3000), (0, 3000)];
    for (var i = 0; i < 4; i++) {
      store.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 240);
    }
    store.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: store.flaechenErkennen(g).single);
    planstandSchreiben(store);

    final geraet = Directory('${tmp.path}/geraet')..createSync();
    final app = MobilApp(
      ordner: LokalOrdner(store.ordner),
      einstellungen: await MobilEinstellungen.laden(ordner: geraet),
      puffer: await Puffer.laden(basis: geraet),
      kamera: (_) async => [0xFF, 0xD8, 0xFF, 0xD9],
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.text('Bad'), findsOneWidget);
    await tester.tap(find.text('Bad'));
    await tester.pump();
    await tester.tap(find.text('Messwert'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Wert'), '1250');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final ein = Directory('${store.ordner}/eingang').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    expect(ein.length, 1);
    final r = eingangUebernehmen(store);
    expect(r.uebernommen, 1);
    expect(store.tagebuch().single.text, contains('Messwert 1250 mm'));
    await tester.pumpWidget(const SizedBox());
    store.schliessen();
  });
}
