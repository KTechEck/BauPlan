import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Diktat mit Transkription (keine Audio-Notizen – es bleibt nur Text).
///
/// PC: Windows-Spracherkennung (System.Speech) über PowerShell, ohne Internet,
/// sofern eine deutsche Spracherkennung installiert ist. Jede erkannte Phrase
/// kommt sofort als eigene Zeile. iPhone: Diktierfunktion der Tastatur (auf
/// neueren Geräten auf dem Gerät), der Text wird danach genauso ausgewertet.
class DiktatSitzung {
  DiktatSitzung._(this._prozess);
  final Process _prozess;
  final _phrasen = StreamController<String>.broadcast();
  String? fehler;

  Stream<String> get phrasen => _phrasen.stream;

  /// Startet das Diktat; null, wenn es auf diesem System nicht geht.
  static Future<DiktatSitzung?> starten({int maxSekunden = 300}) async {
    if (!Platform.isWindows) return null;
    final skript = File(p.join(Directory.systemTemp.path, 'bauspur_diktat.ps1'));
    if (!skript.existsSync() || skript.readAsStringSync() != _skript) skript.writeAsStringSync(_skript);
    try {
      final pr = await Process.start('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', skript.path, '$maxSekunden']);
      final s = DiktatSitzung._(pr);
      pr.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((z) {
        final t = z.trim();
        if (t.startsWith('#FEHLER ')) {
          s.fehler = t.substring(8);
        } else if (t.isNotEmpty) {
          s._phrasen.add(t);
        }
      }, onDone: () => s._phrasen.close());
      pr.stderr.drain<void>();
      return s;
    } catch (_) {
      return null;
    }
  }

  /// Beendet das Diktat (bereits erkannte Phrasen bleiben erhalten).
  void beenden() => _prozess.kill();

  Future<int> get ende => _prozess.exitCode;
}

const _skript = r'''
param([int]$sek = 300)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
  Add-Type -AssemblyName System.Speech
  $alle = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
  $info = $alle | Where-Object { $_.Culture.Name -like 'de*' } | Select-Object -First 1
  if (-not $info) { $info = $alle | Select-Object -First 1 }
  if (-not $info) { Write-Output '#FEHLER Keine Windows-Spracherkennung installiert (Einstellungen > Zeit und Sprache > Sprache > Deutsch > Spracherkennung).'; exit 2 }
  $e = New-Object System.Speech.Recognition.SpeechRecognitionEngine($info)
  $e.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
  $e.SetInputToDefaultAudioDevice()
  $e.InitialSilenceTimeout = [TimeSpan]::FromSeconds(20)
  $e.EndSilenceTimeout = [TimeSpan]::FromSeconds(1)
  $ende = (Get-Date).AddSeconds($sek)
  while ((Get-Date) -lt $ende) {
    $r = $e.Recognize([TimeSpan]::FromSeconds(30))
    if ($r -ne $null -and $r.Text) { [Console]::Out.WriteLine($r.Text); [Console]::Out.Flush() }
  }
} catch {
  Write-Output ('#FEHLER ' + $_.Exception.Message)
  exit 1
}
''';

/// Gesprochene Satzzeichen und Befehle in Text umsetzen, Satzanfänge groß.
String diktatAufbereiten(String roh) {
  var t = ' ${roh.replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  final ersetzungen = <String, String>{
    r' (neue zeile|nächste zeile|neuer absatz|absatz) ': '\n',
    r' (punkt) ': '. ',
    r' (komma) ': ', ',
    r' (fragezeichen) ': '? ',
    r' (ausrufezeichen) ': '! ',
    r' (doppelpunkt) ': ': ',
    r' (bindestrich|minus) ': '-',
  };
  for (final e in ersetzungen.entries) {
    t = t.replaceAll(RegExp(e.key, caseSensitive: false), e.value);
  }
  t = t.replaceAll(RegExp(r' +([.,?!:])'), r'$1').replaceAll(RegExp(r' *\n *'), '\n').trim();
  // Satzanfänge groß
  final b = StringBuffer();
  var gross = true;
  for (final ch in t.split('')) {
    if (gross && RegExp(r'[a-zäöü]').hasMatch(ch)) {
      b.write(ch.toUpperCase());
      gross = false;
    } else {
      if (RegExp(r'[A-Za-zÄÖÜäöüß0-9]').hasMatch(ch)) gross = false;
      b.write(ch);
    }
    if ('.?!\n'.contains(ch)) gross = true;
  }
  return b.toString();
}

/// Ausgewertetes Diktat: Notiz plus erkannte Aufgaben und Mängel (zum
/// Bestätigen – nichts wird ungefragt angelegt).
class DiktatTeile {
  DiktatTeile(this.notiz, this.aufgaben, this.maengel, this.messwerte);
  final String notiz;
  final List<String> aufgaben;
  final List<String> maengel;
  final List<({String was, double wert, String einheit})> messwerte;
}

/// Sätze mit „Aufgabe/To-do/noch …/muss …/nicht vergessen“ werden Aufgaben,
/// „Mangel/Schaden/kaputt/undicht/Riss“ Mängel; Zahlen mit Einheit Messwerte.
DiktatTeile diktatAuswerten(String text) {
  final saetze = text.split(RegExp(r'(?<=[.!?])\s+|\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final aufgaben = <String>[], maengel = <String>[];
  final mess = <({String was, double wert, String einheit})>[];
  String ohnePraefix(String s) =>
      s.replaceFirst(RegExp(r'^(aufgabe|to-?do|mangel|schaden)\s*[:,-]?\s*', caseSensitive: false), '').replaceAll(RegExp(r'[.!]$'), '').trim();
  for (final s in saetze) {
    final k = s.toLowerCase();
    if (RegExp(r'^(mangel|schaden)\b').hasMatch(k) || RegExp(r'\b(kaputt|undicht|beschädigt|riss|tropft|defekt)\b').hasMatch(k)) {
      maengel.add(_gross(ohnePraefix(s)));
    } else if (RegExp(r'^(aufgabe|to-?do)\b').hasMatch(k) || RegExp(r'^(noch|bitte|nicht vergessen)\b').hasMatch(k) || RegExp(r'\b(muss|müssen|sollte) noch\b').hasMatch(k)) {
      aufgaben.add(_gross(ohnePraefix(s)));
    }
    for (final m in RegExp(r'([A-Za-zÄÖÜäöüß]+)\s+(\d+(?:[.,]\d+)?)\s*(mm|zentimeter|cm|meter|m|grad|°c|bar|volt|v|ampere|a|ohm|watt|w|prozent|%)\b', caseSensitive: false)
        .allMatches(s)) {
      final wert = double.tryParse(m.group(2)!.replaceAll(',', '.'));
      if (wert == null) continue;
      final e = m.group(3)!.toLowerCase();
      final einheit = switch (e) {
        'zentimeter' => 'cm',
        'meter' => 'm',
        'grad' || '°c' => '°C',
        'volt' => 'V',
        'ampere' => 'A',
        'ohm' => 'Ω',
        'watt' => 'W',
        'prozent' => '%',
        _ => e,
      };
      mess.add((was: m.group(1)!, wert: wert, einheit: einheit));
    }
  }
  return DiktatTeile(text.trim(), aufgaben, maengel, mess);
}

String _gross(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Anfrage an die lokale KI, ein Diktat zu ordnen (Antwort als JSON).
const kiDiktatAnfrage = 'Ordne dieses Baustellen-Diktat. Antworte NUR mit JSON: '
    '{"notiz": "aufgeräumter Text fürs Bautagebuch", "aufgaben": ["…"], "maengel": ["…"]}. '
    'Erfinde nichts, lass leere Listen leer.';

/// Antwort der KI lesen (null, wenn kein JSON darin steht).
DiktatTeile? kiDiktatLesen(String antwort) {
  final m = RegExp(r'\{[\s\S]*\}').firstMatch(antwort);
  if (m == null) return null;
  try {
    final j = jsonDecode(m.group(0)!) as Map<String, dynamic>;
    List<String> liste(String k) => [for (final e in (j[k] as List? ?? const [])) '$e'.trim()].where((s) => s.isNotEmpty).toList();
    return DiktatTeile('${j['notiz'] ?? ''}'.trim(), liste('aufgaben'), liste('maengel'), const []);
  } catch (_) {
    return null;
  }
}
