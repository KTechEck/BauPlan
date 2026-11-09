import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/ki.dart';
import '../../state/app_state.dart';
import '../../core/ki_einrichtung.dart' show Hardware;
import 'projektpruefung.dart';

/// Modul KI-Assistent: Planprüfung (feste Regeln und, auf Wunsch,
/// Einschätzungen des Sprachmodells – klar getrennt), Fragen an das Projekt,
/// Einstellungen. Der Assistent liest nur; entscheiden tust du.
class AssistentPage extends StatefulWidget {
  const AssistentPage({super.key, required this.state, this.anbieter, this.hardware, this.modelle});
  final AppState state;

  /// Für Tests: eigener Anbieter statt des eingestellten Sprachmodells.
  final KiAnbieter? anbieter;

  /// Für Tests: Hardware und Modellabfrage der Einrichtung.
  final Future<Hardware> Function()? hardware;
  final Future<List<String>?> Function(String adresse)? modelle;

  @override
  State<AssistentPage> createState() => _AssistentPageState();
}

class _AssistentPageState extends State<AssistentPage> {
  int _ansicht = 0;
  List<PruefHinweis> _ki = [];
  bool _laeuft = false;
  String? _fehler;
  final _frage = TextEditingController();
  List<(String, String)> _treffer = [];
  String? _antwort;

  AppState get _s => widget.state;
  KiEinstellung get _einstellung => KiEinstellung.ausJson(_s.settings.ki);
  KiAnbieter get _anbieter => widget.anbieter ?? OllamaAnbieter(_einstellung);
  Regelwerte get _regeln => Regelwerte.ausJson(_s.store!.einstellung<Map>('regeln')?.cast<String, dynamic>());

  @override
  void dispose() {
    _frage.dispose();
    super.dispose();
  }

  Map<String, String> get _status => Map<String, String>.from(_s.store!.einstellung<Map>('pruefung_status') ?? const {});

  void _statusSetzen(PruefHinweis h, String status) {
    final m = _status..[h.schluessel] = status;
    _s.store!.einstellungSetzen('pruefung_status', m); // steht damit im Änderungsprotokoll
    _s.geaendert();
  }

  /// Vor dem Senden an einen Dienst außerhalb des Heimnetzes zeigen, was gesendet wird.
  Future<bool> _sendenErlaubt(String text) async {
    final a = _anbieter;
    if (!a.extern) return true;
    if (!_einstellung.cloudErlaubt) {
      setState(() => _fehler = 'Die eingestellte Adresse liegt nicht im Heimnetz. Cloud-Dienste sind in den Einstellungen ausgeschaltet.');
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Das verlässt das Heimnetz'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontFamily: 'Consolas', fontSize: 12))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('An ${a.name} senden')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _einschaetzen(List<PruefHinweis> regeln) async {
    final text = '${projektSteckbrief(_s.store!, regeln)}\n'
        'Prüfe diese Planung und nenne bis zu 10 weitere Hinweise als Aufzählung (je Zeile „- …“), jeweils mit kurzer Begründung. '
        'Wiederhole nicht, was die festen Regeln schon gefunden haben.';
    if (!await _sendenErlaubt(text)) return;
    setState(() {
      _laeuft = true;
      _fehler = null;
    });
    try {
      final antwort = await _anbieter.fragen(kiSystem, text);
      setState(() => _ki = kiHinweiseLesen(antwort));
    } catch (e) {
      setState(() => _fehler = 'Sprachmodell nicht erreichbar: $e');
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  /// Suchbare Einträge des Projekts: Räume, Objekte, Stromkreise.
  Map<String, (String, String)> _eintraege() {
    final store = _s.store!;
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final m = <String, (String, String)>{};
    for (final geb in store.gebaeude()) {
      for (final g in store.geschosse(geb.id)) {
        final raeume = {for (final r in store.raeume(g.id)) r.id: r.name};
        raeume.forEach((id, name) => m['raum $name ${g.name} ${g.kuerzel}'] = ('Raum', '${g.kuerzel} $name'));
        for (final o in store.objekte(g.id)) {
          final t = typen[o.typId];
          final raum = raeume[o.raumId] ?? '';
          m['${t?.name ?? ''} ${o.kennung} $raum ${o.lage ?? ''} ${t?.kuerzel ?? ''}'] =
              ('Objekt', '${o.kennung} · ${t?.name ?? ''}${raum.isEmpty ? '' : ' · $raum'}${o.lage == null ? '' : ' · ${o.lage}'}');
        }
      }
    }
    final alle = store.alleObjekte();
    final raumNamen = {
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) r.id: r.name,
    };
    for (final s in store.schraenke()) {
      for (final k in store.stromkreise(s.id)) {
        final rs = {for (final o in alle) if (o.eigenschaften['stromkreis'] == k.id && raumNamen[o.raumId] != null) raumNamen[o.raumId]!};
        m['stromkreis stromkreise ${k.bezeichnung} ${rs.join(' ')} ${s.name}'] =
            ('Stromkreis', '=${s.kennzeichen} Stromkreis ${k.nummer} ${k.bezeichnung}${rs.isEmpty ? '' : ' → ${rs.join(', ')}'}');
      }
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
          child: Row(children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.fact_check_outlined, size: 18), label: Text('Planprüfung')),
                ButtonSegment(value: 1, icon: Icon(Icons.question_answer_outlined, size: 18), label: Text('Fragen')),
              ],
              selected: {_ansicht},
              onSelectionChanged: (v) => setState(() => _ansicht = v.first),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                _s.einstellungenZiel = 'ki';
                _s.modulWaehlen(Modul.einstellungen);
              },
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('KI einrichten und Prüfregeln'),
            ),
          ]),
        ),
        Expanded(
          child: switch (_ansicht) {
            0 => _pruefung(),
            _ => _fragen(),
          },
        ),
      ]),
    );
  }

  Widget _hinweisZeile(PruefHinweis h, Map<String, String> status) {
    final st = status[h.schluessel] ?? 'offen';
    return ListTile(
      dense: true,
      leading: Icon(h.ki ? Icons.auto_awesome_outlined : Icons.rule,
          color: st == 'offen' ? (h.ki ? const Color(0xFF7048E8) : const Color(0xFFB45309)) : BsFarben.textLeise),
      title: Text(h.text, style: TextStyle(decoration: st == 'erledigt' ? TextDecoration.lineThrough : null, color: st == 'offen' ? null : BsFarben.textLeise)),
      subtitle: Text('${h.ki ? 'Einschätzung des Sprachmodells' : 'feste Regel'} · ${h.bereich}'),
      trailing: DropdownButton<String>(
        value: st,
        underline: const SizedBox.shrink(),
        items: [for (final e in pruefStatus.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => _statusSetzen(h, v ?? 'offen'),
      ),
      onTap: h.objektId == null
          ? null
          : () {
              final o = _s.store!.alleObjekte().where((x) => x.id == h.objektId).firstOrNull;
              if (o == null) return;
              _s.markiert = {o.id};
              _s.geschossId = o.geschossId;
              _s.modulWaehlen(Modul.installation);
            },
    );
  }

  Widget _pruefung() {
    final regeln = projektPruefen(_s.store!, _regeln);
    final status = _status;
    final offen = regeln.where((h) => (status[h.schluessel] ?? 'offen') == 'offen').length;
    final bereiche = <String, List<PruefHinweis>>{};
    for (final h in regeln) {
      bereiche.putIfAbsent(h.bereich, () => []).add(h);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${regeln.length} Hinweise aus festen Regeln, $offen offen', style: Theme.of(context).textTheme.titleMedium),
        FilledButton.icon(
          onPressed: _laeuft ? null : () => _einschaetzen(regeln),
          icon: _laeuft
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome_outlined, size: 18),
          label: const Text('KI-Prüfung (Einschätzung)'),
        ),
      ]),
      const SizedBox(height: 4),
      const Text(
          'Feste Regeln rechnet das Programm exakt (Kreislängen, Füllgrad, Abstände, Querschnitt zu Schutzorgan …). '
          'Einschätzungen kommen vom Sprachmodell und sind getrennt gekennzeichnet. Jeder Hinweis ist ein Hinweis, keine Abnahme.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      if (_fehler != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_fehler!, style: const TextStyle(color: Color(0xFFB91C1C)))),
      for (final e in bereiche.entries) ...[
        const SizedBox(height: 12),
        Text(e.key, style: Theme.of(context).textTheme.titleSmall),
        Card(child: Column(children: [for (final h in e.value) _hinweisZeile(h, status)])),
      ],
      if (regeln.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Die festen Regeln finden nichts.'))),
      if (_ki.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Einschätzungen des Sprachmodells', style: Theme.of(context).textTheme.titleSmall),
        Card(child: Column(children: [for (final h in _ki) _hinweisZeile(h, status)])),
      ],
    ]);
  }

  Widget _fragen() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _frage,
            decoration: const InputDecoration(
              labelText: 'Frage an das Projekt',
              hintText: 'z. B. „Welche Stromkreise gehen ins Bad?“ oder „Wo liegt die Wasserleitung in der Küche?“',
            ),
            onSubmitted: (_) => setState(() {
              _treffer = stichwortSuche(_frage.text, _eintraege());
              _antwort = null;
            }),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: () => setState(() {
            _treffer = stichwortSuche(_frage.text, _eintraege());
            _antwort = null;
          }),
          child: const Text('Suchen'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _laeuft || _frage.text.trim().isEmpty
              ? null
              : () async {
                  final treffer = stichwortSuche(_frage.text, _eintraege());
                  final text = '${projektSteckbrief(_s.store!, const [])}\nPassende Einträge:\n'
                      '${treffer.take(40).map((t) => '- ${t.$1}: ${t.$2}').join('\n')}\n\nFrage: ${_frage.text.trim()}';
                  if (!await _sendenErlaubt(text)) return;
                  setState(() {
                    _laeuft = true;
                    _fehler = null;
                    _treffer = treffer;
                  });
                  try {
                    final a = await _anbieter.fragen(kiSystem, text);
                    setState(() => _antwort = a);
                  } catch (e) {
                    setState(() => _fehler = 'Sprachmodell nicht erreichbar: $e');
                  } finally {
                    if (mounted) setState(() => _laeuft = false);
                  }
                },
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: const Text('Sprachmodell fragen'),
        ),
      ]),
      if (_fehler != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_fehler!, style: const TextStyle(color: Color(0xFFB91C1C)))),
      if (_antwort != null) ...[
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFFF3F0FF),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Antwort des Sprachmodells (Einschätzung)', style: TextStyle(fontSize: 12, color: Color(0xFF7048E8))),
              const SizedBox(height: 6),
              SelectableText(_antwort!),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(_treffer.isEmpty ? 'Keine Treffer – andere Wörter versuchen.' : '${_treffer.length} Treffer im Projekt',
          style: Theme.of(context).textTheme.titleSmall),
      for (final (art, text) in _treffer.take(60)) ListTile(dense: true, leading: Text(art, style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)), title: Text(text)),
    ]);
  }

}
