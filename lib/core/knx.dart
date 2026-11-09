import 'dart:math' as math;

/// KNX-Gruppenadresse (dreistufig: Haupt-/Mittel-/Untergruppe) mit Name,
/// Funktion und verknüpften Objekten. Gespeichert in den Projekteinstellungen
/// unter `knx_gruppenadressen`.
class Gruppenadresse {
  Gruppenadresse({
    required this.id,
    required this.haupt,
    required this.mittel,
    required this.unter,
    required this.name,
    this.funktion = 'schalten',
    this.objekte = const [],
  });

  final String id;
  final int haupt; // 0 … 31
  final int mittel; // 0 … 7
  final int unter; // 0 … 255
  final String name;
  final String funktion; // siehe [gaFunktionen]
  final List<String> objekte;

  String get adresse => '$haupt/$mittel/$unter';
  int get sortierwert => haupt * 100000 + mittel * 1000 + unter;

  /// Datenpunkttyp für die ETS.
  String get dpt => gaFunktionen[funktion]?.$2 ?? 'DPST-1-1';

  Map<String, dynamic> toJson() =>
      {'id': id, 'h': haupt, 'm': mittel, 'u': unter, 'name': name, 'funktion': funktion, 'objekte': objekte};

  static Gruppenadresse ausJson(Map<String, dynamic> m) => Gruppenadresse(
        id: m['id'] as String,
        haupt: (m['h'] as num).toInt(),
        mittel: (m['m'] as num).toInt(),
        unter: (m['u'] as num).toInt(),
        name: m['name'] as String? ?? '',
        funktion: m['funktion'] as String? ?? 'schalten',
        objekte: [for (final o in (m['objekte'] as List? ?? const [])) o as String],
      );

  Gruppenadresse mit({String? name, String? funktion, List<String>? objekte, int? haupt, int? mittel, int? unter}) => Gruppenadresse(
        id: id,
        haupt: haupt ?? this.haupt,
        mittel: mittel ?? this.mittel,
        unter: unter ?? this.unter,
        name: name ?? this.name,
        funktion: funktion ?? this.funktion,
        objekte: objekte ?? this.objekte,
      );
}

/// Funktionen: Bezeichnung und ETS-Datenpunkttyp.
const gaFunktionen = <String, (String, String)>{
  'schalten': ('Schalten', 'DPST-1-1'),
  'status': ('Status Schalten', 'DPST-1-1'),
  'dimmen': ('Dimmen relativ', 'DPST-3-7'),
  'helligkeit': ('Helligkeitswert', 'DPST-5-1'),
  'status_helligkeit': ('Status Helligkeit', 'DPST-5-1'),
  'jalousie_auf_ab': ('Jalousie Auf/Ab', 'DPST-1-8'),
  'jalousie_stopp': ('Jalousie Stopp', 'DPST-1-10'),
  'position': ('Position', 'DPST-5-1'),
  'temperatur': ('Temperatur', 'DPST-9-1'),
  'praesenz': ('Präsenz', 'DPST-1-18'),
};

/// Gültige dreistufige Adresse „h/m/u“ lesen, sonst null.
(int, int, int)? gaLesen(String text) {
  final m = RegExp(r'^\s*(\d{1,2})/(\d)/(\d{1,3})\s*$').firstMatch(text);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!), u = int.parse(m.group(3)!);
  if (h > 31 || mi > 7 || u > 255) return null;
  return (h, mi, u);
}

/// Nächste freie Untergruppe in Haupt-/Mittelgruppe.
int naechsteUntergruppe(Iterable<Gruppenadresse> gas, int haupt, int mittel) {
  final belegt = {for (final g in gas) if (g.haupt == haupt && g.mittel == mittel) g.unter};
  var u = 0;
  while (belegt.contains(u)) {
    u++;
  }
  return u;
}

/// Doppelt vergebene Adressen.
List<String> doppelteAdressen(Iterable<Gruppenadresse> gas) {
  final gesehen = <String>{}, doppelt = <String>{};
  for (final g in gas) {
    if (!gesehen.add(g.adresse)) doppelt.add(g.adresse);
  }
  return doppelt.toList()..sort();
}

/// Kurzer Name für Home-Assistant-Entitäten: Kleinbuchstaben, Umlaute
/// umschreiben, sonst Unterstrich.
String haSlug(String text) {
  final t = text
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return t.isEmpty ? 'objekt' : t;
}

/// Home-Assistant-Domäne zu einem Objekttyp (Kürzel) und Aktortyp.
String haDomaene(String kuerzel, {String? aktortyp}) {
  if (aktortyp == 'Jalousie') return 'cover';
  if (aktortyp == 'Heizung') return 'climate';
  return switch (kuerzel) {
    'LE' => 'light',
    'PM' || 'BM' => 'binary_sensor',
    'ES' => 'sensor',
    _ => 'switch',
  };
}

/// Ein belegter Aktorkanal: Aktor (Kennzeichen), Kanal, Verbraucher.
typedef KanalBelegung = ({String aktorId, String aktor, String aktortyp, String kanal, String objektId, String name, String kuerzel});

/// Gruppenadressen aus der Kanalbelegung vorschlagen: je Kanal „Schalten“
/// und „Status“ (bei Dimmaktoren zusätzlich Dimmen und Helligkeit, bei
/// Jalousieaktoren Auf/Ab, Stopp, Position). Hauptgruppe = [haupt],
/// Mittelgruppe nach Funktion. Bereits vorhandene (gleicher Name) bleiben.
List<Gruppenadresse> gruppenadressenVorschlagen(
  List<KanalBelegung> belegung,
  List<Gruppenadresse> vorhanden, {
  int haupt = 1,
  required String Function() neueId,
}) {
  final ergebnis = [...vorhanden];
  final namen = {for (final g in vorhanden) g.name};
  void neu(String name, String funktion, int mittel, String objektId) {
    if (namen.contains(name)) return;
    namen.add(name);
    ergebnis.add(Gruppenadresse(
      id: neueId(),
      haupt: haupt,
      mittel: mittel,
      unter: naechsteUntergruppe(ergebnis, haupt, mittel),
      name: name,
      funktion: funktion,
      objekte: [objektId],
    ));
  }

  for (final b in belegung) {
    switch (b.aktortyp) {
      case 'Dimm':
        neu('${b.name} schalten', 'schalten', 0, b.objektId);
        neu('${b.name} Status', 'status', 1, b.objektId);
        neu('${b.name} dimmen', 'dimmen', 2, b.objektId);
        neu('${b.name} Helligkeit', 'helligkeit', 3, b.objektId);
        neu('${b.name} Status Helligkeit', 'status_helligkeit', 4, b.objektId);
      case 'Jalousie':
        neu('${b.name} Auf/Ab', 'jalousie_auf_ab', 5, b.objektId);
        neu('${b.name} Stopp', 'jalousie_stopp', 6, b.objektId);
        neu('${b.name} Position', 'position', 7, b.objektId);
      default:
        neu('${b.name} schalten', 'schalten', 0, b.objektId);
        neu('${b.name} Status', 'status', 1, b.objektId);
    }
  }
  return ergebnis..sort((a, b) => a.sortierwert.compareTo(b.sortierwert));
}

String _csv(String s) => '"${s.replaceAll('"', '""')}"';

/// Gruppenadressen als CSV im Format des ETS-Exports (für den Import in die ETS).
String etsCsv(List<Gruppenadresse> gas, {Map<int, String> hauptNamen = const {}, Map<int, String> mittelNamen = const {}}) {
  final b = StringBuffer('"Group name","Address","Central","Unfiltered","Description","DatapointType","Security"\n');
  final sortiert = [...gas]..sort((a, b) => a.sortierwert.compareTo(b.sortierwert));
  int? h, m;
  for (final g in sortiert) {
    if (g.haupt != h) {
      h = g.haupt;
      m = null;
      b.writeln('${_csv(hauptNamen[g.haupt] ?? 'Hauptgruppe ${g.haupt}')},"${g.haupt}/-/-","","","","","Auto"');
    }
    if (g.mittel != m) {
      m = g.mittel;
      b.writeln(
          '${_csv(mittelNamen[g.mittel] ?? gaFunktionenNachMittel[g.mittel] ?? 'Mittelgruppe ${g.mittel}')},"${g.haupt}/${g.mittel}/-","","","","","Auto"');
    }
    b.writeln('${_csv(g.name)},"${g.adresse}","","","","${g.dpt}","Auto"');
  }
  return b.toString();
}

/// Vorgabe-Namen der Mittelgruppen beim automatischen Vorschlag.
const gaFunktionenNachMittel = <int, String>{
  0: 'Schalten',
  1: 'Status',
  2: 'Dimmen',
  3: 'Helligkeit',
  4: 'Status Helligkeit',
  5: 'Jalousie Auf/Ab',
  6: 'Jalousie Stopp',
  7: 'Position',
};

/// Eintrag für die Home-Assistant-Konfiguration.
typedef HaEintrag = ({String domaene, String name, String entity, List<Gruppenadresse> gas});

/// KNX-Konfiguration für Home Assistant (YAML, Abschnitt `knx:`).
String haYaml(List<HaEintrag> eintraege) {
  final nach = <String, List<HaEintrag>>{};
  for (final e in eintraege) {
    nach.putIfAbsent(e.domaene, () => []).add(e);
  }
  final b = StringBuffer('# erzeugt von BauSpur – in configuration.yaml unter knx: einfügen\nknx:\n');
  String? ga(HaEintrag e, String f) => e.gas.where((g) => g.funktion == f).firstOrNull?.adresse;
  for (final d in nach.keys.toList()..sort()) {
    b.writeln('  $d:');
    for (final e in nach[d]!) {
      b.writeln('    - name: "${e.name.replaceAll('"', "'")}"');
      final eid = e.entity.contains('.') ? e.entity.split('.').last : e.entity;
      b.writeln('      unique_id: "bauspur_$eid"');
      switch (d) {
        case 'light':
          if (ga(e, 'schalten') != null) b.writeln('      address: "${ga(e, 'schalten')}"');
          if (ga(e, 'status') != null) b.writeln('      state_address: "${ga(e, 'status')}"');
          if (ga(e, 'helligkeit') != null) b.writeln('      brightness_address: "${ga(e, 'helligkeit')}"');
          if (ga(e, 'status_helligkeit') != null) b.writeln('      brightness_state_address: "${ga(e, 'status_helligkeit')}"');
        case 'cover':
          if (ga(e, 'jalousie_auf_ab') != null) b.writeln('      move_long_address: "${ga(e, 'jalousie_auf_ab')}"');
          if (ga(e, 'jalousie_stopp') != null) b.writeln('      stop_address: "${ga(e, 'jalousie_stopp')}"');
          if (ga(e, 'position') != null) b.writeln('      position_address: "${ga(e, 'position')}"');
        case 'binary_sensor':
          final s = ga(e, 'praesenz') ?? ga(e, 'status') ?? ga(e, 'schalten');
          if (s != null) b.writeln('      state_address: "$s"');
        case 'sensor':
          final s = ga(e, 'temperatur');
          if (s != null) {
            b.writeln('      state_address: "$s"');
            b.writeln('      type: temperature');
          }
        default:
          if (ga(e, 'schalten') != null) b.writeln('      address: "${ga(e, 'schalten')}"');
          if (ga(e, 'status') != null) b.writeln('      state_address: "${ga(e, 'status')}"');
      }
    }
  }
  return b.toString();
}

/// Kanalbezeichnungen eines Aktors: A, B, C … (bis 24 Kanäle).
List<String> kanalNamen(int anzahl) => [for (var i = 0; i < math.min(anzahl, 24); i++) String.fromCharCode(65 + i)];

/// Physikalische Adresse „Bereich.Linie.Teilnehmer“ prüfen.
bool paGueltig(String text) {
  final m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{1,3})$').firstMatch(text.trim());
  if (m == null) return false;
  return int.parse(m.group(1)!) <= 15 && int.parse(m.group(2)!) <= 15 && int.parse(m.group(3)!) <= 255;
}
