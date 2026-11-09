import 'anschluesse.dart';
import 'raumerkennung.dart';

/// Heizkreisverteiler für Flächenheizung: Ausstattung, Montage, Belegung.
enum Montage { unterputz, aufputz, frei, vorwand }

extension MontageText on Montage {
  String get label => switch (this) {
        Montage.unterputz => 'Unterputzschrank',
        Montage.aufputz => 'Aufputzschrank',
        Montage.frei => 'frei an der Wand (ohne Schrank)',
        Montage.vorwand => 'in Vorwand / Trockenbau',
      };

  /// Tiefe des Schranks bzw. Verteilers in mm.
  int get tiefe => switch (this) {
        Montage.unterputz => 110,
        Montage.aufputz => 125,
        Montage.frei => 90,
        Montage.vorwand => 110,
      };

  /// Liegt der Verteiler in der Wand (sonst davor)?
  bool get inWand => this == Montage.unterputz || this == Montage.vorwand;
}

const antriebe = ['230 V stromlos zu', '24 V stromlos zu', '230 V stromlos offen', '24 V stromlos offen', 'keine (Handventile)'];
const dimensionen = ['DN 20 (¾″)', 'DN 25 (1″)', 'DN 32 (1¼″)'];

/// Ventile im Vorlauf je Abgang.
const vorlaufVentile = [
  'Durchflussmesser (Topmeter)',
  'Regulierventil mit Skala',
  'Absperrventil',
  'keines',
];

/// Ventile im Rücklauf je Abgang (dort sitzen die Stellantriebe).
const ruecklaufVentile = [
  'Thermostatventil (für Stellantrieb)',
  'Ventil mit Voreinstellung',
  'druckunabhängiges Regelventil (dynamisch)',
  'Handregulierventil',
];

class VerteilerDaten {
  VerteilerDaten({
    this.abgaenge = 6,
    this.montage = Montage.unterputz,
    this.anschlussLinks = true,
    this.antrieb = '230 V stromlos zu',
    String? vorlaufVentil,
    bool? durchflussmesser,
    this.ruecklaufVentil = 'Thermostatventil (für Stellantrieb)',
    this.kugelhaehne = true,
    this.entlueftung = true,
    this.mischer = false,
    this.pumpe = false,
    this.waermemengenzaehler = false,
    this.thermometer = false,
    this.ueberstroemventil = false,
    this.temperaturbegrenzer = false,
    this.schmutzfaenger = false,
    this.dimension = 'DN 25 (1″)',
    this.zuleitung = 0,
    List<String?>? kreise,
  })  : vorlaufVentil = vorlaufVentil ?? (durchflussmesser == false ? 'keines' : vorlaufVentile.first),
        kreise = kreise ?? List<String?>.filled(abgaenge, null);

  int abgaenge;
  Montage montage;
  bool anschlussLinks; // Vor-/Rücklauf kommen von links
  String antrieb;
  String vorlaufVentil; // je Abgang im Vorlauf
  String ruecklaufVentil; // je Abgang im Rücklauf
  bool kugelhaehne; // Absperrung Vor-/Rücklauf
  bool entlueftung; // Entlüftung/Entleerung (KFE)
  bool mischer; // Festwert-/Mischregelung
  bool pumpe; // eigene Umwälzpumpe (mit Mischer)
  bool waermemengenzaehler;
  bool thermometer; // Thermometer Vor- und Rücklauf
  bool ueberstroemventil; // Differenzdruck-Überströmventil zwischen den Balken
  bool temperaturbegrenzer; // Sicherheitstemperaturbegrenzer (bei Mischer/Pumpe Pflicht)
  bool schmutzfaenger; // in der Zuleitung (Vorlauf)
  String dimension; // Zuleitung
  int zuleitung; // einfache Länge der Zuleitung vom Wärmeerzeuger in mm
  List<String?> kreise; // Heizkreis-Objekt-ID je Abgang

  bool get durchflussmesser => vorlaufVentil.startsWith('Durchflussmesser');
  set durchflussmesser(bool x) => vorlaufVentil = x ? vorlaufVentile.first : 'keines';

  /// Übliche Schrankbreite (Unterputz) nach Anzahl der Abgänge, mm.
  int get schrankBreite {
    final mitMischer = mischer || pumpe ? 2 : 0;
    final n = abgaenge + mitMischer + (waermemengenzaehler ? 1 : 0);
    if (n <= 3) return 550;
    if (n <= 5) return 750;
    if (n <= 7) return 850;
    if (n <= 9) return 1000;
    if (n <= 11) return 1150;
    return 1300;
  }

  int get schrankHoehe => 710;

  /// Abgänge anpassen, Belegung behalten soweit möglich.
  void abgaengeSetzen(int n) {
    abgaenge = n.clamp(1, 16);
    kreise = [for (var i = 0; i < abgaenge; i++) i < kreise.length ? kreise[i] : null];
  }

  Map<String, dynamic> toJson() => {
        'abgaenge': abgaenge,
        'montage': montage.name,
        'anschluss_links': anschlussLinks,
        'antrieb': antrieb,
        'vorlauf_ventil': vorlaufVentil,
        'ruecklauf_ventil': ruecklaufVentil,
        'durchflussmesser': durchflussmesser,
        'kugelhaehne': kugelhaehne,
        'entlueftung': entlueftung,
        'mischer': mischer,
        'pumpe': pumpe,
        'wmz': waermemengenzaehler,
        'thermometer': thermometer,
        'ueberstroemventil': ueberstroemventil,
        'stb': temperaturbegrenzer,
        'schmutzfaenger': schmutzfaenger,
        'dimension': dimension,
        'zuleitung_mm': zuleitung,
        'kreise': kreise,
      };

  static VerteilerDaten ausJson(Map<String, dynamic> m) {
    final n = (m['abgaenge'] as num?)?.toInt() ?? 6;
    final k = (m['kreise'] as List?)?.map((e) => e as String?).toList();
    final vl = m['vorlauf_ventil'] as String?;
    final rl = m['ruecklauf_ventil'] as String?;
    return VerteilerDaten(
      abgaenge: n,
      montage: Montage.values.where((x) => x.name == m['montage']).firstOrNull ?? Montage.unterputz,
      anschlussLinks: m['anschluss_links'] as bool? ?? true,
      antrieb: m['antrieb'] as String? ?? antriebe.first,
      vorlaufVentil: vorlaufVentile.contains(vl) ? vl : null,
      durchflussmesser: m['durchflussmesser'] as bool? ?? true,
      ruecklaufVentil: ruecklaufVentile.contains(rl) ? rl! : ruecklaufVentile.first,
      kugelhaehne: m['kugelhaehne'] as bool? ?? true,
      entlueftung: m['entlueftung'] as bool? ?? true,
      mischer: m['mischer'] as bool? ?? false,
      pumpe: m['pumpe'] as bool? ?? false,
      waermemengenzaehler: m['wmz'] as bool? ?? false,
      thermometer: m['thermometer'] as bool? ?? false,
      ueberstroemventil: m['ueberstroemventil'] as bool? ?? false,
      temperaturbegrenzer: m['stb'] as bool? ?? false,
      schmutzfaenger: m['schmutzfaenger'] as bool? ?? false,
      dimension: m['dimension'] as String? ?? dimensionen[1],
      zuleitung: (m['zuleitung_mm'] as num?)?.toInt() ?? 0,
      kreise: [for (var i = 0; i < n; i++) k != null && i < k.length ? k[i] : null],
    );
  }

  /// Hinweise zur Ausstattung (fachliche Plausibilität).
  List<String> hinweise() => [
        if ((mischer || pumpe) && !temperaturbegrenzer)
          'Mit Mischer/Pumpe ist ein Sicherheitstemperaturbegrenzer (STB) für die Fußbodenheizung vorgeschrieben.',
        if (pumpe && !ueberstroemventil && !ruecklaufVentil.startsWith('druckunabhängig'))
          'Eigene Pumpe: Überströmventil oder druckunabhängige Ventile vorsehen, falls alle Kreise schließen.',
        if (!antrieb.startsWith('keine') && ruecklaufVentil == 'Handregulierventil')
          'Stellantriebe brauchen Thermostat- oder Regelventile im Rücklauf, keine Handregulierventile.',
      ];

  /// Stückliste der Ausstattung (Text, Anzahl).
  List<(String, int)> stueckliste() => [
        ('Heizkreisverteiler $abgaenge Abgänge', 1),
        if (montage == Montage.unterputz || montage == Montage.vorwand) ('Unterputz-Verteilerschrank $schrankBreite mm', 1),
        if (montage == Montage.aufputz) ('Aufputz-Verteilerschrank $schrankBreite mm', 1),
        if (!antrieb.startsWith('keine')) ('Stellantrieb $antrieb', abgaenge),
        if (vorlaufVentil != 'keines') ('$vorlaufVentil (Vorlauf)', abgaenge),
        ('$ruecklaufVentil (Rücklauf)', abgaenge),
        ('Anschlussverschraubung Heizrohr', abgaenge * 2),
        if (kugelhaehne) ('Kugelhahn $dimension', 2),
        if (entlueftung) ('Entlüftung / KFE-Hahn', 2),
        if (mischer) ('Mischer / Festwertregelung', 1),
        if (pumpe) ('Umwälzpumpe', 1),
        if (temperaturbegrenzer) ('Sicherheitstemperaturbegrenzer (STB)', 1),
        if (ueberstroemventil) ('Differenzdruck-Überströmventil', 1),
        if (thermometer) ('Thermometer Vor-/Rücklauf', 2),
        if (schmutzfaenger) ('Schmutzfänger $dimension', 1),
        if (waermemengenzaehler) ('Wärmemengenzähler', 1),
      ];
}

/// Wand als Achse mit Dicke (mm) – für die Lage des Verteilerschranks.
typedef WandStrecke = ({Punkt a, Punkt b, double dicke});

/// Lage des Verteilerschranks im Grundriss: Mitte auf der Wandachsenprojektion,
/// Wandrichtung [u], Normale [n] zur Seite des Verteilerpunkts (Raumseite),
/// Abstand der Vorder- und Hinterkante von der Achse (positiv = Raumseite).
typedef VerteilerLage = ({Punkt mitte, Punkt u, Punkt n, double vorn, double hinten});

/// Bestimmt die Lage an der nächsten Wand (bis [fang] mm Abstand): Unterputz
/// und Vorwand liegen in der Wand, Aufputz und frei davor – jeweils auf der
/// Seite, auf der der Verteilerpunkt liegt. Ohne Wand liegt er waagerecht um
/// den Punkt, Vorderseite nach unten (+y).
VerteilerLage verteilerLage(Punkt p, VerteilerDaten d, Iterable<WandStrecke> waende, {double fang = 600}) {
  final tiefe = d.montage.tiefe.toDouble();
  WandStrecke? beste;
  var abstand = fang;
  for (final w in waende) {
    final ab = w.b - w.a;
    final l2 = ab.x * ab.x + ab.y * ab.y;
    if (l2 < 1) continue;
    final t = (((p.x - w.a.x) * ab.x + (p.y - w.a.y) * ab.y) / l2).clamp(0.0, 1.0);
    final q = Punkt(w.a.x + ab.x * t, w.a.y + ab.y * t);
    final dist = (p - q).laenge;
    if (dist < abstand) {
      abstand = dist;
      beste = w;
    }
  }
  if (beste == null) {
    return (mitte: p, u: const Punkt(1, 0), n: const Punkt(0, 1), vorn: tiefe / 2, hinten: -tiefe / 2);
  }
  final ab = beste.b - beste.a;
  final l = ab.laenge;
  final u = Punkt(ab.x / l, ab.y / l);
  var n = Punkt(-u.y, u.x);
  final ap = p - beste.a;
  if (ap.x * n.x + ap.y * n.y < 0) n = Punkt(-n.x, -n.y); // Normale zur Seite des Punkts
  final entlang = ap.x * u.x + ap.y * u.y;
  final mitte = Punkt(beste.a.x + u.x * entlang, beste.a.y + u.y * entlang);
  final flaeche = beste.dicke / 2;
  final (vorn, hinten) = d.montage.inWand ? (flaeche, flaeche - tiefe) : (flaeche + tiefe, flaeche);
  return (mitte: mitte, u: u, n: n, vorn: vorn, hinten: hinten);
}

/// Umriss (vier Ecken, mm) des Verteilerschranks im Grundriss.
List<Punkt> verteilerUmriss(Punkt p, VerteilerDaten d, Iterable<WandStrecke> waende, {double fang = 600}) {
  final l = verteilerLage(p, d, waende, fang: fang);
  final breite = d.schrankBreite.toDouble();
  Punkt ecke(double s, double v) => Punkt(l.mitte.x + l.u.x * s + l.n.x * v, l.mitte.y + l.u.y * s + l.n.y * v);
  return [ecke(-breite / 2, l.hinten), ecke(breite / 2, l.hinten), ecke(breite / 2, l.vorn), ecke(-breite / 2, l.vorn)];
}

/// Anschlusspunkte der Abgänge im Grundriss an der Vorderkante des Schranks
/// („rechts“ wie in der Wandansicht vom Raum aus gesehen).
List<(String, Punkt)> verteilerAnschlussPunkte(Punkt p, VerteilerDaten d, Iterable<WandStrecke> waende) {
  final l = verteilerLage(p, d, waende);
  final rechts = Punkt(l.n.y, -l.n.x); // Blick gegen n, y nach unten
  final vorn = Punkt(l.mitte.x + l.n.x * l.vorn, l.mitte.y + l.n.y * l.vorn);
  return [
    for (final a in verteilerAnschluesse(d))
      if (a.dz == 0) (a.name, Punkt(vorn.x + rechts.x * a.dx, vorn.y + rechts.y * a.dx)),
  ];
}
