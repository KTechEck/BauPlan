import 'dart:math' as math;

import '../data/models.dart';
import '../data/project_store.dart';
import 'ids.dart';
import 'raumerkennung.dart';
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
    double? t1, t2;
    for (final q in u) {
      final dx = q.x - w.x1, dy = q.y - w.y1;
      if (((dx * nx + dy * ny) - soll).abs() > 6) continue;
      final t = dx * ux + dy * uy;
      t1 = t1 == null ? t : math.min(t1, t);
      t2 = t2 == null ? t : math.max(t2, t);
    }
    if (t1 != null && t2 != null && t2 - t1 > 50) aus[r.id] = (t1, t2);
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
  for (var i = 0; i < waende.length; i++) {
    final w = waende[i];
    final g = flankenGrenzen(achsen[i], (w.verbinden ?? verbindenStandard) ? nachbarn : [achsen[i]]);
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
  if (id == null || wert == null || wert <= 0) return 'Kein gültiger Wert.';
  final plan = aufmassPlanwert(store, a);
  if (plan == null) return 'Das Bauteil gibt es im Plan nicht mehr.';
  switch (a['ziel']) {
    case 'wand':
      if (feld == 'dicke') {
        store.wandAendern(id, dicke: wert);
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
    default:
      return 'Unbekanntes Ziel.';
  }
  _gemessenMerken(store, id, '$feld${a['bezug'] == null ? '' : '_${a['bezug']}'}', wert);
  aufmassStatusSetzen(store, a['nr'] as String, 'uebernommen');
  return null;
}
