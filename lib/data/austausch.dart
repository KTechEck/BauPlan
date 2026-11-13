import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/auswertung.dart';
import '../core/aufmass.dart';
import '../core/brandschutz.dart';
import '../core/geschossuebergreifend.dart';
import '../core/height.dart';
import '../core/sparren.dart';
import '../core/raumerkennung.dart';
import 'models.dart';
import 'project_store.dart';
import 'tagebuch_models.dart';

/// Austausch PC ↔ App (Lastenheft Abschnitt 2 und 14):
/// - Der PC legt bei jedem Speichern eine Lesekopie `planstand/planstand.json` ab
///   (Grundriss mit Ebenen, Objekte, Einkaufsliste) – die App liest nur sie.
/// - Die App schreibt jede Erfassung als eigene Datei nach `eingang/`
///   (`<zeit>_<id>.json`, bei Fotos dazu `<zeit>_<id>.jpg`) und nie in die Datenbank.
/// - Der PC übernimmt den Eingang und verschiebt die Dateien nach `eingang/_archiv`.
const planstandDatei = 'planstand/planstand.json';
const planstandVersion = 2;

/// Netzwerkordner (NAS, Netzwerkrechner) für den Austausch – gesetzt vom
/// Programm, wenn die Speicherart „Heimnetz“ gewählt und der Ordner erreichbar
/// ist (siehe AppState). Darin liegt je Projekt ein Unterordner.
String? netzAustauschBasis;

/// Ordner für den Austausch mit der App: der Projektordner oder, bei
/// Speicherart „Heimnetz“, `<Netzwerkordner>/<Projektname>`.
String austauschOrdner(ProjectStore store) {
  final netz = netzAustauschBasis;
  return netz == null || netz.isEmpty ? store.ordner : p.join(netz, p.basename(store.ordner));
}

/// Zusätzliche Einkaufszeilen (Besorgungsliste aus der Bibliothek) – gesetzt
/// vom Programm (AppState), in Tests leer.
List<Map<String, dynamic>> Function(ProjectStore store)? zusatzEinkauf;

/// Bauelement aus Projekt oder Bibliothek als JSON – gesetzt vom Programm.
Map<String, dynamic>? Function(ProjectStore store, String id)? bauelementLesen;

/// Lesekopie des Projekts für die App (Version 2: Maße, Höhen, Wandseiten,
/// Bemaßungen, Aufmaß, Aufgaben, Einkaufsliste nach Lastenheft).
Map<String, dynamic> planstandErzeugen(ProjectStore store) {
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final gewerke = store.gewerke();
  final gewerkKuerzel = {for (final g in gewerke) g.id: g.kuerzel};
  final gewerkName = {for (final g in gewerke) g.id: g.name};
  final verbinden = store.einstellung<bool>('ecken_verbinden') ?? true;
  final gemessen = aufmassGemessen(store);
  final brandschutz = wandFeuerwiderstand(store);
  final raumName = <String, String>{};
  final produkte = {for (final pr in store.produkte()) pr.id: pr};
  final geschosse = <Map<String, dynamic>>[];
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final waende = store.waende(g.id);
      final raeume = store.raeume(g.id);
      for (final r in raeume) {
        raumName[r.id] = r.name;
      }
      final masse = wandMasse(waende, raeume, verbindenStandard: verbinden);
      final wandNach = {for (final w in waende) w.id: w};
      final hoeheRaum = {for (final r in raeume) r.id: r.hoehen(g)};
      int ffbVon(String? raumId) => (hoeheRaum[raumId] ?? g.hoehen).ffb;
      geschosse.add({
        'id': g.id,
        'name': g.name,
        'kuerzel': g.kuerzel,
        'gebaeude': geb.name,
        'ffb': g.hoehen.ffb,
        'rohdecke': g.hoehen.rohdecke,
        'meterriss': g.hoehen.meterriss - g.hoehen.ffb,
        'waende': [
          for (final w in waende)
            {
              'id': w.id,
              'a': [w.x1, w.y1],
              'b': [w.x2, w.y2],
              'd': w.dicke,
              'zustand': w.zustand.name,
              'l': w.laenge.round(),
              'li': masse[w.id]!.links.round(),
              're': masse[w.id]!.rechts.round(),
              'gr': [for (final v in [masse[w.id]!.grenzen.linksA, masse[w.id]!.grenzen.linksB, masse[w.id]!.grenzen.rechtsA, masse[w.id]!.grenzen.rechtsB]) v.round()],
              if (masse[w.id]!.raumLinks != null) 'rl': masse[w.id]!.raumLinks,
              if (masse[w.id]!.raumRechts != null) 'rr': masse[w.id]!.raumRechts,
              'sl': [for (final e in masse[w.id]!.stueckeLinks.entries) [e.key, e.value.$1.round(), e.value.$2.round()]],
              'sr': [for (final e in masse[w.id]!.stueckeRechts.entries) [e.key, e.value.$1.round(), e.value.$2.round()]],
              if (gemessen[w.id] != null) 'gemessen': gemessen[w.id],
              if (brandschutz[w.id] != null) 'brandschutz': brandschutz[w.id],
              if (w.gesperrt) 'gesperrt': true,
            }
        ],
        'oeffnungen': [
          for (final o in store.oeffnungen(g.id))
            if (wandNach[o.wandId] != null)
              {
                'id': o.id,
                'wand': o.wandId,
                'art': o.art.name,
                'abstand': o.abstand,
                'breite': o.breite,
                'hoehe': o.hoehe,
                'bruestung': o.bruestung,
                if (gemessen[o.id] != null) 'gemessen': gemessen[o.id],
              }
        ],
        'raeume': [
          for (final r in raeume)
            {
              'id': r.id,
              'name': r.name,
              'kuerzel': r.kuerzel,
              if (r.umriss != null) 'umriss': [for (final q in r.umriss!) [q.x.round(), q.y.round()]],
              if (r.flaeche != null) 'flaeche': r.flaeche!.round(),
              'hoehe': ((r.ukDecke ?? hoeheRaum[r.id]!.rohdecke) - hoeheRaum[r.id]!.ffb),
              'art': r.art.name,
              if (r.eigenschaften['schraegen'] != null) 'schraegen': r.eigenschaften['schraegen'],
              if (r.eigenschaften['verkleidung'] != null) 'verkleidung': r.eigenschaften['verkleidung'],
              if (gemessen[r.id] != null) 'gemessen': gemessen[r.id],
            }
        ],
        'sparren': [
          for (final f in sparrenfelder(store, g.id)) {...f.toJson(), if (gemessen[f.id] != null) 'gemessen': gemessen[f.id]}
        ],
        'bemassungen': [
          for (final b in store.bemassungen(g.id))
            if (!b.versteckt) {'id': b.id, 'a': [b.x1, b.y1], 'b': [b.x2, b.y2], 'abstand': b.abstand, 'l': b.laenge.round(), if (gemessen[b.id] != null) 'gemessen': gemessen[b.id]}
        ],
        'objekte': [
          for (final o in store.objekte(g.id))
            if (typen[o.typId] != null) _objektFuerApp(store, o, typen[o.typId]!, gewerkKuerzel, hoeheRaum[o.raumId] ?? g.hoehen, ffbVon(o.raumId), produkte),
          // Steigleitungen, Kamine, Treppen aus anderen Geschossen
          for (final o in durchgehendeObjekte(store, g.id))
            if (typen[o.typId] != null)
              {..._objektFuerApp(store, o, typen[o.typId]!, gewerkKuerzel, g.hoehen, g.hoehen.ffb, produkte), 'durchgehend': true}..remove('h'),
        ],
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
    'einkauf': _einkaufFuerApp(store, raumName, gewerkName, produkte),
    'aufmass': [for (final a in aufmassListe(store)) if (a['status'] == 'offen') a],
    'aufgaben': [
      for (final a in store.aufgaben())
        if (a.status != AufgabenStatus.erledigt)
          {
            'id': a.id,
            'titel': a.titel,
            if (a.beschreibung.isNotEmpty) 'text': a.beschreibung,
            if (a.raumId != null) 'raum': a.raumId,
            if (a.gewerkId != null) 'gewerk': gewerkKuerzel[a.gewerkId],
            if (a.faellig != null) 'faellig': a.faellig!.toIso8601String(),
            'status': a.status.name,
          }
    ],
  };
}

Map<String, dynamic> _objektFuerApp(ProjectStore store, Objekt o, Objekttyp t, Map<String, String> gewerkKuerzel, Bezugshoehen h,
    int ffb, Map<String, Produkt> produkte) {
  final hoehe = o.z == null ? null : absolut(o.z!, o.zBezug ?? Hoehenbezug.ffb, h) - ffb;
  final zAbs = o.eigenschaften['z_abs'];
  final belId = o.eigenschaften['bauelement'] as String?;
  final bel = belId == null ? null : bauelementLesen?.call(store, belId);
  final produkt = produkte[o.produktId];
  return {
    'id': o.id,
    'kennung': o.kennung,
    'typ': t.kuerzel,
    'name': t.name,
    'geometrie': t.geometrie.name,
    'gewerk': gewerkKuerzel[t.gewerkId] ?? '',
    'raum': o.raumId,
    'status': o.status.name,
    'lage': o.lage,
    'punkte': [for (final q in o.punkte) [q.x.round(), q.y.round()]],
    if (o.z != null) 'z': o.z,
    if (o.zBezug != null) 'z_bezug': o.zBezug!.name,
    if (hoehe != null) 'h': hoehe,
    if (zAbs is List && zAbs.length == o.punkte.length) 'hs': [for (final z in zAbs) z is num ? z.round() - ffb : null],
    if (o.punkte.length >= 2) 'laenge': o.laenge.round(),
    if (produkt != null) 'produkt': [if (produkt.hersteller != null) produkt.hersteller, produkt.name].join(' '),
    if (bel != null)
      'geraet': {
        'name': [if ('${bel['hersteller'] ?? ''}'.isNotEmpty) bel['hersteller'], bel['name']].join(' '),
        if ('${bel['artikelnummer'] ?? ''}'.isNotEmpty) 'artikel': bel['artikelnummer'],
        'daten': bel['daten'],
      },
    if (o.eigenschaften['kabel'] != null) 'kabel': o.eigenschaften['kabel'],
    if (o.eigenschaften['stromkreis'] != null) 'stromkreis': o.eigenschaften['stromkreis'],
  };
}

/// Einkaufsliste nach Lastenheft: alle offenen Positionen, gruppiert nach
/// Händler, mit Produktinfo und Händler-Link; auf dem Handy abhakbar.
List<Map<String, dynamic>> _einkaufFuerApp(ProjectStore store, Map<String, String> raumName, Map<String, String> gewerkName, Map<String, Produkt> produkte) {
  final einkauf = <Map<String, dynamic>>[];
  for (final e in einkaufsliste(store.kostenpositionen(), store.produkte(), auchUnterwegs: true).entries) {
    for (final x in e.value) {
      final pr = x.produkt;
      einkauf.add({
        'id': x.position.id,
        'quelle': 'kosten',
        'text': x.position.text,
        'menge': x.menge,
        'einheit': x.position.einheit,
        'haendler': e.key,
        if (x.angebot?.link != null) 'link': x.angebot!.link,
        'preis_cent': x.einzelCent,
        'status': x.position.status.name,
        if (x.position.raumId != null) 'raum': raumName[x.position.raumId],
        if (x.position.gewerkId != null) 'gewerk': gewerkName[x.position.gewerkId],
        if (pr != null)
          'produkt': {
            'name': pr.name,
            if (pr.hersteller != null) 'hersteller': pr.hersteller,
            if (pr.artikelnummer != null) 'artikel': pr.artikelnummer,
            if (pr.ean != null) 'ean': pr.ean,
            'angebote': [
              for (final a in pr.angebote) {'haendler': a.haendler, if (a.link != null) 'link': a.link, 'preis_cent': a.preisCent, if (a.datum != null) 'datum': a.datum}
            ],
          },
      });
    }
  }
  try {
    einkauf.addAll(zusatzEinkauf?.call(store) ?? const []);
  } catch (_) {}
  return einkauf;
}

/// Lesekopie schreiben (atomar: erst .tmp, dann umbenennen).
void planstandSchreiben(ProjectStore store) {
  final ziel = File(p.join(austauschOrdner(store), planstandDatei));
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
  final ordner = Directory(p.join(austauschOrdner(store), 'eingang'));
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
    final marken = e['markierungen'];
    if (marken is List && marken.isNotEmpty) {
      store.fotoMarkierungenSetzen(medium, [for (final m in marken) if (m is Map) Map<String, dynamic>.from(m)]);
    }
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
      final element = e['element'] as String?;
      if (element != null) {
        // Besorgungsliste: abgehakt = gekauft, Bestand erhöhen (bzw. zurücknehmen)
        final m = Map<String, dynamic>.from(store.einstellung<Map>('bestand') ?? const {});
        final menge = (e['menge'] as num?)?.toDouble() ?? 1;
        final neu = ((m[element] as num?)?.toDouble() ?? 0) + (e['erledigt'] == false ? -menge : menge);
        if (neu <= 0) {
          m.remove(element);
        } else {
          m[element] = neu;
        }
        store.einstellungSetzen('bestand', m);
        hinweise.add('${e['text'] ?? 'Artikel'} ${e['erledigt'] == false ? 'wieder offen' : 'gekauft'} ($autor)');
      } else if (id != null) {
        store.kostenpositionAendern(id, {'status': e['erledigt'] == false ? KostenStatus.geplant.name : KostenStatus.geliefert.name});
      }
    case 'aufmass':
      aufmassAblegen(store, {...e, 'autor': autor, 'zeit': zeit.toIso8601String()});
      hinweise.add('Aufmaß ${aufmassFeldText('${e['ziel']}', '${e['feld']}')}: ${e['wert']} mm ($autor)');
    case 'aufgabe':
      final id = e['aufgabe'] as String?;
      if (id != null) {
        if (e['status'] == 'erledigt') {
          store.aufgabeErledigen(id, am: zeit);
        } else if (e['status'] != null) {
          store.aufgabeAendern(id, {'status': e['status']});
        }
        if (text.isNotEmpty) store.tagebuchAnlegen(datum: zeit, text: 'Aufgabe: $text – $autor (App)', raeume: [if (raumId != null) raumId]);
      }
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
