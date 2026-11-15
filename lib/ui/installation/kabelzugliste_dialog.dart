import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/kabelwege.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Kabelzugliste: jedes Kabel mit von/nach, Geschossen und Länge (auch über
/// Steigleitungen in andere Geschosse). Klick hebt den Kabelweg im Plan hervor.
Future<void> kabelzuglisteZeigen(BuildContext context, AppState s, {void Function(Kabelweg k)? zeigen}) {
  final store = s.store!;
  final l = kabelwege(store, name: (id) => s.bibliothek.fuerProjekt(store, id)?.anzeige);
  String m(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  final summe = l.fold<double>(0, (a, k) => a + k.meter);
  final jeKabel = <String, double>{};
  for (final k in l) {
    jeKabel[k.kabel] = (jeKabel[k.kabel] ?? 0) + k.meter;
  }
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Kabelzugliste (${l.length} Kabel, ${m(summe)} m)'),
      content: SizedBox(
        width: 1000,
        height: 560,
        child: l.isEmpty
            ? const Center(
                child: Text('Noch keine Kabel. Leitungen (LT, NK, BL …) zeichnen oder Geräte Stromkreisen zuordnen. '
                    'Über Geschosse: Leitung an einer Steigleitung (SR) enden lassen und im anderen Geschoss an derselben Steigleitung weiterführen.',
                    textAlign: TextAlign.center, style: TextStyle(color: BsFarben.textLeise)),
              )
            : ListView(children: [
                const Text('Klick auf eine Zeile zeigt den Kabelweg im Plan. Senkrecht = Weg durch die Decken an Steigleitungen; dazu je Kabel 1 m Reserve.',
                    style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                const SizedBox(height: 6),
                DataTable(
                  showCheckboxColumn: false,
                  headingRowHeight: 32,
                  dataRowMinHeight: 30,
                  dataRowMaxHeight: 52,
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('Nr')),
                    DataColumn(label: Text('Kabel')),
                    DataColumn(label: Text('von')),
                    DataColumn(label: Text('nach')),
                    DataColumn(label: Text('Geschosse')),
                    DataColumn(label: Text('Länge'), numeric: true),
                  ],
                  rows: [
                    for (final k in l)
                      DataRow(
                        onSelectChanged: zeigen == null
                            ? null
                            : (_) {
                                Navigator.pop(c);
                                zeigen(k);
                              },
                        cells: [
                          DataCell(Text(k.nr)),
                          DataCell(SizedBox(width: 170, child: Text(k.kabel, overflow: TextOverflow.ellipsis))),
                          DataCell(SizedBox(width: 200, child: Text(k.von, overflow: TextOverflow.ellipsis, maxLines: 2))),
                          DataCell(SizedBox(width: 220, child: Text(k.nach, overflow: TextOverflow.ellipsis, maxLines: 2))),
                          DataCell(Text(k.geschosse.join(', '))),
                          DataCell(Text('${m(k.meter)} m${k.senkrecht > 0 ? ' (↕ ${m(k.senkrecht)})' : ''}${k.geschaetzt ? ' ≈' : ''}')),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Summe je Kabeltyp', style: TextStyle(fontWeight: FontWeight.w700)),
                for (final e in jeKabel.entries) Text('${e.key}: ${m(e.value)} m'),
              ]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final f = File(p.join(store.ordner, 'exporte', 'Kabelzugliste.csv'));
            await f.parent.create(recursive: true);
            await f.writeAsString('﻿${kabelzuglisteCsv(l)}');
            if (c.mounted) zeigeHinweis(c, 'Gespeichert unter ${f.path}');
          },
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: const Text('Als CSV (Excel)'),
        ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen')),
      ],
    ),
  );
}
