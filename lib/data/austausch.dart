import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/auswertung.dart';
import '../core/raumerkennung.dart';
import 'models.dart';
import 'project_store.dart';

/// Austausch PC ↔ App (Lastenheft Abschnitt 2 und 14):
/// - Der PC legt bei jedem Speichern eine Lesekopie `planstand/planstand.json` ab
///   (Grundriss mit Ebenen, Objekte, Einkaufsliste) – die App liest nur sie.
/// - Die App schreibt jede Erfassung als eigene Datei nach `eingang/`
///   (`<zeit>_<id>.json`, bei Fotos dazu `<zeit>_<id>.jpg`) und nie in die Datenbank.
/// - Der PC übernimmt den Eingang und verschiebt die Dateien nach `eingang/_archiv`.
const planstandDatei = 'planstand/planstand.json';
const planstandVersion = 1;

/// Lesekopie des Projekts für die App.
Map<String, dynamic> planstandErzeugen(ProjectStore store) {
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final gewerke = store.gewerke();
  final gewerkKuerzel = {for (final g in gewerke) g.id: g.kuerzel};
  final geschosse = <Map<String, dynamic>>[];
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final waende = store.waende(g.id);
      final wandNach = {for (final w in waende) w.id: w};
      geschosse.add({
        'id': g.id,
        'name': g.name,
        'kuerzel': g.kuerzel,
        'gebaeude': geb.name,
        'waende': [
          for (final w in waende) {'id': w.id, 'a': [w.x1, w.y1], 'b': [w.x2, w.y2], 'd': w.dicke}
        ],
        'oeffnungen': [
          for (final o in store.oeffnungen(g.id))
            if (wandNach[o.wandId] != null) {'wand': o.wandId, 'art': o.art.name, 'abstand': o.abstand, 'breite': o.breite}
        ],
        'raeume': [
          for (final r in store.raeume(g.id))
            {
              'id': r.id,
              'name': r.name,
              'kuerzel': r.kuerzel,
              if (r.umriss != null) 'umriss': [for (final q in r.umriss!) [q.x.round(), q.y.round()]],
            }
        ],
        'objekte': [
          for (final o in store.objekte(g.id))
            if (typen[o.typId] != null)
              {
                'id': o.id,
                'kennung': o.kennung,
                'typ': typen[o.typId]!.kuerzel,
                'name': typen[o.typId]!.name,
                'geometrie': typen[o.typId]!.geometrie.name,
                'gewerk': gewerkKuerzel[typen[o.typId]!.gewerkId] ?? '',
                'raum': o.raumId,
                'status': o.status.name,
                'lage': o.lage,
                'punkte': [for (final q in o.punkte) [q.x.round(), q.y.round()]],
                if (o.z != null) 'z': o.z,
                if (o.zBezug != null) 'z_bezug': o.zBezug!.name,
              }
        ],
      });
    }
  }
  final einkauf = <Map<String, dynamic>>[];
  for (final e in einkaufsliste(store.kostenpositionen(), store.produkte(), auchUnterwegs: true).entries) {
    for (final x in e.value) {
      einkauf.add({
        'id': x.position.id,
        'text': x.position.text,
        'menge': x.menge,
        'einheit': x.position.einheit,
        'haendler': e.key,
        if (x.angebot?.link != null) 'link': x.angebot!.link,
        'status': x.position.status.name,
      });
    }
  }
  return {
    'version': planstandVersion,
    'erstellt': DateTime.now().toUtc().toIso8601String(),
    'projekt': p.basename(store.ordner),
    'gewerke': [for (final g in gewerke) {'kuerzel': g.kuerzel, 'name': g.name, 'farbe': g.farbe}],
    'status': [for (final s in ObjektStatus.values) {'name': s.name, 'label': s.label}],
    'geschosse': geschosse,
    'einkauf': einkauf,
  };
}

/// Lesekopie schreiben (atomar: erst .tmp, dann umbenennen).
void planstandSchreiben(ProjectStore store) {
  final ziel = File(p.join(store.ordner, planstandDatei));
  ziel.parent.createSync(recursive: true);
  final tmp = File('${ziel.path}.tmp');
  tmp.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(planstandErzeugen(store)));
  if (ziel.existsSync()) ziel.deleteSync();
  tmp.renameSync(ziel.path);
}

/// Ergebnis einer Übernahme.
typedef EingangErgebnis = ({int uebernommen, int fehler, List<String> hinweise});

/// Neue Erfassungen aus `eingang/` übernehmen und archivieren.
EingangErgebnis eingangUebernehmen(ProjectStore store) {
  final ordner = Directory(p.join(store.ordner, 'eingang'));
  if (!ordner.existsSync()) return (uebernommen: 0, fehler: 0, hinweise: const []);
  final archiv = Directory(p.join(ordner.path, '_archiv'))..createSync(recursive: true);
  var n = 0, f = 0;
  final hinweise = <String>[];
  final jsons = ordner.listSync().whereType<File>().where((d) => d.path.toLowerCase().endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final datei in jsons) {
    try {
      final e = Map<String, dynamic>.from(jsonDecode(datei.readAsStringSync()) as Map);
      final anhang = e['datei'] is String ? File(p.join(ordner.path, e['datei'] as String)) : null;
      if (anhang != null && !anhang.existsSync()) continue; // Foto noch nicht vollständig synchronisiert
      _eintragUebernehmen(store, e, anhang, hinweise);
      for (final d in [datei, if (anhang != null) anhang]) {
        final z = File(p.join(archiv.path, p.basename(d.path)));
        if (z.existsSync()) z.deleteSync();
        d.renameSync(z.path);
      }
      n++;
    } catch (err) {
      f++;
      hinweise.add('${p.basename(datei.path)}: $err');
    }
  }
  return (uebernommen: n, fehler: f, hinweise: hinweise);
}

void _eintragUebernehmen(ProjectStore store, Map<String, dynamic> e, File? anhang, List<String> hinweise) {
  final art = e['art'] as String? ?? '';
  final geschossId = e['geschoss'] as String?;
  final raumId = e['raum'] as String?;
  final objektId = e['objekt'] as String?;
  final autor = e['autor'] as String? ?? 'App';
  final zeit = DateTime.tryParse(e['zeit'] as String? ?? '') ?? DateTime.now();
  final text = (e['text'] as String? ?? '').trim();
  String? medium;
  if (anhang != null && geschossId != null) {
    medium = store.fotoImportieren(anhang.path, geschossId: geschossId, raumId: raumId, notiz: text.isEmpty ? null : '$text ($autor)');
    final x = (e['x'] as num?)?.round(), y = (e['y'] as num?)?.round();
    if (x != null && y != null) store.fotoMarkerAendern(medium, {'x_mm': x, 'y_mm': y});
    if (objektId != null) store.fotoObjektZuordnen(medium, objektId, true);
  }
  switch (art) {
    case 'status':
      final s = ObjektStatus.values.where((x) => x.name == e['status']).firstOrNull;
      if (objektId != null && s != null) store.objektAendern(objektId, {'status': s.name});
      hinweise.add('Status ${s?.label ?? e['status']} gesetzt ($autor)');
    case 'messwert':
    case 'material':
    case 'notiz':
      final wert = e['wert'] == null ? '' : ' ${e['wert']} ${e['einheit'] ?? ''}'.trimRight();
      final titel = switch (art) { 'messwert' => 'Messwert', 'material' => 'Material', _ => 'Notiz' };
      if (objektId != null && art != 'notiz') {
        final o = _objekt(store, geschossId, objektId);
        if (o != null) {
          final liste = [...(o.eigenschaften['erfassungen'] as List? ?? const []), {'art': art, 'text': text, 'wert': e['wert'], 'einheit': e['einheit'], 'zeit': zeit.toIso8601String(), 'autor': autor}];
          store.objektAendern(objektId, {'eigenschaften': jsonEncode({...o.eigenschaften, 'erfassungen': liste})});
        }
      }
      store.tagebuchAnlegen(datum: zeit, text: '$titel$wert${text.isEmpty ? '' : ': $text'} – $autor (App)', raeume: [if (raumId != null) raumId]);
    case 'einkauf':
      final id = e['position'] as String?;
      if (id != null) store.kostenpositionAendern(id, {'status': e['erledigt'] == false ? KostenStatus.geplant.name : KostenStatus.geliefert.name});
    case 'foto':
      break;
    default:
      hinweise.add('Unbekannte Erfassung „$art“');
  }
}

Objekt? _objekt(ProjectStore store, String? geschossId, String id) {
  if (geschossId != null) {
    final o = store.objekte(geschossId).where((x) => x.id == id).firstOrNull;
    if (o != null) return o;
  }
  return store.alleObjekte().where((x) => x.id == id).firstOrNull;
}

/// Kleine Hilfe für Tests/App: Punkt aus JSON.
Punkt punktAus(List l) => Punkt((l[0] as num).toDouble(), (l[1] as num).toDouble());
