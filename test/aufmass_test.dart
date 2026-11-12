import 'dart:convert';
import 'dart:io';

import 'package:bauspur/app/qr_bild.dart';
import 'package:bauspur/core/aufmass.dart';
import 'package:bauspur/core/brandschutz.dart';
import 'package:bauspur/core/ki.dart';
import 'package:bauspur/data/austausch.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/mobil/kontext.dart';
import 'package:bauspur/mobil/mobil_app.dart';
import 'package:bauspur/mobil/ordner.dart';
import 'package:bauspur/mobil/planstand.dart';
import 'package:bauspur/mobil/seiten/plan.dart';
import 'package:bauspur/mobil/seiten/wandansicht.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

(ProjectStore, String, Directory) _projekt() {
  final tmp = Directory.systemTemp.createTempSync('bauspur_aufmass_');
  final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'A');
  final g = store.geschosse(store.gebaeude().single.id).single.id;
  const e = [(0, 0), (4000, 0), (4000, 3000), (0, 3000)];
  for (var i = 0; i < 4; i++) {
    store.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 240);
  }
  store.raumAnlegen(geschossId: g, name: 'Kinderzimmer', kuerzel: 'KI', flaeche: store.flaechenErkennen(g).single);
  return (store, g, tmp);
}

void main() {
  test('Planstand 2: Wandseiten, Räume beiderseits, Höhen', () {
    final (store, g, tmp) = _projekt();
    final p = planstandErzeugen(store);
    expect(p['version'], 2);
    final waende = (p['geschosse'] as List).first['waende'] as List;
    final w = waende.first as Map;
    expect(w['l'], 4000);
    // eine Seite liegt im Raum (innen 4000 − 240 = 3760), die andere außen
    expect([w['li'], w['re']], contains(3760));
    expect(w['rl'] ?? w['rr'], isNotNull);
    final raum = ((p['geschosse'] as List).first['raeume'] as List).first as Map;
    expect(raum['hoehe'], greaterThan(2000));
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Aufmaß vom Handy: Eingang → offen → übernehmen ändert die Wand', () {
    final (store, g, tmp) = _projekt();
    final w = store.waende(g).first;
    final p = planstandErzeugen(store);
    final pw = ((p['geschosse'] as List).first['waende'] as List).first as Map;
    final seite = pw['li'] == 3760 ? 'l' : 'r';
    final ein = Directory('${store.ordner}/eingang')..createSync(recursive: true);
    File('${ein.path}/1_a.json').writeAsStringSync(jsonEncode({
      'art': 'aufmass', 'ziel': 'wand', 'id': w.id, 'feld': 'laenge', 'wert': 3810, 'seite': seite, 'bezug': 'innen', 'geschoss': g, 'autor': 'Tim', 'plan': 3760,
    }));
    expect(eingangUebernehmen(store).uebernommen, 1);
    expect(aufmassOffen(store), 1);
    final a = aufmassListe(store).single;
    expect(aufmassPlanwert(store, a), closeTo(3760, 1));
    expect(aufmassAnwenden(store, a), isNull);
    final neu = store.waende(g).firstWhere((x) => x.id == w.id);
    expect(neu.laenge, closeTo(4050, 1));
    expect(aufmassOffen(store), 0);
    expect(aufmassGemessen(store)[w.id]?['laenge_innen'], 3810);
    // im neuen Planstand steht die Wand als gemessen
    final p2 = planstandErzeugen(store);
    final w2 = ((p2['geschosse'] as List).first['waende'] as List).firstWhere((x) => (x as Map)['id'] == w.id) as Map;
    expect((w2['gemessen'] as Map)['laenge_innen'], 3810);
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Raumlänge an langer Wand (zwei Zimmer): Teilstück messen verschiebt die Zwischenwand', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_aufmass2_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'B');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    const e = [(0, 0), (6000, 0), (6000, 4000), (0, 4000)];
    for (var i = 0; i < 4; i++) {
      store.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 300);
    }
    store.wandAnlegen(geschossId: g, x1: 3000, y1: 0, x2: 3000, y2: 4000, dicke: 100);
    final fl = store.flaechenErkennen(g)..sort((a, b) => a.licht.first.x.compareTo(b.licht.first.x));
    store.raumAnlegen(geschossId: g, name: 'Links', kuerzel: 'L', flaeche: fl.first);
    final rechts = store.raumAnlegen(geschossId: g, name: 'Rechts', kuerzel: 'R', flaeche: fl.last);
    final p = planstandErzeugen(store);
    final oben = ((p['geschosse'] as List).first['waende'] as List).first as Map;
    final st = [...oben['sl'] as List, ...oben['sr'] as List].firstWhere((x) => (x as List)[0] == rechts) as List;
    final seite = (oben['sl'] as List).contains(st) ? 'l' : 'r';
    expect((st[2] as num) - (st[1] as num), closeTo(2800, 2)); // 3050 … 5850
    final a = {'nr': 'x', 'ziel': 'raumseite', 'id_ziel': oben['id'], 'feld': 'laenge_$rechts', 'wert': 3000, 'seite': seite, 'raum': rechts, 'geschoss': g, 'status': 'offen'};
    store.einstellungSetzen('aufmass', [a]);
    expect(aufmassPlanwert(store, a), closeTo(2800, 2));
    expect(aufmassAnwenden(store, a), isNull);
    final zwischen = store.waende(g).firstWhere((w) => w.dicke == 100);
    expect(zwischen.x1, closeTo(2800, 2)); // Zwischenwand 20 cm nach links
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Brandschutz: Gewerk vorhanden, Rauchmelder-Pflicht im Kinderzimmer', () {
    final (store, g, tmp) = _projekt();
    expect(store.gewerke().any((x) => x.kuerzel == 'BS'), isTrue);
    final typen = {for (final t in store.objekttypen()) t.id: t};
    expect(typen.values.any((t) => t.kuerzel == 'RW'), isTrue);
    final geschoss = store.geschosse(store.gebaeude().single.id).single;
    var h = brandschutzPruefen(store, geschoss, store.raeume(g), store.objekte(g), typen);
    expect(h.map((x) => x.text).join(), contains('kein Rauchwarnmelder'));
    final rw = typen.values.firstWhere((t) => t.kuerzel == 'RW');
    store.objektAnlegen(typ: rw, geschossId: g, punkte: [punktAus([2000, 1500])]);
    h = brandschutzPruefen(store, geschoss, store.raeume(g), store.objekte(g), typen);
    expect(h.whereType<PruefHinweis>().map((x) => x.text).join(), isNot(contains('kein Rauchwarnmelder')));
    wandFeuerwiderstandSetzen(store, [store.waende(g).first.id], 'F90 / EI 90');
    expect(wandFeuerwiderstand(store).values.single, 'F90 / EI 90');
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('QR-Kopplung: Text hin und zurück', () {
    final t = kopplungsText(adressen: ['192.168.178.20', '10.0.0.5:47830'], code: '123456', name: 'PC');
    final k = kopplungLesen(t)!;
    expect(k.adressen, ['192.168.178.20', '10.0.0.5:47830']);
    expect(k.code, '123456');
    expect(kopplungLesen('https://example.org'), isNull);
  });

  testWidgets('App: Plan mit Maßen, Wand antippen, Wandansicht mit Bohrhilfe', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (store, g, tmp) = _projekt();
    planstandSchreiben(store);
    final geraet = Directory('${tmp.path}/geraet')..createSync();
    final e = await MobilEinstellungen.laden(ordner: geraet);
    await tester.pumpWidget(MobilApp(ordner: LokalOrdner(store.ordner), einstellungen: e, puffer: await Puffer.laden(basis: geraet)));
    await tester.pumpAndSettle();
    expect(find.text('Räume'), findsWidgets);
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.byType(GrundrissAnsicht), findsOneWidget);
    // Wandansicht direkt öffnen
    final plan = Planstand.lesen(File('${store.ordner}/planstand/planstand.json').readAsBytesSync())!;
    final geschoss = plan.geschosse.first;
    final wand = Planstand.liste(geschoss['waende']).first;
    final k = MobilKontext(plan: plan, einstellungen: e, erfasst: (x, {foto}) async {}, abgleichen: () async {}, verbindungAendern: () async {}, wartend: 0, ordnerName: 'A');
    await tester.pumpWidget(MaterialApp(home: WandansichtSeite(k: k, geschoss: geschoss, wand: wand, links: wand['rl'] != null)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bohrhilfe'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(215, 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anzeichnen:'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.schliessen();
  });
}
