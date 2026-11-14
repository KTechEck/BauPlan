import 'dart:convert';
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
