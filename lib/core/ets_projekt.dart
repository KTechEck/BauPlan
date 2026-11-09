import 'dart:convert';
import 'dart:typed_data';

import 'knx.dart';
import 'zip_lesen.dart';

/// Gruppenadresse aus einem ETS-Projekt.
class EtsGa {
  const EtsGa({required this.haupt, required this.mittel, required this.unter, required this.name, this.dpt = '', this.beschreibung = ''});
  final int haupt, mittel, unter;
  final String name;
  final String dpt; // z. B. DPST-1-1
  final String beschreibung;
  String get adresse => '$haupt/$mittel/$unter';
  int get sortierwert => haupt * 100000 + mittel * 1000 + unter;
}

/// Gerät aus einem ETS-Projekt mit physikalischer Adresse.
class EtsGeraet {
  const EtsGeraet({required this.pa, required this.name});
  final String pa; // Bereich.Linie.Teilnehmer
  final String name;
}

/// Gelesener Inhalt eines ETS-Projekts (.knxproj) oder eines CSV-Exports.
class EtsProjekt {
  EtsProjekt({this.name = '', required this.gas, this.geraete = const [], this.hauptNamen = const {}, this.mittelNamen = const {}});
  final String name;
  final List<EtsGa> gas;
  final List<EtsGeraet> geraete;
  final Map<int, String> hauptNamen;
  final Map<String, String> mittelNamen; // "h/m"
}

class EtsFehler implements Exception {
  const EtsFehler(this.meldung);
  final String meldung;
  @override
  String toString() => meldung;
}

// ----------------------------------------------------------- XML (minimal)

/// Ein Element-Start aus dem XML-Strom (nur was der Abgleich braucht).
class XmlTag {
  XmlTag(this.name, this.attribute, {required this.schliessend, required this.leer});
  final String name;
  final Map<String, String> attribute;
  final bool schliessend; // </name>
  final bool leer; // <name … />
}

String _entitaeten(String s) => s
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

/// Tags eines XML-Textes der Reihe nach (Kommentare, Deklarationen und
/// Textinhalt werden übersprungen).
Iterable<XmlTag> xmlTags(String xml) sync* {
  final tag = RegExp(r'<(/?)([A-Za-z_][\w.:-]*)((?:\s+[^\s=>/]+\s*=\s*(?:"[^"]*"|' "'[^']*'" r'))*)\s*(/?)>');
  final attr = RegExp(r'([^\s=]+)\s*=\s*(?:"([^"]*)"|' "'([^']*)')");
  for (final m in tag.allMatches(xml)) {
    final a = <String, String>{};
    for (final x in attr.allMatches(m[3] ?? '')) {
      a[x[1]!] = _entitaeten(x[2] ?? x[3] ?? '');
    }
    yield XmlTag(m[2]!, a, schliessend: m[1] == '/', leer: m[4] == '/');
  }
}

// ------------------------------------------------------------ Einlesen

/// Gruppenadresse als Zahl (ETS 5/6) oder Text „h/m/u“ lesen.
(int, int, int)? etsAdresse(String text) {
  final n = int.tryParse(text.trim());
  if (n != null) return ((n >> 11) & 31, (n >> 8) & 7, n & 255);
  return gaLesen(text);
}

/// Projektdaten aus dem XML der ETS (Datei `P-xxxx/0.xml`).
EtsProjekt etsXmlLesen(String xml, {String name = ''}) {
  final gas = <EtsGa>[];
  final geraete = <EtsGeraet>[];
  final hauptNamen = <int, String>{};
  final mittelNamen = <String, String>{};
  var projektName = name;
  // Bereiche/Linien für die physikalische Adresse.
  final stapel = <String>[];
  String? bereich, linie;
  final bereichStapel = <String?>[], linieStapel = <String?>[];
  // Gruppenbereiche: Tiefe 1 = Hauptgruppe, Tiefe 2 = Mittelgruppe.
  final gruppenStapel = <(int, int)?>[];
  for (final t in xmlTags(xml)) {
    if (t.schliessend) {
      if (stapel.isNotEmpty) stapel.removeLast();
      switch (t.name) {
        case 'Area':
          bereich = bereichStapel.isEmpty ? null : bereichStapel.removeLast();
        case 'Line':
          linie = linieStapel.isEmpty ? null : linieStapel.removeLast();
        case 'GroupRange':
          if (gruppenStapel.isNotEmpty) gruppenStapel.removeLast();
      }
      continue;
    }
    switch (t.name) {
      case 'ProjectInformation':
        if (projektName.isEmpty) projektName = t.attribute['Name'] ?? '';
      case 'Area':
        if (!t.leer) {
          bereichStapel.add(bereich);
          bereich = t.attribute['Address'];
        }
      case 'Line':
        if (!t.leer) {
          linieStapel.add(linie);
          linie = t.attribute['Address'];
        }
      case 'DeviceInstance':
        final nr = t.attribute['Address'];
        if (nr != null && bereich != null && linie != null) {
          geraete.add(EtsGeraet(pa: '$bereich.$linie.$nr', name: t.attribute['Name'] ?? t.attribute['Description'] ?? ''));
        }
      case 'GroupRange':
        final start = int.tryParse(t.attribute['RangeStart'] ?? '');
        final tiefe = gruppenStapel.length;
        if (start != null) {
          final a = etsAdresse('$start')!;
          final nm = t.attribute['Name'] ?? '';
          if (tiefe == 0) hauptNamen[a.$1] = nm;
          if (tiefe == 1) mittelNamen['${a.$1}/${a.$2}'] = nm;
        }
        if (!t.leer) gruppenStapel.add(start == null ? null : (start, tiefe));
      case 'GroupAddress':
        final a = etsAdresse(t.attribute['Address'] ?? '');
        if (a != null) {
          gas.add(EtsGa(
            haupt: a.$1,
            mittel: a.$2,
            unter: a.$3,
            name: t.attribute['Name'] ?? '',
            dpt: (t.attribute['DatapointType'] ?? '').split(RegExp(r'[\s,]+')).first,
            beschreibung: t.attribute['Description'] ?? '',
          ));
        }
    }
    if (!t.leer) stapel.add(t.name);
  }
  gas.sort((a, b) => a.sortierwert.compareTo(b.sortierwert));
  return EtsProjekt(name: projektName, gas: gas, geraete: geraete, hauptNamen: hauptNamen, mittelNamen: mittelNamen);
}

/// ETS-Projektdatei (.knxproj, ein ZIP) lesen. Passwortgeschützte Projekte
/// lassen sich nicht öffnen – dafür gibt es den CSV-Export der ETS.
EtsProjekt knxprojLesen(Uint8List daten) {
  final zip = ZipArchiv(daten);
  String? projektName;
  // Name aus P-xxxx/project.xml
  for (final n in zip.namen) {
    if (RegExp(r'^P-[0-9A-F]+/project\.xml$', caseSensitive: false).hasMatch(n) && !zip.verschluesselt(n)) {
      projektName = xmlTags(zip.text(n) ?? '').where((t) => t.name == 'ProjectInformation').firstOrNull?.attribute['Name'];
    }
  }
  final xmlName = zip.namen.where((n) => RegExp(r'^P-[0-9A-F]+/0\.xml$', caseSensitive: false).hasMatch(n)).firstOrNull;
  if (xmlName != null) {
    if (zip.verschluesselt(xmlName)) throw const EtsFehler(_passwortHinweis);
    return etsXmlLesen(zip.text(xmlName)!, name: projektName ?? '');
  }
  // ETS 5/6: Projekt als eingebettetes P-xxxx.zip
  final innen = zip.namen.where((n) => RegExp(r'^P-[0-9A-F]+\.zip$', caseSensitive: false).hasMatch(n)).firstOrNull;
  if (innen != null) {
    final ZipArchiv z2;
    try {
      z2 = ZipArchiv(zip.lesen(innen)!);
    } on ZipVerschluesselt {
      throw const EtsFehler(_passwortHinweis);
    }
    final x = z2.namen.where((n) => RegExp(r'(^|/)0\.xml$').hasMatch(n)).firstOrNull;
    if (x == null) throw const EtsFehler('Im ETS-Projekt wurde keine Projektdatei (0.xml) gefunden.');
    try {
      final name = z2.namen.where((n) => n.endsWith('project.xml')).map((n) => xmlTags(z2.text(n) ?? '')).expand((e) => e).where((t) => t.name == 'ProjectInformation').firstOrNull?.attribute['Name'];
      return etsXmlLesen(z2.text(x)!, name: name ?? projektName ?? '');
    } on ZipVerschluesselt {
      throw const EtsFehler(_passwortHinweis);
    }
  }
  throw const EtsFehler('Das ist keine ETS-Projektdatei (kein Ordner P-xxxx gefunden).');
}

const _passwortHinweis = 'Das ETS-Projekt ist mit einem Passwort geschützt und kann nicht gelesen werden. '
    'Entweder in der ETS ohne Passwort exportieren oder die Gruppenadressen als CSV exportieren '
    '(ETS: Gruppenadressen → Exportieren → CSV, Format „1/1“) und die CSV hier einlesen.';

List<String> _csvZeile(String zeile, String trenner) {
  final felder = <String>[];
  final b = StringBuffer();
  var inAnf = false;
  for (var i = 0; i < zeile.length; i++) {
    final c = zeile[i];
    if (inAnf) {
      if (c == '"') {
        if (i + 1 < zeile.length && zeile[i + 1] == '"') {
          b.write('"');
          i++;
        } else {
          inAnf = false;
        }
      } else {
        b.write(c);
      }
    } else if (c == '"') {
      inAnf = true;
    } else if (c == trenner) {
      felder.add(b.toString());
      b.clear();
    } else {
      b.write(c);
    }
  }
  felder.add(b.toString());
  return felder;
}

/// Bytes als Text: UTF-8 (mit/ohne BOM, UTF-16 LE) oder sonst Latin-1.
String etsText(Uint8List b) {
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    final w = ByteData.sublistView(b);
    return String.fromCharCodes([for (var i = 2; i + 1 < b.length; i += 2) w.getUint16(i, Endian.little)]);
  }
  try {
    final t = utf8.decode(b);
    return t.startsWith('﻿') ? t.substring(1) : t;
  } on FormatException {
    return latin1.decode(b);
  }
}

/// CSV-Export der Gruppenadressen aus der ETS („Group name“, „Address“, …).
EtsProjekt etsCsvLesen(String text) {
  final zeilen = const LineSplitter().convert(text).where((z) => z.trim().isNotEmpty).toList();
  if (zeilen.isEmpty) throw const EtsFehler('Die CSV-Datei ist leer.');
  final trenner = zeilen.first.contains('\t') ? '\t' : (zeilen.first.split(';').length > zeilen.first.split(',').length ? ';' : ',');
  final kopf = _csvZeile(zeilen.first, trenner).map((s) => s.trim().toLowerCase()).toList();
  int spalte(List<String> namen, int sonst) {
    final i = kopf.indexWhere((k) => namen.contains(k));
    return i >= 0 ? i : sonst;
  }

  final hatKopf = kopf.contains('address') || kopf.contains('adresse');
  final iName = spalte(['group name', 'name', 'gruppenname'], 0);
  final iAdr = spalte(['address', 'adresse'], 1);
  final iDpt = spalte(['datapointtype', 'datenpunkttyp', 'dpt'], -1);
  final iBes = spalte(['description', 'beschreibung'], -1);
  final gas = <EtsGa>[];
  final hauptNamen = <int, String>{};
  final mittelNamen = <String, String>{};
  for (final z in zeilen.skip(hatKopf ? 1 : 0)) {
    final f = _csvZeile(z, trenner);
    if (f.length <= iAdr) continue;
    final adr = f[iAdr].trim();
    final name = f[iName].trim();
    final h = RegExp(r'^(\d+)/-/-$').firstMatch(adr);
    final m = RegExp(r'^(\d+)/(\d+)/-$').firstMatch(adr);
    if (h != null) {
      hauptNamen[int.parse(h[1]!)] = name;
      continue;
    }
    if (m != null) {
      mittelNamen['${m[1]}/${m[2]}'] = name;
      continue;
    }
    final a = gaLesen(adr);
    if (a == null) continue;
    gas.add(EtsGa(
      haupt: a.$1,
      mittel: a.$2,
      unter: a.$3,
      name: name,
      dpt: iDpt >= 0 && iDpt < f.length ? f[iDpt].trim() : '',
      beschreibung: iBes >= 0 && iBes < f.length ? f[iBes].trim() : '',
    ));
  }
  if (gas.isEmpty) throw const EtsFehler('In der CSV-Datei wurden keine Gruppenadressen gefunden.');
  gas.sort((a, b) => a.sortierwert.compareTo(b.sortierwert));
  return EtsProjekt(gas: gas, hauptNamen: hauptNamen, mittelNamen: mittelNamen);
}

// ------------------------------------------------------------ Abgleich

enum AbgleichArt {
  gleich('stimmt überein'),
  nameAnders('Name weicht ab'),
  dptAnders('Datenpunkttyp weicht ab'),
  nurEts('nur in der ETS'),
  nurBauspur('nur in BauSpur');

  const AbgleichArt(this.label);
  final String label;
}

class AbgleichZeile {
  const AbgleichZeile(this.art, this.adresse, {this.bauspur, this.ets});
  final AbgleichArt art;
  final String adresse;
  final Gruppenadresse? bauspur;
  final EtsGa? ets;
}

/// DPT normalisieren: „DPST-1-1“, „DPT-1“, „1.001“ → „1.001“ bzw. „1“.
String dptKurz(String dpt) {
  final s = RegExp(r'^DPST-(\d+)-(\d+)$').firstMatch(dpt.trim());
  if (s != null) return '${s[1]}.${s[2]!.padLeft(3, '0')}';
  final t = RegExp(r'^DPT-(\d+)$').firstMatch(dpt.trim());
  if (t != null) return t[1]!;
  return dpt.trim();
}

bool _dptPasst(String a, String b) {
  final x = dptKurz(a), y = dptKurz(b);
  if (x.isEmpty || y.isEmpty) return true;
  return x == y || x.split('.').first == y || y.split('.').first == x;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Gruppenadressen von BauSpur und ETS nach Adresse vergleichen.
List<AbgleichZeile> gaAbgleich(List<Gruppenadresse> bauspur, List<EtsGa> ets) {
  final b = {for (final g in bauspur) g.adresse: g};
  final e = {for (final g in ets) g.adresse: g};
  final alle = {...b.keys, ...e.keys}.toList()
    ..sort((x, y) {
      int w(String a) {
        final t = gaLesen(a)!;
        return t.$1 * 100000 + t.$2 * 1000 + t.$3;
      }

      return w(x).compareTo(w(y));
    });
  return [
    for (final a in alle)
      if (b[a] == null)
        AbgleichZeile(AbgleichArt.nurEts, a, ets: e[a])
      else if (e[a] == null)
        AbgleichZeile(AbgleichArt.nurBauspur, a, bauspur: b[a])
      else if (_norm(b[a]!.name) != _norm(e[a]!.name))
        AbgleichZeile(AbgleichArt.nameAnders, a, bauspur: b[a], ets: e[a])
      else if (!_dptPasst(b[a]!.dpt, e[a]!.dpt))
        AbgleichZeile(AbgleichArt.dptAnders, a, bauspur: b[a], ets: e[a])
      else
        AbgleichZeile(AbgleichArt.gleich, a, bauspur: b[a], ets: e[a]),
  ];
}

/// Funktion (siehe [gaFunktionen]) aus Datenpunkttyp und Name ableiten.
String funktionAusEts(EtsGa g) {
  final n = g.name.toLowerCase();
  final d = dptKurz(g.dpt);
  final status = n.contains('status') || n.contains('rückmeld') || n.contains('rm ');
  if (d.startsWith('3')) return 'dimmen';
  if (d == '1.008' || n.contains('auf/ab')) return 'jalousie_auf_ab';
  if (d == '1.010' || n.contains('stopp') || n.contains('stop')) return 'jalousie_stopp';
  if (d.startsWith('9')) return 'temperatur';
  if (d == '1.018' || n.contains('präsenz')) return 'praesenz';
  if (d.startsWith('5')) {
    if (n.contains('position')) return 'position';
    return status ? 'status_helligkeit' : 'helligkeit';
  }
  return status ? 'status' : 'schalten';
}

/// ETS-Stand übernehmen: fehlende Adressen anlegen, bei [namenUebernehmen]
/// auch abweichende Namen ändern. Verknüpfte Objekte bleiben erhalten.
List<Gruppenadresse> etsUebernehmen(
  List<Gruppenadresse> bauspur,
  List<AbgleichZeile> abgleich, {
  bool namenUebernehmen = false,
  Set<String>? nurAdressen,
  required String Function() neueId,
}) {
  final ergebnis = [...bauspur];
  for (final z in abgleich) {
    if (nurAdressen != null && !nurAdressen.contains(z.adresse)) continue;
    if (z.art == AbgleichArt.nurEts) {
      final g = z.ets!;
      ergebnis.add(Gruppenadresse(id: neueId(), haupt: g.haupt, mittel: g.mittel, unter: g.unter, name: g.name, funktion: funktionAusEts(g)));
    } else if (z.art == AbgleichArt.nameAnders && namenUebernehmen) {
      final i = ergebnis.indexWhere((x) => x.id == z.bauspur!.id);
      if (i >= 0) ergebnis[i] = ergebnis[i].mit(name: z.ets!.name);
    }
  }
  return ergebnis..sort((a, b) => a.sortierwert.compareTo(b.sortierwert));
}

/// Physikalische Adressen: in BauSpur vergebene (PA → Bezeichnung) gegen die ETS.
({List<String> nurBauspur, List<EtsGeraet> nurEts, List<String> gleich}) paAbgleich(Map<String, String> bauspur, List<EtsGeraet> ets) {
  final e = {for (final g in ets) g.pa: g};
  return (
    nurBauspur: [for (final pa in bauspur.keys) if (!e.containsKey(pa)) pa]..sort(),
    nurEts: [for (final g in ets) if (!bauspur.containsKey(g.pa)) g],
    gleich: [for (final pa in bauspur.keys) if (e.containsKey(pa)) pa]..sort(),
  );
}
