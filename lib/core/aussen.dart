import 'dart:math' as math;

import 'raumerkennung.dart';

/// Außenbereich als Planungshilfe: Regenwasser (Fallrohre, Zisterne,
/// Versickerung), Bewässerung, Außenlicht, Außensteckdosen und Kabel im
/// Außenbereich (Erdkabel, auf Putz). Richtwerte.

/// Objekttypen des Gewerks Außenanlagen (Migration 27).
const aussenTypen = [
  ('AE', 'Außenleuchte (Wand / Mast)', 'punkt'),
  ('PO', 'Poller- / Wegeleuchte', 'punkt'),
  ('EB', 'Bodeneinbaustrahler außen', 'punkt'),
  ('AS', 'Außensteckdose / Energiesäule', 'punkt'),
  ('EK', 'Erdkabel (im Schutzrohr)', 'linie'),
  ('AK', 'Außenkabel auf Putz (Schutzrohr / Kanal)', 'linie'),
  ('RF', 'Regenfallrohr', 'punkt'),
  ('RG', 'Regenwasser- / Grundleitung', 'linie'),
  ('ZS', 'Zisterne', 'flaeche'),
  ('RI', 'Rigole / Sickeranlage', 'flaeche'),
  ('BW', 'Bewässerungsleitung', 'linie'),
  ('RE', 'Regner / Tropfer', 'punkt'),
  ('BV', 'Bewässerungsventil / Verteiler', 'punkt'),
  ('AW', 'Außenwasserhahn (frostsicher)', 'punkt'),
  ('GA', 'Garten- / Rasenfläche', 'flaeche'),
  ('WG', 'Weg / Terrasse / Zufahrt', 'flaeche'),
];

// ---------------------------------------------------------- Regenwasser

/// Abflussbeiwert C je Dachart/Fläche.
const abflussbeiwerte = <String, double>{'Steildach (Ziegel)': 1.0, 'Flachdach (Kies)': 0.8, 'Gründach extensiv': 0.5, 'Gründach intensiv': 0.3, 'Pflaster': 0.7, 'Rasengitter': 0.4};

/// Regenabfluss in l/s: Fläche (m²) × C × Regenspende r (l/(s·ha), Vorgabe 300).
double regenabfluss(double flaecheM2, double c, {double r = 300}) => flaecheM2 * c * r / 10000;

/// Fallrohr-Nennweite für den Abfluss (Richtwerte DIN EN 12056-3, Füllungsgrad 0,33).
int fallrohrDn(double ls) {
  for (final (dn, q) in const [(60, 0.8), (70, 1.2), (80, 1.8), (100, 3.4), (120, 5.9), (150, 10.8)]) {
    if (ls <= q) return dn;
  }
  return 200;
}

/// Zisterne nach DIN 1989-1 (vereinfacht): Ertrag (m³/a), Bedarf (m³/a), Volumen (m³, ~3 Wochen Reserve).
({double ertrag, double bedarf, double volumen}) zisterne({required double dachM2, double c = 0.9, double niederschlagMm = 750, int personen = 4, double gartenM2 = 0, bool wc = true, bool waschmaschine = true}) {
  final ertrag = dachM2 * niederschlagMm / 1000 * c * 0.9;
  final bedarf = personen * ((wc ? 24 : 0) + (waschmaschine ? 10 : 0)) * 365 / 1000 + gartenM2 * 0.06;
  final volumen = math.min(ertrag, bedarf) * 21 / 365;
  return (ertrag: ertrag, bedarf: bedarf, volumen: volumen);
}

/// Rigole (Kies, Speicherkoeffizient 0,35) für die angeschlossene Fläche, Richtwert 15 l je m² A_u.
({double speicher, double kiesVolumen}) rigole(double flaecheM2, double c) {
  final speicher = flaecheM2 * c * 0.015; // m³
  return (speicher: speicher, kiesVolumen: speicher / 0.35);
}

// ------------------------------------------------------------ Bewässerung

/// Regner: Mitte, Radius (mm), Durchfluss (l/min), Ventil-ID.
typedef Regner = ({Punkt p, double radius, double lmin, String? ventil});

/// Anteil der Gartenflächen, die ein Regner erreicht.
double bewaesserungAbdeckung(List<List<Punkt>> flaechen, List<Regner> regner, {double raster = 300}) {
  var n = 0, ok = 0;
  for (final f in flaechen) {
    if (f.length < 3) continue;
    final xs = f.map((p) => p.x), ys = f.map((p) => p.y);
    for (var y = ys.reduce(math.min) + raster / 2; y < ys.reduce(math.max); y += raster) {
      for (var x = xs.reduce(math.min) + raster / 2; x < xs.reduce(math.max); x += raster) {
        final q = Punkt(x, y);
        if (!punktInPolygon(q, f)) continue;
        n++;
        if (regner.any((r) => (r.p - q).laenge <= r.radius)) ok++;
      }
    }
  }
  return n == 0 ? 0 : ok / n;
}

/// Durchfluss je Ventil/Zone gegen die verfügbare Leistung (l/min).
List<String> bewaesserungZonen(List<Regner> regner, {double verfuegbarLmin = 25}) {
  final zonen = <String, double>{};
  for (final r in regner) {
    zonen[r.ventil ?? 'ohne Ventil'] = (zonen[r.ventil ?? 'ohne Ventil'] ?? 0) + r.lmin;
  }
  return [
    for (final e in zonen.entries)
      if (e.value > verfuegbarLmin) 'Zone ${e.key}: ${e.value.toStringAsFixed(0)} l/min – mehr als ${verfuegbarLmin.toStringAsFixed(0)} l/min verfügbar, Zone teilen.',
  ];
}

// ------------------------------------------------------------- Außenlicht

/// Ausleuchtungsradius (mm) einer Außenleuchte aus Lichtpunkthöhe (Richtwert ≈ 1,7 × Höhe).
double lichtRadius(String kuerzel, {double? hoehe}) => switch (kuerzel) {
      'PO' => 1.7 * (hoehe ?? 800) + 500,
      'EB' => 1500,
      _ => 1.7 * (hoehe ?? 2200),
    };

/// Anteil beleuchteter Weg-/Terrassenfläche.
double wegAusleuchtung(List<List<Punkt>> wege, List<(Punkt, double)> leuchten) => bewaesserungAbdeckung(wege, [for (final (p, r) in leuchten) (p: p, radius: r, lmin: 0, ventil: null)]);

/// Hinweise zur Außenbeleuchtung.
List<String> aussenlichtHinweise({required int leuchten, required bool bewegungsmelder, required double ausleuchtung}) => [
      if (ausleuchtung < 0.6 && leuchten > 0) 'Wege nur zu ${(ausleuchtung * 100).round()} % ausgeleuchtet – Poller-/Wegeleuchten ergänzen (Abstand ca. 3–5 m).',
      if (!bewegungsmelder && leuchten > 0) 'Eingang/Zufahrt: Bewegungsmelder oder Zeitschaltung vorsehen.',
      'Insektenfreundlich: warmweiß ≤ 2700 K, nach unten abstrahlend, keine Kugelleuchten; Nachbarn nicht blenden.',
      'Außenleuchten mindestens IP44, Bodeneinbau IP67 mit Drainage; separater Außenstromkreis mit RCD 30 mA.',
    ];

// -------------------------------------------------------------- Kabel außen

/// Erdkabel: Tiefe 60 cm (unter befahrenen Flächen 80 cm), Sandbett, Warnband,
/// Kabelschutzrohr. Liefert Mengen und Hinweise.
List<({String was, double menge, String einheit})> erdkabelMengen(double laengeM, {bool befahren = false}) {
  final tiefe = befahren ? 0.8 : 0.6;
  return [
    (was: 'Kabelgraben ${(tiefe * 100).round()} cm tief, 30 cm breit', menge: laengeM * tiefe * 0.3, einheit: 'm³'),
    (was: 'Kabelschutzrohr DN 50 (erdverlegt, mit Zugdraht)', menge: laengeM * 1.05, einheit: 'm'),
    (was: 'Sandbett 10 cm unter / über dem Rohr', menge: laengeM * 0.3 * 0.2, einheit: 'm³'),
    (was: 'Trassenwarnband (30 cm über dem Kabel)', menge: laengeM, einheit: 'm'),
  ];
}

/// Kabel auf Putz außen: UV-beständiges Rohr/Kanal, Schellen alle 40 cm.
List<({String was, double menge, String einheit})> aufputzAussenMengen(double laengeM) => [
      (was: 'UV-beständiges Installationsrohr (oder Stahlrohr) außen', menge: laengeM * 1.1, einheit: 'm'),
      (was: 'Rohrschellen (Abstand 40 cm, nicht rostend)', menge: (laengeM / 0.4).ceilToDouble() + 2, einheit: 'Stk'),
      (was: 'Feuchtraum-Abzweigdose IP54/IP65', menge: math.max(1, laengeM / 8).ceilToDouble(), einheit: 'Stk'),
    ];

/// Hinweise für Kabel im Außenbereich je Kabeltyp.
List<String> aussenKabelHinweise(String kabel, {required bool erdverlegt}) {
  final k = kabel.toUpperCase();
  return [
    if (erdverlegt && k.startsWith('NYM')) 'NYM ist nicht für das Erdreich zugelassen – NYY-J (oder NAYY) verwenden.',
    if (!erdverlegt && k.startsWith('NYM')) 'NYM außen nur im UV-beständigen Rohr; frei verlegt NYY-J oder H07RN-F.',
    if (erdverlegt) 'Erdkabel mindestens 60 cm tief (unter Zufahrt 80 cm), im Schutzrohr, mit Warnband; Lage einmessen und fotografieren.',
    if (!erdverlegt) 'Auf Putz außen: Rohr UV-stabil, Befestigung alle 30–50 cm, Abzweigdosen mindestens IP54, Durchführung ins Haus nach unten geneigt und abgedichtet.',
  ];
}
