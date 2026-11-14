import 'dart:io';
import 'dart:typed_data';

/// Aufnahmedatum aus den EXIF-Daten eines JPEG-Fotos (DateTimeOriginal,
/// sonst DateTime); null, wenn keins drinsteht. Liest nur den Dateianfang.
DateTime? exifAufnahme(List<int> daten) {
  final b = daten is Uint8List ? daten : Uint8List.fromList(daten);
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 4 < b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    final laenge = (b[i + 2] << 8) | b[i + 3];
    if (marker == 0xE1 && i + 10 < b.length && String.fromCharCodes(b.sublist(i + 4, i + 8)) == 'Exif') {
      return _tiff(b, i + 10, laenge - 8);
    }
    if (marker == 0xDA || marker == 0xD9) return null; // Bilddaten beginnen
    i += 2 + laenge;
  }
  return null;
}

DateTime? _tiff(Uint8List b, int start, int laenge) {
  if (start + 8 > b.length) return null;
  final le = b[start] == 0x49; // II = little endian
  int u16(int o) => le ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
  int u32(int o) => le ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24) : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  String? ascii(int ifd, int tag) {
    final o = start + ifd;
    if (o + 2 > b.length) return null;
    final n = u16(o);
    for (var k = 0; k < n; k++) {
      final e = o + 2 + k * 12;
      if (e + 12 > b.length) return null;
      if (u16(e) == tag) {
        final anzahl = u32(e + 4);
        final wo = anzahl <= 4 ? e + 8 : start + u32(e + 8);
        if (wo + anzahl > b.length) return null;
        return String.fromCharCodes(b.sublist(wo, wo + anzahl).takeWhile((c) => c != 0));
      }
    }
    return null;
  }

  int? zeiger(int ifd, int tag) {
    final o = start + ifd;
    if (o + 2 > b.length) return null;
    final n = u16(o);
    for (var k = 0; k < n; k++) {
      final e = o + 2 + k * 12;
      if (e + 12 > b.length) return null;
      if (u16(e) == tag) return u32(e + 8);
    }
    return null;
  }

  final ifd0 = u32(start + 4);
  final exif = zeiger(ifd0, 0x8769);
  final text = (exif == null ? null : ascii(exif, 0x9003)) ?? ascii(ifd0, 0x0132);
  return _datum(text);
}

DateTime? _datum(String? t) {
  if (t == null) return null;
  final m = RegExp(r'(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(t);
  if (m == null) return null;
  final w = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  if (w[0] < 1990) return null;
  return DateTime(w[0], w[1], w[2], w[3], w[4], w[5]);
}

/// Aufnahmedatum einer Fotodatei (EXIF), sonst null.
DateTime? exifAusDatei(String pfad) {
  try {
    final f = File(pfad).openSync();
    try {
      return exifAufnahme(f.readSync(256 * 1024));
    } finally {
      f.closeSync();
    }
  } catch (_) {
    return null;
  }
}
