import 'dart:math' as math;

import 'raumerkennung.dart';

/// Kabelkanäle (Typ KK) und Montage von Rohren/Leitungen (Montageschiene MS,
/// Schellen, Halter).
///
/// Kabelkanal in `Objekt.eigenschaften`:
/// - `kanal`: Bibliothekselement (Kategorie Kabelkanal), sonst `kanal_b`/`kanal_t`
/// - `kanal_montage`: aufputz | eingelassen | bruestung | sockel | boden | decke | trasse
/// - `kammern`, `stange_mm` (Lieferlänge), `kabel_liste` (Kabel direkt im Kanal)
/// - Leitungen im Kanal tragen `eigenschaften['kanal'] = <Kanal-Objekt-ID>`.
enum KanalMontage {
  aufputz('Auf Putz (Wandkanal)'),
  eingelassen('In der Wand eingelassen (bündig)'),
  bruestung('Brüstungskanal'),
  sockel('Sockelleistenkanal'),
  boden('Fußbodenkanal / Unterflur'),
  decke('Deckenkanal'),
  trasse('Kabelrinne / Trasse (Technikraum, Zählerraum)');

  const KanalMontage(this.label);
  final String label;

  bool get inWand => this == KanalMontage.eingelassen;
  static KanalMontage aus(Object? n) => KanalMontage.values.where((m) => m.name == n).firstOrNull ?? KanalMontage.aufputz;
}

/// Maße eines Kanals (mm): Breite (sichtbar an der Wand) × Tiefe (von der Wand weg).
class KanalMasse {
  const KanalMasse(this.breite, this.tiefe, {this.kammern = 1, this.stange = 2000});
  final double breite, tiefe;
  final int kammern;
  final double stange;

  /// Nutzbarer Querschnitt (mm²): Innenmaß ca. Außenmaß − 2 × 2 mm Wand, Trennstege je 2 mm.
  double get nutzquerschnitt => math.max(0, (breite - 4 - (kammern - 1) * 2) * (tiefe - 4));
}

/// Formteile eines Kanalzugs. [punkte] im Grundriss (mm), [z] optional je
/// Punkt (absolute Höhe, aus der Wandansicht). [raeume] für die Unterscheidung
/// Innen-/Außenecke. [enden] = Anzahl freier Enden (2 ohne Anschluss).
Map<String, int> kanalFormteile(List<Punkt> punkte, {List<int>? z, List<List<Punkt>> raeume = const [], int enden = 2, int abzweige = 0, double stange = 2000}) {
  final m = <String, int>{};
  void plus(String k, int n) {
    if (n > 0) m[k] = (m[k] ?? 0) + n;
  }

  var laenge = 0.0;
  for (var i = 0; i + 1 < punkte.length; i++) {
    final a = punkte[i], b = punkte[i + 1];
    final dz = z == null ? 0.0 : (z[i + 1] - z[i]).toDouble();
    final eben = (b - a).laenge;
    laenge += math.sqrt(eben * eben + dz * dz);
    if (i + 2 >= punkte.length) continue;
    final c = punkte[i + 2];
    final dz2 = z == null ? 0.0 : (z[i + 2] - z[i + 1]).toDouble();
    final eben2 = (c - b).laenge;
    // Richtungswechsel in der Wandebene (waagerecht ↔ senkrecht) = Flachwinkel
    final senk1 = dz.abs() > eben, senk2 = dz2.abs() > eben2;
    if (senk1 != senk2 && (eben < 1 || eben2 < 1 || dz.abs() > 1 || dz2.abs() > 1)) {
      plus('Flachwinkel', 1);
      continue;
    }
    if (eben < 1 || eben2 < 1) continue;
    final d1 = b - a, d2 = c - b;
    final kreuz = d1.kreuz(d2);
    final winkel = math.atan2(kreuz, d1.skalar(d2)).abs() * 180 / math.pi;
    if (winkel < 20) continue;
    // Ecke im Grundriss: liegt der Raum innen in der Kurve → Innenecke, sonst Außenecke
    final n1 = Punkt(-d1.y, d1.x) * (1 / d1.laenge), n2 = Punkt(-d2.y, d2.x) * (1 / d2.laenge);
    final innen = (n1 + n2) * (kreuz > 0 ? 1.0 : -1.0);
    // knapp neben die Ecke: bei einer Außenecke liegt dort die Wand (kein Raum)
    final probe = b + innen * (60 / math.max(1e-9, innen.laenge));
    final imRaum = raeume.any((r) => r.length >= 3 && punktInPolygon(probe, r));
    plus(raeume.isEmpty ? 'Ecke (innen/außen)' : (imRaum ? 'Innenecke' : 'Außenecke'), 1);
  }
  plus('Endkappe', enden);
  plus('T-Stück / Abzweig', abzweige);
  if (laenge > 0 && stange > 0) plus('Stoßstellenabdeckung', math.max(0, (laenge / stange).ceil() - 1));
  return m;
}

/// Füllgrad eines Kanals: Summe der Kabel-/Rohrquerschnitte (aus den
/// Außendurchmessern) zum Nutzquerschnitt, 0 … 1+.
double kanalFuellgrad(KanalMasse k, Iterable<double> durchmesser) {
  final q = k.nutzquerschnitt;
  if (q <= 0) return 0;
  return durchmesser.fold<double>(0, (s, d) => s + math.pi * d * d / 4) / q;
}

/// Bewertung des Füllgrads (Reserve für Nachbelegung: üblich höchstens 60 %).
String? fuellgradHinweis(double f) => f > 1
    ? 'Kanal überfüllt (${(f * 100).round()} %) – größeren Kanal oder zweiten Kanal'
    : f > 0.6
        ? 'Füllgrad ${(f * 100).round()} % – keine Reserve mehr (Richtwert höchstens 60 %)'
        : null;

/// Richtwert für den Befestigungsabstand (mm) von Rohren und Leitungen nach
/// Material und Außendurchmesser; senkrecht etwas größer. Herstellerangaben gehen vor.
double befestigungsabstand(String? art, double aussen, {bool senkrecht = false}) {
  final a = (art ?? '').toLowerCase();
  double w;
  if (a.contains('kupfer') || a.contains('stahl') || a.contains('edelstahl')) {
    w = aussen <= 15 ? 1250 : aussen <= 22 ? 1500 : aussen <= 28 ? 1800 : aussen <= 42 ? 2400 : 2700;
  } else if (a.contains('verbund')) {
    w = aussen <= 16 ? 1000 : aussen <= 20 ? 1250 : aussen <= 26 ? 1500 : 2000;
  } else if (a.contains('ht') || a.contains('kg') || a.contains('abwasser')) {
    w = 10 * math.max(aussen, 32); // waagerecht 10 × Außendurchmesser
    if (senkrecht) return 2000;
  } else if (a.contains('pe-x') || a.contains('heizrohr') || a.contains('pp') || a.contains('kunststoff')) {
    w = aussen <= 20 ? 500 : aussen <= 32 ? 800 : 1000;
  } else if (a.contains('leerrohr') || a.contains('wellrohr')) {
    w = aussen <= 25 ? 600 : 800;
  } else if (a.contains('lüftung') || a.contains('lueftung')) {
    w = 1500;
  } else {
    // Kabel ohne Rohr (Mantelleitung): waagerecht ca. 20 × d, höchstens 400 mm
    w = math.min(400, math.max(250, 20 * aussen));
    if (senkrecht) return math.min(1000, w * 2);
  }
  return senkrecht ? w * 1.3 : w;
}

/// Schellen einer Leitung: Anzahl nach Länge (waagerecht/senkrecht getrennt)
/// plus je eine an Anfang, Ende und jedem Richtungswechsel.
int schellenAnzahl(List<Punkt> punkte, double abstandWaagerecht, double abstandSenkrecht, {List<int>? z}) {
  var n = 1;
  for (var i = 0; i + 1 < punkte.length; i++) {
    final eben = (punkte[i + 1] - punkte[i]).laenge;
    final dz = z == null ? 0.0 : (z[i + 1] - z[i]).toDouble().abs();
    final l = math.sqrt(eben * eben + dz * dz);
    final abst = dz > eben ? abstandSenkrecht : abstandWaagerecht;
    if (l > 0) n += math.max(1, (l / abst).ceil());
  }
  return n;
}

/// Montageschiene (Typ MS): Konsolen/Wandbefestigungen nach Halterabstand.
int schienenHalter(double laenge, {double halterAbstand = 1000}) => laenge <= 0 ? 0 : (laenge / halterAbstand).ceil() + 1;
