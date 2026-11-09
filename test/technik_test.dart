import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/technik.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/haustechnik/haustechnik_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TechnikGeraet geraet(String name, double x, double y, {int b = 600, int t = 600, int drehung = 0, int vorn = 0}) =>
    (id: name, name: name, x: x, y: y, b: b, t: t, drehung: drehung, vorn: vorn, links: 0, rechts: 0);

void main() {
  group('Technikraum', () {
    test('Umriss, Drehung und Wartungsfreiraum', () {
      final g = geraet('WP', 1000, 1000, b: 600, t: 400, vorn: 800);
      final u = geraeteUmriss(g);
      expect(u.map((p) => p.x).reduce((a, b) => a < b ? a : b), closeTo(700, 1e-9));
      expect(u.map((p) => p.y).reduce((a, b) => a > b ? a : b), closeTo(1200, 1e-9));
      final fr = freiraumUmriss(g);
      expect(fr.map((p) => p.y).reduce((a, b) => a > b ? a : b), closeTo(2000, 1e-9)); // 200 + 800 vor dem Gerät
      final gedreht = geraeteUmriss(geraet('WP', 0, 0, b: 600, t: 400, drehung: 90));
      expect(gedreht.map((p) => p.x).reduce((a, b) => a > b ? a : b), closeTo(200, 1e-9));
    });

    test('Kollisionen: Überlappung, Freiraum, außerhalb des Raums', () {
      const raum = [Punkt(0, 0), Punkt(3000, 0), Punkt(3000, 3000), Punkt(0, 3000)];
      final a = geraet('Speicher', 500, 400, vorn: 800);
      final b = geraet('Puffer', 500, 1300); // im Freiraum vor dem Speicher
      final c = geraet('MAG', 2900, 400); // ragt hinaus
      final h = technikKollisionen([a, b, c], raum: raum).join('\n');
      expect(h, contains('Puffer steht im Wartungsfreiraum von Speicher'));
      expect(h, contains('MAG ragt aus dem Raum'));
      expect(h, isNot(contains('überlappen')));
      expect(technikKollisionen([geraet('A', 500, 500), geraet('B', 800, 500)]).single, contains('überlappen'));
      expect(technikKollisionen([geraet('A', 500, 500), geraet('B', 1100, 500)]), isEmpty); // berühren sich nur
    });

    test('Elektro unter wasserführender Leitung', () {
      final h = elektroUnterWasser(
        [(name: 'SD-1', x: 100, y: 50, z: 300), (name: 'SD-2', x: 2000, y: 2000, z: 300)],
        [(name: 'KW-1', punkte: const [Punkt(0, 0), Punkt(1000, 0)], z: 1500)],
      );
      expect(h, ['SD-1 liegt unter KW-1 (wasserführend).']);
    });
  });

  group('Schächte', () {
    Schacht schacht(List<SchachtLeitung> l, {int b = 300, int t = 200, bool trenn = false, String art = 'Installationsschacht'}) =>
        Schacht(id: 's', name: 'S1', art: art, breite: b, tiefe: t, trennsteg: trenn, geschosse: const ['eg', 'og'], leitungen: l);
    SchachtLeitung l(String n, String zone, double d, [double dae = 0]) => SchachtLeitung(id: n, bezeichnung: n, zone: zone, durchmesser: d, daemmung: dae);

    test('Füllgrad, Querschnitt in Zonen, Regeln', () {
      final s = schacht([l('KW', 'Wasser', 20, 13), l('WW', 'Wasser', 20, 13), l('NYM', 'Elektro', 10), l('CAT', 'Daten', 7.5)]);
      final f = fuellgrad(s);
      expect(f, closeTo((2 * 3.14159265 * 23 * 23 + 3.14159265 * 25 + 3.14159265 * 7.5 * 7.5 / 4) / 60000, 0.001));
      final q = querschnitt(s);
      expect(q.passt, isTrue);
      final y = {for (final (x, _, yy) in q.lagen) x.zone: yy};
      expect(y['Wasser']! < y['Elektro']!, isTrue);
      expect(y['Elektro']! < y['Daten']!, isTrue);
      final h = schachtHinweise(s).join('\n');
      expect(h, contains('ohne Trennsteg'));
      expect(h, contains('Warmgehende'));
      expect(h, contains('abschotten'));
      expect(schachtHinweise(schacht([l('NYM', 'Elektro', 10), l('CAT', 'Daten', 7)], trenn: true)).join(), isNot(contains('Trennsteg')));
    });

    test('Überfüllung und zu kleiner Querschnitt', () {
      final s = schacht([for (var i = 0; i < 12; i++) l('HT$i', 'Abwasser', 110)], b: 300, t: 200);
      expect(fuellgrad(s), greaterThan(1));
      expect(querschnitt(s).passt, isFalse);
      final h = schachtHinweise(s).join('\n');
      expect(h, contains('Füllgrad'));
      expect(h, contains('passen so nicht'));
    });

    test('JSON und Länge im Schacht', () {
      final s = schacht([SchachtLeitung(id: 'a', bezeichnung: 'a', zone: 'Elektro', durchmesser: 10, vonGeschoss: 'eg', bisGeschoss: 'og')]);
      final z = Schacht.ausJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(z.leitungen.single.bisGeschoss, 'og');
      expect(laengeImSchacht(z.leitungen.single, const ['kg', 'eg', 'og', 'dg'], const {'eg': 3000, 'og': 2900}), 3000);
      expect(laengeImSchacht(SchachtLeitung(id: 'b', bezeichnung: 'b', zone: 'Elektro', durchmesser: 5), const ['eg', 'og'], const {}), 2800);
    });
  });

  testWidgets('Modul Haustechnik: Vorlage Heizraum einfügen, Schacht anlegen', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_ht_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'H');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    for (final (x1, y1, x2, y2) in [(0, 0, 4400, 0), (4400, 0, 4400, 3400), (4400, 3400, 0, 3400), (0, 3400, 0, 0)]) {
      store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
    }
    store.raumAnlegen(geschossId: g, name: 'Heizraum', kuerzel: 'HZR', flaeche: store.flaechenErkennen(g).single);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))
      ..store = store
      ..geschossId = g;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: HaustechnikPage(state: state))));
    await tester.pump();
    await tester.tap(find.text('Vorlage Heizraum'));
    await tester.pump();
    final geraete = store.objekte(g).where((o) => o.eigenschaften['masse'] != null).toList();
    expect(geraete.length, raumVorlagen['Heizraum']!.length);
    expect(find.text('Kollisionen und Hinweise'), findsOneWidget);

    await tester.tap(find.text('Schächte & Trassen'));
    await tester.pump();
    await tester.tap(find.text('Schacht / Trasse'));
    await tester.pump();
    expect((store.einstellung<List>('schaechte') ?? const []).length, 1);
    expect(find.textContaining('Füllgrad 0 %'), findsOneWidget);
  });
}
