import 'package:flutter/material.dart';

import '../core/kennung.dart';
import '../core/raumerkennung.dart';
import '../data/models.dart';
import '../data/project_store.dart';
import 'widgets.dart';

/// Dialog: neues Geschoss mit Bezugshöhen.
Future<bool> geschossDialog(BuildContext context, ProjectStore store, String gebaeudeId) async {
  final name = TextEditingController();
  final kuerzel = TextEditingController();
  final rfb = TextEditingController(text: '0');
  final ffb = TextEditingController(text: '0');
  final rd = TextEditingController(text: '2600');
  final mr = TextEditingController(text: '1000');
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Neues Geschoss'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name, z. B. Obergeschoss'),
              onChanged: (v) {
                final k = kuerzelVorschlag(v);
                kuerzel.text = k.length > 2 ? k.substring(0, 2) : k;
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: kuerzel, decoration: const InputDecoration(labelText: 'Kürzel, z. B. OG')),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Bezugshöhen im Geschoss (Nullpunkt frei wählbar, meist RFB = 0)'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: MmFeld(label: 'Rohfußboden', controller: rfb)),
              const SizedBox(width: 12),
              Expanded(child: MmFeld(label: 'Fertigfußboden', controller: ffb)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: MmFeld(label: 'Rohdecke', controller: rd)),
              const SizedBox(width: 12),
              Expanded(child: MmFeld(label: 'Meterriss', controller: mr)),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Anlegen')),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return false;
  store.geschossAnlegen(
    gebaeudeId: gebaeudeId,
    name: name.text.trim(),
    kuerzel: kuerzel.text.trim().isEmpty ? kuerzelVorschlag(name.text) : kuerzel.text.trim(),
    rfb: mmWert(rfb) ?? 0,
    ffb: mmWert(ffb) ?? 0,
    rohdecke: mmWert(rd) ?? 2600,
    meterriss: mmWert(mr) ?? 1000,
  );
  return true;
}

/// Dialog: neuer Raum, optional mit eigenen Höhen. Mit [flaeche] wird der
/// Raum auf einer erkannten Fläche im Grundriss angelegt; dann lässt sich
/// stattdessen auch ein vorhandener, noch nicht verorteter Raum zuordnen.
/// Liefert die ID des angelegten oder zugeordneten Raums.
Future<String?> raumDialog(
  BuildContext context,
  ProjectStore store,
  Geschoss geschoss, {
  ErkannterRaum? flaeche,
}) async {
  final name = TextEditingController();
  final kuerzel = TextEditingController();
  final ffb = TextEditingController();
  final rd = TextEditingController();
  final uk = TextEditingController();
  final freie = flaeche == null ? <Raum>[] : store.raeume(geschoss.id).where((r) => r.umriss == null).toList();
  String? vorhandener;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialog) => AlertDialog(
        title: Text(flaeche == null
            ? 'Neuer Raum im ${geschoss.name}'
            : 'Raum anlegen · ${flaecheText(flaeche.flaeche)}, Umfang ${meterText(flaeche.umfang)}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (freie.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  initialValue: null,
                  decoration: const InputDecoration(labelText: 'Vorhandenen Raum zuordnen'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('– neuen Raum anlegen –')),
                    for (final r in freie) DropdownMenuItem(value: r.id, child: Text('${r.name} (${r.kuerzel})')),
                  ],
                  onChanged: (v) => setDialog(() => vorhandener = v),
                ),
                const SizedBox(height: 16),
              ],
              if (vorhandener == null) ...[
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name, z. B. Bad'),
                  onChanged: (v) => kuerzel.text = kuerzelVorschlag(v),
                ),
                const SizedBox(height: 12),
                TextField(controller: kuerzel, decoration: const InputDecoration(labelText: 'Kürzel, z. B. BAD')),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Eigene Höhen (leer lassen = wie Geschoss)'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: MmFeld(
                      label: 'Fertigfußboden',
                      controller: ffb,
                      hinweis: 'Geschoss: ${mmText(geschoss.hoehen.ffb)}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MmFeld(
                      label: 'Rohdecke',
                      controller: rd,
                      hinweis: 'Geschoss: ${mmText(geschoss.hoehen.rohdecke)}',
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                MmFeld(label: 'Unterkante Decke (z. B. abgehängt)', controller: uk),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(vorhandener == null ? 'Anlegen' : 'Zuordnen'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  final v = vorhandener;
  if (v != null && flaeche != null) {
    store.raumVerorten(v, flaeche);
    return v;
  }
  if (name.text.trim().isEmpty) return null;
  return store.raumAnlegen(
    geschossId: geschoss.id,
    name: name.text.trim(),
    kuerzel: kuerzel.text.trim().isEmpty ? kuerzelVorschlag(name.text) : kuerzel.text.trim(),
    ffb: mmWert(ffb),
    rohdecke: mmWert(rd),
    ukDecke: mmWert(uk),
    flaeche: flaeche,
  );
}

/// Dialog: Raum umbenennen (Name und Kürzel).
Future<bool> raumUmbenennenDialog(BuildContext context, ProjectStore store, Raum raum) async {
  final name = TextEditingController(text: raum.name);
  final kuerzel = TextEditingController(text: raum.kuerzel);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Raum umbenennen'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(controller: kuerzel, decoration: const InputDecoration(labelText: 'Kürzel')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return false;
  store.raumAendern(raum.id, name: name.text.trim(), kuerzel: kuerzel.text.trim().isEmpty ? null : kuerzel.text.trim());
  return true;
}
