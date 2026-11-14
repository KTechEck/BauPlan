import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/keller_sockel.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/floorplan/keller_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kellertrockenlegung, Dämmung, Sockel', () {
    final waende = [
      (id: 'a', laenge: 10000.0, dicke: 365, freilegbar: true),
      (id: 'b', laenge: 8000.0, dicke: 365, freilegbar: true),
      (id: 'c', laenge: 10000.0, dicke: 365, freilegbar: false),
      (id: 'd', laenge: 8000.0, dicke: 365, freilegbar: true),
    ];
    const v = KellerVorgaben(tiefe: 2200, sockelUeberGok: 300, innenabdichtung: true);
    final e = kellerBerechnen(waende, v, kellerHoeheInnen: 2300, deckenFlaeche: 70);
    double menge(String s) => e.positionen.firstWhere((x) => x.was.startsWith(s)).menge;
    // freilegbar 26 m × 2,5 m = 65 m², PMBC 4 l/m²
    expect(menge('Bitumendickbeschichtung'), closeTo(260, 1e-6));
    expect(menge('Drainrohr'), closeTo(26 * 1.05, 1e-6));
    expect(menge('Bohrlöcher'), (36 / 0.12).ceil().toDouble());
    expect(menge('Perimeterdämmung'), closeTo(26 * 2.2 * 1.05, 1e-6));
    expect(menge('Kellerdeckendämmung'), closeTo(73.5, 1e-6));
    expect(e.hinweise.any((h) => h.contains('Vorflut')), isTrue);
    final druck = kellerBerechnen(waende, const KellerVorgaben(lastfall: Lastfall.drueckend));
    expect(druck.positionen.any((x) => x.was.startsWith('Drainrohr')), isFalse);
    expect(uKellerwand(1.2, perimeter: 120), closeTo(1 / (1 / 1.2 + 0.12 / 0.035), 1e-9));
    final s = sockelBerechnen(30, const SockelVorgaben(unterGok: 300, ueberGok: 300));
    expect(s.positionen.firstWhere((x) => x.was.startsWith('Sockeldämmung')).menge, closeTo(30 * 0.6 * 1.05, 1e-9));
    expect(s.hinweise.first, contains('Sockel ≠ Fassade'));
  });

  test('Putzprofile und Fensterbänke', () {
    final m = putzprofileAusPlan(
      aussenEckenHoeheM: 4 * 6,
      oeffnungenAussen: const [(b: 1000, h: 1250, fenster: true, tuer: false)],
      sockelLaengeM: 36,
      innenEckenHoeheM: 2.5,
      oeffnungenInnen: const [],
      balkonRandM: 6,
    );
    expect(m['Tropfkantenprofil Sturz (mit Gewebe)'], 1);
    expect(m['Anputzleiste / Fensteranschlussprofil'], closeTo(3.5, 1e-9));
    expect(m['Balkon-Tropfkantenprofil (Plattenrand)'], 6);
    expect(profilStaebe('Sockelprofil / Sockelschiene (WDVS)', 36), (36 * 1.1 / 2.5).ceil());
    final a = fensterbankAussenBerechnen(material: 'Aluminium (gekantet)', breite: 1010, laibungstiefe: 160, daemmung: 160);
    expect(a.tiefe, 360);
    expect(a.laenge, 1020);
    expect(a.endkappen, 2);
    expect(fensterbankAussenBerechnen(material: 'Naturstein', breite: 1010, laibungstiefe: 160, ueberstand: 20).hinweise.first, contains('Überstand'));
    expect(fensterbankInnenBerechnen(material: 'Holz', breite: 1010, laibungInnen: 120).laenge, 1060);
  });

  testWidgets('Keller-Dialog mit allen Reitern', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_b29_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'K');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final ids = [
      for (final (x1, y1, x2, y2) in [(0, 0, 6000, 0), (6000, 0, 6000, 4000), (6000, 4000, 0, 4000), (0, 4000, 0, 0)])
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 365),
    ];
    store.raumAnlegen(geschossId: g, name: 'Keller', kuerzel: 'KE', flaeche: store.flaechenErkennen(g).single);
    store.oeffnungAnlegen(wandId: ids.first, art: OeffnungsArt.fenster, abstand: 1000, breite: 1010, hoehe: 1250, bruestung: 900);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))
      ..store = store
      ..geschossId = g;
    await tester.pumpWidget(MaterialApp(
      theme: bauSpurTheme(),
      home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => kellerSockelDialog(c, state), child: const Text('K')))),
    ));
    await tester.tap(find.text('K'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bitumendickbeschichtung'), findsOneWidget);
    for (final t in ['Sockel', 'Putzprofile', 'Fensterbänke']) {
      await tester.tap(find.text(t));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: t);
    }
    expect(find.textContaining('Bestellliste'), findsOneWidget);
  });
}
