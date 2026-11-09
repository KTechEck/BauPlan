import 'dart:math' as math;
import 'dart:convert';

import 'bauelemente.dart';

/// Einkäufe und Bestand: was gekauft wurde (z. B. vom Kassenzettel) und was
/// noch auf der Baustelle liegt. Gespeichert in den Projekteinstellungen
/// `einkaeufe` (Liste) und `bestand` (Element-ID → Menge).

class EinkaufPosition {
  EinkaufPosition({required this.text, this.menge = 1, this.einheit = 'Stk', this.preisCent, this.elementId});
  String text;
  double menge;
  String einheit;
  int? preisCent; // Gesamtpreis der Zeile (brutto)
  String? elementId;

  Map<String, dynamic> toJson() => {'text': text, 'menge': menge, 'einheit': einheit, 'preis_cent': preisCent, 'element': elementId};
  static EinkaufPosition ausJson(Map<String, dynamic> m) => EinkaufPosition(
        text: m['text'] as String? ?? '',
        menge: (m['menge'] as num?)?.toDouble() ?? 1,
        einheit: m['einheit'] as String? ?? 'Stk',
        preisCent: (m['preis_cent'] as num?)?.toInt(),
        elementId: m['element'] as String?,
      );
}

class Einkauf {
  Einkauf({required this.id, required this.datum, this.haendler = '', required this.positionen, this.beleg});
  final String id;
  final DateTime datum;
  final String haendler;
  final List<EinkaufPosition> positionen;
  final String? beleg; // Dateiname des Belegs im Projektordner

  int get summeCent => positionen.fold(0, (s, p) => s + (p.preisCent ?? 0));

  Map<String, dynamic> toJson() => {
        'id': id,
        'datum': datum.toIso8601String(),
        'haendler': haendler,
        'positionen': [for (final p in positionen) p.toJson()],
        if (beleg != null) 'beleg': beleg,
      };

  static Einkauf ausJson(Map<String, dynamic> m) => Einkauf(
        id: m['id'] as String,
        datum: DateTime.tryParse(m['datum'] as String? ?? '') ?? DateTime.now(),
        haendler: m['haendler'] as String? ?? '',
        positionen: [for (final p in (m['positionen'] as List? ?? const [])) EinkaufPosition.ausJson(Map<String, dynamic>.from(p as Map))],
        beleg: m['beleg'] as String?,
      );
}

/// Kassenzettel-Text ohne KI lesen: Zeilen mit Betrag am Ende, Mengen wie
/// „3 x“ oder „2 St“ am Anfang. Summen-, Steuer- und Zahlungszeilen fallen weg.
List<EinkaufPosition> kassenzettelLesen(String text) {
  final weg = RegExp(r'summe|gesamt|total|mwst|ust|steuer|bar|ec[- ]?karte|kartenzahlung|rückgeld|gegeben|netto|brutto|zwischensumme|rabatt gesamt',
      caseSensitive: false);
  final l = <EinkaufPosition>[];
  for (final roh in const LineSplitter().convert(text)) {
    final z = roh.trim();
    if (z.length < 3 || weg.hasMatch(z)) continue;
    final preis = RegExp(r'(-?\d{1,5}[.,]\d{2})\s*(?:€|EUR|[AB]|\*)?\s*$').firstMatch(z);
    if (preis == null) continue;
    var rest = z.substring(0, preis.start).trim().replaceAll(RegExp(r'^\d{5,}\s+'), ''); // Artikelnummer vorne
    var menge = 1.0;
    var einheit = 'Stk';
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(x|×|st\.?|stk\.?|m|lfm|pak|pck|rolle)\s+', caseSensitive: false).firstMatch(rest);
    if (m != null) {
      menge = double.parse(m.group(1)!.replaceAll(',', '.'));
      final e = m.group(2)!.toLowerCase();
      einheit = e.startsWith('m') || e == 'lfm' ? 'm' : (e.startsWith('rol') ? 'Rolle' : (e.startsWith('p') ? 'Packung' : 'Stk'));
      rest = rest.substring(m.end).trim();
    }
    rest = rest.replaceAll(RegExp(r'\s{2,}'), ' ').replaceAll(RegExp(r'^\d{5,}\s+'), ''); // Artikelnummer vorne
    if (rest.isEmpty) continue;
    final cent = (double.parse(preis.group(1)!.replaceAll(',', '.')) * 100).round();
    l.add(EinkaufPosition(text: rest, menge: menge, einheit: einheit, preisCent: cent));
  }
  return l;
}

/// Anweisung an das Sprachmodell (Text oder Bild des Belegs).
const kiKassenzettelAnfrage = 'Das ist ein Kassenzettel oder eine Rechnung eines Baumarkts. Gib NUR ein JSON-Objekt zurück: '
    '{"haendler": "...", "datum": "JJJJ-MM-TT", "positionen": [{"text": "Artikelbezeichnung", "menge": Zahl, "einheit": "Stk|m|m²|Packung|Rolle|Platte|Sack|kg|l", "preis": Gesamtpreis der Zeile in Euro als Zahl}]}. '
    'Summen, Steuer, Pfand und Zahlungszeilen weglassen. Nichts erfinden.';

/// Antwort der KI zum Kassenzettel lesen.
({String haendler, DateTime? datum, List<EinkaufPosition> positionen})? kiKassenzettelLesen(String antwort) {
  final m = kiJsonLesen(antwort);
  if (m == null) return null;
  final pos = <EinkaufPosition>[];
  for (final p in (m['positionen'] as List? ?? const [])) {
    if (p is! Map) continue;
    final text = '${p['text'] ?? ''}'.trim();
    if (text.isEmpty) continue;
    num? z(Object? v) => v is num ? v : num.tryParse('$v'.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.\-]'), ''));
    final preis = z(p['preis']);
    pos.add(EinkaufPosition(
      text: text,
      menge: (z(p['menge']) ?? 1).toDouble(),
      einheit: '${p['einheit'] ?? 'Stk'}',
      preisCent: preis == null ? null : (preis * 100).round(),
    ));
  }
  return (haendler: '${m['haendler'] ?? ''}', datum: DateTime.tryParse('${m['datum'] ?? ''}'), positionen: pos);
}

/// Passendes Bibliothekselement zu einer Kassenzettelzeile (gemeinsame Wörter/Zahlen).
Bauelement? elementVorschlagen(String text, List<Bauelement> bibliothek) {
  List<String> woerter(String s) => s.toLowerCase().replaceAll(',', '.').split(RegExp(r'[^a-z0-9äöüß.]+')).where((w) => w.length >= 2).toList();
  final t = woerter(text).toSet();
  Bauelement? best;
  var bestWert = 0.0;
  for (final e in bibliothek) {
    final w = woerter('${e.name} ${e.hersteller} ${e.artikelnummer}');
    if (w.isEmpty) continue;
    final treffer = w.where(t.contains).length;
    final wert = treffer / w.length + (e.artikelnummer.isNotEmpty && text.contains(e.artikelnummer) ? 1 : 0);
    if (treffer >= 2 && wert > bestWert) {
      best = e;
      bestWert = wert;
    }
  }
  return best;
}

/// Kategorie für eine neue Zeile aus Stichwörtern raten.
BauelementKategorie kategorieRaten(String text) {
  final t = text.toLowerCase();
  bool hat(List<String> w) => w.any(t.contains);
  if (hat(['styrodur', 'xps', 'eps', 'dämm', 'daemm', 'mineralwolle', 'pir', 'holzfaser', 'kalziumsilikat'])) return BauelementKategorie.daemmstoff;
  if (hat(['kompriband', 'schaum', 'dichtband', 'silikon', 'acryl', 'folie', 'butyl'])) return BauelementKategorie.dichtstoff;
  if (hat(['nym', 'kabel', 'leitung', 'cat', 'h07v', 'j-y'])) return BauelementKategorie.kabel;
  if (hat(['leerrohr', 'rohr', 'wellrohr', 'ht-', 'kg-'])) return BauelementKategorie.rohr;
  if (hat(['dose', 'abzweig'])) return BauelementKategorie.dose;
  if (hat(['steckdose', 'schalter', 'taster', 'rahmen', 'wippe'])) return BauelementKategorie.elektro;
  if (hat(['bohrer', 'säge', 'saege', 'schrauber', 'hammer', 'zange', 'messer', 'wasserwaage', 'meter', 'spachtel ', 'kelle'])) return BauelementKategorie.werkzeug;
  if (hat(['putz', 'mörtel', 'moertel', 'kleber', 'gips', 'estrich', 'beton', 'zement', 'grundierung', 'fliese', 'platte'])) return BauelementKategorie.baustoff;
  return BauelementKategorie.kleinmaterial;
}

/// Formteile und Halter aus dem Leitungsverlauf schätzen: Richtungswechsel
/// > 30° = Winkel/Bogen, Leitungsende an einer anderen Leitung = T-Stück,
/// je angefangenem Meter eine Rohrschelle. Schlüssel: „Art · Dimension“.
Map<String, int> formteileSchaetzen(List<({List<(double, double)> punkte, String dimension, bool anderLeitung})> leitungen, {double schellenAbstand = 1000}) {
  final m = <String, int>{};
  void plus(String k, int n) => m[k] = (m[k] ?? 0) + n;
  for (final l in leitungen) {
    final p = l.punkte;
    var laenge = 0.0;
    for (var i = 0; i + 1 < p.length; i++) {
      final dx = p[i + 1].$1 - p[i].$1, dy = p[i + 1].$2 - p[i].$2;
      laenge += math.sqrt(dx * dx + dy * dy);
      if (i + 2 < p.length) {
        final ex = p[i + 2].$1 - p[i + 1].$1, ey = p[i + 2].$2 - p[i + 1].$2;
        final kreuz = dx * ey - dy * ex, skalar = dx * ex + dy * ey;
        final winkel = math.atan2(kreuz, skalar).abs() * 180 / math.pi;
        if (winkel > 60) {
          plus('Winkel 90° · ${l.dimension}', 1);
        } else if (winkel > 30) {
          plus('Winkel 45° · ${l.dimension}', 1);
        }
      }
    }
    if (l.anderLeitung) plus('T-Stück · ${l.dimension}', 1);
    if (laenge > 0) plus('Rohrschelle · ${l.dimension}', (laenge / schellenAbstand).ceil() + 1);
  }
  return m;
}
