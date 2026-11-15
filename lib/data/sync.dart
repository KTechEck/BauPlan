import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'project_store.dart';

/// Echtzeit-Synchronisation PC ↔ iPad.
///
/// Jedes Gerät hat eine eigene Kopie des Projekts. Temporäre Trigger schreiben
/// jede Änderung (Tabelle + Datensatz-ID) in `sync_log`; Projekteinstellungen
/// werden je Schlüssel als Tabelle `einstellung` vermerkt. Beim Abgleich
/// schickt das iPad seine geänderten Datensätze (aktueller Stand der Zeile
/// oder „gelöscht“) an den PC, der PC antwortet mit seinen Änderungen seit
/// dem letzten Abgleich. Wurde derselbe Datensatz auf beiden Seiten geändert,
/// gewinnt die jüngere Änderung – die andere landet unter `sync_konflikte`
/// und lässt sich am PC wiederherstellen. Nichts geht verloren.

/// Tabellen, die nicht abgeglichen werden.
const _ohne = {'aenderung', 'sync_log', 'sqlite_sequence', 'projekt'};

/// Abgeglichene Tabellen (alle mit Spalte `id`).
List<String> syncTabellen(Database db) => [
      for (final r in db.select("SELECT name FROM sqlite_master WHERE type = 'table'"))
        if (!_ohne.contains(r['name']) && !'${r['name']}'.startsWith('sqlite_') && db.select('PRAGMA table_info(${r['name']})').any((c) => c['name'] == 'id')) '${r['name']}',
    ];

/// Temporäre Trigger und Steuertabelle anlegen (bei jedem Öffnen).
void syncVorbereiten(Database db) {
  db.execute('CREATE TEMP TABLE IF NOT EXISTS sync_kontext (stumm INTEGER NOT NULL, herkunft TEXT)');
  if (db.select('SELECT COUNT(*) AS n FROM temp.sync_kontext').first['n'] == 0) db.execute('INSERT INTO temp.sync_kontext VALUES (0, NULL)');
  for (final t in syncTabellen(db)) {
    for (final (art, ref) in const [('INSERT', 'NEW'), ('UPDATE', 'NEW'), ('DELETE', 'OLD')]) {
      db.execute('CREATE TEMP TRIGGER IF NOT EXISTS sync_${t}_${art.toLowerCase()} AFTER $art ON main.$t '
          'WHEN (SELECT stumm FROM temp.sync_kontext) = 0 BEGIN '
          "INSERT INTO main.sync_log (tabelle, datensatz, zeit, herkunft) VALUES ('$t', $ref.id, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT herkunft FROM temp.sync_kontext)); "
          'END');
    }
  }
}

/// Geänderten Einstellungsschlüssel vermerken (vom Store aufgerufen).
void syncEinstellungVermerken(Database db, String schluessel) {
  try {
    final k = db.select('SELECT stumm, herkunft FROM temp.sync_kontext').firstOrNull;
    if (k == null || k['stumm'] == 1) return;
    db.execute("INSERT INTO sync_log (tabelle, datensatz, zeit, herkunft) VALUES ('einstellung', ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), ?)", [schluessel, k['herkunft']]);
  } catch (_) {}
}

int syncStand(Database db) => (db.select('SELECT MAX(nr) AS n FROM sync_log').first['n'] as int?) ?? 0;

/// Änderungen nach [seit] (ohne die von [ausser] stammenden), je Datensatz der
/// jüngste Stand: Zeile oder null (gelöscht).
({int bis, List<Map<String, dynamic>> aenderungen}) aenderungenSeit(ProjectStore store, int seit, {String? ausser}) {
  final db = store.db;
  final eintraege = db.select('SELECT nr, tabelle, datensatz, zeit, herkunft FROM sync_log WHERE nr > ? ORDER BY nr', [seit]);
  final jung = <String, Map<String, dynamic>>{};
  var bis = seit;
  for (final e in eintraege) {
    bis = e['nr'] as int;
    final h = e['herkunft'] as String?;
    final key = '${e['tabelle']}|${e['datensatz']}';
    if (ausser != null && h == ausser) {
      // eigene Änderung dieses Geräts – nicht zurückschicken, aber ältere fremde überschreibt sie
      jung.remove(key);
      continue;
    }
    jung[key] = {'t': e['tabelle'], 'id': e['datensatz'], 'zeit': e['zeit']};
  }
  final tabellen = syncTabellen(db).toSet();
  final aus = <Map<String, dynamic>>[];
  for (final x in jung.values) {
    final t = x['t'] as String;
    if (t == 'einstellung') {
      aus.add({...x, 'zeile': {'wert': store.einstellung<Object>(x['id'] as String)}});
      continue;
    }
    if (!tabellen.contains(t)) continue;
    final r = db.select('SELECT * FROM $t WHERE id = ?', [x['id']]).firstOrNull;
    aus.add({...x, 'zeile': r == null ? null : {for (final k in r.keys) k: r[k]}});
  }
  return (bis: bis, aenderungen: aus);
}

/// Änderungen eines anderen Geräts anwenden. [herkunft] = Gerät (am PC: wird
/// mitprotokolliert, damit andere Geräte sie bekommen); [stumm] = gar nicht
/// protokollieren (auf dem iPad für Änderungen vom PC).
void aenderungenAnwenden(ProjectStore store, List<Map<String, dynamic>> aenderungen, {String? herkunft, bool stumm = false}) {
  final db = store.db;
  final spalten = <String, Set<String>>{};
  Set<String> sp(String t) => spalten[t] ??= {for (final c in db.select('PRAGMA table_info($t)')) '${c['name']}'};
  final tabellen = syncTabellen(db).toSet();
  db.execute('PRAGMA foreign_keys = OFF');
  db.execute('UPDATE temp.sync_kontext SET stumm = ?, herkunft = ?', [stumm ? 1 : 0, herkunft]);
  db.execute('BEGIN');
  try {
    for (final a in aenderungen) {
      final t = a['t'] as String;
      final id = a['id'] as String;
      final z = a['zeile'] as Map?;
      if (t == 'einstellung') {
        store.einstellungUebernehmen(id, z?['wert']);
        if (!stumm) syncEinstellungVermerken(db, id);
        continue;
      }
      if (!tabellen.contains(t)) continue;
      if (z == null) {
        db.execute('DELETE FROM $t WHERE id = ?', [id]);
        continue;
      }
      final cols = [for (final k in z.keys) if (sp(t).contains(k)) '$k'];
      if (cols.isEmpty) continue;
      final update = [for (final c in cols) if (c != 'id') '$c = excluded.$c'].join(', ');
      db.execute('INSERT INTO $t (${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')}) '
          'ON CONFLICT(id) DO ${update.isEmpty ? 'NOTHING' : 'UPDATE SET $update'}', [for (final c in cols) z[c]]);
    }
    db.execute('COMMIT');
  } catch (e) {
    db.execute('ROLLBACK');
    rethrow;
  } finally {
    db.execute('UPDATE temp.sync_kontext SET stumm = 0, herkunft = NULL');
    db.execute('PRAGMA foreign_keys = ON');
  }
}

/// Konflikte (am PC gespeichert): beide Stände, wer gewonnen hat.
List<Map<String, dynamic>> syncKonflikte(ProjectStore store) =>
    [for (final x in store.einstellung<List>('sync_konflikte') ?? const []) Map<String, dynamic>.from(x as Map)];

/// PC-Seite eines Abgleichs. [body]: {seit, aenderungen}. Liefert die Antwort.
Map<String, dynamic> syncAmPc(ProjectStore store, Map<String, dynamic> body, String geraet, {String geraetName = 'iPad'}) {
  final seit = (body['seit'] as num?)?.toInt() ?? 0;
  final rein = [for (final a in (body['aenderungen'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)];
  // Konflikte: Datensatz am PC nach „seit“ von jemand anderem geändert
  final db = store.db;
  final amPc = <String, String>{};
  for (final e in db.select('SELECT tabelle, datensatz, zeit, herkunft FROM sync_log WHERE nr > ?', [seit])) {
    if (e['herkunft'] == geraet) continue;
    amPc['${e['tabelle']}|${e['datensatz']}'] = e['zeit'] as String;
  }
  final anwenden = <Map<String, dynamic>>[];
  final konflikte = syncKonflikte(store);
  var neueKonflikte = 0;
  for (final a in rein) {
    final key = '${a['t']}|${a['id']}';
    final pcZeit = amPc[key];
    if (pcZeit == null) {
      anwenden.add(a);
      continue;
    }
    final ipadNeuer = '${a['zeit']}'.compareTo(pcZeit) > 0;
    final Object? pcZeile = a['t'] == 'einstellung'
        ? {'wert': store.einstellung<Object>('${a['id']}')}
        : (() {
            final r = db.select('SELECT * FROM ${a['t']} WHERE id = ?', [a['id']]).firstOrNull;
            return r == null ? null : {for (final k in r.keys) k: r[k]};
          })();
    konflikte.add({
      'tabelle': a['t'],
      'id': a['id'],
      'zeit': DateTime.now().toIso8601String(),
      'geraet': geraetName,
      'gewinner': ipadNeuer ? geraetName : 'PC',
      'verlierer_zeile': ipadNeuer ? pcZeile : a['zeile'],
      'verlierer_zeit': ipadNeuer ? pcZeit : a['zeit'],
    });
    neueKonflikte++;
    if (ipadNeuer) anwenden.add(a);
  }
  if (anwenden.isNotEmpty) aenderungenAnwenden(store, anwenden, herkunft: geraet);
  if (neueKonflikte > 0) store.einstellungSetzen('sync_konflikte', konflikte.length > 200 ? konflikte.sublist(konflikte.length - 200) : konflikte);
  final raus = aenderungenSeit(store, seit, ausser: geraet);
  return {'bis': syncStand(db), 'aenderungen': raus.aenderungen, 'konflikte': neueKonflikte, 'angewendet': anwenden.length};
}

/// Stand des Abgleichs auf dem iPad (Datei im Projektordner).
class SyncStand {
  SyncStand({this.pc = 0, this.eigen = -1, this.dateienSeit, this.eigeneDateienSeit, this.adresse, this.code, this.geraet = ''});
  int pc; // letzter bekannter Stand des PCs (sync_log-Nr. dort)
  int eigen; // eigene Änderungen bis hierhin übertragen (−1: beim ersten Öffnen festlegen)
  DateTime? dateienSeit; // Uhr des PCs: dessen Dateien bis hier bekannt
  DateTime? eigeneDateienSeit; // eigene Uhr: eigene Dateien bis hier hochgeladen
  String? adresse, code;
  String geraet;

  static const datei = 'sync_stand.json';

  static SyncStand? lesen(String ordner) {
    final f = File(p.join(ordner, datei));
    if (!f.existsSync()) return null;
    try {
      final m = jsonDecode(f.readAsStringSync()) as Map;
      return SyncStand(
        pc: (m['pc'] as num?)?.toInt() ?? 0,
        eigen: (m['eigen'] as num?)?.toInt() ?? 0,
        dateienSeit: DateTime.tryParse('${m['dateien_seit'] ?? ''}'),
        eigeneDateienSeit: DateTime.tryParse('${m['eigene_dateien_seit'] ?? ''}'),
        adresse: m['adresse'] as String?,
        code: m['code'] as String?,
        geraet: m['geraet'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  void schreiben(String ordner) => File(p.join(ordner, datei)).writeAsStringSync(jsonEncode({
        'pc': pc,
        'eigen': eigen,
        if (dateienSeit != null) 'dateien_seit': dateienSeit!.toIso8601String(),
        if (eigeneDateienSeit != null) 'eigene_dateien_seit': eigeneDateienSeit!.toIso8601String(),
        'adresse': adresse,
        'code': code,
        'geraet': geraet,
      }));
}

/// Neue/geänderte Dateien im Projektordner seit [seit] (ohne Datenbank, Sicherungen, Austausch).
List<String> geaenderteDateien(String ordner, DateTime? seit) {
  final aus = <String>[];
  final basis = Directory(ordner);
  if (!basis.existsSync()) return aus;
  for (final f in basis.listSync(recursive: true, followLinks: false).whereType<File>()) {
    final rel = p.relative(f.path, from: ordner).replaceAll(r'\', '/');
    if (rel.startsWith(datenbankDatei) || rel == sperrDatei || rel.startsWith('backup/') || rel.startsWith('austausch/') || rel.endsWith('.lock') || rel == SyncStand.datei || rel.endsWith('.tmp') || rel.startsWith('ipad_ausleihe')) continue;
    if (seit != null && !f.lastModifiedSync().isAfter(seit)) continue;
    aus.add(rel);
  }
  return aus;
}
