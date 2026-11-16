import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/wandaufbau.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';

/// Aufbau einer Wandseite bearbeiten: Bereiche (entlang der Wand von/bis,
/// in der Höhe von/bis) mit Schichten vom Kern nach außen.
Future<void> aufbauDialog(BuildContext context, ProjectStore store, Wand w, bool links, String seitenName, {VoidCallback? geaendert}) =>
    showDialog<void>(context: context, builder: (_) => _AufbauDialog(store: store, wand: w, links: links, seitenName: seitenName, geaendert: geaendert));

class _AufbauDialog extends StatefulWidget {
  const _AufbauDialog({required this.store, required this.wand, required this.links, required this.seitenName, this.geaendert});
  final ProjectStore store;
  final Wand wand;
  final bool links;
  final String seitenName;
  final VoidCallback? geaendert;
  @override
  State<_AufbauDialog> createState() => _AufbauDialogState();
}

class _AufbauDialogState extends State<_AufbauDialog> {
  late List<Map<String, dynamic>> _bereiche = [
    for (final b in aufbau(widget.wand, widget.links)) Map<String, dynamic>.from(jsonDecode(jsonEncode(b.toJson())) as Map),
  ];

  String get _key => widget.links ? 'aufbau_l' : 'aufbau_r';

  void _speichern() {
    widget.store.wandEigenschaftenSetzen(widget.wand.id, {_key: _bereiche.isEmpty ? null : _bereiche});
    widget.geaendert?.call();
    setState(() {});
  }

  Widget _zahl(String label, Object? wert, void Function(int?) setzen, {String suffix = 'mm', double breite = 110}) => SizedBox(
        width: breite,
        child: TextFormField(
          initialValue: wert == null ? '' : '$wert',
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
          onChanged: (v) {
            setzen(int.tryParse(v));
            _speichern();
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final materialien = widget.store.materialien();
    final typen = widget.store.wandtypen();
    return AlertDialog(
      title: Text('Aufbau ${widget.seitenName}'),
      content: SizedBox(
        width: 640,
        height: 520,
        child: ListView(children: [
          const Text('Schichten vom Kern nach außen (z. B. Putz, Fliese; außen Kleber, WDVS, Armierung, Oberputz). Mehrere Bereiche für Abschnitte der Wand '
              'oder Höhen, z. B. Fliese im Duschbereich bis 2100 mm. Ohne von/bis gilt ein Bereich für die ganze Wand.',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            PopupMenuButton<Wandtyp>(
              tooltip: 'Schichten aus einem Wandtyp übernehmen',
              onSelected: (t) {
                final a = ausWandtyp(t.schichten);
                final seite = a.eigenschaften[_key];
                setState(() => _bereiche = [
                      for (final b in (seite as List? ?? const [])) Map<String, dynamic>.from(b as Map),
                    ]);
                _speichern();
              },
              itemBuilder: (_) => [for (final t in typen) PopupMenuItem(value: t, child: Text(t.name))],
              child: const Chip(avatar: Icon(Icons.layers_outlined, size: 16), label: Text('Aus Wandtyp …')),
            ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Bereich'),
              onPressed: () {
                setState(() => _bereiche.add({'von': 0, 'bis': widget.wand.laenge.round(), 's': <Map<String, dynamic>>[]}));
                _speichern();
              },
            ),
          ]),
          if (_bereiche.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() => _bereiche.add({'s': <Map<String, dynamic>>[]}));
                  _speichern();
                },
                icon: const Icon(Icons.add),
                label: const Text('Aufbau für die ganze Wand anlegen'),
              ),
            ),
          for (final (i, b) in _bereiche.indexed)
            Card(
              margin: const EdgeInsets.only(top: 10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('Bereich ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    _zahl('von', b['von'], (v) => v == null ? b.remove('von') : b['von'] = v),
                    _zahl('bis', b['bis'], (v) => v == null ? b.remove('bis') : b['bis'] = v),
                    _zahl('Höhe von', b['z_von'], (v) => v == null ? b.remove('z_von') : b['z_von'] = v),
                    _zahl('Höhe bis', b['z_bis'], (v) => v == null ? b.remove('z_bis') : b['z_bis'] = v),
                    IconButton(
                      tooltip: 'Bereich entfernen',
                      onPressed: () {
                        setState(() => _bereiche.removeAt(i));
                        _speichern();
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ]),
                  for (final (j, sch) in ((b['s'] as List?) ?? const []).indexed)
                    Row(children: [
                      Text('${j + 1}.', style: const TextStyle(color: BsFarben.textLeise)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          value: materialien.any((m) => m.id == (sch as Map)['m']) ? sch['m'] as String : null,
                          hint: const Text('Baustoff wählen'),
                          items: [for (final m in materialien) DropdownMenuItem(value: m.id, child: Row(children: [Container(width: 12, height: 12, color: Color(m.farbe)), const SizedBox(width: 6), Expanded(child: Text(m.name, overflow: TextOverflow.ellipsis))]))],
                          onChanged: (v) {
                            (sch as Map)['m'] = v;
                            _speichern();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _zahl('Dicke', (sch as Map)['d'], (v) => sch['d'] = v ?? 0, breite: 100),
                      IconButton(
                        onPressed: () {
                          (b['s'] as List).removeAt(j);
                          _speichern();
                        },
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ]),
                  TextButton.icon(
                    onPressed: () {
                      b['s'] = [...(b['s'] as List? ?? const []), {'m': materialien.firstOrNull?.id, 'd': 15}];
                      _speichern();
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Schicht'),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fertig'))],
    );
  }
}
