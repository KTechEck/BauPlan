import 'verteiler.dart';

/// Anschlusspunkt eines Objekts in der Wandansicht: Name sowie Lage relativ
/// zum Objektpunkt – [dx] entlang der Wand (nach rechts, vom Raum aus gesehen)
/// und [dz] in der Höhe (nach oben), beides in mm.
typedef Anschluss = ({String name, double dx, double dz});

/// Anschlüsse je Objekttyp. Der Heizkreisverteiler richtet sich nach seiner
/// Konfiguration (Abgänge, Anschlussseite); der Objektpunkt ist dort die
/// Mitte der Schrankunterkante.
List<Anschluss> anschluesse(String kuerzel, Map<String, dynamic> eigenschaften) {
  switch (kuerzel) {
    case 'ES': // eigener Sensor: Anschlüsse aus der Vorlage (beim Zuweisen kopiert)
      final l = eigenschaften['anschluesse'];
      if (l is! List || l.isEmpty) return const [];
      return [
        for (var i = 0; i < l.length; i++) (name: '${(l[i] as Map)['name']}', dx: (i - (l.length - 1) / 2) * 15.0, dz: -40.0),
      ];
    case 'HV':
      final d = VerteilerDaten.ausJson(eigenschaften);
      return verteilerAnschluesse(d);
    case 'HZ': // Anlagenbauteil (Kessel, Wärmepumpe, Speicher …)
      return const [(name: 'VL', dx: -60, dz: 0), (name: 'RL', dx: 60, dz: 0)];
    case 'EN': // Entnahmestelle / Ablauf
      return const [(name: 'KW', dx: -50, dz: 0), (name: 'WW', dx: 50, dz: 0), (name: 'AW', dx: 0, dz: -300)];
    case 'LG': // Lüftungsgerät
      return const [
        (name: 'ZUL', dx: -150, dz: 0),
        (name: 'ABL', dx: -50, dz: 0),
        (name: 'FOL', dx: 50, dz: 0),
        (name: 'AUL', dx: 150, dz: 0),
      ];
    case 'KG': // Klimagerät
      return const [(name: 'Flüssig', dx: -30, dz: 0), (name: 'Saug', dx: 30, dz: 0), (name: 'Kondensat', dx: 80, dz: 0)];
    default:
      return const [];
  }
}

/// Abstand der Abgänge am Verteilerbalken (mm).
const verteilerTeilung = 50.0;

/// Anschlüsse des Heizkreisverteilers: je Abgang Vor- und Rücklauf an der
/// Schrankunterkante, dazu die Zuleitung (VL/RL) auf der Anschlussseite.
List<Anschluss> verteilerAnschluesse(VerteilerDaten d) {
  final b = d.schrankBreite.toDouble();
  final s = d.anschlussLinks ? 1.0 : -1.0;
  // Platz für Zuleitung, Kugelhähne und ggf. Mischer/Pumpe auf der Anschlussseite
  final rand = 120.0 + (d.mischer || d.pumpe ? 200.0 : 0.0);
  final start = -s * b / 2 + s * rand;
  return [
    (name: 'Zuleitung VL', dx: -s * b / 2 + s * 40, dz: 420),
    (name: 'Zuleitung RL', dx: -s * b / 2 + s * 40, dz: 300),
    for (var i = 0; i < d.abgaenge; i++) ...[
      (name: '${i + 1} VL', dx: start + s * i * verteilerTeilung, dz: 0),
      (name: '${i + 1} RL', dx: start + s * (i * verteilerTeilung + verteilerTeilung / 2), dz: 0),
    ],
  ];
}
