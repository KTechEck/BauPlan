import '../data/project_store.dart';
import '../data/schrank_models.dart';

/// 19″-Rack im Netzwerkschrank: Geräte nach Höheneinheiten (HE, 44,45 mm)
/// in `schrank.eigenschaften.rack`, Ports der Patchfelder in `…patch`.

const rackArten = ['Patchfeld', 'Switch', 'Router / Firewall', 'Fachboden', 'NAS / Server', 'USV', 'Steckdosenleiste', 'Kabelführung', 'Blende', 'Sonstiges'];

class RackGeraet {
  RackGeraet({required this.id, required this.art, required this.he, this.hoehe = 1, this.name = '', this.ports = 0, this.watt = 0});
  final String id;
  final String art;
  final int he; // unterste belegte HE (1 = ganz unten)
  final int hoehe; // HE
  final String name;
  final int ports;
  final int watt;

  int get oben => he + hoehe - 1;

  Map<String, dynamic> toJson() => {'id': id, 'art': art, 'he': he, 'hoehe': hoehe, if (name.isNotEmpty) 'name': name, if (ports > 0) 'ports': ports, if (watt > 0) 'watt': watt};

  static RackGeraet ausJson(Map m) => RackGeraet(
        id: '${m['id']}',
        art: '${m['art'] ?? 'Sonstiges'}',
        he: (m['he'] as num?)?.toInt() ?? 1,
        hoehe: (m['hoehe'] as num?)?.toInt() ?? 1,
        name: '${m['name'] ?? ''}',
        ports: (m['ports'] as num?)?.toInt() ?? 0,
        watt: (m['watt'] as num?)?.toInt() ?? 0,
      );

  RackGeraet mit({String? art, int? he, int? hoehe, String? name, int? ports, int? watt}) =>
      RackGeraet(id: id, art: art ?? this.art, he: he ?? this.he, hoehe: hoehe ?? this.hoehe, name: name ?? this.name, ports: ports ?? this.ports, watt: watt ?? this.watt);
}

List<RackGeraet> rackLesen(Schrank s) => [for (final m in (s.eigenschaften['rack'] as List? ?? const [])) if (m is Map) RackGeraet.ausJson(m)];

/// Höhe des Racks in HE (`schrank.eigenschaften.rack_he`, Vorgabe 12).
int rackHoehe(Schrank s) => (s.eigenschaften['rack_he'] as num?)?.toInt() ?? 12;

/// Prüfung: Überlappungen, außerhalb, Füllgrad, Wärme.
List<String> rackPruefen(Schrank s) {
  final g = rackLesen(s)..sort((a, b) => a.he.compareTo(b.he));
  final h = rackHoehe(s);
  final aus = <String>[];
  for (var i = 0; i < g.length; i++) {
    if (g[i].he < 1 || g[i].oben > h) aus.add('${g[i].name.isEmpty ? g[i].art : g[i].name} ragt aus dem Rack ($h HE)');
    for (var j = i + 1; j < g.length; j++) {
      if (g[j].he <= g[i].oben) aus.add('${g[i].name.isEmpty ? g[i].art : g[i].name} und ${g[j].name.isEmpty ? g[j].art : g[j].name} überlappen');
    }
  }
  final belegt = g.fold<int>(0, (a, x) => a + x.hoehe);
  if (h > 0 && belegt / h > 0.8) aus.add('Rack zu ${(belegt / h * 100).round()} % belegt – Reserve einplanen');
  final watt = g.fold<int>(0, (a, x) => a + x.watt);
  if (watt > 150) aus.add('$watt W Abwärme – Belüftung/Lüfter im Schrank vorsehen');
  final pf = g.where((x) => x.art == 'Patchfeld').fold<int>(0, (a, x) => a + (x.ports == 0 ? 24 : x.ports));
  final sw = g.where((x) => x.art == 'Switch').fold<int>(0, (a, x) => a + x.ports);
  if (pf > 0 && sw > 0 && sw < pf) aus.add('Switch-Ports ($sw) weniger als Patchfeld-Ports ($pf)');
  return aus;
}

/// Wo eine Dose aufgelegt ist: „NW1 Port 12“ (alle Netzwerkschränke), sonst null.
String? dosePort(ProjectStore store, String objektId) {
  for (final s in store.schraenke()) {
    final p = s.eigenschaften['patch'] as Map? ?? const {};
    for (final e in p.entries) {
      if (e.value == objektId) return '${s.kennzeichen} Port ${e.key}';
    }
  }
  return null;
}
