import 'dart:io';

import 'package:bauspur/core/wandaufbau.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Umstellung auf Kern + Aufbau: Achse auf Kernmitte, Ecken verbunden, Öffnung bleibt, rückgängig', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_b36_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'K');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final ziegel = store.materialien().firstWhere((m) => m.name == 'Hochlochziegel').id;
    final putz = store.materialien().firstWhere((m) => m.name == 'Gipsputz').id;
    final typ = store.wandtypAnlegen('Test WDVS', [Schicht(putz, 160), Schicht(ziegel, 240), Schicht(putz, 15)]);
    // alte Wände (ohne Kern) wie vor Build 36: Gesamtdicke 415, Achse in der Mitte
    final ids = <String>[];
    for (final (x1, y1, x2, y2) in [(0, 0, 6000, 0), (6000, 0, 6000, 4000), (6000, 4000, 0, 4000), (0, 4000, 0, 0)]) {
      final id = store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 415);
      store.db.execute("UPDATE wand SET wandtyp_id = ?, dicke_mm = 415, eigenschaften = '{}' WHERE id = ?", [typ, id]);
      ids.add(id);
    }
    store.oeffnungAnlegen(wandId: ids[0], art: OeffnungsArt.fenster, abstand: 2000, breite: 1000, hoehe: 1200, bruestung: 900);
    Offset fenster() {
      final w = store.waende(g).firstWhere((x) => x.id == ids[0]);
      final o = store.oeffnungen(g).single;
      final l = w.laenge;
      return Offset(w.x1 + (w.x2 - w.x1) * o.abstand / l, w.y1 + (w.y2 - w.y1) * o.abstand / l);
    }

    final vorher = fenster();
    expect(store.wandmodellUmstellen(g), 4);
    final ws = store.waende(g);
    expect(ws.every(hatKern), isTrue);
    expect(ws.every((w) => w.dicke == 240), isTrue);
    // Ecken weiter verbunden: jedes Ende trifft ein Ende einer anderen Wand
    for (final w in ws) {
      for (final (x, y) in [(w.x1, w.y1), (w.x2, w.y2)]) {
        expect(ws.where((o) => o.id != w.id && ((o.x1 - x).abs() <= 1 && (o.y1 - y).abs() <= 1 || (o.x2 - x).abs() <= 1 && (o.y2 - y).abs() <= 1)), isNotEmpty);
      }
    }
    // Achse liegt nicht mehr bei 0 (Kernmitte verschoben)
    expect(ws.firstWhere((w) => w.id == ids[0]).y1, isNot(0));
    expect((fenster() - vorher).distance, lessThan(80), reason: 'Fenster bleibt etwa an seiner Stelle');
    // Bänder: außen 160 mm WDVS, an der Ecke auf Gehrung
    final baender = aufbauBaender(ws);
    expect(baender, isNotEmpty);
    expect(store.wandmodellZurueck(g), isTrue);
    expect(store.waende(g).firstWhere((w) => w.id == ids[0]).y1, 0);
    expect(store.waende(g).every((w) => w.dicke == 415), isTrue);
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Aufbau je Seite mit Bereichen', () {
    final w = Wand(id: 'w', geschossId: 'g', x1: 0, y1: 0, x2: 5000, y2: 0, dicke: 175, zustand: WandZustand.bestand, eigenschaften: {
      'kern': {'d': 175},
      'aufbau_l': [
        {'s': [{'m': 'putz', 'd': 15}]},
        {'von': 0, 'bis': 1200, 'z_bis': 2100, 's': [{'m': 'putz', 'd': 10}, {'m': 'fliese', 'd': 10}]},
      ],
    });
    expect(schichtenBei(w, true, 600).map((s) => s.material), ['putz', 'fliese']);
    expect(schichtenBei(w, true, 600, z: 2400).map((s) => s.material), ['putz']);
    expect(schichtenBei(w, true, 3000).single.dicke, 15);
    expect(schichtenQuer(w, 600).map((s) => s.dicke), [10, 10, 175]);
    final a = ausWandtyp(const [Schicht('a', 160), Schicht('b', 240), Schicht('c', 15)]);
    expect(a.kern, 240);
    expect(a.versatz, closeTo((160 + 240 + 15) / 2 - (160 + 120), 1e-9));
  });
}
