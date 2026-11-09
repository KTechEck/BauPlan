import 'dart:io';

import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schema.dart';
import 'package:bauspur/data/seed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('bauspur_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('Neues Projekt: Ordner, Schema, Startdaten, Sperre', () {
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Haus A/B');
    final ordner = p.join(tmp.path, 'Haus A_B');
    expect(s.ordner, ordner);
    for (final u in projektUnterordner) {
      expect(Directory(p.join(ordner, u)).existsSync(), isTrue, reason: u);
    }
    expect(s.db.userVersion, migrationen.length);
    expect(s.name, 'Haus A/B');

    final geb = s.gebaeude();
    expect(geb.map((g) => g.name), ['Haupthaus']);
    final gs = s.geschosse(geb.single.id);
    expect(gs.single.kuerzel, 'EG');

    final gewerke = s.gewerke();
    expect(gewerke.length, gewerkVorlagen.length);
    final typen = gewerke.fold<int>(0, (n, g) => n + s.anzahlObjekttypen(g.id));
    expect(typen, gewerkVorlagen.fold<int>(0, (n, g) => n + g.typen.length));

    expect(Sperre.lesen(ordner)?.istDieserRechner, isTrue);
    s.schliessen();
    expect(File(p.join(ordner, sperrDatei)).existsSync(), isFalse);
  });

  test('Zweites Anlegen im selben Ordner wird abgelehnt', () {
    ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'X').schliessen();
    expect(
      () => ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'X'),
      throwsStateError,
    );
  });

  test('Wände: anlegen, ändern, weich löschen, wiederherstellen, Protokoll', () {
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'W');
    final eg = s.geschosse(s.gebaeude().single.id).single.id;

    final id = s.wandAnlegen(geschossId: eg, x1: 0, y1: 0, x2: 3000, y2: 4000, dicke: 115);
    var w = s.waende(eg).single;
    expect(w.laenge, 5000);
    expect(w.zustand, WandZustand.bestand);

    s.wandAendern(id, dicke: 240, zustand: WandZustand.abbruch);
    w = s.waende(eg).single;
    expect((w.dicke, w.zustand), (240, WandZustand.abbruch));

    s.wandLoeschen(id);
    expect(s.waende(eg), isEmpty);
    expect(s.db.select('SELECT COUNT(*) AS n FROM wand').first['n'], 1);

    expect(s.wandWiederherstellen(id), isTrue);
    expect(s.waende(eg).length, 1);

    final aktionen = s.db
        .select("SELECT aktion FROM aenderung WHERE tabelle = 'wand' ORDER BY nr")
        .map((r) => r['aktion'])
        .toList();
    expect(aktionen, ['anlegen', 'aendern', 'loeschen', 'wiederherstellen']);
    s.schliessen();
  });

  test('Geschosse und Räume mit eigenen Höhen', () {
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'R');
    final geb = s.gebaeude().single.id;
    final og = s.geschossAnlegen(
      gebaeudeId: geb,
      name: 'Obergeschoss',
      kuerzel: 'og',
      rfb: 2900,
      ffb: 3020,
      rohdecke: 5500,
      meterriss: 4020,
    );
    expect(s.geschosse(geb).map((g) => g.kuerzel), ['EG', 'OG']);
    expect(s.geschoss(og)!.hoehen.ffb, 3020);

    final bad = s.raumAnlegen(geschossId: og, name: 'Bad', kuerzel: 'bad', ffb: 3040);
    s.raumAnlegen(geschossId: og, name: 'Flur', kuerzel: 'FL');
    final raeume = s.raeume(og);
    expect(raeume.map((r) => r.kuerzel), ['BAD', 'FL']);
    expect(raeume.first.hatEigeneHoehen, isTrue);
    expect(raeume.last.hatEigeneHoehen, isFalse);

    s.raumLoeschen(bad);
    expect(s.raeume(og).map((r) => r.name), ['Flur']);
    s.schliessen();
  });

  test('Öffnen legt Sicherung an und behält die Daten', () {
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'O');
    final ordner = s.ordner;
    final eg = s.geschosse(s.gebaeude().single.id).single.id;
    s.wandAnlegen(geschossId: eg, x1: 0, y1: 0, x2: 1000, y2: 0, dicke: 240);
    s.schliessen();

    final s2 = ProjectStore.oeffnen(ordner);
    expect(s2.waende(eg).length, 1);
    final sicherungen = Directory(p.join(ordner, 'backup')).listSync().whereType<File>();
    expect(sicherungen.length, 1);
    s2.schliessen();
  });

  test('Öffnen eines fremden Ordners wird abgelehnt', () {
    expect(() => ProjectStore.oeffnen(tmp.path), throwsStateError);
  });
}
