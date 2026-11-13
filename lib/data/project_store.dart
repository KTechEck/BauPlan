import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../core/fbh.dart';
import '../core/height.dart';
import '../core/ids.dart';
import '../core/kennung.dart';
import '../core/raumerkennung.dart';
import '../core/wandmasse.dart';
import 'models.dart';
import 'schrank_models.dart';
import 'tagebuch_models.dart';
import 'schema.dart';
import 'seed.dart';

/// Dateiname der Projektdatenbank im Projektordner.
const datenbankDatei = 'projekt.bauspur';
const sperrDatei = 'projekt.lock';

/// Unterordner, die jedes Projekt bekommt (siehe Lastenheft, Datenmodell).
const projektUnterordner = [
  'planstand',
  'planstand/vorschau',
  'eingang',
  'eingang/_archiv',
  'medien',
  'dokumente/datenblaetter',
  'dokumente/rechnungen',
  'dokumente/protokolle',
  'exporte',
  'backup',
];

/// Wer hält das Projekt gerade offen?
class Sperre {
  Sperre({required this.rechner, required this.benutzer, required this.seit});
  final String rechner;
  final String benutzer;
  final String seit;

  bool get istDieserRechner => rechner == Platform.localHostname;

  Map<String, dynamic> toJson() => {'rechner': rechner, 'benutzer': benutzer, 'seit': seit};

  static Sperre? lesen(String ordner) {
    final f = File(p.join(ordner, sperrDatei));
    if (!f.existsSync()) return null;
    try {
      final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return Sperre(
        rechner: m['rechner'] as String? ?? '?',
        benutzer: m['benutzer'] as String? ?? '?',
        seit: m['seit'] as String? ?? '?',
      );
    } catch (_) {
      return Sperre(rechner: '?', benutzer: '?', seit: '?');
    }
  }
}

String aktuellerBenutzer() =>
    Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? 'unbekannt';

/// Zugriff auf einen Projektordner und seine Datenbank.
/// Alle Längen in ganzen Millimetern.
class ProjectStore {
  ProjectStore._(this.ordner, this.db);

  final String ordner;
  final Database db;
  final String benutzer = aktuellerBenutzer();

  String get name =>
      db.select('SELECT name FROM projekt LIMIT 1').firstOrNull?['name'] as String? ??
      p.basename(ordner);

  // ---------------------------------------------------------------- Öffnen

  static bool istProjektordner(String ordner) =>
      File(p.join(ordner, datenbankDatei)).existsSync();

  /// Legt einen neuen Projektordner an und befüllt die Startdaten.
  static ProjectStore anlegen({required String elternOrdner, required String projektName}) {
    final ordnerName = projektName.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final ordner = p.join(elternOrdner, ordnerName);
    if (istProjektordner(ordner)) {
      throw StateError('In „$ordner“ gibt es schon ein Projekt.');
    }
    for (final u in projektUnterordner) {
      Directory(p.join(ordner, u)).createSync(recursive: true);
    }
    final db = sqlite3.open(p.join(ordner, datenbankDatei));
    final store = ProjectStore._(ordner, db);
    store._migrieren();
    store._startdaten(projektName.trim());
    store._sperreSetzen();
    return store;
  }

  /// Öffnet ein bestehendes Projekt. Legt vorher eine Sicherung an.
  static ProjectStore oeffnen(String ordner) {
    if (!istProjektordner(ordner)) {
      throw StateError('„$ordner“ ist kein BauSpur-Projektordner.');
    }
    for (final u in projektUnterordner) {
      Directory(p.join(ordner, u)).createSync(recursive: true);
    }
    _sicherungAnlegen(ordner);
    final db = sqlite3.open(p.join(ordner, datenbankDatei));
    final store = ProjectStore._(ordner, db);
    store._migrieren();
    store._sperreSetzen();
    // bestehende Wände einmal richtig herum legen (nur falsch liegende)
    try {
      for (final geb in store.gebaeude()) {
        for (final g in store.geschosse(geb.id)) {
          store.waendeAnAnschluessenTeilen(g.id);
          store._waendeAusrichten(g.id, store.flaechenErkennen(g.id));
        }
      }
    } catch (_) {}
    return store;
  }

  void schliessen() {
    final f = File(p.join(ordner, sperrDatei));
    final s = Sperre.lesen(ordner);
    if (f.existsSync() && (s == null || s.istDieserRechner)) {
      f.deleteSync();
    }
    db.close();
  }

  // ------------------------------------------------------------- Intern

  void _migrieren() {
    db.execute('PRAGMA foreign_keys = ON');
    var version = db.userVersion;
    while (version < migrationen.length) {
      db.execute('BEGIN');
      try {
        for (final sql in migrationen[version]) {
          // Spalten, die es (z. B. nach einer zurückgesetzten Version) schon gibt, überspringen
          final spalte = RegExp(r'^ALTER TABLE (\w+) ADD COLUMN (\w+)').firstMatch(sql);
          if (spalte != null && db.select('PRAGMA table_info(${spalte.group(1)})').any((r) => r['name'] == spalte.group(2))) continue;
          db.execute(sql);
        }
        // Startbestand, der mit einer Migration neu dazukommt – auch für
        // bestehende Projekte, in derselben Transaktion.
        if (version == 1) _bibliothekStarten();
        if (version == 9) _objekttypErgaenzen('FH', 'HR', 'Heizrohr / Anbindeleitung', 'linie');
        if (version == 10) _objekttypErgaenzen('AL', 'WD', 'Wanddurchbruch / Kernbohrung', 'punkt');
        if (version == 12) _objekttypErgaenzen('EL', 'LB', 'LED-Streifen / Lichtband', 'linie');
        if (version == 16) {
          _objekttypErgaenzen('SA', 'VB', 'Verbindungselement (Fitting, Halter …)', 'punkt');
          _objekttypErgaenzen('HZ', 'VH', 'Verbindungselement Heizung (Fitting, Halter …)', 'punkt');
          _objekttypErgaenzen('SA', 'AV', 'Armatur / Absperrventil', 'punkt');
        }
        if (version == 17) _gewerkErgaenzen('BS');
        if (version == 18) {
          _objekttypErgaenzen('AL', 'TR', 'Treppe (Lauflinie)', 'linie');
          _objekttypErgaenzen('AL', 'TP', 'Treppenpodest / Zwischenpodest', 'flaeche');
          _objekttypErgaenzen('AL', 'KM', 'Kamin / Schornstein', 'flaeche');
          _objekttypErgaenzen('SA', 'SR', 'Steigleitung / Fallrohr (über Geschosse)', 'punkt');
          _objekttypErgaenzen('HZ', 'SR', 'Steigleitung Heizung (über Geschosse)', 'punkt');
          _objekttypErgaenzen('EL', 'SR', 'Steigleitung Elektro (über Geschosse)', 'punkt');
        }
        version++;
        db.userVersion = version;
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
    // neue Baustoffe aus dem Startbestand in bestehenden Projekten ergänzen (WDVS-Kleber …)
    if (db.select("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'material'").isNotEmpty) {
      for (final (name, kategorie, farbe, einheit) in materialVorlagen) {
        if (!name.contains('WDVS')) continue;
        if (db.select('SELECT 1 FROM material WHERE name = ?', [name]).isEmpty) {
          db.execute('INSERT INTO material (id, name, kategorie, farbe, einheit, reihenfolge) VALUES (?, ?, ?, ?, ?, 99)',
              [neueId(), name, kategorie, farbe, einheit]);
        }
      }
    }
  }

  /// Neues Gewerk aus dem Startbestand in bestehenden Projekten ergänzen
  /// (samt Objekttypen; fehlende Typen werden nachgetragen).
  void _gewerkErgaenzen(String kuerzel) {
    final v = gewerkVorlagen.where((g) => g.kuerzel == kuerzel).firstOrNull;
    // neues Projekt: Gewerke kommen gleich aus dem Startbestand
    if (v == null || db.select('SELECT 1 FROM gewerk LIMIT 1').isEmpty) return;
    if (db.select('SELECT 1 FROM gewerk WHERE kuerzel = ?', [kuerzel]).isEmpty) {
      final n = (db.select('SELECT COUNT(*) AS n FROM gewerk').first['n'] as int?) ?? 0;
      db.execute('INSERT INTO gewerk (id, name, kuerzel, farbe, linie, reihenfolge, sichtbar) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [neueId(), v.name, v.kuerzel, v.farbe, v.linie, n, v.sichtbar ? 1 : 0]);
    }
    for (final t in v.typen) {
      _objekttypErgaenzen(kuerzel, t.$1, t.$2, t.$3);
    }
  }

  /// Neuen Objekttyp aus dem Startbestand in bestehenden Projekten ergänzen
  /// (nur wenn das Gewerk existiert und der Typ noch fehlt).
  void _objekttypErgaenzen(String gewerk, String kuerzel, String name, String geometrie) {
    for (final r in db.select('SELECT id FROM gewerk WHERE kuerzel = ?', [gewerk])) {
      final gid = r['id'] as String;
      final da = db.select('SELECT 1 FROM objekttyp WHERE gewerk_id = ? AND kuerzel = ?', [gid, kuerzel]).isNotEmpty;
      if (!da) {
        db.execute('INSERT INTO objekttyp (id, gewerk_id, name, kuerzel, geometrie) VALUES (?, ?, ?, ?, ?)',
            [neueId(), gid, name, kuerzel, geometrie]);
      }
    }
  }

  /// Materialien und Wandtypen aus den Vorlagen anlegen (ohne eigene Transaktion).
  void _bibliothekStarten() {
    final ids = <String, String>{};
    var i = 0;
    for (final (name, kategorie, farbe, einheit) in materialVorlagen) {
      final id = neueId();
      ids[name] = id;
      db.execute(
        'INSERT INTO material (id, name, kategorie, farbe, einheit, reihenfolge) VALUES (?, ?, ?, ?, ?, ?)',
        [id, name, kategorie, farbe, einheit, i++],
      );
    }
    i = 0;
    for (final (name, schichten) in wandtypVorlagen) {
      final id = neueId();
      db.execute('INSERT INTO wandtyp (id, name, reihenfolge) VALUES (?, ?, ?)', [id, name, i++]);
      var k = 0;
      for (final (material, dicke) in schichten) {
        db.execute(
          'INSERT INTO wandtyp_schicht (id, wandtyp_id, reihenfolge, material_id, dicke_mm) VALUES (?, ?, ?, ?, ?)',
          [neueId(), id, k++, ids[material]!, dicke],
        );
      }
    }
  }

  void _startdaten(String projektName) {
    db.execute('BEGIN');
    db.execute(
      'INSERT INTO projekt (id, name, erstellt) VALUES (?, ?, ?)',
      [neueId(), projektName, jetzt()],
    );
    final gebaeudeId = neueId();
    db.execute('INSERT INTO gebaeude (id, name, reihenfolge) VALUES (?, ?, 0)',
        [gebaeudeId, 'Haupthaus']);
    db.execute(
      'INSERT INTO geschoss (id, gebaeude_id, name, kuerzel, reihenfolge, rfb_mm, ffb_mm, rohdecke_mm, meterriss_mm) '
      'VALUES (?, ?, ?, ?, 0, 0, 0, 2600, 1000)',
      [neueId(), gebaeudeId, 'Erdgeschoss', 'EG'],
    );
    var i = 0;
    for (final g in gewerkVorlagen) {
      final gid = neueId();
      db.execute(
        'INSERT INTO gewerk (id, name, kuerzel, farbe, linie, reihenfolge, sichtbar) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [gid, g.name, g.kuerzel, g.farbe, g.linie, i++, g.sichtbar ? 1 : 0],
      );
      for (final t in g.typen) {
        db.execute(
          'INSERT INTO objekttyp (id, gewerk_id, name, kuerzel, geometrie) VALUES (?, ?, ?, ?, ?)',
          [neueId(), gid, t.$2, t.$1, t.$3],
        );
      }
    }
    db.execute('COMMIT');
  }

  void _sperreSetzen() {
    final s = Sperre(rechner: Platform.localHostname, benutzer: benutzer, seit: jetzt());
    File(p.join(ordner, sperrDatei)).writeAsStringSync(jsonEncode(s.toJson()));
  }

  /// Kopiert die Datenbank nach backup/ und behält die letzten 20 Stände.
  static void _sicherungAnlegen(String ordner) {
    final quelle = File(p.join(ordner, datenbankDatei));
    final backup = Directory(p.join(ordner, 'backup'))..createSync(recursive: true);
    final stempel = DateTime.now().toIso8601String().replaceAll(':', '').split('.').first;
    quelle.copySync(p.join(backup.path, 'projekt_$stempel.bauspur'));
    final staende = backup
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('projekt_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    while (staende.length > 20) {
      staende.removeAt(0).deleteSync();
    }
  }

  /// Änderungsverlauf eines Datensatzes (neueste zuerst).
  List<({String zeit, String aktion, String daten})> verlauf(String tabelle, String id, {int grenze = 100}) => [
        for (final r in db.select('SELECT zeit, aktion, daten FROM aenderung WHERE tabelle = ? AND datensatz = ? ORDER BY zeit DESC LIMIT ?', [tabelle, id, grenze]))
          (zeit: r['zeit'] as String? ?? '', aktion: r['aktion'] as String? ?? '', daten: r['daten']?.toString() ?? ''),
      ];

  void _protokoll(String tabelle, String id, String aktion, [Map<String, Object?>? daten]) {
    db.execute(
      'INSERT INTO aenderung (zeit, benutzer, tabelle, datensatz, aktion, daten) VALUES (?, ?, ?, ?, ?, ?)',
      [jetzt(), benutzer, tabelle, id, aktion, daten == null ? null : jsonEncode(daten)],
    );
  }

  // ---------------------------------------------------- Gebäude & Geschosse

  List<Gebaeude> gebaeude() => db
      .select('SELECT * FROM gebaeude WHERE geloescht IS NULL ORDER BY reihenfolge, name')
      .map(Gebaeude.ausZeile)
      .toList();

  List<Geschoss> geschosse(String gebaeudeId) => db
      .select(
        'SELECT * FROM geschoss WHERE gebaeude_id = ? AND geloescht IS NULL ORDER BY reihenfolge',
        [gebaeudeId],
      )
      .map(Geschoss.ausZeile)
      .toList();

  Geschoss? geschoss(String id) {
    final r = db.select('SELECT * FROM geschoss WHERE id = ?', [id]);
    return r.isEmpty ? null : Geschoss.ausZeile(r.first);
  }

  String gebaeudeAnlegen(String name) {
    final id = neueId();
    final n = (db.select('SELECT COUNT(*) AS n FROM gebaeude').first['n'] as int);
    db.execute('INSERT INTO gebaeude (id, name, reihenfolge) VALUES (?, ?, ?)', [id, name, n]);
    _protokoll('gebaeude', id, 'anlegen', {'name': name});
    return id;
  }

  String geschossAnlegen({
    required String gebaeudeId,
    required String name,
    required String kuerzel,
    required int rfb,
    required int ffb,
    required int rohdecke,
    required int meterriss,
  }) {
    final id = neueId();
    final n = (db.select('SELECT COUNT(*) AS n FROM geschoss WHERE gebaeude_id = ?', [gebaeudeId])
        .first['n'] as int);
    db.execute(
      'INSERT INTO geschoss (id, gebaeude_id, name, kuerzel, reihenfolge, rfb_mm, ffb_mm, rohdecke_mm, meterriss_mm) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, gebaeudeId, name, kuerzel.toUpperCase(), n, rfb, ffb, rohdecke, meterriss],
    );
    _protokoll('geschoss', id, 'anlegen', {'name': name, 'kuerzel': kuerzel});
    return id;
  }

  // ------------------------------------------------------------- Räume

  List<Raum> raeume(String geschossId) => db
      .select(
        'SELECT * FROM raum WHERE geschoss_id = ? AND geloescht IS NULL ORDER BY name',
        [geschossId],
      )
      .map(Raum.ausZeile)
      .toList();

  String raumAnlegen({
    required String geschossId,
    required String name,
    required String kuerzel,
    int? ffb,
    int? rohdecke,
    int? ukDecke,
    ErkannterRaum? flaeche,
  }) {
    final id = neueId();
    final bezug = flaeche?.innenpunkt;
    db.execute(
      'INSERT INTO raum (id, geschoss_id, name, kuerzel, ffb_mm, rohdecke_mm, uk_decke_mm, umriss, bezug_x, bezug_y) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id, geschossId, name, kuerzel.toUpperCase(), ffb, rohdecke, ukDecke,
        flaeche == null ? null : Raum.umrissText(flaeche.licht),
        bezug?.x.round(), bezug?.y.round(),
      ],
    );
    _protokoll('raum', id, 'anlegen', {'name': name, 'kuerzel': kuerzel});
    return id;
  }


  /// Bodenplatte ohne Wände (Balkon, Terrasse …) mit fest gezeichnetem Umriss.
  String bodenplatteAnlegen({
    required String geschossId,
    required String name,
    required String kuerzel,
    required RaumArt art,
    required List<Punkt> umriss,
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO raum (id, geschoss_id, name, kuerzel, umriss, art) VALUES (?, ?, ?, ?, ?, ?)',
      [id, geschossId, name, kuerzel.toUpperCase(), Raum.umrissText(umriss), art.name],
    );
    _protokoll('raum', id, 'anlegen', {'name': name, 'kuerzel': kuerzel, 'art': art.name});
    return id;
  }

  /// Raumart ändern.
  void raumArtSetzen(String id, RaumArt art) {
    db.execute('UPDATE raum SET art = ? WHERE id = ?', [art.name, id]);
    _protokoll('raum', id, 'art', {'art': art.name});
  }
  void raumAendern(String id, {String? name, String? kuerzel}) {
    if (name != null) db.execute('UPDATE raum SET name = ? WHERE id = ?', [name, id]);
    if (kuerzel != null) {
      db.execute('UPDATE raum SET kuerzel = ? WHERE id = ?', [kuerzel.toUpperCase(), id]);
    }
    _protokoll('raum', id, 'aendern', {'name': name, 'kuerzel': kuerzel});
  }

  /// Verortet einen (bisher freien) Raum auf einer erkannten Fläche.
  void raumVerorten(String id, ErkannterRaum flaeche) {
    final b = flaeche.innenpunkt;
    db.execute(
      'UPDATE raum SET umriss = ?, bezug_x = ?, bezug_y = ? WHERE id = ?',
      [Raum.umrissText(flaeche.licht), b.x.round(), b.y.round(), id],
    );
    _protokoll('raum', id, 'verorten', {'x': b.x.round(), 'y': b.y.round()});
  }

  /// Eigene Höhen eines Raums setzen (null lässt den Wert unverändert, *Leeren setzt auf Geschoss zurück).
  /// Zusatzdaten eines Raums setzen (vollständige Map); gibt die alte zurück.
  Map<String, dynamic> raumEigenschaftenSetzen(String id, Map<String, dynamic> eig) {
    final r = db.select('SELECT eigenschaften FROM raum WHERE id = ?', [id]).firstOrNull;
    final alt = r == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(r['eigenschaften'] as String? ?? '{}') as Map);
    db.execute('UPDATE raum SET eigenschaften = ? WHERE id = ?', [jsonEncode(eig), id]);
    _protokoll('raum', id, 'aendern', {'eigenschaften': eig});
    return alt;
  }

  /// Bauphysikalische Daten eines Baustoffs setzen; gibt die alten zurück.
  Map<String, dynamic> materialEigenschaftenSetzen(String id, Map<String, dynamic> eig) {
    final r = db.select('SELECT eigenschaften FROM material WHERE id = ?', [id]).firstOrNull;
    final alt = r == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(r['eigenschaften'] as String? ?? '{}') as Map);
    db.execute('UPDATE material SET eigenschaften = ? WHERE id = ?', [jsonEncode(eig), id]);
    _protokoll('material', id, 'aendern', {'eigenschaften': eig});
    return alt;
  }

  void raumHoehenSetzen(String id, {int? ukDecke, bool ukDeckeLeeren = false}) {
    if (ukDeckeLeeren) {
      db.execute('UPDATE raum SET uk_decke_mm = NULL WHERE id = ?', [id]);
    } else if (ukDecke != null) {
      db.execute('UPDATE raum SET uk_decke_mm = ? WHERE id = ?', [ukDecke, id]);
    }
    _protokoll('raum', id, 'hoehen', {'uk_decke': ukDeckeLeeren ? null : ukDecke});
  }

  void raumLoeschen(String id) {
    db.execute('UPDATE raum SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('raum', id, 'loeschen');
  }

  void raumWiederherstellen(String id) {
    db.execute('UPDATE raum SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('raum', id, 'wiederherstellen');
  }

  /// Erkennt alle geschlossenen Wandzüge im Geschoss. Abbruchwände zählen
  /// nicht mit – die Räume zeigen den Zustand nach dem Umbau.
  List<ErkannterRaum> flaechenErkennen(String geschossId) => erkenneAusWaenden(waende(geschossId));

  static List<ErkannterRaum> erkenneAusWaenden(List<Wand> waende) => raeumeErkennen(
      [for (final w in waende) if (w.zustand != WandZustand.abbruch) w.achse]);

  /// Führt die Umrisse aller verorteten Räume nach Wandänderungen nach.
  /// Ein Raum findet seine Fläche über seinen Bezugspunkt wieder; ist der
  /// Wandzug offen, bleibt der letzte Umriss stehen.
  void _raeumeAbgleichen(String geschossId) {
    final flaechen = flaechenErkennen(geschossId);
    for (final r in raeume(geschossId)) {
      final b = r.bezug;
      if (b == null) continue;
      final f = flaechen.where((f) => f.enthaelt(b)).firstOrNull;
      if (f == null) continue;
      final neu = Raum.umrissText(f.licht);
      final alt = r.umriss == null ? null : Raum.umrissText(r.umriss!);
      if (neu == alt) continue;
      db.execute('UPDATE raum SET umriss = ? WHERE id = ?', [neu, r.id]);
      _protokoll('raum', r.id, 'umriss', {'flaeche_mm2': f.flaeche.round(), 'umfang_mm': f.umfang.round()});
    }
    _waendeAusrichten(geschossId, flaechen);
  }

  /// Wandaufbau automatisch richtig herum: die erste Schicht (innen, „Seite 1“)
  /// liegt links der Zeichenrichtung. Liegt links keine Raumfläche, rechts aber
  /// schon, wird die Wand umgedreht. Von Hand gedrehte Wände bleiben, wie sie sind.
  void _waendeAusrichten(String geschossId, List<ErkannterRaum> flaechen) {
    if (flaechen.isEmpty) return;
    final manuell = {for (final x in (einstellung<List>('wand_manuell') ?? const [])) '$x'};
    for (final w in waende(geschossId)) {
      if (w.wandtypId == null || manuell.contains(w.id)) continue;
      final dx = (w.x2 - w.x1).toDouble(), dy = (w.y2 - w.y1).toDouble();
      final l = math.sqrt(dx * dx + dy * dy);
      if (l < 1) continue;
      final nx = dy / l, ny = -dx / l; // links der Zeichenrichtung (wie wandUmriss)
      final mx = (w.x1 + w.x2) / 2, my = (w.y1 + w.y2) / 2, o = w.dicke / 2 + 150;
      bool drin(double x, double y) => flaechen.any((f) => punktInPolygon(Punkt(x, y), f.licht));
      final links = drin(mx + nx * o, my + ny * o), rechts = drin(mx - nx * o, my - ny * o);
      if (!links && rechts) {
        _wandRichtungTauschen(w.id);
        _protokoll('wand', w.id, 'ausrichten');
      }
    }
  }

  /// Zeichenrichtung einer Wand umkehren; Öffnungen bleiben an ihrem Ort
  /// (Abstand ab dem neuen Anfang, Anschlag und Aufgehrichtung gespiegelt).
  void _wandRichtungTauschen(String id) {
    final r = db.select('SELECT x1, y1, x2, y2 FROM wand WHERE id = ?', [id]).firstOrNull;
    if (r == null) return;
    final dx = (r['x2'] as int) - (r['x1'] as int), dy = (r['y2'] as int) - (r['y1'] as int);
    final l = math.sqrt(dx * dx + dy * dy).round();
    db.execute('UPDATE wand SET x1 = x2, y1 = y2, x2 = x1, y2 = y1 WHERE id = ?', [id]);
    db.execute(
        'UPDATE oeffnung SET abstand_mm = ? - abstand_mm - breite_mm, band_rechts = 1 - band_rechts, aufgehen_links = 1 - aufgehen_links WHERE wand_id = ?',
        [l, id]);
  }

  String? _geschossDerWand(String wandId) =>
      db.select('SELECT geschoss_id FROM wand WHERE id = ?', [wandId]).firstOrNull?['geschoss_id'] as String?;

  void _nachWandAenderung(String wandId) {
    final g = _geschossDerWand(wandId);
    if (g != null) _raeumeAbgleichen(g);
  }

  // ------------------------------------------------------------- Wände

  List<Wand> waende(String geschossId) => db
      .select('SELECT * FROM wand WHERE geschoss_id = ? AND geloescht IS NULL', [geschossId])
      .map(Wand.ausZeile)
      .toList();

  /// Durchgehende Wände an Anschlusspunkten teilen: Endet eine andere Wand
  /// auf der Achse einer Wand (T-Stoß), wird diese dort geteilt – so hat jeder
  /// Raum seine eigenen Wandstücke und Innenmaße. Doppelt gezeichnete Wände
  /// (z. B. beim angrenzenden Rechteckraum) werden danach entfernt, die
  /// ältere bleibt; Öffnungen wandern mit. Liefert die Zahl der Änderungen.
  int waendeAnAnschluessenTeilen(String geschossId) {
    var n = 0;
    for (var runde = 0; runde < 200; runde++) {
      final alle = waende(geschossId);
      var geteilt = false;
      for (final w in alle) {
        final l = w.laenge;
        if (l < 100) continue;
        final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
        final schnitte = <int>{};
        for (final o in alle) {
          if (o.id == w.id) continue;
          for (final (px, py) in [(o.x1, o.y1), (o.x2, o.y2)]) {
            final t = (px - w.x1) * ux + (py - w.y1) * uy;
            final quer = ((px - w.x1) * uy - (py - w.y1) * ux).abs();
            if (quer <= 1.5 && t > 20 && t < l - 20) schnitte.add(t.round());
          }
        }
        if (schnitte.isEmpty) continue;
        final ts = [0, ...(schnitte.toList()..sort()), l.round()];
        final zeile = db.select('SELECT * FROM wand WHERE id = ?', [w.id]).first;
        final oeff = oeffnungen(geschossId).where((o) => o.wandId == w.id).toList();
        for (var i = 0; i + 1 < ts.length; i++) {
          final x1 = (w.x1 + ux * ts[i]).round(), y1 = (w.y1 + uy * ts[i]).round();
          final x2 = (w.x1 + ux * ts[i + 1]).round(), y2 = (w.y1 + uy * ts[i + 1]).round();
          String id;
          if (i == 0) {
            id = w.id;
            db.execute('UPDATE wand SET x2 = ?, y2 = ? WHERE id = ?', [x2, y2, id]);
          } else {
            id = neueId();
            final spalten = [for (final k in zeile.keys) if (!const {'id', 'x1', 'y1', 'x2', 'y2'}.contains(k)) k];
            db.execute(
              'INSERT INTO wand (id, x1, y1, x2, y2, ${spalten.join(', ')}) VALUES (?, ?, ?, ?, ?, ${spalten.map((_) => '?').join(', ')})',
              [id, x1, y1, x2, y2, for (final k in spalten) zeile[k]],
            );
          }
          for (final o in oeff) {
            if (o.abstand >= ts[i] - 1 && (o.abstand < ts[i + 1] || i == ts.length - 2)) {
              db.execute('UPDATE oeffnung SET wand_id = ?, abstand_mm = ? WHERE id = ?', [id, o.abstand - ts[i], o.id]);
            }
          }
        }
        _protokoll('wand', w.id, 'teilen', {'stuecke': ts.length - 1});
        n++;
        geteilt = true;
        break;
      }
      if (!geteilt) break;
    }
    // doppelte Wände (gleiche Endpunkte) entfernen, die ältere bleibt
    final alle = waende(geschossId)..sort((a, b) => a.id.compareTo(b.id));
    final weg = <String>{};
    for (var i = 0; i < alle.length; i++) {
      final a = alle[i];
      if (weg.contains(a.id)) continue;
      for (var j = i + 1; j < alle.length; j++) {
        final b = alle[j];
        if (weg.contains(b.id)) continue;
        bool gleich(int ax, int ay, int bx, int by) => (ax - bx).abs() <= 2 && (ay - by).abs() <= 2;
        final vorwaerts = gleich(a.x1, a.y1, b.x1, b.y1) && gleich(a.x2, a.y2, b.x2, b.y2);
        final rueckwaerts = gleich(a.x1, a.y1, b.x2, b.y2) && gleich(a.x2, a.y2, b.x1, b.y1);
        if (!vorwaerts && !rueckwaerts) continue;
        final l = b.laenge.round();
        for (final o in oeffnungen(geschossId).where((o) => o.wandId == b.id)) {
          db.execute('UPDATE oeffnung SET wand_id = ?, abstand_mm = ? WHERE id = ?', [a.id, rueckwaerts ? l - o.abstand - o.breite : o.abstand, o.id]);
        }
        db.execute('UPDATE wand SET geloescht = ? WHERE id = ?', [jetzt(), b.id]);
        _protokoll('wand', b.id, 'doppelt_entfernt', {'bleibt': a.id});
        weg.add(b.id);
        n++;
      }
    }
    if (n > 0) _raeumeAbgleichen(geschossId);
    return n;
  }

  String wandAnlegen({
    required String geschossId,
    required int x1,
    required int y1,
    required int x2,
    required int y2,
    required int dicke,
    WandZustand zustand = WandZustand.bestand,
    String? wandtypId,
    bool? verbinden,
  }) {
    final id = neueId();
    if (wandtypId != null) dicke = wandtyp(wandtypId)?.dicke ?? dicke;
    db.execute(
      'INSERT INTO wand (id, geschoss_id, x1, y1, x2, y2, dicke_mm, zustand, wandtyp_id, verbinden) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, geschossId, x1, y1, x2, y2, dicke, zustand.name, wandtypId, verbinden == null ? null : (verbinden ? 1 : 0)],
    );
    _protokoll('wand', id, 'anlegen',
        {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'dicke': dicke, 'wandtyp': wandtypId});
    _raeumeAbgleichen(geschossId);
    return id;
  }

  void wandAendern(String id, {int? dicke, WandZustand? zustand}) {
    if (dicke != null) {
      // Eine freie Dicke löst die Wand vom Wandtyp.
      db.execute('UPDATE wand SET dicke_mm = ?, wandtyp_id = NULL WHERE id = ?', [dicke, id]);
    }
    if (zustand != null) {
      db.execute('UPDATE wand SET zustand = ? WHERE id = ?', [zustand.name, id]);
    }
    _protokoll('wand', id, 'aendern', {'dicke': dicke, 'zustand': zustand?.name});
    _nachWandAenderung(id);
  }

  /// Weist einen Wandtyp zu; die Dicke folgt der Summe seiner Schichten.
  /// Ohne Typ (null) behält die Wand ihre Dicke.
  /// Nach einer Dickenänderung die Wand so versetzen, dass eine Seite fest
  /// bleibt (lichtes Innenmaß des Raums ändert sich nicht). [festSeite]: 1 =
  /// Seite links der Zeichenrichtung, −1 = rechts, 0 = Mitte (nichts tun).
  /// Anschließende Wände werden entlang ihrer eigenen Richtung bis zur neuen
  /// Achse verlängert bzw. gekürzt – Winkel bleiben, es wird nur skaliert.
  void wandDickeVersetzen(String id, int alteDicke, int neueDicke, int festSeite) {
    if (festSeite == 0 || alteDicke == neueDicke) return;
    final alle = waende(_geschossDerWand(id) ?? '');
    final w = alle.where((x) => x.id == id).firstOrNull;
    if (w == null || w.gesperrt || w.laenge < 1) return;
    final l = w.laenge;
    final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
    final nlx = uy, nly = -ux;
    final d = -festSeite * (neueDicke - alteDicke) / 2;
    final vx = nlx * d, vy = nly * d;
    // Schnitt der Geraden durch (px,py) Richtung (dx,dy) mit der neuen Wandachse
    (double, double)? schnitt(double px, double py, double dx, double dy) {
      final nenner = dx * uy - dy * ux;
      if (nenner.abs() < 1e-6) return null;
      final qx = w.x1 + vx - px, qy = w.y1 + vy - py;
      final t = (qx * uy - qy * ux) / nenner;
      return (px + dx * t, py + dy * t);
    }

    bool aufAlterAchse(int px, int py) {
      final t = (px - w.x1) * ux + (py - w.y1) * uy;
      final quer = ((px - w.x1) * uy - (py - w.y1) * ux).abs();
      return quer <= 2 && t >= -2 && t <= l + 2;
    }

    for (final o in alle) {
      if (o.id == w.id || o.gesperrt || o.laenge < 1) continue;
      final ol = o.laenge;
      final odx = (o.x2 - o.x1) / ol, ody = (o.y2 - o.y1) / ol;
      if ((odx * uy - ody * ux).abs() < 1e-3) continue; // parallel
      for (final ende in [1, 2]) {
        final px = ende == 1 ? o.x1 : o.x2, py = ende == 1 ? o.y1 : o.y2;
        if (!aufAlterAchse(px, py)) continue;
        final q = schnitt(px.toDouble(), py.toDouble(), odx, ody);
        if (q == null) continue;
        db.execute('UPDATE wand SET ${ende == 1 ? 'x1 = ?, y1 = ?' : 'x2 = ?, y2 = ?'} WHERE id = ?', [q.$1.round(), q.$2.round(), o.id]);
      }
    }
    db.execute('UPDATE wand SET x1 = ?, y1 = ?, x2 = ?, y2 = ? WHERE id = ?',
        [(w.x1 + vx).round(), (w.y1 + vy).round(), (w.x2 + vx).round(), (w.y2 + vy).round(), id]);
    _protokoll('wand', id, 'versetzen', {'fest': festSeite, 'dicke': neueDicke});
    _nachWandAenderung(id);
  }

  void wandWandtypSetzen(String id, String? wandtypId) {
    final typ = wandtypId == null ? null : wandtyp(wandtypId);
    if (typ == null) {
      db.execute('UPDATE wand SET wandtyp_id = NULL WHERE id = ?', [id]);
    } else {
      db.execute('UPDATE wand SET wandtyp_id = ?, dicke_mm = ? WHERE id = ?', [typ.id, typ.dicke, id]);
    }
    _protokoll('wand', id, 'wandtyp', {'wandtyp': typ?.id, 'dicke': typ?.dicke});
    _nachWandAenderung(id);
  }

  /// Ändert die Achslänge einer Wand. Der Anfang bleibt stehen (oder mit
  /// [amAnfang] das Ende). Wände, die am bewegten Ende anschließen, wandern
  /// als Ganzes mit, und deren Nachbarn werden gestreckt – so bleibt z. B.
  /// ein rechteckiger Raum rechteckig. Liefert die alten Koordinaten aller
  /// geänderten Wände (für Rückgängig mit [waendeKoordinatenSetzen]).
  Map<String, (int, int, int, int)> wandLaengeAendern(String id, int neueLaenge,
      {bool amAnfang = false, bool ausweichen = true}) {
    final r = db.select('SELECT * FROM wand WHERE id = ?', [id]).firstOrNull;
    if (r == null || neueLaenge <= 0) return const {};
    final w = Wand.ausZeile(r);
    final l = w.laenge;
    if (l < 1 || w.gesperrt) return const {};
    final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
    final diff = neueLaenge - l;
    // Verschiebung des bewegten Endes
    final dx = ((amAnfang ? -ux : ux) * diff).round();
    final dy = ((amAnfang ? -uy : uy) * diff).round();
    if (dx == 0 && dy == 0) return const {};
    final px = amAnfang ? w.x1 : w.x2, py = amAnfang ? w.y1 : w.y2;
    bool an(int x, int y, int qx, int qy) => (x - qx).abs() <= 1 && (y - qy).abs() <= 1;

    final alle = waende(w.geschossId);
    final neu = <String, (int, int, int, int)>{};
    (int, int, int, int) aktuell(Wand v) => neu[v.id] ?? (v.x1, v.y1, v.x2, v.y2);

    // 1. die Wand selbst
    neu[w.id] = amAnfang ? (w.x1 + dx, w.y1 + dy, w.x2, w.y2) : (w.x1, w.y1, w.x2 + dx, w.y2 + dy);
    // 2. Nachbarn am bewegten Ende: ganz verschieben
    final verschoben = <Wand>[];
    for (final v in alle) {
      if (v.id == w.id) continue;
      if (an(v.x1, v.y1, px, py) || an(v.x2, v.y2, px, py)) {
        if (v.gesperrt) {
          // Gesperrter Nachbar: stattdessen das andere Ende bewegen
          return ausweichen ? wandLaengeAendern(id, neueLaenge, amAnfang: !amAnfang, ausweichen: false) : const {};
        }
        neu[v.id] = (v.x1 + dx, v.y1 + dy, v.x2 + dx, v.y2 + dy);
        verschoben.add(v);
      }
    }
    // 3. deren andere Enden: dort anschließende Wände strecken
    for (final v in verschoben) {
      final fern = an(v.x1, v.y1, px, py) ? (v.x2, v.y2) : (v.x1, v.y1);
      for (final n in alle) {
        if (n.id == w.id || n.gesperrt || verschoben.any((e) => e.id == n.id)) continue;
        var (x1, y1, x2, y2) = aktuell(n);
        if (an(n.x1, n.y1, fern.$1, fern.$2)) {
          x1 += dx;
          y1 += dy;
        }
        if (an(n.x2, n.y2, fern.$1, fern.$2)) {
          x2 += dx;
          y2 += dy;
        }
        if ((x1, y1, x2, y2) != (n.x1, n.y1, n.x2, n.y2)) neu[n.id] = (x1, y1, x2, y2);
      }
    }
    final alt = {
      for (final v in alle)
        if (neu.containsKey(v.id)) v.id: (v.x1, v.y1, v.x2, v.y2)
    };
    _koordinatenSchreiben(w.geschossId, neu, 'laenge', {'wand': id, 'laenge': neueLaenge});
    return alt;
  }

  /// Ändert die Achslänge einer Wand, indem nur ihr Eckpunkt wandert: Der Punkt
  /// gleitet entlang der anschließenden Wand (deren Richtung bleibt), dadurch
  /// ändert sich der Winkel dieser Wand. Ohne Nachbarwand wird wie bei
  /// [wandLaengeAendern] in Wandrichtung verlängert. Liefert die alten Koordinaten.
  Map<String, (int, int, int, int)> wandEckeVerschieben(String id, int neueLaenge, {bool amAnfang = false}) {
    final r = db.select('SELECT * FROM wand WHERE id = ?', [id]).firstOrNull;
    if (r == null || neueLaenge <= 0) return const {};
    final w = Wand.ausZeile(r);
    if (w.gesperrt) return const {};
    final (px, py) = amAnfang ? (w.x1, w.y1) : (w.x2, w.y2);
    final (ax, ay) = amAnfang ? (w.x2, w.y2) : (w.x1, w.y1);
    bool an(int x, int y) => (x - px).abs() <= 1 && (y - py).abs() <= 1;
    final alle = waende(w.geschossId);
    final nachbarn = [for (final v in alle) if (v.id != w.id && (an(v.x1, v.y1) || an(v.x2, v.y2))) v];
    if (nachbarn.isEmpty) return wandLaengeAendern(id, neueLaenge, amAnfang: amAnfang);
    if (nachbarn.any((v) => v.gesperrt)) return const {};
    final n = nachbarn.first;
    final (fx, fy) = an(n.x1, n.y1) ? (n.x2, n.y2) : (n.x1, n.y1);
    final nl = math.sqrt(math.pow(fx - px, 2) + math.pow(fy - py, 2));
    if (nl < 1) return const {};
    final vx = (fx - px) / nl, vy = (fy - py) / nl;
    final dx = (px - ax).toDouble(), dy = (py - ay).toDouble();
    final vd = vx * dx + vy * dy;
    final disk = vd * vd - (dx * dx + dy * dy) + neueLaenge * neueLaenge;
    if (disk < 0) return const {};
    final t1 = -vd + math.sqrt(disk), t2 = -vd - math.sqrt(disk);
    final t = t1.abs() <= t2.abs() ? t1 : t2;
    final qx = (px + vx * t).round(), qy = (py + vy * t).round();
    if (qx == px && qy == py) return const {};
    final neu = <String, (int, int, int, int)>{
      w.id: amAnfang ? (qx, qy, w.x2, w.y2) : (w.x1, w.y1, qx, qy),
      for (final v in nachbarn)
        v.id: (
          an(v.x1, v.y1) ? qx : v.x1,
          an(v.x1, v.y1) ? qy : v.y1,
          an(v.x2, v.y2) ? qx : v.x2,
          an(v.x2, v.y2) ? qy : v.y2,
        ),
    };
    final alt = {
      for (final v in alle)
        if (neu.containsKey(v.id)) v.id: (v.x1, v.y1, v.x2, v.y2)
    };
    _koordinatenSchreiben(w.geschossId, neu, 'ecke', {'wand': id, 'laenge': neueLaenge});
    return alt;
  }

  /// Verschiebt einen Wandendpunkt auf (x, y); alle Wände, die dort anschließen,
  /// wandern mit diesem Ende mit (sie strecken oder drehen sich). Liefert die
  /// alten Koordinaten, leer wenn eine betroffene Wand gesperrt ist.
  Map<String, (int, int, int, int)> wandEndeVersetzen(String id, {required bool amAnfang, required int x, required int y}) {
    final r = db.select('SELECT * FROM wand WHERE id = ?', [id]).firstOrNull;
    if (r == null) return const {};
    final w = Wand.ausZeile(r);
    final (px, py) = amAnfang ? (w.x1, w.y1) : (w.x2, w.y2);
    if (px == x && py == y) return const {};
    return punktVersetzen(w.geschossId, px, py, x, y);
  }

  /// Verschiebt alle Wandenden, die auf (px, py) liegen, nach (x, y).
  Map<String, (int, int, int, int)> punktVersetzen(String geschossId, int px, int py, int x, int y) {
    bool an(int ax, int ay) => (ax - px).abs() <= 1 && (ay - py).abs() <= 1;
    final betroffen = [for (final v in waende(geschossId)) if (an(v.x1, v.y1) || an(v.x2, v.y2)) v];
    if (betroffen.isEmpty || betroffen.any((v) => v.gesperrt)) return const {};
    final neu = {
      for (final v in betroffen)
        v.id: (an(v.x1, v.y1) ? x : v.x1, an(v.x1, v.y1) ? y : v.y1, an(v.x2, v.y2) ? x : v.x2, an(v.x2, v.y2) ? y : v.y2),
    };
    final alt = {for (final v in betroffen) v.id: (v.x1, v.y1, v.x2, v.y2)};
    _koordinatenSchreiben(geschossId, neu, 'punkt', {'von': [px, py], 'nach': [x, y]});
    return alt;
  }

  /// Maßanzeige für Wände setzen (null = Voreinstellung des Grundrisses).
  void waendeMassanzeigeSetzen(List<String> ids, MassAnzeige? anzeige) {
    for (final id in ids) {
      db.execute('UPDATE wand SET massanzeige = ? WHERE id = ?', [anzeige?.name, id]);
      _protokoll('wand', id, 'massanzeige', {'massanzeige': anzeige?.name});
    }
  }

  /// Setzt Koordinaten mehrerer Wände (z. B. Rückgängig einer Längenänderung).
  void waendeKoordinatenSetzen(Map<String, (int, int, int, int)> koordinaten) {
    if (koordinaten.isEmpty) return;
    final g = _geschossDerWand(koordinaten.keys.first);
    if (g == null) return;
    _koordinatenSchreiben(g, koordinaten, 'koordinaten', null);
  }

  /// Bemaßungen, deren Endpunkte auf verschobenen Wandpunkten liegen, wandern mit.
  void _bemassungenNachziehen(String geschossId, Map<(int, int), (int, int)> punkte) {
    if (punkte.isEmpty) return;
    (int, int)? neu(int x, int y) {
      for (final e in punkte.entries) {
        if ((e.key.$1 - x).abs() <= 1 && (e.key.$2 - y).abs() <= 1) return e.value;
      }
      return null;
    }

    for (final b in bemassungen(geschossId)) {
      final a = neu(b.x1, b.y1), e = neu(b.x2, b.y2);
      if (a == null && e == null) continue;
      final (x1, y1) = a ?? (b.x1, b.y1);
      final (x2, y2) = e ?? (b.x2, b.y2);
      db.execute('UPDATE bemassung SET x1 = ?, y1 = ?, x2 = ?, y2 = ? WHERE id = ?', [x1, y1, x2, y2, b.id]);
    }
  }

  void _koordinatenSchreiben(
      String geschossId, Map<String, (int, int, int, int)> k, String aktion, Map<String, Object?>? info) {
    db.execute('BEGIN');
    try {
      final punkte = <(int, int), (int, int)>{};
      k.forEach((id, p) {
        final alt = db.select('SELECT x1, y1, x2, y2 FROM wand WHERE id = ?', [id]).firstOrNull;
        if (alt != null) {
          punkte[(alt['x1'] as int, alt['y1'] as int)] = (p.$1, p.$2);
          punkte[(alt['x2'] as int, alt['y2'] as int)] = (p.$3, p.$4);
        }
      });
      _bemassungenNachziehen(geschossId, punkte);
      k.forEach((id, p) {
        db.execute('UPDATE wand SET x1 = ?, y1 = ?, x2 = ?, y2 = ? WHERE id = ?', [p.$1, p.$2, p.$3, p.$4, id]);
        _protokoll('wand', id, aktion, {...?info, 'x1': p.$1, 'y1': p.$2, 'x2': p.$3, 'y2': p.$4});
      });
      _raeumeAbgleichen(geschossId);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Verschiebt mehrere Wände gemeinsam um (dx | dy) mm. Räume, deren
  /// Bezugspunkt danach in keiner Fläche mehr liegt, wandern mit, wenn sie
  /// an der verschobenen Stelle ihre Fläche wiederfinden.
  void waendeVerschieben(List<String> ids, int dx, int dy) {
    if (ids.isEmpty || (dx == 0 && dy == 0)) return;
    final geschosse = <String>{};
    final punkte = <(int, int), (int, int)>{};
    db.execute('BEGIN');
    try {
      for (final id in ids) {
        final alt = db.select('SELECT * FROM wand WHERE id = ?', [id]).firstOrNull;
        if (alt == null || (alt['gesperrt'] as int? ?? 0) == 1) continue; // gesperrte Wände bleiben
        db.execute('UPDATE wand SET x1 = x1 + ?, y1 = y1 + ?, x2 = x2 + ?, y2 = y2 + ? WHERE id = ?',
            [dx, dy, dx, dy, id]);
        final ax1 = alt['x1'] as int, ay1 = alt['y1'] as int, ax2 = alt['x2'] as int, ay2 = alt['y2'] as int;
        punkte[(ax1, ay1)] = (ax1 + dx, ay1 + dy);
        punkte[(ax2, ay2)] = (ax2 + dx, ay2 + dy);
        final g = _geschossDerWand(id);
        if (g != null) geschosse.add(g);
      }
      _protokoll('wand', ids.first, 'verschieben', {'waende': ids, 'dx': dx, 'dy': dy});
      for (final g in geschosse) {
        final flaechen = flaechenErkennen(g);
        for (final r in raeume(g)) {
          final b = r.bezug;
          if (b == null || flaechen.any((f) => f.enthaelt(b))) continue;
          final neu = Punkt(b.x + dx, b.y + dy);
          if (!flaechen.any((f) => f.enthaelt(neu))) continue;
          db.execute('UPDATE raum SET bezug_x = ?, bezug_y = ? WHERE id = ?', [neu.x.round(), neu.y.round(), r.id]);
          _protokoll('raum', r.id, 'verschieben', {'dx': dx, 'dy': dy});
        }
        _bemassungenNachziehen(g, punkte);
        _raeumeAbgleichen(g);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Dreht die Zeichenrichtung um – damit liegen die Schichten des
  /// Wandtyps spiegelverkehrt (z. B. Dämmung außen statt innen).
  void wandUmdrehen(String id) {
    _wandRichtungTauschen(id);
    _protokoll('wand', id, 'umdrehen');
    // von Hand gedreht: automatische Ausrichtung lässt sie in Ruhe
    final m = {for (final x in (einstellung<List>('wand_manuell') ?? const [])) '$x'};
    if (m.add(id)) einstellungSetzen('wand_manuell', m.toList());
  }

  void wandLoeschen(String id) {
    if ((db.select('SELECT gesperrt FROM wand WHERE id = ?', [id]).firstOrNull?['gesperrt'] as int? ?? 0) == 1) return;
    db.execute('UPDATE wand SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('wand', id, 'loeschen');
    _nachWandAenderung(id);
  }

  /// Letzte gelöschte Wand wiederherstellen (einfaches Rückgängig).
  bool wandWiederherstellen(String id) {
    db.execute('UPDATE wand SET geloescht = NULL WHERE id = ?', [id]);
    final ok = db.updatedRows > 0;
    _protokoll('wand', id, 'wiederherstellen');
    _nachWandAenderung(id);
    return ok;
  }

  // ------------------------------------------------- Materialien & Wandtypen

  List<Baustoff> materialien() => db
      .select('SELECT * FROM material WHERE geloescht IS NULL ORDER BY reihenfolge, name')
      .map(Baustoff.ausZeile)
      .toList();

  String materialAnlegen({
    required String name,
    required String kategorie,
    required int farbe,
    String einheit = 'm²',
  }) {
    final id = neueId();
    final n = db.select('SELECT COUNT(*) AS n FROM material').first['n'] as int;
    db.execute(
      'INSERT INTO material (id, name, kategorie, farbe, einheit, reihenfolge) VALUES (?, ?, ?, ?, ?, ?)',
      [id, name, kategorie, farbe, einheit, n],
    );
    _protokoll('material', id, 'anlegen', {'name': name, 'kategorie': kategorie});
    return id;
  }

  void materialAendern(String id, {String? name, String? kategorie, int? farbe, String? einheit}) {
    if (name != null) db.execute('UPDATE material SET name = ? WHERE id = ?', [name, id]);
    if (kategorie != null) db.execute('UPDATE material SET kategorie = ? WHERE id = ?', [kategorie, id]);
    if (farbe != null) db.execute('UPDATE material SET farbe = ? WHERE id = ?', [farbe, id]);
    if (einheit != null) db.execute('UPDATE material SET einheit = ? WHERE id = ?', [einheit, id]);
    _protokoll('material', id, 'aendern',
        {'name': name, 'kategorie': kategorie, 'farbe': farbe, 'einheit': einheit});
  }

  /// Wie viele aktive Wandtypen nutzen dieses Material?
  int materialVerwendung(String id) => db.select(
        'SELECT COUNT(DISTINCT s.wandtyp_id) AS n FROM wandtyp_schicht s JOIN wandtyp t ON t.id = s.wandtyp_id '
        'WHERE s.material_id = ? AND s.geloescht IS NULL AND t.geloescht IS NULL',
        [id],
      ).first['n'] as int;

  void materialLoeschen(String id) {
    db.execute('UPDATE material SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('material', id, 'loeschen');
  }

  List<Wandtyp> wandtypen() => db
      .select('SELECT * FROM wandtyp WHERE geloescht IS NULL ORDER BY reihenfolge, name')
      .map((r) => Wandtyp(id: r['id'] as String, name: r['name'] as String, schichten: _schichten(r['id'] as String)))
      .toList();

  Wandtyp? wandtyp(String id) {
    final r = db.select('SELECT * FROM wandtyp WHERE id = ?', [id]).firstOrNull;
    if (r == null) return null;
    return Wandtyp(id: id, name: r['name'] as String, schichten: _schichten(id));
  }

  List<Schicht> _schichten(String wandtypId) => db
      .select(
        'SELECT material_id, dicke_mm FROM wandtyp_schicht WHERE wandtyp_id = ? AND geloescht IS NULL ORDER BY reihenfolge',
        [wandtypId],
      )
      .map((r) => Schicht(r['material_id'] as String, r['dicke_mm'] as int))
      .toList();

  String wandtypAnlegen(String name, List<Schicht> schichten) {
    final id = neueId();
    final n = db.select('SELECT COUNT(*) AS n FROM wandtyp').first['n'] as int;
    db.execute('INSERT INTO wandtyp (id, name, reihenfolge) VALUES (?, ?, ?)', [id, name, n]);
    _protokoll('wandtyp', id, 'anlegen', {'name': name});
    _schichtenSchreiben(id, schichten);
    return id;
  }

  void wandtypUmbenennen(String id, String name) {
    db.execute('UPDATE wandtyp SET name = ? WHERE id = ?', [name, id]);
    _protokoll('wandtyp', id, 'aendern', {'name': name});
  }

  /// Ersetzt die Schichten eines Wandtyps. Alte Schichten werden weich
  /// gelöscht; alle Wände dieses Typs bekommen die neue Gesamtdicke, und
  /// die Räume der betroffenen Geschosse werden nachgeführt.
  void wandtypSchichtenSetzen(String id, List<Schicht> schichten) {
    db.execute('BEGIN');
    try {
      db.execute('UPDATE wandtyp_schicht SET geloescht = ? WHERE wandtyp_id = ? AND geloescht IS NULL', [jetzt(), id]);
      _schichtenSchreiben(id, schichten);
      final dicke = schichten.fold<int>(0, (s, e) => s + e.dicke);
      final geschosse = db
          .select('SELECT DISTINCT geschoss_id FROM wand WHERE wandtyp_id = ? AND geloescht IS NULL', [id])
          .map((r) => r['geschoss_id'] as String)
          .toList();
      db.execute('UPDATE wand SET dicke_mm = ? WHERE wandtyp_id = ? AND geloescht IS NULL', [dicke, id]);
      geschosse.forEach(_raeumeAbgleichen);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _schichtenSchreiben(String id, List<Schicht> schichten) {
    var k = 0;
    for (final s in schichten) {
      db.execute(
        'INSERT INTO wandtyp_schicht (id, wandtyp_id, reihenfolge, material_id, dicke_mm) VALUES (?, ?, ?, ?, ?)',
        [neueId(), id, k++, s.materialId, s.dicke],
      );
    }
    _protokoll('wandtyp', id, 'schichten', {
      'schichten': [for (final s in schichten) {'material': s.materialId, 'dicke': s.dicke}],
    });
  }

  /// Wie viele Wände (aktiv) nutzen diesen Typ?
  int wandtypVerwendung(String id) =>
      db.select('SELECT COUNT(*) AS n FROM wand WHERE wandtyp_id = ? AND geloescht IS NULL', [id]).first['n']
          as int;

  /// Weich löschen; Wände behalten Dicke und Verweis (gelten dann als frei).
  void wandtypLoeschen(String id) {
    db.execute('UPDATE wandtyp SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('wandtyp', id, 'loeschen');
  }

  // ---------------------------------------------- Projekteinstellungen

  Map<String, dynamic> get _einstellungen {
    final t = db.select('SELECT einstellungen FROM projekt LIMIT 1').firstOrNull?['einstellungen'] as String?;
    try {
      return t == null ? {} : (jsonDecode(t) as Map<String, dynamic>);
    } catch (_) {
      return {};
    }
  }

  /// Projekteinstellung lesen (gilt für alle Geräte und Nutzer).
  T? einstellung<T>(String schluessel) {
    final v = _einstellungen[schluessel];
    return v is T ? v : null;
  }

  void einstellungSetzen(String schluessel, Object? wert) {
    final m = _einstellungen..[schluessel] = wert;
    db.execute('UPDATE projekt SET einstellungen = ?', [jsonEncode(m)]);
    _protokoll('projekt', 'einstellungen', 'aendern', {schluessel: wert});
  }

  // ------------------------------------------- Sperren und Verbinden

  void waendeSperren(List<String> ids, bool gesperrt) {
    for (final id in ids) {
      db.execute('UPDATE wand SET gesperrt = ? WHERE id = ?', [gesperrt ? 1 : 0, id]);
      _protokoll('wand', id, gesperrt ? 'sperren' : 'entsperren');
    }
  }

  /// Ecken verbinden je Wand: null = Projektvorgabe.
  void waendeVerbindenSetzen(List<String> ids, bool? verbinden) {
    for (final id in ids) {
      db.execute('UPDATE wand SET verbinden = ? WHERE id = ?', [verbinden == null ? null : (verbinden ? 1 : 0), id]);
      _protokoll('wand', id, 'verbinden', {'verbinden': verbinden});
    }
  }

  // ------------------------------------- Bemaßung ändern → Geometrie

  /// Setzt das Maß einer Bemaßung. Bewegt wird der zweite Punkt (oder, wenn
  /// dort nichts verschoben werden darf, der erste): liegt dort das Ende
  /// oder die Ecke einer Wand in Maßrichtung, ändert sich deren Länge samt
  /// verbundener Wände; sonst wandern die Wandenden an diesem Punkt.
  /// Liefert eine Rückgängig-Aktion oder null, wenn nichts ging.
  void Function()? bemassungAendern(String id, int neuerWert) {
    final r = db.select('SELECT * FROM bemassung WHERE id = ?', [id]).firstOrNull;
    if (r == null || neuerWert <= 0) return null;
    final b = Bemassung.ausZeile(r);
    final l = b.laenge;
    if (l < 1) return null;
    final diff = neuerWert - l;
    final ux = (b.x2 - b.x1) / l, uy = (b.y2 - b.y1) / l;
    final alleWaende = waende(b.geschossId);
    final achsen = [for (final w in alleWaende) w.achse];

    void Function()? versuchen(int px, int py, double sx, double sy) {
      final dx = (sx * diff).round(), dy = (sy * diff).round();
      // Laibung einer Tür / eines Fensters am Punkt: Öffnung entlang ihrer Wand verschieben
      for (final o in oeffnungen(b.geschossId)) {
        final w = alleWaende.where((e) => e.id == o.wandId).firstOrNull;
        if (w == null || w.laenge < 1) continue;
        final wux = (w.x2 - w.x1) / w.laenge, wuy = (w.y2 - w.y1) / w.laenge;
        final entlang = (px - w.x1) * wux + (py - w.y1) * wuy;
        final quer = ((px - w.x1) * wuy - (py - w.y1) * wux).abs();
        if (quer > w.dicke / 2 + 1) continue;
        if ((entlang - o.abstand).abs() > 1 && (entlang - o.abstand - o.breite).abs() > 1) continue;
        final schub = (dx * wux + dy * wuy).round();
        if (schub == 0) continue; // Maß quer zur Wand: Öffnung bleibt
        final neu = o.abstand + schub;
        if (neu < 0 || neu + o.breite > w.laenge) return null;
        final alt = oeffnungAendern(o.id, {'abstand_mm': neu});
        _bemassungPunktSetzen(b, px, py, px + dx, py + dy);
        return () {
          oeffnungAendern(o.id, alt);
          db.execute('UPDATE bemassung SET x1 = ?, y1 = ?, x2 = ?, y2 = ? WHERE id = ?', [b.x1, b.y1, b.x2, b.y2, b.id]);
        };
      }
      for (var i = 0; i < alleWaende.length; i++) {
        final w = alleWaende[i];
        if (w.gesperrt) continue;
        final wl = w.laenge;
        if (wl < 1) continue;
        final parallel = (((w.x2 - w.x1) * uy - (w.y2 - w.y1) * ux) / wl).abs() < 0.01;
        if (!parallel) continue;
        // Endpunkt oder verschnittene Ecke dieser Wand am Punkt?
        final ecken = wandUmriss(achsen[i], achsen);
        final amA = (w.x1 - px).abs() <= 1 && (w.y1 - py).abs() <= 1 ||
            [ecken[0], ecken[3]].any((e) => (e.x - px).abs() <= 1 && (e.y - py).abs() <= 1);
        final amB = (w.x2 - px).abs() <= 1 && (w.y2 - py).abs() <= 1 ||
            [ecken[1], ecken[2]].any((e) => (e.x - px).abs() <= 1 && (e.y - py).abs() <= 1);
        if (!amA && !amB) continue;
        // Wird die Wand in Maßrichtung länger oder kürzer?
        final wux = (w.x2 - w.x1) / wl, wuy = (w.y2 - w.y1) / wl;
        final richtung = amB ? (wux * sx + wuy * sy) : -(wux * sx + wuy * sy);
        final alt = wandLaengeAendern(w.id, (wl + richtung * diff).round(), amAnfang: amA && !amB, ausweichen: false);
        if (alt.isEmpty) continue;
        _bemassungPunktSetzen(b, px, py, px + dx, py + dy);
        return () {
          waendeKoordinatenSetzen(alt);
          db.execute('UPDATE bemassung SET x1 = ?, y1 = ?, x2 = ?, y2 = ? WHERE id = ?', [b.x1, b.y1, b.x2, b.y2, b.id]);
        };
      }
      // Quer stehende Wand am Punkt (Achse, Seite oder Ecke): ganz verschieben,
      // anschließende Wände werden gestreckt – z. B. Raumbreite über das Innenmaß.
      for (final w in alleWaende) {
        if (w.gesperrt || w.laenge < 1) continue;
        final a = Punkt(w.x1.toDouble(), w.y1.toDouble()), e = Punkt(w.x2.toDouble(), w.y2.toDouble());
        final d = e - a;
        final t = ((Punkt(px.toDouble(), py.toDouble()) - a).skalar(d) / d.skalar(d)) * w.laenge;
        final quer = ((Punkt(px.toDouble(), py.toDouble()) - a).kreuz(d) / w.laenge).abs();
        if (quer > w.dicke / 2 + 1 || t < -w.dicke / 2 - 1 || t > w.laenge + w.dicke / 2 + 1) continue;
        final parallel = (((w.x2 - w.x1) * uy - (w.y2 - w.y1) * ux) / w.laenge).abs() < 0.01;
        if (parallel) continue;
        bool an(Wand v, int x, int y) => (v.x1 - x).abs() <= 1 && (v.y1 - y).abs() <= 1 || (v.x2 - x).abs() <= 1 && (v.y2 - y).abs() <= 1;
        final angeschlossen = [for (final v in alleWaende) if (v.id != w.id && (an(v, w.x1, w.y1) || an(v, w.x2, w.y2))) v];
        if (angeschlossen.any((v) => v.gesperrt)) continue;
        (int, int) bewegt(int x, int y) =>
            ((x - w.x1).abs() <= 1 && (y - w.y1).abs() <= 1) || ((x - w.x2).abs() <= 1 && (y - w.y2).abs() <= 1) ? (x + dx, y + dy) : (x, y);
        final neu = <String, (int, int, int, int)>{
          w.id: (w.x1 + dx, w.y1 + dy, w.x2 + dx, w.y2 + dy),
          for (final v in angeschlossen) v.id: (bewegt(v.x1, v.y1).$1, bewegt(v.x1, v.y1).$2, bewegt(v.x2, v.y2).$1, bewegt(v.x2, v.y2).$2),
        };
        final alt = {for (final v in [w, ...angeschlossen]) v.id: (v.x1, v.y1, v.x2, v.y2)};
        _koordinatenSchreiben(b.geschossId, neu, 'bemassung', {'bemassung': id});
        _bemassungPunktSetzen(b, px, py, px + dx, py + dy);
        return () {
          waendeKoordinatenSetzen(alt);
          db.execute('UPDATE bemassung SET x1 = ?, y1 = ?, x2 = ?, y2 = ? WHERE id = ?', [b.x1, b.y1, b.x2, b.y2, b.id]);
        };
      }
      // Wandenden genau am Punkt verschieben
      final betroffen = [
        for (final w in alleWaende)
          if ((w.x1 - px).abs() <= 1 && (w.y1 - py).abs() <= 1 || (w.x2 - px).abs() <= 1 && (w.y2 - py).abs() <= 1) w
      ];
      if (betroffen.any((w) => w.gesperrt)) return null;
      final neu = <String, (int, int, int, int)>{
        for (final w in betroffen)
          w.id: (
            (w.x1 - px).abs() <= 1 && (w.y1 - py).abs() <= 1 ? w.x1 + dx : w.x1,
            (w.x1 - px).abs() <= 1 && (w.y1 - py).abs() <= 1 ? w.y1 + dy : w.y1,
            (w.x2 - px).abs() <= 1 && (w.y2 - py).abs() <= 1 ? w.x2 + dx : w.x2,
            (w.x2 - px).abs() <= 1 && (w.y2 - py).abs() <= 1 ? w.y2 + dy : w.y2,
          )
      };
      final alt = {for (final w in betroffen) w.id: (w.x1, w.y1, w.x2, w.y2)};
      if (neu.isNotEmpty) _koordinatenSchreiben(b.geschossId, neu, 'bemassung', {'bemassung': id});
      _bemassungPunktSetzen(b, px, py, px + dx, py + dy);
      return () {
        if (alt.isNotEmpty) waendeKoordinatenSetzen(alt);
        db.execute('UPDATE bemassung SET x1 = ?, y1 = ?, x2 = ?, y2 = ? WHERE id = ?', [b.x1, b.y1, b.x2, b.y2, b.id]);
      };
    }

    final ergebnis = versuchen(b.x2, b.y2, ux, uy) ?? versuchen(b.x1, b.y1, -ux, -uy);
    if (ergebnis != null) _protokoll('bemassung', id, 'aendern', {'wert': neuerWert});
    return ergebnis;
  }

  void _bemassungPunktSetzen(Bemassung b, int px, int py, int nx, int ny) {
    final r = db.select('SELECT x1, y1, x2, y2 FROM bemassung WHERE id = ?', [b.id]).first;
    var (x1, y1, x2, y2) = (r['x1'] as int, r['y1'] as int, r['x2'] as int, r['y2'] as int);
    // ursprünglicher Punkt der Bemaßung (vor evtl. Nachziehen durch Wandänderungen)
    if ((b.x1 - px).abs() <= 1 && (b.y1 - py).abs() <= 1) {
      (x1, y1) = (nx, ny);
    } else {
      (x2, y2) = (nx, ny);
    }
    db.execute('UPDATE bemassung SET x1 = ?, y1 = ?, x2 = ?, y2 = ? WHERE id = ?', [x1, y1, x2, y2, b.id]);
  }

  // -------------------------------------------------------- Winkelmaße

  List<Winkelmass> winkelmasse(String geschossId) => db
      .select('SELECT * FROM winkelmass WHERE geschoss_id = ? AND geloescht IS NULL', [geschossId])
      .map(Winkelmass.ausZeile)
      .toList();

  String winkelmassAnlegen(String geschossId, String wand1, String wand2) {
    final id = neueId();
    db.execute('INSERT INTO winkelmass (id, geschoss_id, wand1_id, wand2_id, erstellt) VALUES (?, ?, ?, ?, ?)',
        [id, geschossId, wand1, wand2, jetzt()]);
    _protokoll('winkelmass', id, 'anlegen', {'wand1': wand1, 'wand2': wand2});
    return id;
  }

  void winkelmassLoeschen(String id) {
    db.execute('UPDATE winkelmass SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('winkelmass', id, 'loeschen');
  }

  void winkelmassWiederherstellen(String id) {
    db.execute('UPDATE winkelmass SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('winkelmass', id, 'wiederherstellen');
  }

  /// Gemeinsamer Punkt zweier Wände und die beiden fernen Enden.
  static ((int, int), (int, int), (int, int))? winkelGeometrie(Wand a, Wand b) {
    for (final (pa, fa) in [((a.x1, a.y1), (a.x2, a.y2)), ((a.x2, a.y2), (a.x1, a.y1))]) {
      for (final (pb, fb) in [((b.x1, b.y1), (b.x2, b.y2)), ((b.x2, b.y2), (b.x1, b.y1))]) {
        if ((pa.$1 - pb.$1).abs() <= 1 && (pa.$2 - pb.$2).abs() <= 1) return (pa, fa, fb);
      }
    }
    return null;
  }

  /// Stellt den Winkel zwischen den Wänden ein (0 … 180°): gedreht wird die
  /// zweite Wand um den gemeinsamen Punkt (oder die erste, wenn die zweite
  /// gesperrt ist); Wände am fernen Ende werden mitgezogen.
  void Function()? winkelAendern(String id, double grad) {
    final r = db.select('SELECT * FROM winkelmass WHERE id = ?', [id]).firstOrNull;
    if (r == null || grad <= 0 || grad >= 180) return null;
    final m = Winkelmass.ausZeile(r);
    final alle = waende(r['geschoss_id'] as String);
    final w1 = alle.where((w) => w.id == m.wand1Id).firstOrNull;
    final w2 = alle.where((w) => w.id == m.wand2Id).firstOrNull;
    if (w1 == null || w2 == null) return null;
    final dreh = !w2.gesperrt ? w2 : (!w1.gesperrt ? w1 : null);
    if (dreh == null) return null;
    final fest = identical(dreh, w2) ? w1 : w2;
    final g = winkelGeometrie(fest, dreh);
    if (g == null) return null;
    final (v, ff, fd) = g;
    final wf = math.atan2((ff.$2 - v.$2).toDouble(), (ff.$1 - v.$1).toDouble());
    final wd = math.atan2((fd.$2 - v.$2).toDouble(), (fd.$1 - v.$1).toDouble());
    var delta = wd - wf;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    final ziel = wf + (delta >= 0 ? 1 : -1) * grad * math.pi / 180;
    final laenge = dreh.laenge;
    final nx = (v.$1 + math.cos(ziel) * laenge).round(), ny = (v.$2 + math.sin(ziel) * laenge).round();
    bool an(int x, int y) => (x - fd.$1).abs() <= 1 && (y - fd.$2).abs() <= 1;
    // Wandenden am fernen Punkt (ohne gesperrte) ziehen mit
    final betroffen = [
      for (final w in alle)
        if (!w.gesperrt && (an(w.x1, w.y1) || an(w.x2, w.y2))) w
    ];
    final neu = {
      for (final w in betroffen)
        w.id: (
          an(w.x1, w.y1) ? nx : w.x1,
          an(w.x1, w.y1) ? ny : w.y1,
          an(w.x2, w.y2) ? nx : w.x2,
          an(w.x2, w.y2) ? ny : w.y2,
        )
    };
    final alt = {for (final w in betroffen) w.id: (w.x1, w.y1, w.x2, w.y2)};
    _koordinatenSchreiben(dreh.geschossId, neu, 'winkel', {'winkelmass': id, 'grad': grad});
    return () => waendeKoordinatenSetzen(alt);
  }

  // ------------------------------------------------------- Planvorlage

  /// Aktuelle Planvorlage (Hintergrundbild) eines Geschosses.
  Planvorlage? planvorlage(String geschossId) {
    final r = db.select(
      'SELECT * FROM planvorlage WHERE geschoss_id = ? AND geloescht IS NULL ORDER BY erstellt DESC LIMIT 1',
      [geschossId],
    ).firstOrNull;
    return r == null ? null : Planvorlage.ausZeile(r);
  }

  /// Kopiert ein Bild nach dokumente/plaene/ und legt es als Vorlage an
  /// (eine vorhandene Vorlage des Geschosses wird weich ersetzt).
  String planvorlageAnlegen(String geschossId, String quelle, {int umProPx = 10000, int deckkraft = 50}) {
    final ziel = Directory(p.join(ordner, 'dokumente', 'plaene'))..createSync(recursive: true);
    final name = '${neueId()}${p.extension(quelle).toLowerCase()}';
    File(quelle).copySync(p.join(ziel.path, name));
    final alt = planvorlage(geschossId);
    if (alt != null) planvorlageLoeschen(alt.id);
    final id = neueId();
    db.execute(
      'INSERT INTO planvorlage (id, geschoss_id, datei, x_mm, y_mm, um_pro_px, deckkraft, sichtbar, erstellt) '
      'VALUES (?, ?, ?, 0, 0, ?, ?, 1, ?)',
      [id, geschossId, p.join('dokumente', 'plaene', name), umProPx, deckkraft, jetzt()],
    );
    _protokoll('planvorlage', id, 'anlegen', {'quelle': p.basename(quelle)});
    return id;
  }

  void planvorlageAendern(String id, {int? x, int? y, int? umProPx, int? deckkraft, bool? sichtbar}) {
    final felder = <String, Object?>{
      if (x != null) 'x_mm': x,
      if (y != null) 'y_mm': y,
      if (umProPx != null) 'um_pro_px': umProPx,
      if (deckkraft != null) 'deckkraft': deckkraft,
      if (sichtbar != null) 'sichtbar': sichtbar ? 1 : 0,
    };
    if (felder.isEmpty) return;
    db.execute('UPDATE planvorlage SET ${felder.keys.map((k) => '$k = ?').join(', ')} WHERE id = ?',
        [...felder.values, id]);
    _protokoll('planvorlage', id, 'aendern', felder);
  }

  void planvorlageLoeschen(String id) {
    db.execute('UPDATE planvorlage SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('planvorlage', id, 'loeschen');
  }

  void planvorlageWiederherstellen(String id) {
    db.execute('UPDATE planvorlage SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('planvorlage', id, 'wiederherstellen');
  }

  // --------------------------------------------------------- Öffnungen

  /// Alle Öffnungen des Projekts.
  List<Oeffnung> alleOeffnungen() => db
      .select('SELECT o.* FROM oeffnung o JOIN wand w ON w.id = o.wand_id WHERE o.geloescht IS NULL AND w.geloescht IS NULL')
      .map(Oeffnung.ausZeile)
      .toList();

  List<Oeffnung> oeffnungen(String geschossId) => db
      .select(
        'SELECT o.* FROM oeffnung o JOIN wand w ON w.id = o.wand_id '
        'WHERE w.geschoss_id = ? AND o.geloescht IS NULL AND w.geloescht IS NULL',
        [geschossId],
      )
      .map(Oeffnung.ausZeile)
      .toList();

  String oeffnungAnlegen({
    required String wandId,
    required OeffnungsArt art,
    required int abstand,
    required int breite,
    required int hoehe,
    int bruestung = 0,
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO oeffnung (id, wand_id, art, abstand_mm, breite_mm, hoehe_mm, bruestung_mm, erstellt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [id, wandId, art.name, abstand, breite, hoehe, bruestung, jetzt()],
    );
    _protokoll('oeffnung', id, 'anlegen',
        {'wand': wandId, 'art': art.name, 'abstand': abstand, 'breite': breite, 'hoehe': hoehe, 'bruestung': bruestung});
    return id;
  }

  /// Ändert Felder einer Öffnung; liefert die alten Werte für Rückgängig.
  Map<String, Object?> oeffnungAendern(String id, Map<String, Object?> felder) {
    final r = db.select('SELECT * FROM oeffnung WHERE id = ?', [id]).firstOrNull;
    if (r == null || felder.isEmpty) return const {};
    final alt = {for (final k in felder.keys) k: r[k]};
    db.execute('UPDATE oeffnung SET ${felder.keys.map((k) => '$k = ?').join(', ')} WHERE id = ?',
        [...felder.values, id]);
    _protokoll('oeffnung', id, 'aendern', felder);
    return alt;
  }

  void oeffnungLoeschen(String id) {
    db.execute('UPDATE oeffnung SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('oeffnung', id, 'loeschen');
  }

  void oeffnungWiederherstellen(String id) {
    db.execute('UPDATE oeffnung SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('oeffnung', id, 'wiederherstellen');
  }

  // ------------------------------------------------------------ Objekte

  List<Objekttyp> objekttypen() => db
      .select('SELECT t.* FROM objekttyp t JOIN gewerk g ON g.id = t.gewerk_id ORDER BY g.reihenfolge, t.name')
      .map(Objekttyp.ausZeile)
      .toList();

  /// Alle Objekte des Projekts (alle Geschosse).
  List<Objekt> alleObjekte() =>
      db.select('SELECT * FROM objekt WHERE geloescht IS NULL ORDER BY kennung').map(Objekt.ausZeile).toList();

  List<Objekt> objekte(String geschossId) => db
      .select('SELECT * FROM objekt WHERE geschoss_id = ? AND geloescht IS NULL ORDER BY kennung', [geschossId])
      .map(Objekt.ausZeile)
      .toList();

  /// Legt ein Objekt an und vergibt die nächste sprechende Kennung
  /// (Geschoss-Raum-Typ-Nummer, z. B. EG-BAD-SD-03).
  String objektAnlegen({
    required String geschossId,
    required Objekttyp typ,
    required List<Punkt> punkte,
    String? raumId,
    int? z,
    Hoehenbezug? zBezug,
    String? lage,
    ObjektStatus status = ObjektStatus.geplant,
  }) {
    final g = geschoss(geschossId);
    final raum = raumId == null
        ? null
        : db.select('SELECT kuerzel FROM raum WHERE id = ?', [raumId]).firstOrNull?['kuerzel'] as String?;
    final vorhandene = db
        .select('SELECT kennung FROM objekt WHERE geschoss_id = ?', [geschossId])
        .map((r) => r['kennung'] as String);
    final kennung = naechsteKennung(
      geschoss: g?.kuerzel ?? 'G',
      raum: raum ?? 'ALLG',
      typ: typ.kuerzel,
      vorhandene: vorhandene,
    );
    final id = neueId();
    final zeit = jetzt();
    db.execute(
      'INSERT INTO objekt (id, typ_id, geschoss_id, raum_id, kennung, geometrie, z_mm, z_bezug, lage, status, erstellt, geaendert) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, typ.id, geschossId, raumId, kennung, Objekt.geometrieText(punkte), z, zBezug?.name, lage, status.name, zeit, zeit],
    );
    _protokoll('objekt', id, 'anlegen', {'typ': typ.kuerzel, 'kennung': kennung});
    return id;
  }

  /// Ändert Felder eines Objekts (Spaltennamen); liefert die alten Werte.
  Map<String, Object?> objektAendern(String id, Map<String, Object?> felder) {
    final r = db.select('SELECT * FROM objekt WHERE id = ?', [id]).firstOrNull;
    if (r == null || felder.isEmpty) return const {};
    final alt = {for (final k in felder.keys) k: r[k]};
    db.execute(
      'UPDATE objekt SET ${felder.keys.map((k) => '$k = ?').join(', ')}, geaendert = ? WHERE id = ?',
      [...felder.values, jetzt(), id],
    );
    _protokoll('objekt', id, 'aendern', felder);
    return alt;
  }

  void objektLoeschen(String id) {
    db.execute('UPDATE objekt SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('objekt', id, 'loeschen');
  }

  void objektWiederherstellen(String id) {
    db.execute('UPDATE objekt SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('objekt', id, 'wiederherstellen');
  }

  /// Anzahl aktiver Objekte je Gewerk in einem Geschoss.
  Map<String, int> objekteJeGewerk(String geschossId) => {
        for (final r in db.select(
          'SELECT t.gewerk_id AS g, COUNT(*) AS n FROM objekt o JOIN objekttyp t ON t.id = o.typ_id '
          'WHERE o.geschoss_id = ? AND o.geloescht IS NULL GROUP BY t.gewerk_id',
          [geschossId],
        ))
          r['g'] as String: r['n'] as int
      };

  // -------------------------------------------------------------- Fotos

  /// Kopiert ein Foto nach medien/<Geschoss>/<Raum>/ (lesbar ohne Programm),
  /// legt Medium und (noch unverorteten) Fotomarker an.
  String fotoImportieren(String quelle, {required String geschossId, String? raumId, String? notiz}) {
    final datei = File(quelle);
    final g = geschoss(geschossId);
    final raum = raumId == null
        ? null
        : db.select('SELECT kuerzel FROM raum WHERE id = ?', [raumId]).firstOrNull?['kuerzel'] as String?;
    final gk = g?.kuerzel ?? 'G', rk = raum ?? 'ALLG';
    final aufnahme = datei.lastModifiedSync().toUtc();
    final id = neueId();
    final kurz = id.substring(id.length - 8);
    final tag = aufnahme.toIso8601String().substring(0, 10);
    final rel = p.join('medien', gk, rk, '${tag}_$gk-${rk}_$kurz${p.extension(quelle).toLowerCase()}');
    final ziel = File(p.join(ordner, rel));
    ziel.parent.createSync(recursive: true);
    datei.copySync(ziel.path);
    db.execute(
      'INSERT INTO medium (id, datei, art, aufnahme, autor, groesse, notiz, erstellt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [id, rel, 'foto', aufnahme.toIso8601String(), benutzer, ziel.lengthSync(), notiz, jetzt()],
    );
    db.execute(
      'INSERT INTO fotomarker (id, medium_id, geschoss_id, raum_id) VALUES (?, ?, ?, ?)',
      [neueId(), id, geschossId, raumId],
    );
    _protokoll('medium', id, 'importieren', {'datei': rel});
    return id;
  }

  List<Foto> fotos(String geschossId) {
    final zuordnungen = <String, List<String>>{};
    for (final r in db.select(
      'SELECT z.medium_id, z.ziel_id FROM medienzuordnung z JOIN fotomarker f ON f.medium_id = z.medium_id '
      'WHERE f.geschoss_id = ? AND z.geloescht IS NULL',
      [geschossId],
    )) {
      (zuordnungen[r['medium_id'] as String] ??= []).add(r['ziel_id'] as String);
    }
    return db
        .select(
          'SELECT m.*, f.geschoss_id, f.x_mm, f.y_mm, f.richtung, f.raum_id FROM medium m '
          'JOIN fotomarker f ON f.medium_id = m.id WHERE f.geschoss_id = ? AND m.geloescht IS NULL '
          'ORDER BY m.aufnahme DESC',
          [geschossId],
        )
        .map((r) => Foto.ausZeile(r, zuordnungen[r['id']] ?? const []))
        .toList();
  }


  /// Markierungen eines Fotos (JSON-Liste, Koordinaten 0 … 1 im Bild).
  List<Map<String, dynamic>> fotoMarkierungen(String mediumId) {
    final r = db.select('SELECT markierungen FROM medium WHERE id = ?', [mediumId]).firstOrNull;
    return [for (final m in jsonDecode(r?['markierungen'] as String? ?? '[]') as List) Map<String, dynamic>.from(m as Map)];
  }

  /// Markierungen setzen; liefert die alten für Rückgängig.
  List<Map<String, dynamic>> fotoMarkierungenSetzen(String mediumId, List<Map<String, dynamic>> markierungen) {
    final alt = fotoMarkierungen(mediumId);
    db.execute('UPDATE medium SET markierungen = ? WHERE id = ?', [jsonEncode(markierungen), mediumId]);
    _protokoll('medium', mediumId, 'markierungen', {'anzahl': markierungen.length});
    return alt;
  }

  bool fotoIstPanorama(String mediumId) =>
      (db.select('SELECT panorama FROM medium WHERE id = ?', [mediumId]).firstOrNull?['panorama'] as int? ?? 0) == 1;

  void fotoPanoramaSetzen(String mediumId, bool panorama) {
    db.execute('UPDATE medium SET panorama = ? WHERE id = ?', [panorama ? 1 : 0, mediumId]);
    _protokoll('medium', mediumId, 'panorama', {'panorama': panorama});
  }
  /// Ändert den Marker eines Fotos (Lage, Richtung, Raum); liefert alte Werte.
  Map<String, Object?> fotoMarkerAendern(String mediumId, Map<String, Object?> felder) {
    final r = db.select('SELECT * FROM fotomarker WHERE medium_id = ?', [mediumId]).firstOrNull;
    if (r == null || felder.isEmpty) return const {};
    final alt = {for (final k in felder.keys) k: r[k]};
    db.execute('UPDATE fotomarker SET ${felder.keys.map((k) => '$k = ?').join(', ')} WHERE medium_id = ?',
        [...felder.values, mediumId]);
    _protokoll('fotomarker', mediumId, 'aendern', felder);
    return alt;
  }

  void fotoNotizSetzen(String mediumId, String? notiz) {
    db.execute('UPDATE medium SET notiz = ? WHERE id = ?', [notiz, mediumId]);
    _protokoll('medium', mediumId, 'notiz', {'notiz': notiz});
  }

  void fotoLoeschen(String mediumId) {
    db.execute('UPDATE medium SET geloescht = ? WHERE id = ?', [jetzt(), mediumId]);
    _protokoll('medium', mediumId, 'loeschen');
  }

  void fotoWiederherstellen(String mediumId) {
    db.execute('UPDATE medium SET geloescht = NULL WHERE id = ?', [mediumId]);
    _protokoll('medium', mediumId, 'wiederherstellen');
  }

  /// Foto zeigt ein Objekt (an/aus).
  void fotoObjektZuordnen(String mediumId, String objektId, bool zuordnen) {
    if (zuordnen) {
      final da = db.select(
        'SELECT 1 FROM medienzuordnung WHERE medium_id = ? AND ziel_id = ? AND geloescht IS NULL',
        [mediumId, objektId],
      ).isNotEmpty;
      if (da) return;
      db.execute(
        "INSERT INTO medienzuordnung (id, medium_id, ziel_tabelle, ziel_id, erstellt) VALUES (?, ?, 'objekt', ?, ?)",
        [neueId(), mediumId, objektId, jetzt()],
      );
    } else {
      db.execute(
        'UPDATE medienzuordnung SET geloescht = ? WHERE medium_id = ? AND ziel_id = ? AND geloescht IS NULL',
        [jetzt(), mediumId, objektId],
      );
    }
    _protokoll('medienzuordnung', mediumId, zuordnen ? 'zuordnen' : 'entfernen', {'objekt': objektId});
  }

  /// Anzahl Fotos je Objekt (für Hinweise im Modul Installation).
  Map<String, int> fotosJeObjekt(String geschossId) => {
        for (final r in db.select(
          'SELECT z.ziel_id AS o, COUNT(*) AS n FROM medienzuordnung z JOIN medium m ON m.id = z.medium_id '
          'JOIN fotomarker f ON f.medium_id = m.id '
          'WHERE f.geschoss_id = ? AND z.geloescht IS NULL AND m.geloescht IS NULL GROUP BY z.ziel_id',
          [geschossId],
        ))
          r['o'] as String: r['n'] as int
      };

  // ------------------------------------------------- Produkte und Kosten

  List<Produkt> produkte() {
    final angebote = <String, List<Angebot>>{};
    for (final r in db.select('SELECT * FROM haendlerangebot WHERE geloescht IS NULL ORDER BY preis_cent')) {
      final a = Angebot.ausZeile(r);
      (angebote[a.produktId] ??= []).add(a);
    }
    return db
        .select('SELECT * FROM produkt WHERE geloescht IS NULL ORDER BY name')
        .map((r) => Produkt.ausZeile(r, angebote[r['id']] ?? const []))
        .toList();
  }

  String produktAnlegen({required String name, String einheit = 'Stk', bool platzhalter = false}) {
    final id = neueId();
    db.execute('INSERT INTO produkt (id, name, einheit, platzhalter, erstellt) VALUES (?, ?, ?, ?, ?)',
        [id, name, einheit, platzhalter ? 1 : 0, jetzt()]);
    _protokoll('produkt', id, 'anlegen', {'name': name});
    return id;
  }

  Map<String, Object?> produktAendern(String id, Map<String, Object?> felder) =>
      _felderAendern('produkt', id, felder);

  void produktLoeschen(String id) {
    db.execute('UPDATE produkt SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('produkt', id, 'loeschen');
  }

  String angebotAnlegen({
    required String produktId,
    required String haendler,
    required int preisCent,
    int steuer = 1900,
    String? link,
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO haendlerangebot (id, produkt_id, haendler, link, preis_cent, steuer, preisdatum) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, produktId, haendler, link, preisCent, steuer, jetzt().substring(0, 10)],
    );
    _protokoll('haendlerangebot', id, 'anlegen', {'produkt': produktId, 'preis': preisCent});
    return id;
  }

  void angebotLoeschen(String id) {
    db.execute('UPDATE haendlerangebot SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('haendlerangebot', id, 'loeschen');
  }

  List<Kostenposition> kostenpositionen() => db
      .select('SELECT * FROM kostenposition WHERE geloescht IS NULL ORDER BY herkunft DESC, text')
      .map(Kostenposition.ausZeile)
      .toList();

  String kostenpositionAnlegen({
    required String text,
    String kostenart = 'Material',
    int mengeMilli = 1000,
    String einheit = 'Stk',
    int einzelCent = 0,
    int steuer = 1900,
    String? gewerkId,
    String? raumId,
    String? produktId,
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO kostenposition (id, kostenart, text, produkt_id, raum_id, gewerk_id, menge_milli, einheit, '
      'einzel_cent, steuer, status, herkunft, erstellt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, kostenart, text, produktId, raumId, gewerkId, mengeMilli, einheit, einzelCent, steuer, 'geplant', 'manuell', jetzt()],
    );
    _protokoll('kostenposition', id, 'anlegen', {'text': text});
    return id;
  }

  Map<String, Object?> kostenpositionAendern(String id, Map<String, Object?> felder) =>
      _felderAendern('kostenposition', id, felder);

  void kostenpositionLoeschen(String id) {
    db.execute('UPDATE kostenposition SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('kostenposition', id, 'loeschen');
  }

  void kostenpositionWiederherstellen(String id) {
    db.execute('UPDATE kostenposition SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('kostenposition', id, 'wiederherstellen');
  }

  Map<String, Object?> _felderAendern(String tabelle, String id, Map<String, Object?> felder) {
    final r = db.select('SELECT * FROM $tabelle WHERE id = ?', [id]).firstOrNull;
    if (r == null || felder.isEmpty) return const {};
    final alt = {for (final k in felder.keys) k: r[k]};
    db.execute('UPDATE $tabelle SET ${felder.keys.map((k) => '$k = ?').join(', ')} WHERE id = ?', [...felder.values, id]);
    _protokoll(tabelle, id, 'aendern', felder);
    return alt;
  }

  /// Führt die Positionen „aus Plan“ nach: je Objekttyp und Produkt eine
  /// Position mit Stückzahl, Metern oder m² über alle Geschosse. Status und
  /// von Hand geänderte Preise bleiben erhalten; entfallene Positionen
  /// werden weich gelöscht. Liefert die Anzahl der Positionen.
  int planMengenNachfuehren() {
    final typen = {for (final t in objekttypen()) t.id: t};
    final produkteNach = {for (final p in produkte()) p.id: p};
    final mengen = <String, (Objekttyp, String?, double)>{};
    for (final r in db.select('SELECT * FROM objekt WHERE geloescht IS NULL')) {
      final o = Objekt.ausZeile(r);
      final t = typen[o.typId];
      if (t == null) continue;
      final produkt = r['produkt_id'] as String?;
      final menge = switch (t.geometrie) {
        Geometrieart.punkt => 1.0,
        Geometrieart.linie => o.laenge / 1000,
        Geometrieart.flaeche => t.kuerzel == 'HK'
            ? rohrlaenge(o.punkte, FbhEinstellung.ausJson(o.eigenschaften)) / 1000
            : polygonFlaeche(o.punkte).abs() / 1e6,
      };
      final schluessel = '${t.id}|${produkt ?? ''}';
      final alt = mengen[schluessel];
      mengen[schluessel] = (t, produkt, (alt?.$3 ?? 0) + menge);
    }
    final vorhanden = {
      for (final r in db.select("SELECT * FROM kostenposition WHERE herkunft = 'plan'")) r['plan_schluessel'] as String: r
    };
    db.execute('BEGIN');
    try {
      for (final e in mengen.entries) {
        final (t, produktId, menge) = e.value;
        final produkt = produktId == null ? null : produkteNach[produktId];
        final einheit = switch (t.geometrie) {
          Geometrieart.punkt => 'Stk',
          Geometrieart.linie => 'm',
          Geometrieart.flaeche => t.kuerzel == 'HK' ? 'm' : 'm²',
        };
        final milli = (menge * 1000).round();
        final name = t.kuerzel == 'HK' ? 'Heizrohr (Heizkreise)' : t.name;
        final text = produkt == null ? name : '$name – ${produkt.name}';
        final r = vorhanden[e.key];
        if (r == null) {
          final angebot = produkt?.bestesAngebot;
          db.execute(
            'INSERT INTO kostenposition (id, kostenart, text, produkt_id, gewerk_id, menge_milli, einheit, einzel_cent, '
            "steuer, status, herkunft, plan_schluessel, erstellt) VALUES (?, 'Material', ?, ?, ?, ?, ?, ?, ?, 'geplant', 'plan', ?, ?)",
            [neueId(), text, produktId, t.gewerkId, milli, einheit, angebot?.preisCent ?? 0, angebot?.steuer ?? 1900, e.key, jetzt()],
          );
        } else {
          db.execute('UPDATE kostenposition SET menge_milli = ?, text = ?, geloescht = NULL WHERE id = ?',
              [milli, text, r['id']]);
        }
      }
      for (final e in vorhanden.entries) {
        if (!mengen.containsKey(e.key) && e.value['geloescht'] == null) {
          db.execute('UPDATE kostenposition SET geloescht = ? WHERE id = ?', [jetzt(), e.value['id']]);
        }
      }
      _protokoll('kostenposition', 'plan', 'nachfuehren', {'positionen': mengen.length});
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return mengen.length;
  }

  // ------------------------------------------------- Schränke und Stromkreise

  List<Schrank> schraenke() =>
      db.select('SELECT * FROM schrank WHERE geloescht IS NULL ORDER BY kennzeichen').map(Schrank.ausZeile).toList();

  String schrankAnlegen({
    required String name,
    required String kennzeichen,
    SchrankArt art = SchrankArt.unterverteiler,
    int reihen = 4,
    int teJeReihe = 12,
    String? geschossId,
    String? objektId,
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO schrank (id, geschoss_id, objekt_id, name, kennzeichen, art, reihen, te_je_reihe, erstellt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, geschossId, objektId, name, kennzeichen, art.name, reihen, teJeReihe, jetzt()],
    );
    _protokoll('schrank', id, 'anlegen', {'name': name, 'kennzeichen': kennzeichen});
    return id;
  }

  Map<String, Object?> schrankAendern(String id, Map<String, Object?> felder) => _felderAendern('schrank', id, felder);

  void schrankLoeschen(String id) {
    db.execute('UPDATE schrank SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('schrank', id, 'loeschen');
  }

  void schrankWiederherstellen(String id) {
    db.execute('UPDATE schrank SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('schrank', id, 'wiederherstellen');
  }

  List<SchrankGeraet> schrankGeraete(String schrankId) => db
      .select('SELECT * FROM schrankgeraet WHERE schrank_id = ? AND geloescht IS NULL ORDER BY reihe, position', [schrankId])
      .map(SchrankGeraet.ausZeile)
      .toList();

  String geraetAnlegen({
    required String schrankId,
    required int reihe,
    required int position,
    required GeraeteArt art,
    required String kennzeichen,
    int pole = 1,
    int? breite,
    String bezeichnung = '',
    int? nennstrom,
    String? charakteristik,
    int? fehlerstrom,
    String? phase,
    String? vorgeschaltetId,
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO schrankgeraet (id, schrank_id, reihe, position, breite, art, kennzeichen, bezeichnung, pole, nennstrom, '
      'charakteristik, fehlerstrom, phase, vorgeschaltet_id, erstellt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id, schrankId, reihe, position, breite ?? art.breite(pole), art.name, kennzeichen, bezeichnung, pole, nennstrom,
        charakteristik, fehlerstrom, phase, vorgeschaltetId, jetzt(),
      ],
    );
    _protokoll('schrankgeraet', id, 'anlegen', {'art': art.name, 'kennzeichen': kennzeichen});
    return id;
  }

  Map<String, Object?> geraetAendern(String id, Map<String, Object?> felder) => _felderAendern('schrankgeraet', id, felder);

  void geraetLoeschen(String id) {
    db.execute('UPDATE schrankgeraet SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('schrankgeraet', id, 'loeschen');
  }

  void geraetWiederherstellen(String id) {
    db.execute('UPDATE schrankgeraet SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('schrankgeraet', id, 'wiederherstellen');
  }

  List<Stromkreis> stromkreise(String schrankId) => db
      .select('SELECT * FROM stromkreis WHERE schrank_id = ? AND geloescht IS NULL', [schrankId])
      .map(Stromkreis.ausZeile)
      .toList()
    ..sort((a, b) => (int.tryParse(a.nummer) ?? 9999).compareTo(int.tryParse(b.nummer) ?? 9999));

  String stromkreisAnlegen({
    required String schrankId,
    required String nummer,
    String bezeichnung = '',
    String? schutzId,
    int querschnitt = 150,
    String leitung = 'NYM-J 3x1,5',
    int leistung = 0,
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO stromkreis (id, schrank_id, nummer, bezeichnung, schutz_id, querschnitt, leitung, leistung_w, erstellt) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, schrankId, nummer, bezeichnung, schutzId, querschnitt, leitung, leistung, jetzt()],
    );
    _protokoll('stromkreis', id, 'anlegen', {'nummer': nummer, 'bezeichnung': bezeichnung});
    return id;
  }

  Map<String, Object?> stromkreisAendern(String id, Map<String, Object?> felder) => _felderAendern('stromkreis', id, felder);

  void stromkreisLoeschen(String id) {
    db.execute('UPDATE stromkreis SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('stromkreis', id, 'loeschen');
  }

  void stromkreisWiederherstellen(String id) {
    db.execute('UPDATE stromkreis SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('stromkreis', id, 'wiederherstellen');
  }

  /// Objekte (alle Geschosse), die einem Stromkreis zugeordnet sind (`eigenschaften.stromkreis`).
  List<Objekt> objekteImStromkreis(String stromkreisId) =>
      [for (final o in alleObjekte()) if (o.eigenschaften['stromkreis'] == stromkreisId) o];

  // ------------------------------------------------- Bautagebuch und Aufgaben

  String _tag(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<TagebuchEintrag> tagebuch() => db
      .select('SELECT * FROM tagebuch WHERE geloescht IS NULL ORDER BY datum DESC, erstellt DESC')
      .map(TagebuchEintrag.ausZeile)
      .toList();

  String tagebuchAnlegen({
    required DateTime datum,
    String text = '',
    double stunden = 0,
    List<String> raeume = const [],
    List<String> gewerke = const [],
    String wetter = '',
    String personen = '',
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO tagebuch (id, datum, text, stunden_hundertstel, raeume, gewerke, wetter, personen, erstellt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, _tag(datum), text, (stunden * 100).round(), jsonEncode(raeume), jsonEncode(gewerke), wetter, personen, jetzt()],
    );
    _protokoll('tagebuch', id, 'anlegen', {'datum': _tag(datum)});
    return id;
  }

  Map<String, Object?> tagebuchAendern(String id, Map<String, Object?> felder) => _felderAendern('tagebuch', id, felder);

  void tagebuchLoeschen(String id) {
    db.execute('UPDATE tagebuch SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('tagebuch', id, 'loeschen');
  }

  void tagebuchWiederherstellen(String id) {
    db.execute('UPDATE tagebuch SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('tagebuch', id, 'wiederherstellen');
  }

  List<Aufgabe> aufgaben() => db
      .select("SELECT * FROM aufgabe WHERE geloescht IS NULL ORDER BY CASE status WHEN 'erledigt' THEN 1 ELSE 0 END, faellig IS NULL, faellig")
      .map(Aufgabe.ausZeile)
      .toList();

  String aufgabeAnlegen({
    required String titel,
    String beschreibung = '',
    String? raumId,
    String? gewerkId,
    DateTime? faellig,
    String? abhaengigVon,
    int? intervallTage,
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO aufgabe (id, titel, beschreibung, raum_id, gewerk_id, faellig, abhaengig_von, intervall_tage, erstellt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, titel, beschreibung, raumId, gewerkId, faellig == null ? null : _tag(faellig), abhaengigVon, intervallTage, jetzt()],
    );
    _protokoll('aufgabe', id, 'anlegen', {'titel': titel});
    return id;
  }

  Map<String, Object?> aufgabeAendern(String id, Map<String, Object?> felder) => _felderAendern('aufgabe', id, felder);

  /// Aufgabe erledigen; eine Wartung bekommt dabei das nächste Fälligkeitsdatum
  /// und bleibt offen. Liefert die alten Werte für Rückgängig.
  Map<String, Object?> aufgabeErledigen(String id, {DateTime? am}) {
    final r = db.select('SELECT * FROM aufgabe WHERE id = ?', [id]).firstOrNull;
    if (r == null) return const {};
    final a = Aufgabe.ausZeile(r);
    final tag = am ?? DateTime.now();
    if (a.istWartung) {
      return _felderAendern('aufgabe', id, {'erledigt_am': _tag(tag), 'faellig': _tag(naechsteWartung(a, tag)), 'status': AufgabenStatus.offen.name});
    }
    return _felderAendern('aufgabe', id, {'erledigt_am': _tag(tag), 'status': AufgabenStatus.erledigt.name});
  }

  void aufgabeLoeschen(String id) {
    db.execute('UPDATE aufgabe SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('aufgabe', id, 'loeschen');
  }

  void aufgabeWiederherstellen(String id) {
    db.execute('UPDATE aufgabe SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('aufgabe', id, 'wiederherstellen');
  }

  List<Pruefprotokoll> pruefprotokolle() =>
      db.select('SELECT * FROM pruefprotokoll WHERE geloescht IS NULL ORDER BY datum DESC').map(Pruefprotokoll.ausZeile).toList();

  String pruefprotokollAnlegen({
    required String art,
    required DateTime datum,
    String? raumId,
    String? objektId,
    Map<String, String> messwerte = const {},
    String ergebnis = 'bestanden',
    String pruefer = '',
    String notiz = '',
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO pruefprotokoll (id, art, datum, raum_id, objekt_id, messwerte, ergebnis, pruefer, notiz, erstellt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, art, _tag(datum), raumId, objektId, jsonEncode(messwerte), ergebnis, pruefer, notiz, jetzt()],
    );
    _protokoll('pruefprotokoll', id, 'anlegen', {'art': art});
    return id;
  }

  Map<String, Object?> pruefprotokollAendern(String id, Map<String, Object?> felder) => _felderAendern('pruefprotokoll', id, felder);

  void pruefprotokollLoeschen(String id) {
    db.execute('UPDATE pruefprotokoll SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('pruefprotokoll', id, 'loeschen');
  }

  void pruefprotokollWiederherstellen(String id) {
    db.execute('UPDATE pruefprotokoll SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('pruefprotokoll', id, 'wiederherstellen');
  }

  /// Automatische Verlaufseinträge: Statuswechsel von Objekten (aus dem
  /// Änderungsprotokoll), neueste zuerst: (Zeit, Benutzer, Objekt-ID, Status).
  List<(DateTime, String, String, String)> statusVerlauf({int limit = 500}) => [
        for (final r in db.select(
          "SELECT zeit, benutzer, datensatz, daten FROM aenderung WHERE tabelle = 'objekt' AND aktion = 'aendern' "
          "AND daten LIKE '%\"status\"%' ORDER BY nr DESC LIMIT ?",
          [limit],
        ))
          if ((jsonDecode(r['daten'] as String? ?? '{}') as Map)['status'] case final String s)
            (DateTime.parse(r['zeit'] as String).toLocal(), r['benutzer'] as String, r['datensatz'] as String, s),
      ];

  // --------------------------------------------------------- Bemaßungen

  List<Bemassung> bemassungen(String geschossId) => db
      .select('SELECT * FROM bemassung WHERE geschoss_id = ? AND geloescht IS NULL', [geschossId])
      .map(Bemassung.ausZeile)
      .toList();

  String bemassungAnlegen({
    required String geschossId,
    required int x1,
    required int y1,
    required int x2,
    required int y2,
    required int abstand,
  }) {
    final id = neueId();
    db.execute(
      'INSERT INTO bemassung (id, geschoss_id, x1, y1, x2, y2, abstand_mm, erstellt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [id, geschossId, x1, y1, x2, y2, abstand, jetzt()],
    );
    _protokoll('bemassung', id, 'anlegen', {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'abstand': abstand});
    return id;
  }

  /// Eigene Bemaßung oder Winkelmaß ausblenden (oder wieder zeigen).
  void massVerstecken(String tabelle, String id, bool versteckt) {
    assert(tabelle == 'bemassung' || tabelle == 'winkelmass');
    db.execute('UPDATE $tabelle SET versteckt = ? WHERE id = ?', [versteckt ? 1 : 0, id]);
    _protokoll(tabelle, id, versteckt ? 'ausblenden' : 'einblenden');
  }

  /// Alle einzeln ausgeblendeten Maße eines Geschosses wieder zeigen; liefert die IDs.
  List<(String, String)> versteckteMasseZeigen(String geschossId) {
    final ids = [
      for (final t in ['bemassung', 'winkelmass'])
        for (final r in db.select('SELECT id FROM $t WHERE geschoss_id = ? AND versteckt = 1 AND geloescht IS NULL', [geschossId]))
          (t, r['id'] as String)
    ];
    for (final (t, id) in ids) {
      massVerstecken(t, id, false);
    }
    return ids;
  }

  void bemassungLoeschen(String id) {
    db.execute('UPDATE bemassung SET geloescht = ? WHERE id = ?', [jetzt(), id]);
    _protokoll('bemassung', id, 'loeschen');
  }

  void bemassungWiederherstellen(String id) {
    db.execute('UPDATE bemassung SET geloescht = NULL WHERE id = ?', [id]);
    _protokoll('bemassung', id, 'wiederherstellen');
  }

  // ------------------------------------------------------------ Gewerke

  List<Gewerk> gewerke() => db
      .select('SELECT * FROM gewerk ORDER BY reihenfolge')
      .map(Gewerk.ausZeile)
      .toList();

  void gewerkAendern(String id, {int? farbe, bool? sichtbar}) {
    if (farbe != null) db.execute('UPDATE gewerk SET farbe = ? WHERE id = ?', [farbe, id]);
    if (sichtbar != null) {
      db.execute('UPDATE gewerk SET sichtbar = ? WHERE id = ?', [sichtbar ? 1 : 0, id]);
    }
    _protokoll('gewerk', id, 'aendern', {'farbe': farbe, 'sichtbar': sichtbar});
  }

  int anzahlObjekttypen(String gewerkId) =>
      db.select('SELECT COUNT(*) AS n FROM objekttyp WHERE gewerk_id = ?', [gewerkId]).first['n']
          as int;
}
