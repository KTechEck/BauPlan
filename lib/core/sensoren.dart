import 'dart:convert';

/// Anschluss eines eigenen Sensors: Bezeichnung (z. B. „+5 V“, „GND“, „Daten“)
/// und Aderfarbe der Zuleitung.
typedef SensorAnschluss = ({String name, String farbe});

/// Vorlage für einen selbst gebauten oder zugekauften Sensor (Bibliothek).
class SensorVorlage {
  SensorVorlage({
    required this.id,
    required this.name,
    this.kategorie = 'Klima',
    this.breite = 0,
    this.hoehe = 0,
    this.tiefe = 0,
    this.montage = 'Wand',
    this.versorgung = '5 V DC',
    this.protokoll = 'ESPHome / WLAN',
    this.anschluesse = const [],
    this.entitaeten = const [],
    this.dateien = const [],
    this.notiz = '',
  });

  final String id;
  final String name;
  final String kategorie;
  final int breite, hoehe, tiefe; // mm
  final String montage; // Decke, Wand, UP-Dose, Kanal, Hutschiene
  final String versorgung;
  final String protokoll;
  final List<SensorAnschluss> anschluesse;

  /// Home-Assistant-Entitäten als Vorlage, z. B. „temperatur“, „feuchte“, „co2“.
  final List<String> entitaeten;

  /// Dateien relativ zum Projektordner (Schaltplan, Firmware, STL, Fotos …).
  final List<String> dateien;
  final String notiz;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kategorie': kategorie,
        'masse': [breite, hoehe, tiefe],
        'montage': montage,
        'versorgung': versorgung,
        'protokoll': protokoll,
        'anschluesse': [for (final a in anschluesse) {'name': a.name, 'farbe': a.farbe}],
        'entitaeten': entitaeten,
        'dateien': dateien,
        'notiz': notiz,
      };

  static SensorVorlage ausJson(Map<String, dynamic> m) {
    final masse = (m['masse'] as List? ?? const [0, 0, 0]).map((e) => (e as num).toInt()).toList();
    return SensorVorlage(
      id: m['id'] as String,
      name: m['name'] as String? ?? 'Sensor',
      kategorie: m['kategorie'] as String? ?? 'Klima',
      breite: masse.isNotEmpty ? masse[0] : 0,
      hoehe: masse.length > 1 ? masse[1] : 0,
      tiefe: masse.length > 2 ? masse[2] : 0,
      montage: m['montage'] as String? ?? 'Wand',
      versorgung: m['versorgung'] as String? ?? '',
      protokoll: m['protokoll'] as String? ?? '',
      anschluesse: [
        for (final a in (m['anschluesse'] as List? ?? const []))
          (name: (a as Map)['name'] as String? ?? '', farbe: a['farbe'] as String? ?? ''),
      ],
      entitaeten: [for (final e in (m['entitaeten'] as List? ?? const [])) e as String],
      dateien: [for (final e in (m['dateien'] as List? ?? const [])) e as String],
      notiz: m['notiz'] as String? ?? '',
    );
  }

  SensorVorlage mit({
    String? name,
    String? kategorie,
    int? breite,
    int? hoehe,
    int? tiefe,
    String? montage,
    String? versorgung,
    String? protokoll,
    List<SensorAnschluss>? anschluesse,
    List<String>? entitaeten,
    List<String>? dateien,
    String? notiz,
  }) =>
      SensorVorlage(
        id: id,
        name: name ?? this.name,
        kategorie: kategorie ?? this.kategorie,
        breite: breite ?? this.breite,
        hoehe: hoehe ?? this.hoehe,
        tiefe: tiefe ?? this.tiefe,
        montage: montage ?? this.montage,
        versorgung: versorgung ?? this.versorgung,
        protokoll: protokoll ?? this.protokoll,
        anschluesse: anschluesse ?? this.anschluesse,
        entitaeten: entitaeten ?? this.entitaeten,
        dateien: dateien ?? this.dateien,
        notiz: notiz ?? this.notiz,
      );
}

const sensorKategorien = ['Klima', 'Luftqualität', 'Präsenz / Bewegung', 'Fenster / Tür', 'Wasser / Leckage', 'Energie', 'Licht', 'Sonstiges'];
const sensorMontagen = ['Decke', 'Wand', 'UP-Dose', 'Kanal', 'Hutschiene', 'Aufputz'];
const sensorProtokolle = ['ESPHome / WLAN', '1-Wire', 'I²C', 'RS485 / Modbus', 'KNX', 'Zigbee', 'Binäreingang', 'analog 0–10 V'];
const aderfarben = ['rot', 'schwarz', 'gelb', 'weiß', 'grün', 'braun', 'blau', 'grau', 'rosa', 'violett', 'orange'];

/// Kabeltypen für Signal-, Bus- und Netzwerkleitungen mit Adern.
const kabelTypen = <String, List<String>>{
  'J-Y(St)Y 2×2×0,8': ['rot', 'schwarz', 'weiß', 'gelb'],
  'J-Y(St)Y 4×2×0,8': ['rot', 'schwarz', 'weiß', 'gelb', 'braun', 'grün', 'blau', 'grau'],
  'KNX-Busleitung (J-Y(St)Y 2×2×0,8, grün)': ['rot', 'schwarz', 'weiß', 'gelb'],
  'LiYY 4×0,25': ['weiß', 'braun', 'grün', 'gelb'],
  'LiYCY 6×0,25 (geschirmt)': ['weiß', 'braun', 'grün', 'gelb', 'grau', 'rosa'],
  'CAT 7 S/FTP': ['weiß-orange', 'orange', 'weiß-grün', 'blau', 'weiß-blau', 'grün', 'weiß-braun', 'braun'],
  'Klingeldraht YR 4×0,8': ['rot', 'schwarz', 'weiß', 'gelb'],
};

/// Standardbelegung je Protokoll (Ader → Signal), wenn noch nichts eingetragen ist.
Map<String, String> standardBelegung(String protokoll) => switch (protokoll) {
      '1-Wire' => {'rot': '+5 V', 'schwarz': 'GND', 'gelb': 'Daten'},
      'I²C' => {'rot': '+3,3 V', 'schwarz': 'GND', 'weiß': 'SDA', 'gelb': 'SCL'},
      'RS485 / Modbus' => {'rot': '+24 V', 'schwarz': 'GND', 'weiß': 'A', 'gelb': 'B'},
      'KNX' => {'rot': 'KNX +', 'schwarz': 'KNX −'},
      _ => {'rot': '+', 'schwarz': 'GND'},
    };

/// Home-Assistant-Entitäten einer eingebauten Instanz: je Vorlagen-Entität
/// `sensor.<präfix>_<entität>` (Präfix aus Raum und Kennung).
Map<String, String> instanzEntitaeten(SensorVorlage v, String praefix) => {
      for (final e in v.entitaeten) e: '${e == 'bewegung' || e == 'fenster' || e == 'wasser' ? 'binary_sensor' : 'sensor'}.${praefix}_$e',
    };

/// Inhaltspaket: Vorlagen als JSON (zum Weitergeben zwischen Projekten).
String inhaltspaket(List<SensorVorlage> vorlagen) =>
    const JsonEncoder.withIndent('  ').convert({'bauspur_inhaltspaket': 1, 'art': 'sensoren', 'sensoren': [for (final v in vorlagen) v.toJson()]});

/// Inhaltspaket lesen; wirft FormatException bei fremden Dateien.
List<SensorVorlage> inhaltspaketLesen(String json) {
  final m = jsonDecode(json);
  if (m is! Map || m['bauspur_inhaltspaket'] == null || m['art'] != 'sensoren') {
    throw const FormatException('Kein BauSpur-Inhaltspaket mit Sensoren.');
  }
  return [for (final s in (m['sensoren'] as List)) SensorVorlage.ausJson(Map<String, dynamic>.from(s as Map))];
}

/// Netztopologie aus Leitungsstrecken (Endpunkte als Knoten, ≤ [toleranz] mm
/// zusammengefasst): „Linie“, „Stern“ oder „Baum“; null ohne Leitung.
String? topologie(List<List<(double, double)>> leitungen, {double toleranz = 5}) {
  if (leitungen.isEmpty) return null;
  final knoten = <(double, double)>[];
  int knotenVon((double, double) p) {
    for (var i = 0; i < knoten.length; i++) {
      final k = knoten[i];
      if ((k.$1 - p.$1).abs() <= toleranz && (k.$2 - p.$2).abs() <= toleranz) return i;
    }
    knoten.add(p);
    return knoten.length - 1;
  }

  final grad = <int, int>{};
  for (final l in leitungen) {
    if (l.length < 2) continue;
    final a = knotenVon(l.first), b = knotenVon(l.last);
    grad[a] = (grad[a] ?? 0) + 1;
    grad[b] = (grad[b] ?? 0) + 1;
  }
  final hoch = grad.values.where((g) => g >= 3).length;
  if (hoch == 0) return 'Linie';
  if (hoch == 1) return 'Stern';
  return 'Baum';
}
