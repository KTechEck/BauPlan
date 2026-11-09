import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/height.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'dialogs.dart';
import 'widgets.dart';

/// Projektübersicht: Gebäude, Geschosse mit Bezugshöhen, Höhenrechner.
class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, required this.state});
  final AppState state;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  final _wert = TextEditingController(text: '300');
  Hoehenbezug _von = Hoehenbezug.ffb;
  Hoehenbezug _nach = Hoehenbezug.rfb;

  @override
  Widget build(BuildContext context) {
    final store = widget.state.store!;
    final geschosse = <Geschoss>[
      for (final g in store.gebaeude()) ...store.geschosse(g.id),
    ];
    final aktiv = widget.state.geschossId == null ? null : store.geschoss(widget.state.geschossId!);
    final raum = widget.state.raumId == null
        ? null
        : store.raeume(aktiv!.id).where((r) => r.id == widget.state.raumId).firstOrNull;
    final hoehen = aktiv == null ? null : (raum?.hoehen(aktiv) ?? aktiv.hoehen);
    final ergebnis = hoehen == null || mmWert(_wert) == null
        ? null
        : umrechnen(mmWert(_wert)!, _von, _nach, hoehen);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(store.name, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(store.ordner, style: const TextStyle(color: BsFarben.textLeise)),
        const SizedBox(height: 24),
        Text('Geschosse und Bezugshöhen', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Geschoss')),
                DataColumn(label: Text('RFB'), numeric: true),
                DataColumn(label: Text('FFB'), numeric: true),
                DataColumn(label: Text('Meterriss'), numeric: true),
                DataColumn(label: Text('Rohdecke'), numeric: true),
                DataColumn(label: Text('Räume'), numeric: true),
              ],
              rows: [
                for (final g in geschosse)
                  DataRow(cells: [
                    DataCell(Text('${g.kuerzel} · ${g.name}')),
                    DataCell(Text(mmText(g.hoehen.rfb))),
                    DataCell(Text(mmText(g.hoehen.ffb))),
                    DataCell(Text(mmText(g.hoehen.meterriss))),
                    DataCell(Text(mmText(g.hoehen.rohdecke))),
                    DataCell(Text('${store.raeume(g.id).length}')),
                  ]),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final geb = store.gebaeude().first;
              if (await geschossDialog(context, store, geb.id)) widget.state.geaendert();
            },
            icon: const Icon(Icons.add),
            label: const Text('Geschoss'),
          ),
        ),
        const SizedBox(height: 24),
        Text('Höhen umrechnen', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          aktiv == null
              ? 'Wähle links im Grundriss ein Geschoss.'
              : 'Für ${raum?.name ?? aktiv.name}${raum?.hatEigeneHoehen == true ? ' (eigene Raumhöhen)' : ''}',
          style: const TextStyle(color: BsFarben.textLeise),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 140, child: MmFeld(label: 'Wert', controller: _wert)),
            DropdownButton<Hoehenbezug>(
              value: _von,
              items: [for (final b in Hoehenbezug.values) DropdownMenuItem(value: b, child: Text(b.label))],
              onChanged: (b) => setState(() => _von = b!),
            ),
            const Icon(Icons.arrow_forward),
            DropdownButton<Hoehenbezug>(
              value: _nach,
              items: [for (final b in Hoehenbezug.values) DropdownMenuItem(value: b, child: Text(b.label))],
              onChanged: (b) => setState(() => _nach = b!),
            ),
            FilledButton(onPressed: () => setState(() {}), child: const Text('Rechnen')),
            if (ergebnis != null)
              Text('= ${mmText(ergebnis)} mm ${_nach.label}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ],
        ),
      ],
    );
  }
}
