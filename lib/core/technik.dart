import 'dart:math' as math;

import 'raumerkennung.dart';

// ======================================================= Technikraum

/// Gerätevorlage für Technik- und Heizräume: Typkürzel im Projekt, Maße
/// (Breite × Tiefe × Höhe, mm), Montage und Wartungsfreiräume (vorn, links,
/// rechts, oben) nach typischen Herstellerangaben.
typedef TechnikVorlage = ({
  String name,
  String typ,
  int b,
  int t,
  int h,
  String montage,
  int vorn,
  int links,
  int rechts,
  int oben,
});

const technikVorlagen = <TechnikVorlage>[
  (name: 'Wärmepumpe Innengerät', typ: 'HZ', b: 600, t: 600, h: 1800, montage: 'Stand', vorn: 1000, links: 100, rechts: 300, oben: 200),
  (name: 'Gas-Brennwerttherme', typ: 'HZ', b: 440, t: 340, h: 720, montage: 'Wand', vorn: 700, links: 50, rechts: 50, oben: 300),
  (name: 'Trinkwasserspeicher 300 l', typ: 'HZ', b: 650, t: 650, h: 1700, montage: 'Stand', vorn: 600, links: 0, rechts: 0, oben: 400),
  (name: 'Pufferspeicher 200 l', typ: 'HZ', b: 600, t: 600, h: 1300, montage: 'Stand', vorn: 500, links: 0, rechts: 0, oben: 300),
  (name: 'Ausdehnungsgefäß 35 l', typ: 'HZ', b: 360, t: 360, h: 450, montage: 'Wand', vorn: 300, links: 0, rechts: 0, oben: 0),
  (name: 'Heizkreisverteiler (Aufputz)', typ: 'HV', b: 850, t: 125, h: 710, montage: 'Wand', vorn: 600, links: 0, rechts: 0, oben: 0),
  (name: 'Hausanschluss Wasser', typ: 'EN', b: 600, t: 200, h: 400, montage: 'Wand', vorn: 800, links: 0, rechts: 0, oben: 0),
  (name: 'Hausanschlusskasten Strom', typ: 'VT', b: 300, t: 150, h: 400, montage: 'Wand', vorn: 1200, links: 300, rechts: 300, oben: 0),
  (name: 'Zählerschrank', typ: 'VT', b: 800, t: 210, h: 1100, montage: 'Wand', vorn: 1200, links: 0, rechts: 0, oben: 0),
  (name: 'Netzwerkschrank 12 HE', typ: 'AP', b: 600, t: 450, h: 640, montage: 'Wand', vorn: 800, links: 0, rechts: 0, oben: 0),
  (name: 'Lüftungsgerät', typ: 'LG', b: 700, t: 600, h: 800, montage: 'Wand', vorn: 700, links: 100, rechts: 300, oben: 300),
];

/// Vorlagensätze für typische Räume.
const raumVorlagen = <String, List<String>>{
  'Heizraum': ['Wärmepumpe Innengerät', 'Trinkwasserspeicher 300 l', 'Pufferspeicher 200 l', 'Ausdehnungsgefäß 35 l', 'Heizkreisverteiler (Aufputz)'],
  'Technikraum': ['Hausanschluss Wasser', 'Hausanschlusskasten Strom', 'Zählerschrank', 'Netzwerkschrank 12 HE', 'Lüftungsgerät'],
};

/// Grundriss eines Technikgeräts: Mitte (mm), Maße und Drehung (Grad, 0 =
/// Vorderseite zeigt nach +y).
typedef TechnikGeraet = ({String id, String name, double x, double y, int b, int t, int drehung, int vorn, int links, int rechts});

/// Ecken eines gedrehten Rechtecks um (x, y): [b] quer, [t] in Blickrichtung.
List<Punkt> _rechteck(double x, double y, double b, double t, int drehung, {double dx = 0, double dy = 0}) {
  final w = drehung * math.pi / 180;
  final c = math.cos(w), s = math.sin(w);
  Punkt p(double u, double v) => Punkt(x + (u + dx) * c - (v + dy) * s, y + (u + dx) * s + (v + dy) * c);
  return [p(-b / 2, -t / 2), p(b / 2, -t / 2), p(b / 2, t / 2), p(-b / 2, t / 2)];
}

List<Punkt> geraeteUmriss(TechnikGeraet g) => _rechteck(g.x, g.y, g.b.toDouble(), g.t.toDouble(), g.drehung);

/// Wartungsfreiraum vor dem Gerät (inkl. seitlicher Zuschläge), als Rechteck.
List<Punkt> freiraumUmriss(TechnikGeraet g) {
  final b = g.b + g.links + g.rechts.toDouble();
  final verschiebung = (g.rechts - g.links) / 2;
  return _rechteck(g.x, g.y, b, g.vorn.toDouble(), g.drehung, dx: verschiebung, dy: g.t / 2 + g.vorn / 2);
}

/// Schneiden sich zwei konvexe Vielecke? (Trennachsen-Test)
bool vieleckeSchneiden(List<Punkt> a, List<Punkt> b) {
  for (final poly in [a, b]) {
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i], q = poly[(i + 1) % poly.length];
      final n = Punkt(-(q.y - p.y), q.x - p.x);
      double proj(Punkt r) => r.x * n.x + r.y * n.y;
      final pa = a.map(proj), pb = b.map(proj);
      final aMin = pa.reduce(math.min), aMax = pa.reduce(math.max);
      final bMin = pb.reduce(math.min), bMax = pb.reduce(math.max);
      if (aMax <= bMin + 1 || bMax <= aMin + 1) return false; // Berührung zählt nicht
    }
  }
  return true;
}

/// Kollisionen im Technikraum: Geräte überlappen, Gerät im Wartungsfreiraum
/// eines anderen, Gerät oder Freiraum außerhalb des Raums.
List<String> technikKollisionen(List<TechnikGeraet> geraete, {List<Punkt>? raum}) {
  final h = <String>[];
  for (var i = 0; i < geraete.length; i++) {
    final a = geraete[i];
    final ua = geraeteUmriss(a);
    if (raum != null && !ua.every((p) => punktInPolygon(p, raum))) h.add('${a.name} ragt aus dem Raum.');
    for (var j = 0; j < geraete.length; j++) {
      if (i == j) continue;
      final b = geraete[j];
      if (j > i && vieleckeSchneiden(ua, geraeteUmriss(b))) h.add('${a.name} und ${b.name} überlappen.');
      if (b.vorn > 0 && vieleckeSchneiden(ua, freiraumUmriss(b))) h.add('${a.name} steht im Wartungsfreiraum von ${b.name}.');
    }
    if (raum != null && a.vorn > 0) {
      final fr = freiraumUmriss(a);
      if (!fr.every((p) => punktInPolygon(p, raum))) h.add('Wartungsfreiraum von ${a.name} reicht über den Raum hinaus.');
    }
  }
  return h;
}

/// Elektro unter wasserführender Leitung: Elektroobjekt (Lage, Höhe über FFB)
/// liegt im Grundriss näher als [abstand] an einer Wasser-/Heizleitung, die höher liegt.
List<String> elektroUnterWasser(
  List<({String name, double x, double y, double z})> elektro,
  List<({String name, List<Punkt> punkte, double z})> wasser, {
  double abstand = 300,
}) {
  final h = <String>[];
  for (final e in elektro) {
    for (final w in wasser) {
      if (w.z <= e.z) continue;
      for (var i = 0; i + 1 < w.punkte.length; i++) {
        final a = w.punkte[i], b = w.punkte[i + 1];
        final ab = b - a;
        final l2 = ab.x * ab.x + ab.y * ab.y;
        final t = l2 == 0 ? 0.0 : (((e.x - a.x) * ab.x + (e.y - a.y) * ab.y) / l2).clamp(0.0, 1.0);
        final d = (Punkt(e.x, e.y) - Punkt(a.x + ab.x * t, a.y + ab.y * t)).laenge;
        if (d < abstand) {
          h.add('${e.name} liegt unter ${w.name} (wasserführend).');
          break;
        }
      }
    }
  }
  return h;
}

// ======================================================= Schächte und Trassen

const schachtArten = ['Installationsschacht', 'Kabelkanal', 'Kabelrinne', 'Leerrohrbündel', 'Deckentrasse'];

/// Zonen im Querschnitt, von unten nach oben.
const schachtZonen = ['Abwasser', 'Wasser', 'Heizung', 'Lüftung', 'Elektro', 'Daten'];

/// Belegung: Rohr oder Kabel mit Außendurchmesser (mm) und Dämmdicke (mm).
class SchachtLeitung {
  SchachtLeitung({
    required this.id,
    required this.bezeichnung,
    required this.zone,
    required this.durchmesser,
    this.daemmung = 0,
    this.vonGeschoss,
    this.bisGeschoss,
    this.objektId,
  });
  final String id;
  final String bezeichnung;
  final String zone;
  final double durchmesser;
  final double daemmung;
  final String? vonGeschoss, bisGeschoss; // Ein- und Austritt (Steigschema)
  final String? objektId; // Leitung im Grundriss

  double get aussen => durchmesser + 2 * daemmung;
  bool get warm {
    final b = bezeichnung.toLowerCase();
    return zone == 'Heizung' || b.contains('warm') || b.contains('zirk') || RegExp(r'^(ww|zi|vl|rl)(\s|$)').hasMatch(b);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bezeichnung': bezeichnung,
        'zone': zone,
        'd': durchmesser,
        'daemmung': daemmung,
        'von': vonGeschoss,
        'bis': bisGeschoss,
        'objekt': objektId,
      };

  static SchachtLeitung ausJson(Map<String, dynamic> m) => SchachtLeitung(
        id: m['id'] as String,
        bezeichnung: m['bezeichnung'] as String? ?? '',
        zone: m['zone'] as String? ?? 'Elektro',
        durchmesser: (m['d'] as num?)?.toDouble() ?? 10,
        daemmung: (m['daemmung'] as num?)?.toDouble() ?? 0,
        vonGeschoss: m['von'] as String?,
        bisGeschoss: m['bis'] as String?,
        objektId: m['objekt'] as String?,
      );
}

class Schacht {
  Schacht({
    required this.id,
    required this.name,
    this.art = 'Installationsschacht',
    this.breite = 300,
    this.tiefe = 200,
    this.trennsteg = false,
    this.geschosse = const [],
    this.leitungen = const [],
  });
  final String id;
  final String name;
  final String art;
  final int breite, tiefe; // Innenmaße mm
  final bool trennsteg; // Trennung Starkstrom/Daten vorhanden
  final List<String> geschosse;
  final List<SchachtLeitung> leitungen;

  /// Zulässiger Füllgrad (Anteil der Querschnittsfläche).
  double get maxFuellgrad => switch (art) {
        'Kabelkanal' => 0.6,
        'Leerrohrbündel' => 0.4,
        _ => 0.5,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'art': art,
        'b': breite,
        't': tiefe,
        'trennsteg': trennsteg,
        'geschosse': geschosse,
        'leitungen': [for (final l in leitungen) l.toJson()],
      };

  static Schacht ausJson(Map<String, dynamic> m) => Schacht(
        id: m['id'] as String,
        name: m['name'] as String? ?? 'Schacht',
        art: m['art'] as String? ?? 'Installationsschacht',
        breite: (m['b'] as num?)?.toInt() ?? 300,
        tiefe: (m['t'] as num?)?.toInt() ?? 200,
        trennsteg: m['trennsteg'] as bool? ?? false,
        geschosse: [for (final g in (m['geschosse'] as List? ?? const [])) g as String],
        leitungen: [for (final l in (m['leitungen'] as List? ?? const [])) SchachtLeitung.ausJson(Map<String, dynamic>.from(l as Map))],
      );

  Schacht mit({String? name, String? art, int? breite, int? tiefe, bool? trennsteg, List<String>? geschosse, List<SchachtLeitung>? leitungen}) =>
      Schacht(
        id: id,
        name: name ?? this.name,
        art: art ?? this.art,
        breite: breite ?? this.breite,
        tiefe: tiefe ?? this.tiefe,
        trennsteg: trennsteg ?? this.trennsteg,
        geschosse: geschosse ?? this.geschosse,
        leitungen: leitungen ?? this.leitungen,
      );
}

/// Typische Außendurchmesser (mm) zum Auswählen.
const leitungsVorlagen = <String, (String, double, double)>{
  'NYM-J 3×1,5': ('Elektro', 8.5, 0),
  'NYM-J 3×2,5': ('Elektro', 10, 0),
  'NYM-J 5×2,5': ('Elektro', 12.5, 0),
  'NYM-J 5×6': ('Elektro', 17, 0),
  'KNX-Busleitung': ('Daten', 5.5, 0),
  'CAT 7': ('Daten', 7.5, 0),
  'Koax': ('Daten', 7, 0),
  'Leerrohr M25': ('Elektro', 25, 0),
  'Verbundrohr 16×2 (gedämmt)': ('Wasser', 16, 9),
  'Verbundrohr 20×2 (gedämmt)': ('Wasser', 20, 13),
  'Verbundrohr 26×3 (gedämmt)': ('Heizung', 26, 20),
  'HT-Rohr DN 50': ('Abwasser', 50, 0),
  'HT-Rohr DN 100': ('Abwasser', 110, 0),
  'Lüftungsrohr DN 125': ('Lüftung', 125, 10),
};

/// Füllgrad (0 … 1): Kreisflächen der Leitungen inkl. Dämmung durch die Innenfläche.
double fuellgrad(Schacht s) {
  final innen = s.breite * s.tiefe.toDouble();
  if (innen <= 0) return 0;
  final belegt = s.leitungen.fold<double>(0, (a, l) => a + math.pi * math.pow(l.aussen / 2, 2));
  return belegt / innen;
}

/// Lage der Leitungen im Querschnitt (Mitte x/y in mm ab linker unterer
/// Innenecke): je Zone von unten nach oben in Reihen, links beginnend.
/// Liefert auch, ob alles hineinpasst.
({List<(SchachtLeitung, double, double)> lagen, bool passt}) querschnitt(Schacht s) {
  final lagen = <(SchachtLeitung, double, double)>[];
  var y = 0.0; // Unterkante der aktuellen Reihe
  var passt = true;
  for (final zone in schachtZonen) {
    final inZone = [for (final l in s.leitungen) if (l.zone == zone) l]..sort((a, b) => b.aussen.compareTo(a.aussen));
    if (inZone.isEmpty) continue;
    var x = 0.0, reihe = 0.0;
    for (final l in inZone) {
      final d = l.aussen + 4; // 2 mm Luft je Seite
      if (x + d > s.breite && x > 0) {
        y += reihe;
        x = 0;
        reihe = 0;
      }
      lagen.add((l, x + d / 2, y + d / 2));
      x += d;
      reihe = math.max(reihe, d);
    }
    y += reihe;
  }
  if (y > s.tiefe) passt = false;
  for (final (l, x, _) in lagen) {
    if (x + l.aussen / 2 > s.breite) passt = false;
  }
  return (lagen: lagen, passt: passt);
}

/// Regeln und Hinweise zu einem Schacht bzw. einer Trasse.
List<String> schachtHinweise(Schacht s) {
  final h = <String>[];
  final f = fuellgrad(s);
  if (f > s.maxFuellgrad) {
    h.add('Füllgrad ${(f * 100).round()} % über ${(s.maxFuellgrad * 100).round()} % – größer planen oder aufteilen.');
  }
  if (!querschnitt(s).passt) h.add('Die Leitungen passen so nicht in den Querschnitt ${s.breite} × ${s.tiefe} mm.');
  final zonen = {for (final l in s.leitungen) l.zone};
  if (zonen.contains('Elektro') && zonen.contains('Daten') && !s.trennsteg) {
    h.add('Starkstrom und Daten ohne Trennsteg – trennen oder Abstand halten.');
  }
  if (zonen.contains('Elektro') && s.leitungen.any((l) => l.warm)) {
    h.add('Warmgehende Leitungen neben Elektro: Abstand halten bzw. gut dämmen.');
  }
  if ((zonen.contains('Wasser') || zonen.contains('Abwasser')) && zonen.contains('Elektro')) {
    h.add('Wasser unten, Elektro oben anordnen (im Querschnitt bereits so sortiert).');
  }
  if (s.geschosse.length > 1) {
    h.add('Decken- und Wanddurchgänge brandschutzgerecht abschotten (Hinweis).');
  }
  for (final l in s.leitungen) {
    if (l.zone == 'Abwasser' && l.durchmesser >= 100 && s.tiefe < 150) h.add('${l.bezeichnung}: Schachttiefe für DN 100 knapp.');
  }
  return h;
}

/// Länge einer Leitung im Schacht: Summe der Geschosshöhen zwischen Ein- und
/// Austritt (Geschosse in Reihenfolge, Höhen in mm).
double laengeImSchacht(SchachtLeitung l, List<String> geschosse, Map<String, int> geschossHoehe) {
  if (geschosse.isEmpty) return 0;
  var a = l.vonGeschoss == null ? 0 : geschosse.indexOf(l.vonGeschoss!);
  var b = l.bisGeschoss == null ? geschosse.length - 1 : geschosse.indexOf(l.bisGeschoss!);
  if (a < 0) a = 0;
  if (b < 0) b = geschosse.length - 1;
  if (a > b) (a, b) = (b, a);
  var summe = 0.0;
  for (var i = a; i < b; i++) {
    summe += geschossHoehe[geschosse[i]] ?? 2800;
  }
  return summe;
}
