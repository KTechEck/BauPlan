import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/knx.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schrank_models.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/verteiler/schrank_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KNX-Kern', () {
    test('Adressen lesen, nächste Untergruppe, Doppelte, PA', () {
      expect(gaLesen('1/0/12'), (1, 0, 12));
      expect(gaLesen('32/0/1'), isNull);
      expect(gaLesen('1/8/1'), isNull);
      final gas = [
        Gruppenadresse(id: 'a', haupt: 1, mittel: 0, unter: 0, name: 'a'),
        Gruppenadresse(id: 'b', haupt: 1, mittel: 0, unter: 1, name: 'b'),
        Gruppenadresse(id: 'c', haupt: 1, mittel: 0, unter: 1, name: 'c'),
      ];
      expect(naechsteUntergruppe(gas, 1, 0), 2);
      expect(naechsteUntergruppe(gas, 1, 1), 0);
      expect(doppelteAdressen(gas), ['1/0/1']);
      expect(paGueltig('1.1.10'), isTrue);
      expect(paGueltig('16.1.1'), isFalse);
      expect(haSlug('Bad Decke Ü'), 'bad_decke_ue');
      expect(kanalNamen(3), ['A', 'B', 'C']);
    });

    test('Vorschlag aus Kanalbelegung, ETS-CSV und Home-Assistant-YAML', () {
      var n = 0;
      final gas = gruppenadressenVorschlagen([
        (aktorId: 'k1', aktor: '=UV1-K1', aktortyp: 'Schalt', kanal: 'A', objektId: 'o1', name: 'Bad Leuchte', kuerzel: 'LE'),
        (aktorId: 'k2', aktor: '=UV1-K2', aktortyp: 'Dimm', kanal: 'A', objektId: 'o2', name: 'Wohnen Leuchte', kuerzel: 'LE'),
        (aktorId: 'k3', aktor: '=UV1-K3', aktortyp: 'Jalousie', kanal: 'A', objektId: 'o3', name: 'Wohnen Jalousie', kuerzel: 'FA'),
      ], const [], neueId: () => 'g${n++}');
      expect(gas.length, 2 + 5 + 3);
      final schalten = gas.where((g) => g.funktion == 'schalten').toList();
      expect(schalten.map((g) => g.adresse), ['1/0/0', '1/0/1']);
      expect(gas.firstWhere((g) => g.funktion == 'position').adresse, '1/7/0');
      // erneut vorschlagen ändert nichts
      expect(gruppenadressenVorschlagen([(aktorId: 'k1', aktor: '', aktortyp: 'Schalt', kanal: 'A', objektId: 'o1', name: 'Bad Leuchte', kuerzel: 'LE')], gas, neueId: () => 'x').length,
          gas.length);

      final csv = etsCsv(gas);
      expect(csv.split('\n').first, contains('"Group name","Address"'));
      expect(csv, contains('"Bad Leuchte schalten","1/0/0","","","","DPST-1-1","Auto"'));
      expect(csv, contains('"Schalten","1/0/-"'));

      final yaml = haYaml([
        (domaene: 'light', name: 'Wohnen Leuchte', entity: 'light.wohnen_leuchte', gas: [for (final g in gas) if (g.objekte.contains('o2')) g]),
        (domaene: 'cover', name: 'Wohnen Jalousie', entity: 'cover.wohnen_jalousie', gas: [for (final g in gas) if (g.objekte.contains('o3')) g]),
      ]);
      expect(yaml, contains('knx:\n  cover:'));
      expect(yaml, contains('brightness_address: "1/3/0"'));
      expect(yaml, contains('move_long_address: "1/5/0"'));
      expect(yaml, contains('unique_id: "bauspur_wohnen_leuchte"'));
    });
  });

  group('Oberfläche', () {
    late Directory tmp;
    late ProjectStore store;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('bauspur_knx_');
      store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'K');
    });
    tearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });

    testWidgets('Aktorkanal belegen, Gruppenadressen vorschlagen, Patchfeld', (tester) async {
      tester.view.physicalSize = const Size(1700, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      final le = store.objekttypen().firstWhere((t) => t.kuerzel == 'LE');
      final o = store.objektAnlegen(geschossId: g, typ: le, punkte: const [Punkt(0, 0)]);
      final sid = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1', reihen: 1, teJeReihe: 12);
      final aktor = store.geraetAnlegen(schrankId: sid, reihe: 0, position: 0, art: GeraeteArt.knx, kennzeichen: '-K1');
      store.geraetAendern(aktor, {'eigenschaften': jsonEncode({'aktortyp': 'Schalt', 'kanaele': 4})});
      store.objektAendern(o, {'eigenschaften': jsonEncode({'knx_kanal': '$aktor:B'})});

      final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))..store = store;
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: SchrankPage(state: state))));
      await tester.pump();
      await tester.tap(find.text('KNX / Home Assistant'));
      await tester.pump();
      expect(find.text('=UV1-K1'), findsOneWidget);
      expect(find.text('Kanalbelegung (1)'), findsOneWidget);
      await tester.tap(find.text('Gruppenadressen aus Kanalbelegung'));
      await tester.pump();
      final gas = store.einstellung<List>('knx_gruppenadressen')!;
      expect(gas.length, 2);
      expect(find.text('Gruppenadressen (2)'), findsOneWidget);

      // Netzwerkschrank mit Patchfeld
      final nid = store.schrankAnlegen(name: 'Netzwerk', kennzeichen: 'NW1', art: SchrankArt.netzwerk);
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: SchrankPage(state: state))));
      await tester.pump();
      await tester.tap(find.text('NW1').first);
      await tester.pump();
      await tester.tap(find.descendant(of: find.byType(SegmentedButton<int>), matching: find.text('Schrank')));
      await tester.pump();
      expect(store.schraenke().any((s) => s.id == nid), isTrue);
      expect(find.text('Patchfeld'), findsOneWidget);
    });

    testWidgets('Stromlaufplan, ETS-Abgleich und Home Assistant live öffnen', (tester) async {
      tester.view.physicalSize = const Size(1900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      final sd = store.objekttypen().firstWhere((t) => t.kuerzel == 'SD');
      final o = store.objektAnlegen(geschossId: g, typ: sd, punkte: const [Punkt(0, 0)]);
      final sid = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1', reihen: 2, teJeReihe: 12);
      final fi = store.geraetAnlegen(schrankId: sid, reihe: 0, position: 0, art: GeraeteArt.rcd, kennzeichen: '-F1');
      final ls = store.geraetAnlegen(schrankId: sid, reihe: 0, position: 4, art: GeraeteArt.ls, kennzeichen: '-F2');
      store.geraetAendern(ls, {'vorgeschaltet_id': fi, 'phase': 'L1'});
      final k = store.stromkreisAnlegen(schrankId: sid, nummer: '1');
      store.stromkreisAendern(k, {'schutz_id': ls, 'bezeichnung': 'Steckdosen Flur'});
      store.objektAendern(o, {'eigenschaften': jsonEncode({'stromkreis': k, 'ha_entity': 'switch.flur'})});

      final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))..store = store;
      await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: SchrankPage(state: state))));
      await tester.pump();
      await tester.tap(find.text('Stromlaufplan'));
      await tester.pump();
      expect(find.text('Blatt 1: Einspeisung und Stromkreise'), findsOneWidget);
      expect(find.text('Blatt 2: Betriebsmittelliste'), findsOneWidget);
      expect(find.text('Als PDF (A3)'), findsOneWidget);

      await tester.tap(find.text('KNX / Home Assistant'));
      await tester.pump();
      await tester.tap(find.text('ETS-Projekt abgleichen'));
      await tester.pumpAndSettle();
      expect(find.text('ETS-Projekt oder CSV öffnen …'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Home Assistant live'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Zugangs-Token fehlt'), findsOneWidget);
      expect(find.text('In BauSpur eingetragen (1)'), findsOneWidget);
      expect(find.textContaining('switch.flur'), findsOneWidget);
    });
  });
}
