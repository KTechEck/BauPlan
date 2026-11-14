import 'dart:math' as math;

/// Kühlung, Klima und Lüftung als Planungshilfe: Taupunkt, Kühllast-
/// Richtwert, Lüftung nach DIN 1946-6 (vereinfacht), Luftleitungen und
/// eigene Komponenten im Druckverlust.

// ------------------------------------------------------------- Taupunkt

/// Taupunkt (°C) nach Magnus aus Temperatur (°C) und relativer Feuchte (%).
double taupunkt(double temperatur, double feuchteProzent) {
  const a = 17.62, b = 243.12;
  final g = math.log(math.max(1, feuchteProzent) / 100) + a * temperatur / (b + temperatur);
  return b * g / (a - g);
}

/// Kleinste zulässige Vorlauftemperatur der Flächenkühlung: Taupunkt + [abstand] K.
double minKuehlVorlauf(double raumTemp, double feuchte, {double abstand = 2}) => taupunkt(raumTemp, feuchte) + abstand;

/// Kondensat an einer Leitung: Oberfläche (≈ Medium) unter dem Taupunkt der Umgebung?
bool kondensatGefahr(double mediumTemp, double umgebungTemp, double feuchte) => mediumTemp < taupunkt(umgebungTemp, feuchte);

// ---------------------------------------------------------------- Kühllast

/// Kühllast-Richtwert (W): Grundlast je m² plus Sonneneintrag der Fenster
/// nach Richtung (W/m² Glas, mit Fc des Sonnenschutzes), Personen, Geräte.
double kuehllast({
  required double flaeche,
  List<({double glas, String richtung, double fc})> fenster = const [],
  int personen = 0,
  double geraeteW = 0,
  double grundWm2 = 20,
}) {
  double sonne(String r) => switch (r) { 'S' => 350, 'SW' || 'SO' => 400, 'W' || 'O' => 450, 'NW' || 'NO' => 200, _ => 100 };
  final f = fenster.fold<double>(0, (s, x) => s + x.glas * sonne(x.richtung) * x.fc * 0.6);
  return flaeche * grundWm2 + f + personen * 80 + geraeteW;
}

/// Passende Klimagerät-Leistung (kW) aus üblichen Größen.
double klimageraetGroesse(double lastW) {
  const g = [2.0, 2.5, 3.5, 4.2, 5.0, 6.0, 7.1];
  return g.firstWhere((x) => x * 1000 >= lastW, orElse: () => g.last);
}

// ----------------------------------------------------------------- Lüftung

/// Raumart für die Lüftung.
enum LuftArt { zuluft, abluft, ueberstroem, keine }

/// Lüftungsart eines Raums am Namen (DIN 1946-6): Wohn-/Schlafräume Zuluft,
/// Küche/Bad/WC/HWR Abluft, Flur/Diele Überström.
LuftArt luftArtVorschlag(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'küche|bad|dusch|\bwc\b|toilette|hwr|hauswirtschaft|wasch|abstell|speis|technik|heiz').hasMatch(n)) return LuftArt.abluft;
  if (RegExp(r'flur|diele|gang|treppe|galerie').hasMatch(n)) return LuftArt.ueberstroem;
  if (RegExp(r'garage|terrasse|balkon|keller').hasMatch(n)) return LuftArt.keine;
  return LuftArt.zuluft;
}

/// Mindest-Abluft je Raum (m³/h) bei Nennlüftung (DIN 1946-6 Tab. 7, Richtwerte).
double abluftMindest(String name) {
  final n = name.toLowerCase();
  if (n.contains('küche')) return 45;
  if (RegExp(r'bad|dusch').hasMatch(n)) return 45;
  if (RegExp(r'\bwc\b|toilette').hasMatch(n)) return 25;
  return 25;
}

/// Gewicht für die Zuluftverteilung.
double zuluftGewicht(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'wohn|ess').hasMatch(n)) return 3;
  return 2;
}

/// Gesamt-Außenluftvolumenstrom bei Nennlüftung (m³/h) aus der Fläche der
/// Nutzungseinheit (DIN 1946-6, Näherung q = −0,001·A² + 1,15·A + 20).
double nennlueftung(double flaeche) => math.max(0, -0.001 * flaeche * flaeche + 1.15 * flaeche + 20);

/// Lüftungsstufen relativ zur Nennlüftung.
const lueftungsStufen = {'Feuchteschutz': 0.3, 'Reduziert': 0.7, 'Nennlüftung': 1.0, 'Intensiv': 1.3};

/// Ein Raum in der Lüftungsauslegung.
typedef LuftRaum = ({String id, String name, double flaeche, LuftArt art, double? vonHand});

/// Ergebnis je Raum: Volumenstrom (m³/h).
typedef LuftVerteilung = ({String id, String name, LuftArt art, double volumenstrom});

/// Volumenströme verteilen: Abluft mindestens Tabellenwert, Summe Abluft
/// und Zuluft gleich groß (balanciert), mindestens Nennlüftung.
({double gesamt, List<LuftVerteilung> raeume}) lueftungVerteilen(List<LuftRaum> raeume) {
  final flaeche = raeume.fold<double>(0, (s, r) => s + r.flaeche);
  final ab = raeume.where((r) => r.art == LuftArt.abluft).toList();
  final zu = raeume.where((r) => r.art == LuftArt.zuluft).toList();
  final abSumme = ab.fold<double>(0, (s, r) => s + (r.vonHand ?? abluftMindest(r.name)));
  final gesamt = math.max(nennlueftung(flaeche), abSumme);
  final aus = <LuftVerteilung>[];
  final faktorAb = abSumme <= 0 ? 0.0 : gesamt / abSumme;
  for (final r in ab) {
    aus.add((id: r.id, name: r.name, art: r.art, volumenstrom: r.vonHand ?? abluftMindest(r.name) * faktorAb));
  }
  final gew = zu.fold<double>(0, (s, r) => s + zuluftGewicht(r.name) * math.max(1, r.flaeche));
  final zuVonHand = zu.where((r) => r.vonHand != null).fold<double>(0, (s, r) => s + r.vonHand!);
  final gewFrei = zu.where((r) => r.vonHand == null).fold<double>(0, (s, r) => s + zuluftGewicht(r.name) * math.max(1, r.flaeche));
  for (final r in zu) {
    final v = r.vonHand ?? (gewFrei <= 0 ? 0.0 : (gesamt - zuVonHand) * zuluftGewicht(r.name) * math.max(1, r.flaeche) / gewFrei);
    aus.add((id: r.id, name: r.name, art: r.art, volumenstrom: v));
  }
  if (gew == 0) {
    // keine Zulufträume – nur Abluft (Abluftanlage)
  }
  for (final r in raeume.where((r) => r.art == LuftArt.ueberstroem || r.art == LuftArt.keine)) {
    aus.add((id: r.id, name: r.name, art: r.art, volumenstrom: 0));
  }
  return (gesamt: gesamt, raeume: aus);
}

/// Freier Querschnitt eines Überström-Luftdurchlasses (cm²) bei höchstens 1 m/s.
double ueberstroemQuerschnitt(double volumenstrom, {double v = 1.0}) => volumenstrom / 3600 / v * 1e4;

/// Luftleitung: Geschwindigkeit (m/s) und Druckgefälle (Pa/m) eines Rundrohrs.
({double v, double r}) luftleitung(double volumenstrom, double durchmesserMm) {
  final d = durchmesserMm / 1000;
  final a = math.pi * d * d / 4;
  final v = volumenstrom / 3600 / a;
  if (v <= 0) return (v: 0, r: 0);
  const nu = 15.1e-6, rho = 1.2;
  final re = v * d / nu;
  final lambda = re < 2300 ? 64 / re : 0.3164 * math.pow(re, -0.25) * 1.15; // Zuschlag Rauigkeit/Formteile
  return (v: v, r: lambda / d * rho * v * v / 2);
}

/// Kleinster üblicher Rohrdurchmesser für [volumenstrom] bei höchstens [vMax] m/s.
int luftrohrVorschlag(double volumenstrom, {double vMax = 3}) {
  const ds = [63, 75, 90, 100, 125, 160, 180, 200, 250];
  return ds.firstWhere((d) => luftleitung(volumenstrom, d.toDouble()).v <= vMax, orElse: () => ds.last);
}

/// Eigene Lüftungskomponente mit Druckverlust bei Nennvolumenstrom
/// (Schalldämpfer, Filter, Heiz-/Kühlregister, Erdwärmetauscher …).
typedef LuftKomponente = ({String name, double druckverlust, double? leistungW, String art});

/// Externer Druckbedarf des Geräts: längster Strang (Pa) + Komponenten + Ventile/Durchlässe.
double druckbedarf({required double strangPa, required List<LuftKomponente> komponenten, double ventilPa = 30, double aussenFortPa = 40}) =>
    strangPa + komponenten.fold<double>(0, (s, k) => s + k.druckverlust) + ventilPa + aussenFortPa;

/// Hinweise zur Dämmung: Außen-/Fortluft immer dampfdiffusionsdicht, Zu-/Abluft
/// in unbeheizten Bereichen gedämmt; gekühlte Zuluft unter Taupunkt → diffusionsdicht.
List<String> daemmHinweise({required bool kuehlung, double zuluftTemp = 16, double raumTemp = 26, double feuchte = 60}) => [
      'Außen- und Fortluftleitungen dampfdiffusionsdicht dämmen (Kondensat).',
      'Zu- und Abluftleitungen in unbeheizten Bereichen (Dachboden, Kaltdach) wärmegedämmt führen.',
      if (kuehlung && kondensatGefahr(zuluftTemp, raumTemp, feuchte))
        'Gekühlte Zuluft ${zuluftTemp.toStringAsFixed(0)} °C liegt unter dem Taupunkt ${taupunkt(raumTemp, feuchte).toStringAsFixed(1).replaceAll('.', ',')} °C – Zuluftleitungen diffusionsdicht dämmen.',
    ];
