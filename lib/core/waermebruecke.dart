import 'dart:math' as math;
import 'dart:typed_data';

/// Wärmebrückenberechnung für den Fenstereinbau (Laibung, Horizontalschnitt)
/// mit einem 2D-Finite-Volumen-Verfahren, angelehnt an DIN EN ISO 10211 und
/// DIN 4108 Beiblatt 2: Ψ-Wert des Einbaus und Temperaturfaktor fRsi.
/// Vereinfachungen: Rahmen und Verglasung als homogene Ersatzschichten aus Uf
/// und Ug, Anschlussfuge als Dämmstoff, Wand 1 m seitlich, Schnittränder adiabat.

/// Wärmeübergangswiderstände (m²K/W).
const rse = 0.04, rsiWaerme = 0.13, rsiFeuchte = 0.25;

/// Bemessungstemperaturen DIN 4108-2 (°C).
const thetaI = 20.0, thetaE = -5.0;

class WbSchicht {
  const WbSchicht(this.name, this.dicke, this.lambda);
  final String name;
  final int dicke; // mm
  final double lambda; // W/(mK)
}

/// Eingaben des Einbaudetails (alle Längen in mm).
class EinbauDetail {
  const EinbauDetail({
    required this.schichten,
    this.rahmenBautiefe = 82,
    this.rahmenBreite = 117,
    this.uf = 1.0,
    this.ug = 0.6,
    this.glasdicke = 44,
    this.einbaulage = 120,
    this.fuge = 10,
    this.fugeLambda = 0.04,
    this.laibungDaemmung = 0,
    this.laibungLambda = 0.035,
    this.innenLaibungDaemmung = 0,
    this.innenLaibungLambda = 0.06,
    this.wandLaenge = 1000,
    this.glasLaenge = 190,
  });

  /// Wandschichten von außen nach innen.
  final List<WbSchicht> schichten;
  final int rahmenBautiefe, rahmenBreite;
  final double uf, ug;
  final int glasdicke;

  /// Abstand Außenkante Rahmen ↔ Außenoberfläche Wand.
  final int einbaulage;
  final int fuge;
  final double fugeLambda;

  /// Dämmung auf der äußeren Laibung (Dicke) und ihr λ.
  final int laibungDaemmung;
  final double laibungLambda;

  /// Dämmung auf der inneren Laibung (z. B. Kalziumsilikat), Dicke.
  final int innenLaibungDaemmung;
  final double innenLaibungLambda;
  final int wandLaenge, glasLaenge;

  int get wanddicke => schichten.fold(0, (s, x) => s + x.dicke);

  double get uWand => 1 / (rse + rsiWaerme + schichten.fold<double>(0, (s, x) => s + x.dicke / 1000 / x.lambda));

  /// Ersatz-λ des Rahmens aus Uf (gleiches U bei gleicher Bautiefe).
  double get lambdaRahmen => rahmenBautiefe / 1000 / math.max(0.01, 1 / uf - rse - rsiWaerme);
  double get lambdaGlas => glasdicke / 1000 / math.max(0.01, 1 / ug - rse - rsiWaerme);

  EinbauDetail mit({int? einbaulage, int? laibungDaemmung, double? laibungLambda, int? innenLaibungDaemmung, int? fuge}) => EinbauDetail(
        schichten: schichten,
        rahmenBautiefe: rahmenBautiefe,
        rahmenBreite: rahmenBreite,
        uf: uf,
        ug: ug,
        glasdicke: glasdicke,
        einbaulage: einbaulage ?? this.einbaulage,
        fuge: fuge ?? this.fuge,
        fugeLambda: fugeLambda,
        laibungDaemmung: laibungDaemmung ?? this.laibungDaemmung,
        laibungLambda: laibungLambda ?? this.laibungLambda,
        innenLaibungDaemmung: innenLaibungDaemmung ?? this.innenLaibungDaemmung,
        innenLaibungLambda: innenLaibungLambda,
        wandLaenge: wandLaenge,
        glasLaenge: glasLaenge,
      );
}

/// Zellarten des Rechengitters.
enum WbZelle { aussenluft, innenluft, wand, rahmen, glas, fuge, daemmung }

class WbErgebnis {
  WbErgebnis({
    required this.psi,
    required this.fRsi,
    required this.thetaSiMin,
    required this.l2d,
    required this.nx,
    required this.ny,
    required this.h,
    required this.y0,
    required this.temperatur,
    required this.art,
    required this.minOrt,
  });

  /// Ψ des Einbaus (W/(mK)).
  final double psi;

  /// Temperaturfaktor an der ungünstigsten Stelle innen (Rsi = 0,25).
  final double fRsi;
  final double thetaSiMin;

  /// thermischer Leitwert des 2D-Modells (W/(mK)).
  final double l2d;
  final int nx, ny;
  final double h; // mm je Zelle
  final double y0; // y der ersten Zeile in mm (negativ: Fensterseite)
  final Float64List temperatur; // °C, Feuchtefall (Rsi 0,25)
  final List<WbZelle> art;
  final (double, double) minOrt; // mm (x, y)

  bool get schimmelOk => fRsi >= 0.70;
  WbZelle zelle(int i, int j) => art[j * nx + i];
  double t(int i, int j) => temperatur[j * nx + i];
}

/// Gitter aufbauen: x quer durch die Wand (0 = außen), y entlang der Wand
/// (0 = Laibungskante, > 0 Wand, < 0 Fensteröffnung).
(List<WbZelle>, Float64List, int, int, double) _gitter(EinbauDetail d, double h) {
  final dicke = d.wanddicke.toDouble();
  final nx = (dicke / h).ceil();
  final yMin = -(d.fuge + d.rahmenBreite + d.glasLaenge).toDouble();
  final yMax = d.wandLaenge.toDouble();
  final ny = ((yMax - yMin) / h).ceil();
  final art = List<WbZelle>.filled(nx * ny, WbZelle.aussenluft);
  final lam = Float64List(nx * ny);
  // Schichtgrenzen
  final grenzen = <double>[];
  var s = 0.0;
  for (final x in d.schichten) {
    s += x.dicke;
    grenzen.add(s);
  }
  final e = d.einbaulage.toDouble(), b = d.rahmenBautiefe.toDouble();
  final glasX0 = e + b / 2 - d.glasdicke / 2, glasX1 = glasX0 + d.glasdicke;
  for (var j = 0; j < ny; j++) {
    final y = yMin + (j + 0.5) * h;
    for (var i = 0; i < nx; i++) {
      final x = (i + 0.5) * h;
      final k = j * nx + i;
      if (y >= 0) {
        // Wand: Schicht suchen; Innenlaibungsdämmung ersetzt nichts (liegt in y < 0)
        var n = 0;
        while (n < grenzen.length - 1 && x > grenzen[n]) {
          n++;
        }
        art[k] = WbZelle.wand;
        lam[k] = d.schichten[n].lambda;
        continue;
      }
      final inRahmenX = x >= e && x <= e + b;
      if (inRahmenX && y >= -d.fuge) {
        art[k] = WbZelle.fuge;
        lam[k] = d.fugeLambda;
      } else if (inRahmenX && y >= -(d.fuge + d.rahmenBreite)) {
        art[k] = WbZelle.rahmen;
        lam[k] = d.lambdaRahmen;
      } else if (x >= glasX0 && x <= glasX1) {
        art[k] = WbZelle.glas;
        lam[k] = d.lambdaGlas;
      } else if (x < e && y >= -d.laibungDaemmung) {
        art[k] = WbZelle.daemmung;
        lam[k] = d.laibungLambda;
      } else if (x > e + b && y >= -d.innenLaibungDaemmung) {
        art[k] = WbZelle.daemmung;
        lam[k] = d.innenLaibungLambda;
      } else {
        art[k] = x < e + b / 2 ? WbZelle.aussenluft : WbZelle.innenluft;
      }
    }
  }
  return (art, lam, nx, ny, yMin);
}

bool _fest(WbZelle z) => z != WbZelle.aussenluft && z != WbZelle.innenluft;

/// Stationäre Temperaturverteilung lösen; gibt Temperaturen und den
/// Wärmestrom von innen nach außen (W/m) zurück.
(Float64List, double) _loesen(List<WbZelle> art, Float64List lam, int nx, int ny, double h, double rsi, {int maxIter = 6000}) {
  final hm = h / 1000;
  final t = Float64List(nx * ny);
  for (var k = 0; k < t.length; k++) {
    t[k] = (thetaI + thetaE) / 2;
  }
  // Leitwerte zu Nachbarn (O, W, N, S) und zu Luft
  final gO = Float64List(nx * ny), gN = Float64List(nx * ny);
  final gAussen = Float64List(nx * ny), gInnen = Float64List(nx * ny);
  double gFest(double l1, double l2) => 1 / (1 / (2 * l1) + 1 / (2 * l2));
  double gLuft(double l, double rs) => hm / (hm / (2 * l) + rs);
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      final k = j * nx + i;
      if (!_fest(art[k])) continue;
      void luft(WbZelle nachbar) {
        if (nachbar == WbZelle.aussenluft) gAussen[k] += gLuft(lam[k], rse);
        if (nachbar == WbZelle.innenluft) gInnen[k] += gLuft(lam[k], rsi);
      }

      // Osten (x+)
      if (i + 1 < nx) {
        if (_fest(art[k + 1])) {
          gO[k] = gFest(lam[k], lam[k + 1]);
        } else {
          luft(art[k + 1]);
        }
      } else {
        luft(WbZelle.innenluft); // Wandinnenseite
      }
      // Westen (x−)
      if (i > 0) {
        if (!_fest(art[k - 1])) luft(art[k - 1]);
      } else {
        luft(WbZelle.aussenluft); // Wandaußenseite
      }
      // Norden (y+)
      if (j + 1 < ny) {
        if (_fest(art[k + nx])) {
          gN[k] = gFest(lam[k], lam[k + nx]);
        } else {
          luft(art[k + nx]);
        }
      }
      // Süden (y−)
      if (j > 0 && !_fest(art[k - nx])) luft(art[k - nx]);
    }
  }
  const omega = 1.9;
  for (var it = 0; it < maxIter; it++) {
    var maxD = 0.0;
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        final k = j * nx + i;
        if (!_fest(art[k])) continue;
        var sg = gAussen[k] + gInnen[k];
        var st = gAussen[k] * thetaE + gInnen[k] * thetaI;
        if (gO[k] > 0) {
          sg += gO[k];
          st += gO[k] * t[k + 1];
        }
        if (i > 0 && gO[k - 1] > 0) {
          sg += gO[k - 1];
          st += gO[k - 1] * t[k - 1];
        }
        if (gN[k] > 0) {
          sg += gN[k];
          st += gN[k] * t[k + nx];
        }
        if (j > 0 && gN[k - nx] > 0) {
          sg += gN[k - nx];
          st += gN[k - nx] * t[k - nx];
        }
        if (sg == 0) continue;
        final neu = t[k] + omega * (st / sg - t[k]);
        final dd = (neu - t[k]).abs();
        if (dd > maxD) maxD = dd;
        t[k] = neu;
      }
    }
    if (maxD < 1e-5) break;
  }
  var q = 0.0;
  for (var k = 0; k < t.length; k++) {
    q += gInnen[k] * (thetaI - t[k]);
  }
  // Oberflächentemperaturen innen: in die Zelltemperatur eingerechnet über den
  // Übergang; für fRsi die Oberfläche als Mittel zwischen Zelle und Luft.
  return (t, q);
}

/// Einbaudetail berechnen (Rastergröße [h] in mm).
WbErgebnis waermebrueckeBerechnen(EinbauDetail d, {double h = 5}) {
  final (art, lam, nx, ny, y0) = _gitter(d, h);
  final (_, q) = _loesen(art, lam, nx, ny, h, rsiWaerme);
  final l2d = q / (thetaI - thetaE);
  final lWand = d.wandLaenge / 1000, lRahmen = (d.fuge + d.rahmenBreite) / 1000, lGlas = d.glasLaenge / 1000;
  final psi = l2d - d.uWand * lWand - d.uf * lRahmen - d.ug * lGlas;
  final (tF, _) = _loesen(art, lam, nx, ny, h, rsiFeuchte);
  // minimale Oberflächentemperatur innen
  var tMin = double.infinity;
  var ort = (0.0, 0.0);
  final hm = h / 1000;
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      final k = j * nx + i;
      if (!_fest(art[k])) continue;
      final innen = i + 1 >= nx || art[k + 1] == WbZelle.innenluft || (j + 1 < ny && art[k + nx] == WbZelle.innenluft) || (j > 0 && art[k - nx] == WbZelle.innenluft);
      if (!innen) continue;
      // Oberfläche: Zelltemperatur + Anteil des halben Zellwiderstands
      final r1 = hm / 2 / lam[k];
      final ts = tF[k] + (thetaI - tF[k]) * r1 / (r1 + rsiFeuchte);
      if (ts < tMin) {
        tMin = ts;
        ort = ((i + 0.5) * h, y0 + (j + 0.5) * h);
      }
    }
  }
  return WbErgebnis(
    psi: psi,
    fRsi: (tMin - thetaE) / (thetaI - thetaE),
    thetaSiMin: tMin,
    l2d: l2d,
    nx: nx,
    ny: ny,
    h: h,
    y0: y0,
    temperatur: tF,
    art: art,
    minOrt: ort,
  );
}

/// Uw im eingebauten Zustand: Uw + Σ(Ψ·l)/A (Ψ für alle Seiten gleich angesetzt,
/// optional Rollladenkasten oben mit eigenem Ψ).
double uwEingebaut({required double uw, required int breite, required int hoehe, required double psi, double? psiKasten}) {
  final a = breite / 1000 * hoehe / 1000;
  if (a <= 0) return uw;
  final umfang = 2 * (breite + hoehe) / 1000;
  final kasten = psiKasten == null ? 0.0 : (psiKasten - psi) * breite / 1000;
  return uw + (psi * umfang + kasten) / a;
}

/// λ-Richtwert für einen Baustoff nach Name/Kategorie (W/(mK)), falls keiner hinterlegt ist.
double lambdaVorschlag(String name, String kategorie) {
  final n = '${name.toLowerCase()} ${kategorie.toLowerCase()}';
  bool hat(List<String> w) => w.any(n.contains);
  if (hat(['pur', 'pir', 'resol'])) return 0.024;
  if (hat(['eps', 'xps', 'mineralwolle', 'steinwolle', 'glaswolle', 'dämm', 'daemm', 'holzfaser', 'zellulose'])) return 0.035;
  if (hat(['porenbeton', 'ytong', 'gasbeton'])) return 0.12;
  if (hat(['kalksandstein', 'ks-'])) return 0.99;
  if (hat(['stahlbeton', 'beton'])) return 2.3;
  if (hat(['estrich'])) return 1.4;
  if (hat(['leichtlehm', 'lehm'])) return 0.5;
  if (hat(['hochlochziegel', 'planziegel', 'poroton', 'ziegel', 'mauerziegel'])) return 0.45;
  if (hat(['vollziegel', 'klinker'])) return 0.81;
  if (hat(['bims', 'leichtbeton'])) return 0.4;
  if (hat(['gipskarton', 'gipsfaser', 'trockenbau', 'gk'])) return 0.25;
  if (hat(['holz', 'osb', 'span', 'brett'])) return 0.13;
  if (hat(['kalkzement', 'außenputz', 'aussenputz', 'zementputz'])) return 0.87;
  if (hat(['putz', 'kalk', 'gips'])) return 0.7;
  if (hat(['fliese', 'keramik'])) return 1.3;
  if (hat(['naturstein', 'granit'])) return 2.8;
  if (hat(['luft'])) return 0.17;
  if (hat(['mauerwerk'])) return 0.6;
  return 0.8;
}

/// Ein Beratungspunkt zum Einbaudetail; [aenderung] ist ein umsetzbarer Vorschlag
/// (Schlüssel der Einbaudaten → Wert), z. B. {'laibung': 30}.
typedef WbRat = ({int stufe, String titel, String text, Map<String, num>? aenderung});

/// Bewertung und Lösungsvorschläge (stufe 0 = gut, 1 = Hinweis, 2 = Warnung).
List<WbRat> waermebrueckeBeratung(EinbauDetail d, WbErgebnis r) {
  final l = <WbRat>[];
  // Lage der Außendämmung (Schichten mit λ < 0,06 von außen)
  var daemmDicke = 0;
  var lauf = 0;
  for (final s in d.schichten) {
    if (s.lambda < 0.06 && lauf == daemmDicke) daemmDicke += s.dicke;
    lauf += s.dicke;
  }
  // Außenputz vor der Dämmung zählt mit zur Lage der Dämmebene
  if (daemmDicke == 0 && d.schichten.length > 1 && d.schichten.first.dicke <= 20 && d.schichten[1].lambda < 0.06) {
    daemmDicke = d.schichten.first.dicke + d.schichten[1].dicke;
  }
  final hatAussenDaemmung = daemmDicke > 0;

  if (r.thetaSiMin < 9.3) {
    l.add((
      stufe: 2,
      titel: 'Tauwasser an der Laibung',
      text: 'Die kälteste Stelle innen hat nur ${r.thetaSiMin.toStringAsFixed(1)} °C. Bei 20 °C und 50 % Luftfeuchte liegt der Taupunkt bei 9,3 °C – '
          'dort schlägt sich Wasser nieder. Laibung dämmen und den Rahmen tiefer in die Dämmebene setzen.',
      aenderung: {'laibung': 40, 'innenlaibung': 20},
    ));
  } else if (!r.schimmelOk) {
    l.add((
      stufe: 2,
      titel: 'Schimmelgefahr (fRsi < 0,70)',
      text: 'DIN 4108-2 verlangt fRsi ≥ 0,70, d. h. mindestens 12,6 °C an der kältesten Stelle. Abhilfe: äußere Laibung mit 20–40 mm dämmen, '
          'die Dämmung bis an den Rahmen führen und ihn möglichst überdämmen; im Bestand ohne Außendämmung zusätzlich die Innenlaibung '
          'mit Kalziumsilikat (kapillaraktiv) dämmen.',
      aenderung: {'laibung': 30, 'innenlaibung': d.innenLaibungDaemmung > 0 ? d.innenLaibungDaemmung : 20},
    ));
  } else {
    l.add((
      stufe: 0,
      titel: 'Kein Schimmelrisiko an der Laibung',
      text: 'fRsi ${r.fRsi.toStringAsFixed(2).replaceAll('.', ',')} ≥ 0,70: die Oberfläche bleibt auch bei −5 °C außen warm genug (${r.thetaSiMin.toStringAsFixed(1).replaceAll('.', ',')} °C).',
      aenderung: null,
    ));
  }

  if (r.psi > 0.10) {
    l.add((
      stufe: 2,
      titel: 'Hoher Wärmeverlust am Anschluss (Ψ ${r.psi.toStringAsFixed(3).replaceAll('.', ',')})',
      text: 'Über diesen Anschluss geht deutlich mehr Wärme verloren als über die Wand daneben. Üblich sind bei gutem Einbau Ψ ≤ 0,04 W/(mK). '
          '${hatAussenDaemmung ? 'Den Rahmen in die Dämmebene setzen (Einbaulage etwa an der Grenze Dämmung/Mauerwerk) und 30–40 mm überdämmen.' : 'Ohne Außendämmung hilft vor allem eine Laibungsdämmung mit gutem λ (PIR 0,026) und eine Innenlaibungsdämmung.'}',
      aenderung: hatAussenDaemmung ? {'einbaulage': daemmDicke, 'laibung': 40} : {'laibung': 30, 'laibung_lambda': 0.026},
    ));
  } else if (r.psi > 0.04) {
    l.add((
      stufe: 1,
      titel: 'Anschluss verbesserbar (Ψ ${r.psi.toStringAsFixed(3).replaceAll('.', ',')})',
      text: 'Gut ist Ψ ≤ 0,04 W/(mK) (Richtwert für Einbau in der Dämmebene nach DIN 4108 Beiblatt 2). Mehr Überdämmung des Rahmens oder eine '
          'Laibungsdämmung mit besserem λ bringt meist schon genug.',
      aenderung: {'laibung': d.laibungDaemmung < 30 ? 30 : d.laibungDaemmung + 10},
    ));
  } else {
    l.add((
      stufe: 0,
      titel: 'Guter Einbau (Ψ ${r.psi.toStringAsFixed(3).replaceAll('.', ',')})',
      text: r.psi < 0
          ? 'Negativer Ψ-Wert: der Anschluss verliert sogar weniger Wärme als die Wand und das Fenster einzeln gerechnet – sehr gut.'
          : 'Der Anschluss liegt im Bereich eines guten Einbaus in der Dämmebene.',
      aenderung: null,
    ));
  }

  final e = d.einbaulage;
  if (hatAussenDaemmung && e > daemmDicke + 20 && d.laibungDaemmung < 20) {
    l.add((
      stufe: 1,
      titel: 'Rahmen sitzt hinter der Dämmebene',
      text: 'Zwischen Außendämmung ($daemmDicke mm) und Rahmen (Einbaulage $e mm) liegt ungedämmtes Mauerwerk in der Laibung. '
          'Entweder den Rahmen nach vorne an die Dämmung setzen (Montagewinkel/Konsolen) oder die Laibung bis an den Rahmen dämmen.',
      aenderung: {'laibung': 30},
    ));
  }
  if (d.laibungDaemmung > 0 && d.laibungDaemmung < d.fuge + 15) {
    l.add((
      stufe: 1,
      titel: 'Rahmen kaum überdämmt',
      text: 'Die Laibungsdämmung (${d.laibungDaemmung} mm) überdeckt den Rahmen nur wenig. 20–30 mm Überdämmung des Blendrahmens senken Ψ spürbar; '
          'die sichtbare Rahmenbreite wird dabei etwas kleiner.',
      aenderung: {'laibung': d.fuge + 30},
    ));
  }
  l.add((
    stufe: 1,
    titel: 'Anschlussfuge nach RAL-Montage',
    text: 'Innen luftdicht (Folie oder Dichtstoff), Mitte wärmedämmend (${d.fugeLambda <= 0.04 ? 'PU-Schaum dämmt hier gut' : 'Kompriband dämmt etwas schlechter als Schaum'}), '
        'außen schlagregendicht und diffusionsoffen (Kompriband oder Folie). Ein Multifunktionsband (3E) erfüllt alle drei Ebenen in einem.',
    aenderung: null,
  ));
  return l;
}

/// Kurze technische Erklärungen zu den Ergebnissen.
const wbErklaerungen = <(String, String)>[
  ('Ψ (Psi)-Wert', 'Längenbezogener Wärmedurchgangskoeffizient in W/(mK): zusätzlicher Wärmeverlust je Meter Fensteranschluss gegenüber Wand und Fenster '
      'einzeln gerechnet. Er wird mit der Anschlusslänge multipliziert und in Heizlast und Energiebilanz eingerechnet. Kleiner ist besser, negativ ist möglich.'),
  ('fRsi (Temperaturfaktor)', 'Verhältnis (θsi − θe) / (θi − θe) an der kältesten Stelle innen, gerechnet mit Rsi = 0,25 m²K/W (Möbel, Vorhänge). '
      'DIN 4108-2 verlangt fRsi ≥ 0,70 – das entspricht 12,6 °C bei 20 °C innen und −5 °C außen; darunter droht Schimmel.'),
  ('Uw eingebaut', 'U-Wert des Fensters inklusive der Einbauwärmebrücke: Uw + Σ(Ψ · Länge) / Fensterfläche. Bei Rollläden mit Kasten zählt oben dessen eigener Ψ-Wert.'),
  ('So wird gerechnet', 'Zweidimensionaler Horizontalschnitt durch die Laibung (Finite-Volumen-Verfahren, Raster 5 mm) nach DIN EN ISO 10211. '
      'Rahmen und Glas werden als Ersatzschichten mit gleichem U-Wert (Uf, Ug) abgebildet, die Anschlussfuge mit ihrem λ. Wand 1 m seitlich, Schnittränder adiabat. '
      'Sturz und Brüstung haben eigene Werte; für GEG-/KfW-Nachweise ist ein zertifiziertes Wärmebrückenprogramm nötig.'),
];
