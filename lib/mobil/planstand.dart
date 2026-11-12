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

// ------------------------------------------------------------ Planstand v2

extension PlanstandMehr on Planstand {
  List<Map<String, dynamic>> get aufgaben => Planstand.liste(daten['aufgaben']);
  List<Map<String, dynamic>> get aufmassOffen => Planstand.liste(daten['aufmass']);

  /// Raum in irgendeinem Geschoss (mit Geschoss).
  (Map<String, dynamic> raum, Map<String, dynamic> geschoss)? raum(String? id) {
    for (final g in geschosse) {
      for (final r in Planstand.liste(g['raeume'])) {
        if (r['id'] == id) return (r, g);
      }
    }
    return null;
  }

  String raumName(String? id) => '${raum(id)?.$1['name'] ?? ''}';
}

/// Lichte Raumhöhe (mm) aus dem Raum, sonst aus dem Geschoss.
int raumHoehe(Map<String, dynamic> geschoss, String? raumId) {
  final r = Planstand.liste(geschoss['raeume']).where((x) => x['id'] == raumId).firstOrNull;
  final h = (r?['hoehe'] as num?)?.round();
  if (h != null && h > 500) return h;
  final g = ((geschoss['rohdecke'] as num?) ?? 2600) - ((geschoss['ffb'] as num?) ?? 0);
  return g.round() > 500 ? g.round() : 2500;
}

/// Eine Wandseite für die Wandansicht in der App (wie am PC: von der
/// Raumseite aus gesehen, x nach rechts).
class AppWandSeite {
  AppWandSeite(this.wand, this.links);
  final Map<String, dynamic> wand;
  final bool links;

  Offset get a => punkt(wand['a']);
  Offset get b => punkt(wand['b']);
  double get achse => (b - a).distance;
  Offset get u => achse < 1 ? const Offset(1, 0) : (b - a) / achse;
  Offset get nl => Offset(u.dy, -u.dx);
  double get s => links ? 1 : -1;
  double get dicke => (wand['d'] as num?)?.toDouble() ?? 175;
  List<double> get _gr {
    final g = wand['gr'] as List?;
    if (g == null || g.length < 4) return [0, achse, 0, achse];
    return [for (final x in g) (x as num).toDouble()];
  }

  double get tA => links ? _gr[0] : _gr[2];
  double get tB => links ? _gr[1] : _gr[3];
  double get laenge => tB - tA;
  String? get raumId => (links ? wand['rl'] : wand['rr']) as String?;
  String get seiteKurz => links ? 'l' : 'r';

  Offset get ursprung => a + nl * (s * dicke / 2) + u * (links ? tB : tA);
  Offset get richtung => links ? -u : u;

  /// x in der Ansicht für einen Weltpunkt.
  double x(Offset welt) => (welt - ursprung).dx * richtung.dx + (welt - ursprung).dy * richtung.dy;

  /// Abstand vor der Wandoberfläche (positiv = im Raum).
  double vor(Offset welt) => (welt - ursprung).dx * nl.dx * s + (welt - ursprung).dy * nl.dy * s;

  /// x für einen Achsparameter t (ab Wandanfang A).
  double xAusT(double t) => links ? tB - t : t - tA;
}

/// Installationszonen nach DIN 18015-3 in einer Wandansicht (x, z in mm über FFB):
/// waagrecht 15–45 cm unter der Decke und über dem Fußboden, 100–130 cm
/// (Arbeitsflächen); senkrecht 10–30 cm neben Ecken und Öffnungen.
List<Rect> installationszonen(double laenge, double hoehe, List<(double, double)> oeffnungenX) => [
      Rect.fromLTRB(0, hoehe - 450, laenge, hoehe - 150),
      Rect.fromLTRB(0, 150, laenge, 450),
      Rect.fromLTRB(0, 1000, laenge, 1300),
      Rect.fromLTRB(100, 0, 300, hoehe),
      Rect.fromLTRB(laenge - 300, 0, laenge - 100, hoehe),
      for (final (x1, x2) in oeffnungenX) ...[
        Rect.fromLTRB(x1 - 300, 0, x1 - 100, hoehe),
        Rect.fromLTRB(x2 + 100, 0, x2 + 300, hoehe),
      ],
    ];

String mmM(num mm) {
  final v = mm / 1000;
  return '${v.toStringAsFixed(3).replaceAll('.', ',')} m';
}

String mmCm(num mm) => '${(mm / 10).toStringAsFixed(mm.abs() < 100 ? 1 : 0).replaceAll('.', ',')} cm';
