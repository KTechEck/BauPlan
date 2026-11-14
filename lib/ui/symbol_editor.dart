import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/ids.dart';
import '../data/project_store.dart';
import '../state/app_state.dart';

/// Eigene Plansymbole: einfache Linien, Kreise, Rechtecke und Text auf einem
/// Raster von −20 … 20, gespeichert in der Projekteinstellung `eigene_symbole`;
/// Zuordnung Objekttyp → Symbol in `symbol_zuordnung`.

typedef SymbolTeil = Map<String, dynamic>; // {t: l|k|r|t, …}

class EigenesSymbol {
  EigenesSymbol(this.id, this.name, this.teile);
  final String id, name;
  final List<SymbolTeil> teile;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'teile': teile};
  static EigenesSymbol ausJson(Map m) => EigenesSymbol('${m['id']}', '${m['name'] ?? ''}', [for (final t in (m['teile'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)]);
}

List<EigenesSymbol> eigeneSymbole(ProjectStore store) => [for (final m in (store.einstellung<List>('eigene_symbole') ?? const [])) if (m is Map) EigenesSymbol.ausJson(m)];

/// Eigenes Symbol eines Objekttyps oder null.
EigenesSymbol? symbolFuerTyp(ProjectStore store, String typId) {
  final id = (store.einstellung<Map>('symbol_zuordnung') ?? const {})[typId];
  if (id == null) return null;
  return eigeneSymbole(store).where((s) => s.id == id).firstOrNull;
}

/// Zeichnet ein eigenes Symbol um [mitte] mit Radius [rad] (Raster ±20 → ±rad).
void eigenesSymbolZeichnen(Canvas c, EigenesSymbol s, Offset mitte, double rad, Color farbe, {double drehung = 0}) {
  final f = rad / 20;
  final p = Paint()
    ..color = farbe
    ..strokeWidth = math.max(1.0, f * 1.6)
    ..style = PaintingStyle.stroke;
  c.save();
  c.translate(mitte.dx, mitte.dy);
  if (drehung != 0) c.rotate(drehung);
  c.drawCircle(Offset.zero, rad, Paint()..color = Colors.white.withValues(alpha: 0.85));
  double z(Object? v) => (v as num? ?? 0).toDouble() * f;
  for (final t in s.teile) {
    switch (t['t']) {
      case 'l':
        c.drawLine(Offset(z(t['x1']), z(t['y1'])), Offset(z(t['x2']), z(t['y2'])), p);
      case 'k':
        c.drawCircle(Offset(z(t['x']), z(t['y'])), z(t['r']).abs(), p);
      case 'r':
        c.drawRect(Rect.fromLTWH(z(t['x']), z(t['y']), z(t['b']), z(t['h'])), p);
      case 't':
        final tp = TextPainter(
          text: TextSpan(text: '${t['text'] ?? ''}', style: TextStyle(fontSize: math.max(6, 9 * f), color: farbe, fontWeight: FontWeight.w600, fontFamily: 'Roboto')),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset(z(t['x']), z(t['y'])) - Offset(tp.width / 2, tp.height / 2));
    }
  }
  c.restore();
}

/// Editor für eigene Symbole; mit [typId] wird das Symbol diesem Objekttyp zugeordnet.
Future<void> symbolEditor(BuildContext context, AppState s, {String? typId, String? typName}) =>
    showDialog<void>(context: context, builder: (_) => _SymbolEditor(state: s, typId: typId, typName: typName));

class _SymbolEditor extends StatefulWidget {
  const _SymbolEditor({required this.state, this.typId, this.typName});
  final AppState state;
  final String? typId, typName;
  @override
  State<_SymbolEditor> createState() => _SymbolEditorState();
}

class _SymbolEditorState extends State<_SymbolEditor> {
  String _werkzeug = 'l';
  final _teile = <SymbolTeil>[];
  final _name = TextEditingController();
  final _text = TextEditingController(text: 'A');
  Offset? _start, _jetzt;
  String? _id;

  static const _feld = 240.0;
  Offset _raster(Offset px) => Offset(((px.dx / _feld * 40 - 20) * 2).round() / 2, ((px.dy / _feld * 40 - 20) * 2).round() / 2);

  @override
  void initState() {
    super.initState();
    final store = widget.state.store!;
    final vorhanden = widget.typId == null ? null : symbolFuerTyp(store, widget.typId!);
    if (vorhanden != null) {
      _id = vorhanden.id;
      _teile.addAll(vorhanden.teile);
      _name.text = vorhanden.name;
    } else {
      _name.text = widget.typName ?? 'Eigenes Symbol';
    }
  }

  void _speichern() {
    final store = widget.state.store!;
    final id = _id ?? neueId();
    final alle = [for (final x in eigeneSymbole(store)) if (x.id != id) x, EigenesSymbol(id, _name.text.trim(), _teile)];
    store.einstellungSetzen('eigene_symbole', [for (final x in alle) x.toJson()]);
    if (widget.typId != null) {
      store.einstellungSetzen('symbol_zuordnung', {...(store.einstellung<Map>('symbol_zuordnung') ?? const {}), widget.typId!: id});
    }
    widget.state.geaendert();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final vorschau = EigenesSymbol('v', _name.text, [
      ..._teile,
      if (_start != null && _jetzt != null) _teil(_start!, _jetzt!),
    ]);
    return AlertDialog(
      title: Text(widget.typName == null ? 'Eigenes Symbol' : 'Eigenes Symbol für „${widget.typName}“'),
      content: SizedBox(
        width: 560,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onPanStart: (d) => setState(() => _start = _jetzt = _raster(d.localPosition)),
            onPanUpdate: (d) => setState(() => _jetzt = _raster(d.localPosition)),
            onPanEnd: (_) => setState(() {
              if (_start != null && _jetzt != null) _teile.add(_teil(_start!, _jetzt!));
              _start = _jetzt = null;
            }),
            onTapUp: (d) {
              if (_werkzeug != 't') return;
              final p = _raster(d.localPosition);
              setState(() => _teile.add({'t': 't', 'x': p.dx, 'y': p.dy, 'text': _text.text}));
            },
            child: Container(
              width: _feld,
              height: _feld,
              decoration: BoxDecoration(border: Border.all(color: BsFarben.rand), color: Colors.white),
              child: CustomPaint(painter: _EditorPainter(vorschau)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (w, l) in const [('l', 'Linie'), ('k', 'Kreis'), ('r', 'Rechteck'), ('t', 'Text')])
                  ChoiceChip(label: Text(l), selected: _werkzeug == w, onSelected: (_) => setState(() => _werkzeug = w)),
              ]),
              if (_werkzeug == 't') TextField(controller: _text, decoration: const InputDecoration(labelText: 'Text (Klick setzt)')),
              const SizedBox(height: 8),
              Wrap(children: [
                TextButton.icon(onPressed: _teile.isEmpty ? null : () => setState(_teile.removeLast), icon: const Icon(Icons.undo, size: 18), label: const Text('Zurück')),
                TextButton.icon(onPressed: _teile.isEmpty ? null : () => setState(_teile.clear), icon: const Icon(Icons.clear, size: 18), label: const Text('Leeren')),
              ]),
              const SizedBox(height: 8),
              const Text('Vorschau im Plan:', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              SizedBox(width: 60, height: 60, child: CustomPaint(painter: _VorschauPainter(vorschau))),
              if (widget.typId != null && _id != null)
                TextButton(
                  onPressed: () {
                    final store = widget.state.store!;
                    store.einstellungSetzen('symbol_zuordnung', {...(store.einstellung<Map>('symbol_zuordnung') ?? const {})}..remove(widget.typId));
                    widget.state.geaendert();
                    Navigator.pop(context);
                  },
                  child: const Text('Wieder Standardsymbol verwenden'),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: _teile.isEmpty ? null : _speichern, child: const Text('Speichern')),
      ],
    );
  }

  SymbolTeil _teil(Offset a, Offset b) => switch (_werkzeug) {
        'k' => {'t': 'k', 'x': a.dx, 'y': a.dy, 'r': (b - a).distance},
        'r' => {'t': 'r', 'x': math.min(a.dx, b.dx), 'y': math.min(a.dy, b.dy), 'b': (b.dx - a.dx).abs(), 'h': (b.dy - a.dy).abs()},
        _ => {'t': 'l', 'x1': a.dx, 'y1': a.dy, 'x2': b.dx, 'y2': b.dy},
      };
}

class _EditorPainter extends CustomPainter {
  _EditorPainter(this.s);
  final EigenesSymbol s;
  @override
  void paint(Canvas c, Size size) {
    final r = Paint()..color = BsFarben.raster;
    for (var i = 0; i <= 40; i += 5) {
      final x = i / 40 * size.width;
      c.drawLine(Offset(x, 0), Offset(x, size.height), r);
      c.drawLine(Offset(0, x), Offset(size.width, x), r);
    }
    c.drawCircle(size.center(Offset.zero), size.width / 2, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black12);
    eigenesSymbolZeichnen(c, s, size.center(Offset.zero), size.width / 2, Colors.black87);
  }

  @override
  bool shouldRepaint(_EditorPainter o) => true;
}

class _VorschauPainter extends CustomPainter {
  _VorschauPainter(this.s);
  final EigenesSymbol s;
  @override
  void paint(Canvas c, Size size) => eigenesSymbolZeichnen(c, s, size.center(Offset.zero), 10, const Color(0xFFE6A700));
  @override
  bool shouldRepaint(_VorschauPainter o) => true;
}
