import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Kleiner ZIP-Leser (ohne Zusatzpaket): liest das zentrale Verzeichnis und
/// entpackt Einträge, die gespeichert (0) oder mit Deflate (8) gepackt sind.
/// Verschlüsselte Einträge lösen [ZipVerschluesselt] aus.
class ZipArchiv {
  ZipArchiv(this.daten) {
    _verzeichnisLesen();
  }

  final Uint8List daten;
  final Map<String, _Eintrag> _eintraege = {};

  Iterable<String> get namen => _eintraege.keys;

  bool verschluesselt(String name) => _eintraege[name]?.verschluesselt ?? false;

  /// Inhalt eines Eintrags oder null, wenn es ihn nicht gibt.
  Uint8List? lesen(String name) {
    final e = _eintraege[name];
    if (e == null) return null;
    if (e.verschluesselt) throw ZipVerschluesselt(name);
    final bd = ByteData.sublistView(daten);
    final o = e.lokal;
    if (bd.getUint32(o, Endian.little) != 0x04034b50) throw const FormatException('ZIP: lokaler Kopf fehlt');
    final start = o + 30 + bd.getUint16(o + 26, Endian.little) + bd.getUint16(o + 28, Endian.little);
    final roh = Uint8List.sublistView(daten, start, start + e.gepackt);
    return switch (e.methode) {
      0 => Uint8List.fromList(roh),
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(roh)),
      _ => throw FormatException('ZIP: Packverfahren ${e.methode} wird nicht unterstützt'),
    };
  }

  String? text(String name) {
    final b = lesen(name);
    if (b == null) return null;
    return utf8.decode(b, allowMalformed: true);
  }

  void _verzeichnisLesen() {
    final bd = ByteData.sublistView(daten);
    var ende = -1;
    for (var i = daten.length - 22; i >= 0 && i >= daten.length - 22 - 65535; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50) {
        ende = i;
        break;
      }
    }
    if (ende < 0) throw const FormatException('Keine ZIP-Datei');
    final anzahl = bd.getUint16(ende + 10, Endian.little);
    var o = bd.getUint32(ende + 16, Endian.little);
    for (var n = 0; n < anzahl; n++) {
      if (bd.getUint32(o, Endian.little) != 0x02014b50) break;
      final flags = bd.getUint16(o + 8, Endian.little);
      final methode = bd.getUint16(o + 10, Endian.little);
      final gepackt = bd.getUint32(o + 20, Endian.little);
      final nl = bd.getUint16(o + 28, Endian.little), el = bd.getUint16(o + 30, Endian.little), kl = bd.getUint16(o + 32, Endian.little);
      final lokal = bd.getUint32(o + 42, Endian.little);
      final name = utf8.decode(daten.sublist(o + 46, o + 46 + nl), allowMalformed: true).replaceAll('\\', '/');
      _eintraege[name] = _Eintrag(methode, gepackt, lokal, flags & 1 == 1);
      o += 46 + nl + el + kl;
    }
  }
}

class _Eintrag {
  _Eintrag(this.methode, this.gepackt, this.lokal, this.verschluesselt);
  final int methode, gepackt, lokal;
  final bool verschluesselt;
}

class ZipVerschluesselt implements Exception {
  const ZipVerschluesselt(this.name);
  final String name;
  @override
  String toString() => 'Eintrag „$name“ ist mit Passwort geschützt';
}
