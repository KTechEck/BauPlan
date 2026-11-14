import 'dart:math' as math;

/// Hydraulikschema: Symbole (Erzeuger, Speicher, Pumpen, Mischer, Ventile,
/// Fühler, Verbraucher) und Leitungen dazwischen. Gespeichert in der
/// Projekteinstellung `hydraulikschema`; Symbole können mit Objekten im
/// Grundriss verknüpft sein (`objekt`).

/// Symbolarten mit Anzeigename und Standardgröße (Einheiten im Schema).
const schemaSymbole = <String, (String, double, double)>{
  'waermepumpe': ('Wärmepumpe', 80, 60),
  'kessel': ('Kessel / Therme', 60, 80),
  'puffer': ('Pufferspeicher', 50, 110),
  'tww': ('Trinkwasserspeicher', 50, 110),
  'pumpe': ('Pumpe', 30, 30),
  'mischer': ('3-Wege-Mischer', 30, 30),
  'umschalt': ('3-Wege-Umschaltventil', 30, 30),
  'ventil': ('Absperrventil', 24, 24),
  'rueckschlag': ('Rückschlagventil', 24, 24),
  'ag': ('Ausdehnungsgefäß', 30, 44),
  'fuehler': ('Temperaturfühler', 16, 16),
  'waermetauscher': ('Wärmetauscher', 40, 60),
  'verteiler': ('Heizkreisverteiler', 110, 30),
  'fbh': ('Fußbodenheizkreis', 60, 40),
  'heizkoerper': ('Heizkörper', 60, 36),
  'solar': ('Solarkollektor', 80, 50),
  'zaehler': ('Wärmemengenzähler', 30, 24),
  'sicherheit': ('Sicherheitsventil', 20, 28),
  'kw': ('Kaltwasser-Anschluss', 30, 20),
  'text': ('Beschriftung', 60, 16),
};

/// Leitungsarten mit Farbe (ARGB) und Strichart.
const schemaLeitungen = <String, (String, int, bool)>{
  'vl': ('Vorlauf', 0xFFE03131, false),
  'rl': ('Rücklauf', 0xFF1C7ED6, false),
  'tww': ('Warmwasser', 0xFFE8590C, false),
  'kw': ('Kaltwasser', 0xFF15AABF, false),
  'zirk': ('Zirkulation', 0xFFE8590C, true),
  'sole': ('Sole / Glykol', 0xFF2F9E44, false),
  'signal': ('Fühler / Signal', 0xFF6B7178, true),
};

class SchemaSymbol {
  SchemaSymbol({required this.id, required this.art, required this.x, required this.y, this.name = '', this.objekt, this.drehung = 0});
  final String id;
  final String art;
  final double x, y; // Mitte
  final String name;
  final String? objekt; // verknüpftes Objekt im Grundriss
  final int drehung; // 0/90/180/270

  (double, double) get groesse {
    final g = schemaSymbole[art] ?? ('', 40.0, 40.0);
    return drehung % 180 == 0 ? (g.$2, g.$3) : (g.$3, g.$2);
  }

  Map<String, dynamic> toJson() => {'id': id, 'art': art, 'x': x, 'y': y, if (name.isNotEmpty) 'name': name, if (objekt != null) 'objekt': objekt, if (drehung != 0) 'drehung': drehung};
  static SchemaSymbol ausJson(Map m) => SchemaSymbol(
        id: '${m['id']}',
        art: '${m['art']}',
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        name: '${m['name'] ?? ''}',
        objekt: m['objekt'] as String?,
        drehung: (m['drehung'] as num?)?.toInt() ?? 0,
      );

  SchemaSymbol mit({double? x, double? y, String? name, Object? objekt = _k, int? drehung}) =>
      SchemaSymbol(id: id, art: art, x: x ?? this.x, y: y ?? this.y, name: name ?? this.name, objekt: objekt == _k ? this.objekt : objekt as String?, drehung: drehung ?? this.drehung);
}

const _k = Object();

class SchemaLinie {
  SchemaLinie({required this.id, required this.von, required this.bis, this.art = 'vl'});
  final String id, von, bis, art;
  Map<String, dynamic> toJson() => {'id': id, 'von': von, 'bis': bis, 'art': art};
  static SchemaLinie ausJson(Map m) => SchemaLinie(id: '${m['id']}', von: '${m['von']}', bis: '${m['bis']}', art: '${m['art'] ?? 'vl'}');
}

class HydraulikSchema {
  HydraulikSchema(this.symbole, this.linien);
  final List<SchemaSymbol> symbole;
  final List<SchemaLinie> linien;

  Map<String, dynamic> toJson() => {'symbole': [for (final s in symbole) s.toJson()], 'linien': [for (final l in linien) l.toJson()]};
  static HydraulikSchema ausJson(Map? m) => HydraulikSchema(
        [for (final s in (m?['symbole'] as List? ?? const [])) if (s is Map) SchemaSymbol.ausJson(s)],
        [for (final l in (m?['linien'] as List? ?? const [])) if (l is Map) SchemaLinie.ausJson(l)],
      );
}

/// Rechtwinkliger Leitungsweg zwischen zwei Symbolmitten (erst waagerecht, dann senkrecht).
List<(double, double)> schemaWeg(SchemaSymbol a, SchemaSymbol b) {
  final mx = (a.x + b.x) / 2;
  return [(a.x, a.y), (mx, a.y), (mx, b.y), (b.x, b.y)];
}

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Schema als SVG (für Dokumentation, C.M.I.-Schemaseite als Hintergrund,
/// Weitergabe). [platzhalter]: Symbol-ID → Text (z. B. „E1: Vorlauf“).
String schemaSvg(HydraulikSchema s, {Map<String, String> platzhalter = const {}, String titel = ''}) {
  if (s.symbole.isEmpty) return '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200"></svg>';
  var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
  for (final sy in s.symbole) {
    final (b, h) = sy.groesse;
    x0 = math.min(x0, sy.x - b / 2);
    y0 = math.min(y0, sy.y - h / 2);
    x1 = math.max(x1, sy.x + b / 2);
    y1 = math.max(y1, sy.y + h / 2 + 14);
  }
  const rand = 30.0;
  final w = x1 - x0 + 2 * rand, h = y1 - y0 + 2 * rand + (titel.isEmpty ? 0 : 24);
  final dy = titel.isEmpty ? 0.0 : 24.0;
  double tx(double x) => x - x0 + rand;
  double ty(double y) => y - y0 + rand + dy;
  final b = StringBuffer('<svg xmlns="http://www.w3.org/2000/svg" width="${w.round()}" height="${h.round()}" viewBox="0 0 ${w.round()} ${h.round()}" font-family="Arial" font-size="10">')
    ..write('<rect width="100%" height="100%" fill="white"/>');
  if (titel.isNotEmpty) b.write('<text x="${rand.round()}" y="20" font-size="14" font-weight="bold">${_x(titel)}</text>');
  final nach = {for (final sy in s.symbole) sy.id: sy};
  for (final l in s.linien) {
    final a = nach[l.von], z = nach[l.bis];
    if (a == null || z == null) continue;
    final (_, farbe, strich) = schemaLeitungen[l.art] ?? ('', 0xFF000000, false);
    final hex = '#${(farbe & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final pts = schemaWeg(a, z).map((p) => '${tx(p.$1).toStringAsFixed(1)},${ty(p.$2).toStringAsFixed(1)}').join(' ');
    b.write('<polyline points="$pts" fill="none" stroke="$hex" stroke-width="2"${strich ? ' stroke-dasharray="5,4"' : ''}/>');
  }
  for (final sy in s.symbole) {
    final (bb, hh) = sy.groesse;
    final x = tx(sy.x - bb / 2), y = ty(sy.y - hh / 2);
    final rund = const {'pumpe', 'fuehler', 'ag'}.contains(sy.art);
    if (sy.art == 'text') {
      b.write('<text x="${tx(sy.x).toStringAsFixed(1)}" y="${ty(sy.y).toStringAsFixed(1)}" text-anchor="middle">${_x(sy.name)}</text>');
      continue;
    }
    b.write(rund
        ? '<ellipse cx="${tx(sy.x).toStringAsFixed(1)}" cy="${ty(sy.y).toStringAsFixed(1)}" rx="${(bb / 2).toStringAsFixed(1)}" ry="${(hh / 2).toStringAsFixed(1)}" fill="white" stroke="black" stroke-width="1.5"/>'
        : '<rect x="${x.toStringAsFixed(1)}" y="${y.toStringAsFixed(1)}" width="${bb.toStringAsFixed(1)}" height="${hh.toStringAsFixed(1)}" rx="3" fill="white" stroke="black" stroke-width="1.5"/>');
    final label = sy.name.isEmpty ? (schemaSymbole[sy.art]?.$1 ?? sy.art) : sy.name;
    b.write('<text x="${tx(sy.x).toStringAsFixed(1)}" y="${(ty(sy.y + hh / 2) + 11).toStringAsFixed(1)}" text-anchor="middle">${_x(label)}</text>');
    final ph = platzhalter[sy.id];
    if (ph != null) {
      b.write('<text x="${tx(sy.x).toStringAsFixed(1)}" y="${(ty(sy.y) + 3).toStringAsFixed(1)}" text-anchor="middle" fill="#9A3412" font-weight="bold">${_x(ph)}</text>');
    }
  }
  b.write('</svg>');
  return b.toString();
}
