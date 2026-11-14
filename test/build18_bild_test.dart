// Bildschirmfotos der Build-17/18-Teile. Ohne BAUSPUR_BILD nur Aufbau ohne Fehler.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/bauelemente.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/verteiler.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/bauteile/anschluss_editor.dart';
import 'package:bauspur/ui/benutzer_rollen.dart';
import 'package:bauspur/ui/einstellungen_mehr.dart';
import 'package:bauspur/ui/verteiler/abgleich_page.dart';
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
  expect(tester.takeException(), isNull, reason: name);
  if (_ziel == null) return;
  final ro = _rahmen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_ziel/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('Build 18: neue Seiten bauen ohne Fehler', (tester) async {
    if (_ziel != null) await tester.runAsync(_schriften);
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 860);
    final tmp = Directory.systemTemp.createTempSync('bauspur_b18_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Wohnhaus');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    const e = [(0, 0), (4000, 0), (4000, 3000), (0, 3000)];
    for (var i = 0; i < 4; i++) {
      store.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 240);
    }
    final raum = store.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: store.flaechenErkennen(g).single);
    final typ = {for (final t in store.objekttypen()) t.kuerzel: t};
    final hv = store.objektAnlegen(geschossId: g, typ: typ['HV']!, punkte: const [Punkt(300, 200)], raumId: raum);
    final k1 = store.objektAnlegen(geschossId: g, typ: typ['HK']!, raumId: raum, punkte: const [Punkt(200, 400), Punkt(3800, 400), Punkt(3800, 2800), Punkt(200, 2800)]);
    store.objektAendern(hv, {'eigenschaften': jsonEncode(VerteilerDaten(abgaenge: 3, kreise: [k1, null, null]).toJson())});
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;
    Widget app(Widget kind) => RepaintBoundary(key: _rahmen, child: MaterialApp(debugShowCheckedModeBanner: false, theme: bauSpurTheme(), home: kind));

    await tester.pumpWidget(app(AbgleichPage(state: state, verteilerId: hv)));
    await _foto(tester, 'b18_abgleich');

    for (final (name, w) in [
      ('zeichnen', ZeichnenAnsicht(state: state)),
      ('projekt', ProjektGeschosseAnsicht(state: state)),
      ('vorgaben', VorgabenAnsicht(state: state)),
      ('objekttypen', ObjekttypenAnsicht(state: state)),
      ('kennungen', KennungenAnsicht(state: state)),
      ('benutzer', BenutzerAnsicht(state: state)),
    ]) {
      await tester.pumpWidget(app(Scaffold(body: w)));
      await _foto(tester, 'b18_einst_$name');
    }

    var el = Bauelement(
      id: 'x1',
      kategorie: BauelementKategorie.technik,
      name: 'Wärmepumpe Innenteil',
      daten: const {'breite': 600, 'hoehe': 1800, 'tiefe': 600, 'freiraum_seite': 200, 'freiraum_oben': 300, 'einbauhoehe': 900},
    );
    await tester.pumpWidget(app(Scaffold(
      body: StatefulBuilder(builder: (c, setS) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: AnschlussEditor(element: el, setzen: (d) => setS(() => el = el.mit(daten: d))))),
    )));
    await tester.tap(find.text('4 Bohrlöcher an den Ecken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Typische Anschlüsse vorschlagen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VL').first);
    await _foto(tester, 'b18_schaubild');
    expect(el.daten['bohrungen'], hasLength(4));

    await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: BenutzerRollenKarte(state: state)))));
    await _foto(tester, 'b18_rollen');
    store.schliessen();
  });
}
