import 'dart:math' as math;

/// Fassade und Ausbau als Planungshilfe: WDVS mit Plattenraster, Dübeln,
/// Sockel, Profilen, Montageblöcken und Durchdringungen; Balkon-Hinweise;
/// Sockelleisten; abgehängte Deckenfelder mit Schattenfuge; Einbautiefe von
/// Bodeneinbaustrahlern.

// ------------------------------------------------------------------- WDVS

class WdvsVorgaben {
  const WdvsVorgaben({
    this.daemmstoff = 'EPS 032',
    this.dicke = 160,
    this.plattenB = 1000,
    this.plattenH = 500,
    this.sockelHoehe = 300,
    this.duebelProM2 = 6,
    this.duebelRand = 8,
    this.randbreite = 1000,
    this.laibung = 30,
    this.verschnitt = 5,
  });
  final String daemmstoff;
  final int dicke; // mm
  final int plattenB, plattenH; // mm
  final int sockelHoehe; // mm (Perimeter/Sockelplatten)
  final double duebelProM2; // Fläche
  final double duebelRand; // Randzone an Gebäudeecken
  final int randbreite; // mm je Ecke
  final int laibung; // Laibungsdämmung mm
  final double verschnitt; // %

  double get lambda => switch (daemmstoff) {
        'EPS 032' => 0.032,
        'EPS 035' => 0.035,
        'Mineralwolle 035' => 0.035,
        'Holzfaser 040' => 0.040,
        'PU 024' => 0.024,
        _ => 0.035,
      };

  Map<String, Object?> toJson() => {
        'daemmstoff': daemmstoff,
        'dicke': dicke,
        'platten_b': plattenB,
        'platten_h': plattenH,
        'sockel': sockelHoehe,
        'duebel': duebelProM2,
        'duebel_rand': duebelRand,
        'laibung': laibung,
        'verschnitt': verschnitt,
      };

  static WdvsVorgaben ausJson(Map? m) => WdvsVorgaben(
        daemmstoff: '${m?['daemmstoff'] ?? 'EPS 032'}',
        dicke: (m?['dicke'] as num?)?.toInt() ?? 160,
        plattenB: (m?['platten_b'] as num?)?.toInt() ?? 1000,
        plattenH: (m?['platten_h'] as num?)?.toInt() ?? 500,
        sockelHoehe: (m?['sockel'] as num?)?.toInt() ?? 300,
        duebelProM2: (m?['duebel'] as num?)?.toDouble() ?? 6,
        duebelRand: (m?['duebel_rand'] as num?)?.toDouble() ?? 8,
        laibung: (m?['laibung'] as num?)?.toInt() ?? 30,
        verschnitt: (m?['verschnitt'] as num?)?.toDouble() ?? 5,
      );
}

const wdvsDaemmstoffe = ['EPS 032', 'EPS 035', 'Mineralwolle 035', 'Holzfaser 040', 'PU 024'];

/// Eine Fassadenseite: Länge der Außenkante (mm), Höhe (mm) und Öffnungen.
typedef Fassadenseite = ({String name, double laenge, double hoehe, List<({double b, double h, bool tuer})> oeffnungen});

class WdvsErgebnis {
  WdvsErgebnis({
    required this.flaeche,
    required this.platten,
    required this.duebel,
    required this.sockelM2,
    required this.sockelschiene,
    required this.laibungM2,
    required this.kantenprofil,
    required this.anputzleiste,
    required this.tropfkante,
    required this.armierung,
  });
  final double flaeche; // m² Dämmfläche (ohne Sockel)
  final int platten; // Stück mit Verschnitt
  final int duebel;
  final double sockelM2;
  final double sockelschiene; // m
  final double laibungM2;
  final double kantenprofil; // m (Gebäudeecken + Laibungskanten)
  final double anputzleiste; // m (Fensteranschluss)
  final double tropfkante; // m (Fensterstürze)
  final double armierung; // m² Gewebe (Fläche + 10 %)
}

/// WDVS-Mengen aus den Fassadenseiten. [ecken] = Gebäudeaußenecken.
WdvsErgebnis wdvsBerechnen(List<Fassadenseite> seiten, WdvsVorgaben v, {int ecken = 4}) {
  var brutto = 0.0, oeff = 0.0, laibung = 0.0, kante = 0.0, anputz = 0.0, tropf = 0.0, sockelL = 0.0;
  for (final s in seiten) {
    brutto += s.laenge * s.hoehe / 1e6;
    sockelL += s.laenge / 1000;
    for (final o in s.oeffnungen) {
      oeff += o.b * o.h / 1e6;
      final umfang = (o.tuer ? o.b + 2 * o.h : 2 * (o.b + o.h)) / 1000;
      laibung += umfang * (v.dicke + 20) / 1000; // Laibungstiefe ≈ Dämmdicke
      kante += umfang;
      anputz += umfang;
      tropf += o.b / 1000;
      if (o.tuer) sockelL -= o.b / 1000;
    }
  }
  final sockel = math.max(0.0, sockelL) * v.sockelHoehe / 1000;
  final flaeche = math.max(0.0, brutto - oeff - sockel);
  final platte = v.plattenB * v.plattenH / 1e6;
  final platten = ((flaeche + laibung * 0) / platte * (1 + v.verschnitt / 100)).ceil();
  // Dübel: Randzonen an Ecken mit mehr Dübeln
  final hoehe = seiten.isEmpty ? 0.0 : seiten.map((s) => s.hoehe).reduce(math.max) / 1000;
  final rand = math.min(flaeche, ecken * 2 * v.randbreite / 1000 * hoehe);
  final duebel = ((flaeche - rand) * v.duebelProM2 + rand * v.duebelRand).ceil();
  return WdvsErgebnis(
    flaeche: flaeche,
    platten: platten,
    duebel: duebel,
    sockelM2: sockel,
    sockelschiene: math.max(0, sockelL),
    laibungM2: laibung,
    kantenprofil: kante + ecken * hoehe,
    anputzleiste: anputz,
    tropfkante: tropf,
    armierung: (flaeche + laibung + sockel) * 1.1,
  );
}

/// U-Wert einer Wand nach Aufbringen von WDVS.
double uMitWdvs(double uBestand, WdvsVorgaben v) => uBestand <= 0 ? 0 : 1 / (1 / uBestand + v.dicke / 1000 / v.lambda);

/// Montageblöcke/-zylinder je Anbauteil (Lampe, Markise, Briefkasten …).
String montageteil(String anbau) => switch (anbau.toLowerCase()) {
      final a when a.contains('markise') || a.contains('vordach') || a.contains('geländer') => 'Montagequader (schwerlast)',
      final a when a.contains('kamera') || a.contains('leuchte') || a.contains('lampe') || a.contains('melder') => 'Montagezylinder Ø 70–90 mm (mit Leitungsdurchführung)',
      final a when a.contains('steckdose') || a.contains('schalter') => 'Geräteträger für Dosen im WDVS',
      _ => 'Montagezylinder',
    };

/// Balkon-Hinweise (LBO/DIN, Richtwerte).
List<String> balkonHinweise({required double flaecheM2, double? gelaender, double? gefaelle, bool thermischGetrennt = false, bool auskragend = true}) => [
      if (gelaender == null || gelaender < 900) 'Absturzsicherung: Geländer mindestens 0,90 m (über 12 m Absturzhöhe 1,10 m), Öffnungen ≤ 12 cm.',
      if (gefaelle == null || gefaelle < 1.5) 'Gefälle mindestens 1,5–2 % vom Haus weg, Entwässerung (Rinne/Speier) vorsehen.',
      if (auskragend && !thermischGetrennt) 'Auskragende Platte: Wärmebrücke – thermische Trennung (z. B. Isokorb) oder vorgestellter Balkon; WDVS umläuft die Platte.',
      'Türschwelle zur Balkontür: Abdichtung 150 mm hoch oder barrierefrei ≤ 20 mm mit Rinne.',
      'Wohnflächenanteil Balkon nach WoFlV: in der Regel 1/4, höchstens 1/2 (${(flaecheM2 / 4).toStringAsFixed(1).replaceAll('.', ',')}–${(flaecheM2 / 2).toStringAsFixed(1).replaceAll('.', ',')} m²).',
    ];

// ------------------------------------------------------------- Sockelleisten

/// Sockelleisten: Länge (m) = Umfang − Türbreiten, mit Verschnitt; Stäbe à [stab] m,
/// Innen-/Außenecken aus dem Raumumriss (konvex/konkav), Endkappen je Tür.
({double laenge, int staebe, int innenecken, int aussenecken, int endkappen}) sockelleisten({
  required double umfangMm,
  required List<double> tuerbreitenMm,
  required int innenecken,
  required int aussenecken,
  double verschnitt = 8,
  double stab = 2.4,
}) {
  final netto = math.max(0.0, umfangMm - tuerbreitenMm.fold<double>(0, (a, b) => a + b)) / 1000;
  final l = netto * (1 + verschnitt / 100);
  return (laenge: l, staebe: (l / stab).ceil(), innenecken: innenecken, aussenecken: aussenecken, endkappen: tuerbreitenMm.length * 2);
}

/// Innen- und Außenecken eines Raumumrisses (Polygon in mm).
(int innen, int aussen) eckenZaehlen(List<(double, double)> umriss) {
  if (umriss.length < 3) return (0, 0);
  var flaeche = 0.0;
  for (var i = 0; i < umriss.length; i++) {
    final a = umriss[i], b = umriss[(i + 1) % umriss.length];
    flaeche += a.$1 * b.$2 - b.$1 * a.$2;
  }
  final ccw = flaeche > 0;
  var innen = 0, aussen = 0;
  for (var i = 0; i < umriss.length; i++) {
    final a = umriss[(i - 1 + umriss.length) % umriss.length], b = umriss[i], c = umriss[(i + 1) % umriss.length];
    final kreuz = (b.$1 - a.$1) * (c.$2 - b.$2) - (b.$2 - a.$2) * (c.$1 - b.$1);
    if (kreuz.abs() < 1e-6) continue;
    // Ecke, die in den Raum zeigt (konvex vom Raum aus) = Innenecke der Leiste
    if ((kreuz > 0) == ccw) {
      innen++;
    } else {
      aussen++;
    }
  }
  return (innen, aussen);
}

// ----------------------------------------------------- Abgehängte Felder

/// Material eines abgehängten Deckenfelds (Gipskarton auf Unterkonstruktion)
/// mit Schattenfuge: GK-Fläche, CD-Profile (Achsabstand 400 mm), UD-Randprofil,
/// Abhänger (≈ 1,1 je m² bei 900 mm Raster), Schattenfugenprofil.
({double gk, double cd, double ud, int abhaenger, double schattenfuge}) deckenfeldMaterial(double flaecheM2, double umfangM, {int schattenfugeMm = 15}) => (
      gk: flaecheM2 * 1.1,
      cd: flaecheM2 / 0.4 * 1.05,
      ud: umfangM,
      abhaenger: (flaecheM2 * 1.1).ceil(),
      schattenfuge: schattenfugeMm > 0 ? umfangM : 0,
    );

// -------------------------------------------------- Bodeneinbaustrahler

/// Passt ein Bodeneinbaustrahler in den Aufbau? [schichten] = Dicken (mm) von
/// oben nach unten, [abdichtungIndex] = erste Schicht, die nicht durchstoßen
/// werden darf (Abdichtung/Dämmung unter Estrich), [einbautiefe] laut Datenblatt.
({bool passt, double verfuegbar, List<String> hinweise}) bodenstrahlerPruefen(List<int> schichten, double einbautiefe, {int? abdichtungIndex, bool aussen = false}) {
  final bis = abdichtungIndex ?? schichten.length;
  final verfuegbar = schichten.take(bis).fold<int>(0, (a, b) => a + b).toDouble();
  final h = <String>[
    if (einbautiefe > verfuegbar) 'Einbautiefe ${einbautiefe.round()} mm, verfügbar ${verfuegbar.round()} mm bis zur Abdichtung/Dämmung – Strahler mit geringerer Tiefe oder Aufbau anpassen.',
    'Leerrohr (M20) zum Strahler in der Ausgleichs-/Estrichschicht führen, Zugang für Tausch.',
    if (aussen) 'Außen: Einbaugehäuse mit Drainage (Kies), Schutzart IP67, Überfahrbarkeit prüfen.',
  ];
  return (passt: einbautiefe <= verfuegbar, verfuegbar: verfuegbar, hinweise: h);
}
