import 'dart:math' as math;

import 'raumerkennung.dart';

/// Bad und Abdichtung als Planungshilfe nach DIN 18534 (Innenräume):
/// Wassereinwirkungsklassen, Abdichtungsflächen, Dichtband, Ecken und
/// Manschetten aus Raumumriss, Dusche/Wanne und Nischen.

/// Nassraum automatisch am Namen erkennen (Bad, Dusche, Sanitär …).
/// `raum.eigenschaften['nassraum']` (true/false) geht immer vor – so ist die
/// Erkennung jederzeit lösbar.
bool istNassraum(String name, Map<String, dynamic> eigenschaften, {bool hatDuscheOderWanne = false}) {
  final v = eigenschaften['nassraum'];
  if (v is bool) return v;
  final n = name.toLowerCase();
  if (RegExp(r'bad|dusch|sanitär|sanitaer|wellness|sauna').hasMatch(n)) return true;
  return hatDuscheOderWanne;
}

/// Dusche oder Wanne im Raum.
class BadFlaeche {
  const BadFlaeche({required this.umriss, required this.wanne, this.bodengleich = true, this.brause = true, this.hoehe = 2000});
  final List<Punkt> umriss;
  final bool wanne;
  final bool bodengleich; // nur Dusche: bodengleich mit Ablauf/Rinne
  final bool brause; // nur Wanne: mit Brause (Wandfläche wie Dusche)
  final int hoehe; // Abdichtungshöhe an der Wand (mm)
}

/// Nische in einer Wand des Raums.
typedef BadNische = ({double breite, double hoehe, double tiefe, bool imSpritzbereich});

class AbdichtungsFlaeche {
  const AbdichtungsFlaeche(this.bezeichnung, this.klasse, this.m2);
  final String bezeichnung;
  final String klasse; // W0-I, W1-I
  final double m2;
}

class AbdichtungErgebnis {
  AbdichtungErgebnis({
    required this.flaechen,
    required this.dichtband,
    required this.innenecken,
    required this.aussenecken,
    required this.wandmanschetten,
    required this.bodenmanschetten,
    required this.hinweise,
  });

  final List<AbdichtungsFlaeche> flaechen;
  final double dichtband; // m
  final int innenecken;
  final int aussenecken;
  final int wandmanschetten;
  final int bodenmanschetten;
  final List<String> hinweise;

  double get summe => flaechen.fold(0, (s, f) => s + f.m2);
  double summeKlasse(String k) => flaechen.where((f) => f.klasse == k).fold(0, (s, f) => s + f.m2);

  /// Verbrauch Flüssigabdichtung in kg (zwei Lagen, [kgJeM2Lage] je Lage).
  double verbrauchKg({double kgJeM2Lage = 1.2}) => summeKlasse('W1-I') * 2 * kgJeM2Lage;
}

double _abstandPunktGerade(Punkt p, Punkt a, Punkt b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final l = math.sqrt(dx * dx + dy * dy);
  if (l < 1e-9) return math.sqrt(math.pow(p.x - a.x, 2) + math.pow(p.y - a.y, 2));
  return ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / l;
}

double _projektion(Punkt p, Punkt a, Punkt b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final l = math.sqrt(dx * dx + dy * dy);
  return l < 1e-9 ? 0 : ((p.x - a.x) * dx + (p.y - a.y) * dy) / l;
}

double _laenge(Punkt a, Punkt b) => math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));

/// Abschnitte einer Raumkante, an denen eine Dusche/Wanne anliegt
/// (Kante der Fläche höchstens [nah] mm von der Raumkante), um [zugabe] mm
/// verlängert: Liste (von, bis, Höhe) entlang der Kante.
List<(double, double, int)> _zonen(Punkt a, Punkt b, List<BadFlaeche> flaechen, {double nah = 150, double zugabe = 200}) {
  final l = _laenge(a, b);
  final z = <(double, double, int)>[];
  for (final f in flaechen) {
    final hoehe = f.wanne && !f.brause ? 800 : f.hoehe;
    for (var i = 0; i < f.umriss.length; i++) {
      final p = f.umriss[i], q = f.umriss[(i + 1) % f.umriss.length];
      if (_abstandPunktGerade(p, a, b) > nah || _abstandPunktGerade(q, a, b) > nah) continue;
      var s0 = _projektion(p, a, b), s1 = _projektion(q, a, b);
      if (s0 > s1) (s0, s1) = (s1, s0);
      if (s1 < 0 || s0 > l || s1 - s0 < 50) continue;
      z.add((math.max(0, s0 - zugabe), math.min(l, s1 + zugabe), hoehe));
    }
  }
  // überlappende Abschnitte zusammenfassen (größere Höhe gewinnt)
  z.sort((x, y) => x.$1.compareTo(y.$1));
  final aus = <(double, double, int)>[];
  for (final e in z) {
    if (aus.isNotEmpty && e.$1 <= aus.last.$2) {
      final l0 = aus.removeLast();
      aus.add((l0.$1, math.max(l0.$2, e.$2), math.max(l0.$3, e.$3)));
    } else {
      aus.add(e);
    }
  }
  return aus;
}

/// Abdichtung eines Raums berechnen. [umriss] = lichter Raumumriss (mm),
/// [raumhoehe] lichte Höhe, [sockel] Höhe des Sockelstreifens außerhalb der
/// Spritzbereiche (W0-I, Empfehlung), [anzahlWt] Waschtische (Manschetten nur,
/// wenn sie in einem abgedichteten Bereich liegen – hier nicht gezählt).
AbdichtungErgebnis abdichtungBerechnen({
  required List<Punkt> umriss,
  required List<BadFlaeche> flaechen,
  List<BadNische> nischen = const [],
  int raumhoehe = 2500,
  int sockel = 150,
  bool bodenablauf = false,
}) {
  final f = <AbdichtungsFlaeche>[];
  final h = <String>[];
  final boden = polygonFlaeche(umriss).abs() / 1e6;
  final umfang = [for (var i = 0; i < umriss.length; i++) _laenge(umriss[i], umriss[(i + 1) % umriss.length])].fold<double>(0, (s, v) => s + v) / 1000;
  final duschen = flaechen.where((x) => !x.wanne).toList();
  final bodengleich = duschen.any((d) => d.bodengleich) || bodenablauf;
  f.add(AbdichtungsFlaeche(bodengleich ? 'Boden (mit Ablauf, ganzer Raum)' : 'Boden (ohne Ablauf)', bodengleich ? 'W1-I' : 'W0-I', boden));

  var zonenLaenge = 0.0, wandZone = 0.0, eckenZone = 0;
  var eckenHoehe = 0.0;
  final kantenZonen = <List<(double, double, int)>>[];
  for (var i = 0; i < umriss.length; i++) {
    final a = umriss[i], b = umriss[(i + 1) % umriss.length];
    final z = _zonen(a, b, flaechen);
    kantenZonen.add(z);
    for (final (s0, s1, hh) in z) {
      final hz = math.min(hh, raumhoehe);
      zonenLaenge += (s1 - s0) / 1000;
      wandZone += (s1 - s0) / 1000 * hz / 1000;
    }
  }
  // senkrechte Innenecken im Spritzbereich: Ecke, an der beide Kanten eine Zone berühren
  for (var i = 0; i < umriss.length; i++) {
    final vor = kantenZonen[(i - 1 + umriss.length) % umriss.length];
    final nach = kantenZonen[i];
    final lVor = _laenge(umriss[(i - 1 + umriss.length) % umriss.length], umriss[i]);
    final amEndeVor = vor.where((z) => z.$2 >= lVor - 1).firstOrNull;
    final amAnfangNach = nach.where((z) => z.$1 <= 1).firstOrNull;
    if (amEndeVor != null && amAnfangNach != null) {
      eckenZone++;
      eckenHoehe += math.min(amEndeVor.$3, amAnfangNach.$3) / 1000;
    }
  }
  if (wandZone > 0) f.add(AbdichtungsFlaeche('Wände im Dusch-/Wannenbereich', 'W1-I', wandZone));
  final rest = math.max(0.0, umfang - zonenLaenge);
  if (rest > 0 && sockel > 0) f.add(AbdichtungsFlaeche('Sockelstreifen übrige Wände (${sockel / 10} cm, Empfehlung)', 'W0-I', rest * sockel / 1000));
  var nischenFl = 0.0;
  for (final n in nischen) {
    if (!n.imSpritzbereich) continue;
    // Rückwand + Laibungen (oben, unten, beidseitig)
    nischenFl += (n.breite * n.hoehe + 2 * n.tiefe * (n.breite + n.hoehe)) / 1e6;
  }
  if (nischenFl > 0) f.add(AbdichtungsFlaeche('Nischen im Spritzbereich (Laibungen)', 'W1-I', nischenFl));

  // Dichtband: Boden-Wand-Fuge (ganzer Raum bei Boden W1-I, sonst nur Zonen),
  // senkrechte Ecken in Zonen, Wannenrand an der Wand
  var band = bodengleich ? umfang : zonenLaenge;
  band += eckenHoehe;
  var wannenrand = 0.0;
  for (final w in flaechen.where((x) => x.wanne)) {
    for (var i = 0; i < umriss.length; i++) {
      for (final (s0, s1, _) in _zonen(umriss[i], umriss[(i + 1) % umriss.length], [w], zugabe: 0)) {
        wannenrand += (s1 - s0) / 1000;
      }
    }
  }
  band += wannenrand;
  for (final n in nischen) {
    if (n.imSpritzbereich) band += 2 * (n.breite + n.hoehe) / 1000;
  }
  final innen = (bodengleich ? umriss.length : eckenZone) + eckenZone;
  final manschetten = duschen.length * 2 + flaechen.where((x) => x.wanne).length * 2;
  final bodenM = duschen.where((d) => d.bodengleich).length + (bodenablauf ? 1 : 0);

  if (bodengleich) h.add('Bodengleiche Dusche: Gefälle 1–2 % zum Ablauf/zur Rinne, Ablauf mit Dichtflansch, Abdichtung im Verbund (AIV).');
  for (final d in duschen) {
    final xs = d.umriss.map((p) => p.x), ys = d.umriss.map((p) => p.y);
    final b = xs.reduce(math.max) - xs.reduce(math.min), t = ys.reduce(math.max) - ys.reduce(math.min);
    if (math.min(b, t) < 800) h.add('Dusche ${b.round()} × ${t.round()} mm: unter 80 cm Seitenlänge wird es eng (barrierefrei 120 × 120 cm).');
  }
  if (flaechen.any((x) => x.wanne && x.brause)) h.add('Wanne mit Brause: Wandflächen bis 2 m wie in der Dusche abdichten, Wannendichtband am Rand.');
  if (wandZone == 0 && flaechen.isNotEmpty) h.add('Dusche/Wanne liegt an keiner Wand – Lage prüfen (Abstand zur Wand höchstens 15 cm).');
  return AbdichtungErgebnis(
    flaechen: f,
    dichtband: band,
    innenecken: innen,
    aussenecken: 0,
    wandmanschetten: manschetten,
    bodenmanschetten: bodenM,
    hinweise: h,
  );
}

/// Übliche Maße von Badobjekten (Breite × Tiefe × Höhe in mm) je Kürzel.
const badObjektMasse = <String, (int, int, int)>{
  'WC': (380, 560, 400),
  'WT': (600, 480, 850),
  'UR': (360, 350, 650),
};

/// Bewegungsfläche vor Badobjekten nach DIN 18022 (Tiefe in mm).
const badBewegungsflaeche = <String, int>{'WC': 750, 'WT': 550, 'UR': 600};

/// Prüft Abstände der Badobjekte (Mittelpunkt, Drehung) untereinander und zur
/// Wand: Seitenabstand WC/WT ≥ 200 mm (DIN 18022), Bewegungsfläche davor.
List<String> badAbstaende(List<({String kuerzel, String kennung, Punkt mitte})> objekte) {
  final h = <String>[];
  for (var i = 0; i < objekte.length; i++) {
    for (var j = i + 1; j < objekte.length; j++) {
      final a = objekte[i], b = objekte[j];
      final ma = badObjektMasse[a.kuerzel], mb = badObjektMasse[b.kuerzel];
      if (ma == null || mb == null) continue;
      final d = _laenge(a.mitte, b.mitte) - (ma.$1 + mb.$1) / 2;
      if (d < 200) h.add('${a.kennung} und ${b.kennung}: seitlicher Abstand ${math.max(0, d).round()} mm, empfohlen mindestens 200 mm.');
    }
  }
  return h;
}
