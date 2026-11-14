import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Einfacher ZIP-Schreiber (Einträge ungepackt, „stored“), ohne Fremdpaket –
/// läuft auch auf iPhone/iPad, wo es kein tar gibt. Fotos sind ohnehin gepackt.
class ZipSchreiber {
  final _daten = BytesBuilder(copy: false);
  final _verzeichnis = BytesBuilder(copy: false);
  var _anzahl = 0;

  static final _crcTabelle = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int crc32(List<int> b) {
    var c = 0xFFFFFFFF;
    for (final x in b) {
      c = _crcTabelle[(c ^ x) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }

  void hinzu(String name, List<int> inhalt) {
    final n = utf8.encode(name.replaceAll(r'\', '/'));
    final crc = crc32(inhalt);
    final offset = _daten.length;
    final kopf = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little) // UTF-8-Namen
      ..setUint16(8, 0, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, inhalt.length, Endian.little)
      ..setUint32(22, inhalt.length, Endian.little)
      ..setUint16(26, n.length, Endian.little);
    _daten
      ..add(kopf.buffer.asUint8List())
      ..add(n)
      ..add(inhalt);
    final z = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, inhalt.length, Endian.little)
      ..setUint32(24, inhalt.length, Endian.little)
      ..setUint16(28, n.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    _verzeichnis
      ..add(z.buffer.asUint8List())
      ..add(n);
    _anzahl++;
  }

  Uint8List fertig() {
    final v = _verzeichnis.takeBytes();
    final start = _daten.length;
    final ende = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, _anzahl, Endian.little)
      ..setUint16(10, _anzahl, Endian.little)
      ..setUint32(12, v.length, Endian.little)
      ..setUint32(16, start, Endian.little);
    _daten
      ..add(v)
      ..add(ende.buffer.asUint8List());
    return _daten.takeBytes();
  }
}

/// Dateien eines Ordners packen, die [nach] einem Zeitpunkt geändert wurden
/// (plus alle in [immer]); [aus] = Ordnernamen, die übersprungen werden.
Uint8List ordnerPacken(String ordner, {DateTime? nach, Set<String> immer = const {}, Set<String> aus = const {}}) {
  final z = ZipSchreiber();
  final basis = Directory(ordner);
  for (final f in basis.listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(basis.path.length + 1).replaceAll(r'\', '/');
    if (aus.any((a) => rel == a || rel.startsWith('$a/'))) continue;
    if (!immer.contains(rel) && nach != null && !f.lastModifiedSync().isAfter(nach)) continue;
    z.hinzu(rel, f.readAsBytesSync());
  }
  return z.fertig();
}
