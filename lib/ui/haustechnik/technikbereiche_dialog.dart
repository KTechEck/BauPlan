import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/ids.dart';
import '../../core/technikbereich.dart';
import '../../state/app_state.dart';

/// Technikbereiche verwalten: erkannte Räume (lösbar), eigene Bereiche als
/// Raum oder Technikwand mit zugeordneten Schränken.
Future<void> technikbereicheDialog(BuildContext context, AppState s) async {
  final store = s.store!;
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      final alle = technikbereiche(store);
      final eigene = alle.where((b) => !b.automatisch).toList();
      final raeume = [
        for (final geb in store.gebaeude())
          for (final g in store.geschosse(geb.id))
            for (final r in store.raeume(g.id))
              if (r.umriss != null) (r, g),
      ];
      final raumName = {for (final (r, g) in raeume) r.id: '${g.kuerzel} ${r.name}'};
      final geloest = {for (final e in (store.einstellung<List>('technikbereich_aus') ?? const [])) '$e'};
      final schraenke = store.schraenke();
      return AlertDialog(
        title: const Text('Technikbereiche'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'Ein Technikbereich ist ein ganzer Raum oder eine Technikwand in einem anderen Raum (z. B. Büro mit Netzwerk-, Smart-Home- und 230-V-Schrank). '
                  'Räume mit „Technik“, „Heiz“, „HWR“ im Namen werden automatisch erkannt – das lässt sich lösen.',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              const SizedBox(height: 8),
              for (final b in alle)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(b.istWand ? Icons.view_week_outlined : Icons.meeting_room_outlined, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${b.name} · ${raumName[b.raumId] ?? '?'}${b.automatisch ? ' (automatisch erkannt)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (b.automatisch)
                          TextButton(
                            onPressed: () {
                              technikbereichAutoLoesen(store, b.raumId, true);
                              s.geaendert();
                              setD(() {});
                            },
                            child: const Text('kein Technikbereich'),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () {
                              technikbereicheSpeichern(store, [for (final x in eigene) if (x.id != b.id) x]);
                              s.geaendert();
                              setD(() {});
                            },
                          ),
                      ]),
                      if (!b.automatisch)
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          for (final sch in schraenke)
                            FilterChip(
                              label: Text('${sch.kennzeichen} ${sch.art.label}'),
                              selected: b.schraenke.contains(sch.id),
                              onSelected: (v) {
                                technikbereicheSpeichern(store, [
                                  for (final x in eigene)
                                    x.id == b.id
                                        ? Technikbereich(id: x.id, name: x.name, raumId: x.raumId, wandId: x.wandId, schraenke: v ? [...x.schraenke, sch.id] : [for (final i in x.schraenke) if (i != sch.id) i])
                                        : x
                                ]);
                                s.geaendert();
                                setD(() {});
                              },
                            ),
                        ]),
                    ]),
                  ),
                ),
              if (geloest.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  const Text('Gelöst:', style: TextStyle(fontSize: 12)),
                  for (final id in geloest)
                    if (raumName[id] != null)
                      InputChip(
                        label: Text(raumName[id]!),
                        onDeleted: () {
                          technikbereichAutoLoesen(store, id, false);
                          s.geaendert();
                          setD(() {});
                        },
                        deleteIcon: const Icon(Icons.undo, size: 16),
                      ),
                ]),
              ],
              const Divider(height: 24),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (r, _) in raeume)
                  if (!alle.any((b) => b.raumId == r.id))
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text('${raumName[r.id]} als Bereich'),
                      onPressed: () {
                        technikbereicheSpeichern(store, [...eigene, Technikbereich(id: neueId(), name: r.name, raumId: r.id)]);
                        s.geaendert();
                        setD(() {});
                      },
                    ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (r, _) in raeume)
                  ActionChip(
                    avatar: const Icon(Icons.view_week_outlined, size: 16),
                    label: Text('Technikwand in ${raumName[r.id]}'),
                    onPressed: () {
                      technikbereicheSpeichern(store, [...eigene, Technikbereich(id: neueId(), name: 'Technikwand ${r.name}', raumId: r.id, wandId: 'wand')]);
                      s.geaendert();
                      setD(() {});
                    },
                  ),
              ]),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
      );
    }),
  );
}
