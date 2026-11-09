import 'dart:io';

import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schrank_models.dart';
import 'package:bauspur/ui/export/export_page.dart';
import 'package:bauspur/ui/export/hausdoku.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Hausdokumentation als PDF mit Inhaltsverzeichnis', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('bauspur_hd_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Haus');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    for (final (x1, y1, x2, y2) in [(0, 0, 4400, 0), (4400, 0, 4400, 3400), (4400, 3400, 0, 3400), (0, 3400, 0, 0)]) {
      store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
    }
    store.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: store.flaechenErkennen(g).single);
    final s = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1');
    final ls = store.geraetAnlegen(schrankId: s, reihe: 0, position: 0, art: GeraeteArt.ls, kennzeichen: '-F1');
    store.stromkreisAnlegen(schrankId: s, nummer: '1', bezeichnung: 'Bad', schutzId: ls);
    store.tagebuchAnlegen(datum: DateTime(2026, 11, 7), text: 'Start');
    store.kostenpositionAnlegen(text: 'Kabel', mengeMilli: 10000, einheit: 'm', einzelCent: 100);
    final hd = HausDokumentation(store: store, papier: Papier.a4);
    final datei = (await tester.runAsync(() => hd.erstellen()))!;
    expect(File(datei).existsSync(), isTrue);
    expect(File(datei).lengthSync(), greaterThan(5000));
    expect(datei, contains('Hausdokumentation_Haus'));
  });
}

