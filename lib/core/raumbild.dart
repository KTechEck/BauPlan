import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// KI-Raumbilder über eine austauschbare Schnittstelle: aus Raumdaten und
/// einer Planskizze als Vorlage entsteht ein Bild. Anbieter: OpenAI (Standard,
/// gpt-image-1), Google Gemini (Bildmodell) oder ein eigenes ComfyUI im Heimnetz.
/// Schlüssel liegen nur in den Programmeinstellungen dieses PCs.

abstract class RaumbildAnbieter {
  String get name;

  /// Grobe Kosten je Bild in Euro je Qualität (niedrig, mittel, hoch); 0 = lokal.
  double kosten(String qualitaet);

  /// Bild erzeugen (PNG/JPEG-Bytes). [vorlage] = Planskizze als PNG (optional).
  Future<Uint8List> erzeugen({required String prompt, Uint8List? vorlage, String qualitaet = 'mittel', String format = 'quer'});
}

class RaumbildFehler implements Exception {
  RaumbildFehler(this.text);
  final String text;
  @override
  String toString() => text;
}

String _grenze() => '----bauspur${DateTime.now().microsecondsSinceEpoch}${math.Random().nextInt(1 << 30)}';

/// multipart/form-data von Hand (Felder + Dateien).
({List<int> body, String typ}) multipart(Map<String, String> felder, Map<String, (String name, String mime, List<int> daten)> dateien) {
  final g = _grenze();
  final b = BytesBuilder();
  void z(String s) => b.add(utf8.encode(s));
  for (final e in felder.entries) {
    z('--$g\r\nContent-Disposition: form-data; name="${e.key}"\r\n\r\n${e.value}\r\n');
  }
  for (final e in dateien.entries) {
    z('--$g\r\nContent-Disposition: form-data; name="${e.key}"; filename="${e.value.$1}"\r\nContent-Type: ${e.value.$2}\r\n\r\n');
    b.add(e.value.$3);
    z('\r\n');
  }
  z('--$g--\r\n');
  return (body: b.toBytes(), typ: 'multipart/form-data; boundary=$g');
}

Future<String> _senden(HttpClient c, String methode, Uri uri, {Map<String, String> kopf = const {}, List<int>? body, Duration warten = const Duration(minutes: 3)}) async {
  final r = await c.openUrl(methode, uri).timeout(const Duration(seconds: 20));
  kopf.forEach(r.headers.set);
  if (body != null) {
    r.contentLength = body.length;
    r.add(body);
  }
  final a = await r.close().timeout(warten);
  final text = await a.transform(utf8.decoder).join();
  if (a.statusCode >= 300) {
    var meldung = text;
    try {
      final j = jsonDecode(text);
      meldung = '${(j as Map)['error'] is Map ? (j['error'] as Map)['message'] : j['error'] ?? text}';
    } catch (_) {}
    throw RaumbildFehler('${a.statusCode}: ${meldung.length > 300 ? meldung.substring(0, 300) : meldung}');
  }
  return text;
}

// ------------------------------------------------------------------ OpenAI

class OpenAiBild implements RaumbildAnbieter {
  OpenAiBild(this.schluessel, {this.modell = 'gpt-image-1', HttpClient? client}) : _c = client ?? HttpClient();
  final String schluessel, modell;
  final HttpClient _c;

  @override
  String get name => 'OpenAI ($modell)';

  @override
  double kosten(String q) => switch (q) { 'niedrig' => 0.02, 'hoch' => 0.25, _ => 0.07 };

  @override
  Future<Uint8List> erzeugen({required String prompt, Uint8List? vorlage, String qualitaet = 'mittel', String format = 'quer'}) async {
    if (schluessel.trim().isEmpty) throw RaumbildFehler('Kein OpenAI-API-Schlüssel eingetragen (Einstellungen › KI-Raumbilder).');
    final size = format == 'quer' ? '1536x1024' : (format == 'hoch' ? '1024x1536' : '1024x1024');
    final quality = switch (qualitaet) { 'niedrig' => 'low', 'hoch' => 'high', _ => 'medium' };
    final String text;
    if (vorlage != null) {
      final m = multipart({'model': modell, 'prompt': prompt, 'size': size, 'quality': quality, 'n': '1'}, {'image': ('plan.png', 'image/png', vorlage)});
      text = await _senden(_c, 'POST', Uri.parse('https://api.openai.com/v1/images/edits'),
          kopf: {'Authorization': 'Bearer $schluessel', 'Content-Type': m.typ}, body: m.body);
    } else {
      text = await _senden(_c, 'POST', Uri.parse('https://api.openai.com/v1/images/generations'),
          kopf: {'Authorization': 'Bearer $schluessel', 'Content-Type': 'application/json'},
          body: utf8.encode(jsonEncode({'model': modell, 'prompt': prompt, 'size': size, 'quality': quality, 'n': 1})));
    }
    return openAiAntwortLesen(text);
  }
}

Uint8List openAiAntwortLesen(String text) {
  final j = jsonDecode(text) as Map<String, dynamic>;
  final d = (j['data'] as List?)?.firstOrNull as Map?;
  final b64 = d?['b64_json'] as String?;
  if (b64 == null) throw RaumbildFehler('Antwort ohne Bild.');
  return base64Decode(b64);
}

// ------------------------------------------------------------------ Gemini

class GeminiBild implements RaumbildAnbieter {
  GeminiBild(this.schluessel, {this.modell = 'gemini-2.5-flash-image', HttpClient? client}) : _c = client ?? HttpClient();
  final String schluessel, modell;
  final HttpClient _c;

  @override
  String get name => 'Google Gemini ($modell)';

  @override
  double kosten(String q) => 0.04;

  @override
  Future<Uint8List> erzeugen({required String prompt, Uint8List? vorlage, String qualitaet = 'mittel', String format = 'quer'}) async {
    if (schluessel.trim().isEmpty) throw RaumbildFehler('Kein Gemini-API-Schlüssel eingetragen (Einstellungen › KI-Raumbilder).');
    final teile = [
      {'text': prompt},
      if (vorlage != null) {'inline_data': {'mime_type': 'image/png', 'data': base64Encode(vorlage)}},
    ];
    final text = await _senden(_c, 'POST', Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$modell:generateContent'),
        kopf: {'x-goog-api-key': schluessel, 'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({
          'contents': [
            {'parts': teile}
          ]
        })));
    return geminiAntwortLesen(text);
  }
}

Uint8List geminiAntwortLesen(String text) {
  final j = jsonDecode(text) as Map<String, dynamic>;
  for (final k in (j['candidates'] as List? ?? const [])) {
    for (final p in (((k as Map)['content'] as Map?)?['parts'] as List? ?? const [])) {
      final d = (p as Map)['inline_data'] ?? p['inlineData'];
      if (d is Map && d['data'] is String) return base64Decode(d['data'] as String);
    }
  }
  throw RaumbildFehler('Antwort ohne Bild (eventuell vom Dienst abgelehnt).');
}

// ----------------------------------------------------------------- ComfyUI

/// Eigenes ComfyUI im Heimnetz: Arbeitsablauf (API-Format, JSON) mit den
/// Platzhaltern %PROMPT% und optional %BILD% (Dateiname der hochgeladenen Vorlage).
class ComfyUiBild implements RaumbildAnbieter {
  ComfyUiBild(this.adresse, this.workflow, {HttpClient? client}) : _c = client ?? HttpClient();
  final String adresse, workflow;
  final HttpClient _c;

  @override
  String get name => 'ComfyUI (lokal)';

  @override
  double kosten(String q) => 0;

  @override
  Future<Uint8List> erzeugen({required String prompt, Uint8List? vorlage, String qualitaet = 'mittel', String format = 'quer'}) async {
    if (adresse.isEmpty || workflow.isEmpty) throw RaumbildFehler('ComfyUI: Adresse und Arbeitsablauf (JSON) in den Einstellungen angeben.');
    final basis = adresse.startsWith('http') ? adresse.replaceAll(RegExp(r'/+$'), '') : 'http://$adresse';
    var bildName = '';
    if (vorlage != null) {
      final m = multipart({'overwrite': 'true'}, {'image': ('bauspur_vorlage.png', 'image/png', vorlage)});
      final t = await _senden(_c, 'POST', Uri.parse('$basis/upload/image'), kopf: {'Content-Type': m.typ}, body: m.body);
      bildName = '${(jsonDecode(t) as Map)['name'] ?? 'bauspur_vorlage.png'}';
    }
    final wf = File(workflow).readAsStringSync().replaceAll('%PROMPT%', jsonEncode(prompt).replaceAll(RegExp(r'^"|"$'), '')).replaceAll('%BILD%', bildName);
    final t = await _senden(_c, 'POST', Uri.parse('$basis/prompt'),
        kopf: {'Content-Type': 'application/json'}, body: utf8.encode(jsonEncode({'prompt': jsonDecode(wf)})));
    final id = '${(jsonDecode(t) as Map)['prompt_id']}';
    for (var i = 0; i < 180; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final h = jsonDecode(await _senden(_c, 'GET', Uri.parse('$basis/history/$id'))) as Map;
      final eintrag = h[id] as Map?;
      if (eintrag == null) continue;
      for (final o in ((eintrag['outputs'] as Map?) ?? const {}).values) {
        for (final b in ((o as Map)['images'] as List? ?? const [])) {
          final m = b as Map;
          final uri = Uri.parse('$basis/view').replace(queryParameters: {'filename': '${m['filename']}', 'subfolder': '${m['subfolder'] ?? ''}', 'type': '${m['type'] ?? 'output'}'});
          final r = await _c.getUrl(uri);
          final a = await r.close();
          final bb = BytesBuilder();
          await for (final x in a) {
            bb.add(x);
          }
          return bb.toBytes();
        }
      }
    }
    throw RaumbildFehler('ComfyUI hat nach 6 Minuten kein Bild geliefert.');
  }
}

// ------------------------------------------------------------------ Prompt

/// Raumdaten für den Prompt.
typedef RaumbildDaten = ({
  String raum,
  double flaecheM2,
  double breiteM,
  double tiefeM,
  double hoeheM,
  int fenster,
  int tueren,
  List<String> ausstattung,
  List<String> oberflaechen,
});

const raumbildStile = ['modern', 'skandinavisch', 'Landhaus', 'Industrial', 'minimalistisch', 'warm und gemütlich', 'Altbau saniert'];

/// Prompt (Englisch – Bildmodelle verstehen das am zuverlässigsten).
String raumbildPrompt(RaumbildDaten d, {String stil = 'modern', String tageszeit = 'Tag', String wuensche = '', bool mitVorlage = true}) {
  final s = StringBuffer('Photorealistic interior photograph of a ${_raumEn(d.raum)} (${d.raum}), ')
    ..write('about ${d.breiteM.toStringAsFixed(1)} m × ${d.tiefeM.toStringAsFixed(1)} m (${d.flaecheM2.toStringAsFixed(0)} m²), ceiling height ${d.hoeheM.toStringAsFixed(2)} m, ')
    ..write('${d.fenster} window${d.fenster == 1 ? '' : 's'}, ${d.tueren} door${d.tueren == 1 ? '' : 's'}. ')
    ..write('Style: ${_stilEn(stil)}. ');
  if (d.oberflaechen.isNotEmpty) s.write('Surfaces: ${d.oberflaechen.join(', ')}. ');
  if (d.ausstattung.isNotEmpty) s.write('Planned fixtures (keep their positions): ${d.ausstattung.join(', ')}. ');
  if (mitVorlage) s.write('Use the attached floor plan sketch for room shape, window/door positions and fixture placement. ');
  s.write(tageszeit == 'Abend' ? 'Evening, warm artificial lighting. ' : 'Daylight through the windows. ');
  if (wuensche.trim().isNotEmpty) s.write('Additional wishes: ${wuensche.trim()}. ');
  s.write('Eye-level wide-angle view, realistic proportions, no text, no people.');
  return s.toString();
}

String _raumEn(String n) {
  final l = n.toLowerCase();
  for (final (k, v) in const [
    ('bad', 'bathroom'), ('dusch', 'shower room'), ('wc', 'guest toilet'), ('küche', 'kitchen'), ('wohn', 'living room'), ('ess', 'dining room'),
    ('schlaf', 'bedroom'), ('kind', "children's room"), ('büro', 'home office'), ('arbeit', 'home office'), ('flur', 'hallway'), ('diele', 'entrance hall'),
    ('hwr', 'utility room'), ('technik', 'technical room'), ('keller', 'basement room'), ('gäste', 'guest room'), ('ankleide', 'walk-in closet'),
  ]) {
    if (l.contains(k)) return v;
  }
  return 'room';
}

String _stilEn(String s) => switch (s) {
      'skandinavisch' => 'Scandinavian, light wood, white walls',
      'Landhaus' => 'country house style, natural materials',
      'Industrial' => 'industrial loft, concrete, black metal',
      'minimalistisch' => 'minimalist, clean lines',
      'warm und gemütlich' => 'warm and cozy, textiles, warm colors',
      'Altbau saniert' => 'renovated old building, stucco details, wooden floor',
      _ => 'modern contemporary',
    };
