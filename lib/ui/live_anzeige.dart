import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/sync.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// iPad: Zustand der Live-Verbindung in der Kopfleiste; Antippen gleicht sofort ab.
class LiveChip extends StatelessWidget {
  const LiveChip({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final live = state.live;
    if (live == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: live.zustand,
      builder: (_, z, __) => Tooltip(
        message: z.verbunden ? 'Live mit dem PC verbunden – Änderungen gehen sofort hin und her' : 'Keine Verbindung zum PC: ${z.fehler ?? ''}\nDu kannst weiterarbeiten, abgeglichen wird beim nächsten Kontakt.',
        child: ActionChip(
          avatar: Icon(z.verbunden ? Icons.sync : Icons.sync_problem, size: 16, color: z.verbunden ? const Color(0xFF2F9E44) : const Color(0xFFE67700)),
          label: Text(z.verbunden ? 'Live mit PC' : 'Offline${z.wartend > 0 ? ' · ${z.wartend} warten' : ''}'),
          onPressed: live.abgleichen,
        ),
      ),
    );
  }
}

/// PC: wer live mitarbeitet und ob es Konflikte gab (Statusleiste).
class LivePcAnzeige extends StatelessWidget {
  const LivePcAnzeige({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final jetzt = DateTime.now();
    final aktiv = [for (final g in state.liveGeraete.values) if (jetzt.difference(g.zeit).inSeconds < 20) g];
    final konflikte = state.store == null ? 0 : syncKonflikte(state.store!).length;
    if (aktiv.isEmpty && konflikte == 0) return const SizedBox.shrink();
    const stil = TextStyle(fontSize: 12, color: BsFarben.textLeise);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (aktiv.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Tooltip(
            message: 'Arbeitet gerade live mit: ${aktiv.map((g) => g.name).join(', ')}',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.sync, size: 13, color: Color(0xFF2F9E44)),
              const SizedBox(width: 4),
              Text('${aktiv.map((g) => g.name).join(', ')} live', style: stil),
            ]),
          ),
        ),
      if (konflikte > 0)
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: InkWell(
            onTap: () => konflikteZeigen(context, state),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.call_split, size: 13, color: Color(0xFFE67700)),
              const SizedBox(width: 4),
              Text('$konflikte Konflikt${konflikte == 1 ? '' : 'e'}', style: stil.copyWith(color: const Color(0xFFE67700))),
            ]),
          ),
        ),
    ]);
  }
}

/// Konflikte aus dem Live-Abgleich: welcher Stand gewonnen hat, den anderen wiederherstellen.
Future<void> konflikteZeigen(BuildContext context, AppState s) {
  final store = s.store!;
  return showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      final l = syncKonflikte(store);
      void entfernen(int i) {
        final n = [...l]..removeAt(i);
        store.einstellungSetzen('sync_konflikte', n);
        setD(() {});
        s.geaendert();
      }

      return AlertDialog(
        title: const Text('Konflikte beim Live-Abgleich'),
        content: SizedBox(
          width: 640,
          height: 420,
          child: l.isEmpty
              ? const Center(child: Text('Keine Konflikte.'))
              : ListView(children: [
                  const Text('Derselbe Eintrag wurde am PC und am iPad geändert. Die jüngere Änderung gilt; die andere steht hier und lässt sich wiederherstellen.',
                      style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                  for (final (i, k) in l.indexed.toList().reversed)
                    ListTile(
                      dense: true,
                      title: Text('${_tabelleText('${k['tabelle']}')}: ${_kurz(k['verlierer_zeile'])}'),
                      subtitle: Text('Gilt jetzt: Stand von ${k['gewinner']} · überschrieben: Stand vom ${k['gewinner'] == 'PC' ? k['geraet'] : 'PC'} (${'${k['verlierer_zeit'] ?? ''}'.replaceFirst('T', ' ').split('.').first})'),
                      trailing: Wrap(spacing: 4, children: [
                        TextButton(
                          onPressed: () {
                            aenderungenAnwenden(store, [
                              {'t': k['tabelle'], 'id': k['id'], 'zeile': k['verlierer_zeile']}
                            ]);
                            entfernen(i);
                            zeigeHinweis(context, 'Wiederhergestellt – geht auch ans iPad.');
                          },
                          child: const Text('Diesen Stand nehmen'),
                        ),
                        IconButton(tooltip: 'Erledigt', onPressed: () => entfernen(i), icon: const Icon(Icons.check, size: 18)),
                      ]),
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
      );
    }),
  );
}

String _tabelleText(String t) => switch (t) {
      'wand' => 'Wand',
      'raum' => 'Raum',
      'objekt' => 'Objekt',
      'oeffnung' => 'Öffnung',
      'einstellung' => 'Einstellung',
      'aufgabe' => 'Aufgabe',
      'tagebuch' => 'Tagebuch',
      'kostenposition' => 'Kostenposition',
      _ => t,
    };

String _kurz(Object? zeile) {
  if (zeile is! Map) return 'gelöscht';
  final n = zeile['name'] ?? zeile['kennung'] ?? zeile['titel'] ?? zeile['text'] ?? zeile['wert'];
  final t = '${n ?? zeile['id'] ?? ''}';
  return t.length > 60 ? '${t.substring(0, 60)} …' : t;
}
