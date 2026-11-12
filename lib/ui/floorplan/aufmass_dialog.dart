import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/aufmass.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Aufmaß vom Handy prüfen: gemessene Maße neben dem Planwert, einzeln oder
/// alle übernehmen bzw. verwerfen. So wird am PC grob gezeichnet, auf der
/// Baustelle gemessen und hier nachgearbeitet.
Future<void> aufmassDialogZeigen(BuildContext context, AppState s) =>
    showDialog<void>(context: context, builder: (_) => _AufmassDialog(state: s));

class _AufmassDialog extends StatefulWidget {
  const _AufmassDialog({required this.state});
  final AppState state;

  @override
  State<_AufmassDialog> createState() => _AufmassDialogState();
}

class _AufmassDialogState extends State<_AufmassDialog> {
  bool _alle = false;

  String _zielText(Map<String, dynamic> a) {
    final store = widget.state.store!;
    final raumId = a['raum'] as String?;
    String? raum;
    if (raumId != null) {
      for (final geb in store.gebaeude()) {
        for (final g in store.geschosse(geb.id)) {
          raum ??= store.raeume(g.id).where((r) => r.id == raumId).firstOrNull?.name;
        }
      }
    }
    final bezug = switch (a['bezug']) { 'innen' => ' (innen)', 'aussen' => ' (außen)', 'achse' => ' (Achse)', _ => '' };
    return '${aufmassFeldText('${a['ziel']}', '${a['feld']}')}$bezug${raum == null ? '' : ' · $raum'}';
  }

  void _anwenden(Map<String, dynamic> a) {
    final f = aufmassAnwenden(widget.state.store!, a);
    if (f != null) zeigeFehler(context, f);
    widget.state.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.state.store!;
    final liste = aufmassListe(store).reversed.where((a) => _alle || a['status'] == 'offen').toList();
    final offen = liste.where((a) => a['status'] == 'offen').toList();
    return AlertDialog(
      title: const Text('Aufmaß von der Baustelle'),
      content: SizedBox(
        width: 720,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Mit der BauSpur-App gemessene Maße. „Übernehmen“ ändert den Plan (Wandlängen über die gewählte Seite, '
            'Nachbarwände ziehen mit). Was übernommen ist, gilt als gemessen und wird in der App grün angezeigt.',
            style: TextStyle(fontSize: 12, color: BsFarben.textLeise),
          ),
          Row(children: [
            Checkbox(value: _alle, onChanged: (v) => setState(() => _alle = v == true)),
            const Text('auch erledigte zeigen'),
          ]),
          Expanded(
            child: liste.isEmpty
                ? const Center(child: Text('Keine offenen Maße. In der App: Plan › Wand antippen › „Maß aufnehmen“.'))
                : ListView(children: [
                    for (final a in liste)
                      Builder(builder: (_) {
                        final plan = aufmassPlanwert(store, a);
                        final wert = (a['wert'] as num?)?.toDouble() ?? 0;
                        final diff = plan == null ? null : wert - plan;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            switch (a['status']) { 'uebernommen' => Icons.check_circle, 'verworfen' => Icons.cancel_outlined, _ => Icons.straighten },
                            color: switch (a['status']) { 'uebernommen' => const Color(0xFF2F9E44), 'verworfen' => BsFarben.textLeise, _ => BsFarben.akzent },
                          ),
                          title: Text(_zielText(a)),
                          subtitle: Text([
                            'gemessen ${mmText(wert)} mm',
                            if (plan != null) 'Plan ${mmText(plan)} mm',
                            if (diff != null) 'Δ ${diff >= 0 ? '+' : ''}${mmText(diff)} mm',
                            '${a['autor']}, ${_datum('${a['zeit']}')}',
                            if (a['text'] != null) '„${a['text']}“',
                          ].join(' · ')),
                          trailing: a['status'] != 'offen'
                              ? Text(a['status'] == 'uebernommen' ? 'übernommen' : 'verworfen', style: const TextStyle(color: BsFarben.textLeise))
                              : Wrap(spacing: 4, children: [
                                  TextButton(
                                    onPressed: () {
                                      aufmassStatusSetzen(store, a['nr'] as String, 'verworfen');
                                      widget.state.geaendert();
                                      setState(() {});
                                    },
                                    child: const Text('Verwerfen'),
                                  ),
                                  FilledButton(onPressed: () => _anwenden(a), child: const Text('Übernehmen')),
                                ]),
                        );
                      }),
                  ]),
          ),
        ]),
      ),
      actions: [
        if (offen.isNotEmpty)
          OutlinedButton(
            onPressed: () {
              for (final a in offen) {
                final f = aufmassAnwenden(store, a);
                if (f != null) zeigeFehler(context, '${_zielText(a)}: $f');
              }
              widget.state.geaendert();
              setState(() {});
            },
            child: Text('Alle ${offen.length} übernehmen'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
      ],
    );
  }

  String _datum(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.day}.${d.month}. ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }
}
