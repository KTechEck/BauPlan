import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/fassade.dart';
import 'package:bauspur/core/pdf_bild.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/floorplan/fassade_dialog.dart';
import 'package:bauspur/ui/symbol_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('WDVS-Mengen, U-Wert, Balkon, Sockelleisten, Deckenfeld, Bodenstrahler', () {
    const v = WdvsVorgaben(dicke: 160, daemmstoff: 'EPS 032');
    // 4 Seiten à 10 m × 3 m, ein Fenster 1×1,25 und eine Tür 1×2,1
    final seiten = [
      (name: 'N', laenge: 10000.0, hoehe: 3000.0, oeffnungen: [(b: 1000.0, h: 1250.0, tuer: false)]),
      (name: 'O', laenge: 10000.0, hoehe: 3000.0, oeffnungen: <({double b, double h, bool tuer})>[]),
      (name: 'S', laenge: 10000.0, hoehe: 3000.0, oeffnungen: [(b: 1000.0, h: 2100.0, tuer: true)]),
      (name: 'W', laenge: 10000.0, hoehe: 3000.0, oeffnungen: <({double b, double h, bool tuer})>[]),
    ];
    final e = wdvsBerechnen(seiten, v);
    // brutto 120 − Öffnungen 3,35 − Sockel (40 − 1) · 0,3 = 11,7 → 104,95 m²
    expect(e.flaeche, closeTo(104.95, 0.01));
    expect(e.platten, (104.95 / 0.5 * 1.05).ceil());
    expect(e.sockelschiene, closeTo(39, 1e-9));
    expect(e.tropfkante, 2);
    expect(e.duebel, greaterThan(104.95 * 6));
    expect(uMitWdvs(1.4, v), closeTo(1 / (1 / 1.4 + 0.16 / 0.032), 1e-9));
    expect(montageteil('Markise'), contains('Montagequader'));
    expect(balkonHinweise(flaecheM2: 8).length, 5);
    final s = sockelleisten(umfangMm: 16000, tuerbreitenMm: [885], innenecken: 4, aussenecken: 0);
    expect(s.laenge, closeTo(15.115 * 1.08, 1e-9));
    expect(s.staebe, 7);
    expect(s.endkappen, 2);
    // L-Raum: 5 Innenecken, 1 Außenecke
    expect(eckenZaehlen(const [(0, 0), (4000, 0), (4000, 1500), (2000, 1500), (2000, 3000), (0, 3000)]), (5, 1));
    final d = deckenfeldMaterial(10, 13);
    expect(d.ud, 13);
    expect(d.abhaenger, 11);
    final b = bodenstrahlerPruefen([10, 65, 30, 180], 110, abdichtungIndex: 2);
    expect(b.passt, isFalse);
    expect(b.verfuegbar, 75);
    expect(bodenstrahlerPruefen([30, 40, 100, 3, 150], 60, abdichtungIndex: 2).passt, isTrue);
  });

  test('PDF als Planvorlage (Windows)', () async {
    if (!Platform.isWindows) return;
    final tmp = Directory.systemTemp.createTempSync('bauspur_b26pdf_');
    final d = pw.Document()..addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (c) => pw.Center(child: pw.Container(width: 100, height: 100, color: PdfColors.black))));
    final f = File('${tmp.path}/plan.pdf')..writeAsBytesSync(await d.save());
    final r = await pdfSeiteAlsPng(f.path, '${tmp.path}/plan.png', dpi: 100);
    expect(r, isNotNull);
    expect(r!.breitePt, closeTo(PdfPageFormat.a4.width, 1));
    expect(File(r.png).lengthSync(), greaterThan(1000));
    expect(umProPxAusMassstab(200, 100), 12700);
    tmp.deleteSync(recursive: true);
  });

  testWidgets('Fassade-Dialog und Symbol-Editor öffnen', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_b26_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'F');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    for (final (x1, y1, x2, y2) in [(0, 0, 6000, 0), (6000, 0, 6000, 4000), (6000, 4000, 0, 4000), (0, 4000, 0, 0)]) {
      store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 365);
    }
    store.raumAnlegen(geschossId: g, name: 'Wohnen', kuerzel: 'WO', flaeche: store.flaechenErkennen(g).single);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))
      ..store = store
      ..geschossId = g;
    expect(aussenSeiten(store.waende(g), store.raeume(g)).length, 4);
    await tester.pumpWidget(MaterialApp(
      theme: bauSpurTheme(),
      home: Scaffold(body: Builder(builder: (c) => Column(children: [
            TextButton(onPressed: () => fassadeDialog(c, state), child: const Text('F')),
            TextButton(onPressed: () => symbolEditor(c, state, typId: store.objekttypen().first.id, typName: 'Test'), child: const Text('S')),
          ]))),
    ));
    await tester.tap(find.text('F'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dämmfläche'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S'));
    await tester.pumpAndSettle();
    final feld = find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_EditorPainter');
    await tester.dragFrom(tester.getTopLeft(feld) + const Offset(40, 40), const Offset(120, 120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(symbolFuerTyp(store, store.objekttypen().first.id)!.teile.single['t'], 'l');
  });
}
