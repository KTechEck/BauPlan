import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/licht.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/decke/decke_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const raum = [Punkt(0, 0), Punkt(4000, 0), Punkt(4000, 3000), Punkt(0, 3000)];

  test('Beleuchtungsstärke: senkrecht unter der Leuchte, Kegel, Abstandsgesetz', () {
    const l = (x: 0.0, y: 0.0, hoehe: 2750.0, lumen: 1000.0, winkel: 120.0);
    // Raumwinkel 2π(1−cos60°) = π → I = 1000/π cd; h = 2 m → E = I / 4
    expect(beleuchtungsstaerke(const Punkt(0, 0), [l]), closeTo(1000 / 3.14159265 / 4, 0.5));
    // außerhalb des Kegels dunkel
    expect(beleuchtungsstaerke(const Punkt(6000, 0), [l]), 0);
    // doppelte Höhe über Arbeitsebene → ein Viertel
    const hoch = (x: 0.0, y: 0.0, hoehe: 4750.0, lumen: 1000.0, winkel: 120.0);
    expect(beleuchtungsstaerke(const Punkt(0, 0), [hoch]), closeTo(beleuchtungsstaerke(const Punkt(0, 0), [l]) / 4, 0.2));
  });

  test('Raster: Mittelwert, Gleichmäßigkeit, indirekter Anteil', () {
    final leer = lichtraster(raum, const [], raster: 500);
    expect(leer.zellen.length, 8 * 6);
    expect(leer.mittel, 0);
    final indirekt = lichtraster(raum, const [], raster: 500, indirektLumen: 2400, indirektFaktor: 0.5);
    expect(indirekt.mittel, closeTo(2400 * 0.5 / 12, 0.01));
    expect(indirekt.gleichmaessigkeit, closeTo(1, 1e-9));
    final vier = lichtraster(raum, const [
      (x: 1000.0, y: 750.0, hoehe: 2600.0, lumen: 1000.0, winkel: 100.0),
      (x: 3000.0, y: 750.0, hoehe: 2600.0, lumen: 1000.0, winkel: 100.0),
      (x: 1000.0, y: 2250.0, hoehe: 2600.0, lumen: 1000.0, winkel: 100.0),
      (x: 3000.0, y: 2250.0, hoehe: 2600.0, lumen: 1000.0, winkel: 100.0),
    ], raster: 250);
    expect(vier.mittel, greaterThan(100));
    expect(vier.gleichmaessigkeit, inExclusiveRange(0, 1));
    expect(vier.maximum, greaterThan(vier.mittel));
    expect(zielBeleuchtung('Küche'), 300);
    expect(zielBeleuchtung('Flur EG'), 100);
    expect(lichtFarbe(0, 200) >> 24 & 0xFF, 0xA0);
  });

  test('LED-Streifen: Netzteil und Einspeisungen', () {
    final p = ledPruefung(12000, 10, '24 V');
    expect(p.leistung, 120);
    expect(p.netzteil, 150);
    expect(p.einspeisungen, 2);
    expect(p.hinweise.first, contains('2 Einspeisungen'));
    expect(ledPruefung(3000, 5, '230 V').hinweise, isEmpty);
  });

  test('Melder: Erfassung und nicht erfasste Flächen', () {
    final e = erfassung(2500);
    expect(e.praesenz, 1700 * 1.5 + 800);
    expect(e.quer, greaterThan(e.frontal));
    expect(nichtErfasst(raum, const [(Punkt(2000, 1500), 5000)]), isEmpty);
    expect(nichtErfasst(raum, const [(Punkt(0, 0), 1000)]).length, greaterThan(100));
  });

  testWidgets('Deckenansicht: LED-Streifen zeichnen und Lichtverteilung', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_li_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'L');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    for (final (x1, y1, x2, y2) in [(0, 0, 4400, 0), (4400, 0, 4400, 3400), (4400, 3400, 0, 3400), (0, 3400, 0, 0)]) {
      store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
    }
    final raumId = store.raumAnlegen(geschossId: g, name: 'Küche', kuerzel: 'KUE', flaeche: store.flaechenErkennen(g).single);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))
      ..store = store
      ..geschossId = g;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: DeckePage(state: state, raumId: raumId)));
    await tester.pump();
    expect(find.textContaining('Em 0 lx'), findsOneWidget);
    final flaeche = find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_DeckenPainter');
    final c = tester.getCenter(flaeche);

    // Leuchte setzen → Em steigt
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    await tester.tapAt(c);
    await tester.pump();
    expect(find.textContaining('Em 0 lx'), findsNothing);

    // LED-Streifen
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    await tester.tapAt(c + const Offset(-100, 80));
    await tester.pump();
    await tester.tapAt(c + const Offset(100, 80));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final lb = store.objekttypen().firstWhere((t) => t.kuerzel == 'LB');
    final streifen = store.objekte(g).where((o) => o.typId == lb.id).toList();
    expect(streifen.length, 1);
    expect(streifen.single.lage, 'an Decke');
    expect(find.textContaining('1 LED-Streifen'), findsOneWidget);

    await tester.tap(find.text('Lichtverteilung'));
    await tester.pump();
    expect(find.text('Zielwert mittlere Beleuchtungsstärke'), findsOneWidget);
  });
}
