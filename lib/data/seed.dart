/// Startbestand an Gewerken und Objekttypen für ein neues Projekt.
/// Farben als ARGB-Werte; in den Einstellungen änderbar.
class GewerkVorlage {
  const GewerkVorlage(this.kuerzel, this.name, this.farbe, this.linie, this.sichtbar, this.typen);
  final String kuerzel;
  final String name;
  final int farbe;
  final String linie;
  final bool sichtbar;
  final List<(String kuerzel, String name, String geometrie)> typen;
}

const gewerkVorlagen = <GewerkVorlage>[
  GewerkVorlage('EL', 'Elektro', 0xFFE6A700, 'dashed', true, [
    ('SD', 'Steckdose', 'punkt'),
    ('TA', 'Schalter / Taster', 'punkt'),
    ('LE', 'Leuchte / Leuchtenauslass', 'punkt'),
    ('DO', 'Geräte- / Abzweigdose', 'punkt'),
    ('FA', 'Festanschluss', 'punkt'),
    ('LT', 'Leitung', 'linie'),
    ('LR', 'Leerrohr', 'linie'),
    ('VT', 'Verteiler / Zählerschrank', 'punkt'),
    ('LB', 'LED-Streifen / Lichtband', 'linie'),
    ('SR', 'Steigleitung Elektro (über Geschosse)', 'punkt'),
  ]),
  GewerkVorlage('KX', 'KNX / Smart Home', 0xFF2F9E44, 'dashed', false, [
    ('KX', 'KNX-Gerät', 'punkt'),
    ('BL', 'Busleitung', 'linie'),
    ('PM', 'Präsenzmelder', 'punkt'),
    ('BM', 'Bewegungsmelder', 'punkt'),
    ('ES', 'Eigener Sensor', 'punkt'),
    ('SL', 'Signalleitung', 'linie'),
  ]),
  GewerkVorlage('NW', 'Netzwerk / Medien', 0xFF7048E8, 'dashed', false, [
    ('ND', 'Netzwerkdose', 'punkt'),
    ('NK', 'Netzwerkkabel', 'linie'),
    ('AP', 'Access Point / Kamera', 'punkt'),
  ]),
  GewerkVorlage('SA', 'Sanitär', 0xFF1C7ED6, 'solid', true, [
    ('KW', 'Kaltwasserleitung', 'linie'),
    ('WW', 'Warmwasserleitung', 'linie'),
    ('ZI', 'Zirkulation', 'linie'),
    ('AW', 'Abwasserleitung', 'linie'),
    ('EN', 'Entnahmestelle / Ablauf', 'punkt'),
    ('SR', 'Steigleitung / Fallrohr (über Geschosse)', 'punkt'),
  ]),
  GewerkVorlage('HZ', 'Heizungsanlage', 0xFFE03131, 'solid', true, [
    ('VL', 'Vorlauf', 'linie'),
    ('RL', 'Rücklauf', 'linie'),
    ('HZ', 'Anlagenbauteil', 'punkt'),
    ('SR', 'Steigleitung Heizung (über Geschosse)', 'punkt'),
  ]),
  GewerkVorlage('FH', 'Flächenheizung', 0xFFF08C00, 'solid', true, [
    ('HK', 'Heizkreis', 'flaeche'),
    ('HV', 'Heizkreisverteiler', 'punkt'),
    ('HR', 'Heizrohr / Anbindeleitung', 'linie'),
  ]),
  GewerkVorlage('LU', 'Lüftung', 0xFF0C8599, 'solid', false, [
    ('LK', 'Luftkanal', 'linie'),
    ('LV', 'Luftventil', 'punkt'),
    ('LG', 'Lüftungsgerät', 'punkt'),
  ]),
  GewerkVorlage('KL', 'Klima', 0xFF15AABF, 'solid', false, [
    ('KG', 'Klimagerät', 'punkt'),
    ('KL', 'Kältemittel- / Kondensatleitung', 'linie'),
  ]),
  GewerkVorlage('BS', 'Brandschutz', 0xFFC92A2A, 'solid', true, brandschutzTypen),
  GewerkVorlage('AL', 'Allgemein', 0xFF6B7178, 'solid', true, [
    ('MP', 'Messpunkt / Warnhinweis', 'punkt'),
    ('WD', 'Wanddurchbruch / Kernbohrung', 'punkt'),
    ('TR', 'Treppe (Lauflinie)', 'linie'),
    ('TP', 'Treppenpodest / Zwischenpodest', 'flaeche'),
    ('KM', 'Kamin / Schornstein', 'flaeche'),
  ]),
];

/// Objekttypen des Gewerks Brandschutz (Migration 18 ergänzt sie in alten Projekten).
const brandschutzTypen = <(String, String, String)>[
  ('RW', 'Rauchwarnmelder', 'punkt'),
  ('WR', 'Wärmemelder', 'punkt'),
  ('CM', 'CO-Melder / Gasmelder', 'punkt'),
  ('FL', 'Feuerlöscher / Löschdecke', 'punkt'),
  ('BA', 'Brandschutzabschottung (Durchführung)', 'punkt'),
  ('BK', 'Brandschutzklappe', 'punkt'),
  ('SI', 'Sicherheitsleuchte / Fluchtweg', 'punkt'),
  ('BW', 'Brandwand / Brandabschnitt', 'linie'),
];

/// Startbestand der Materialbibliothek (Name, Kategorie, Farbe, Einheit).
const materialVorlagen = <(String, String, int, String)>[
  ('Hochlochziegel', 'Mauerwerk', 0xFFD98B6E, 'm³'),
  ('Kalksandstein', 'Mauerwerk', 0xFFE4E0D2, 'm³'),
  ('Porenbeton', 'Mauerwerk', 0xFFEDEAE0, 'm³'),
  ('Vollziegel (Bestand)', 'Mauerwerk', 0xFFC4704F, 'm³'),
  ('Beton / Stahlbeton', 'Beton', 0xFFA9AEB3, 'm³'),
  ('Gipskarton', 'Trockenbau', 0xFFF1EEE6, 'm²'),
  ('Ständerwerk Metall', 'Trockenbau', 0xFFCED4DA, 'm²'),
  ('Holz / Holzständer', 'Holz', 0xFFC9A26B, 'm³'),
  ('Mineralwolle', 'Dämmung', 0xFFF2DC8C, 'm²'),
  ('EPS-Dämmplatte (WDVS)', 'Dämmung', 0xFFF4F1F8, 'm²'),
  ('XPS / Styrodur', 'Dämmung', 0xFFB9D8F0, 'm²'),
  ('Holzfaser-Dämmplatte', 'Dämmung', 0xFFB98E5A, 'm²'),
  ('Gipsputz', 'Putz', 0xFFF8F6F0, 'm²'),
  ('Kalkzementputz', 'Putz', 0xFFE9E4D8, 'm²'),
  ('Oberputz / Armierung (WDVS)', 'Putz', 0xFFE2DDD0, 'm²'),
  ('WDVS-Klebemörtel', 'Putz', 0xFFD6D0C2, 'm²'),
  ('Armierungsschicht mit Gewebe (WDVS)', 'Putz', 0xFFDCD6C8, 'm²'),
  ('Fliesen inkl. Kleber', 'Belag', 0xFFB7D3D0, 'm²'),
];

/// Startbestand an Wandtypen: Name und Schichten (Material, Dicke in mm),
/// von der ersten Wandseite zur zweiten.
const wandtypVorlagen = <(String, List<(String, int)>)>[
  ('Außenwand Ziegel 365, verputzt', [
    ('Gipsputz', 15),
    ('Hochlochziegel', 365),
    ('Kalkzementputz', 20),
  ]),
  ('Außenwand KS 175 + WDVS 160', [
    ('Gipsputz', 15),
    ('Kalksandstein', 175),
    ('WDVS-Klebemörtel', 5),
    ('EPS-Dämmplatte (WDVS)', 160),
    ('Oberputz / Armierung (WDVS)', 5),
  ]),
  ('Innenwand Ziegel 115, verputzt', [
    ('Gipsputz', 15),
    ('Hochlochziegel', 115),
    ('Gipsputz', 15),
  ]),
  ('Innenwand KS 240, verputzt', [
    ('Gipsputz', 15),
    ('Kalksandstein', 240),
    ('Gipsputz', 15),
  ]),
  ('Trockenbau CW 75, doppelt beplankt', [
    ('Gipskarton', 25),
    ('Mineralwolle', 75),
    ('Gipskarton', 25),
  ]),
];
