import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/height.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/verteiler.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schema.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/decke/decke_page.dart';
import 'package:bauspur/ui/verteiler/verteiler_editor.dart';
import 'package:bauspur/ui/wandansicht/wandansicht_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Verteiler (Kern)', () {
    test('JSON hin und zurück, Abgänge ändern behält Belegung', () {
      final d = VerteilerDaten(abgaenge: 4, montage: Montage.aufputz, mischer: true, kreise: ['a', null, 'c', null]);
      final z = VerteilerDaten.ausJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(z.abgaenge, 4);
      expect(z.montage, Montage.aufputz);
      expect(z.mischer, isTrue);
      expect(z.kreise, ['a', null, 'c', null]);
      z.abgaengeSetzen(6);
      expect(z.kreise, ['a', null, 'c', null, null, null]);
      z.abgaengeSetzen(2);
      expect(z.kreise, ['a', null]);
    });

    test('Schrankbreite und Stückliste', () {
      final d = VerteilerDaten(abgaenge: 6);
      expect(d.schrankBreite, 850);
      final liste = {for (final (t, n) in d.stueckliste()) t: n};
      expect(liste['Heizkreisverteiler 6 Abgänge'], 1);
      expect(liste['Stellantrieb 230 V stromlos zu'], 6);
      expect(liste['Anschlussverschraubung Heizrohr'], 12);
      expect(liste.keys.any((t) => t.startsWith('Unterputz-Verteilerschrank 850')), isTrue);
      expect((d..mischer = true).schrankBreite, 1000);
    });

    test('Schrankumriss liegt in der Wand (Unterputz) bzw. davor (Aufputz)', () {
      const wand = (a: Punkt(0, 0), b: Punkt(4000, 0), dicke: 240.0);
      final d = VerteilerDaten(abgaenge: 3); // 550 breit
      final up = verteilerUmriss(const Punkt(1000, 300), d, [wand]);
      final ys = up.map((p) => p.y).toList()..sort();
      final xs = up.map((p) => p.x).toList()..sort();
      expect(ys.first, closeTo(120 - 110, 0.01));
      expect(ys.last, closeTo(120, 0.01));
      expect(xs.first, closeTo(1000 - 275, 0.01));
      expect(xs.last, closeTo(1000 + 275, 0.01));

      final ap = verteilerUmriss(const Punkt(1000, -300), d..montage = Montage.aufputz, [wand]);
      final ys2 = ap.map((p) => p.y).toList()..sort();
      expect(ys2.first, closeTo(-120 - 125, 0.01)); // andere Wandseite, vor der Wand
      expect(ys2.last, closeTo(-120, 0.01));

      final frei = verteilerUmriss(const Punkt(1000, 3000), d, [wand]);
      expect(frei.map((p) => p.y).reduce((a, b) => a < b ? a : b), closeTo(3000 - 125 / 2, 0.01));
    });

    test('Erfassungsbereich Präsenzmelder und Deckenobjekte', () {
      expect(erfassungsDurchmesser(2500), 1700 * 1.5 + 800);
      expect(erfassungsDurchmesser(500), 350);
    });

    test('Leitungslänge mit Höhen je Punkt zählt Steigstrecken', () {
      final o = Objekt(
        id: 'x',
        typId: 't',
        geschossId: 'g',
        raumId: null,
        kennung: 'K',
        punkte: const [Punkt(0, 0), Punkt(0, 0), Punkt(3000, 0)],
        z: 0,
        zBezug: Hoehenbezug.ffb,
        lage: 'in Wand',
        status: ObjektStatus.geplant,
        normkennzeichen: null,
        eigenschaften: const {'z_abs': [1200, 200, 200]},
      );
      expect(o.laenge, 4000);
    });
  });

  group('Projekt', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('bauspur_dv_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('Migration 10 ergänzt den Leitungstyp Heizrohr', () {
      var s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'M');
      expect(s.objekttypen().where((t) => t.kuerzel == 'HR').length, 1);
      // alten Stand nachbilden: Typ fehlt, Version 9
      s.db.execute("DELETE FROM objekttyp WHERE kuerzel = 'HR'");
      s.db.execute('ALTER TABLE raum DROP COLUMN art'); // kam erst mit Version 11
      s.db.execute('ALTER TABLE medium DROP COLUMN markierungen');
      s.db.execute('ALTER TABLE medium DROP COLUMN panorama');
      for (final t in ['stromkreis', 'schrankgeraet', 'schrank', 'tagebuch', 'aufgabe', 'pruefprotokoll']) {
        s.db.execute('DROP TABLE $t'); // kamen erst mit Version 12
      }
      s.db.userVersion = 9;
      final ordner = s.ordner;
      s.schliessen();
      s = ProjectStore.oeffnen(ordner);
      expect(s.db.userVersion, migrationen.length);
      final hr = s.objekttypen().where((t) => t.kuerzel == 'HR').toList();
      expect(hr.length, 1);
      expect(hr.single.geometrie, Geometrieart.linie);
      s.schliessen();
    });
  });

  group('Oberfläche', () {
    late Directory tmp;
    late ProjectStore store;
    late AppState state;
    late String raumId;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('bauspur_dvui_');
      store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'UI');
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      for (final (x1, y1, x2, y2) in [(0, 0, 4400, 0), (4400, 0, 4400, 3400), (4400, 3400, 0, 3400), (0, 3400, 0, 0)]) {
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
      }
      raumId = store.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: store.flaechenErkennen(g).single);
      state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))
        ..store = store
        ..geschossId = g;
    });

    tearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });

    Future<void> zeigen(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: w));
      await tester.pump();
    }

    Finder malflaeche(String painter) =>
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == painter);

    Objekttyp typ(String k) => store.objekttypen().firstWhere((t) => t.kuerzel == k);

    testWidgets('Deckenansicht: Leuchte setzen, Abhängung, von oben/unten', (tester) async {
      await zeigen(tester, DeckePage(state: state, raumId: raumId));
      expect(find.textContaining('Deckenansicht · Bad'), findsOneWidget);
      expect(find.text('Deckenaufbau'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      await tester.tapAt(tester.getCenter(malflaeche('_DeckenPainter')));
      await tester.pump();
      final o = store.objekte(state.geschossId!).single;
      expect(typ('LE').id, o.typId);
      expect(o.lage, 'an Decke');
      expect(o.zBezug, Hoehenbezug.rohdecke);
      expect(o.raumId, raumId);
      // Mitte des Raums (licht 4000 × 3000 ab 200/200)
      expect(o.punkte.single.x, closeTo(2200, 20));
      expect(o.punkte.single.y, closeTo(1700, 20));

      await tester.tap(find.text('von oben zeigen'));
      await tester.pump();
      expect(find.textContaining('von oben'), findsWidgets);

      // Abhängung eintragen → neue Objekte sitzen „in Decke“
      final rd = store.raeume(state.geschossId!).single.hoehen(store.geschoss(state.geschossId!)!).rohdecke;
      await tester.enterText(find.byType(TextFormField).first, '${rd - 200}');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(store.raeume(state.geschossId!).single.ukDecke, rd - 200);
      expect(find.textContaining('Abhängehöhe 200 mm'), findsOneWidget);
    });

    testWidgets('Verteiler-Editor: Heizkreise automatisch zuordnen', (tester) async {
      final g = state.geschossId!;
      final hv = store.objektAnlegen(geschossId: g, typ: typ('HV'), punkte: const [Punkt(400, 300)], raumId: raumId);
      store.objektAnlegen(
          geschossId: g, typ: typ('HK'), raumId: raumId, punkte: const [Punkt(300, 300), Punkt(2000, 300), Punkt(2000, 1500), Punkt(300, 1500)]);
      await zeigen(tester, VerteilerEditor(state: state, objektId: hv));
      expect(find.textContaining('Heizkreisverteiler'), findsWidgets);
      expect(find.textContaining('1 Heizkreis(e) noch ohne Abgang'), findsOneWidget);
      await tester.tap(find.text('Heizkreise automatisch zuordnen'));
      await tester.pump();
      final d = VerteilerDaten.ausJson(store.objekte(g).firstWhere((o) => o.id == hv).eigenschaften);
      expect(d.kreise.whereType<String>().length, 1);
      expect(find.textContaining('0 Heizkreis(e) noch ohne Abgang'), findsOneWidget);
      final hk = store.objekte(g).firstWhere((o) => o.typId == typ('HK').id);
      expect(hk.eigenschaften['verteiler'], hv);
      expect(hk.eigenschaften['zuleitung_mm'], 100);
    });

    testWidgets('Wandansicht: Heizrohr mit Steigstrecke zeichnen', (tester) async {
      final w = store.waende(state.geschossId!).first;
      await zeigen(tester, WandansichtPage(state: state, wandId: w.id, links: false));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      final c = tester.getCenter(malflaeche('_AnsichtPainter'));
      await tester.tapAt(c);
      await tester.pump();
      await tester.tapAt(c + const Offset(0, 80));
      await tester.pump();
      await tester.tapAt(c + const Offset(150, 80));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final o = store.objekte(state.geschossId!).single;
      expect(o.typId, typ('HR').id);
      final zs = o.zPunkte!;
      expect(zs.length, 3);
      expect(zs[0], greaterThan(zs[1])); // erst senkrecht nach unten
      expect(zs[1], zs[2]);
      expect(o.laenge, greaterThan((o.punkte.last - o.punkte.first).laenge));
    });
  });
}
