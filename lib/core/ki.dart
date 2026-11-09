import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// KI-Assistent: anbieterneutrale Schnittstelle. Standard ist ein lokales
/// Sprachmodell im Heimnetz (Ollama-kompatible API); ein Cloud-Dienst wird nur
/// benutzt, wenn er ausdrücklich eingeschaltet ist. Der Assistent liest nur und
/// schlägt vor – Änderungen übernimmt immer der Mensch.
abstract class KiAnbieter {
  String get name;

  /// Läuft der Dienst außerhalb des Heimnetzes? Dann muss vor dem Senden
  /// angezeigt werden, was das Heimnetz verlässt.
  bool get extern;

  Future<String> fragen(String system, String frage);
}

/// Einstellungen für den Assistenten (Programmeinstellungen bzw. Projekt).
class KiEinstellung {
  const KiEinstellung({this.adresse = 'http://localhost:11434', this.modell = 'llama3.1:8b', this.cloudErlaubt = false});
  final String adresse;
  final String modell;
  final bool cloudErlaubt;

  /// Liegt die Adresse im Heimnetz (localhost, private Adressbereiche, .local)?
  bool get lokal => adresseLokal(adresse);

  Map<String, dynamic> toJson() => {'adresse': adresse, 'modell': modell, 'cloud': cloudErlaubt};
  static KiEinstellung ausJson(Map<String, dynamic>? m) => m == null
      ? const KiEinstellung()
      : KiEinstellung(
          adresse: m['adresse'] as String? ?? 'http://localhost:11434',
          modell: m['modell'] as String? ?? 'llama3.1:8b',
          cloudErlaubt: m['cloud'] as bool? ?? false,
        );
}

bool adresseLokal(String adresse) {
  final host = Uri.tryParse(adresse)?.host.toLowerCase() ?? '';
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1' || host.endsWith('.local') || host.endsWith('.lan') || host.endsWith('.fritz.box')) {
    return true;
  }
  final teile = host.split('.').map(int.tryParse).toList();
  if (teile.length == 4 && teile.every((t) => t != null)) {
    final a = teile[0]!, b = teile[1]!;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }
  return false;
}

/// Ollama-kompatibler Anbieter (POST /api/chat, ohne Streaming).
class OllamaAnbieter implements KiAnbieter {
  OllamaAnbieter(this.einstellung, {HttpClient? client}) : _client = client ?? HttpClient();
  final KiEinstellung einstellung;
  final HttpClient _client;

  @override
  String get name => 'Sprachmodell ${einstellung.modell} (${Uri.tryParse(einstellung.adresse)?.host ?? einstellung.adresse})';

  @override
  bool get extern => !einstellung.lokal;

  @override
  Future<String> fragen(String system, String frage) async {
    if (extern && !einstellung.cloudErlaubt) {
      throw StateError('Die Adresse liegt nicht im Heimnetz und Cloud-Dienste sind ausgeschaltet.');
    }
    final uri = Uri.parse('${einstellung.adresse.replaceAll(RegExp(r'/+$'), '')}/api/chat');
    final anfrage = await _client.postUrl(uri).timeout(const Duration(seconds: 10));
    anfrage.headers.contentType = ContentType.json;
    anfrage.write(jsonEncode({
      'model': einstellung.modell,
      'stream': false,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': frage},
      ],
    }));
    final antwort = await anfrage.close().timeout(const Duration(minutes: 3));
    final text = await antwort.transform(utf8.decoder).join();
    if (antwort.statusCode != 200) throw HttpException('KI-Dienst antwortet mit ${antwort.statusCode}: $text');
    final m = jsonDecode(text) as Map<String, dynamic>;
    return ((m['message'] as Map?)?['content'] as String? ?? '').trim();
  }
}

/// Frage mit Bildern an ein Ollama-Modell mit Bildverstehen (z. B. Kassenzettel,
/// Typenschild). [modell] ist das Bildmodell aus der Einrichtung.
Future<String> ollamaBildFrage(KiEinstellung e, String modell, String frage, List<List<int>> bilder, {HttpClient? client}) async {
  if (!e.lokal && !e.cloudErlaubt) throw StateError('Die Adresse liegt nicht im Heimnetz und Cloud-Dienste sind ausgeschaltet.');
  final c = client ?? HttpClient();
  try {
    final anfrage = await c.postUrl(Uri.parse('${e.adresse.replaceAll(RegExp(r'/+$'), '')}/api/chat')).timeout(const Duration(seconds: 10));
    anfrage.headers.contentType = ContentType.json;
    anfrage.write(jsonEncode({
      'model': modell,
      'stream': false,
      'messages': [
        {'role': 'user', 'content': frage, 'images': [for (final b in bilder) base64Encode(b)]},
      ],
    }));
    final antwort = await anfrage.close().timeout(const Duration(minutes: 5));
    final text = await antwort.transform(utf8.decoder).join();
    if (antwort.statusCode != 200) throw HttpException('KI-Dienst antwortet mit ${antwort.statusCode}: $text');
    final m = jsonDecode(text) as Map<String, dynamic>;
    return ((m['message'] as Map?)?['content'] as String? ?? '').trim();
  } finally {
    if (client == null) c.close(force: true);
  }
}

/// Systemanweisung für Planprüfungen und Fragen.
const kiSystem = 'Du bist der Assistent in BauSpur, einer Software zur Planung und Dokumentation von Gebäudesanierungen. '
    'Antworte auf Deutsch, knapp und konkret. Du hast nur Lesezugriff: Schlage Änderungen vor, nimm sie nie selbst vor. '
    'Kennzeichne Einschätzungen als solche. Elektro-, Gas- und Kältetechnik bleiben in der Verantwortung der Fachkraft; '
    'nenne keine Normtexte wörtlich.';

// ============================================================ Planprüfung

/// Ein Prüfhinweis: Quelle „Regel“ (exakt gerechnet) oder „KI“ (Einschätzung),
/// Bereich, betroffenes Objekt (optional) und Text.
class PruefHinweis {
  const PruefHinweis({required this.bereich, required this.text, this.objektId, this.ki = false, this.begruendung});
  final String bereich;
  final String text;
  final String? objektId;
  final bool ki;
  final String? begruendung;

  /// Stabiler Schlüssel für den Status (erledigt/ignoriert/bewusst so geplant).
  String get schluessel => '$bereich|$text';
}

const pruefStatus = {'offen': 'offen', 'erledigt': 'erledigt', 'ignoriert': 'ignoriert', 'bewusst': 'bewusst so geplant'};

/// Eigene Grenzwerte für die festen Regeln (Projekteinstellung `regeln`).
class Regelwerte {
  const Regelwerte({this.maxKreislaengeM = 120, this.minReserveSchrank = 20, this.minAbstandWasserElektro = 300, this.lichtAnteilZiel = 60});
  final int maxKreislaengeM;
  final int minReserveSchrank; // %
  final int minAbstandWasserElektro; // mm
  final int lichtAnteilZiel; // % des Zielwerts, darunter Hinweis

  Map<String, dynamic> toJson() => {
        'kreis_m': maxKreislaengeM,
        'reserve': minReserveSchrank,
        'abstand_we': minAbstandWasserElektro,
        'licht': lichtAnteilZiel,
      };
  static Regelwerte ausJson(Map<String, dynamic>? m) => m == null
      ? const Regelwerte()
      : Regelwerte(
          maxKreislaengeM: (m['kreis_m'] as num?)?.toInt() ?? 120,
          minReserveSchrank: (m['reserve'] as num?)?.toInt() ?? 20,
          minAbstandWasserElektro: (m['abstand_we'] as num?)?.toInt() ?? 300,
          lichtAnteilZiel: (m['licht'] as num?)?.toInt() ?? 60,
        );
}

/// Antwort des Sprachmodells in einzelne Einschätzungen zerlegen (Aufzählungen).
List<PruefHinweis> kiHinweiseLesen(String antwort, {String bereich = 'Einschätzung'}) {
  final zeilen = antwort.split('\n').map((z) => z.trim()).where((z) => z.isNotEmpty);
  final punkte = [
    for (final z in zeilen)
      if (RegExp(r'^([-*•]|\d+[.)])\s+').hasMatch(z)) z.replaceFirst(RegExp(r'^([-*•]|\d+[.)])\s+'), ''),
  ];
  final liste = punkte.isEmpty ? [antwort.trim()] : punkte;
  return [for (final p in liste) if (p.isNotEmpty) PruefHinweis(bereich: bereich, text: p, ki: true)];
}

/// Einfache Suche ohne Sprachmodell: Wörter der Frage gegen Einträge
/// (Text → Ergebnis), sortiert nach Anzahl der Treffer.
List<T> stichwortSuche<T>(String frage, Map<String, T> eintraege) {
  final woerter = frage
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zäöüß0-9 ]'), ' ')
      .split(' ')
      .where((w) => w.length >= 3 && !_fuellwoerter.contains(w))
      .toList();
  if (woerter.isEmpty) return const [];
  final bewertet = <(T, int)>[];
  eintraege.forEach((text, wert) {
    final t = text.toLowerCase();
    final n = woerter.where((w) => t.contains(w) || (w.length > 4 && t.contains(w.substring(0, w.length - 1)))).length;
    if (n > 0) bewertet.add((wert, n));
  });
  bewertet.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (w, _) in bewertet) w];
}

const _fuellwoerter = {'welche', 'welcher', 'welches', 'gehen', 'geht', 'liegt', 'liegen', 'sind', 'die', 'der', 'das', 'den', 'dem', 'ins', 'wo', 'wie', 'was', 'und', 'oder', 'mit', 'von', 'zum', 'zur', 'im', 'in'};
