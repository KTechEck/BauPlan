import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Einrichtung des lokalen Sprachmodells (Ollama): erkennen, Hardware lesen,
/// Modell empfehlen und laden. Das Modell wird nicht mit BauSpur ausgeliefert.

/// Hardware des PCs: Arbeitsspeicher und Grafikkarte (GB).
typedef Hardware = ({double ramGb, String grafik, double vramGb});

/// Empfehlung eines Modells passend zur Hardware.
typedef ModellEmpfehlung = ({String modell, String groesse, String grund});

/// Modell nach Grafikspeicher bzw. Arbeitsspeicher wählen. Bildverstehen
/// (für Datenblätter und Typenschilder) bringen die „vision“-Modelle mit.
ModellEmpfehlung modellEmpfehlen(Hardware h) {
  if (h.vramGb >= 16) {
    return (modell: 'qwen2.5:14b', groesse: 'ca. 9 GB', grund: 'Grafikkarte mit ${h.vramGb.round()} GB – ein großes Modell läuft flüssig.');
  }
  if (h.vramGb >= 8) {
    return (modell: 'llama3.1:8b', groesse: 'ca. 5 GB', grund: 'Grafikkarte mit ${h.vramGb.round()} GB – ein mittleres Modell läuft flüssig.');
  }
  if (h.ramGb >= 16) {
    return (
      modell: 'llama3.2:3b',
      groesse: 'ca. 2 GB',
      grund: 'Keine starke Grafikkarte, aber ${h.ramGb.round()} GB Arbeitsspeicher – ein kleines Modell läuft auf dem Prozessor (langsamer).'
    );
  }
  return (
    modell: 'llama3.2:1b',
    groesse: 'ca. 1,3 GB',
    grund: 'Wenig Arbeitsspeicher (${h.ramGb.round()} GB) – nur ein sehr kleines Modell; für gute Ergebnisse besser einen stärkeren PC im Heimnetz nutzen.'
  );
}

/// Hardware unter Windows über PowerShell/CIM lesen (ohne Treiberwerkzeuge).
/// Grafikspeicher meldet Windows bei großen Karten oft zu klein (max. 4 GB) –
/// dann zählt der Name der Karte als Hinweis.
Future<Hardware> hardwareLesen() async {
  if (!Platform.isWindows) return (ramGb: 0.0, grafik: 'unbekannt', vramGb: 0.0);
  Future<String> ps(String befehl) async {
    try {
      final r = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', befehl]).timeout(const Duration(seconds: 15));
      return (r.stdout as String).trim();
    } catch (_) {
      return '';
    }
  }

  final ram = double.tryParse(await ps('(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory')) ?? 0;
  final gpu = await ps(r"Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name + '|' + $_.AdapterRAM }");
  var bester = ('unbekannt', 0.0);
  for (final zeile in gpu.split('\n')) {
    final teile = zeile.trim().split('|');
    if (teile.isEmpty || teile.first.isEmpty) continue;
    var vram = (double.tryParse(teile.length > 1 ? teile[1] : '') ?? 0) / 1073741824;
    vram = vramAusName(teile.first) ?? vram;
    if (vram >= bester.$2) bester = (teile.first, vram);
  }
  return (ramGb: ram / 1073741824, grafik: bester.$1, vramGb: bester.$2);
}

/// Grafikspeicher bekannter Karten aus dem Namen (Windows meldet über 4 GB falsch).
double? vramAusName(String name) {
  final n = name.toLowerCase();
  const tabelle = <String, double>{
    '4090': 24, '3090': 24, '4080': 16, '5080': 16, '5090': 32, '4070 ti super': 16, '4060 ti 16': 16, '4070': 12, '3080': 10, '3060': 12,
    '4060': 8, '3070': 8, '2080': 8, '2070': 8, '3050': 8, '1660': 6, '1060': 6, 'rx 7900': 20, 'rx 6800': 16, 'rx 7800': 16, 'rx 6700': 12,
    'rx 7600': 8, 'arc a770': 16, 'arc a750': 8,
  };
  for (final e in tabelle.entries) {
    if (n.contains(e.key)) return e.value;
  }
  return null;
}

/// Läuft Ollama unter [adresse]? Liefert die installierten Modelle oder null.
Future<List<String>?> ollamaModelle(String adresse, {HttpClient? client}) async {
  final c = client ?? HttpClient();
  try {
    final req = await c.getUrl(Uri.parse('${adresse.replaceAll(RegExp(r'/+$'), '')}/api/tags')).timeout(const Duration(seconds: 3));
    final res = await req.close().timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final m = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    return [for (final x in (m['models'] as List? ?? const [])) (x as Map)['name'] as String];
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close(force: true);
  }
}

/// Modell laden (POST /api/pull, gestreamt). Meldet Fortschritt 0 … 1 und Status.
Stream<(double, String)> ollamaLaden(String adresse, String modell, {HttpClient? client}) async* {
  final c = client ?? HttpClient();
  try {
    final req = await c.postUrl(Uri.parse('${adresse.replaceAll(RegExp(r'/+$'), '')}/api/pull'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'name': modell, 'stream': true}));
    final res = await req.close();
    if (res.statusCode != 200) throw HttpException('Ollama antwortet mit ${res.statusCode}');
    await for (final zeile in res.transform(utf8.decoder).transform(const LineSplitter())) {
      if (zeile.trim().isEmpty) continue;
      final m = jsonDecode(zeile) as Map<String, dynamic>;
      if (m['error'] != null) throw HttpException(m['error'] as String);
      final gesamt = (m['total'] as num?)?.toDouble() ?? 0, fertig = (m['completed'] as num?)?.toDouble() ?? 0;
      yield (gesamt > 0 ? fertig / gesamt : 0.0, m['status'] as String? ?? '');
    }
  } finally {
    if (client == null) c.close(force: true);
  }
}

/// Ollama per winget installieren (Windows 10/11). Liefert Ausgabe und Erfolg.
Future<(bool, String)> ollamaInstallieren() async {
  try {
    final r = await Process.run('winget', [
      'install',
      '--id',
      'Ollama.Ollama',
      '-e',
      '--accept-source-agreements',
      '--accept-package-agreements',
    ]).timeout(const Duration(minutes: 15));
    return (r.exitCode == 0, '${r.stdout}\n${r.stderr}'.trim());
  } catch (e) {
    return (false, '$e');
  }
}

/// Webseite im Standardbrowser öffnen.
Future<void> webseiteOeffnen(String url) async {
  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', url]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [url]);
  } else {
    await Process.run('xdg-open', [url]);
  }
}

const ollamaDownload = 'https://ollama.com/download/windows';

// ------------------------------------------------------------ Modellauswahl

/// Ein Sprachmodell zur Auswahl, in Alltagssprache beschrieben.
class ModellInfo {
  const ModellInfo(this.id, this.titel, this.beschreibung, {required this.groesseGb, required this.speicherGb, this.bilder = false});
  final String id;
  final String titel;
  final String beschreibung;
  final double groesseGb; // Download
  final double speicherGb; // benötigter Grafik- bzw. Arbeitsspeicher
  final bool bilder; // versteht Bilder (Datenblätter, Typenschilder, Fotos)
}

const modellKatalog = [
  ModellInfo('llama3.2:3b', 'Klein und schnell', 'Fragen zum Projekt, kurze Prüfungen. Läuft auch ohne Grafikkarte.', groesseGb: 2, speicherGb: 4),
  ModellInfo('llama3.1:8b', 'Ausgewogen (empfohlen)', 'Gute Antworten zur Planung, liest Datenblätter als Text.', groesseGb: 4.9, speicherGb: 8),
  ModellInfo('qwen2.5:14b', 'Groß und genau', 'Beste Ergebnisse bei Tabellen, Normwerten und langen Datenblättern.', groesseGb: 9, speicherGb: 14),
  ModellInfo('gemma3:4b', 'Bilder lesen (klein)', 'Versteht Fotos und gescannte Datenblätter, z. B. Typenschilder.', groesseGb: 3.3, speicherGb: 6, bilder: true),
  ModellInfo('llama3.2-vision:11b', 'Bilder lesen (genau)', 'Liest Pläne, Fotos und Datenblätter als Bild deutlich genauer.', groesseGb: 7.9, speicherGb: 12, bilder: true),
];

enum Eignung { passt, langsam, zuGross }

/// Passt ein Modell zur Hardware? Grafikspeicher zählt voll, sonst läuft es
/// (langsamer) im Arbeitsspeicher.
Eignung eignung(ModellInfo m, Hardware? h) {
  if (h == null || (h.ramGb == 0 && h.vramGb == 0)) return Eignung.passt;
  if (h.vramGb >= m.speicherGb) return Eignung.passt;
  if (h.ramGb >= m.speicherGb * 2) return Eignung.langsam;
  return Eignung.zuGross;
}

/// Vorauswahl: das größte passende Textmodell (+ kein Bildmodell).
List<String> modelleVorschlagen(Hardware? h) {
  final text = modellKatalog.where((m) => !m.bilder).toList();
  final passend = text.where((m) => eignung(m, h) == Eignung.passt).toList();
  if (passend.isNotEmpty) return [passend.last.id];
  final langsam = text.where((m) => eignung(m, h) == Eignung.langsam).toList();
  return [(langsam.isEmpty ? text.first : langsam.first).id];
}

// ------------------------------------------------------------ Heimnetz

/// Eigene IPv4-Adressen im Heimnetz.
Future<List<String>> eigeneAdressen() async {
  try {
    final l = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final n in l)
        for (final a in n.addresses)
          if (!a.isLoopback && (a.address.startsWith('192.168.') || a.address.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a.address))) a.address,
    ];
  } catch (_) {
    return const [];
  }
}

/// Im eigenen /24-Netz nach Ollama-Servern suchen (Port 11434).
Future<List<String>> heimnetzSuchen({int port = 11434, Duration timeout = const Duration(milliseconds: 400)}) async {
  final gefunden = <String>[];
  for (final eigene in await eigeneAdressen()) {
    final netz = eigene.substring(0, eigene.lastIndexOf('.'));
    await Future.wait([
      for (var i = 1; i < 255; i++)
        () async {
          final ip = '$netz.$i';
          try {
            final s = await Socket.connect(ip, port, timeout: timeout);
            s.destroy();
            final adresse = 'http://$ip:$port';
            if (await ollamaModelle(adresse) != null) gefunden.add(adresse);
          } catch (_) {}
        }(),
    ]);
  }
  return gefunden..sort();
}

/// Ollama auf diesem PC starten, falls installiert aber nicht aktiv; wartet bis erreichbar.
Future<bool> ollamaStarten(String adresse, {Duration warten = const Duration(seconds: 40)}) async {
  if (await ollamaModelle(adresse) != null) return true;
  try {
    await Process.start('ollama', ['serve'], mode: ProcessStartMode.detached, runInShell: true);
  } catch (_) {
    // Startmenü-Verknüpfung als Ausweg
    final pfad = ollamaPfad('ollama app.exe');
    if (File(pfad).existsSync()) await Process.start(pfad, const [], mode: ProcessStartMode.detached);
  }
  final ende = DateTime.now().add(warten);
  while (DateTime.now().isBefore(ende)) {
    if (await ollamaModelle(adresse) != null) return true;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return false;
}

/// Ist Ollama auf diesem PC installiert?
Future<bool> ollamaInstalliert() async {
  try {
    final r = await Process.run('where', ['ollama'], runInShell: true);
    if (r.exitCode == 0) return true;
  } catch (_) {}
  final pfad = ollamaPfad('ollama.exe');
  return File(pfad).existsSync();
}

/// Arten von Servern im Heimnetz.
enum ServerArt {
  linux('Linux-PC / Mini-PC (SSH)'),
  synology('Synology / NAS mit Docker'),
  windows('Windows-PC');

  const ServerArt(this.label);
  final String label;
}

/// Befehl, der Ollama auf dem Server einrichtet und im Heimnetz freigibt.
String serverBefehl(ServerArt a) => switch (a) {
      ServerArt.linux => 'curl -fsSL https://ollama.com/install.sh | sh && '
          'sudo mkdir -p /etc/systemd/system/ollama.service.d && '
          "printf '[Service]\nEnvironment=\"OLLAMA_HOST=0.0.0.0:11434\"\n' | sudo tee /etc/systemd/system/ollama.service.d/heimnetz.conf && "
          'sudo systemctl daemon-reload && sudo systemctl restart ollama',
      ServerArt.synology => 'docker run -d --name ollama --restart unless-stopped -p 11434:11434 -v /volume1/docker/ollama:/root/.ollama ollama/ollama',
      ServerArt.windows => 'winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements; '
          'setx OLLAMA_HOST 0.0.0.0:11434; '
          'netsh advfirewall firewall add rule name="Ollama" dir=in action=allow protocol=TCP localport=11434',
    };

/// Server per SSH einrichten (nur mit hinterlegtem Schlüssel, ohne Passwortabfrage).
Future<(bool, String)> perSshEinrichten(String ziel) async {
  try {
    final r = await Process.run('ssh', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'StrictHostKeyChecking=accept-new', ziel, serverBefehl(ServerArt.linux)])
        .timeout(const Duration(minutes: 15));
    return (r.exitCode == 0, '${r.stdout}\n${r.stderr}'.trim());
  } catch (e) {
    return (false, '$e');
  }
}

/// Pfad im Installationsordner von Ollama (Benutzerinstallation).
String ollamaPfad(String datei) => [Platform.environment['LOCALAPPDATA'] ?? '', 'Programs', 'Ollama', datei].join(Platform.pathSeparator);
