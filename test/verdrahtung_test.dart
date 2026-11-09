import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/verdrahtung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schrank_models.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/verteiler/schrank_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ProjectStore store;
  late String sid, rcd, ls1, ls2, k1;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bauspur_vd_');
    store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'V');
    sid = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1', reihen: 2, teJeReihe: 12);
    store.geraetAnlegen(schrankId: sid, reihe: 0, position: 0, art: GeraeteArt.hauptschalter, pole: 3, kennzeichen: '-Q1', nennstrom: 63);
    rcd = store.geraetAnlegen(schrankId: sid, reihe: 0, position: 3, art: GeraeteArt.rcd, pole: 4, kennzeichen: '-F1', nennstrom: 40);
    ls1 = store.geraetAnlegen(schrankId: sid, reihe: 0, position: 7, art: GeraeteArt.ls, kennzeichen: '-F2', nennstrom: 16, phase: 'L1', vorgeschaltetId: rcd);
    ls2 = store.geraetAnlegen(schrankId: sid, reihe: 0, position: 8, art: GeraeteArt.ls, kennzeichen: '-F3', nennstrom: 16, phase: 'L2', vorgeschaltetId: rcd);
    final x1 = store.geraetAnlegen(schrankId: sid, reihe: 1, position: 0, art: GeraeteArt.klemme, kennzeichen: '-X1');
    k1 = store.stromkreisAnlegen(schrankId: sid, nummer: '1', bezeichnung: 'Bad', schutzId: ls1, querschnitt: 250);
    store.stromkreisAnlegen(schrankId: sid, nummer: '2', bezeichnung: 'Flur', schutzId: ls2);
    store.geraetAendern(x1, {'eigenschaften': jsonEncode({'stromkreis': k1})});
  });
  tearDown(() {
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  Schrank schrank() => store.schraenke().single;

  test('Verdrahtung aus der Schrankplanung', () {
    final d = verdrahtung(schrank(), store.schrankGeraete(sid), store.stromkreise(sid));
    // Einspeisung 3+N, Q1 → F1 4, F1 → F2/F3 je 1, Abgang 1: L, N, PE an X1, Abgang 2: L (ohne Klemme)
    expect(d.where((x) => x.von == 'Einspeisung').length, 4);
    expect(d.where((x) => x.von == '-Q1:2' && x.nach.startsWith('-F1')).length, 4);
    expect(d.where((x) => x.von == '-F1:2').map((x) => x.nach).toSet(), {'-F2:1', '-F3:1'});
    final bad = d.where((x) => x.stromkreis == k1).toList();
    expect(bad.map((x) => x.leiter).toList(), ['L1', 'N', 'PE']);
    expect(bad.first.nach, '-X1:1');
    expect(bad.first.querschnitt, 250);
    expect(bad[1].von, '-F1:N');
    expect(d.firstWhere((x) => x.nach == 'Abgang 2').leiter, 'L2');
    expect(d.firstWhere((x) => x.leiter == 'L2').farbe, 'schwarz');
    expect(d.every((x) => x.laenge > 0), isTrue);
    expect(verdrahtungsHinweise(schrank(), store.schrankGeraete(sid), store.stromkreise(sid)).single, contains('Stromkreis 2 Flur: Abgang ohne Klemme'));
  });

  test('Kammschiene ersetzt Einzeldrähte, Material zählt TE und Draht', () {
    final s = schrank();
    store.schrankAendern(sid, {
      'eigenschaften': jsonEncode({
        'kammschienen': [Kammschiene(id: 'k', reihe: 0, von: 7, bis: 12, art: '3P+N', einspeisung: rcd).toJson()],
      }),
    });
    final s2 = schrank();
    expect(kammschienen(s2).single.deckt(store.schrankGeraete(sid).firstWhere((g) => g.id == ls2)), isTrue);
    final d = verdrahtung(s2, store.schrankGeraete(sid), store.stromkreise(sid));
    expect(d.where((x) => x.von == '-F1:2'), isEmpty);
    final m = {for (final (t, n, _) in verdrahtungsMaterial(d, kammschienen(s2))) t: n};
    expect(m['Kammschiene 3P+N'], 5);
    expect(m['Aderendhülsen'], d.length * 2);
    expect(m.keys.any((k) => k.startsWith('H07V-K 2,5 mm² braun')), isTrue);
    expect(s.eigenschaften.containsKey('kammschienen'), isFalse);
  });

  test('Kammschiene ohne Einspeisung wird gemeldet', () {
    store.schrankAendern(sid, {
      'eigenschaften': jsonEncode({
        'kammschienen': [Kammschiene(id: 'k', reihe: 1, von: 5, bis: 9).toJson()],
      }),
    });
    final h = verdrahtungsHinweise(schrank(), store.schrankGeraete(sid), store.stromkreise(sid)).join('\n');
    expect(h, contains('ohne Einspeisung'));
    expect(h, contains('verbindet keine Geräte'));
  });

  testWidgets('Ansicht Verdrahtung zeigt Liste und Material', (tester) async {
    tester.view.physicalSize = const Size(1700, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))..store = store;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: SchrankPage(state: state))));
    await tester.pump();
    await tester.tap(find.text('Verdrahtung'));
    await tester.pump();
    expect(find.text('Verdrahtungsliste'), findsOneWidget);
    expect(find.text('-X1:1'), findsOneWidget);
    expect(find.text('Aderendhülsen', skipOffstage: false), findsNothing); // steht mit Menge davor
    expect(find.textContaining('Aderendhülsen'), findsOneWidget);
    await tester.tap(find.text('In die Kostenliste'));
    await tester.pump();
    expect(store.kostenpositionen().where((k) => k.text.contains('Aderendhülsen')).length, 1);
  });
}
