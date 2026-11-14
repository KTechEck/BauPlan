import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/diktat.dart';
import '../core/ki.dart';
import '../state/app_state.dart';

/// Mikrofon-Knopf neben einem Textfeld: diktieren, Text wird angehängt.
class DiktatKnopf extends StatelessWidget {
  const DiktatKnopf({super.key, required this.state, required this.controller});
  final AppState state;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Diktieren (Text statt Sprachnotiz)',
        icon: const Icon(Icons.mic_none),
        onPressed: () async {
          final t = await diktatDialog(context, state);
          if (t == null || t.isEmpty) return;
          final alt = controller.text.trimRight();
          controller.text = alt.isEmpty ? t : '$alt ${t.trimLeft()}';
        },
      );
}

/// Diktat aufnehmen und als Text zurückgeben (null = abgebrochen).
Future<String?> diktatDialog(BuildContext context, AppState s) => showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DiktatDialog(state: s),
    );

class _DiktatDialog extends StatefulWidget {
  const _DiktatDialog({required this.state});
  final AppState state;

  @override
  State<_DiktatDialog> createState() => _DiktatDialogState();
}

class _DiktatDialogState extends State<_DiktatDialog> {
  final _text = TextEditingController();
  DiktatSitzung? _sitzung;
  StreamSubscription<String>? _abo;
  bool _laeuft = false, _ki = false;
  String? _meldung;

  @override
  void initState() {
    super.initState();
    _starten();
  }

  Future<void> _starten() async {
    final s = await DiktatSitzung.starten();
    if (!mounted) {
      s?.beenden();
      return;
    }
    if (s == null) {
      setState(() => _meldung = 'Diktat geht hier nicht. Tipp: Windows-Diktat mit Win + H direkt ins Feld sprechen.');
      return;
    }
    _sitzung = s;
    setState(() => _laeuft = true);
    _abo = s.phrasen.listen((p) {
      final alt = _text.text.trimRight();
      _text.text = alt.isEmpty ? p : '$alt $p';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    }, onDone: () {
      if (!mounted) return;
      setState(() {
        _laeuft = false;
        if (s.fehler != null) _meldung = '${s.fehler} Tipp: Win + H (Windows-Diktat) geht auch.';
      });
    });
  }

  void _stopp() {
    _sitzung?.beenden();
    setState(() => _laeuft = false);
  }

  Future<void> _kiOrdnen() async {
    setState(() => _ki = true);
    try {
      final ki = OllamaAnbieter(KiEinstellung.ausJson(widget.state.settings.ki));
      final a = await ki.fragen('Du ordnest Baustellen-Diktate. Antworte nur mit JSON.', '$kiDiktatAnfrage\n\nDIKTAT:\n${diktatAufbereiten(_text.text)}');
      final r = kiDiktatLesen(a);
      if (r == null) throw const FormatException('keine verwertbare Antwort');
      _text.text = [
        r.notiz,
        for (final x in r.aufgaben) 'Aufgabe: $x.',
        for (final x in r.maengel) 'Mangel: $x.',
      ].where((e) => e.trim().isNotEmpty).join('\n');
    } catch (e) {
      setState(() => _meldung = 'KI nicht erreichbar oder Antwort unklar ($e). Der Text bleibt, wie er ist.');
    } finally {
      if (mounted) setState(() => _ki = false);
    }
  }

  @override
  void dispose() {
    _abo?.cancel();
    _sitzung?.beenden();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kiDa = widget.state.settings.ki != null;
    return AlertDialog(
      title: Row(children: [
        Icon(_laeuft ? Icons.mic : Icons.mic_off_outlined, color: _laeuft ? BsFarben.akzent : BsFarben.textLeise),
        const SizedBox(width: 8),
        Text(_laeuft ? 'Diktat läuft …' : 'Diktat'),
      ]),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sprich ganz normal. „Punkt“, „Komma“ und „neue Zeile“ werden umgesetzt. '
              'Sätze mit „Aufgabe …“, „noch …“ oder „Mangel …“ werden beim Übernehmen erkannt. Es wird nur Text gespeichert, kein Ton.',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          const SizedBox(height: 8),
          TextField(controller: _text, maxLines: 8, minLines: 5, decoration: const InputDecoration(hintText: 'Hier erscheint der erkannte Text – du kannst ihn korrigieren.')),
          if (_meldung != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_meldung!, style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)))),
        ]),
      ),
      actions: [
        if (_laeuft) TextButton.icon(onPressed: _stopp, icon: const Icon(Icons.stop), label: const Text('Stopp')),
        if (!_laeuft && _sitzung != null)
          TextButton.icon(onPressed: () {
            _abo?.cancel();
            _starten();
          }, icon: const Icon(Icons.mic), label: const Text('Weiter diktieren')),
        if (kiDa)
          TextButton.icon(
            onPressed: _ki || _text.text.trim().isEmpty ? null : _kiOrdnen,
            icon: _ki ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Mit KI ordnen'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () {
            _sitzung?.beenden();
            Navigator.pop(context, diktatAufbereiten(_text.text));
          },
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

/// Diktat als Tagebucheintrag; erkannte Aufgaben und Mängel werden zum
/// Abhaken angeboten (nichts wird ungefragt angelegt).
Future<void> diktatInsTagebuch(BuildContext context, AppState s, {List<String> raeume = const []}) async {
  final text = await diktatDialog(context, s);
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  final teile = diktatAuswerten(text);
  final wahl = {for (final a in teile.aufgaben) 'A:$a': true, for (final m in teile.maengel) 'M:$m': true};
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Diktat übernehmen'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tagebucheintrag (heute)', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(teile.notiz),
              if (wahl.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Erkannt – als Aufgabe anlegen?', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final k in wahl.keys)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: wahl[k],
                    title: Text(k.startsWith('M:') ? 'Mangel: ${k.substring(2)}' : k.substring(2)),
                    onChanged: (v) => setD(() => wahl[k] = v ?? false),
                  ),
              ],
              if (teile.messwerte.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Messwerte im Text: ${teile.messwerte.map((m) => '${m.was} ${m.wert.toString().replaceAll('.', ',')} ${m.einheit}').join(', ')}',
                    style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final store = s.store!;
  store.tagebuchAnlegen(datum: DateTime.now(), text: teile.notiz, raeume: raeume);
  for (final e in wahl.entries) {
    if (!e.value) continue;
    final t = e.key.substring(2);
    store.aufgabeAnlegen(titel: t, art: e.key.startsWith('M:') ? 'mangel' : 'aufgabe', beschreibung: 'aus Diktat vom ${DateTime.now().day}.${DateTime.now().month}.');
  }
  s.geaendert();
}
