import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'zip_lesen.dart';

/// Projekt zwischen PC und iPad (volle BauSpur auf dem iPad) als Ausleihe:
/// Holt das iPad das Projekt, ist es am PC nur noch lesbar (technisch gesperrt),
/// bis das iPad es zurückgibt. Bei der Rückgabe kommen Datenbank und alle neuen
/// oder geänderten Dateien (Fotos, Dokumente) zurück; der PC sichert vorher.
/// So können PC und iPad nie gleichzeitig ändern und nichts geht verloren.
const ausleiheDatei = 'ipad_ausleihe.json';

class Ausleihe {
  const Ausleihe({required this.geraet, required this.name, required this.seit, required this.amPc, this.zurueckgegeben = false, this.pc = ''});
  final String geraet; // ID des iPads
  final String name; // Name des iPads
  final DateTime seit;
  final bool amPc; // true: Kopie am PC (ausgeliehen), false: Kopie auf dem iPad (geliehen)
  final bool zurueckgegeben; // nur auf dem iPad: schon zurückgegeben → nur noch lesen
  final String pc; // nur auf dem iPad: Name/Adresse des PCs

  Map<String, dynamic> toJson() => {'geraet': geraet, 'name': name, 'seit': seit.toIso8601String(), 'am_pc': amPc, if (zurueckgegeben) 'zurueck': true, if (pc.isNotEmpty) 'pc': pc};

  static Ausleihe? lesen(String ordner) {
    final f = File(p.join(ordner, ausleiheDatei));
    if (!f.existsSync()) return null;
    try {
      final m = jsonDecode(f.readAsStringSync()) as Map;
      return Ausleihe(
        geraet: '${m['geraet']}',
        name: '${m['name'] ?? 'iPad'}',
        seit: DateTime.tryParse('${m['seit']}') ?? DateTime.now(),
        amPc: m['am_pc'] == true,
        zurueckgegeben: m['zurueck'] == true,
        pc: '${m['pc'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }

  void schreiben(String ordner) => File(p.join(ordner, ausleiheDatei)).writeAsStringSync(jsonEncode(toJson()));

  static void loeschen(String ordner) {
    final f = File(p.join(ordner, ausleiheDatei));
    if (f.existsSync()) f.deleteSync();
  }

  /// Darf in dieser Kopie geändert werden?
  bool get sperrt => amPc || zurueckgegeben;

  String get text => amPc
      ? 'An „$name“ ausgeliehen seit ${_zeit(seit)} – am PC nur lesen, bis das iPad das Projekt zurückgibt.'
      : zurueckgegeben
          ? 'Zurückgegeben an den PC – diese iPad-Kopie ist nur noch zum Lesen. Neu holen, um weiterzuarbeiten.'
          : 'Vom PC${pc.isEmpty ? '' : ' „$pc“'} ausgeliehen seit ${_zeit(seit)} – nach der Arbeit „An PC zurückgeben“.';

  static String _zeit(DateTime t) => '${t.day}.${t.month}. ${t.hour}:${t.minute.toString().padLeft(2, '0')}';
}

/// Dateien, die nie mitgehen oder überschrieben werden.
const _nieKopieren = {'projekt.lock', ausleiheDatei};

/// ZIP in einen Ordner entpacken (überschreibt gleichnamige Dateien, löscht nichts).
/// Pfade mit „..“, Sperr- und Ausleihdatei werden übersprungen.
int projektEntpacken(Uint8List zip, String ziel) {
  final a = ZipArchiv(zip);
  var n = 0;
  for (final name in a.namen) {
    if (name.endsWith('/') || name.contains('..')) continue;
    final rel = name.startsWith('./') ? name.substring(2) : name;
    if (rel.isEmpty || _nieKopieren.contains(rel) || rel.startsWith('backup/')) continue;
    final b = a.lesen(name);
    if (b == null) continue;
    final f = File(p.join(ziel, rel))..parent.createSync(recursive: true);
    f.writeAsBytesSync(b);
    n++;
  }
  return n;
}

/// Prüft ein Rückgabe-ZIP: muss eine SQLite-Projektdatenbank enthalten.
String? rueckgabePruefen(Uint8List zip) {
  try {
    final a = ZipArchiv(zip);
    final name = a.namen.where((n) => n == 'projekt.bauspur' || n == './projekt.bauspur').firstOrNull;
    if (name == null) return 'In der Rückgabe fehlt die Projektdatenbank.';
    final db = a.lesen(name)!;
    if (db.length < 100 || String.fromCharCodes(db.sublist(0, 15)) != 'SQLite format 3') return 'Die Projektdatenbank in der Rückgabe ist beschädigt.';
    return null;
  } catch (e) {
    return 'Rückgabe nicht lesbar: $e';
  }
}
