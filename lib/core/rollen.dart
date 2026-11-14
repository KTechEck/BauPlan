import 'dart:math';

/// Rollen laut Lastenheft: Eigentümer (alles), Mitarbeit (anschauen und
/// erfassen in freigegebenen Räumen, Einträge zur Prüfung), Gast (nur lesen).
enum Rolle {
  eigentuemer('Eigentümer', 'alles: planen, ändern, freigeben'),
  mitarbeit('Mitarbeit', 'anschauen und erfassen (Fotos, Notizen, Messwerte), keine Planänderungen'),
  gast('Gast', 'nur lesen');

  const Rolle(this.label, this.darf);
  final String label, darf;

  bool get darfErfassen => this != Rolle.gast;
  static Rolle aus(Object? name) => Rolle.values.where((r) => r.name == name).firstOrNull ?? Rolle.eigentuemer;
}

/// Ein Benutzer des Projekts (Projekteinstellung `benutzer`). Jeder hat einen
/// eigenen Kopplungscode – darüber erkennt der PC, wer sich verbindet.
class Benutzer {
  Benutzer({required this.id, required this.name, required this.rolle, required this.code, this.raeume = const [], this.pruefpflicht = true});
  final String id, name, code;
  final Rolle rolle;

  /// Freigegebene Räume (leer = alle).
  final List<String> raeume;

  /// Einträge erst nach Prüfung durch den Eigentümer übernehmen.
  final bool pruefpflicht;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'rolle': rolle.name, 'code': code, 'raeume': raeume, 'pruefpflicht': pruefpflicht};

  static Benutzer ausJson(Map m) => Benutzer(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        rolle: Rolle.aus(m['rolle']),
        code: '${m['code'] ?? ''}',
        raeume: [for (final r in (m['raeume'] as List? ?? const [])) '$r'],
        pruefpflicht: m['pruefpflicht'] as bool? ?? true,
      );

  /// Was der PC-Dienst über den Benutzer weitergibt (ohne Code).
  Map<String, dynamic> get auskunft => {'benutzer_id': id, 'benutzer': name, 'rolle': rolle.name, if (raeume.isNotEmpty) 'raeume': raeume, 'pruefpflicht': pruefpflicht};

  Benutzer mit({String? name, Rolle? rolle, List<String>? raeume, bool? pruefpflicht, String? code}) => Benutzer(
      id: id, name: name ?? this.name, rolle: rolle ?? this.rolle, code: code ?? this.code, raeume: raeume ?? this.raeume, pruefpflicht: pruefpflicht ?? this.pruefpflicht);
}

List<Benutzer> benutzerAus(Object? liste) => [for (final m in (liste as List? ?? const [])) if (m is Map) Benutzer.ausJson(m)];

String benutzerCode() => (Random.secure().nextInt(900000) + 100000).toString();

/// Planstand für einen Benutzer: Objekte nur in freigegebenen Räumen, dazu
/// Rolle und Name (die App zeigt danach nur, was die Rolle erlaubt).
Map<String, dynamic> planstandFuerBenutzer(Map<String, dynamic> plan, Map<String, dynamic> auskunft) {
  final raeume = {for (final r in (auskunft['raeume'] as List? ?? const [])) '$r'};
  final aus = {...plan, 'rolle': auskunft['rolle'], 'benutzer': auskunft['benutzer']};
  if (raeume.isEmpty) return aus;
  aus['geschosse'] = [
    for (final g in (plan['geschosse'] as List? ?? const []))
      if (g is Map)
        {
          ...g,
          'objekte': [for (final o in (g['objekte'] as List? ?? const [])) if (o is Map && raeume.contains(o['raum'])) o],
        }
  ];
  aus['aufgaben'] = [for (final a in (plan['aufgaben'] as List? ?? const [])) if (a is Map && (a['raum'] == null || raeume.contains(a['raum']))) a];
  aus['freigegeben'] = raeume.toList();
  return aus;
}
