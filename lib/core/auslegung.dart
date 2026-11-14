import 'dart:math' as math;

/// Kabel- und Rohrauslegung als Planungshilfe (keine Prüfung nach Norm):
/// Querschnitt, Absicherung, Spannungsfall und Abschaltbedingung für
/// Stromkreise, Dimension und Geschwindigkeit für Heizungs- und
/// Trinkwasserleitungen. Werte nach DIN VDE 0298-4 (Belastbarkeit Cu/PVC,
/// 30 °C), DIN 18015-1 (Spannungsfall) und DIN 1988-300 (Spitzendurchfluss).

// ------------------------------------------------------------------ Kabel

enum Verlegeart { a1, a2, b1, b2, c, e }

extension VerlegeartText on Verlegeart {
  String get kurz => name.toUpperCase();
  String get label => switch (this) {
        Verlegeart.a1 => 'A1 – Aderleitungen im Rohr in Dämmung',
        Verlegeart.a2 => 'A2 – Mantelleitung im Rohr in Dämmung',
        Verlegeart.b1 => 'B1 – Aderleitungen im Rohr auf/in der Wand',
        Verlegeart.b2 => 'B2 – Mantelleitung im Rohr/Kanal auf/in der Wand',
        Verlegeart.c => 'C – direkt auf/in der Wand (Stegleitung, unter Putz)',
        Verlegeart.e => 'E – frei in Luft (Kabelrinne, Wanne)',
      };
}

/// Standardquerschnitte in mm².
const querschnitte = [1.5, 2.5, 4.0, 6.0, 10.0, 16.0, 25.0, 35.0];

/// Genormte Bemessungsströme von Leitungsschutzschaltern in A.
const nennstroeme = [6, 10, 13, 16, 20, 25, 32, 40, 50, 63];

/// Belastbarkeit Iz in A (Cu, PVC 70 °C, 30 °C Umgebung): je Verlegeart
/// für [2 belastete Adern, 3 belastete Adern] je Querschnitt aus [querschnitte].
const _iz = <Verlegeart, List<List<double>>>{
  Verlegeart.a1: [[15.5, 13.5], [19.5, 18], [26, 24], [34, 31], [46, 42], [61, 56], [80, 73], [99, 89]],
  Verlegeart.a2: [[15.5, 13], [18.5, 17.5], [25, 23], [32, 29], [43, 39], [57, 52], [75, 68], [92, 83]],
  Verlegeart.b1: [[17.5, 15.5], [24, 21], [32, 28], [41, 36], [57, 50], [76, 68], [101, 89], [125, 110]],
  Verlegeart.b2: [[16.5, 15], [23, 20], [30, 27], [38, 34], [52, 46], [69, 62], [90, 80], [111, 99]],
  Verlegeart.c: [[19.5, 17.5], [27, 24], [36, 32], [46, 41], [63, 57], [85, 76], [112, 96], [138, 119]],
  Verlegeart.e: [[22, 18.5], [30, 25], [40, 34], [51, 43], [70, 60], [94, 80], [119, 101], [148, 126]],
};

/// Belastbarkeit ohne Umrechnungsfaktoren.
double belastbarkeit(Verlegeart art, double querschnitt, {required bool drehstrom}) {
  final i = querschnitte.indexWhere((q) => (q - querschnitt).abs() < 0.01);
  if (i < 0) {
    // Zwischenwerte: nächstkleineren Normquerschnitt nehmen (sichere Seite)
    final k = querschnitte.lastIndexWhere((q) => q < querschnitt);
    if (k < 0) return 0;
    return _iz[art]![k][drehstrom ? 1 : 0];
  }
  return _iz[art]![i][drehstrom ? 1 : 0];
}

/// Umrechnungsfaktor für Häufung (gebündelt auf Wand/in Rohr, DIN VDE 0298-4 Tab. 21).
double haeufungsFaktor(int stromkreise) {
  const f = {1: 1.0, 2: 0.80, 3: 0.70, 4: 0.65, 5: 0.60, 6: 0.57, 7: 0.54, 8: 0.52, 9: 0.50, 12: 0.45, 16: 0.41, 20: 0.38};
  if (stromkreise <= 1) return 1;
  final keys = f.keys.toList()..sort();
  for (final k in keys.reversed) {
    if (stromkreise >= k) return f[k]!;
  }
  return 1;
}

/// Umrechnungsfaktor für die Umgebungstemperatur (PVC).
double temperaturFaktor(double grad) {
  const t = [(10.0, 1.22), (15.0, 1.17), (20.0, 1.12), (25.0, 1.06), (30.0, 1.0), (35.0, 0.94), (40.0, 0.87), (45.0, 0.79), (50.0, 0.71), (55.0, 0.61), (60.0, 0.50)];
  if (grad <= t.first.$1) return t.first.$2;
  if (grad >= t.last.$1) return t.last.$2;
  for (var i = 0; i + 1 < t.length; i++) {
    final (a, fa) = t[i];
    final (b, fb) = t[i + 1];
    if (grad >= a && grad <= b) return fa + (fb - fa) * (grad - a) / (b - a);
  }
  return 1;
}

class KabelEingabe {
  const KabelEingabe({
    required this.leistungW,
    required this.laengeM,
    this.drehstrom = false,
    this.cosPhi = 1,
    this.art = Verlegeart.c,
    this.haeufung = 1,
    this.umgebungC = 30,
    this.nennstrom,
    this.charakteristik = 'B',
    this.querschnitt,
    this.zVorOhm = 0.3,
    this.maxSpannungsfall = 3,
    this.gleichzeitigkeit = 1,
  });

  final double leistungW;
  final double laengeM; // einfache Länge Verteiler → letzter Verbraucher
  final bool drehstrom;
  final double cosPhi;
  final Verlegeart art;
  final int haeufung; // Stromkreise im selben Bündel
  final double umgebungC;
  final int? nennstrom; // vorhandene Absicherung (A) oder null = vorschlagen
  final String charakteristik; // B, C, D, K
  final double? querschnitt; // vorhandener Querschnitt (mm²) oder null = vorschlagen
  final double zVorOhm; // Schleifenimpedanz bis zum Verteiler
  final double maxSpannungsfall; // %
  final double gleichzeitigkeit; // 0…1
}

class KabelErgebnis {
  KabelErgebnis({
    required this.ib,
    required this.nennstrom,
    required this.querschnitt,
    required this.iz,
    required this.spannungsfall,
    required this.zs,
    required this.zsMax,
    required this.maxLaenge,
    required this.hinweise,
  });

  final double ib; // Betriebsstrom A
  final int nennstrom;
  final double querschnitt;
  final double iz; // Belastbarkeit inkl. Faktoren
  final double spannungsfall; // %
  final double zs; // Schleifenimpedanz Ω
  final double zsMax; // zulässig für 0,4 s
  final double maxLaenge; // m, bei der ΔU oder Zs gerade noch passen
  final List<String> hinweise;

  bool get ok => hinweise.isEmpty;
}

const _kappa = 56.0; // Cu bei 20 °C, m/(Ω·mm²)
const _kappaWarm = 46.0; // Cu bei 70 °C (Abschaltbedingung)

double _ia(int inn, String ch) => inn * switch (ch) { 'C' => 10.0, 'D' => 20.0, 'K' => 12.0, _ => 5.0 };

/// Betriebsstrom aus Leistung.
double betriebsstrom(double leistungW, {bool drehstrom = false, double cosPhi = 1}) =>
    drehstrom ? leistungW / (math.sqrt(3) * 400 * cosPhi) : leistungW / (230 * cosPhi);

/// Spannungsfall in % bei Strom [i], einfacher Länge [l] und Querschnitt [a].
double spannungsfall(double i, double l, double a, {bool drehstrom = false, double cosPhi = 1}) => drehstrom
    ? math.sqrt(3) * l * i * cosPhi / (_kappa * a) / 400 * 100
    : 2 * l * i * cosPhi / (_kappa * a) / 230 * 100;

KabelErgebnis _pruefen(KabelEingabe e, double a, int inn) {
  final ib = betriebsstrom(e.leistungW * e.gleichzeitigkeit, drehstrom: e.drehstrom, cosPhi: e.cosPhi);
  final iz = belastbarkeit(e.art, a, drehstrom: e.drehstrom) * haeufungsFaktor(e.haeufung) * temperaturFaktor(e.umgebungC);
  final du = spannungsfall(ib, e.laengeM, a, drehstrom: e.drehstrom, cosPhi: e.cosPhi);
  final zs = e.zVorOhm + 2 * e.laengeM / (_kappaWarm * a);
  final zsMax = 230 / _ia(inn, e.charakteristik);
  // größte Länge, bei der Spannungsfall und Abschaltbedingung gerade passen
  final lDu = ib <= 0 ? double.infinity : e.maxSpannungsfall / spannungsfall(ib, 1, a, drehstrom: e.drehstrom, cosPhi: e.cosPhi);
  final lZs = math.max(0.0, (zsMax - e.zVorOhm) * _kappaWarm * a / 2);
  final h = <String>[
    if (ib > inn) 'Betriebsstrom ${_z(ib)} A über der Absicherung $inn A',
    if (inn > iz) 'Absicherung $inn A über der Belastbarkeit ${_z(iz)} A (${e.art.kurz}, Häufung ${e.haeufung}, ${e.umgebungC.round()} °C)',
    if (du > e.maxSpannungsfall) 'Spannungsfall ${_z(du)} % über ${_z(e.maxSpannungsfall)} %',
    if (zs > zsMax) 'Schleifenimpedanz ${_z(zs)} Ω über ${_z(zsMax)} Ω – Abschaltung in 0,4 s nicht sicher (nur mit RCD)',
  ];
  return KabelErgebnis(ib: ib, nennstrom: inn, querschnitt: a, iz: iz, spannungsfall: du, zs: zs, zsMax: zsMax, maxLaenge: math.min(lDu, lZs), hinweise: h);
}

String _z(double v) => v.toStringAsFixed(v >= 10 ? 0 : 1).replaceAll('.', ',');

/// Prüft die vorhandene Auslegung (mit [KabelEingabe.querschnitt] und
/// [KabelEingabe.nennstrom]); fehlende Werte werden vorgeschlagen.
KabelErgebnis kabelPruefen(KabelEingabe e) {
  final v = kabelVorschlag(e);
  return _pruefen(e, e.querschnitt ?? v.querschnitt, e.nennstrom ?? v.nennstrom);
}

/// Kleinster Querschnitt (ab 1,5 mm²) und passende Absicherung, bei denen
/// Belastbarkeit, Spannungsfall und Abschaltbedingung eingehalten sind.
KabelErgebnis kabelVorschlag(KabelEingabe e) {
  final ib = betriebsstrom(e.leistungW * e.gleichzeitigkeit, drehstrom: e.drehstrom, cosPhi: e.cosPhi);
  KabelErgebnis? letztes;
  for (final a in querschnitte) {
    if (e.querschnitt != null && a < e.querschnitt! - 0.01) continue;
    final kandidaten = e.nennstrom != null ? [e.nennstrom!] : [for (final n in nennstroeme) if (n >= ib) n];
    // Steckdosen-/Lichtkreise üblich ab 10 A (bzw. 16 A bei 1,5 mm² nur, wenn es passt)
    for (final inn in kandidaten) {
      final r = _pruefen(e, a, inn);
      letztes = r;
      if (r.ok) return r;
    }
  }
  return letztes ?? _pruefen(e, querschnitte.last, nennstroeme.last);
}

/// Querschnitt aus einer Leitungsbezeichnung lesen, z. B. „NYM-J 3x2,5“ → 2,5.
double? querschnittAusText(String text) {
  final m = RegExp(r'(\d+)\s*[x×]\s*(\d+(?:[.,]\d+)?)').firstMatch(text);
  if (m == null) return null;
  return double.tryParse(m.group(2)!.replaceAll(',', '.'));
}

/// Aderzahl aus einer Leitungsbezeichnung, z. B. „NYM-J 5x2,5“ → 5.
int? adernAusText(String text) {
  final m = RegExp(r'(\d+)\s*[x×]\s*\d').firstMatch(text);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Leitungsbezeichnung aus Querschnitt und Drehstrom (NYM-J).
String leitungText(double querschnitt, {bool drehstrom = false}) =>
    'NYM-J ${drehstrom ? 5 : 3}x${querschnitt.toStringAsFixed(querschnitt % 1 == 0 ? 0 : 1).replaceAll('.', ',')}';

// ------------------------------------------------------------------- Rohre

enum Medium { heizung, trinkwasser, kuehlung }

extension MediumText on Medium {
  String get label => switch (this) { Medium.heizung => 'Heizung', Medium.trinkwasser => 'Trinkwasser', Medium.kuehlung => 'Kühlung' };
}

/// Ein Rohr mit Außenmaß × Wandstärke und Innendurchmesser (mm).
typedef RohrMass = ({String name, String system, double innen});

const rohrMasse = <RohrMass>[
  (name: '16×2', system: 'Mehrschichtverbund', innen: 12),
  (name: '20×2', system: 'Mehrschichtverbund', innen: 16),
  (name: '26×3', system: 'Mehrschichtverbund', innen: 20),
  (name: '32×3', system: 'Mehrschichtverbund', innen: 26),
  (name: '40×3,5', system: 'Mehrschichtverbund', innen: 33),
  (name: '50×4', system: 'Mehrschichtverbund', innen: 42),
  (name: '63×4,5', system: 'Mehrschichtverbund', innen: 54),
  (name: '15×1', system: 'Kupfer', innen: 13),
  (name: '18×1', system: 'Kupfer', innen: 16),
  (name: '22×1', system: 'Kupfer', innen: 20),
  (name: '28×1,5', system: 'Kupfer', innen: 25),
  (name: '35×1,5', system: 'Kupfer', innen: 32),
  (name: '42×1,5', system: 'Kupfer', innen: 39),
  (name: '54×2', system: 'Kupfer', innen: 50),
  (name: '15×1,2', system: 'Edelstahl', innen: 12.6),
  (name: '18×1,2', system: 'Edelstahl', innen: 15.6),
  (name: '22×1,5', system: 'Edelstahl', innen: 19),
  (name: '28×1,5', system: 'Edelstahl', innen: 25),
  (name: '35×1,5', system: 'Edelstahl', innen: 32),
];

const rohrSysteme = ['Mehrschichtverbund', 'Kupfer', 'Edelstahl'];

/// Berechnungsdurchfluss VR einer Entnahmestelle in l/s (DIN 1988-300, je Kalt bzw. Warm).
const entnahmeArten = <String, double>{
  'Waschtisch': 0.07,
  'Dusche': 0.15,
  'Badewanne': 0.15,
  'WC (Spülkasten)': 0.13,
  'Urinal': 0.30,
  'Bidet': 0.07,
  'Spüle': 0.07,
  'Geschirrspüler': 0.07,
  'Waschmaschine': 0.15,
  'Ausgussbecken': 0.15,
  'Außenzapfstelle': 0.30,
};

/// Spitzendurchfluss in l/s aus der Summe der Berechnungsdurchflüsse
/// (Wohngebäude: a = 1,48, b = 0,19, c = 0,94; unter 0,2 l/s gilt die Summe,
/// nie mehr als die Summe).
double spitzendurchfluss(double summeVr) {
  if (summeVr <= 0.2) return summeVr;
  return math.min(summeVr, 1.48 * math.pow(summeVr, 0.19) - 0.94);
}

class RohrEingabe {
  const RohrEingabe({
    required this.medium,
    required this.laengeM,
    this.leistungW = 0,
    this.spreizungK = 10,
    this.summeVr = 0,
    this.system = 'Mehrschichtverbund',
    this.innen,
    this.vMax,
    this.rMax,
  });

  final Medium medium;
  final double laengeM;
  final double leistungW; // Heizung/Kühlung
  final double spreizungK;
  final double summeVr; // Trinkwasser: Summe der Berechnungsdurchflüsse (l/s)
  final String system;
  final double? innen; // vorhandener Innendurchmesser (mm)
  final double? vMax; // m/s
  final double? rMax; // Pa/m
}

class RohrErgebnis {
  RohrErgebnis({required this.durchflussLh, required this.mass, required this.v, required this.rProM, required this.pa, required this.hinweise});
  final double durchflussLh;
  final RohrMass mass;
  final double v;
  final double rProM;
  final double pa;
  final List<String> hinweise;
  bool get ok => hinweise.isEmpty;
}

const _rho = 990.0;

double _nu(Medium m) => switch (m) { Medium.heizung => 0.55e-6, Medium.trinkwasser => 1.0e-6, Medium.kuehlung => 1.3e-6 };

/// Volumenstrom in l/h.
double rohrDurchfluss(RohrEingabe e) => switch (e.medium) {
      Medium.trinkwasser => spitzendurchfluss(e.summeVr) * 3600,
      _ => e.spreizungK <= 0 ? 0 : e.leistungW / (1.163 * e.spreizungK),
    };

/// Druckgefälle (Pa/m) und Geschwindigkeit; glattes Rohr (Blasius / laminar).
({double r, double v}) rohrGefaelle(double lh, double innenMm, Medium medium) {
  final d = innenMm / 1000;
  final a = math.pi * d * d / 4;
  final v = lh / 1000 / 3600 / a;
  if (v <= 0) return (r: 0, v: 0);
  final re = v * d / _nu(medium);
  final lambda = re < 2300 ? 64 / re : 0.3164 * math.pow(re, -0.25);
  return (r: lambda / d * _rho * v * v / 2, v: v);
}

double _vMax(RohrEingabe e) => e.vMax ?? switch (e.medium) { Medium.trinkwasser => 2.0, _ => 0.7 };
double _rMax(RohrEingabe e) => e.rMax ?? switch (e.medium) { Medium.trinkwasser => 2500, _ => 150 };

RohrErgebnis _rohr(RohrEingabe e, RohrMass m) {
  final lh = rohrDurchfluss(e);
  final g = rohrGefaelle(lh, m.innen, e.medium);
  final h = <String>[
    if (g.v > _vMax(e)) 'Geschwindigkeit ${g.v.toStringAsFixed(2).replaceAll('.', ',')} m/s über ${_vMax(e).toStringAsFixed(1).replaceAll('.', ',')} m/s',
    if (g.r > _rMax(e)) 'Druckgefälle ${g.r.round()} Pa/m über ${_rMax(e).round()} Pa/m',
  ];
  return RohrErgebnis(durchflussLh: lh, mass: m, v: g.v, rProM: g.r, pa: g.r * e.laengeM, hinweise: h);
}

/// Kleinste Dimension im gewählten System, die Geschwindigkeit und Druckgefälle einhält.
RohrErgebnis rohrVorschlag(RohrEingabe e) {
  final masse = [for (final m in rohrMasse) if (m.system == e.system) m]..sort((a, b) => a.innen.compareTo(b.innen));
  RohrErgebnis? letztes;
  for (final m in masse) {
    if (e.innen != null && m.innen < e.innen! - 0.01) continue;
    final r = _rohr(e, m);
    letztes = r;
    if (r.ok) return r;
  }
  return letztes ?? _rohr(e, rohrMasse.first);
}

/// Prüft ein vorhandenes Rohr (Innendurchmesser) oder schlägt eins vor.
RohrErgebnis rohrPruefen(RohrEingabe e) {
  final i = e.innen;
  if (i == null) return rohrVorschlag(e);
  final m = rohrMasse.where((m) => m.system == e.system && (m.innen - i).abs() < 0.3).firstOrNull ??
      (name: 'Ø ${i.toStringAsFixed(0)} innen', system: e.system, innen: i);
  return _rohr(e, m);
}

// ------------------------------------------------------- Kabel-/Rohrliste

/// Ein Stück Leitung für die Kabel-/Rohrliste.
typedef LeitungsStueck = ({String art, String bezeichnung, double laengeM, String woher, bool geschaetzt});

/// Gesammelte Länge je Leitungsart für den Einkauf.
class LeitungsSumme {
  LeitungsSumme(this.art, this.bezeichnung);
  final String art; // Kabel, Rohr, Leerrohr, Kanal …
  final String bezeichnung; // z. B. NYM-J 3x1,5
  double gezeichnet = 0; // m aus gezeichneten Leitungen
  double geschaetzt = 0; // m aus Stromkreisen ohne gezeichnete Leitung
  final woher = <String>{};

  double get summe => gezeichnet + geschaetzt;

  /// Einkaufslänge mit Zuschlag, auf ganze Meter aufgerundet.
  double einkauf(double zuschlagProzent) => summe <= 0 ? 0 : (summe * (1 + zuschlagProzent / 100) - 1e-9).ceilToDouble();

  /// Aufteilung in Ringe/Rollen (größte zuerst), z. B. 2×100 m + 1×50 m.
  List<(int, int)> ringe(double zuschlagProzent, List<int> groessen) {
    var rest = einkauf(zuschlagProzent);
    if (rest <= 0 || groessen.isEmpty) return const [];
    final g = [...groessen]..sort((a, b) => b.compareTo(a));
    final aus = <(int, int)>[];
    while (rest > 0) {
      // passt der Rest in einen Ring, den kleinsten passenden nehmen
      final passt = g.where((x) => x >= rest).toList();
      if (passt.isNotEmpty) {
        aus.add((1, passt.last));
        break;
      }
      final n = (rest / g.first).floor();
      aus.add((n, g.first));
      rest -= n * g.first;
    }
    return aus;
  }
}

/// Fasst Leitungsstücke nach Art und Bezeichnung zusammen.
List<LeitungsSumme> leitungsliste(Iterable<LeitungsStueck> stuecke) {
  final m = <String, LeitungsSumme>{};
  for (final s in stuecke) {
    if (s.laengeM <= 0 || s.bezeichnung.trim().isEmpty) continue;
    final z = m.putIfAbsent('${s.art}|${s.bezeichnung}', () => LeitungsSumme(s.art, s.bezeichnung.trim()));
    if (s.geschaetzt) {
      z.geschaetzt += s.laengeM;
    } else {
      z.gezeichnet += s.laengeM;
    }
    if (s.woher.isNotEmpty) z.woher.add(s.woher);
  }
  return m.values.toList()
    ..sort((a, b) => a.art != b.art ? a.art.compareTo(b.art) : a.bezeichnung.compareTo(b.bezeichnung));
}

/// Übliche Ring-/Rollengrößen in m je Art.
List<int> ringGroessen(String art, String bezeichnung) {
  final b = bezeichnung.toLowerCase();
  if (art == 'Kabel') {
    if (b.contains('cat') || b.contains('netzwerk')) return const [500, 305, 100, 50];
    if (b.contains('nym') || b.contains('nyy')) return const [100, 50, 25];
    return const [500, 100, 50];
  }
  if (art == 'Leerrohr') return const [50, 25];
  if (art == 'Rohr') {
    if (b.contains('kupfer') || b.contains('edelstahl')) return const [5]; // Stangen à 5 m
    return const [200, 100, 50];
  }
  return const [];
}

/// Geschätzte Kabellänge eines Stromkreises ohne gezeichnete Leitung:
/// vom Verteiler der Reihe nach zum jeweils nächsten Gerät (rechtwinklig
/// gemessen), je Gerät Steig-/Fallstrecke, plus Reserve am Verteiler.
double stromkreisLaengeSchaetzen({
  required (double, double) verteiler,
  required List<(double, double, double)> geraete, // x, y (mm), Höhe über FFB (mm)
  double raumhoeheMm = 2500,
  double reserveM = 1.5,
  double geschossZuschlagM = 0,
}) {
  if (geraete.isEmpty) return 0;
  var pos = verteiler;
  final offen = [...geraete];
  var mm = 0.0;
  while (offen.isNotEmpty) {
    offen.sort((a, b) => ((a.$1 - pos.$1).abs() + (a.$2 - pos.$2).abs()).compareTo((b.$1 - pos.$1).abs() + (b.$2 - pos.$2).abs()));
    final g = offen.removeAt(0);
    mm += (g.$1 - pos.$1).abs() + (g.$2 - pos.$2).abs();
    // Installationszone unter der Decke ↔ Gerät: hin und zurück
    mm += 2 * math.max(300.0, raumhoeheMm - 300 - g.$3);
    pos = (g.$1, g.$2);
  }
  return mm / 1000 + reserveM + geschossZuschlagM;
}
