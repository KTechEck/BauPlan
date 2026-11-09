import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// Lesekopie des Projekts, wie der PC sie in `planstand/planstand.json` ablegt.
class Planstand {
  Planstand(this.daten);
  final Map<String, dynamic> daten;

  static Planstand? lesen(List<int>? bytes) {
    if (bytes == null) return null;
    try {
      return Planstand(Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map));
    } catch (_) {
      return null;
    }
  }

  String get projekt => daten['projekt'] as String? ?? 'Projekt';
  DateTime? get erstellt => DateTime.tryParse(daten['erstellt'] as String? ?? '')?.toLocal();
  List<Map<String, dynamic>> get geschosse => _liste(daten['geschosse']);
  List<Map<String, dynamic>> get einkauf => _liste(daten['einkauf']);
  Map<String, ({String name, Color farbe})> get gewerke => {
        for (final g in _liste(daten['gewerke'])) '${g['kuerzel']}': (name: '${g['name']}', farbe: Color((g['farbe'] as num?)?.toInt() ?? 0xFF888888))
      };
  List<({String name, String label})> get status => [
        for (final s in _liste(daten['status'])) (name: '${s['name']}', label: '${s['label']}')
      ];

  Map<String, dynamic>? geschoss(String? id) => geschosse.where((g) => g['id'] == id).firstOrNull ?? geschosse.firstOrNull;

  static List<Map<String, dynamic>> _liste(Object? o) => [for (final x in (o as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
  static List<Map<String, dynamic>> liste(Object? o) => _liste(o);
}

Offset punkt(Object? l) {
  final x = l as List;
  return Offset((x[0] as num).toDouble(), (x[1] as num).toDouble());
}

List<Offset> punkte(Object? l) => [for (final q in (l as List? ?? const [])) punkt(q)];

bool imPolygon(Offset q, List<Offset> poly) {
  var drin = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > q.dy) != (b.dy > q.dy) && q.dx < (b.dx - a.dx) * (q.dy - a.dy) / (b.dy - a.dy) + a.dx) drin = !drin;
  }
  return drin;
}

double abstandStrecke(Offset q, Offset a, Offset b) {
  final d = b - a;
  final l2 = d.dx * d.dx + d.dy * d.dy;
  if (l2 < 1e-9) return (q - a).distance;
  final t = (((q - a).dx * d.dx + (q - a).dy * d.dy) / l2).clamp(0.0, 1.0);
  return (a + d * t - q).distance;
}

/// Bohr-Check: Leitungen und Geräte im Umkreis [radius] mm um [q].
List<(Map<String, dynamic>, double)> bohrCheck(Map<String, dynamic> geschoss, Offset q, {double radius = 300}) {
  final aus = <(Map<String, dynamic>, double)>[];
  for (final o in Planstand.liste(geschoss['objekte'])) {
    final pts = punkte(o['punkte']);
    if (pts.isEmpty) continue;
    var d = double.infinity;
    if (pts.length == 1) {
      d = (pts.first - q).distance;
    } else {
      for (var i = 0; i + 1 < pts.length; i++) {
        d = math.min(d, abstandStrecke(q, pts[i], pts[i + 1]));
      }
    }
    if (d <= radius && o['geometrie'] != 'flaeche') aus.add((o, d));
  }
  aus.sort((a, b) => a.$2.compareTo(b.$2));
  return aus;
}
