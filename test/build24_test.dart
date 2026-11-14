import 'dart:convert';
import 'dart:io';

import 'package:bauspur/core/elektro.dart';
import 'package:bauspur/core/licht.dart';
import 'package:bauspur/core/rack.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schrank_models.dart';
import 'package:bauspur/app/theme.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/verteiler/schrank_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ProjectStore store;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bauspur_b24_');
    store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'E');
  });
  tearDown(() {
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Phasenlast, Schieflast, RCD, ÜSS, Verdrahtungsabgleich', () {
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final s = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1', reihen: 1, teJeReihe: 12);
    final ls1 = store.geraetAnlegen(schrankId: s, reihe: 0, position: 0, art: GeraeteArt.ls, kennzeichen: '-F1', nennstrom: 16, charakteristik: 'B', phase: 'L1');
    final ls2 = store.geraetAnlegen(schrankId: s, reihe: 0, position: 1, art: GeraeteArt.ls, kennzeichen: '-F2', nennstrom: 16, charakteristik: 'B', phase: 'L1');
    final herd = store.geraetAnlegen(schrankId: s, reihe: 0, position: 2, art: GeraeteArt.ls, kennzeichen: '-F3', nennstrom: 16, charakteristik: 'B', pole: 3);
    store.stromkreisAnlegen(schrankId: s, nummer: '1', schutzId: ls1, leistung: 3500);
    store.stromkreisAnlegen(schrankId: s, nummer: '2', schutzId: ls2, leistung: 3000);
    final k3 = store.stromkreisAnlegen(schrankId: s, nummer: '3', schutzId: herd, leistung: 9000);
    final schrank = store.schraenke().single;
    final last = phasenlast(store.stromkreise(s), store.schrankGeraete(s), const {});
    expect(last['L1'], 6500 + 3000);
    expect(last['L2'], 3000);
    expect(schieflastHinweis(last), contains('Schieflast'));
    final p = elektroPruefen(store, schrank);
    expect(p.where((x) => x.text.contains('ohne RCD')).length, 3);
    expect(p.any((x) => x.bereich == 'Überspannung'), isTrue);
    expect(p.any((x) => x.bereich == 'Reserve'), isFalse);
    // Abgleich: Steckdose ohne Stromkreis, Kreise ohne Verbraucher, Objekt mit gelöschtem Kreis
    final typ = {for (final t in store.objekttypen()) t.kuerzel: t};
    store.objektAnlegen(geschossId: g, typ: typ['SD']!, punkte: const [Punkt(0, 0)]);
    final o = store.objektAnlegen(geschossId: g, typ: typ['SD']!, punkte: const [Punkt(500, 0)]);
    store.objektAendern(o, {'eigenschaften': jsonEncode({'stromkreis': k3})});
    store.stromkreisLoeschen(k3);
    final a = verdrahtungsabgleich(store);
    expect(a.any((x) => x.text.contains('keinem Stromkreis')), isTrue);
    expect(a.any((x) => x.text.contains('gelöscht')), isTrue);
    expect(a.where((x) => x.text.contains('keine Verbraucher')).length, 2);
    store.einstellungSetzen('plankopf', {'ersteller': 'Tim', 'revision': 'B'});
    expect(plankopfZeile(store, 'Haus'), 'Haus · Tim · Rev. B');
  });

  test('DIN 18015-2 Soll und Ist', () {
    expect(ausstattungSoll('Wohnzimmer', 25, 2), (sd: 9, licht: 3, daten: 2));
    expect(ausstattungSoll('Bad', 8, 2).sd, 3);
    expect(ausstattungSoll('Schlafzimmer', 14, 1).sd, 4);
    expect(ausstattungSoll('Schlafzimmer', 14, 3).sd, 7);
    final k = {for (final t in store.objekttypen()) t.kuerzel};
    expect(k.containsAll(['KA', 'ZU', 'TS', 'TO']), isTrue);
  });

  test('Rack: Überlappung, Ports, Dose kennt ihren Port; LED-Zuleitung', () {
    final s = store.schrankAnlegen(name: 'Netzwerk', kennzeichen: 'NW1', art: SchrankArt.netzwerk);
    store.schrankAendern(s, {
      'eigenschaften': jsonEncode({
        'rack_he': 6,
        'rack': [
          {'id': 'a', 'art': 'Patchfeld', 'he': 6, 'hoehe': 1, 'ports': 24},
          {'id': 'b', 'art': 'Switch', 'he': 5, 'hoehe': 2, 'ports': 16, 'watt': 200},
          {'id': 'c', 'art': 'USV', 'he': 6, 'hoehe': 2},
        ],
        'patch': {'12': 'dose-1'},
      })
    });
    final sch = store.schraenke().single;
    final h = rackPruefen(sch);
    expect(h.any((x) => x.contains('überlappen')), isTrue);
    expect(h.any((x) => x.contains('ragt')), isTrue);
    expect(h.any((x) => x.contains('Abwärme')), isTrue);
    expect(h.any((x) => x.contains('Switch-Ports')), isTrue);
    expect(dosePort(store, 'dose-1'), 'NW1 Port 12');
    expect(dosePort(store, 'x'), isNull);
    // 60 W an 24 V über 10 m auf 1,5 mm²: I = 2,5 A, ΔU = 2·10·2,5/(56·1,5) = 0,595 V = 2,5 %
    final z = ledZuleitung(60, '24 V', 10, 1.5);
    expect(z.prozent, closeTo(2.48, 0.01));
    expect(ledZuleitung(120, '12 V', 10, 1.5).empfohlen, greaterThan(1.5));
    expect(ledStreifenWirksam(10000, 'beidseitig'), 5000);
  });

  testWidgets('Verteiler: Prüfung und Rack öffnen', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.schrankAnlegen(name: 'Netzwerk', kennzeichen: 'NW1', art: SchrankArt.netzwerk);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))..store = store;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: SchrankPage(state: state))));
    await tester.pump();
    await tester.ensureVisible(find.text('Prüfung'));
    await tester.tap(find.text('Prüfung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Phasenlast'), findsWidgets);
    await tester.ensureVisible(find.text('Rack 19″'));
    await tester.tap(find.text('Rack 19″'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Switch'));
    await tester.pumpAndSettle();
    expect(rackLesen(store.schraenke().single).single.art, 'Switch');
    expect(tester.takeException(), isNull);
  });
}

