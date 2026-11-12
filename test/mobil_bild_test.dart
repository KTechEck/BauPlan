// Bildschirmfotos der Baustellen-App (iPhone-Größe) zur Sichtprüfung.
// Läuft nur mit gesetzter Umgebungsvariable BAUSPUR_BILD (Zielordner).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/height.dart';
import 'package:bauspur/data/austausch.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/mobil/kontext.dart';
import 'package:bauspur/mobil/ordner.dart';
import 'package:bauspur/mobil/planstand.dart';
import 'package:bauspur/mobil/seiten/einkauf.dart';
import 'package:bauspur/mobil/seiten/erfassen.dart';
import 'package:bauspur/mobil/seiten/plan.dart';
import 'package:bauspur/mobil/seiten/wandansicht.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _ziel = Platform.environment['BAUSPUR_BILD'];
final _rahmen = GlobalKey();

Future<void> _schriften() async {
  final mf = '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/tkuns/dev/flutter'}/bin/cache/artifacts/material_fonts';
  for (final e in {
    'Roboto': ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf'],
    'MaterialIcons': ['materialicons-regular.otf']
  }.entries) {
    final l = FontLoader(e.key);
    for (final d in e.value) {
      l.addFont(Future.value(ByteData.sublistView(File('$mf/$d').readAsBytesSync())));
    }
    await l.load();
  }
}

Future<void> _foto(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final ro = _rahmen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_ziel/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _app(Widget kind) => RepaintBoundary(key: _rahmen, child: MaterialApp(debugShowCheckedModeBanner: false, theme: bauSpurTheme(), home: kind));

void main() {
  testWidgets('App-Bilder', (tester) async {
    if (_ziel == null) return;
    await tester.runAsync(_schriften);
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    final tmp = Directory.systemTemp.createTempSync('bauspur_mbild_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Wohnhaus');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    const e = [(0, 0), (5200, 0), (5200, 4000), (0, 4000)];
    for (var i = 0; i < 4; i++) {
      store.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 300);
    }
    store.wandAnlegen(geschossId: g, x1: 3000, y1: 0, x2: 3000, y2: 4000, dicke: 115);
    for (final (f, name) in [(0, 'Wohnzimmer'), (1, 'Kinderzimmer')]) {
      final fl = store.flaechenErkennen(g)[f];
      store.raumAnlegen(geschossId: g, name: name, kuerzel: name.substring(0, 2).toUpperCase(), flaeche: fl);
    }
    final w0 = store.waende(g).first;
    store.oeffnungAnlegen(wandId: w0.id, art: OeffnungsArt.fenster, abstand: 800, breite: 1250, hoehe: 1350, bruestung: 900);
    final typen = {for (final t in store.objekttypen()) t.kuerzel: t};
    store.objektAnlegen(geschossId: g, typ: typen['SD']!, punkte: [punktAus([2400, 160])], z: 300, zBezug: Hoehenbezug.ffb);
    store.objektAnlegen(geschossId: g, typ: typen['TA']!, punkte: [punktAus([450, 160])], z: 1050, zBezug: Hoehenbezug.ffb);
    store.objektAnlegen(geschossId: g, typ: typen['RW']!, punkte: [punktAus([1500, 2000])]);
    final p = planstandErzeugen(store);
    p['einkauf'] = [
      {'id': '1', 'quelle': 'bedarf', 'text': 'Gira E2 Steckdose reinweiß', 'menge': 12, 'einheit': 'Stk', 'haendler': 'Elektro-Großhandel', 'preis_cent': 890, 'herkunft': 'Installation', 'kategorie': 'Elektro', 'link': 'https://example.org'},
      {'id': '2', 'quelle': 'bedarf', 'text': 'NYM-J 3×1,5 mm²', 'menge': 85, 'einheit': 'm', 'haendler': 'Elektro-Großhandel', 'preis_cent': 95, 'herkunft': 'Leitungen', 'kategorie': 'Kabel / Leitung'},
      {'id': '3', 'quelle': 'bedarf', 'text': 'Rauchwarnmelder 10 J', 'menge': 4, 'einheit': 'Stk', 'haendler': 'Baumarkt', 'preis_cent': 2490, 'herkunft': 'Installation', 'kategorie': 'Rauchmelder / Brandschutz'},
    ];
    final plan = Planstand(p);
    final geraet = Directory('${tmp.path}/geraet')..createSync();
    final ein = await MobilEinstellungen.laden(ordner: geraet);
    ein.geschoss = g;
    final wand = Planstand.liste(plan.geschosse.first['waende']).first;
    ein.aufmass[aufmassSchluessel('${wand['id']}', 'laenge', seite: wand['rl'] != null ? 'l' : 'r', bezug: 'innen')] = {'wert': 4870, 'zeit': DateTime.now().toUtc().toIso8601String()};
    final k = MobilKontext(plan: plan, einstellungen: ein, erfasst: (x, {foto}) async {}, abgleichen: () async {}, verbindungAendern: () async {}, wartend: 0, ordnerName: 'PC');

    await tester.pumpWidget(_app(Scaffold(appBar: AppBar(title: const Text('Wohnhaus')), body: PlanSeite(k: k))));
    await _foto(tester, 'app_plan');
    await tester.pumpWidget(_app(WandansichtSeite(k: k, geschoss: plan.geschosse.first, wand: wand, links: wand['rl'] != null)));
    await _foto(tester, 'app_wand');
    await tester.tap(find.text('Bohrhilfe'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(150, 520));
    await _foto(tester, 'app_bohren');
    final raum = Planstand.liste(plan.geschosse.first['raeume']).first;
    await tester.pumpWidget(_app(RaumAufmassSeite(k: k, geschoss: plan.geschosse.first, raum: raum)));
    await _foto(tester, 'app_raum');
    // Dachschräge an der linken Außenwand des Wohnzimmers, Ansicht der oberen Wand (Giebelseite)
    final links = Planstand.liste(plan.geschosse.first['waende']).firstWhere((w) => (w['a'] as List)[0] == 0 && (w['b'] as List)[0] == 0);
    final wz = (links['rl'] ?? links['rr']) as String;
    final sl = links['rl'] == wz ? 'l' : 'r';
    final jetzt = DateTime.now().toUtc().toIso8601String();
    for (final (f, v) in [('kniestock', 900), ('tiefe', 1800), ('decke', 2400)]) {
      ein.aufmass['$wz|$f|$sl|${links['id']}'] = {'wert': v, 'zeit': jetzt};
    }
    final oben = Planstand.liste(plan.geschosse.first['waende']).first;
    await tester.pumpWidget(_app(WandansichtSeite(k: k, geschoss: plan.geschosse.first, wand: oben, links: oben['rl'] == wz)));
    await _foto(tester, 'app_schraege');
    await tester.pumpWidget(_app(Scaffold(body: EinkaufSeite(k: k))));
    await _foto(tester, 'app_einkauf');
    ein.raum = raum['id'] as String;
    await tester.pumpWidget(_app(Scaffold(body: ErfassenSeite(k: k))));
    await _foto(tester, 'app_erfassen');
    await tester.pumpWidget(const SizedBox());
    store.schliessen();
  });
}
