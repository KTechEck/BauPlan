import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/bauelemente.dart';
import 'package:bauspur/core/heizlast.dart';
import 'package:bauspur/core/ki.dart';
import 'package:bauspur/core/pdf_text.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/bauelement_bibliothek.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/bauphysik/bauphysik_page.dart';
import 'package:bauspur/ui/bauteile/bauteile_page.dart';
import 'package:bauspur/ui/floorplan/einbaudetail_page.dart';
import 'package:bauspur/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

class _KiAttrappe implements KiAnbieter {
  @override
  bool get extern => false;
  @override
  String get name => 'Test';
  @override
  Future<String> fragen(String system, String frage) async =>
      'Hier: {"name": "Fenster X", "hersteller": "Muster", "uw": "0,72", "verglasung": "3-fach", "unsinn": 5}';
}

void main() {
  group('Bauelemente', () {
    test('Werte aus Datenblatt-Text erkennen', () {
      const text = 'Profilsystem 82 MD, Bautiefe 82 mm, Uw = 0,78 W/(m²K) bei Ug 0,5 W/(m²K), Uf = 1,0. '
          'g-Wert 0,52 · Schalldämmung Rw 36 dB · Prüfmaß 1230 x 1480 mm · 3-fach Isolierverglasung, RC2';
      final w = datenblattWerte(text, BauelementKategorie.fenster);
      expect(w['uw'], 0.78);
      expect(w['ug'], 0.5);
      expect(w['uf'], 1);
      expect(w['bautiefe'], 82);
      expect(w['rw'], 36);
      expect(w['g_wert'], 0.52);
      expect(w['breite'], 1230);
      expect(w['hoehe'], 1480);
      expect(w['verglasung'], '3-fach');
      expect(w['rc'], 'RC2');
      final ls = datenblattWerte('Leitungsschutzschalter C16, 1 TE, Schaltvermögen 10 kA', BauelementKategorie.schrankgeraet);
      expect(ls['charakteristik'], 'C');
      expect(ls['nennstrom'], 16);
      expect(ls['te'], 1);
      expect(ls['schaltvermoegen'], 10);
    });

    test('KI-Antwort lesen und bereinigen', () {
      final m = kiJsonLesen('Antwort: {"uw": "0,72", "verglasung": "3-Fach", "rc": "RC9", "x": 1} Ende')!;
      final w = kiWerteBereinigen(m, BauelementKategorie.fenster);
      expect(w, {'uw': 0.72, 'verglasung': '3-fach'});
      expect(kiJsonLesen('kein json'), isNull);
      expect(kiDatenblattAnfrage('Text', BauelementKategorie.fenster), contains('"uw"'));
    });

    test('Text aus PDF lesen', () async {
      final doc = pw.Document();
      doc.addPage(pw.Page(build: (_) => pw.Column(children: [pw.Text('Bautiefe 82 mm'), pw.Text('Uw = 0,8 W/(m2K)')])));
      final t = pdfText(await doc.save());
      expect(t.replaceAll(RegExp(r'\s+'), ' '), contains('Bautiefe 82 mm'));
      expect(datenblattWerte(t, BauelementKategorie.fenster)['uw'], 0.8);
    });

    test('Bibliothek speichert, legt Beispiele an und kopiert ins Projekt', () {
      final tmp = Directory.systemTemp.createTempSync('bauspur_bib_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final bib = BauelementBibliothek(Directory('${tmp.path}/b'));
      expect(bib.inKategorie(BauelementKategorie.fenster).length, greaterThanOrEqualTo(2));
      final e = Bauelement(id: bib.neueId(), kategorie: BauelementKategorie.tuer, name: 'Haustür Test', daten: {'ud': 0.9});
      bib.speichern(e);
      final bib2 = BauelementBibliothek(Directory('${tmp.path}/b'));
      expect(bib2.element(e.id)?.zahl('ud'), 0.9);
      expect(bib2.element(e.id)?.kurzdaten, contains('0,9 Ud'));
      final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'P');
      addTearDown(store.schliessen);
      BauelementBibliothek.insProjekt(store, e);
      bib2.loeschen(e.id);
      expect(bib2.fuerProjekt(store, e.id)?.name, 'Haustür Test');
      expect(bib2.auswahl(store, BauelementKategorie.tuer).any((x) => x.id == e.id), isTrue);
    });
  });

  group('Heizlast', () {
    // Zwei Räume 4 × 4 m nebeneinander, Außenwände rundum, Innenwand dazwischen
    List<HlWand> waende() {
      HlWand w(String id, double x1, double y1, double x2, double y2) =>
          HlWand(id: id, a: Punkt(x1, y1), b: Punkt(x2, y2), dicke: 300, u: 0.3, uInnen: 1.5);
      return [
        w('s', 0, 0, 8000, 0),
        w('o', 8000, 0, 8000, 4000),
        w('n', 8000, 4000, 0, 4000),
        w('w', 0, 4000, 0, 0),
        w('i', 4000, 0, 4000, 4000),
      ];
    }

    List<Punkt> quadrat(double x) => [Punkt(x + 150, 150), Punkt(x + 3850, 150), Punkt(x + 3850, 3850), Punkt(x + 150, 3850)];

    test('Transmission, Fenster, Innenwand, Boden, Lüftung', () {
      final raeume = [
        HlRaum(id: 'a', name: 'Wohnen', umriss: quadrat(0), hoehe: 2500, temperatur: 20, boden: Gegen.erdreich, uBoden: 0.3),
        HlRaum(id: 'b', name: 'Bad', umriss: quadrat(4000), hoehe: 2500, temperatur: 24, luftwechsel: 1.5),
      ];
      final oe = [HlOeffnung(wandId: 's', abstand: 1000, breite: 1000, hoehe: 1000, u: 1.0)];
      final e = heizlastBerechnen(raeume, waende(), oe, const HlParameter(normAussen: -10, jahresmittel: 10, deltaUwb: 0.05));
      final wohnen = e.firstWhere((x) => x.raum.id == 'a'), bad = e.firstWhere((x) => x.raum.id == 'b');
      // Fenster: 1 m² · 1,0 · 30 K
      expect(wohnen.posten.firstWhere((p) => p.bauteil.startsWith('Fenster')).leistung, closeTo(30, 0.01));
      // Innenwand: Wohnen 20 °C verliert nichts an das Bad, das Bad gibt an Wohnen ab
      final innen = bad.posten.where((p) => p.bauteil.startsWith('Innenwand')).single;
      expect(innen.deltaT, 4);
      expect(wohnen.posten.where((p) => p.bauteil.startsWith('Innenwand') && p.leistung > 0), isEmpty);
      expect(wohnen.posten.any((p) => p.bauteil.contains('Erdreich')), isTrue);
      expect(wohnen.lueftung, closeTo(0.34 * 0.5 * (3.7 * 3.7 * 2.5) * 30, 0.5));
      expect(bad.lueftung, greaterThan(wohnen.lueftung));
      expect(wohnen.gesamt, greaterThan(300));
      expect(innenTemperaturVorschlag('Bad OG'), 24);
      expect(heizkoerperLeistung(1653, 1.33, 75, 65, 20), closeTo(1653, 1));
      expect(heizkoerperLeistung(1653, 1.33, 55, 45, 20), lessThan(1000));
    });

    test('Aufbau: U-Wert je nach Lage', () {
      final a = Aufbau(id: 'x', name: 'Dach', art: Gegen.aussen, schichten: [('d', 200), ('b', 200)]);
      double l(String id) => id == 'd' ? 0.04 : 2.0;
      final u = a.uWert(l);
      expect(u, closeTo(1 / (0.10 + 0.04 + 5 + 0.1), 1e-6));
      final j = Aufbau.ausJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(j.schichten, a.schichten);
      expect(j.art, Gegen.aussen);
    });
  });

  group('Oberfläche', () {
    late Directory tmp;
    late ProjectStore store;
    late AppState state;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('bauspur_bt_');
      store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'B');
      state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))..store = store;
    });
    tearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });

    testWidgets('Bauteile: Kategorie wählen, Element anlegen, Datenblatt per KI', (tester) async {
      tester.view.physicalSize = const Size(1700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: BauteilePage(state: state, kiAnbieter: _KiAttrappe()))));
      await tester.pump();
      expect(find.text('Kunststofffenster 82 mm, 3-fach (Beispiel)'), findsOneWidget);
      await tester.tap(find.text('Neu'));
      await tester.pumpAndSettle();
      expect(find.text('Technische Daten'), findsOneWidget);
      expect(find.text('Uw'), findsWidgets);
      await tester.tap(find.text('Aus Datenblatt …'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Fenster mit Uw 0,9 W/(m²K) und Bautiefe 76 mm');
      await tester.tap(find.text('Werte erkennen'));
      await tester.pump();
      await tester.tap(find.text('Mit KI auslesen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hersteller: Muster'), findsOneWidget);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      final neu = state.bibliothek.inKategorie(BauelementKategorie.fenster).where((e) => e.name == 'Fenster X').single;
      expect(neu.zahl('uw'), 0.72); // KI hat Vorrang vor der Regel
      expect(neu.zahl('bautiefe'), 76);
      expect(neu.hersteller, 'Muster');
    });

    testWidgets('Bauphysik: Heizlast, Aufbauten, Baustoffe; Einstellungen Klima und KI', (tester) async {
      tester.view.physicalSize = const Size(1700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      state.geschossId = g;
      for (final (x1, y1, x2, y2) in [(0, 0, 5000, 0), (5000, 0, 5000, 4000), (5000, 4000, 0, 4000), (0, 4000, 0, 0)]) {
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 300, zustand: WandZustand.bestand);
      }
      final f = ProjectStore.erkenneAusWaenden(store.waende(g)).single;
      store.raumAnlegen(geschossId: g, name: 'Wohnen', kuerzel: 'WO', flaeche: f);
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: BauphysikPage(state: state))));
      await tester.pump();
      expect(find.text('Wohnen'), findsOneWidget);
      expect(find.text('Summe Geschoss'), findsOneWidget);
      await tester.tap(find.text('Wohnen'));
      await tester.pump();
      expect(find.text('Wärmeverluste'), findsOneWidget);
      expect(find.textContaining('Außenwand'), findsWidgets);
      await tester.tap(find.text('Boden- und Deckenaufbauten'));
      await tester.pump();
      await tester.tap(find.text('+ Bodenplatte'));
      await tester.pump();
      expect(find.textContaining('U = '), findsOneWidget);
      await tester.tap(find.text('Baustoffkennwerte'));
      await tester.pump();
      expect(find.textContaining('Wärmeleitfähigkeit'), findsOneWidget);

      state.einstellungenZiel = 'klima';
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: SettingsPage(state: state))));
      await tester.pump();
      expect(find.text('Norm-Außentemperatur θe'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Norm-Außentemperatur θe'), '-16');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect((store.einstellung<Map>('heizlast')!['theta_e'] as num).toInt(), -16);
    });

    testWidgets('Einbaudetail: Wärmebrücke berechnen und speichern', (tester) async {
      tester.view.physicalSize = const Size(1600, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      final wid = store.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 4000, y2: 0, dicke: 365, zustand: WandZustand.bestand);
      final oid = store.oeffnungAnlegen(wandId: wid, art: OeffnungsArt.fenster, abstand: 1000, breite: 1230, hoehe: 1480, bruestung: 900);
      store.oeffnungAendern(oid, {'eigenschaften': jsonEncode({'bauelement': 'bsp-fenster-kunststoff-3fach'})});
      final wand = store.waende(g).single;
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: EinbaudetailPage(state: state, oeffnungId: oid, wand: wand)));
      await tester.pump();
      expect(find.text('Kunststofffenster 82 mm, 3-fach (Beispiel)'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Wärmebrücke berechnen'));
        for (var i = 0; i < 100 && (store.alleOeffnungen().single.eigenschaften['einbau'] as Map?)?['psi'] == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await tester.pump();
      final ein = store.alleOeffnungen().single.eigenschaften['einbau'] as Map;
      expect(ein['psi'], isA<num>());
      expect(ein['f_rsi'], isA<num>());
      expect(find.text('Uw eingebaut'), findsOneWidget);
    });
  });
}
