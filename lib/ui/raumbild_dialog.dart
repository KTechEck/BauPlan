import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/theme.dart';
import '../core/raumbild.dart';
import '../core/raumerkennung.dart';
import '../data/models.dart';
import '../data/project_store.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Anbieter aus den Programmeinstellungen.
RaumbildAnbieter raumbildAnbieter(Map<String, dynamic>? e) => switch (e?['anbieter']) {
      'gemini' => GeminiBild('${e?['gemini_key'] ?? ''}'),
      'comfyui' => ComfyUiBild('${e?['comfy_adresse'] ?? ''}', '${e?['comfy_workflow'] ?? ''}'),
      _ => OpenAiBild('${e?['openai_key'] ?? ''}'),
    };

/// Raumdaten für den Prompt aus dem Projekt.
RaumbildDaten raumbildDaten(ProjectStore store, Raum r) {
  final g = store.geschoss(r.geschossId)!;
  final u = r.umriss!;
  final xs = u.map((q) => q.x), ys = u.map((q) => q.y);
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final objekte = [for (final o in store.objekte(r.geschossId)) if (o.raumId == r.id || (o.punkte.isNotEmpty && punktInPolygon(o.punkte.first, u))) o];
  final zaehl = <String, int>{};
  for (final o in objekte) {
    final n = typen[o.typId]?.name;
    if (n == null || const {'Leitung', 'Leerrohr', 'Busleitung', 'Signalleitung', 'Netzwerkkabel'}.contains(n)) continue;
    zaehl[n] = (zaehl[n] ?? 0) + 1;
  }
  final waende = {for (final w in store.waende(r.geschossId)) w.id: w};
  var fenster = 0, tueren = 0;
  for (final o in store.oeffnungen(r.geschossId)) {
    final w = waende[o.wandId];
    if (w == null || w.laenge < 1) continue;
    final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge, t = o.abstand + o.breite / 2, d = w.dicke / 2 + 60;
    final m = Punkt(w.x1 + ux * t, w.y1 + uy * t);
    if (!punktInPolygon(Punkt(m.x - uy * d, m.y + ux * d), u) && !punktInPolygon(Punkt(m.x + uy * d, m.y - ux * d), u)) continue;
    o.art == OeffnungsArt.fenster ? fenster++ : (o.art == OeffnungsArt.nische ? null : tueren++);
  }
  final ob = <String>[];
  final oe = r.eigenschaften['oberflaechen'];
  if (oe is Map) {
    for (final e in oe.entries) {
      final l = e.value is List ? (e.value as List) : const [];
      final t = [for (final x in l) if (x is Map && '${x['text'] ?? ''}'.isNotEmpty) '${x['text']}'];
      if (t.isNotEmpty) ob.add('${e.key}: ${t.join(', ')}');
    }
  }
  return (
    raum: r.name,
    flaecheM2: polygonFlaeche(u).abs() / 1e6,
    breiteM: (xs.reduce(math.max) - xs.reduce(math.min)) / 1000,
    tiefeM: (ys.reduce(math.max) - ys.reduce(math.min)) / 1000,
    hoeheM: ((r.ukDecke ?? r.hoehen(g).rohdecke) - r.hoehen(g).ffb) / 1000,
    fenster: fenster,
    tueren: tueren,
    ausstattung: [for (final e in zaehl.entries) '${e.value}× ${e.key}'],
    oberflaechen: ob,
  );
}

/// Planskizze des Raums als PNG (Vorlage für das Bildmodell).
Future<Uint8List> raumSkizze(ProjectStore store, Raum r) async {
  const groesse = 1024.0;
  final u = r.umriss!;
  final xs = u.map((q) => q.x), ys = u.map((q) => q.y);
  final x0 = xs.reduce(math.min) - 600, y0 = ys.reduce(math.min) - 600, x1 = xs.reduce(math.max) + 600, y1 = ys.reduce(math.max) + 600;
  final m = groesse / math.max(x1 - x0, y1 - y0);
  Offset s(double x, double y) => Offset((x - x0) * m, (y - y0) * m);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, groesse, groesse), Paint()..color = Colors.white);
  c.drawPath(Path()..addPolygon([for (final q in u) s(q.x, q.y)], true), Paint()..color = const Color(0xFFF3F0EA));
  final waende = store.waende(r.geschossId);
  for (final w in waende) {
    if (w.laenge < 1) continue;
    final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge, h = w.dicke / 2;
    c.drawPath(
        Path()
          ..addPolygon([s(w.x1 - uy * h, w.y1 + ux * h), s(w.x2 - uy * h, w.y2 + ux * h), s(w.x2 + uy * h, w.y2 - ux * h), s(w.x1 + uy * h, w.y1 - ux * h)], true),
        Paint()..color = const Color(0xFF333333));
  }
  void text(String t, Offset o, {double gr = 18, Color farbe = Colors.black}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: gr, color: farbe, fontFamily: 'Roboto')), textDirection: TextDirection.ltr)..layout(maxWidth: 260);
    tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
  }

  final wn = {for (final w in waende) w.id: w};
  for (final o in store.oeffnungen(r.geschossId)) {
    final w = wn[o.wandId];
    if (w == null || w.laenge < 1) continue;
    final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge, h = w.dicke / 2 + 5;
    final a = o.abstand.toDouble(), b = (o.abstand + o.breite).toDouble();
    final farbe = o.art == OeffnungsArt.fenster ? const Color(0xFF74C0FC) : const Color(0xFFFFE066);
    c.drawPath(
        Path()..addPolygon([s(w.x1 + ux * a - uy * h, w.y1 + uy * a + ux * h), s(w.x1 + ux * b - uy * h, w.y1 + uy * b + ux * h), s(w.x1 + ux * b + uy * h, w.y1 + uy * b - ux * h), s(w.x1 + ux * a + uy * h, w.y1 + uy * a - ux * h)], true),
        Paint()..color = farbe);
  }
  final typen = {for (final t in store.objekttypen()) t.id: t};
  for (final o in store.objekte(r.geschossId)) {
    if (o.punkte.isEmpty || !(o.raumId == r.id || punktInPolygon(o.punkte.first, u))) continue;
    final t = typen[o.typId];
    if (t == null) continue;
    if (o.punkte.length >= 3) {
      c.drawPath(Path()..addPolygon([for (final q in o.punkte) s(q.x, q.y)], true), Paint()..color = const Color(0x5574C0FC));
      final mp = punktImInneren(o.punkte);
      text(t.name, s(mp.x, mp.y), gr: 14);
    } else if (o.punkte.length == 1) {
      final q = s(o.punkte.first.x, o.punkte.first.y);
      c.drawCircle(q, 8, Paint()..color = const Color(0xFFE8590C));
      text(t.name, q + const Offset(0, 16), gr: 12, farbe: const Color(0xFF9A3412));
    }
  }
  final mp = punktImInneren(u);
  text(r.name, s(mp.x, mp.y), gr: 26);
  final bild = await rec.endRecording().toImage(groesse.toInt(), groesse.toInt());
  return (await bild.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Future<void> raumbildDialog(BuildContext context, AppState s) => showDialog<void>(context: context, builder: (_) => Dialog(child: SizedBox(width: 1000, height: 700, child: _Raumbild(state: s))));

class _Raumbild extends StatefulWidget {
  const _Raumbild({required this.state});
  final AppState state;
  @override
  State<_Raumbild> createState() => _RaumbildState();
}

class _RaumbildState extends State<_Raumbild> {
  String? _raumId;
  String _stil = 'modern', _tageszeit = 'Tag', _qualitaet = 'mittel';
  bool _mitVorlage = true, _laeuft = false;
  final _wuensche = TextEditingController();
  final _prompt = TextEditingController();
  bool _promptVonHand = false;
  String? _fehler;
  String? _bild;
  Future<Uint8List>? _skizze;
  String? _skizzeRaum;

  AppState get _s => widget.state;
  Map<String, dynamic> get _e => _s.settings.bildki ?? {};
  void _setzen(String k, Object? v) {
    _s.settings.bildki = {..._e, k: v}..removeWhere((k, v) => v == null || v == '');
    _s.settings.speichern();
    setState(() {});
  }

  /// Skizze je Raum nur einmal rendern.
  Future<Uint8List> _skizzeFuer(ProjectStore store, Raum r) {
    if (_skizzeRaum != r.id || _skizze == null) {
      _skizzeRaum = r.id;
      _skizze = raumSkizze(store, r);
    }
    return _skizze!;
  }

  Directory _ordner() => Directory(p.join(_s.store!.ordner, 'ki_bilder'));

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final raeume = [for (final r in store.raeume(_s.geschossId ?? '')) if (r.umriss != null && r.art == RaumArt.raum) r];
    if (raeume.isEmpty) return const Center(child: Text('Keine Räume im Geschoss.'));
    final r = raeume.where((x) => x.id == _raumId).firstOrNull ?? raeume.first;
    final daten = raumbildDaten(store, r);
    if (!_promptVonHand) _prompt.text = raumbildPrompt(daten, stil: _stil, tageszeit: _tageszeit, wuensche: _wuensche.text, mitVorlage: _mitVorlage);
    final anbieter = raumbildAnbieter(_e);
    final extern = _e['anbieter'] != 'comfyui';
    final erlaubt = !extern || _e['extern_ok'] == true;
    final alte = _ordner().existsSync()
        ? ([for (final f in _ordner().listSync().whereType<File>()) if (p.basename(f.path).startsWith('${r.kuerzel}_')) f]..sort((a, b) => b.path.compareTo(a.path)))
        : <File>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('KI-Raumbild'),
        automaticallyImplyLeading: false,
        actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))],
      ),
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 420,
          child: ListView(padding: const EdgeInsets.all(14), children: [
            DropdownButtonFormField<String>(
              initialValue: r.id,
              decoration: const InputDecoration(labelText: 'Raum', isDense: true),
              items: [for (final x in raeume) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: (v) => setState(() {
                _raumId = v;
                _promptVonHand = false;
                _bild = null;
              }),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final st in raumbildStile) ChoiceChip(label: Text(st), selected: _stil == st, onSelected: (_) => setState(() {
                _stil = st;
                _promptVonHand = false;
              })),
            ]),
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Licht: '),
              ChoiceChip(label: const Text('Tag'), selected: _tageszeit == 'Tag', onSelected: (_) => setState(() => _tageszeit = 'Tag')),
              ChoiceChip(label: const Text('Abend'), selected: _tageszeit == 'Abend', onSelected: (_) => setState(() => _tageszeit = 'Abend')),
              const Text('  Planskizze'),
              Switch(value: _mitVorlage, onChanged: (v) => setState(() => _mitVorlage = v)),
            ]),
            TextField(controller: _wuensche, decoration: const InputDecoration(labelText: 'Eigene Wünsche (z. B. Eichenparkett, grüne Wand, Sofa am Fenster)', isDense: true), onChanged: (_) => setState(() => _promptVonHand = false)),
            const SizedBox(height: 8),
            TextField(
              controller: _prompt,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(labelText: 'Bildauftrag (wird mitgeschickt, änderbar)'),
              onChanged: (_) => _promptVonHand = true,
            ),
            const Divider(height: 24),
            Text('Anbieter: ${anbieter.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Wrap(children: [
              for (final (k, l) in const [('openai', 'OpenAI'), ('gemini', 'Gemini'), ('comfyui', 'ComfyUI lokal')])
                Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(l), selected: (_e['anbieter'] ?? 'openai') == k, onSelected: (_) => _setzen('anbieter', k))),
            ]),
            if ((_e['anbieter'] ?? 'openai') == 'openai')
              TextField(
                obscureText: true,
                controller: TextEditingController(text: '${_e['openai_key'] ?? ''}'),
                decoration: const InputDecoration(labelText: 'OpenAI-API-Schlüssel (platform.openai.com)', isDense: true, helperText: 'bleibt nur auf diesem PC'),
                onSubmitted: (t) => _setzen('openai_key', t.trim()),
              ),
            if (_e['anbieter'] == 'gemini')
              TextField(
                obscureText: true,
                controller: TextEditingController(text: '${_e['gemini_key'] ?? ''}'),
                decoration: const InputDecoration(labelText: 'Gemini-API-Schlüssel (aistudio.google.com)', isDense: true, helperText: 'bleibt nur auf diesem PC'),
                onSubmitted: (t) => _setzen('gemini_key', t.trim()),
              ),
            if (_e['anbieter'] == 'comfyui') ...[
              TextField(
                controller: TextEditingController(text: '${_e['comfy_adresse'] ?? 'http://127.0.0.1:8188'}'),
                decoration: const InputDecoration(labelText: 'ComfyUI-Adresse', isDense: true),
                onSubmitted: (t) => _setzen('comfy_adresse', t.trim()),
              ),
              Row(children: [
                Expanded(child: Text(_e['comfy_workflow'] == null ? 'Arbeitsablauf (API-JSON mit %PROMPT%, %BILD%) wählen' : p.basename('${_e['comfy_workflow']}'), style: const TextStyle(fontSize: 12))),
                TextButton(
                  onPressed: () async {
                    final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Workflow', extensions: ['json'])]);
                    if (f != null) _setzen('comfy_workflow', f.path);
                  },
                  child: const Text('Datei …'),
                ),
              ]),
            ],
            if (extern)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _e['extern_ok'] == true,
                onChanged: (v) => _setzen('extern_ok', v == true ? true : null),
                title: const Text('Raumdaten und Planskizze dürfen an den externen Dienst gesendet werden', style: TextStyle(fontSize: 12)),
              ),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Qualität: '),
              for (final q in const ['niedrig', 'mittel', 'hoch'])
                Padding(padding: const EdgeInsets.only(right: 4), child: ChoiceChip(label: Text(q), selected: _qualitaet == q, onSelected: (_) => setState(() => _qualitaet = q))),
            ]),
            Text(anbieter.kosten(_qualitaet) == 0 ? 'Lokal – keine Kosten je Bild.' : 'Kosten ca. ${anbieter.kosten(_qualitaet).toStringAsFixed(2).replaceAll('.', ',')} € je Bild (Richtwert, Abrechnung über dein Konto beim Anbieter).',
                style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _laeuft || !erlaubt
                  ? null
                  : () async {
                      setState(() {
                        _laeuft = true;
                        _fehler = null;
                      });
                      try {
                        final vorlage = _mitVorlage ? await raumSkizze(store, r) : null;
                        final b = await anbieter.erzeugen(prompt: _prompt.text, vorlage: vorlage, qualitaet: _qualitaet);
                        final t = DateTime.now();
                        final f = File(p.join(_ordner().path, '${r.kuerzel}_${t.toIso8601String().replaceAll(':', '-').substring(0, 19)}.png'));
                        await f.parent.create(recursive: true);
                        await f.writeAsBytes(b);
                        setState(() => _bild = f.path);
                      } catch (e) {
                        setState(() => _fehler = '$e');
                      } finally {
                        if (mounted) setState(() => _laeuft = false);
                      }
                    },
              icon: _laeuft ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
              label: Text(_laeuft ? 'Bild wird erzeugt … (bis 1 Minute)' : 'Raumbild erzeugen'),
            ),
            if (!erlaubt) const Text('Erst das Senden an den externen Dienst erlauben.', style: TextStyle(fontSize: 12, color: Color(0xFFB45309))),
            if (_fehler != null) Text(_fehler!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12)),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _bild != null
                  ? InteractiveViewer(child: Image.file(File(_bild!), fit: BoxFit.contain))
                  : FutureBuilder<Uint8List>(
                      future: _skizzeFuer(store, r),
                      builder: (c, snap) => snap.hasData
                          ? Column(children: [
                              const Padding(padding: EdgeInsets.all(8), child: Text('Planskizze, die als Vorlage mitgeht:', style: TextStyle(color: BsFarben.textLeise))),
                              Expanded(child: Image.memory(snap.data!, fit: BoxFit.contain)),
                            ])
                          : const Center(child: CircularProgressIndicator()),
                    ),
            ),
            if (_bild != null)
              Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                TextButton.icon(
                  onPressed: () {
                    store.fotoImportieren(_bild!, geschossId: r.geschossId, raumId: r.id, notiz: 'KI-Raumbild ($_stil) – Entwurf, kein Foto');
                    _s.geaendert();
                    zeigeHinweis(context, 'In die Fotos des Raums übernommen.');
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('Zu den Fotos des Raums'),
                ),
                TextButton.icon(onPressed: () => Process.run('explorer', [_bild!]), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Öffnen')),
              ]),
            if (alte.isNotEmpty)
              SizedBox(
                height: 92,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
                  for (final f in alte.take(20))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => setState(() => _bild = f.path),
                        child: Image.file(f, width: 110, height: 76, fit: BoxFit.cover, cacheWidth: 220),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
