import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'bauelemente.dart';

/// Inhaltspaket der Bibliothek (Lastenheft: Inhaltspakete): Bauelemente mit
/// ihren Daten, Anschlüssen, Bohrlöchern und Datenblättern als eine
/// JSON-Datei, zum Weitergeben oder für einen zweiten PC.
const paketFormat = 'bauspur-bibliothek';

String bibliothekPaket(List<Bauelement> elemente, {String name = 'BauSpur-Bibliothek', Map<String, Uint8List> datenblaetter = const {}}) =>
    const JsonEncoder.withIndent(' ').convert({
      'format': paketFormat,
      'version': 1,
      'name': name,
      'erstellt': DateTime.now().toIso8601String(),
      'elemente': [for (final e in elemente) e.toJson()],
      if (datenblaetter.isNotEmpty) 'datenblaetter': {for (final d in datenblaetter.entries) d.key: base64Encode(d.value)},
    });

typedef BibliothekPaket = ({String name, List<Bauelement> elemente, Map<String, Uint8List> datenblaetter});

BibliothekPaket bibliothekPaketLesen(String text) {
  final Object? m;
  try {
    m = jsonDecode(text);
  } catch (_) {
    throw const FormatException('Keine gültige Paketdatei (kein JSON).');
  }
  if (m is! Map || m['format'] != paketFormat) throw const FormatException('Das ist kein BauSpur-Bibliothekspaket.');
  final elemente = <Bauelement>[];
  for (final e in (m['elemente'] as List? ?? const [])) {
    if (e is Map) {
      try {
        elemente.add(Bauelement.ausJson(Map<String, dynamic>.from(e)));
      } catch (_) {}
    }
  }
  return (
    name: '${m['name'] ?? 'Paket'}',
    elemente: elemente,
    datenblaetter: {
      for (final d in (m['datenblaetter'] as Map? ?? const {}).entries)
        if (d.value is String) '${d.key}': base64Decode(d.value as String),
    },
  );
}

/// Welche Elemente beim Import neu sind, welche es gleich schon gibt und welche abweichen.
({List<Bauelement> neu, List<Bauelement> gleich, List<Bauelement> anders}) paketVergleichen(List<Bauelement> paket, List<Bauelement> vorhanden) {
  final nachId = {for (final e in vorhanden) e.id: e};
  final neu = <Bauelement>[], gleich = <Bauelement>[], anders = <Bauelement>[];
  for (final e in paket) {
    final v = nachId[e.id];
    if (v == null) {
      neu.add(e);
    } else if (jsonEncode(v.toJson()) == jsonEncode(e.toJson())) {
      gleich.add(e);
    } else {
      anders.add(e);
    }
  }
  return (neu: neu, gleich: gleich, anders: anders);
}

/// Inhaltspakete automatisch aus einem Ordner laden: nur neue Elemente (gleiche
/// ID schon vorhanden = bleibt unverändert), nur Dateien, die seit dem letzten
/// Laden geändert wurden. [stand] = Datei → Änderungszeit (ms) des letzten Ladens.
/// Liefert (neue Elemente je Paketname, neuer Stand).
({Map<String, List<Bauelement>> neu, Map<String, int> stand}) paketeAusOrdner(String ordner, Set<String> vorhandeneIds, Map<String, int> stand) {
  final neu = <String, List<Bauelement>>{};
  final st = {...stand};
  final d = Directory(ordner);
  if (!d.existsSync()) return (neu: neu, stand: st);
  final ids = {...vorhandeneIds};
  for (final f in d.listSync().whereType<File>()) {
    if (!f.path.toLowerCase().endsWith('.json')) continue;
    final ms = f.lastModifiedSync().millisecondsSinceEpoch;
    if (st[f.path] == ms) continue;
    st[f.path] = ms;
    try {
      final pk = bibliothekPaketLesen(f.readAsStringSync());
      final l = [for (final e in pk.elemente) if (ids.add(e.id)) e];
      if (l.isNotEmpty) neu[pk.name] = l;
    } catch (_) {}
  }
  return (neu: neu, stand: st);
}
