import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/aufmass.dart';
import '../../core/sparren.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// Sparren eines Geschosses: Felder anlegen (an einer Wand, je Raum oder
/// fürs ganze Geschoss), Achsabstand, Querschnitt, Länge mit Überstand,
/// Neigung bearbeiten; Vorschau mit Wänden. In der App werden dieselben
/// Felder auf der Baustelle aufgemessen.
Future<void> sparrenDialogZeigen(BuildContext context, AppState s, String geschossId, {Wand? wand}) =>
    showDialog<void>(context: context, builder: (_) => _SparrenDialog(state: s, geschossId: geschossId, wand: wand));

class _SparrenDialog extends StatefulWidget {
  const _SparrenDialog({required this.state, required this.geschossId, this.wand});
  final AppState state;
  final String geschossId;
  final Wand? wand;

  @override
  State<_SparrenDialog> createState() => _SparrenDialogState();
}

class _SparrenDialogState extends State<_SparrenDialog> {
  String? _gewaehlt;

  void _speichern(List<Sparrenfeld> l) {
    sparrenfelderSetzen(widget.state.store!, widget.geschossId, l);
    widget.state.geaendert();
    setState(() {});
  }

  void _neu({required bool ganzesGeschoss, required bool links}) {
    final store = widget.state.store!;
    final w = widget.wand!;
    final raeume = store.raeume(widget.geschossId);
    final st = raumStuecke(w, links, raeume);
    final raum = st.entries.isEmpty ? null : st.entries.first;
    final f = sparrenfeldAnWand(w,
        links: links,
        von: ganzesGeschoss ? null : raum?.value.$1,
        bis: ganzesGeschoss ? null : raum?.value.$2,
        raumId: ganzesGeschoss ? null : raum?.key);
    _speichern([...sparrenfelder(store, widget.geschossId), f]);
    _gewaehlt = f.id;
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.state.store!;
    final felder = sparrenfelder(store, widget.geschossId);
    final f = felder.where((x) => x.id == _gewaehlt).firstOrNull ?? felder.firstOrNull;
    final waende = store.waende(widget.geschossId);
    return AlertDialog(
      title: const Text('Sparren / Sparrenlage'),
      content: SizedBox(
        width: 860,
        height: 520,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 380,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: CustomPaint(size: Size.infinite, painter: _Vorschau(waende, felder, f?.id))),
              const Text('Sparren dürfen über die Außenwand hinausragen (Dachüberstand, Balkon) – dafür einfach die Länge größer wählen.',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ListView(children: [
              if (widget.wand != null)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final links in [true, false]) ...[
                    OutlinedButton(onPressed: () => _neu(ganzesGeschoss: true, links: links), child: Text('Ganzes Geschoss, Seite ${links ? 'A' : 'B'}')),
                    OutlinedButton(onPressed: () => _neu(ganzesGeschoss: false, links: links), child: Text('Nur Raum, Seite ${links ? 'A' : 'B'}')),
                  ],
                ])
              else
                const Text('Neues Feld: im Grundriss eine Wand wählen (Traufwand) und dort „Sparren …“ öffnen.', style: TextStyle(color: BsFarben.textLeise)),
              const SizedBox(height: 8),
              for (final x in felder)
                ListTile(
                  dense: true,
                  selected: x.id == f?.id,
                  title: Text('${x.art} · ${x.lagen.length} Sparren · ${x.raumId == null ? 'ganzes Geschoss' : 'Raum'}'),
                  subtitle: Text('e = ${x.achsabstand.round()} mm, ${x.breite.round()}×${x.hoehe.round()} mm, Länge ${x.laenge.round()} mm'
                      '${x.positionen.isEmpty ? '' : ' · einzeln gemessen'}'),
                  onTap: () => setState(() => _gewaehlt = x.id),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _speichern([for (final y in felder) if (y.id != x.id) y])),
                ),
              if (f != null) ...[
                const Divider(),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: const ['Dachsparren', 'Sparrendecke / Balkenlage', 'Kehlbalken'].contains(f.art) ? f.art : 'Dachsparren',
                      decoration: const InputDecoration(labelText: 'Art', isDense: true),
                      items: [for (final a in const ['Dachsparren', 'Sparrendecke / Balkenlage', 'Kehlbalken']) DropdownMenuItem(value: a, child: Text(a))],
                      onChanged: (v) => _speichern([for (final y in felder) y.id == f.id ? Sparrenfeld.ausJson({...y.toJson(), 'art': v}) : y]),
                    ),
                  ),
                  for (final e in sparrenFelder.entries)
                    SizedBox(
                      width: 180,
                      child: TextFormField(
                        key: ValueKey('${f.id}-${e.key}-${f.toJson()[e.key]}'),
                        initialValue: '${f.toJson()[e.key]}',
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: InputDecoration(labelText: e.value, suffixText: e.key == 'neigung' ? '°' : 'mm', isDense: true),
                        onFieldSubmitted: (v) {
                          final z = num.tryParse(v.replaceAll(',', '.'));
                          if (z != null) _speichern([for (final y in felder) y.id == f.id ? y.mitWert(e.key, z) : y]);
                        },
                      ),
                    ),
                  SizedBox(
                    width: 120,
                    child: OutlinedButton(
                      onPressed: () => _speichern([for (final y in felder) y.id == f.id ? Sparrenfeld.ausJson({...y.toJson(), 'seite': -y.seite}) : y]),
                      child: const Text('Seite wechseln'),
                    ),
                  ),
                  if (f.positionen.isNotEmpty)
                    OutlinedButton(
                      onPressed: () => _speichern([for (final y in felder) y.id == f.id ? Sparrenfeld.ausJson({...y.toJson()}..remove('positionen')) : y]),
                      child: const Text('Einzelmaße verwerfen (regelmäßig)'),
                    ),
                ]),
              ],
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
    );
  }
}

class _Vorschau extends CustomPainter {
  _Vorschau(this.waende, this.felder, this.gewaehlt);
  final List<Wand> waende;
  final List<Sparrenfeld> felder;
  final String? gewaehlt;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[
      for (final w in waende) ...[Offset(w.x1.toDouble(), w.y1.toDouble()), Offset(w.x2.toDouble(), w.y2.toDouble())],
      for (final f in felder)
        for (final (a, b) in f.strecken) ...[Offset(a.$1, a.$2), Offset(b.$1, b.$2)],
    ];
    if (pts.isEmpty) return;
    var x0 = pts.first.dx, y0 = pts.first.dy, x1 = x0, y1 = y0;
    for (final p in pts) {
      x0 = math.min(x0, p.dx);
      y0 = math.min(y0, p.dy);
      x1 = math.max(x1, p.dx);
      y1 = math.max(y1, p.dy);
    }
    final m = math.min((size.width - 20) / math.max(1, x1 - x0), (size.height - 20) / math.max(1, y1 - y0));
    Offset b(double x, double y) => Offset(10 + (x - x0) * m, 10 + (y - y0) * m);
    for (final w in waende) {
      canvas.drawLine(b(w.x1.toDouble(), w.y1.toDouble()), b(w.x2.toDouble(), w.y2.toDouble()), Paint()
        ..color = const Color(0xFF495057)
        ..strokeWidth = math.max(1.5, w.dicke * m));
    }
    for (final f in felder) {
      final p = Paint()
        ..color = f.id == gewaehlt ? BsFarben.akzent : const Color(0xFF8D6E63)
        ..strokeWidth = math.max(1.0, f.breite * m);
      for (final (a, e) in f.strecken) {
        canvas.drawLine(b(a.$1, a.$2), b(e.$1, e.$2), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Vorschau old) => true;
}
