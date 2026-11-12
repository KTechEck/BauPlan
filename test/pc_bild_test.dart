// Bildschirmfotos der neuen PC-Teile (Aufmaß-Dialog, Anschlüsse in der
// Bibliothek, Besorgungs-/Einkaufsliste, QR). Nur mit BAUSPUR_BILD.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/app/qr_bild.dart';
import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/aufmass.dart';
import 'package:bauspur/core/bauelemente.dart';
import 'package:bauspur/core/geraeteanschluesse.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/austausch.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/bauteile/anschluss_editor.dart';
import 'package:bauspur/ui/bauteile/einkauf_dialog.dart';
import 'package:bauspur/ui/floorplan/aufmass_dialog.dart';
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

void main() {
  testWidgets('PC-Bilder Build 11', (tester) async {
    if (_ziel == null) return;
    await tester.runAsync(_schriften);
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 760);
    final tmp = Directory.systemTemp.createTempSync('bauspur_pcbild_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Wohnhaus');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    const e = [(0, 0), (4000, 0), (4000, 3000), (0, 3000)];
    for (var i = 0; i < 4; i++) {
      store.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 240);
    }
    final raum = store.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: store.flaechenErkennen(g).single);
    final w = store.waende(g).first;
    aufmassAblegen(store, {'ziel': 'wand', 'id': w.id, 'feld': 'laenge', 'wert': 3810, 'seite': 'r', 'bezug': 'innen', 'geschoss': g, 'raum': raum, 'autor': 'Tim', 'plan': 3760});
    aufmassAblegen(store, {'ziel': 'raum', 'id': raum, 'feld': 'hoehe', 'wert': 2480, 'geschoss': g, 'raum': raum, 'autor': 'Tim'});
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;

    Widget app(Widget kind) => RepaintBoundary(key: _rahmen, child: MaterialApp(debugShowCheckedModeBanner: false, theme: bauSpurTheme(), home: kind));
    await tester.pumpWidget(app(Scaffold(body: Builder(builder: (c) => Center(child: FilledButton(onPressed: () => aufmassDialogZeigen(c, state), child: const Text('Aufmaß')))))));
    await tester.tap(find.text('Aufmaß'));
    await _foto(tester, 'pc_aufmass');
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    final el = Bauelement(
      id: 'x1',
      kategorie: BauelementKategorie.technik,
      name: 'Wärmepumpe Innenteil',
      hersteller: 'Muster',
      daten: mitAnschluessen({'breite': 600, 'hoehe': 1800}, anschlussVorschlag(BauelementKategorie.technik, {'breite': 600, 'hoehe': 1800})),
    );
    var aktuell = el;
    await tester.pumpWidget(app(Scaffold(
      body: StatefulBuilder(
        builder: (c, set) => Padding(padding: const EdgeInsets.all(20), child: AnschlussEditor(element: aktuell, setzen: (d) => set(() => aktuell = aktuell.mit(daten: d)))),
      ),
    )));
    await _foto(tester, 'pc_anschluesse');

    await tester.pumpWidget(app(Scaffold(
      body: Center(child: QrBild(kopplungsText(adressen: ['192.168.178.20'], code: '482913', name: 'PC'), groesse: 200)),
    )));
    await _foto(tester, 'pc_qr');

    for (final (id, name, h, typ) in [('e1', 'Steckdose E2', 'Elektro-Großhandel', 'SD'), ('e2', 'Rauchwarnmelder 10 J', 'Baumarkt', 'RW')]) {
      final b = Bauelement(id: id, kategorie: typ == 'SD' ? BauelementKategorie.elektro : BauelementKategorie.brandschutz, name: name, preisCent: 890, daten: {'haendler': h, 'link': 'https://example.org'});
      state.bibliothek.speichern(b);
      final t = store.objekttypen().firstWhere((x) => x.kuerzel == typ);
      for (var i = 0; i < 3; i++) {
        final o = store.objektAnlegen(geschossId: g, typ: t, punkte: [punktAus([1000 + i * 500, 1500])]);
        store.objektAendern(o, {'eigenschaften': '{"bauelement":"$id"}'});
      }
    }
    await tester.pumpWidget(app(Scaffold(body: Builder(builder: (c) => Center(child: FilledButton(onPressed: () => besorgungslisteZeigen(c, state), child: const Text('Liste')))))));
    await tester.tap(find.text('Liste'));
    await _foto(tester, 'pc_besorgung');
    await tester.pumpWidget(const SizedBox());
    store.schliessen();
  });
}
