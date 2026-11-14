import 'dart:convert';

/// Bauelemente-Bibliothek: konkrete Produkte (Fenster, Türen, Rollläden,
/// Steckdosen, Schaltschrankgeräte, Technikgeräte …) mit technischen Daten.
/// Die Bibliothek gilt für alle Projekte dieses PCs; was in einem Projekt
/// verwendet wird, wird dort als Kopie abgelegt, damit das Projekt vollständig bleibt.

enum FeldTyp { zahl, text, auswahl, jaNein }

class FeldDef {
  const FeldDef(this.schluessel, this.label, {this.typ = FeldTyp.zahl, this.einheit = '', this.optionen = const [], this.hilfe = ''});
  final String schluessel;
  final String label;
  final FeldTyp typ;
  final String einheit;
  final List<String> optionen;
  final String hilfe;
}

/// Gruppe für die Auswahl (Dropdown mit Überschriften).
enum BauelementGruppe {
  gebaeudehuelle('Gebäudehülle'),
  elektro('Elektro'),
  schaltschrank('Schaltschrank'),
  brandschutz('Brandschutz'),
  haustechnik('Haustechnik'),
  material('Material'),
  werkzeug('Werkzeug'),
  sonstiges('Sonstiges');

  const BauelementGruppe(this.label);
  final String label;
}

enum BauelementKategorie {
  fenster('Fenster', BauelementGruppe.gebaeudehuelle, _fenster),
  balkontuer('Balkontür / Fenstertür', BauelementGruppe.gebaeudehuelle, _fenster),
  tuer('Tür', BauelementGruppe.gebaeudehuelle, _tuer),
  sonnenschutz('Rollladen / Jalousie / Raffstore', BauelementGruppe.gebaeudehuelle, _sonnenschutz),
  fensterbank('Fensterbank', BauelementGruppe.gebaeudehuelle, _fensterbank),
  elektro('Schalter / Steckdose / Elektro', BauelementGruppe.elektro, _elektro),
  leuchte('Leuchte', BauelementGruppe.elektro, _leuchte),
  sensor('Sensor / Melder', BauelementGruppe.elektro, _sensorFelder),
  brandschutz('Rauchmelder / Brandschutz', BauelementGruppe.brandschutz, _brandschutz),
  schrankgeraet('Schaltschrankgerät', BauelementGruppe.schaltschrank, _schrankgeraet),
  technik('Technikgerät (Heizung, Speicher, Lüftung …)', BauelementGruppe.haustechnik, _technik),
  heizkoerper('Heizkörper / Heizfläche', BauelementGruppe.haustechnik, _heizkoerper),
  sanitaer('Sanitärobjekt', BauelementGruppe.haustechnik, _sanitaer),
  verbinder('Verbindungselement (Fitting, Verschraubung, Halter)', BauelementGruppe.haustechnik, _verbinder),
  armatur('Armatur / Ventil', BauelementGruppe.haustechnik, _armatur),
  daemmstoff('Dämmstoff', BauelementGruppe.material, _daemmstoff),
  verkleidung('Wandverkleidung / Vorsatzschale', BauelementGruppe.material, _verkleidung),
  baustoff('Baustoff (Mauerwerk, Putz, Platten …)', BauelementGruppe.material, _baustoff),
  dichtstoff('Dichtung / Fuge (Kompriband, Schaum, Folie)', BauelementGruppe.material, _dichtstoff),
  kabel('Kabel / Leitung', BauelementGruppe.material, _kabel),
  rohr('Rohr / Leerrohr', BauelementGruppe.material, _rohr),
  dose('Dose (Unterputz, Hohlwand …)', BauelementGruppe.material, _dose),
  kleinmaterial('Kleinmaterial / Befestigung', BauelementGruppe.material, _kleinmaterial),
  werkzeug('Werkzeug', BauelementGruppe.werkzeug, _werkzeug),
  sonstiges('Sonstiges Bauteil', BauelementGruppe.sonstiges, _sonstiges);

  const BauelementKategorie(this.label, this.gruppe, this.felder);
  final String label;
  final BauelementGruppe gruppe;
  final List<FeldDef> felder;
}

const _masse = [
  FeldDef('breite', 'Breite', einheit: 'mm'),
  FeldDef('hoehe', 'Höhe', einheit: 'mm'),
  FeldDef('tiefe', 'Tiefe', einheit: 'mm'),
  FeldDef('gewicht', 'Gewicht', einheit: 'kg'),
];

const _fenster = [
  FeldDef('rahmenmaterial', 'Rahmenmaterial', typ: FeldTyp.auswahl, optionen: ['Kunststoff', 'Holz', 'Holz-Alu', 'Aluminium', 'Kunststoff-Alu', 'Stahl']),
  FeldDef('profil', 'Profilsystem', typ: FeldTyp.text, hilfe: 'z. B. Schüco LivIng 82 MD'),
  FeldDef('bautiefe', 'Bautiefe Rahmen', einheit: 'mm'),
  FeldDef('ansichtsbreite', 'Ansichtsbreite Rahmen', einheit: 'mm', hilfe: 'Rahmen + Flügel, sichtbare Breite'),
  FeldDef('fluegelart', 'Öffnungsart', typ: FeldTyp.auswahl, optionen: ['Dreh-Kipp', 'Dreh', 'Kipp', 'Festverglasung', 'Hebe-Schiebe', 'Parallel-Schiebe-Kipp', 'Schwing', 'Klapp']),
  FeldDef('verglasung', 'Verglasung', typ: FeldTyp.auswahl, optionen: ['2-fach', '3-fach', '4-fach', 'Vakuum']),
  FeldDef('glasaufbau', 'Glasaufbau', typ: FeldTyp.text, hilfe: 'z. B. 4/16/4/16/4 Ar'),
  FeldDef('glasdicke', 'Glasdicke gesamt', einheit: 'mm'),
  FeldDef('uw', 'Uw', einheit: 'W/(m²K)', hilfe: 'Fenster gesamt (Normgröße)'),
  FeldDef('ug', 'Ug', einheit: 'W/(m²K)', hilfe: 'Verglasung'),
  FeldDef('uf', 'Uf', einheit: 'W/(m²K)', hilfe: 'Rahmen'),
  FeldDef('psi_g', 'Ψg Randverbund', einheit: 'W/(mK)'),
  FeldDef('g_wert', 'g-Wert', einheit: '', hilfe: 'Gesamtenergiedurchlass 0 … 1'),
  FeldDef('lt', 'Lichttransmission τv', einheit: ''),
  FeldDef('rw', 'Schalldämmung Rw', einheit: 'dB'),
  FeldDef('rc', 'Einbruchschutz', typ: FeldTyp.auswahl, optionen: ['keiner', 'RC1N', 'RC2N', 'RC2', 'RC3']),
  FeldDef('luftdicht', 'Luftdurchlässigkeit Klasse', typ: FeldTyp.auswahl, optionen: ['1', '2', '3', '4']),
  FeldDef('schlagregen', 'Schlagregendichtheit', typ: FeldTyp.text, hilfe: 'z. B. 9A'),
  FeldDef('glas_anteil', 'Glasanteil', einheit: '%'),
  ..._masse,
];

const _tuer = [
  FeldDef('tuerart', 'Art', typ: FeldTyp.auswahl, optionen: ['Haustür', 'Nebeneingangstür', 'Innentür', 'Schiebetür', 'Wohnungseingangstür', 'Brandschutztür', 'Kellertür']),
  FeldDef('rahmenmaterial', 'Material', typ: FeldTyp.auswahl, optionen: ['Holz', 'Kunststoff', 'Aluminium', 'Stahl', 'Glas', 'Holzwerkstoff']),
  FeldDef('blattdicke', 'Blattdicke', einheit: 'mm'),
  FeldDef('bautiefe', 'Bautiefe Rahmen / Zarge', einheit: 'mm'),
  FeldDef('zarge', 'Zarge', typ: FeldTyp.auswahl, optionen: ['Umfassungszarge', 'Blockzarge', 'Stahlzarge', 'Blockrahmen', 'ohne']),
  FeldDef('ud', 'Ud', einheit: 'W/(m²K)'),
  FeldDef('rw', 'Schalldämmung Rw', einheit: 'dB'),
  FeldDef('klimaklasse', 'Klimaklasse', typ: FeldTyp.auswahl, optionen: ['I', 'II', 'III']),
  FeldDef('brandschutz', 'Brandschutz', typ: FeldTyp.auswahl, optionen: ['keiner', 'T30', 'T60', 'T90', 'RS']),
  FeldDef('rc', 'Einbruchschutz', typ: FeldTyp.auswahl, optionen: ['keiner', 'RC2', 'RC3', 'RC4']),
  FeldDef('bandseite', 'Bänder', typ: FeldTyp.text, hilfe: 'z. B. 3D-Bänder, verdeckt'),
  ..._masse,
];

const _sonnenschutz = [
  FeldDef('system', 'System', typ: FeldTyp.auswahl, optionen: [
    'Vorbaurollladen',
    'Aufsatzrollladen',
    'Einbaurollladen (Sturzkasten)',
    'Raffstore / Außenjalousie',
    'Textilscreen / Senkrechtmarkise',
    'Innenjalousie',
    'Plissee / Rollo innen',
    'Klappladen',
    'Markise',
    'Insektenschutz',
  ]),
  FeldDef('antrieb', 'Antrieb', typ: FeldTyp.auswahl, optionen: ['Gurt', 'Kurbel', 'Motor 230 V', 'Motor Funk', 'Motor KNX', 'Motor SMI', 'Motor Solar', 'Kette']),
  FeldDef('leistung', 'Motorleistung', einheit: 'W'),
  FeldDef('drehmoment', 'Drehmoment', einheit: 'Nm'),
  FeldDef('kastenhoehe', 'Kastenhöhe', einheit: 'mm'),
  FeldDef('kastentiefe', 'Kastentiefe', einheit: 'mm'),
  FeldDef('fuehrung_breite', 'Führungsschiene Breite', einheit: 'mm'),
  FeldDef('fuehrung_tiefe', 'Führungsschiene Tiefe', einheit: 'mm'),
  FeldDef('fliegengitter_tiefe', 'Kammer Fliegengitter', einheit: 'mm',
      hilfe: 'aufgeweitete Schiene: zweite Kammer hinter dem Panzer für das Fliegengitter (0 = keine)'),
  FeldDef('behang', 'Behang / Panzer', typ: FeldTyp.text, hilfe: 'z. B. Alu 37 mm ausgeschäumt, Lamelle 80 mm'),
  FeldDef('usb', 'Usb Kasten', einheit: 'W/(m²K)'),
  FeldDef('psi_kasten', 'Ψ Kastenanschluss', einheit: 'W/(mK)'),
  FeldDef('fc', 'Abminderungsfaktor Fc', einheit: ''),
  FeldDef('max_breite', 'max. Breite', einheit: 'mm'),
  FeldDef('max_hoehe', 'max. Höhe', einheit: 'mm'),
  FeldDef('windklasse', 'Windwiderstandsklasse', typ: FeldTyp.text),
];

const _fensterbank = [
  FeldDef('lage', 'Lage', typ: FeldTyp.auswahl, optionen: ['außen', 'innen']),
  FeldDef('material', 'Material', typ: FeldTyp.auswahl, optionen: ['Aluminium', 'Naturstein', 'Kunststein', 'Holz', 'Werzalit', 'Fliese']),
  FeldDef('ausladung', 'Ausladung', einheit: 'mm'),
  FeldDef('dicke', 'Dicke', einheit: 'mm'),
  FeldDef('ueberstand', 'Überstand vor Fassade', einheit: 'mm'),
];

const _elektro = [
  FeldDef('typ', 'Typ', typ: FeldTyp.auswahl, optionen: [
    'Steckdose',
    'Steckdose mit USB',
    'Steckdose mit Klappdeckel',
    'Herdanschlussdose',
    'Schalter',
    'Taster',
    'KNX-Taster',
    'Dimmer',
    'Netzwerkdose',
    'Antennendose',
    'Raumthermostat',
    'Abzweigdose',
    'Sonstiges',
  ]),
  FeldDef('serie', 'Schalterprogramm', typ: FeldTyp.text, hilfe: 'z. B. Gira E2, Busch-Jaeger future linear'),
  FeldDef('farbe', 'Farbe', typ: FeldTyp.text),
  FeldDef('fach', 'Fach', einheit: 'fach'),
  FeldDef('montage', 'Montage', typ: FeldTyp.auswahl, optionen: ['Unterputz', 'Aufputz', 'Hohlwand', 'Bodentank', 'Kanal']),
  FeldDef('dosentiefe', 'Dosentiefe', einheit: 'mm'),
  FeldDef('ip', 'Schutzart', typ: FeldTyp.text, hilfe: 'z. B. IP20, IP44'),
  FeldDef('nennstrom', 'Nennstrom', einheit: 'A'),
  FeldDef('leistung', 'Leistung / Last', einheit: 'W'),
  FeldDef('rahmen_breite', 'Rahmen außen', einheit: 'mm', hilfe: 'Abdeckrahmen 1-fach, z. B. 80'),
  FeldDef('knx', 'KNX-Tasterschnittstelle / Busankoppler', typ: FeldTyp.jaNein),
  ..._masse,
];

const _leuchte = [
  FeldDef('leuchtenart', 'Art', typ: FeldTyp.auswahl, optionen: ['Einbaustrahler', 'Aufbauleuchte', 'Pendelleuchte', 'LED-Streifen', 'Wandleuchte', 'Außenleuchte', 'Panel']),
  FeldDef('leistung', 'Leistung', einheit: 'W'),
  FeldDef('lichtstrom', 'Lichtstrom', einheit: 'lm'),
  FeldDef('farbtemperatur', 'Farbtemperatur', einheit: 'K'),
  FeldDef('cri', 'Farbwiedergabe Ra', einheit: ''),
  FeldDef('abstrahlwinkel', 'Abstrahlwinkel', einheit: '°'),
  FeldDef('dimmbar', 'Dimmung', typ: FeldTyp.auswahl, optionen: ['nicht dimmbar', 'Phasenabschnitt', 'Phasenanschnitt', 'DALI', '1-10 V', 'PWM', 'Casambi / Funk']),
  FeldDef('einbaudurchmesser', 'Einbaudurchmesser', einheit: 'mm'),
  FeldDef('einbautiefe', 'Einbautiefe', einheit: 'mm'),
  FeldDef('ip', 'Schutzart', typ: FeldTyp.text),
  ..._masse,
];

const _sensorFelder = [
  FeldDef('sensorart', 'Art', typ: FeldTyp.auswahl, optionen: ['Präsenzmelder', 'Bewegungsmelder', 'Rauchmelder', 'Temperatur / Feuchte', 'CO2', 'Fensterkontakt', 'Wassermelder', 'Wetterstation']),
  FeldDef('bus', 'Anbindung', typ: FeldTyp.auswahl, optionen: ['KNX', '230 V', 'Funk', 'Zigbee', 'Matter / Thread', 'WLAN', 'Batterie']),
  FeldDef('erfassung', 'Erfassungsdurchmesser', einheit: 'm'),
  FeldDef('montagehoehe', 'Montagehöhe max.', einheit: 'mm'),
  FeldDef('einbautiefe', 'Einbautiefe', einheit: 'mm'),
  FeldDef('ip', 'Schutzart', typ: FeldTyp.text),
  FeldDef('versorgung', 'Versorgung', typ: FeldTyp.auswahl, optionen: ['Bus', '230 V', '24 V', 'Batterie', '10-Jahres-Batterie', 'PoE']),
  FeldDef('leistung', 'Leistungsaufnahme', einheit: 'W'),
  ..._masse,
];

const _brandschutz = [
  FeldDef('bs_art', 'Art', typ: FeldTyp.auswahl, optionen: [
    'Rauchwarnmelder',
    'Wärmemelder',
    'Kohlenmonoxid-Melder (CO)',
    'Kombimelder Rauch/Wärme',
    'Gasmelder',
    'Feuerlöscher',
    'Löschdecke',
    'Brandschutzabschottung (Rohr/Kabel)',
    'Brandschutzklappe',
    'Brandschutzmanschette',
    'Sicherheitsleuchte / Fluchtweg',
    'Feuerschutzabschluss (Tür/Klappe)',
  ]),
  FeldDef('norm', 'Norm / Zulassung', typ: FeldTyp.text, hilfe: 'z. B. DIN EN 14604, Q-Label, abZ Z-19.53-…'),
  FeldDef('vernetzung', 'Vernetzung', typ: FeldTyp.auswahl, optionen: ['keine', 'Funk', 'Draht', 'KNX', 'Zigbee', 'Matter / Thread']),
  FeldDef('versorgung', 'Versorgung', typ: FeldTyp.auswahl, optionen: ['10-Jahres-Batterie', 'Batterie wechselbar', '230 V mit Akku', 'Bus']),
  FeldDef('lebensdauer', 'Lebensdauer / Austausch', einheit: 'Jahre'),
  FeldDef('wartung', 'Wartungsintervall', einheit: 'Monate', hilfe: 'Rauchmelder: 12 (DIN 14676)'),
  FeldDef('montageort', 'Montage', typ: FeldTyp.auswahl, optionen: ['Decke Raummitte', 'Decke', 'Wand', 'Boden', 'in Wand/Decke (Durchführung)']),
  FeldDef('abstand_wand', 'Mindestabstand Wand/Unterzug', einheit: 'mm', hilfe: 'Rauchmelder: 500'),
  FeldDef('ueberwachung', 'Überwachungsfläche max.', einheit: 'm²', hilfe: 'Rauchmelder: 60 m²'),
  FeldDef('feuerwiderstand', 'Feuerwiderstand', typ: FeldTyp.auswahl, optionen: ['–', 'EI 30', 'EI 60', 'EI 90', 'EI 120', 'F30', 'F60', 'F90', 'K30', 'K90', 'T30', 'T90']),
  FeldDef('loeschmittel', 'Löschmittel', typ: FeldTyp.auswahl, optionen: ['–', 'Schaum', 'Pulver ABC', 'Wasser', 'CO2', 'Fettbrand (F)']),
  FeldDef('loescheinheiten', 'Löschmitteleinheiten', einheit: 'LE'),
  FeldDef('max_belegung', 'max. Belegung / Durchmesser', typ: FeldTyp.text, hilfe: 'z. B. Rohr bis DN 110, Kabelbündel bis 100 mm'),
  FeldDef('lautstaerke', 'Alarmlautstärke', einheit: 'dB'),
  ..._masse,
];

const _schrankgeraet = [
  FeldDef('geraeteart', 'Geräteart', typ: FeldTyp.auswahl, optionen: [
    'hauptschalter',
    'rcd',
    'ls',
    'fils',
    'spd',
    'knx',
    'netzteil',
    'relais',
    'klemme',
    'sonstiges',
  ], hilfe: 'bestimmt Symbol und Kennbuchstaben im Schrank'),
  FeldDef('te', 'Breite', einheit: 'TE'),
  FeldDef('pole', 'Pole', einheit: ''),
  FeldDef('nennstrom', 'Nennstrom', einheit: 'A'),
  FeldDef('charakteristik', 'Auslösecharakteristik', typ: FeldTyp.auswahl, optionen: ['B', 'C', 'D', 'K', 'Z']),
  FeldDef('fehlerstrom', 'Bemessungsfehlerstrom', einheit: 'mA'),
  FeldDef('rcd_typ', 'RCD-Typ', typ: FeldTyp.auswahl, optionen: ['AC', 'A', 'F', 'B', 'B+', 'EV']),
  FeldDef('schaltvermoegen', 'Schaltvermögen', einheit: 'kA'),
  FeldDef('spd_typ', 'SPD-Typ', typ: FeldTyp.auswahl, optionen: ['Typ 1', 'Typ 2', 'Typ 1+2', 'Typ 3']),
  FeldDef('kanaele', 'Kanäle (KNX)', einheit: ''),
  FeldDef('aktortyp', 'Aktortyp (KNX)', typ: FeldTyp.auswahl, optionen: ['Schalt', 'Dimm', 'Jalousie', 'Heizung', 'Binäreingang', 'Spannungsversorgung', 'Linienkoppler', 'IP-Schnittstelle', 'Logik']),
  FeldDef('strom_kanal', 'Strom je Kanal', einheit: 'A'),
  FeldDef('busstrom', 'Busstrom', einheit: 'mA'),
  FeldDef('verlust', 'Verlustleistung', einheit: 'W'),
  FeldDef('hilfskontakt', 'Hilfskontakt', typ: FeldTyp.jaNein),
];

const _technik = [
  FeldDef('technikart', 'Art', typ: FeldTyp.auswahl, optionen: [
    'Wärmepumpe Innengerät',
    'Wärmepumpe Außengerät',
    'Gas-Brennwert',
    'Pelletkessel',
    'Pufferspeicher',
    'Trinkwasserspeicher',
    'Frischwasserstation',
    'Lüftungsgerät',
    'Wechselrichter',
    'Batteriespeicher',
    'Hausanschluss',
    'Wasserenthärter',
    'Hebeanlage',
    'Server / Rack',
    'Sonstiges',
  ]),
  ..._masse,
  FeldDef('freiraum_vorne', 'Freiraum vorne', einheit: 'mm'),
  FeldDef('freiraum_seite', 'Freiraum seitlich', einheit: 'mm'),
  FeldDef('freiraum_oben', 'Freiraum oben', einheit: 'mm'),
  FeldDef('leistung_kw', 'Nennleistung', einheit: 'kW'),
  FeldDef('elektrisch_kw', 'elektr. Anschlussleistung', einheit: 'kW'),
  FeldDef('anschluss', 'Elektroanschluss', typ: FeldTyp.auswahl, optionen: ['230 V', '400 V', '230 V + 400 V', 'keiner']),
  FeldDef('absicherung', 'Absicherung', einheit: 'A'),
  FeldDef('volumen', 'Volumen', einheit: 'l'),
  FeldDef('anschluss_heizung', 'Heizungsanschluss', typ: FeldTyp.text, hilfe: 'z. B. DN25 VL/RL'),
  FeldDef('anschluss_wasser', 'Wasseranschluss', typ: FeldTyp.text),
  FeldDef('luftmenge', 'Luftmenge', einheit: 'm³/h'),
  FeldDef('schall', 'Schallleistung', einheit: 'dB(A)'),
  FeldDef('scop', 'SCOP / Jahresarbeitszahl', einheit: ''),
];

const _heizkoerper = [
  FeldDef('hk_art', 'Art', typ: FeldTyp.auswahl, optionen: ['Kompaktheizkörper', 'Planheizkörper', 'Badheizkörper', 'Konvektor', 'Unterflurkonvektor', 'Röhrenradiator', 'Gliederheizkörper']),
  FeldDef('hk_typ', 'Typ', typ: FeldTyp.text, hilfe: 'z. B. 22, 33'),
  FeldDef('bauhoehe', 'Bauhöhe', einheit: 'mm'),
  FeldDef('baulaenge', 'Baulänge', einheit: 'mm'),
  FeldDef('bautiefe', 'Bautiefe', einheit: 'mm'),
  FeldDef('q_norm', 'Normwärmeleistung 75/65/20', einheit: 'W'),
  FeldDef('exponent', 'Heizkörperexponent n', einheit: '', hilfe: 'meist 1,3'),
  FeldDef('anschluss', 'Anschluss', typ: FeldTyp.auswahl, optionen: ['Ventil (unten Mitte)', 'seitlich', 'unten rechts', 'unten links']),
  FeldDef('wasserinhalt', 'Wasserinhalt', einheit: 'l'),
];

const _sanitaer = [
  FeldDef('san_art', 'Art', typ: FeldTyp.auswahl, optionen: ['WC wandhängend', 'WC stehend', 'Waschtisch', 'Dusche bodengleich', 'Duschwanne', 'Badewanne', 'Urinal', 'Spüle', 'Ausgussbecken', 'Waschmaschinenanschluss']),
  ..._masse,
  FeldDef('anschluss_hoehe', 'Anschlusshöhe', einheit: 'mm'),
  FeldDef('abfluss_dn', 'Abfluss DN', einheit: ''),
  FeldDef('vorwand', 'Vorwandelement', typ: FeldTyp.text),
];

const _verbinder = [
  FeldDef('verbinderart', 'Art', typ: FeldTyp.auswahl, optionen: [
    'Winkel 90°',
    'Winkel 45°',
    'Bogen',
    'T-Stück',
    'T-Stück reduziert',
    'Muffe / Kupplung',
    'Reduzierung',
    'Übergang Innengewinde',
    'Übergang Außengewinde',
    'Verschraubung (flachdichtend)',
    'Verschraubung (konisch)',
    'Klemmringverschraubung',
    'Wandscheibe',
    'Endkappe / Stopfen',
    'Kreuzstück',
    'Rohrschelle',
    'Rohrhalter / Abstandsschelle',
    'Montageschiene',
    'Konsole / Winkel',
    'Verteilerbalken',
  ]),
  FeldDef('system', 'Verbindungstechnik', typ: FeldTyp.auswahl, optionen: ['Pressen', 'Stecken', 'Schrauben (Gewinde)', 'Klemmen', 'Löten', 'Schweißen', 'Kleben', 'Steckmuffe (HT/KG)']),
  FeldDef('material', 'Material', typ: FeldTyp.auswahl, optionen: ['Messing', 'Rotguss', 'Edelstahl', 'Kupfer', 'Stahl verzinkt', 'PPSU', 'PVDF', 'PP', 'PVC', 'Temperguss']),
  FeldDef('dimension', 'Dimension', typ: FeldTyp.text, hilfe: 'z. B. 16×2, 20×2, DN20, 1/2", 3/4"'),
  FeldDef('dimension2', 'Abgang / zweite Dimension', typ: FeldTyp.text, hilfe: 'bei Reduzierung, T-Stück, Übergang'),
  FeldDef('gewinde', 'Gewinde', typ: FeldTyp.auswahl, optionen: ['kein', 'Innengewinde', 'Außengewinde', 'Überwurfmutter', 'Eurokonus']),
  FeldDef('pn', 'Druckstufe PN', einheit: 'bar'),
  FeldDef('temperatur', 'max. Temperatur', einheit: '°C'),
  FeldDef('medium', 'Medium', typ: FeldTyp.auswahl, optionen: ['Trinkwasser', 'Heizwasser', 'Abwasser', 'Gas', 'Druckluft', 'Kältemittel']),
  FeldDef('daemmung', 'mit Dämmung / Schallschutzeinlage', typ: FeldTyp.jaNein),
  ..._lager,
];

const _armatur = [
  FeldDef('armaturart', 'Art', typ: FeldTyp.auswahl, optionen: [
    'Kugelhahn',
    'Absperrventil',
    'Eckventil',
    'Rückflussverhinderer',
    'Sicherheitsventil',
    'Druckminderer',
    'Schmutzfänger / Filter',
    'Thermostatventil',
    'Rücklaufverschraubung',
    'Strangregulierventil',
    'Entlüfter',
    'KFE-Hahn',
    'Mischventil / Verbrühschutz',
    'Wasserzähler',
  ]),
  FeldDef('dimension', 'Dimension', typ: FeldTyp.text, hilfe: 'z. B. DN15, 1/2", 16×2'),
  FeldDef('material', 'Material', typ: FeldTyp.auswahl, optionen: ['Messing', 'Rotguss', 'Edelstahl', 'Kunststoff']),
  FeldDef('kvs', 'kvs-Wert', einheit: 'm³/h', hilfe: 'für den hydraulischen Abgleich'),
  FeldDef('voreinstellung', 'Voreinstellung', typ: FeldTyp.text),
  FeldDef('pn', 'Druckstufe PN', einheit: 'bar'),
  FeldDef('medium', 'Medium', typ: FeldTyp.auswahl, optionen: ['Trinkwasser', 'Heizwasser', 'Gas']),
  ..._lager,
];

const _lager = [
  FeldDef('einheit', 'Einheit', typ: FeldTyp.auswahl, optionen: ['Stk', 'm', 'm²', 'm³', 'Platte', 'Rolle', 'Packung', 'Sack', 'Eimer', 'Kartusche', 'kg', 'l']),
  FeldDef('gebinde', 'Gebinde / Packungsinhalt', typ: FeldTyp.text, hilfe: 'z. B. 10 Platten à 1,25 × 0,6 m, Ring 100 m'),
];

const _verkleidung = [
  FeldDef('dicke', 'Dicke gesamt (je Wandseite)', einheit: 'mm', hilfe: 'zählt beim Fertigmaß'),
  FeldDef('unterkonstruktion', 'Unterkonstruktion', typ: FeldTyp.auswahl, optionen: ['keine (direkt)', 'CW-Profil 50', 'CW-Profil 75', 'CW-Profil 100', 'Holzlattung', 'Direktabhänger', 'Ansetzbinder (Batzen)']),
  FeldDef('uk_dicke', 'Dicke Unterkonstruktion', einheit: 'mm'),
  FeldDef('beplankung', 'Beplankung', typ: FeldTyp.auswahl, optionen: ['GK 12,5', 'GKB 2 × 12,5', 'GKF (Feuerschutz)', 'GKI (imprägniert)', 'Gipsfaser', 'OSB', 'Zementplatte', 'Putz', 'Fliese auf Putz']),
  FeldDef('lagen', 'Lagen Beplankung', einheit: 'Lagen'),
  FeldDef('daemmung', 'Dämmung im Hohlraum', typ: FeldTyp.text, hilfe: 'z. B. Mineralwolle 40 mm'),
  FeldDef('oberflaeche', 'Oberfläche', typ: FeldTyp.text, hilfe: 'z. B. Q2 gespachtelt, Fliesen'),
];

const _daemmstoff = [
  FeldDef('daemmart', 'Art', typ: FeldTyp.auswahl, optionen: [
    'XPS (Styrodur)',
    'EPS (Styropor)',
    'PUR/PIR',
    'Mineralwolle',
    'Steinwolle',
    'Holzfaser',
    'Zellulose',
    'Kalziumsilikat',
    'Aerogel',
    'Perlite',
    'Schaumglas',
    'Kork',
    'Systemplatte FBH (Noppe/Tacker)',
    'Randdämmstreifen (PE)',
    'Trittschalldämmung',
  ]),
  FeldDef('lambda', 'Wärmeleitfähigkeit λ', einheit: 'W/(mK)', hilfe: 'Bemessungswert laut Datenblatt, z. B. 0,035'),
  FeldDef('dicke', 'Dicke', einheit: 'mm'),
  FeldDef('rho', 'Rohdichte', einheit: 'kg/m³'),
  FeldDef('mu', 'Diffusionswiderstand μ', einheit: ''),
  FeldDef('brandklasse', 'Brandklasse', typ: FeldTyp.auswahl, optionen: ['A1', 'A2', 'B1', 'B2', 'E', 'B-s1,d0', 'B-s2,d0']),
  FeldDef('druckfestigkeit', 'Druckfestigkeit', einheit: 'kPa'),
  FeldDef('kante', 'Kante', typ: FeldTyp.auswahl, optionen: ['stumpf', 'Stufenfalz', 'Nut und Feder']),
  FeldDef('format', 'Plattenformat', typ: FeldTyp.text, hilfe: 'z. B. 1250 × 600 mm'),
  ..._lager,
];

const _baustoff = [
  FeldDef('stoffart', 'Art', typ: FeldTyp.auswahl, optionen: [
    'Mauerstein',
    'Beton/Estrich',
    'Putz',
    'Mörtel/Kleber',
    'Gipskarton/Gipsfaser',
    'Holzwerkstoff',
    'Fliese',
    'Spachtel',
    'Grundierung',
    'Abdichtung',
    'Farbe/Anstrich',
    'Dichtschlämme',
    'WDVS-Kleber/Armierung',
    'Fugenmörtel',
  ]),
  FeldDef('lambda', 'Wärmeleitfähigkeit λ', einheit: 'W/(mK)'),
  FeldDef('rho', 'Rohdichte', einheit: 'kg/m³'),
  FeldDef('dicke', 'Dicke / Format', einheit: 'mm'),
  FeldDef('verbrauch', 'Verbrauch', typ: FeldTyp.text, hilfe: 'z. B. 1,4 kg/m² je mm'),
  FeldDef('verbrauch_m2', 'Verbrauch je m² und Lage', hilfe: 'Zahl in der Einheit des Materials (kg, l …) – für Oberflächen'),
  ..._lager,
];

const _dichtstoff = [
  FeldDef('dichtart', 'Art', typ: FeldTyp.auswahl, optionen: [
    'Kompriband (vorkomprimiert)',
    'Multifunktionsband (3E)',
    'PU-Montageschaum',
    'Elastischer Schaum',
    'Dichtstoff (Silikon/Hybrid)',
    'Fensterfolie innen (luftdicht)',
    'Fensterfolie außen (diffusionsoffen)',
    'Butylband',
  ]),
  FeldDef('lambda', 'Wärmeleitfähigkeit λ', einheit: 'W/(mK)', hilfe: 'PU-Schaum ≈ 0,035; Kompriband ≈ 0,045 … 0,055'),
  FeldDef('fuge_von', 'Fugenbreite von', einheit: 'mm'),
  FeldDef('fuge_bis', 'Fugenbreite bis', einheit: 'mm'),
  FeldDef('sd', 'sd-Wert', einheit: 'm'),
  FeldDef('schlagregen', 'Schlagregendicht bis', einheit: 'Pa'),
  ..._lager,
];

const _kabel = [
  FeldDef('kabeltyp', 'Typ', typ: FeldTyp.text, hilfe: 'z. B. NYM-J, J-Y(St)Y, Cat.7, H07V-K, KNX'),
  FeldDef('adern', 'Aderzahl', einheit: ''),
  FeldDef('querschnitt', 'Querschnitt je Ader', einheit: 'mm²'),
  FeldDef('aussendurchmesser', 'Außendurchmesser', einheit: 'mm'),
  FeldDef('farbe', 'Mantelfarbe', typ: FeldTyp.text),
  FeldDef('biegeradius', 'min. Biegeradius', einheit: 'mm'),
  ..._lager,
];

const _rohr = [
  FeldDef('rohrart', 'Art', typ: FeldTyp.auswahl, optionen: [
    'Leerrohr flexibel',
    'Leerrohr starr',
    'Wellrohr (Estrich)',
    'Mehrschichtverbundrohr',
    'PE-Xa Heizrohr',
    'Kupferrohr',
    'HT-Abwasserrohr',
    'KG-Rohr',
    'Lüftungsrohr',
  ]),
  FeldDef('nennweite', 'Nennweite', typ: FeldTyp.text, hilfe: 'z. B. M20, M25, DN50, 16×2'),
  FeldDef('aussendurchmesser', 'Außendurchmesser', einheit: 'mm'),
  FeldDef('innendurchmesser', 'Innendurchmesser', einheit: 'mm'),
  FeldDef('druckfest', 'Druckfestigkeit', typ: FeldTyp.text, hilfe: 'z. B. 320 N (mittel), 750 N (schwer)'),
  FeldDef('halogenfrei', 'halogenfrei', typ: FeldTyp.jaNein),
  ..._lager,
];

const _dose = [
  FeldDef('dosenart', 'Art', typ: FeldTyp.auswahl, optionen: [
    'Unterputz-Gerätedose',
    'Unterputz-Geräteverbindungsdose (tief)',
    'Hohlwanddose',
    'Hohlwand-Elektronikdose',
    'Abzweigdose UP',
    'Abzweigdose AP',
    'Betondose',
    'Dämmstoffdose (luftdicht)',
    'Elektronikdose UP (tief, mit Trennsteg)',
    'Doppeldose / Gerätedose 2fach',
    'Netzwerk-/Datendose UP',
    'Hohlwand-Abzweigdose',
    'Dosenerhöhung / Ausgleichsring',
  ]),
  FeldDef('durchmesser', 'Durchmesser', einheit: 'mm'),
  FeldDef('tiefe', 'Tiefe', einheit: 'mm'),
  FeldDef('bohrung', 'Bohrdurchmesser', einheit: 'mm'),
  FeldDef('einfuehrungen', 'Einführungen bis', typ: FeldTyp.text, hilfe: 'z. B. M20 / M25'),
  FeldDef('luftdicht', 'luftdicht', typ: FeldTyp.jaNein),
  ..._lager,
];

const _kleinmaterial = [
  FeldDef('art', 'Art', typ: FeldTyp.text, hilfe: 'z. B. Dübel 8 mm, Wago 221-413, Rohrschelle'),
  FeldDef('groesse', 'Größe', typ: FeldTyp.text),
  ..._lager,
];

const _werkzeug = [
  FeldDef('werkzeugart', 'Art', typ: FeldTyp.auswahl, optionen: [
    'Bohrmaschine/Bohrhammer',
    'Akkuschrauber',
    'Säge',
    'Schleifer',
    'Mess- und Prüfgerät',
    'Handwerkzeug',
    'Leiter/Gerüst',
    'Mischer',
    'Sauger',
    'Sonstiges',
  ]),
  FeldDef('akku', 'Akkusystem', typ: FeldTyp.text, hilfe: 'z. B. 18 V Makita LXT'),
  FeldDef('zustand', 'Zustand', typ: FeldTyp.auswahl, optionen: ['neu', 'gut', 'gebraucht', 'defekt', 'verliehen']),
  FeldDef('lagerort', 'Lagerort', typ: FeldTyp.text),
  FeldDef('pruefung', 'Nächste Prüfung (DGUV V3)', typ: FeldTyp.text),
  FeldDef('seriennummer', 'Seriennummer', typ: FeldTyp.text),
];

const _sonstiges = [..._masse, FeldDef('beschreibung', 'Beschreibung', typ: FeldTyp.text)];

/// Ein Bauelement (Produkt mit technischen Daten).
class Bauelement {
  Bauelement({
    required this.id,
    required this.kategorie,
    required this.name,
    this.hersteller = '',
    this.artikelnummer = '',
    this.daten = const {},
    this.datenblatt,
    this.notiz = '',
    this.preisCent,
  });

  final String id;
  final BauelementKategorie kategorie;
  final String name;
  final String hersteller;
  final String artikelnummer;
  final Map<String, dynamic> daten;
  final String? datenblatt; // Dateiname im Ordner der Bibliothek
  final String notiz;
  final int? preisCent;

  String get anzeige => [if (hersteller.isNotEmpty) hersteller, name].join(' ');

  num? zahl(String k) {
    final v = daten[k];
    if (v is num) return v;
    if (v is String) return num.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  Bauelement mit({String? name, String? hersteller, String? artikelnummer, Map<String, dynamic>? daten, String? datenblatt, String? notiz, int? preisCent, BauelementKategorie? kategorie}) => Bauelement(
        id: id,
        kategorie: kategorie ?? this.kategorie,
        name: name ?? this.name,
        hersteller: hersteller ?? this.hersteller,
        artikelnummer: artikelnummer ?? this.artikelnummer,
        daten: daten ?? this.daten,
        datenblatt: datenblatt ?? this.datenblatt,
        notiz: notiz ?? this.notiz,
        preisCent: preisCent ?? this.preisCent,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kategorie': kategorie.name,
        'name': name,
        'hersteller': hersteller,
        'artikelnummer': artikelnummer,
        'daten': daten,
        if (datenblatt != null) 'datenblatt': datenblatt,
        'notiz': notiz,
        if (preisCent != null) 'preis_cent': preisCent,
      };

  static Bauelement ausJson(Map<String, dynamic> m) => Bauelement(
        id: m['id'] as String,
        kategorie: BauelementKategorie.values.where((k) => k.name == m['kategorie']).firstOrNull ?? BauelementKategorie.sonstiges,
        name: m['name'] as String? ?? '',
        hersteller: m['hersteller'] as String? ?? '',
        artikelnummer: m['artikelnummer'] as String? ?? '',
        daten: Map<String, dynamic>.from(m['daten'] as Map? ?? const {}),
        datenblatt: m['datenblatt'] as String?,
        notiz: m['notiz'] as String? ?? '',
        preisCent: (m['preis_cent'] as num?)?.toInt(),
      );

  /// Kurzbeschreibung der wichtigsten Daten.
  String get kurzdaten {
    String? z(String k, String e) {
      final v = zahl(k);
      if (v == null) return null;
      final t = v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
      return '$t$e';
    }

    final teile = switch (kategorie) {
      BauelementKategorie.fenster || BauelementKategorie.balkontuer => [z('uw', ' Uw'), z('bautiefe', ' mm Bautiefe'), daten['verglasung'] as String?, z('rw', ' dB')],
      BauelementKategorie.tuer => [daten['tuerart'] as String?, z('ud', ' Ud'), z('blattdicke', ' mm')],
      BauelementKategorie.sonnenschutz => [daten['system'] as String?, daten['antrieb'] as String?, z('kastenhoehe', ' mm Kasten')],
      BauelementKategorie.schrankgeraet => [daten['geraeteart'] as String?, z('te', ' TE'), z('nennstrom', ' A'), daten['charakteristik'] as String?],
      BauelementKategorie.technik => [daten['technikart'] as String?, z('leistung_kw', ' kW'), z('breite', ''), z('tiefe', ''), z('hoehe', ' mm')],
      BauelementKategorie.heizkoerper => [daten['hk_typ'] as String?, z('bauhoehe', '/'), z('baulaenge', ' mm'), z('q_norm', ' W')],
      BauelementKategorie.daemmstoff => [daten['daemmart'] as String?, z('dicke', ' mm'), z('lambda', ' W/(mK)')],
      BauelementKategorie.dichtstoff => [daten['dichtart'] as String?, z('lambda', ' W/(mK)')],
      BauelementKategorie.kabel => [daten['kabeltyp'] as String?, z('adern', '×'), z('querschnitt', ' mm²'), z('aussendurchmesser', ' mm Ø')],
      BauelementKategorie.rohr => [daten['rohrart'] as String?, daten['nennweite'] as String?, z('aussendurchmesser', ' mm Ø')],
      BauelementKategorie.dose => [daten['dosenart'] as String?, z('durchmesser', ' mm Ø'), z('tiefe', ' mm tief')],
      _ => [for (final f in kategorie.felder.take(3)) daten[f.schluessel] == null ? null : '${daten[f.schluessel]}${f.einheit.isEmpty ? '' : ' ${f.einheit}'}'],
    };
    return teile.whereType<String>().where((t) => t.isNotEmpty).join(' · ');
  }
}

// ------------------------------------------------------------ Datenblatt lesen

/// Werte aus dem Text eines Datenblatts erkennen (ohne KI): typische
/// Bezeichnungen wie „Uw = 0,78 W/(m²K)“, „Bautiefe 82 mm“, „Rw 42 dB“.
Map<String, dynamic> datenblattWerte(String text, BauelementKategorie k) {
  final t = text.replaceAll(RegExp(r'[\s ]+'), ' ');
  final w = <String, dynamic>{};
  double? zahlNach(String muster) {
    final m = RegExp('(?:$muster)' r'[^0-9]{0,25}?(\d{1,4}(?:[.,]\d{1,3})?)', caseSensitive: false).firstMatch(t);
    final z = m?.group(m.groupCount);
    if (z == null) return null;
    return double.tryParse(z.replaceAll(',', '.'));
  }

  void setze(String schluessel, String muster, {double? min, double? max}) {
    if (!k.felder.any((f) => f.schluessel == schluessel) && !_masse.any((f) => f.schluessel == schluessel)) return;
    final v = zahlNach(muster);
    if (v == null) return;
    if (min != null && v < min) return;
    if (max != null && v > max) return;
    w[schluessel] = v == v.roundToDouble() ? v.toInt() : v;
  }

  setze('uw', r'\bU\s*w\b', min: 0.3, max: 4);
  setze('ug', r'\bU\s*g\b', min: 0.3, max: 4);
  setze('uf', r'\bU\s*f\b', min: 0.5, max: 5);
  setze('ud', r'\bU\s*[dD]\b', min: 0.3, max: 5);
  setze('psi_g', r'(?:Ψ|psi)\s*g', min: 0.01, max: 0.2);
  setze('g_wert', r'\bg[- ]?(?:Wert|value)\b|\bg\s*=', min: 0.1, max: 0.9);
  setze('rw', r'\bR\s*w\b|Schalldämm', min: 20, max: 60);
  setze('bautiefe', r'Bautiefe|Profiltiefe|Einbautiefe|depth', min: 40, max: 200);
  setze('ansichtsbreite', r'Ansichtsbreite', min: 40, max: 250);
  setze('glasdicke', r'Glasdicke|Glasstärke', min: 10, max: 70);
  setze('blattdicke', r'Blattdicke|Blattstärke', min: 20, max: 120);
  setze('kastenhoehe', r'Kastenhöhe|Kasten\s*H', min: 100, max: 400);
  setze('kastentiefe', r'Kastentiefe|Kasten\s*T', min: 100, max: 500);
  setze('usb', r'\bU\s*sb\b', min: 0.2, max: 3);
  setze('fc', r'\bF\s*c\b', min: 0.05, max: 1);
  setze('leistung', r'Leistung|Leistungsaufnahme|power', min: 0.1, max: 10000);
  setze('leistung_kw', r'Heizleistung|Nennleistung|Wärmeleistung', min: 0.5, max: 100);
  setze('nennstrom', r'Nennstrom|Bemessungsstrom|\bI\s*n\b', min: 1, max: 250);
  setze('fehlerstrom', r'Fehlerstrom|I\s*Δ\s*n', min: 10, max: 500);
  setze('schaltvermoegen', r'Schaltvermögen|Bemessungsschaltvermögen', min: 3, max: 50);
  setze('lichtstrom', r'Lichtstrom|luminous flux', min: 10, max: 50000);
  setze('farbtemperatur', r'Farbtemperatur|CCT', min: 1500, max: 10000);
  setze('gewicht', r'Gewicht|weight', min: 0.01, max: 2000);
  setze('volumen', r'Volumen|Inhalt|Speicherinhalt', min: 1, max: 5000);
  setze('q_norm', r'Normwärmeleistung|75\s*/\s*65\s*/\s*20', min: 50, max: 10000);
  setze('scop', r'SCOP|JAZ', min: 1, max: 8);
  setze('schall', r'Schallleistung', min: 10, max: 90);
  final te = RegExp(r'(\d{1,2})\s*(?:TE|Teilungseinheit|modules?)\b', caseSensitive: false).firstMatch(t);
  if (te != null && k == BauelementKategorie.schrankgeraet) w['te'] = int.parse(te.group(1)!);
  final char = RegExp(r'\b([BCDKZ])\s?(\d{1,3})\s?A?\b').firstMatch(t);
  if (char != null && k == BauelementKategorie.schrankgeraet) {
    w['charakteristik'] = char.group(1);
    w.putIfAbsent('nennstrom', () => int.parse(char.group(2)!));
  }
  // Maße „1230 x 1480 mm“
  final masse = RegExp(r'(\d{3,4})\s*[x×]\s*(\d{3,4})(?:\s*[x×]\s*(\d{2,4}))?\s*mm').firstMatch(t);
  if (masse != null) {
    w.putIfAbsent('breite', () => int.parse(masse.group(1)!));
    w.putIfAbsent('hoehe', () => int.parse(masse.group(2)!));
    if (masse.group(3) != null) w.putIfAbsent('tiefe', () => int.parse(masse.group(3)!));
  }
  if (k == BauelementKategorie.fenster) {
    if (RegExp(r'3[- ]?fach|Dreifach', caseSensitive: false).hasMatch(t)) w['verglasung'] = '3-fach';
    if (RegExp(r'2[- ]?fach|Zweifach', caseSensitive: false).hasMatch(t) && !w.containsKey('verglasung')) w['verglasung'] = '2-fach';
    for (final r in ['RC3', 'RC2N', 'RC2', 'RC1N']) {
      if (t.contains(r)) {
        w['rc'] = r;
        break;
      }
    }
  }
  return w;
}

/// Anweisung an das Sprachmodell: Datenblatt → JSON mit den Feldern der Kategorie.
String kiDatenblattAnfrage(String text, BauelementKategorie k) {
  final felder = [
    for (final f in k.felder)
      '"${f.schluessel}": ${f.label}${f.einheit.isEmpty ? '' : ' in ${f.einheit}'}${f.optionen.isEmpty ? '' : ' (eins von: ${f.optionen.join(', ')})'}'
  ].join('\n');
  final kurz = text.length > 12000 ? text.substring(0, 12000) : text;
  return 'Lies das folgende technische Datenblatt eines Bauteils (Kategorie: ${k.label}) und gib NUR ein JSON-Objekt zurück. '
      'Schlüssel: "name", "hersteller", "artikelnummer" und diese Datenfelder:\n$felder\n'
      'Zahlen ohne Einheit als Zahl mit Punkt. Unbekannte Felder weglassen, nichts erfinden.\n\nDATENBLATT:\n$kurz';
}

/// Antwort des Sprachmodells lesen (erstes JSON-Objekt im Text).
Map<String, dynamic>? kiJsonLesen(String antwort) {
  final start = antwort.indexOf('{');
  final ende = antwort.lastIndexOf('}');
  if (start < 0 || ende <= start) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(antwort.substring(start, ende + 1)) as Map);
  } catch (_) {
    return null;
  }
}

/// Werte der KI-Antwort auf die Felder der Kategorie beschränken und Zahlen säubern.
Map<String, dynamic> kiWerteBereinigen(Map<String, dynamic> m, BauelementKategorie k) {
  final w = <String, dynamic>{};
  for (final f in k.felder) {
    final v = m[f.schluessel];
    if (v == null || (v is String && v.trim().isEmpty)) continue;
    switch (f.typ) {
      case FeldTyp.zahl:
        final z = v is num ? v : num.tryParse('$v'.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.\-]'), ''));
        if (z != null) w[f.schluessel] = z;
      case FeldTyp.auswahl:
        final o = f.optionen.where((o) => o.toLowerCase() == '$v'.toLowerCase()).firstOrNull;
        if (o != null) w[f.schluessel] = o;
      case FeldTyp.jaNein:
        w[f.schluessel] = v == true || '$v'.toLowerCase() == 'ja' || '$v' == 'true';
      case FeldTyp.text:
        w[f.schluessel] = '$v'.trim();
    }
  }
  return w;
}
