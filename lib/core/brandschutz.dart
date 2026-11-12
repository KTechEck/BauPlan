import 'dart:math' as math;

import '../data/models.dart';
import '../data/project_store.dart';
import 'ki.dart';
import 'raumerkennung.dart';

/// Brandschutz im Plan: Feuerwiderstand je Wand (Projekteinstellung
/// `brandschutz_waende`: Wand-ID → Klasse) und feste Prüfregeln für
/// Rauchwarnmelder und Durchbrüche. Hinweise, keine Abnahme.

const feuerwiderstandsKlassen = ['–', 'F30 / EI 30', 'F60 / EI 60', 'F90 / EI 90', 'Brandwand (REI 90-M)'];

Map<String, String> wandFeuerwiderstand(ProjectStore store) =>
    {for (final e in (store.einstellung<Map>('brandschutz_waende') ?? const {}).entries) '${e.key}': '${e.value}'};

void wandFeuerwiderstandSetzen(ProjectStore store, List<String> wandIds, String? klasse) {
  final m = wandFeuerwiderstand(store);
  for (final id in wandIds) {
    if (klasse == null || klasse == '–') {
      m.remove(id);
    } else {
      m[id] = klasse;
    }
  }
  store.einstellungSetzen('brandschutz_waende', m);
}

/// Räume, in denen Rauchwarnmelder Pflicht sind (Schlafräume, Kinderzimmer,
/// Flure als Rettungsweg; in einigen Ländern alle Aufenthaltsräume).
bool rauchmelderPflicht(String raumName) {
  final n = raumName.toLowerCase();
  return RegExp(r'schlaf|kind|gäste|gast|flur|diele|gang|treppe|eltern|wohn|arbeits|büro|spiel').hasMatch(n);
}

const rauchmelderTypen = {'RW', 'WR', 'CM'};

List<PruefHinweis> brandschutzPruefen(ProjectStore store, Geschoss g, List<Raum> raeume, List<Objekt> objekte, Map<String, Objekttyp> typen) {
  final h = <PruefHinweis>[];
  final melder = [for (final o in objekte) if (rauchmelderTypen.contains(typen[o.typId]?.kuerzel) && o.punkte.isNotEmpty) o];
  final waende = store.waende(g.id);
  for (final r in raeume) {
    if (r.istBodenplatte || r.umriss == null || r.umriss!.length < 3) continue;
    final drin = [for (final o in melder) if (o.raumId == r.id || punktInPolygon(o.punkte.first, r.umriss!)) o];
    final rauch = drin.where((o) => typen[o.typId]?.kuerzel == 'RW').toList();
    if (rauchmelderPflicht(r.name) && rauch.isEmpty) {
      h.add(PruefHinweis(
          bereich: 'Brandschutz',
          text: '${g.kuerzel} ${r.name}: kein Rauchwarnmelder (Pflicht in Schlafräumen, Kinderzimmern und Fluren als Rettungsweg).'));
    }
    final flaeche = _flaeche(r.umriss!) / 1e6;
    if (rauch.isNotEmpty && flaeche > 60 * rauch.length) {
      h.add(PruefHinweis(
          bereich: 'Brandschutz',
          text: '${g.kuerzel} ${r.name}: ${flaeche.toStringAsFixed(0)} m² – ein Rauchwarnmelder überwacht höchstens 60 m².',
          objektId: rauch.first.id));
    }
    if (RegExp(r'küche|bad|dusch|wc').hasMatch(r.name.toLowerCase()) && rauch.isNotEmpty) {
      h.add(PruefHinweis(
          bereich: 'Brandschutz',
          text: '${g.kuerzel} ${r.name}: Rauchwarnmelder in Küche/Bad lösen durch Dampf leicht aus – besser Wärmemelder.',
          objektId: rauch.first.id));
    }
  }
  // Abstand zur Wand mind. 50 cm (DIN 14676)
  for (final o in melder) {
    if (typen[o.typId]?.kuerzel != 'RW') continue;
    final q = o.punkte.first;
    var d = double.infinity;
    for (final w in waende) {
      d = math.min(d, _abstand(q, w) - w.dicke / 2);
    }
    if (d < 500) {
      h.add(PruefHinweis(bereich: 'Brandschutz', text: '${o.kennung}: nur ${(d / 10).round()} cm zur Wand – mindestens 50 cm einhalten.', objektId: o.id));
    }
  }
  // Durchbrüche in Wänden mit Feuerwiderstand brauchen eine Abschottung
  final fw = wandFeuerwiderstand(store);
  if (fw.isNotEmpty) {
    final abschottungen = [for (final o in objekte) if (typen[o.typId]?.kuerzel == 'BA' && o.punkte.isNotEmpty) o.punkte.first];
    for (final o in objekte) {
      final k = typen[o.typId]?.kuerzel;
      if (k != 'WD' || o.punkte.isEmpty) continue;
      final q = o.punkte.first;
      for (final w in waende) {
        final klasse = fw[w.id];
        if (klasse == null || _abstand(q, w) > w.dicke / 2 + 150) continue;
        if (!abschottungen.any((a) => (a - q).laenge < 400)) {
          h.add(PruefHinweis(bereich: 'Brandschutz', text: '${o.kennung}: Durchbruch in Wand mit $klasse ohne Brandschutzabschottung.', objektId: o.id));
        }
      }
    }
  }
  return h;
}

double _abstand(Punkt q, Wand w) {
  final ax = w.x1.toDouble(), ay = w.y1.toDouble(), bx = w.x2.toDouble(), by = w.y2.toDouble();
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  final t = l2 < 1 ? 0.0 : (((q.x - ax) * dx + (q.y - ay) * dy) / l2).clamp(0.0, 1.0);
  final px = ax + dx * t - q.x, py = ay + dy * t - q.y;
  return math.sqrt(px * px + py * py);
}

double _flaeche(List<Punkt> u) {
  var a = 0.0;
  for (var i = 0; i < u.length; i++) {
    final p = u[i], q = u[(i + 1) % u.length];
    a += p.x * q.y - q.x * p.y;
  }
  return a.abs() / 2;
}
