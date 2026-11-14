import 'dart:math' as math;

import 'raumerkennung.dart';

/// Gebäude-Helfer (Planungshilfen, keine Nachweise): GEG-Dämmung bei
/// Änderung, Schallschutz-Richtwerte, Sonneneintrag, Treppenmaße,
/// Statik-Richtwerte und die Verknüpfung von Wänden über Geschosse.

// ------------------------------------------------------------------- GEG

/// Bauteilart für die Höchstwerte nach GEG Anlage 7 (Änderung bestehender Gebäude).
enum GegBauteil { aussenwand, dach, oberstGeschossdecke, flachdach, fenster, dachfenster, tuer, kellerdecke, bodenErdreich }

extension GegBauteilText on GegBauteil {
  String get label => switch (this) {
        GegBauteil.aussenwand => 'Außenwand',
        GegBauteil.dach => 'Steildach / Dachschräge',
        GegBauteil.oberstGeschossdecke => 'Oberste Geschossdecke',
        GegBauteil.flachdach => 'Flachdach',
        GegBauteil.fenster => 'Fenster / Fenstertür',
        GegBauteil.dachfenster => 'Dachflächenfenster',
        GegBauteil.tuer => 'Außentür',
        GegBauteil.kellerdecke => 'Decke gegen unbeheizt / Keller',
        GegBauteil.bodenErdreich => 'Boden gegen Erdreich',
      };

  /// Höchstwert des Wärmedurchgangskoeffizienten in W/(m²K).
  double get uMax => switch (this) {
        GegBauteil.aussenwand => 0.24,
        GegBauteil.dach => 0.24,
        GegBauteil.oberstGeschossdecke => 0.24,
        GegBauteil.flachdach => 0.20,
        GegBauteil.fenster => 1.3,
        GegBauteil.dachfenster => 1.4,
        GegBauteil.tuer => 1.8,
        GegBauteil.kellerdecke => 0.30,
        GegBauteil.bodenErdreich => 0.30,
      };
}

/// Fehlende Dämmstärke (mm), damit [u] den GEG-Wert erreicht – bei [lambda]
/// des Dämmstoffs (W/(mK)). 0, wenn es schon passt.
double gegZusatzDaemmung(double u, GegBauteil b, {double lambda = 0.035}) {
  if (u <= b.uMax || u <= 0) return 0;
  final rFehlt = 1 / b.uMax - 1 / u;
  return rFehlt * lambda * 1000;
}

// ------------------------------------------------------------------ Schall

/// Flächenbezogene Masse (kg/m²) aus Schichten (Dicke mm, Rohdichte kg/m³).
double flaechenMasse(List<(int dicke, double rho)> schichten) => schichten.fold(0, (s, x) => s + x.$1 / 1000 * x.$2);

/// Bewertetes Schalldämmmaß einschaliger massiver Bauteile (Massekurve
/// nach DIN 4109-32, Richtwert): R'w ≈ 30,9·log10(m') − 22,2 dB.
double schalldaemmmass(double flaechenmasse) => flaechenmasse <= 1 ? 0 : 30.9 * math.log(flaechenmasse) / math.ln10 - 22.2;

/// Empfohlenes R'w zwischen zwei Räumen im Einfamilienhaus (DIN 4109-5
/// erhöhter Schallschutz / Beiblatt 2, Richtwerte). null = keine Empfehlung.
int? schallEmpfehlung(String raumA, String raumB) {
  bool ruhe(String n) => RegExp(r'schlaf|kind|eltern|gäste|gast|arbeit|büro').hasMatch(n.toLowerCase());
  bool laut(String n) => RegExp(r'bad|wc|dusch|küche|technik|hwr|hauswirtschaft|wasch|heiz|werk').hasMatch(n.toLowerCase());
  if ((ruhe(raumA) && laut(raumB)) || (ruhe(raumB) && laut(raumA))) return 47;
  if (ruhe(raumA) && ruhe(raumB)) return 40;
  return null;
}

// ------------------------------------------------------------ Sonnenschutz

/// Abminderungsfaktor Fc des Sonnenschutzes (DIN 4108-2, Richtwerte).
double fcSonnenschutz(String? art) => switch ((art ?? '').toLowerCase()) {
      final a when a.contains('raff') || a.contains('jalousie') && a.contains('außen') => 0.25,
      final a when a.contains('rollladen') || a.contains('rolladen') || a.contains('fensterladen') => 0.30,
      final a when a.contains('markise') => 0.40,
      final a when a.contains('innen') || a.contains('plissee') || a.contains('vorhang') => 0.75,
      _ => 1.0,
    };

/// Himmelsrichtung einer Fassade aus der Außennormalen (Bildschirm: x rechts,
/// y unten) und der Nordrichtung ([nordGrad]: 0 = oben auf dem Plan).
String himmelsrichtung(double nx, double ny, {double nordGrad = 0}) {
  // Winkel im Uhrzeigersinn ab „oben“
  var w = math.atan2(nx, -ny) * 180 / math.pi - nordGrad;
  w = (w % 360 + 360) % 360;
  const r = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
  return r[((w + 22.5) ~/ 45) % 8];
}

/// Sonneneintragskennwert S = Σ(A_w · g · Fc) / A_Grund (vereinfacht ohne
/// Nordfenster). Richtwert zulässig ca. 0,07–0,10 je nach Bauart und Lüftung.
double sonneneintrag(List<({double flaeche, double g, double fc, String richtung})> fenster, double grundflaeche) {
  if (grundflaeche <= 0) return 0;
  var s = 0.0;
  for (final f in fenster) {
    if (f.richtung == 'N') continue;
    s += f.flaeche * f.g * f.fc;
  }
  return s / grundflaeche;
}

// ------------------------------------------------------------------ Treppe

class TreppenMasse {
  TreppenMasse({required this.stufen, required this.steigung, required this.auftritt, required this.lauflaenge, required this.hinweise});
  final int stufen; // Anzahl Steigungen
  final double steigung; // mm
  final double auftritt; // mm
  final double lauflaenge; // mm (Grundriss)
  final List<String> hinweise;
  double get schrittmass => 2 * steigung + auftritt;
}

/// Treppe aus Geschosshöhe (FFB bis FFB) und verfügbarer Lauflänge
/// (Schrittmaßregel 2h + a = 630 mm, DIN 18065 Wohngebäude), optional mit
/// gewünschter Stufenzahl.
TreppenMasse treppeAuslegen({required double geschosshoehe, double? lauflaenge, int? stufen, double laufbreite = 900, double kopfhoehe = 2000}) {
  final n = stufen ?? math.max(2, (geschosshoehe / 180).round());
  final h = geschosshoehe / n;
  final a = lauflaenge != null && n > 1 ? lauflaenge / (n - 1) : 630 - 2 * h;
  final hw = <String>[
    if (h > 200) 'Steigung ${h.round()} mm über 200 mm (DIN 18065, notwendige Treppe) – mehr Stufen',
    if (h < 140) 'Steigung ${h.round()} mm sehr flach',
    if (a < 230) 'Auftritt ${a.round()} mm unter 230 mm (DIN 18065) – mehr Lauflänge oder gewendelt',
    if ((2 * h + a) < 590 || (2 * h + a) > 650) 'Schrittmaß ${(2 * h + a).round()} mm außerhalb 590–650 mm',
    if (laufbreite < 800) 'Laufbreite ${laufbreite.round()} mm unter 800 mm (notwendige Treppe im EFH)',
    if (kopfhoehe < 2000) 'Kopfhöhe ${kopfhoehe.round()} mm unter 2000 mm',
  ];
  return TreppenMasse(stufen: n, steigung: h, auftritt: a, lauflaenge: a * (n - 1), hinweise: hw);
}

/// Geländer-Hinweis nach LBO (Richtwerte): ab 1 m Absturzhöhe Umwehrung,
/// Höhe ≥ 900 mm (über 12 m Absturz 1100 mm), Öffnungen ≤ 120 mm.
List<String> gelaenderHinweise({required double absturzhoehe, double? hoehe, double? stababstand}) => [
      if (absturzhoehe > 1000 && hoehe == null) 'Absturzhöhe ${(absturzhoehe / 1000).toStringAsFixed(2).replaceAll('.', ',')} m – Geländer/Umwehrung nötig',
      if (hoehe != null && hoehe < (absturzhoehe > 12000 ? 1100 : 900)) 'Geländerhöhe ${hoehe.round()} mm zu niedrig (mind. ${absturzhoehe > 12000 ? 1100 : 900} mm)',
      if (stababstand != null && stababstand > 120) 'Stababstand ${stababstand.round()} mm über 120 mm (Kinder)',
    ];

// ------------------------------------------------------------------ Statik

/// Richtwerte für einen Sturz über einer Öffnung in einer tragenden Wand:
/// Auflagerlänge je Seite, Sturzlänge, typische Ausführung. Kein Nachweis.
({double auflager, double laenge, String art}) sturzRichtwert(double lichteBreite, {double wanddicke = 240}) {
  final auflager = lichteBreite <= 1000 ? 115.0 : (lichteBreite <= 2000 ? 175.0 : 240.0);
  final art = lichteBreite <= 1250
      ? 'Flachsturz / Fertigteilsturz (Mauerwerk)'
      : lichteBreite <= 2500
          ? 'Stahlbetonsturz oder Fertigteilsturz mit Übermauerung'
          : 'Stahlträger oder Stahlbetonunterzug – Statiker';
  return (auflager: auflager, laenge: lichteBreite + 2 * auflager, art: art);
}

// ----------------------------------------------------- Geschosse verknüpfen

/// Wandachse für die Verknüpfung.
typedef WandAchse2 = ({String id, Punkt a, Punkt b, int dicke});

/// Wände eines oberen Geschosses, die auf einer Wand des unteren stehen
/// (parallel, Achsabstand höchstens die halbe Dicke, Überdeckung ≥ [anteil]).
/// [gelöst] = Paare „oben|unten“, die der Benutzer getrennt hat.
Map<String, String> wandVerknuepfungen(List<WandAchse2> oben, List<WandAchse2> unten, {double anteil = 0.6, Set<String> geloest = const {}}) {
  final aus = <String, String>{};
  for (final o in oben) {
    final lo = (o.b - o.a).laenge;
    if (lo < 1) continue;
    final ux = (o.b.x - o.a.x) / lo, uy = (o.b.y - o.a.y) / lo;
    String? best;
    var bestUeb = 0.0;
    for (final u in unten) {
      final lu = (u.b - u.a).laenge;
      if (lu < 1) continue;
      final vx = (u.b.x - u.a.x) / lu, vy = (u.b.y - u.a.y) / lu;
      if ((ux * vy - uy * vx).abs() > 0.03) continue; // nicht parallel (≈ 2°)
      // Querabstand der Achsen
      final q = ((u.a.x - o.a.x) * -uy + (u.a.y - o.a.y) * ux).abs();
      if (q > math.max(o.dicke, u.dicke) / 2 + 20) continue;
      final s0 = (u.a.x - o.a.x) * ux + (u.a.y - o.a.y) * uy;
      final s1 = (u.b.x - o.a.x) * ux + (u.b.y - o.a.y) * uy;
      final ueb = math.min(lo, math.max(s0, s1)) - math.max(0, math.min(s0, s1));
      if (ueb / lo >= anteil && ueb > bestUeb && !geloest.contains('${o.id}|${u.id}')) {
        bestUeb = ueb;
        best = u.id;
      }
    }
    if (best != null) aus[o.id] = best;
  }
  return aus;
}
