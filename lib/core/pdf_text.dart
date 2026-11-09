import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Einfacher Textauszug aus einer PDF-Datei (ohne Zusatzpaket): entpackt
/// Inhaltsströme (FlateDecode) und liest Text aus Tj/TJ-Befehlen. Klappt bei
/// den meisten Datenblättern mit normalen Schriften; bei Schriften mit eigener
/// Kodierung kommt wenig heraus – dann den Text aus dem PDF-Programm kopieren.
String pdfText(Uint8List daten) {
  final roh = latin1.decode(daten, allowInvalid: true);
  final b = StringBuffer();
  final stream = RegExp(r'stream\r?\n');
  var pos = 0;
  while (true) {
    final m = stream.firstMatch(roh.substring(pos));
    if (m == null) break;
    final start = pos + m.end;
    final ende = roh.indexOf('endstream', start);
    if (ende < 0) break;
    final kopfStart = roh.lastIndexOf('<<', pos + m.start);
    final kopf = kopfStart < 0 ? '' : roh.substring(kopfStart, pos + m.start);
    var inhalt = Uint8List.sublistView(daten, start, ende);
    if (kopf.contains('/FlateDecode')) {
      try {
        inhalt = Uint8List.fromList(ZLibDecoder().convert(inhalt));
      } catch (_) {
        try {
          inhalt = Uint8List.fromList(ZLibDecoder(raw: true).convert(inhalt.sublist(2)));
        } catch (_) {
          pos = ende + 9;
          continue;
        }
      }
    } else if (kopf.contains('/Filter')) {
      pos = ende + 9;
      continue; // Bilder u. Ä.
    }
    if (!kopf.contains('/Subtype') || kopf.contains('/Form')) _textAusInhalt(latin1.decode(inhalt, allowInvalid: true), b);
    pos = ende + 9;
  }
  return b.toString().replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n\s*\n+'), '\n').trim();
}

void _textAusInhalt(String s, StringBuffer b) {
  if (!s.contains('BT')) return;
  final befehl = RegExp(r'(\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>|\[(?:[^\]]*)\])\s*(Tj|TJ|\x27|")|(T\*|Td|TD|Tm|ET)');
  for (final m in befehl.allMatches(s)) {
    if (m.group(3) != null) {
      final op = m.group(3)!;
      if (op == 'ET' || op == 'T*' || op == 'Td' || op == 'TD') b.write(op == 'ET' ? '\n' : ' ');
      continue;
    }
    final arg = m.group(1)!;
    if (arg.startsWith('[')) {
      for (final t in RegExp(r'\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>|(-?\d+(?:\.\d+)?)').allMatches(arg)) {
        if (t.group(1) != null) {
          if ((double.tryParse(t.group(1)!) ?? 0) < -200) b.write(' ');
        } else {
          b.write(_zeichenkette(t.group(0)!));
        }
      }
    } else {
      b.write(_zeichenkette(arg));
    }
  }
}

String _zeichenkette(String t) {
  if (t.startsWith('<')) {
    final hex = t.substring(1, t.length - 1).replaceAll(RegExp(r'\s'), '');
    final bytes = [for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
    // Zweibyte-Kodierung mit Nullbyte vorne (häufig bei Unicode-Schriften)
    if (bytes.length.isEven && bytes.length >= 2 && [for (var i = 0; i < bytes.length; i += 2) bytes[i]].every((x) => x == 0)) {
      return String.fromCharCodes([for (var i = 1; i < bytes.length; i += 2) bytes[i]]);
    }
    return String.fromCharCodes(bytes.where((c) => c >= 32));
  }
  final s = t.substring(1, t.length - 1);
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c != '\\' || i + 1 >= s.length) {
      b.write(c);
      continue;
    }
    final n = s[++i];
    switch (n) {
      case 'n':
        b.write('\n');
      case 'r' || 't':
        b.write(' ');
      case '(' || ')' || '\\':
        b.write(n);
      default:
        final okt = RegExp(r'^[0-7]{1,3}').firstMatch(s.substring(i));
        if (okt != null) {
          b.writeCharCode(int.parse(okt.group(0)!, radix: 8));
          i += okt.group(0)!.length - 1;
        }
    }
  }
  return b.toString();
}
