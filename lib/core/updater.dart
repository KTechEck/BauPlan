import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Eigener Updater: neue Programmversion aus einem Ordner (Update-Quelle, z. B.
/// OneDrive/NAS) mit Manifest `bauspur_update.json` {build, dateien: {pfad: sha256}}.
/// Jede Datei wird per SHA-256 geprüft, das laufende Programm vorher gesichert,
/// dann ersetzt ein kleines Skript die Dateien nach dem Beenden und startet neu.

// ------------------------------------------------------------------ SHA-256

const _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

/// SHA-256 als Hex-Text.
String sha256Hex(List<int> daten) {
  final h = Uint32List.fromList([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  final l = daten.length;
  final gesamt = ((l + 9 + 63) ~/ 64) * 64;
  final m = Uint8List(gesamt)..setRange(0, l, daten);
  m[l] = 0x80;
  final bits = l * 8;
  for (var i = 0; i < 8; i++) {
    m[gesamt - 1 - i] = (bits >> (8 * i)) & 0xff;
  }
  final w = Uint32List(64);
  int r(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
  for (var o = 0; o < gesamt; o += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = (m[o + 4 * i] << 24) | (m[o + 4 * i + 1] << 16) | (m[o + 4 * i + 2] << 8) | m[o + 4 * i + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = r(w[i - 15], 7) ^ r(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = r(w[i - 2], 17) ^ r(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = r(e, 6) ^ r(e, 11) ^ r(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final t1 = (hh + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = r(a, 2) ^ r(a, 13) ^ r(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
    h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff;
    h[7] = (h[7] + hh) & 0xffffffff;
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}

// ----------------------------------------------------------------- Manifest

/// Build-Nummer aus „Build 28 · 14.11.2026“.
int buildNummer(String build) => int.tryParse(RegExp(r'Build\s+(\d+)').firstMatch(build)?.group(1) ?? '') ?? 0;

/// Manifest für einen Programmordner schreiben (alle Dateien mit SHA-256).
Future<File> updateManifestSchreiben(String ordner, String build) async {
  final dateien = <String, String>{};
  for (final f in Directory(ordner).listSync(recursive: true).whereType<File>()) {
    final rel = p.relative(f.path, from: ordner).replaceAll(r'\', '/');
    if (rel == 'bauspur_update.json') continue;
    dateien[rel] = sha256Hex(await f.readAsBytes());
  }
  final m = File(p.join(ordner, 'bauspur_update.json'));
  await m.writeAsString(const JsonEncoder.withIndent(' ').convert({'build': build, 'erstellt': DateTime.now().toIso8601String(), 'dateien': dateien}));
  return m;
}

typedef UpdateInfo = ({String build, Map<String, String> dateien, String quelle});

/// Liegt in der Quelle eine neuere Version? (null = nein / keine Quelle)
UpdateInfo? updateSuchen(String quelle, String aktuell) {
  final m = File(p.join(quelle, 'bauspur_update.json'));
  if (!m.existsSync()) return null;
  try {
    final j = jsonDecode(m.readAsStringSync()) as Map<String, dynamic>;
    final build = '${j['build']}';
    if (buildNummer(build) <= buildNummer(aktuell)) return null;
    return (build: build, dateien: {for (final e in (j['dateien'] as Map).entries) '${e.key}': '${e.value}'}, quelle: quelle);
  } catch (_) {
    return null;
  }
}

/// Alle Dateien gegen die Prüfsummen prüfen; liefert die Liste der Fehler.
Future<List<String>> updatePruefen(UpdateInfo u) async {
  final fehler = <String>[];
  for (final e in u.dateien.entries) {
    final f = File(p.join(u.quelle, e.key));
    if (!f.existsSync()) {
      fehler.add('${e.key} fehlt');
    } else if (sha256Hex(await f.readAsBytes()) != e.value) {
      fehler.add('${e.key}: Prüfsumme falsch');
    }
  }
  return fehler;
}

/// Sichert den Programmordner und schreibt das Austausch-Skript (Windows).
/// Danach: Skript starten und das Programm beenden.
Future<({String sicherung, String skript})> updateVorbereiten(UpdateInfo u, {String? programmOrdner, String aktuell = ''}) async {
  final ziel = programmOrdner ?? File(Platform.resolvedExecutable).parent.path;
  final sicherung = p.join(p.dirname(ziel), '${p.basename(ziel)}_Sicherung_${buildNummer(aktuell)}');
  final s = Directory(sicherung);
  if (s.existsSync()) s.deleteSync(recursive: true);
  for (final f in Directory(ziel).listSync(recursive: true).whereType<File>()) {
    final n = File(p.join(sicherung, p.relative(f.path, from: ziel)));
    n.parent.createSync(recursive: true);
    f.copySync(n.path);
  }
  final skript = File(p.join(Directory.systemTemp.path, 'bauspur_update.ps1'));
  await skript.writeAsString('''
param([int]\$warten)
try { Wait-Process -Id \$warten -Timeout 60 -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Milliseconds 500
robocopy "${u.quelle}" "$ziel" /E /R:3 /W:1 /XF bauspur_update.json | Out-Null
Start-Process -FilePath "${p.join(ziel, p.basename(Platform.resolvedExecutable))}"
''');
  return (sicherung: sicherung, skript: skript.path);
}

/// Skript starten (wartet auf das Ende dieses Prozesses) – danach exit().
Future<void> updateStarten(String skript) async {
  await Process.start('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', skript, '$pid'], mode: ProcessStartMode.detached);
}
