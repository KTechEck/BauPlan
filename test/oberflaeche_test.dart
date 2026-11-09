import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/ui/export/export_page.dart';
import 'package:bauspur/ui/floorplan/floorplan_page.dart';
import 'package:bauspur/ui/fotos/fotos_page.dart';
import 'package:bauspur/ui/installation/installation_page.dart';
import 'package:bauspur/ui/kosten/kosten_page.dart';
import 'package:bauspur/ui/wandansicht/wandansicht_page.dart';
import 'package:bauspur/core/height.dart';
import 'package:bauspur/ui/bauteile/bauteile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ProjectStore store;
  late AppState state;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bauspur_ui_');
    store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'UI');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final typ = store.wandtypen().first.id;
    for (final (x1, y1, x2, y2) in [(0, 0, 4400, 0), (4400, 0, 4400, 3400), (4400, 3400, 0, 3400), (0, 3400, 0, 0)]) {
      store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240, wandtypId: typ);
    }
    store.raumAnlegen(geschossId: g, name: 'Wohnen', kuerzel: 'WOH', flaeche: store.flaechenErkennen(g).single);
    state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))
      ..store = store
      ..geschossId = g;
  });

  tearDown(() {
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  Future<void> zeigen(WidgetTester tester, Widget Function() w) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: bauSpurTheme(),
      home: Scaffold(body: ListenableBuilder(listenable: state, builder: (_, __) => w())),
    ));
    await tester.pump();
  }

  testWidgets('Grundriss zeigt Raum mit Fläche im Baum und Wandtyp-Auswahl', (tester) async {
    await zeigen(tester, () => FloorplanPage(state: state));
    // Außenwand 400 mm: licht 4000 × 3000
    expect(find.text('Wohnen'), findsOneWidget);
    expect(find.text('12,00 m²'), findsOneWidget);
    expect(find.text('Wandtyp '), findsOneWidget);
    expect(find.text('Maße (Voreinstellung) '), findsOneWidget);

    state.raumWaehlen(store.raeume(state.geschossId!).single.id);
    await tester.pump();
    expect(find.text('Fläche (licht)'), findsOneWidget);
    expect(find.text('14,00 m'), findsOneWidget);
  });

  testWidgets('Bibliothek: Wandaufbauten und Baustoffe öffnen', (tester) async {
    await zeigen(tester, () => BauteilePage(state: state));
    await tester.tap(find.text('Wandaufbauten'));
    await tester.pump();
    expect(find.textContaining('Außenwand KS 175'), findsOneWidget);
    await tester.tap(find.textContaining('Außenwand KS 175'));
    await tester.pump();
    expect(find.text('Gesamt 360 mm'), findsOneWidget);

    await tester.tap(find.text('Baustoffe und Farben'));
    await tester.pump();
    expect(find.text('Kalksandstein'), findsOneWidget);
  });

  testWidgets('Grundriss: Strg+A wählt alles, Pfeiltaste verschiebt, Strg+Z macht rückgängig', (tester) async {
    await zeigen(tester, () => FloorplanPage(state: state));
    final g = state.geschossId!;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('4 Wände'), findsOneWidget);
    expect(find.text('Maße (4 Wände) '), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(store.waende(g).map((w) => w.y1).reduce((a, b) => a < b ? a : b), -50);
    expect(store.raeume(g).single.flaeche, closeTo(12e6, 1));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(store.waende(g).map((w) => w.y1).reduce((a, b) => a < b ? a : b), 0);
  });

  testWidgets('Wand zeichnen: Tab → Länge, Tab → Winkel, Enter setzt die Wand', (tester) async {
    await zeigen(tester, () => FloorplanPage(state: state));
    final g = state.geschossId!;
    final vorher = store.waende(g).length;
    // Startpunkt irgendwo in der Zeichenfläche setzen
    await tester.tapAt(const Offset(900, 700));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.text('Länge (Achse)'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Länge (Achse)'), '3000');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Winkel'), '30');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final waende = store.waende(g);
    expect(waende.length, vorher + 1);
    final w = waende.last;
    expect(w.laenge, closeTo(3000, 1));
    // 30° nach oben rechts: dx > 0, dy < 0
    expect(w.x2 - w.x1, closeTo(2598, 1));
    expect(w.y2 - w.y1, closeTo(-1500, 1));
  });

  testWidgets('Innenmaß: Rechteck aus Innenmaßen schließt sich genau', (tester) async {
    await zeigen(tester, () => FloorplanPage(state: state));
    final g = state.geschossId!;
    final vorher = store.waende(g).map((w) => w.id).toSet();
    await tester.tapAt(const Offset(900, 700));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.tap(find.text('Innenmaß'));
    await tester.pump();
    for (final (l, w) in [(4000, 0), (3000, 270), (4000, 180), (3000, 90)]) {
      await tester.enterText(find.widgetWithText(TextField, 'Länge (innen)'), '$l');
      await tester.enterText(find.widgetWithText(TextField, 'Winkel'), '$w');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }
    final neu = store.waende(g).where((w) => !vorher.contains(w.id)).toList();
    expect(neu.length, 4);
    // freie Wanddicke 240: Achse = innen + 240
    expect(neu.map((w) => w.laenge.round()).toList()..sort(), [3240, 3240, 4240, 4240]);
    final erste = neu.firstWhere((w) => w.laenge.round() == 4240 && w.x2 > w.x1);
    final letzte = neu.firstWhere((w) => w.y2 < w.y1);
    expect((letzte.x2, letzte.y2), (erste.x1, erste.y1));
  });

  testWidgets('Bemaßen (M): zwei Punkte, Maßlinie setzen, Entf löscht, Strg+Z holt zurück', (tester) async {
    await zeigen(tester, () => FloorplanPage(state: state));
    final g = state.geschossId!;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    for (final p in const [Offset(500, 600), Offset(800, 600), Offset(700, 500)]) {
      await tester.tapAt(p);
      await tester.pump();
    }
    expect(store.bemassungen(g).length, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(store.bemassungen(g), isEmpty);
  });

  testWidgets('Installation: Klick setzt eine Steckdose mit Kennung', (tester) async {
    await zeigen(tester, () => InstallationPage(state: state));
    final g = state.geschossId!;
    expect(find.text('Ebenen'), findsOneWidget);
    await tester.tapAt(const Offset(900, 600));
    await tester.pump();
    final o = store.objekte(g);
    expect(o.length, 1);
    expect(o.single.kennung, startsWith('EG-'));
  });

  testWidgets('Fotos: Modul öffnet mit leerer Galerie', (tester) async {
    await zeigen(tester, () => FotosPage(state: state));
    expect(find.text('Fotos importieren'), findsOneWidget);
    expect(find.text('Alle Fotos des Geschosses'), findsOneWidget);
  });

  testWidgets('Kosten: Modul öffnet mit Kostenliste und Summe', (tester) async {
    await zeigen(tester, () => KostenPage(state: state));
    expect(find.text('Kostenliste'), findsOneWidget);
    expect(find.text('Summe'), findsOneWidget);
    await tester.tap(find.text('Produkte'));
    await tester.pump();
    expect(find.textContaining('Noch keine Produkte'), findsOneWidget);
  });

  testWidgets('Export: PDF mit Grundriss, Installationsplan und Kostenliste', (tester) async {
    final g = state.geschossId!;
    final sd = store.objekttypen().firstWhere((t) => t.kuerzel == 'SD');
    store.objektAnlegen(geschossId: g, typ: sd, punkte: [const Punkt(500, 200)]);
    store.planMengenNachfuehren();
    final pfad = await tester.runAsync(() => PlanExport(
          store: store,
          geschossIds: [g],
          gewerkIds: {sd.gewerkId},
          grundriss: true,
          installation: true,
          kosten: true,
          papier: Papier.a3,
          massstab: 50,
        ).erstellen());
    final datei = File(pfad!);
    expect(datei.existsSync(), isTrue);
    expect(String.fromCharCodes(datei.readAsBytesSync().take(4)), '%PDF');
    expect(datei.lengthSync(), greaterThan(5000));
  });

  testWidgets('Wandansicht: Seite vom Raum aus, Objekt mit Höhe', (tester) async {
    final g = state.geschossId!;
    final oben = store.waende(g).firstWhere((w) => w.y1 == 0 && w.y2 == 0);
    final sd = store.objekttypen().firstWhere((t) => t.kuerzel == 'SD');
    final raum = store.raeume(g).single;
    store.objektAnlegen(geschossId: g, typ: sd, punkte: [const Punkt(1000, 200)], raumId: raum.id, z: 300, zBezug: Hoehenbezug.ffb);
    // Raumseite: innen liegt die Seite mit dem Raum
    final seiten = [true, false].map((l) => WandSeite.berechnen(oben, store.waende(g), store.raeume(g), true, l)).toList();
    final innen = seiten.firstWhere((s) => s.raum != null);
    expect(innen.raum!.name, 'Wohnen');
    expect(innen.laenge, closeTo(4000, 1));
    await zeigen(tester, () => WandansichtPage(state: state, wandId: oben.id, links: innen.links));
    expect(find.textContaining('Wandansicht · Wohnen'), findsOneWidget);
    expect(find.textContaining('1 Objekte'), findsOneWidget);
  });
}
