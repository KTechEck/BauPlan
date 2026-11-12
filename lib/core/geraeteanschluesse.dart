import 'bauelemente.dart';

/// Anschlüsse an einem Gerät aus der Bibliothek (Elektro, Sanitär, Heizung,
/// Lüftung …): Art, Bezeichnung, Seite und Lage in der Vorderansicht.
/// x läuft von der linken Gerätekante nach rechts, y von der Unterkante nach
/// oben (mm). Gespeichert in `Bauelement.daten['anschluesse']`.
class GeraeteAnschluss {
  const GeraeteAnschluss({required this.art, this.name = '', this.seite = 'hinten', this.x = 0, this.y = 0, this.groesse = ''});
  final String art;
  final String name;
  final String seite;
  final int x, y;
  final String groesse;

  String get anzeige => name.isEmpty ? art : name;

  GeraeteAnschluss mit({String? art, String? name, String? seite, int? x, int? y, String? groesse}) => GeraeteAnschluss(
        art: art ?? this.art,
        name: name ?? this.name,
        seite: seite ?? this.seite,
        x: x ?? this.x,
        y: y ?? this.y,
        groesse: groesse ?? this.groesse,
      );

  Map<String, dynamic> toJson() => {'art': art, if (name.isNotEmpty) 'name': name, 'seite': seite, 'x': x, 'y': y, if (groesse.isNotEmpty) 'groesse': groesse};

  static GeraeteAnschluss ausJson(Map m) => GeraeteAnschluss(
        art: '${m['art'] ?? 'Sonstiges'}',
        name: '${m['name'] ?? ''}',
        seite: '${m['seite'] ?? 'hinten'}',
        x: (m['x'] as num?)?.round() ?? 0,
        y: (m['y'] as num?)?.round() ?? 0,
        groesse: '${m['groesse'] ?? ''}',
      );
}

const anschlussSeiten = ['hinten', 'unten', 'oben', 'links', 'rechts', 'vorne'];

/// Anschlussarten mit Farbe (ARGB) für Skizze und Wandansicht.
const anschlussArten = <String, int>{
  '230 V': 0xFFE6A700,
  '400 V': 0xFFB45309,
  'Steuerleitung': 0xFFF59F00,
  'KNX / Bus': 0xFF2F9E44,
  'Netzwerk': 0xFF7048E8,
  'Antenne / SAT': 0xFF9C36B5,
  'Kaltwasser': 0xFF1C7ED6,
  'Warmwasser': 0xFFE03131,
  'Zirkulation': 0xFFC2255C,
  'Abwasser': 0xFF5C3D2E,
  'Heizung Vorlauf': 0xFFE8590C,
  'Heizung Rücklauf': 0xFF4263EB,
  'Solar Vorlauf': 0xFFF76707,
  'Solar Rücklauf': 0xFF3B5BDB,
  'Gas': 0xFFFAB005,
  'Zuluft': 0xFF0CA678,
  'Abluft': 0xFFE67700,
  'Fortluft': 0xFF868E96,
  'Außenluft': 0xFF15AABF,
  'Kältemittel flüssig': 0xFF1098AD,
  'Kältemittel Sauggas': 0xFF0B7285,
  'Kondensat': 0xFF74C0FC,
  'Sicherheitsventil / Ablauf': 0xFF495057,
  'Fühler': 0xFF20C997,
  'Sonstiges': 0xFF868E96,
};

int anschlussFarbe(String art) => anschlussArten[art] ?? 0xFF868E96;

/// Für welche Kategorien Anschlüsse gepflegt werden.
bool kategorieMitAnschluessen(BauelementKategorie k) => const {
      BauelementKategorie.elektro,
      BauelementKategorie.leuchte,
      BauelementKategorie.sensor,
      BauelementKategorie.brandschutz,
      BauelementKategorie.schrankgeraet,
      BauelementKategorie.technik,
      BauelementKategorie.heizkoerper,
      BauelementKategorie.sanitaer,
      BauelementKategorie.armatur,
      BauelementKategorie.sonnenschutz,
      BauelementKategorie.sonstiges,
    }.contains(k);

List<GeraeteAnschluss> geraeteAnschluesse(Map<String, dynamic> daten) => [
      for (final m in (daten['anschluesse'] as List? ?? const [])) if (m is Map) GeraeteAnschluss.ausJson(m),
    ];

Map<String, dynamic> mitAnschluessen(Map<String, dynamic> daten, List<GeraeteAnschluss> l) {
  final d = {...daten};
  if (l.isEmpty) {
    d.remove('anschluesse');
  } else {
    d['anschluesse'] = [for (final a in l) a.toJson()];
  }
  return d;
}

/// Vorschlag für typische Anschlüsse einer Kategorie (Breite b, Höhe h in mm).
List<GeraeteAnschluss> anschlussVorschlag(BauelementKategorie k, Map<String, dynamic> daten) {
  int zahl(String s, int vorgabe) {
    final v = daten[s];
    if (v is num) return v.round();
    return int.tryParse('$v') ?? vorgabe;
  }

  final b = zahl('breite', k == BauelementKategorie.technik ? 600 : 80), h = zahl('hoehe', k == BauelementKategorie.technik ? 1800 : 80);
  final m = b ~/ 2;
  switch (k) {
    case BauelementKategorie.elektro:
    case BauelementKategorie.leuchte:
    case BauelementKategorie.sonnenschutz:
      return [GeraeteAnschluss(art: '230 V', name: 'Zuleitung', x: m, y: h ~/ 2)];
    case BauelementKategorie.sensor:
    case BauelementKategorie.brandschutz:
      return [GeraeteAnschluss(art: 'KNX / Bus', name: 'Bus / Vernetzung', x: m, y: h ~/ 2)];
    case BauelementKategorie.heizkoerper:
      return [
        GeraeteAnschluss(art: 'Heizung Vorlauf', name: 'VL', seite: 'unten', x: m - 25, y: 0, groesse: '½"'),
        GeraeteAnschluss(art: 'Heizung Rücklauf', name: 'RL', seite: 'unten', x: m + 25, y: 0, groesse: '½"'),
      ];
    case BauelementKategorie.sanitaer:
      return [
        GeraeteAnschluss(art: 'Kaltwasser', name: 'KW', x: m - 80, y: zahl('anschluss_hoehe', 550), groesse: '½"'),
        GeraeteAnschluss(art: 'Warmwasser', name: 'WW', x: m + 80, y: zahl('anschluss_hoehe', 550), groesse: '½"'),
        GeraeteAnschluss(art: 'Abwasser', name: 'AW', x: m, y: 500, groesse: 'DN ${daten['abfluss_dn'] ?? 50}'),
      ];
    case BauelementKategorie.technik:
      return [
        GeraeteAnschluss(art: '230 V', name: 'Netz', seite: 'oben', x: b - 60, y: h),
        GeraeteAnschluss(art: 'Heizung Vorlauf', name: 'VL', seite: 'oben', x: 100, y: h),
        GeraeteAnschluss(art: 'Heizung Rücklauf', name: 'RL', seite: 'oben', x: 200, y: h),
      ];
    default:
      return [GeraeteAnschluss(art: '230 V', x: m, y: h ~/ 2)];
  }
}
