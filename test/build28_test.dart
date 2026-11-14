import 'dart:convert';
import 'dart:io';

import 'package:bauspur/core/bauelemente.dart';
import 'package:bauspur/core/inhaltspaket.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/updater.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/assistent/projektpruefung.dart';
import 'package:bauspur/ui/ersteinrichtung.dart';
import 'package:bauspur/ui/export/daten_export.dart';
import 'package:bauspur/ui/suche.dart';
import 'package:bauspur/ui/tastenkuerzel.dart';
import 'package:bauspur/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SHA-256, Build-Nummer, Update aus Ordner mit Prüfsummen', () async {
    expect(sha256Hex(utf8.encode('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(sha256Hex(const []), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(buildNummer('Build 28 · 14.11.2026'), 28);
    final tmp = Directory.systemTemp.createTempSync('bauspur_upd_');
    try {
      File('${tmp.path}/bauspur.exe').writeAsStringSync('neu');
      Directory('${tmp.path}/data').createSync();
      File('${tmp.path}/data/app.so').writeAsStringSync('code');
      await updateManifestSchreiben(tmp.path, 'Build 29 · 15.11.2026');
      expect(updateSuchen(tmp.path, 'Build 29 · 15.11.2026'), isNull);
      final u = updateSuchen(tmp.path, 'Build 28 · 14.11.2026');
      expect(u!.dateien.keys, containsAll(['bauspur.exe', 'data/app.so']));
      expect(await updatePruefen(u), isEmpty);
      File('${tmp.path}/data/app.so').writeAsStringSync('manipuliert');
      expect((await updatePruefen(u)).single, contains('Prüfsumme'));
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('Maßeinheit, Tastenbelegung', () {
    MassEinheit.setzen('cm');
    expect(mmText(2135), '213,5');
    expect(massText(2000), '200 cm');
    MassEinheit.setzen('m');
    expect(mmText(2135), '2,135');
    MassEinheit.setzen('mm');
    expect(massText(2135), '${mmText(2135)} mm');
    TastenBelegung.karte = {'W': 'Q'};
    expect(TastenBelegung.uebersetzen(LogicalKeyboardKey.keyQ), LogicalKeyboardKey.keyW);
    expect(TastenBelegung.uebersetzen(LogicalKeyboardKey.keyW), LogicalKeyboardKey.f24);
    expect(TastenBelegung.uebersetzen(LogicalKeyboardKey.keyM), LogicalKeyboardKey.keyM);
    TastenBelegung.karte = const {};
  });

  test('Suche, Vorlage, Datenausgaben, Bauablauf, Inhaltspakete', () async {
    final tmp = Directory.systemTemp.createTempSync('bauspur_b28_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Such');
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;
    try {
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      for (final (x1, y1, x2, y2) in [(0, 0, 4000, 0), (4000, 0, 4000, 3000), (4000, 3000, 0, 3000), (0, 3000, 0, 0)]) {
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
      }
      final r = store.raumAnlegen(geschossId: g, name: 'Arbeitszimmer', kuerzel: 'AZ', flaeche: store.flaechenErkennen(g).single);
      final typ = {for (final t in store.objekttypen()) t.kuerzel: t};
      final o = store.objektAnlegen(geschossId: g, typ: typ['HK']!, raumId: r, punkte: const [Punkt(100, 100), Punkt(2000, 100), Punkt(2000, 2000)]);
      store.objektAendern(o, {'status': ObjektStatus.verdeckt.name, 'eigenschaften': jsonEncode({'ha_entity': 'climate.az'})});
      store.aufgabeAnlegen(titel: 'Sockelleiste Arbeitszimmer', art: 'restarbeit');
      final t = suchen(state, 'arbeitsz');
      expect(t.map((x) => x.gruppe).toSet(), containsAll(['Räume', 'Aufgaben und Mängel']));
      expect(suchen(state, 'a'), isEmpty);
      // Vorlage
      store.einstellungSetzen('verschnitt_prozent', 12);
      store.einstellungSetzen('bestand', {'x': 3});
      final v = await einstellungenAlsVorlage(state, 'Test');
      final neu = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Neu');
      vorlageAnwenden(neu, v);
      expect(neu.einstellung<num>('verschnitt_prozent'), 12);
      expect(neu.einstellung<Map>('bestand'), isNull);
      neu.schliessen();
      // Datenausgaben
      final csv = await datenAusgeben(store, 'csv');
      expect(File('$csv/Raeume.csv').readAsStringSync(), contains('Arbeitszimmer'));
      expect(File('$csv/Objekte.csv').existsSync(), isTrue);
      final dxf = await datenAusgeben(store, 'dxf');
      final d = Directory(dxf).listSync().whereType<File>().single.readAsStringSync();
      expect(d, contains('WAENDE_BESTAND'));
      expect(d, contains('EOF'));
      final svg = await datenAusgeben(store, 'svg');
      expect(Directory(svg).listSync().whereType<File>().single.readAsStringSync(), contains('<svg'));
      final ha = await datenAusgeben(store, 'ha');
      expect(File('$ha/bereiche.yaml').readAsStringSync(), contains('climate.az'));
      // Bauablauf: Heizkreis verdeckt ohne Druckprobe
      final b = bauablaufPruefen(store, {for (final t in store.objekttypen()) t.id: t}, {for (final g in store.gewerke()) g.id: g.kuerzel});
      expect(b.single.text, contains('Druckprobe Heizung'));
      // Inhaltspakete automatisch: nur neue Elemente, nur geänderte Dateien
      final po = Directory('${tmp.path}/pakete')..createSync();
      final el = Bauelement(id: 'p-1', kategorie: BauelementKategorie.elektro, name: 'Steckdose X');
      File('${po.path}/a.json').writeAsStringSync(bibliothekPaket([el], name: 'Elektro'));
      final r1 = paketeAusOrdner(po.path, {}, {});
      expect(r1.neu['Elektro']!.single.id, 'p-1');
      final r2 = paketeAusOrdner(po.path, {'p-1'}, r1.stand);
      expect(r2.neu, isEmpty);
    } finally {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    }
  });
}
