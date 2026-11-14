import 'dart:math' as math;

import 'auslegung.dart' show entnahmeArten, spitzendurchfluss;

/// Wasser als Planungshilfe: Abwasser nach DIN 1986-100 / DIN EN 12056
/// (Anschlusswerte DU, Nennweiten, Gefälle), Trinkwasser-Hausanschluss
/// (Spitzendurchfluss, Zählergröße) und Wassermelder mit Absperrventil.

/// Anschlusswerte DU (l/s) und Mindest-Nennweite der Einzelanschlussleitung
/// je Entwässerungsgegenstand (System I, Wohnungsbau).
const abwasserGegenstaende = <String, (double du, int dn)>{
  'Waschtisch': (0.5, 40),
  'Dusche (ohne Stöpsel)': (0.6, 50),
  'Bodengleiche Dusche / Rinne': (0.8, 70),
  'Badewanne': (0.8, 50),
  'WC (6 l)': (2.0, 90),
  'Urinal': (0.5, 50),
  'Bidet': (0.5, 40),
  'Spüle': (0.8, 50),
  'Geschirrspüler': (0.8, 50),
  'Waschmaschine': (0.8, 50),
  'Bodenablauf DN 50': (0.8, 50),
  'Bodenablauf DN 100': (2.0, 100),
};

/// Badobjekt-Kürzel → Abwasser-Gegenstand.
const abwasserJeKuerzel = {'WT': 'Waschtisch', 'DU': 'Bodengleiche Dusche / Rinne', 'WA': 'Badewanne', 'WC': 'WC (6 l)', 'UR': 'Urinal'};

/// Schmutzwasserabfluss Qww = K·√ΣDU (K = 0,5 Wohnungsbau), mindestens der größte DU.
double schmutzwasserAbfluss(List<double> du, {double k = 0.5}) {
  if (du.isEmpty) return 0;
  final s = du.fold<double>(0, (a, b) => a + b);
  return math.max(k * math.sqrt(s), du.reduce(math.max));
}

/// Nennweiten mit zulässigem Abfluss (l/s): Sammelanschluss-/Grundleitung
/// bei 1 % Gefälle, Füllungsgrad 0,5 bzw. 0,7 (Richtwerte) und Fallleitung
/// mit Hauptlüftung.
const _dnListe = <(int dn, double liegend, double fall)>[
  (50, 0.8, 0.8),
  (70, 1.5, 1.5),
  (90, 2.0, 2.7),
  (100, 2.5, 4.0),
  (125, 4.1, 5.8),
  (150, 6.6, 9.5),
];

/// Kleinste Nennweite für den Abfluss [qww]; WC verlangt mindestens DN 90/100.
int abwasserNennweite(double qww, {bool fallleitung = false, bool mitWc = false}) {
  for (final (dn, l, f) in _dnListe) {
    if (mitWc && dn < (fallleitung ? 100 : 90)) continue;
    if ((fallleitung ? f : l) >= qww) return dn;
  }
  return 150;
}

/// Mindestgefälle in % (DIN 1986-100): Anschlussleitungen 1 %, Grundleitungen
/// 0,5 % (DN ≥ 90 auch 0,5 % innerhalb von Gebäuden), Fallleitungen senkrecht.
double mindestGefaelle({bool grundleitung = false, int dn = 50}) => grundleitung || dn >= 90 ? 0.5 : 1.0;

/// Prüfung einer liegenden Abwasserleitung.
({double hoehenunterschied, double qww, int dnSoll, List<String> hinweise}) abwasserPruefen({
  required double laengeM,
  required List<double> du,
  int? dn,
  double gefaelleProzent = 1.0,
  bool grundleitung = false,
  bool mitWc = false,
  double? platzMm, // verfügbare Höhe für den Höhenunterschied (Estrich, Vorwand, Decke)
}) {
  final q = schmutzwasserAbfluss(du);
  final soll = abwasserNennweite(q, mitWc: mitWc);
  final dh = laengeM * 1000 * gefaelleProzent / 100;
  final min = mindestGefaelle(grundleitung: grundleitung, dn: dn ?? soll);
  final h = <String>[
    if (dn != null && dn < soll) 'DN $dn zu klein für ${q.toStringAsFixed(2).replaceAll('.', ',')} l/s – DN $soll',
    if (gefaelleProzent < min) 'Gefälle ${gefaelleProzent.toStringAsFixed(1).replaceAll('.', ',')} % unter ${min.toStringAsFixed(1).replaceAll('.', ',')} %',
    if (gefaelleProzent > 5 && !grundleitung) 'Gefälle über 5 % – Selbstabsaugung möglich, Belüftung prüfen',
    if (laengeM > 4 && !grundleitung && (dn ?? soll) < 70) 'Unbelüftete Einzelanschlussleitung über 4 m – größer dimensionieren oder belüften',
    if (platzMm != null && dh > platzMm) 'Höhenunterschied ${dh.round()} mm passt nicht in ${platzMm.round()} mm Aufbau',
  ];
  return (hoehenunterschied: dh, qww: q, dnSoll: soll, hinweise: h);
}

/// Trinkwasser-Hausanschluss: Summe der Berechnungsdurchflüsse aus den
/// Entnahmestellen (kalt + warm getrennt gezählt), Spitzendurchfluss und
/// passender Wasserzähler (Q3 in m³/h).
({double summeVr, double spitze, String zaehler, String anschluss}) hausanschluss(Map<String, int> entnahmen) {
  var s = 0.0;
  for (final e in entnahmen.entries) {
    s += (entnahmeArten[e.key] ?? 0) * e.value;
  }
  final vs = spitzendurchfluss(s);
  final m3h = vs * 3.6;
  final zaehler = m3h <= 2.5 ? 'Q3 = 4 (früher Qn 2,5)' : (m3h <= 4 ? 'Q3 = 6,3 (früher Qn 6)' : 'Q3 = 10 oder größer');
  final anschluss = vs <= 0.6 ? 'DN 25 (32×3 PE)' : (vs <= 1.2 ? 'DN 32 (40×3,7 PE)' : 'DN 40 (50×4,6 PE)');
  return (summeVr: s, spitze: vs, zaehler: zaehler, anschluss: anschluss);
}

/// Entnahmestellen aus Badobjekt-Kürzeln zählen (kalt + warm getrennt).
Map<String, int> entnahmenAusObjekten(Iterable<String> kuerzel) {
  final m = <String, int>{};
  void plus(String art, int n) => m[art] = (m[art] ?? 0) + n;
  for (final k in kuerzel) {
    switch (k) {
      case 'WT':
        plus('Waschtisch', 2);
      case 'DU':
        plus('Dusche', 2);
      case 'WA':
        plus('Badewanne', 2);
      case 'WC':
        plus('WC (Spülkasten)', 1);
      case 'UR':
        plus('Urinal', 1);
    }
  }
  return m;
}

/// Home-Assistant-Automation: Wassermelder schaltet Absperrventil zu.
/// [melder] = binary_sensor-Entitäten, [ventil] = valve-/switch-Entität.
String wassermelderYaml(String name, List<String> melder, String ventil, {bool benachrichtigen = true}) {
  final b = StringBuffer()
    ..writeln('# BauSpur: Wassermelder → Absperrventil schließen')
    ..writeln('- alias: "Wasseralarm $name – Hauptventil zu"')
    ..writeln('  mode: single')
    ..writeln('  trigger:');
  for (final m in melder) {
    b
      ..writeln('    - platform: state')
      ..writeln('      entity_id: $m')
      ..writeln('      to: "on"');
  }
  final dienst = ventil.startsWith('valve.') ? 'valve.close_valve' : 'switch.turn_off';
  b
    ..writeln('  action:')
    ..writeln('    - service: $dienst')
    ..writeln('      target:')
    ..writeln('        entity_id: $ventil');
  if (benachrichtigen) {
    b
      ..writeln('    - service: persistent_notification.create')
      ..writeln('      data:')
      ..writeln('        title: "Wasseralarm"')
      ..writeln('        message: "Wassermelder hat ausgelöst ($name) – Hauptventil wurde geschlossen."');
  }
  return b.toString();
}
