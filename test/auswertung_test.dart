import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/auswertung.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/kosten/auswertung_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ProjectStore store;
  late String g;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bauspur_aw_');
    store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'A');
    g = store.geschosse(store.gebaeude().single.id).single.id;
  });
  tearDown(() {
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  Objekttyp typ(String k) => store.objekttypen().firstWhere((t) => t.kuerzel == k);

  test('Einkaufsmenge: Stück aufrunden, Meter mit Zuschlag', () {
    expect(einkaufsMenge(3, 'Stk'), 3);
    expect(einkaufsMenge(2.2, 'Stk'), 3);
    expect(einkaufsMenge(10, 'm'), 11);
    expect(einkaufsMenge(10, 'm', zuschlagProzent: 0), 10);
    expect(einkaufsMenge(12.3, 'm²', zuschlagProzent: 5), 13);
  });

  test('Fortschritt: verlegt, geprüft, verdeckt je Objektart', () {
    final sd = typ('SD'), lt = typ('LT');
    store.objektAnlegen(geschossId: g, typ: sd, punkte: const [Punkt(0, 0)]);
    store.objektAnlegen(geschossId: g, typ: sd, punkte: const [Punkt(500, 0)], status: ObjektStatus.verlegt);
    store.objektAnlegen(geschossId: g, typ: sd, punkte: const [Punkt(900, 0)], status: ObjektStatus.verdeckt);
    store.objektAnlegen(geschossId: g, typ: lt, punkte: const [Punkt(0, 0), Punkt(4000, 0)], status: ObjektStatus.geprueft);
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final z = {for (final x in fortschritt(store.alleObjekte(), typen)) x.typ.kuerzel: x};
    expect(z['SD']!.gesamt, 3);
    expect(z['SD']!.verlegt, 2);
    expect(z['SD']!.verdeckt, 1);
    expect(z['SD']!.offen, 1);
    expect(z['LT']!.einheit, 'm');
    expect(z['LT']!.geprueft, 4);
    expect(z['LT']!.anteil, 1);
    expect(fortschritt(store.alleObjekte(), typen, gewerkId: typ('HV').gewerkId), isEmpty);
  });

  test('Kosten Plan/Ist und Einkaufsliste nach Händler', () {
    final prod = store.produktAnlegen(name: 'NYM-J 3x1,5', einheit: 'm');
    store.angebotAnlegen(produktId: prod, haendler: 'Elektro Müller', preisCent: 100, steuer: 0);
    store.angebotAnlegen(produktId: prod, haendler: 'Baumarkt', preisCent: 150, steuer: 0);
    final a = store.kostenpositionAnlegen(text: 'Kabel', mengeMilli: 50000, einheit: 'm', produktId: prod, einzelCent: 100, steuer: 0);
    final b = store.kostenpositionAnlegen(text: 'Dosen', mengeMilli: 10000, einzelCent: 50, steuer: 0);
    store.kostenpositionAnlegen(text: 'Elektriker', kostenart: 'Lohn', mengeMilli: 1000, einzelCent: 50000, steuer: 0);
    store.kostenpositionAendern(b, {'status': KostenStatus.bezahlt.name});

    final k = kostenVergleich(store.kostenpositionen());
    final summe = k.fold<int>(0, (s, x) => s + x.plan);
    expect(summe, 5000 + 500 + 50000);
    expect(k.fold<int>(0, (s, x) => s + x.bezahlt), 500);

    final liste = einkaufsliste(store.kostenpositionen(), store.produkte());
    expect(liste.keys, ['Elektro Müller']); // günstigster Händler; Lohn und bezahlte Positionen fehlen
    final e = liste['Elektro Müller']!.single;
    expect(e.position.id, a);
    expect(e.menge, 55); // 50 m + 10 %
    expect(e.bruttoCent, 5500);

    final csv = einkaufCsv(liste);
    expect(csv, contains('"Elektro Müller";"Kabel"'));
    final html = einkaufHtml('Test', liste, DateTime(2026, 11, 7));
    expect(html, contains('type="checkbox"'));
    expect(html, contains('55 m'));

    store.kostenpositionAendern(a, {'status': KostenStatus.bestellt.name});
    expect(einkaufsliste(store.kostenpositionen(), store.produkte()), isEmpty);
    expect(einkaufsliste(store.kostenpositionen(), store.produkte(), auchUnterwegs: true).length, 1);
  });

  testWidgets('Einkaufsliste: Abhaken setzt die Position auf bestellt', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final a = store.kostenpositionAnlegen(text: 'Leerrohr M20', mengeMilli: 25000, einheit: 'm', einzelCent: 40);
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))
      ..store = store
      ..geschossId = g;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: EinkaufAnsicht(state: state))));
    expect(find.text('ohne Händler'), findsOneWidget);
    expect(find.text('28 m'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(store.kostenpositionen().firstWhere((p) => p.id == a).status, KostenStatus.bestellt);

    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: PlanIstAnsicht(state: state))));
    expect(find.text('Kosten: Plan und Ist'), findsOneWidget);
    expect(find.text('Summe'), findsOneWidget);
  });
}
