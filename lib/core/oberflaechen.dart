/// Oberflächen beschichten: je Raum und Fläche (Wände, Boden, Decke) ein
/// Schichtsystem, z. B. Tiefengrund + 2 × Dispersionsfarbe, Dichtschlämme im
/// Bad oder Fliesenkleber. Aus Fläche, Verbrauch je m² und Anzahl der Lagen
/// ergibt sich der Materialbedarf für die Besorgungsliste.
library;

enum Flaechenart {
  waende('Wände'),
  boden('Boden'),
  decke('Decke');

  const Flaechenart(this.label);
  final String label;
}

class Beschichtung {
  const Beschichtung({this.material, this.text = '', this.verbrauch = 0, this.lagen = 1, this.einheit = 'kg', this.anteil = 1});

  /// Bauelement-Id aus der Bibliothek (Baustoff, Dichtstoff …).
  final String? material;
  final String text;

  /// Verbrauch je m² und Lage in [einheit].
  final double verbrauch;
  final int lagen;
  final String einheit;

  /// Anteil der Fläche (z. B. 0,3 = nur Spritzwasserbereich im Bad).
  final double anteil;

  Map<String, dynamic> toJson() => {
        if (material != null) 'material': material,
        if (text.isNotEmpty) 'text': text,
        'verbrauch': verbrauch,
        'lagen': lagen,
        'einheit': einheit,
        if (anteil != 1) 'anteil': anteil,
      };

  static Beschichtung ausJson(Map<String, dynamic> m) => Beschichtung(
        material: m['material'] as String?,
        text: m['text'] as String? ?? '',
        verbrauch: (m['verbrauch'] as num?)?.toDouble() ?? 0,
        lagen: (m['lagen'] as num?)?.toInt() ?? 1,
        einheit: m['einheit'] as String? ?? 'kg',
        anteil: (m['anteil'] as num?)?.toDouble() ?? 1,
      );

  Beschichtung mit({String? material, String? text, double? verbrauch, int? lagen, String? einheit, double? anteil}) => Beschichtung(
        material: material ?? this.material,
        text: text ?? this.text,
        verbrauch: verbrauch ?? this.verbrauch,
        lagen: lagen ?? this.lagen,
        einheit: einheit ?? this.einheit,
        anteil: anteil ?? this.anteil,
      );

  /// Bedarf für [flaeche] m².
  double bedarf(double flaeche) => flaeche * anteil * verbrauch * lagen;
}

/// Schichten einer Fläche aus den Raumeigenschaften.
List<Beschichtung> beschichtungen(Map<String, dynamic> raumEig, Flaechenart a) => [
      for (final m in ((raumEig['oberflaechen'] as Map?)?[a.name] as List? ?? const []))
        Beschichtung.ausJson(Map<String, dynamic>.from(m as Map))
    ];

/// Raumeigenschaften mit neuen Schichten für eine Fläche.
Map<String, dynamic> beschichtungenSetzen(Map<String, dynamic> raumEig, Flaechenart a, List<Beschichtung> l) {
  final o = Map<String, dynamic>.from(raumEig['oberflaechen'] as Map? ?? const {});
  o[a.name] = [for (final b in l) b.toJson()];
  return {...raumEig, 'oberflaechen': o};
}

/// Flächen eines Raums in m²: Wände = Umfang × lichte Höhe − Öffnungen, Boden/Decke = Grundfläche.
double raumFlaeche(Flaechenart a, {required double grundflaecheMm2, required double umfangMm, required int lichteHoeheMm, double oeffnungenMm2 = 0}) =>
    switch (a) {
      Flaechenart.waende => ((umfangMm * lichteHoeheMm - oeffnungenMm2) / 1e6).clamp(0, double.infinity).toDouble(),
      _ => grundflaecheMm2 / 1e6,
    };

/// Vorlagen für übliche Schichtsysteme (Verbrauch je m² und Lage, Herstellerangaben prüfen).
const beschichtungsVorlagen = <String, List<Beschichtung>>{
  'Anstrich (Grund + 2 × Farbe)': [
    Beschichtung(text: 'Tiefengrund', verbrauch: 0.1, einheit: 'l'),
    Beschichtung(text: 'Dispersionsfarbe', verbrauch: 0.15, lagen: 2, einheit: 'l'),
  ],
  'Dichtschlämme Bad (2 Lagen)': [
    Beschichtung(text: 'Grundierung', verbrauch: 0.15, einheit: 'l'),
    Beschichtung(text: 'Flexible Dichtschlämme', verbrauch: 1.5, lagen: 2, einheit: 'kg'),
    Beschichtung(text: 'Dichtband Ecken/Fugen', verbrauch: 0, einheit: 'm'),
  ],
  'Fliesen (Kleber + Fuge)': [
    Beschichtung(text: 'Fliesenkleber', verbrauch: 3.0, einheit: 'kg'),
    Beschichtung(text: 'Fugenmörtel', verbrauch: 0.4, einheit: 'kg'),
  ],
  'WDVS (Kleben + Armieren)': [
    Beschichtung(text: 'Klebe- und Armierungsmörtel (Kleben)', verbrauch: 5.0, einheit: 'kg'),
    Beschichtung(text: 'Klebe- und Armierungsmörtel (Armierung)', verbrauch: 4.5, einheit: 'kg'),
    Beschichtung(text: 'Armierungsgewebe', verbrauch: 1.1, einheit: 'm²'),
  ],
  'Putz innen (Kalkgips 10 mm)': [
    Beschichtung(text: 'Haftgrund', verbrauch: 0.2, einheit: 'kg'),
    Beschichtung(text: 'Kalkgipsputz 10 mm', verbrauch: 10, einheit: 'kg'),
  ],
};
