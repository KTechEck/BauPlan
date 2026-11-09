import 'dart:io';

import 'package:bauspur/core/height.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schema.dart';
import 'package:bauspur/data/seed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bauspur_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  (ProjectStore, String) neu() {
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'T');
    return (s, s.geschosse(s.gebaeude().single.id).single.id);
  }

  void rechteck(ProjectStore s, String g, int x, int y, int b, int h, {int d = 200}) {
    s.wandAnlegen(geschossId: g, x1: x, y1: y, x2: x + b, y2: y, dicke: d);
    s.wandAnlegen(geschossId: g, x1: x + b, y1: y, x2: x + b, y2: y + h, dicke: d);
    s.wandAnlegen(geschossId: g, x1: x + b, y1: y + h, x2: x, y2: y + h, dicke: d);
    s.wandAnlegen(geschossId: g, x1: x, y1: y + h, x2: x, y2: y, dicke: d);
  }

  test('Neues Projekt hat Materialien und Wandtypen aus den Vorlagen', () {
    final (s, _) = neu();
    expect(s.materialien().length, materialVorlagen.length);
    final typen = s.wandtypen();
    expect(typen.length, wandtypVorlagen.length);
    final ks = typen.firstWhere((t) => t.name.contains('WDVS'));
    expect(ks.schichten.length, 5); // inkl. WDVS-Klebemörtel
    expect(ks.dicke, 15 + 175 + 5 + 160 + 5);
    s.schliessen();
  });

  test('Bestehendes Projekt (Version 1) wird migriert und bekommt die Bibliothek', () {
    // Projekt im alten Stand von Hand bauen
    final ordner = p.join(tmp.path, 'Alt');
    Directory(ordner).createSync();
    final db = sqlite3.open(p.join(ordner, datenbankDatei));
    for (final sql in migrationen.first) {
      db.execute(sql);
    }
    db.userVersion = 1;
    db.execute("INSERT INTO projekt (id, name, erstellt) VALUES ('p', 'Alt', '2026-01-01')");
    db.execute("INSERT INTO gebaeude (id, name) VALUES ('g', 'Haus')");
    db.execute("INSERT INTO geschoss (id, gebaeude_id, name, kuerzel) VALUES ('eg', 'g', 'Erdgeschoss', 'EG')");
    db.execute("INSERT INTO raum (id, geschoss_id, name, kuerzel) VALUES ('r', 'eg', 'Bad', 'BAD')");
    db.close();

    final s = ProjectStore.oeffnen(ordner);
    expect(s.db.userVersion, migrationen.length);
    expect(s.materialien(), isNotEmpty);
    expect(s.wandtypen(), isNotEmpty);
    final bad = s.raeume('eg').single;
    expect((bad.name, bad.umriss, bad.bezug), ('Bad', null, null));
    s.schliessen();
  });

  test('Wandtyp zuweisen setzt die Dicke; Schichten ändern zieht alle Wände nach', () {
    final (s, g) = neu();
    final typ = s.wandtypen().firstWhere((t) => t.name.startsWith('Innenwand Ziegel'));
    final w = s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 3000, y2: 0, dicke: 240, wandtypId: typ.id);
    expect(s.waende(g).single.dicke, 145);

    final ziegel = s.materialien().firstWhere((m) => m.name == 'Hochlochziegel').id;
    final gips = s.materialien().firstWhere((m) => m.name == 'Gipsputz').id;
    s.wandtypSchichtenSetzen(typ.id, [Schicht(gips, 10), Schicht(ziegel, 175), Schicht(gips, 10)]);
    expect(s.waende(g).single.dicke, 195);
    expect(s.wandtyp(typ.id)!.schichten.map((e) => e.dicke), [10, 175, 10]);
    // alte Schichten sind nur weich gelöscht
    expect(s.db.select('SELECT COUNT(*) AS n FROM wandtyp_schicht WHERE wandtyp_id = ?', [typ.id]).first['n'], 6);

    // freie Dicke löst die Wand vom Typ
    s.wandAendern(w, dicke: 300);
    final wand = s.waende(g).single;
    expect((wand.dicke, wand.wandtypId), (300, null));

    s.wandWandtypSetzen(w, typ.id);
    expect(s.waende(g).single.wandtypId, typ.id);
    s.wandUmdrehen(w);
    final u = s.waende(g).single;
    expect((u.x1, u.x2), (3000, 0));
    s.schliessen();
  });

  test('Raum auf erkannter Fläche: Umriss folgt Wandänderungen', () {
    final (s, g) = neu();
    rechteck(s, g, 0, 0, 6200, 3200);
    final flaechen = s.flaechenErkennen(g);
    expect(flaechen.length, 1);
    final id = s.raumAnlegen(geschossId: g, name: 'Wohnen', kuerzel: 'WOH', flaeche: flaechen.single);
    var r = s.raeume(g).single;
    expect(r.flaeche, closeTo(6000 * 3000, 1));
    expect(r.umfang, closeTo(18000, 0.5));

    // Trennwand teilt den Raum: Wohnen behält die Hälfte mit seinem Bezugspunkt
    final trenn = s.wandAnlegen(geschossId: g, x1: 1100, y1: 0, x2: 1100, y2: 3200, dicke: 100);
    r = s.raeume(g).single;
    expect(s.flaechenErkennen(g).length, 2);
    final erwartet = r.bezug!.x > 1100 ? (6100 - 1150) * 3000 : (1050 - 100) * 3000;
    expect(r.flaeche, closeTo(erwartet, 1));

    // Wand löschen → Raum wieder groß; Wandzug öffnen → letzter Umriss bleibt
    s.wandLoeschen(trenn);
    expect(s.raeume(g).single.flaeche, closeTo(6000 * 3000, 1));
    final eineWand = s.waende(g).first.id;
    s.wandLoeschen(eineWand);
    expect(s.flaechenErkennen(g), isEmpty);
    expect(s.raeume(g).single.flaeche, closeTo(6000 * 3000, 1));

    // Abbruchwände zählen nicht
    s.wandWiederherstellen(eineWand);
    s.wandAendern(eineWand, zustand: WandZustand.abbruch);
    expect(s.flaechenErkennen(g), isEmpty);

    final aktionen = s.db
        .select("SELECT aktion FROM aenderung WHERE tabelle = 'raum' AND datensatz = ? ORDER BY nr", [id])
        .map((e) => e['aktion'])
        .toList();
    expect(aktionen, ['anlegen', 'umriss', 'umriss']);
    s.schliessen();
  });

  test('Freien Raum verorten und Raum wiederherstellen', () {
    final (s, g) = neu();
    rechteck(s, g, 0, 0, 4200, 3200);
    final id = s.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD');
    expect(s.raeume(g).single.umriss, isNull);
    s.raumVerorten(id, s.flaechenErkennen(g).single);
    expect(s.raeume(g).single.flaeche, closeTo(12e6, 1));
    s.raumAendern(id, name: 'Bad oben');
    s.raumLoeschen(id);
    expect(s.raeume(g), isEmpty);
    s.raumWiederherstellen(id);
    expect(s.raeume(g).single.name, 'Bad oben');
    s.schliessen();
  });

  test('Material anlegen, ändern, Verwendung, weich löschen', () {
    final (s, _) = neu();
    final id = s.materialAnlegen(name: 'Lehmputz', kategorie: 'Putz', farbe: 0xFFCCBB99);
    s.materialAendern(id, farbe: 0xFF000000);
    expect(s.materialien().last.farbe, 0xFF000000);
    expect(s.materialVerwendung(id), 0);
    final gips = s.materialien().firstWhere((m) => m.name == 'Gipsputz').id;
    expect(s.materialVerwendung(gips), greaterThan(1));
    s.materialLoeschen(id);
    expect(s.materialien().any((m) => m.id == id), isFalse);
    s.schliessen();
  });

  test('Wände gemeinsam verschieben: Raum wandert mit, Rückweg stellt alles her', () {
    final (s, g) = neu();
    rechteck(s, g, 0, 0, 4200, 3200);
    s.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: s.flaechenErkennen(g).single);
    final ids = s.waende(g).map((w) => w.id).toList();

    s.waendeVerschieben(ids, 0, 10000); // alles weit nach unten
    var r = s.raeume(g).single;
    expect(r.bezug!.y, greaterThan(10000));
    expect(r.umriss!.every((p) => p.y >= 10000), isTrue);
    expect(r.flaeche, closeTo(12e6, 1));

    s.waendeVerschieben(ids, 0, -10000);
    r = s.raeume(g).single;
    expect(r.umriss!.every((p) => p.y < 3200), isTrue);

    // nur eine Wand verschieben: Raum wird größer, bleibt am Platz
    final rechts = s.waende(g).firstWhere((w) => w.x1 == 4200 && w.x2 == 4200).id;
    s.waendeVerschieben([rechts], 1000, 0);
    // Ober- und Unterwand enden jetzt vor der verschobenen Wand → Wandzug offen
    expect(s.flaechenErkennen(g), isEmpty);
    s.waendeVerschieben([rechts], -1000, 0);
    expect(s.flaechenErkennen(g).length, 1);
    s.schliessen();
  });

  test('Wandlänge ändern: Nachbarn ziehen mit, Raum bleibt rechteckig, Rückgängig', () {
    final (s, g) = neu();
    rechteck(s, g, 0, 0, 4200, 3200);
    s.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: s.flaechenErkennen(g).single);
    final oben = s.waende(g).firstWhere((w) => w.y1 == 0 && w.y2 == 0);
    final alt = s.wandLaengeAendern(oben.id, 5200);
    expect(alt.length, 3); // obere, rechte (verschoben), untere (gestreckt)
    expect(s.raeume(g).single.flaeche, closeTo(5000 * 3000, 1));
    final rechts = s.waende(g).firstWhere((w) => w.x1 == w.x2 && w.x1 != 0);
    expect((rechts.x1, rechts.x2), (5200, 5200));

    s.waendeKoordinatenSetzen(alt);
    expect(s.raeume(g).single.flaeche, closeTo(4000 * 3000, 1));

    // am Anfang ändern: Ende bleibt stehen
    s.wandLaengeAendern(oben.id, 3200, amAnfang: true);
    final o = s.waende(g).firstWhere((w) => w.id == oben.id);
    expect((o.x1, o.x2), (1000, 4200));
    expect(s.raeume(g).single.flaeche, closeTo(3000 * 3000, 1));
    s.schliessen();
  });

  test('Maßanzeige je Wand speichern und zurücksetzen', () {
    final (s, g) = neu();
    final id = s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 3000, y2: 0, dicke: 200);
    expect(s.waende(g).single.massanzeige, isNull);
    s.waendeMassanzeigeSetzen([id], MassAnzeige.achseInnen);
    expect(s.waende(g).single.massanzeige, MassAnzeige.achseInnen);
    s.waendeMassanzeigeSetzen([id], null);
    expect(s.waende(g).single.massanzeige, isNull);
    s.schliessen();
  });

  test('Bemaßung anlegen, weich löschen, wiederherstellen', () {
    final (s, g) = neu();
    final id = s.bemassungAnlegen(geschossId: g, x1: 0, y1: 0, x2: 3000, y2: 4000, abstand: -600);
    final b = s.bemassungen(g).single;
    expect((b.laenge, b.abstand), (5000.0, -600));
    s.bemassungLoeschen(id);
    expect(s.bemassungen(g), isEmpty);
    s.bemassungWiederherstellen(id);
    expect(s.bemassungen(g).length, 1);
    s.schliessen();
  });

  test('Gesperrte Wände: Länge ändert am anderen Ende, Verschieben/Löschen bleiben aus', () {
    final (s, g) = neu();
    rechteck(s, g, 0, 0, 4200, 3200);
    final oben = s.waende(g).firstWhere((w) => w.y1 == 0 && w.y2 == 0);
    final rechts = s.waende(g).firstWhere((w) => w.x1 == 4200 && w.x2 == 4200);
    s.waendeSperren([rechts.id], true);
    s.wandLaengeAendern(oben.id, 5200); // rechts gesperrt → links wird bewegt
    final o = s.waende(g).firstWhere((w) => w.id == oben.id);
    expect((o.x1, o.x2), (-1000, 4200));
    s.waendeVerschieben([rechts.id], 500, 0);
    expect(s.waende(g).firstWhere((w) => w.id == rechts.id).x1, 4200);
    s.wandLoeschen(rechts.id);
    expect(s.waende(g).any((w) => w.id == rechts.id), isTrue);
    s.schliessen();
  });

  test('Bemaßung ändern verlängert eine freie Wand; Bemaßung wandert mit', () {
    final (s, g) = neu();
    final w = s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 3000, y2: 0, dicke: 200);
    final b = s.bemassungAnlegen(geschossId: g, x1: 0, y1: 0, x2: 3000, y2: 0, abstand: 500);
    final zurueck = s.bemassungAendern(b, 3500);
    expect(zurueck, isNotNull);
    expect(s.waende(g).single.laenge, closeTo(3500, 1));
    expect(s.bemassungen(g).single.laenge, closeTo(3500, 1));
    zurueck!();
    expect(s.waende(g).single.laenge, closeTo(3000, 1));
    // Wand verschieben: Bemaßung zieht mit
    s.waendeVerschieben([w], 0, 1000);
    expect(s.bemassungen(g).single.y1, 1000);
    s.schliessen();
  });

  test('Winkelmaß: Winkel einstellen dreht die zweite Wand', () {
    final (s, g) = neu();
    final a = s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 3000, y2: 0, dicke: 200);
    final b = s.wandAnlegen(geschossId: g, x1: 3000, y1: 0, x2: 3000, y2: 2000, dicke: 200);
    final m = s.winkelmassAnlegen(g, a, b);
    final zurueck = s.winkelAendern(m, 135);
    final wb = s.waende(g).firstWhere((w) => w.id == b);
    // 135° zwischen den Wänden: zweite Wand läuft schräg nach unten rechts
    expect(wb.x2, closeTo(3000 + 2000 * 0.7071, 2));
    expect(wb.y2, closeTo(2000 * 0.7071, 2));
    expect(wb.laenge, closeTo(2000, 2));
    zurueck!();
    expect(s.waende(g).firstWhere((w) => w.id == b).x2, 3000);
    s.schliessen();
  });

  test('Projekteinstellungen speichern', () {
    final (s, _) = neu();
    expect(s.einstellung<bool>('ecken_verbinden'), isNull);
    s.einstellungSetzen('ecken_verbinden', false);
    expect(s.einstellung<bool>('ecken_verbinden'), isFalse);
    s.schliessen();
  });

  test('Öffnungen: anlegen, ändern, löschen, verschwinden mit der Wand', () {
    final (s, g) = neu();
    final w = s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 4000, y2: 0, dicke: 240);
    final o = s.oeffnungAnlegen(wandId: w, art: OeffnungsArt.tuer, abstand: 500, breite: 885, hoehe: 2010);
    expect(s.oeffnungen(g).single.breite, 885);
    final alt = s.oeffnungAendern(o, {'breite_mm': 1010, 'band_rechts': 1});
    final e = s.oeffnungen(g).single;
    expect((e.breite, e.bandRechts), (1010, true));
    s.oeffnungAendern(o, alt);
    expect(s.oeffnungen(g).single.breite, 885);
    s.wandLoeschen(w);
    expect(s.oeffnungen(g), isEmpty);
    s.wandWiederherstellen(w);
    s.oeffnungLoeschen(o);
    expect(s.oeffnungen(g), isEmpty);
    s.schliessen();
  });

  test('Planvorlage: Bild wird ins Projekt kopiert und ist kalibrierbar', () {
    final (s, g) = neu();
    final bild = File(p.join(tmp.path, 'scan.png'))..writeAsBytesSync([137, 80, 78, 71]);
    final id = s.planvorlageAnlegen(g, bild.path);
    final v = s.planvorlage(g)!;
    expect(File(p.join(s.ordner, v.datei)).existsSync(), isTrue);
    s.planvorlageAendern(id, umProPx: 5000, x: -100, deckkraft: 75, sichtbar: false);
    final v2 = s.planvorlage(g)!;
    expect((v2.mmProPx, v2.x, v2.deckkraft, v2.sichtbar), (5.0, -100, 75, false));
    // zweite Vorlage ersetzt die erste
    s.planvorlageAnlegen(g, bild.path);
    expect(s.planvorlage(g)!.id, isNot(id));
    s.schliessen();
  });

  test('Objekte: Kennung je Raum und Typ fortlaufend, Höhe mit Bezug, Länge einer Leitung', () {
    final (s, g) = neu();
    rechteck(s, g, 0, 0, 4200, 3200);
    final bad = s.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: s.flaechenErkennen(g).single);
    final sd = s.objekttypen().firstWhere((t) => t.kuerzel == 'SD');
    final lt = s.objekttypen().firstWhere((t) => t.kuerzel == 'LT');
    final a = s.objektAnlegen(geschossId: g, typ: sd, punkte: [const Punkt(500, 100)], raumId: bad, z: 300, zBezug: Hoehenbezug.ffb);
    s.objektAnlegen(geschossId: g, typ: sd, punkte: [const Punkt(900, 100)], raumId: bad);
    s.objektAnlegen(geschossId: g, typ: lt, punkte: [const Punkt(0, 0), const Punkt(3000, 0), const Punkt(3000, 4000)]);
    final o = s.objekte(g);
    expect(o.map((e) => e.kennung).toList(), ['EG-ALLG-LT-01', 'EG-BAD-SD-01', 'EG-BAD-SD-02']);
    expect(o.first.laenge, 7000);
    final erste = o.firstWhere((e) => e.id == a);
    expect((erste.z, erste.zBezug), (300, Hoehenbezug.ffb));
    final alt = s.objektAendern(a, {'status': 'verlegt'});
    expect(s.objekte(g).firstWhere((e) => e.id == a).status, ObjektStatus.verlegt);
    s.objektAendern(a, alt);
    s.objektLoeschen(a);
    expect(s.objekte(g).length, 2);
    // gelöschte Kennungen werden nicht neu vergeben
    s.objektAnlegen(geschossId: g, typ: sd, punkte: [const Punkt(1500, 100)], raumId: bad);
    expect(s.objekte(g).map((e) => e.kennung), contains('EG-BAD-SD-03'));
    expect(s.objekteJeGewerk(g).values.fold<int>(0, (a, b) => a + b), 3);
    s.schliessen();
  });

  test('Fotos: Import nach medien/Geschoss/Raum, verorten, Objekt zuordnen, löschen', () {
    final (s, g) = neu();
    rechteck(s, g, 0, 0, 4200, 3200);
    final bad = s.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: s.flaechenErkennen(g).single);
    final quelle = File(p.join(tmp.path, 'IMG_0001.jpg'))..writeAsBytesSync(List.filled(100, 7));
    final id = s.fotoImportieren(quelle.path, geschossId: g, raumId: bad);
    var f = s.fotos(g).single;
    expect(f.datei.replaceAll('\\', '/'), startsWith('medien/EG/BAD/'));
    expect(File(p.join(s.ordner, f.datei)).existsSync(), isTrue);
    expect(f.verortet, isFalse);
    s.fotoMarkerAendern(id, {'x_mm': 1000, 'y_mm': 800, 'richtung': 90});
    final lr = s.objektAnlegen(
        geschossId: g, typ: s.objekttypen().firstWhere((t) => t.kuerzel == 'LR'), punkte: [const Punkt(0, 0), const Punkt(1000, 0)]);
    s.fotoObjektZuordnen(id, lr, true);
    s.fotoObjektZuordnen(id, lr, true); // doppelt bleibt einmal
    f = s.fotos(g).single;
    expect((f.x, f.richtung), (1000, 90));
    expect(f.objektIds, [lr]);
    expect(s.fotosJeObjekt(g), {lr: 1});
    s.fotoObjektZuordnen(id, lr, false);
    expect(s.fotos(g).single.objektIds, isEmpty);
    s.fotoLoeschen(id);
    expect(s.fotos(g), isEmpty);
    s.schliessen();
  });

  test('Kosten: Mengen aus dem Plan mit Produktpreis, Status bleibt beim Nachführen', () {
    final (s, g) = neu();
    final sd = s.objekttypen().firstWhere((t) => t.kuerzel == 'SD');
    final lr = s.objekttypen().firstWhere((t) => t.kuerzel == 'LR');
    final p = s.produktAnlegen(name: 'Steckdose weiß');
    s.angebotAnlegen(produktId: p, haendler: 'A', preisCent: 899);
    s.angebotAnlegen(produktId: p, haendler: 'B', preisCent: 749);
    final o1 = s.objektAnlegen(geschossId: g, typ: sd, punkte: [const Punkt(0, 0)]);
    final o2 = s.objektAnlegen(geschossId: g, typ: sd, punkte: [const Punkt(500, 0)]);
    s.objektAendern(o1, {'produkt_id': p});
    s.objektAendern(o2, {'produkt_id': p});
    s.objektAnlegen(geschossId: g, typ: lr, punkte: [const Punkt(0, 0), const Punkt(2500, 0)]);
    expect(s.planMengenNachfuehren(), 2);
    var pos = s.kostenpositionen();
    final steck = pos.firstWhere((e) => e.produktId == p);
    expect((steck.mengeMilli, steck.einzelCent, steck.nettoCent), (2000, 749, 1498));
    expect(steck.bruttoCent, 1498 + 285);
    expect(pos.firstWhere((e) => e.einheit == 'm').mengeMilli, 2500);
    s.kostenpositionAendern(steck.id, {'status': 'bestellt'});
    s.objektLoeschen(o2);
    s.planMengenNachfuehren();
    pos = s.kostenpositionen();
    final neu2 = pos.firstWhere((e) => e.produktId == p);
    expect((neu2.mengeMilli, neu2.status), (1000, KostenStatus.bestellt));
    expect(euroText(123456), '1.234,56 €');
    expect(dezimalLesen('12,5', 100), 1250);
    s.schliessen();
  });

  test('Bemaßung an den Wandseiten ändert die Raumbreite (quer stehende Wand wandert)', () {
    final (s, g) = neu();
    rechteck(s, g, 0, 0, 4200, 3200); // innen 100 … 4100 × 100 … 3100
    s.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'BAD', flaeche: s.flaechenErkennen(g).single);
    // Innenmaß mitten an den Seiten gemessen (nicht an Ecken)
    final b = s.bemassungAnlegen(geschossId: g, x1: 100, y1: 1600, x2: 4100, y2: 1600, abstand: 0);
    expect(s.bemassungAendern(b, 5000), isNotNull);
    expect(s.raeume(g).single.flaeche, closeTo(5000 * 3000, 1));
    expect(s.bemassungen(g).single.laenge, closeTo(5000, 1));
    s.schliessen();
  });

  test('Maße einzeln ausblenden und wieder zeigen', () {
    final (s, g) = neu();
    final b = s.bemassungAnlegen(geschossId: g, x1: 0, y1: 0, x2: 1000, y2: 0, abstand: 300);
    s.massVerstecken('bemassung', b, true);
    expect(s.bemassungen(g).single.versteckt, isTrue);
    expect(s.versteckteMasseZeigen(g).length, 1);
    expect(s.bemassungen(g).single.versteckt, isFalse);
    s.schliessen();
  });

  test('FBH: Heizkreis erscheint als Heizrohr in Metern in der Kostenliste', () {
    final (s, g) = neu();
    final hk = s.objekttypen().firstWhere((t) => t.kuerzel == 'HK');
    final id = s.objektAnlegen(geschossId: g, typ: hk, punkte: const [Punkt(0, 0), Punkt(4000, 0), Punkt(4000, 3000), Punkt(0, 3000)]);
    s.objektAendern(id, {'eigenschaften': '{"va_mm":150,"rand_mm":100,"muster":"maeander","zuleitung_mm":3000}'});
    expect(s.objekte(g).single.eigenschaften['va_mm'], 150);
    s.planMengenNachfuehren();
    final p = s.kostenpositionen().single;
    expect(p.einheit, 'm');
    expect(p.text, startsWith('Heizrohr'));
    expect(p.mengeMilli / 1000, inInclusiveRange(68, 86)); // ≈ 71 m + Rücklaufbahn + 6 m Zuleitung
    s.schliessen();
  });
}
