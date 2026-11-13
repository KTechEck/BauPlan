import 'dart:convert';
import 'dart:math' as math;

import '../data/models.dart';
import '../data/project_store.dart';
import 'height.dart';
import 'ids.dart';
import 'raumerkennung.dart';
import 'sparren.dart';
import 'wandmasse.dart';

/// Aufmaß: Am PC wird grob gezeichnet, auf der Baustelle misst man mit dem
/// Handy (später iPad) nach, am PC werden die Maße geprüft und übernommen.
///
/// Die App schickt jedes gemessene Maß als Erfassung `art: aufmass` mit
/// `ziel` (wand, oeffnung, raum, bemassung), `id`, `feld`, `wert` (mm),
/// bei Wandlängen zusätzlich `bezug` (innen, aussen, achse) und `seite`
/// (l/r = Wandseite links/rechts der Zeichenrichtung). Der PC legt die Maße in
/// der Projekteinstellung `aufmass` ab (Status offen, übernommen, verworfen).
/// Was übernommen wurde, steht in `aufmass_gemessen` (Ziel-ID → Feld → Wert).

/// Seitenlängen, Seiten-Grenzen und Räume beiderseits einer Wand.
typedef WandMasse = ({
  double achse,
  double links,
  double rechts,
  ({double linksA, double linksB, double rechtsA, double rechtsB}) grenzen,
  String? raumLinks,
  String? raumRechts,
  Map<String, (double, double)> stueckeLinks,
  Map<String, (double, double)> stueckeRechts,
});

/// Stücke einer Wandseite, die an Räume grenzen (Raum-ID → von/bis entlang der
/// Achse ab A). Eine lange Außenwand grenzt so z. B. an zwei Zimmer; gemessen
/// wird im Raum nur das eigene Stück (von Wand zu Wand).
Map<String, (double, double)> raumStuecke(Wand w, bool links, List<Raum> raeume) {
  final l = math.max(1.0, w.laenge);
  final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
  final nx = uy, ny = -ux; // links der Zeichenrichtung
  final soll = (links ? 1 : -1) * w.dicke / 2;
  final aus = <String, (double, double)>{};
  for (final r in raeume) {
    final u = r.umriss;
    if (u == null || u.length < 3) continue;
    // Umrisskanten, die auf dieser Wandseite liegen (beide Enden auf der Flankenlinie)
    final stuecke = <(double, double)>[];
    for (var i = 0; i < u.length; i++) {
      final p = u[i], q = u[(i + 1) % u.length];
      double quer(Punkt x) => ((x.x - w.x1) * nx + (x.y - w.y1) * ny) - soll;
      if (quer(p).abs() > 6 || quer(q).abs() > 6) continue;
      final tp = (p.x - w.x1) * ux + (p.y - w.y1) * uy, tq = (q.x - w.x1) * ux + (q.y - w.y1) * uy;
      // Kante nicht auf die Wand kürzen: Besteht die Wand aus mehreren geraden
      // Stücken, gilt die ganze lichte Raumkante (eine Länge je Raumseite).
      final a = math.min(tp, tq), b = math.max(tp, tq);
      final ueberlapp = math.min(b, l) - math.max(a, 0.0);
      if (b - a > 50 && ueberlapp > 50) stuecke.add((a, b));
    }
    if (stuecke.isEmpty) continue;
    // zusammenhängende Stücke vereinen, das längste gilt (eine Messstrecke je Raumseite)
    stuecke.sort((x, y) => x.$1.compareTo(y.$1));
    var best = stuecke.first, akt = stuecke.first;
    for (final s in stuecke.skip(1)) {
      if (s.$1 <= akt.$2 + 2) {
        akt = (akt.$1, math.max(akt.$2, s.$2));
      } else {
        akt = s;
      }
      if (akt.$2 - akt.$1 > best.$2 - best.$1) best = akt;
    }
    if (akt.$2 - akt.$1 > best.$2 - best.$1) best = akt;
    aus[r.id] = best;
  }
  return aus;
}

/// Maße aller Wände eines Geschosses (Gehrung wie im Grundriss).
Map<String, WandMasse> wandMasse(List<Wand> waende, List<Raum> raeume, {bool verbindenStandard = true}) {
  final achsen = [for (final w in waende) w.achse];
  final nachbarn = [
    for (var i = 0; i < waende.length; i++)
      if (waende[i].verbinden ?? verbindenStandard) achsen[i]
  ];
  final aus = <String, WandMasse>{};
  final gesehen = <String>{};
  for (var i = 0; i < waende.length; i++) {
    final w = waende[i];
    final g = flankenGrenzen(achsen[i], (w.verbinden ?? verbindenStandard) ? nachbarn : [achsen[i]], masse: true);
    final l = math.max(1.0, w.laenge);
    final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
    String? raumAuf(double s, double tA, double tB) {
      final t = (tA + tB) / 2;
      final q = Punkt(w.x1 + ux * t + uy * s * (w.dicke / 2 + 150), w.y1 + uy * t - ux * s * (w.dicke / 2 + 150));
      for (final r in raeume) {
        if (r.umriss != null && r.umriss!.length >= 3 && punktInPolygon(q, r.umriss!)) return r.id;
      }
      return null;
    }

    final sl = raumStuecke(w, true, raeume), sr = raumStuecke(w, false, raeume);
    // Gleiche Raumkante an mehreren geraden Wandstücken nur einmal (beim ersten Stück)
    for (final (st, links) in [(sl, true), (sr, false)]) {
      for (final e in st.entries.toList()) {
        final ux = (w.x2 - w.x1) / math.max(1.0, w.laenge), uy = (w.y2 - w.y1) / math.max(1.0, w.laenge);
        final s0 = (links ? 1 : -1) * w.dicke / 2;
        final key = '${e.key}|${_rund(w.x1 + ux * e.value.$1 + uy * s0)}|${_rund(w.y1 + uy * e.value.$1 - ux * s0)}|'
            '${_rund(w.x1 + ux * e.value.$2 + uy * s0)}|${_rund(w.y1 + uy * e.value.$2 - ux * s0)}';
        final key2 = '${e.key}|${key.split('|').sublist(3).join('|')}|${key.split('|').sublist(1, 3).join('|')}';
        if (gesehen.contains(key) || gesehen.contains(key2)) {
          st.remove(e.key);
        } else {
          gesehen.add(key);
        }
      }
    }
    String? groesster(Map<String, (double, double)> m) =>
        m.isEmpty ? null : (m.entries.toList()..sort((a, b) => (b.value.$2 - b.value.$1).compareTo(a.value.$2 - a.value.$1))).first.key;
    aus[w.id] = (
      stueckeLinks: sl,
      stueckeRechts: sr,
      achse: w.laenge,
      links: g.linksB - g.linksA,
      rechts: g.rechtsB - g.rechtsA,
      grenzen: g,
      raumLinks: groesster(sl) ?? raumAuf(1, g.linksA, g.linksB),
      raumRechts: groesster(sr) ?? raumAuf(-1, g.rechtsA, g.rechtsB),
    );
  }
  return aus;
}

/// Bezeichnung eines Feldes für Listen.
String aufmassFeldText(String ziel, String feld) => switch ((ziel, feld)) {
      ('wand', 'laenge') => 'Wandlänge',
      ('wand', 'dicke') => 'Wanddicke',
      ('oeffnung', 'breite') => 'Öffnungsbreite',
      ('oeffnung', 'hoehe') => 'Öffnungshöhe',
      ('oeffnung', 'bruestung') => 'Brüstung',
      ('oeffnung', 'abstand') => 'Abstand Öffnung',
      ('raum', 'hoehe') => 'lichte Raumhöhe',
      ('bemassung', _) => 'Bemaßung',
      ('raumseite', _) => 'Raumlänge an der Wand',
      ('diagonale', _) => 'Diagonale (Winkel)',
      ('sparren', 'neu') => 'Neues Sparrenfeld',
      ('sparren', _) => 'Sparren: ${feld.startsWith('pos_') ? 'Lage Sparren ${int.parse(feld.substring(4)) + 1}' : sparrenFelder[feld] ?? feld}',
      ('schraege', 'kniestock') => 'Dachschräge: Kniestock',
      ('schraege', 'tiefe') => 'Dachschräge: Tiefe bis waagrechte Decke',
      ('schraege', 'decke') => 'Dachschräge: Höhe waagrechte Decke',
      ('verkleidung', _) => 'Wandverkleidung (je Seite)',
      ('objekt', 'h') => 'Höhe Gerät über FFB',
      ('objekt', 'x') => 'Gerät ab Wandecke',
      _ => feld,
    };

List<Map<String, dynamic>> aufmassListe(ProjectStore store) =>
    [for (final x in store.einstellung<List>('aufmass') ?? const []) Map<String, dynamic>.from(x as Map)];

int aufmassOffen(ProjectStore store) => aufmassListe(store).where((a) => a['status'] == 'offen').length;

/// Neues Aufmaß aus dem Eingang ablegen (älteres offenes Maß für dasselbe Ziel wird ersetzt).
void aufmassAblegen(ProjectStore store, Map<String, dynamic> e) {
  final liste = aufmassListe(store)
    ..removeWhere((a) => a['status'] == 'offen' && a['ziel'] == e['ziel'] && a['id_ziel'] == e['id'] && a['feld'] == e['feld'] && a['seite'] == e['seite'] && a['bezug'] == e['bezug']);
  liste.add({
    'nr': neueId(),
    'ziel': e['ziel'],
    'id_ziel': e['id'],
    'feld': e['feld'],
    'wert': (e['wert'] as num?)?.round(),
    if (e['bezug'] != null) 'bezug': e['bezug'],
    if (e['seite'] != null) 'seite': e['seite'],
    if (e['plan'] != null) 'plan': (e['plan'] as num).round(),
    'geschoss': e['geschoss'],
    if (e['raum'] != null) 'raum': e['raum'],
    if (e['text'] != null) 'text': e['text'],
    if (e['von'] != null) 'von': e['von'],
    if (e['bis'] != null) 'bis': e['bis'],
    if (e['wand'] != null) 'wand': e['wand'],
    if (e['ecken'] != null) 'ecken': e['ecken'],
    if (e['feld_json'] != null) 'feld_json': e['feld_json'],
    'autor': e['autor'] ?? 'App',
    'zeit': e['zeit'] ?? DateTime.now().toIso8601String(),
    'status': 'offen',
  });
  store.einstellungSetzen('aufmass', liste);
}

void aufmassStatusSetzen(ProjectStore store, String nr, String status) {
  final liste = aufmassListe(store);
  for (final a in liste) {
    if (a['nr'] == nr) a['status'] = status;
  }
  store.einstellungSetzen('aufmass', liste);
}

/// Gemessene (übernommene) Maße je Ziel: id → feld → wert.
Map<String, Map<String, dynamic>> aufmassGemessen(ProjectStore store) => {
      for (final e in (store.einstellung<Map>('aufmass_gemessen') ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map),
    };

void _gemessenMerken(ProjectStore store, String id, String feld, int wert) {
  final m = aufmassGemessen(store);
  (m[id] ??= {})[feld] = wert;
  store.einstellungSetzen('aufmass_gemessen', m);
}

/// Aktueller Planwert für ein Aufmaß (zum Vergleich), null wenn das Ziel fehlt.
double? aufmassPlanwert(ProjectStore store, Map<String, dynamic> a) {
  final id = a['id_ziel'] as String?;
  final feld = a['feld'] as String?;
  final gid = a['geschoss'] as String?;
  if (id == null || feld == null) return null;
  switch (a['ziel']) {
    case 'wand':
      final g = gid ?? _geschossVonWand(store, id);
      if (g == null) return null;
      final waende = store.waende(g);
      final w = waende.where((x) => x.id == id).firstOrNull;
      if (w == null) return null;
      if (feld == 'dicke') return w.dicke.toDouble();
      final m = wandMasse(waende, const [], verbindenStandard: store.einstellung<bool>('ecken_verbinden') ?? true)[id]!;
      return switch (a['bezug']) {
        'achse' => m.achse,
        'aussen' => math.max(m.links, m.rechts),
        _ => a['seite'] == 'l' ? m.links : (a['seite'] == 'r' ? m.rechts : math.min(m.links, m.rechts)),
      };
    case 'oeffnung':
      final o = store.alleOeffnungen().where((x) => x.id == id).firstOrNull;
      if (o == null) return null;
      return switch (feld) { 'breite' => o.breite, 'hoehe' => o.hoehe, 'bruestung' => o.bruestung, _ => o.abstand }.toDouble();
    case 'raum':
      for (final geb in store.gebaeude()) {
        for (final g in store.geschosse(geb.id)) {
          final r = store.raeume(g.id).where((x) => x.id == id).firstOrNull;
          if (r != null) {
            final h = r.hoehen(g);
            return ((r.ukDecke ?? h.rohdecke) - h.ffb).toDouble();
          }
        }
      }
      return null;
    case 'bemassung':
      for (final geb in store.gebaeude()) {
        for (final g in store.geschosse(geb.id)) {
          final b = store.bemassungen(g.id).where((x) => x.id == id).firstOrNull;
          if (b != null) return b.laenge;
        }
      }
      return null;
    case 'raumseite':
      final st = _raumStueck(store, a);
      return st == null ? null : st.$3 - st.$2;
    case 'objekt':
      return _objektMass(store, a)?.wert;
    case 'diagonale':
      final d = _diagonale(store, a);
      return d == null ? null : (d.p[d.i] - d.p[d.j]).laenge;
    case 'sparren':
      if (feld == 'neu') return 0;
      final f = _sparrenfeld(store, id);
      if (f == null) return null;
      if (feld.startsWith('pos_')) {
        final i = int.tryParse(feld.substring(4)) ?? 0;
        return i < f.$1.lagen.length ? f.$1.lagen[i] : 0;
      }
      return (f.$1.toJson()[feld] as num?)?.toDouble();
    case 'verkleidung':
      final r = _raum(store, id);
      return r == null ? null : ((r.$1.eigenschaften['verkleidung'] as Map?)?['dicke'] as num?)?.toDouble() ?? 0;
    case 'schraege':
      final r = _raum(store, id);
      if (r == null) return null;
      final v = (raumSchraegen(r.$1)['${a['wand']}|${a['seite']}'] ?? const {})[feld];
      return (v as num?)?.toDouble() ?? 0;
  }
  return null;
}

(Sparrenfeld, String)? _sparrenfeld(ProjectStore store, String id) {
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final f = sparrenfelder(store, g.id).where((x) => x.id == id).firstOrNull;
      if (f != null) return (f, g.id);
    }
  }
  return null;
}

(Raum, Geschoss)? _raum(ProjectStore store, String id) {
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final r = store.raeume(g.id).where((x) => x.id == id).firstOrNull;
      if (r != null) return (r, g);
    }
  }
  return null;
}

/// Dachschrägen eines Raums je Wandseite („wandId|l/r“ → kniestock, tiefe,
/// decke in mm über FFB bzw. waagrecht ab Wand). Ungleiche Schrägen auf beiden
/// Seiten und Schräge mit waagrechter Decke gehen damit.
Map<String, Map<String, dynamic>> raumSchraegen(Raum r) => {
      for (final e in (r.eigenschaften['schraegen'] as Map? ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map),
    };

/// Ecke B zwischen den Diagonal-Enden A (i) und C (j) im Raumumriss.
({List<Punkt> p, int i, int j, int b, String g})? _diagonale(ProjectStore store, Map<String, dynamic> a) {
  final e = a['ecken'];
  if (e is! List || e.length != 2) return null;
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final r = store.raeume(g.id).where((x) => x.id == a['id_ziel']).firstOrNull;
      final u = r?.umriss;
      if (u == null || u.length < 4) continue;
      final i = (e[0] as num).toInt(), j = (e[1] as num).toInt();
      final n = u.length;
      if (i >= n || j >= n) return null;
      final b = (i + 1) % n == (j - 1 + n) % n ? (i + 1) % n : ((j + 1) % n == (i - 1 + n) % n ? (j + 1) % n : -1);
      if (b < 0) return null;
      return (p: u, i: i, j: j, b: b, g: g.id);
    }
  }
  return null;
}

/// Winkel an Ecke B aus den Seiten AB, BC und der gemessenen Diagonale (Kosinussatz).
double? diagonalWinkel(double ab, double bc, double diagonale) {
  final c = (ab * ab + bc * bc - diagonale * diagonale) / (2 * ab * bc);
  if (c.abs() > 1) return null;
  return math.acos(c) * 180 / math.pi;
}

/// Erklärender Text für den Dialog: welcher Winkel sich aus der Diagonale ergibt.
String? diagonaleText(ProjectStore store, Map<String, dynamic> a) {
  final d = _diagonale(store, a);
  final w = (a['wert'] as num?)?.toDouble();
  if (d == null || w == null) return null;
  final x = diagonalWinkel((d.p[d.i] - d.p[d.b]).laenge, (d.p[d.j] - d.p[d.b]).laenge, w);
  return x == null ? 'Diagonale passt nicht zu den Seitenlängen' : 'Winkel an der Ecke ${x.toStringAsFixed(1).replaceAll('.', ',')}°';
}

/// Aktuelle Lage eines Geräts: Höhe über FFB oder Abstand ab Wandecke (Wandseite wie in der App).
({double wert, Objekt o, Wand? w, double ux, double uy, double s})? _objektMass(ProjectStore store, Map<String, dynamic> a) {
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final o = store.objekte(g.id).where((x) => x.id == a['id_ziel']).firstOrNull;
      if (o == null || o.punkte.isEmpty) continue;
      final raum = store.raeume(g.id).where((r) => r.id == o.raumId).firstOrNull;
      final h = raum?.hoehen(g) ?? g.hoehen;
      if (a['feld'] == 'h') {
        if (o.z == null) return (wert: 0, o: o, w: null, ux: 0, uy: 0, s: 0);
        return (wert: (absolut(o.z!, o.zBezug ?? Hoehenbezug.ffb, h) - h.ffb).toDouble(), o: o, w: null, ux: 0, uy: 0, s: 0);
      }
      final w = store.waende(g.id).where((x) => x.id == a['wand']).firstOrNull;
      if (w == null) return null;
      final m = wandMasse(store.waende(g.id), const [], verbindenStandard: store.einstellung<bool>('ecken_verbinden') ?? true)[w.id]!;
      final l = math.max(1.0, w.laenge);
      final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
      final t = (o.punkte.first.x - w.x1) * ux + (o.punkte.first.y - w.y1) * uy;
      final links = a['seite'] == 'l';
      final x = links ? m.grenzen.linksB - t : t - m.grenzen.rechtsA;
      return (wert: x, o: o, w: w, ux: ux, uy: uy, s: links ? -1.0 : 1.0);
    }
  }
  return null;
}

/// Wand, Anfang und Ende des Raumstücks (entlang der Achse) für ein Aufmaß „raumseite“.
(Wand, double, double, String)? _raumStueck(ProjectStore store, Map<String, dynamic> a) {
  final id = a['id_ziel'] as String?;
  final raumId = a['raum'] as String?;
  final g = (a['geschoss'] as String?) ?? (id == null ? null : _geschossVonWand(store, id));
  if (id == null || raumId == null || g == null) return null;
  final w = store.waende(g).where((x) => x.id == id).firstOrNull;
  if (w == null) return null;
  final st = raumStuecke(w, a['seite'] == 'l', store.raeume(g))[raumId];
  return st == null ? null : (w, st.$1, st.$2, g);
}

String? _geschossVonWand(ProjectStore store, String id) {
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      if (store.waende(g.id).any((w) => w.id == id)) return g.id;
    }
  }
  return null;
}

/// Übernimmt ein Aufmaß in den Plan. Liefert eine Fehlermeldung oder null.
String? aufmassAnwenden(ProjectStore store, Map<String, dynamic> a) {
  final id = a['id_ziel'] as String?;
  final feld = a['feld'] as String? ?? '';
  final wert = (a['wert'] as num?)?.round();
  if (id == null || wert == null || wert < 0 || (wert == 0 && a['ziel'] != 'verkleidung' && !(a['ziel'] == 'sparren' && (feld == 'neu' || feld.startsWith('pos_') || feld == 'erster')))) {
    return 'Kein gültiger Wert.';
  }
  final plan = aufmassPlanwert(store, a);
  if (plan == null) return 'Das Bauteil gibt es im Plan nicht mehr.';
  switch (a['ziel']) {
    case 'wand':
      if (feld == 'dicke') {
        final w = store.waende((a['geschoss'] as String?) ?? _geschossVonWand(store, id) ?? '').where((x) => x.id == id).firstOrNull;
        if (w == null) return 'Wand nicht gefunden.';
        wandDickeMitInnenmass(store, w, () => store.wandAendern(id, dicke: wert));
      } else {
        final g = (a['geschoss'] as String?) ?? _geschossVonWand(store, id);
        final w = g == null ? null : store.waende(g).where((x) => x.id == id).firstOrNull;
        if (w == null) return 'Wand nicht gefunden.';
        if (w.gesperrt) return 'Die Wand ist gesperrt.';
        final neueAchse = (w.laenge + wert - plan).round();
        if (neueAchse <= 0) return 'Die Wand würde kürzer als null.';
        if ((neueAchse - w.laenge).abs() >= 1 && store.wandLaengeAendern(id, neueAchse).isEmpty) {
          return 'Länge ließ sich nicht setzen (Nachbarwand gesperrt?).';
        }
      }
    case 'oeffnung':
      final spalte = switch (feld) { 'breite' => 'breite_mm', 'hoehe' => 'hoehe_mm', 'bruestung' => 'bruestung_mm', _ => 'abstand_mm' };
      store.oeffnungAendern(id, {spalte: wert});
    case 'raum':
      for (final geb in store.gebaeude()) {
        for (final g in store.geschosse(geb.id)) {
          final r = store.raeume(g.id).where((x) => x.id == id).firstOrNull;
          if (r != null) store.raumHoehenSetzen(id, ukDecke: r.hoehen(g).ffb + wert);
        }
      }
    case 'bemassung':
      if (store.bemassungAendern(id, wert) == null) return 'Bemaßung ließ sich nicht ändern.';
    case 'raumseite':
      // Raumlänge an einer langen Wand: wie eine Bemaßung im Raum von Wand zu
      // Wand – die quer stehende Wand am Ende wandert.
      final st = _raumStueck(store, a);
      if (st == null) return 'Raum oder Wand nicht gefunden.';
      final (w, t1, t2, g) = st;
      final l = math.max(1.0, w.laenge);
      final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
      final s = a['seite'] == 'l' ? 1.0 : -1.0;
      final ab = w.dicke / 2 + 300; // 30 cm in den Raum hinein
      int x(double t) => (w.x1 + ux * t + uy * s * ab).round();
      int y(double t) => (w.y1 + uy * t - ux * s * ab).round();
      // Es wandert das Ende mit der Innenwand (Außenwände sind meist richtig
      // gezeichnet); bemassungAendern bewegt das Ende b.
      final raeume = store.raeume(g);
      bool innenwandBei(double t) {
        final px = x(t).toDouble(), py = y(t).toDouble();
        for (final v in store.waende(g)) {
          if (v.id == w.id) continue;
          final dx = v.x2 - v.x1, dy = v.y2 - v.y1;
          final l2 = (dx * dx + dy * dy).toDouble();
          if (l2 < 1) continue;
          final tt = (((px - v.x1) * dx + (py - v.y1) * dy) / l2).clamp(0.0, 1.0);
          final ex = v.x1 + dx * tt - px, ey = v.y1 + dy * tt - py;
          if (math.sqrt(ex * ex + ey * ey) > v.dicke / 2 + 320) continue;
          return raumStuecke(v, true, raeume).isNotEmpty && raumStuecke(v, false, raeume).isNotEmpty;
        }
        return false;
      }

      final umdrehen = innenwandBei(t1) && !innenwandBei(t2);
      final (ta, tb) = umdrehen ? (t2, t1) : (t1, t2);
      final b = store.bemassungAnlegen(geschossId: g, x1: x(ta), y1: y(ta), x2: x(tb), y2: y(tb), abstand: 0);
      final ok = store.bemassungAendern(b, wert) != null;
      store.bemassungLoeschen(b);
      if (!ok) return 'Raumlänge ließ sich nicht setzen (Wand gesperrt?).';
    case 'sparren':
      if (feld == 'neu') {
        final j = a['feld_json'];
        final g = a['geschoss'] as String?;
        if (j is! Map || g == null) return 'Sparrenfeld unvollständig.';
        final l = sparrenfelder(store, g)..removeWhere((x) => x.id == id);
        sparrenfelderSetzen(store, g, [...l, Sparrenfeld.ausJson({...j, 'id': id})]);
      } else {
        final f = _sparrenfeld(store, id);
        if (f == null) return 'Sparrenfeld fehlt – zuerst „Neues Sparrenfeld“ übernehmen.';
        sparrenfelderSetzen(store, f.$2, [for (final x in sparrenfelder(store, f.$2)) x.id == id ? x.mitWert(feld, wert) : x]);
      }
    case 'verkleidung':
      final r = _raum(store, id);
      if (r == null) return 'Raum nicht gefunden.';
      store.raumEigenschaftenSetzen(id, {...r.$1.eigenschaften, 'verkleidung': {'art': a['text'] ?? '', 'dicke': wert}});
    case 'schraege':
      final r = _raum(store, id);
      if (r == null) return 'Raum nicht gefunden.';
      final m = raumSchraegen(r.$1);
      (m['${a['wand']}|${a['seite']}'] ??= {})[feld] = wert;
      store.raumEigenschaftenSetzen(id, {...r.$1.eigenschaften, 'schraegen': m});
    case 'diagonale':
      final d = _diagonale(store, a);
      if (d == null) return 'Raumecken nicht gefunden (Raum geändert?).';
      final winkel = diagonalWinkel((d.p[d.i] - d.p[d.b]).laenge, (d.p[d.j] - d.p[d.b]).laenge, wert.toDouble());
      if (winkel == null) return 'Die Diagonale passt nicht zu den Seitenlängen – erst die Wandlängen übernehmen.';
      // Wände an Ecke B: die, deren Achse den Seitenmitten AB und BC am nächsten liegt
      final waende = store.waende(d.g);
      Wand? naechste(Punkt q) {
        Wand? best;
        var bd = double.infinity;
        for (final w in waende) {
          final dx = (w.x2 - w.x1).toDouble(), dy = (w.y2 - w.y1).toDouble();
          final l2 = dx * dx + dy * dy;
          if (l2 < 1) continue;
          final t = (((q.x - w.x1) * dx + (q.y - w.y1) * dy) / l2).clamp(0.0, 1.0);
          final ex = w.x1 + dx * t - q.x, ey = w.y1 + dy * t - q.y;
          final dd = math.sqrt(ex * ex + ey * ey);
          if (dd < bd) {
            bd = dd;
            best = w;
          }
        }
        return best;
      }

      Punkt mitte(Punkt p, Punkt q) => Punkt((p.x + q.x) / 2, (p.y + q.y) / 2);
      final w1 = naechste(mitte(d.p[d.i], d.p[d.b])), w2 = naechste(mitte(d.p[d.j], d.p[d.b]));
      if (w1 == null || w2 == null || w1.id == w2.id) return 'Wände an der Ecke nicht gefunden.';
      final m = store.winkelmassAnlegen(d.g, w1.id, w2.id);
      if (store.winkelAendern(m, winkel) == null) {
        store.winkelmassLoeschen(m);
        return 'Winkel ließ sich nicht setzen (Wände gesperrt?).';
      }
    case 'objekt':
      final om = _objektMass(store, a);
      if (om == null) return 'Gerät oder Wand nicht gefunden.';
      if (feld == 'h') {
        store.objektAendern(id, {'z_mm': wert, 'z_bezug': Hoehenbezug.ffb.name});
      } else {
        // entlang der Wand verschieben (x der Ansicht läuft auf Seite l gegen die Zeichenrichtung)
        final d = (wert - om.wert) * om.s;
        final q = om.o.punkte.first;
        store.objektAendern(id, {'geometrie': jsonEncode([[(q.x + om.ux * d).round(), (q.y + om.uy * d).round()]])});
      }
    default:
      return 'Unbekanntes Ziel.';
  }
  _gemessenMerken(store, id, '$feld${a['bezug'] == null ? '' : '_${a['bezug']}'}', wert);
  aufmassStatusSetzen(store, a['nr'] as String, 'uebernommen');
  return null;
}

/// Welche Wandseite bei einer Dickenänderung fest bleibt (Projekteinstellung
/// `dicke_fest`: auto, links, rechts, mitte). Automatisch: bei Außenwänden die
/// Raumseite, zwischen zwei Räumen die Seite des kleineren Raums (z. B. Bad).
int festeSeite(ProjectStore store, Wand w) {
  switch (store.einstellung<String>('dicke_fest') ?? 'auto') {
    case 'mitte':
      return 0;
    case 'links':
      return 1;
    case 'rechts':
      return -1;
  }
  final raeume = store.raeume(w.geschossId);
  final m = wandMasse(store.waende(w.geschossId), raeume, verbindenStandard: store.einstellung<bool>('ecken_verbinden') ?? true)[w.id];
  if (m == null) return 0;
  final l = m.raumLinks, r = m.raumRechts;
  if (l != null && r == null) return 1;
  if (r != null && l == null) return -1;
  if (l == null || r == null) return 0;
  double f(String id) => raeume.where((x) => x.id == id).firstOrNull?.flaeche ?? double.infinity;
  return f(l) <= f(r) ? 1 : -1;
}

/// Dicke ändern und dabei das lichte Maß halten (siehe [festeSeite]).
void wandDickeMitInnenmass(ProjectStore store, Wand w, void Function() aendern) {
  final fest = festeSeite(store, w);
  aendern();
  final neu = store.waende(w.geschossId).where((x) => x.id == w.id).firstOrNull;
  if (neu != null) store.wandDickeVersetzen(w.id, w.dicke, neu.dicke, fest);
}

/// Wandverkleidung eines Raums (mm je Wandseite), 0 = keine.
int raumVerkleidung(Raum r) => ((r.eigenschaften['verkleidung'] as Map?)?['dicke'] as num?)?.round() ?? 0;

int _rund(double v) => (v / 20).round(); // 2 cm Raster für den Vergleich gleicher Kanten
