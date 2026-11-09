import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// Eigenes Profil (Querschnitt) eines Bauteils, z. B. Rollladenschiene mit zwei
/// Kammern: geschlossene Linienzüge in mm, Ursprung links oben.
typedef Profil = List<List<Offset>>;

Profil profilLesen(Object? daten) => [
      for (final kontur in (daten as List? ?? const []))
        [for (final p in (kontur as List)) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
    ];

List<List<List<double>>> profilSchreiben(Profil p) => [
      for (final k in p) [for (final q in k) [q.dx, q.dy]],
    ];

/// Profil zeichnen: Klick setzt Punkte im Raster, Klick auf den ersten Punkt
/// schließt die Kontur, Punkte ziehen, Entf löscht den gewählten Punkt.
Future<Profil?> profilZeichnen(BuildContext context, Profil start, {String titel = 'Profil zeichnen'}) =>
    showDialog<Profil>(context: context, builder: (_) => _ProfilEditor(start: start, titel: titel));

class _ProfilEditor extends StatefulWidget {
  const _ProfilEditor({required this.start, required this.titel});
  final Profil start;
  final String titel;

  @override
  State<_ProfilEditor> createState() => _ProfilEditorState();
}

class _ProfilEditorState extends State<_ProfilEditor> {
  late final Profil _konturen = [for (final k in widget.start) [...k]];
  final List<Offset> _offen = [];
  (int, int)? _gewaehlt; // Kontur (−1 = offene), Punkt
  bool _ziehen = false;
  double _raster = 1; // mm
  double _massstab = 6; // px je mm
  final _fokus = FocusNode();

  @override
  void dispose() {
    _fokus.dispose();
    super.dispose();
  }

  static const _rand = 30.0;
  Offset _zuBild(Offset mm) => const Offset(_rand, _rand) + mm * _massstab;
  Offset _zuMm(Offset px) {
    final m = (px - const Offset(_rand, _rand)) / _massstab;
    return Offset((m.dx / _raster).round() * _raster, (m.dy / _raster).round() * _raster);
  }

  (int, int)? _treffer(Offset px) {
    for (final (i, k) in _konturen.indexed) {
      for (final (j, q) in k.indexed) {
        if ((_zuBild(q) - px).distance < 8) return (i, j);
      }
    }
    for (final (j, q) in _offen.indexed) {
      if ((_zuBild(q) - px).distance < 8) return (-1, j);
    }
    return null;
  }

  void _klick(Offset px) {
    _fokus.requestFocus();
    final t = _treffer(px);
    if (t != null) {
      // erster Punkt der offenen Kontur schließt sie
      if (t.$1 == -1 && t.$2 == 0 && _offen.length >= 3) {
        setState(() {
          _konturen.add([..._offen]);
          _offen.clear();
          _gewaehlt = null;
        });
        return;
      }
      setState(() {
        _gewaehlt = t;
        _ziehen = true;
      });
      return;
    }
    setState(() {
      _offen.add(_zuMm(px));
      _gewaehlt = (-1, _offen.length - 1);
    });
  }

  void _verschieben(Offset px) {
    final g = _gewaehlt;
    if (!_ziehen || g == null) return;
    setState(() {
      if (g.$1 == -1) {
        _offen[g.$2] = _zuMm(px);
      } else {
        _konturen[g.$1][g.$2] = _zuMm(px);
      }
    });
  }

  void _loeschen() {
    final g = _gewaehlt;
    if (g == null) return;
    setState(() {
      if (g.$1 == -1) {
        _offen.removeAt(g.$2);
      } else {
        _konturen[g.$1].removeAt(g.$2);
        if (_konturen[g.$1].length < 3) _konturen.removeAt(g.$1);
      }
      _gewaehlt = null;
    });
  }

  /// Rechteck als Startform (z. B. Schienenkörper).
  Future<void> _rechteck() async {
    final b = TextEditingController(text: '53'), h = TextEditingController(text: '22');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechteck'),
        content: Row(children: [
          Expanded(child: TextField(controller: b, decoration: const InputDecoration(labelText: 'Breite', suffixText: 'mm'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: h, decoration: const InputDecoration(labelText: 'Tiefe', suffixText: 'mm'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Einfügen')),
        ],
      ),
    );
    final x = double.tryParse(b.text.replaceAll(',', '.')), y = double.tryParse(h.text.replaceAll(',', '.'));
    if (ok != true || x == null || y == null) return;
    setState(() => _konturen.add([Offset.zero, Offset(x, 0), Offset(x, y), Offset(0, y)]));
  }

  @override
  Widget build(BuildContext context) {
    final alle = [..._konturen.expand((k) => k), ..._offen];
    final ausdehnung = alle.isEmpty
        ? '–'
        : '${(alle.map((p) => p.dx).reduce(math.max) - alle.map((p) => p.dx).reduce(math.min)).toStringAsFixed(1)} × '
            '${(alle.map((p) => p.dy).reduce(math.max) - alle.map((p) => p.dy).reduce(math.min)).toStringAsFixed(1)} mm';
    return AlertDialog(
      title: Text(widget.titel),
      content: SizedBox(
        width: 860,
        height: 560,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: _rechteck, icon: const Icon(Icons.crop_square, size: 18), label: const Text('Rechteck …')),
            OutlinedButton.icon(
              onPressed: _gewaehlt == null ? null : _loeschen,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Punkt löschen (Entf)'),
            ),
            OutlinedButton.icon(
              onPressed: _offen.isEmpty && _konturen.isEmpty ? null : () => setState(() {
                    _offen.clear();
                    _konturen.clear();
                    _gewaehlt = null;
                  }),
              icon: const Icon(Icons.layers_clear_outlined, size: 18),
              label: const Text('Alles leeren'),
            ),
            const SizedBox(width: 12),
            const Text('Raster'),
            DropdownButton<double>(
              value: _raster,
              items: const [
                DropdownMenuItem(value: 0.5, child: Text('0,5 mm')),
                DropdownMenuItem(value: 1, child: Text('1 mm')),
                DropdownMenuItem(value: 5, child: Text('5 mm')),
              ],
              onChanged: (v) => setState(() => _raster = v ?? 1),
            ),
            const Text('Zoom'),
            SizedBox(
              width: 140,
              child: Slider(value: _massstab, min: 2, max: 16, onChanged: (v) => setState(() => _massstab = v)),
            ),
            Text('Außenmaß $ausdehnung', style: const TextStyle(color: BsFarben.textLeise)),
          ]),
          const Text('Klick setzt Punkte, Klick auf den ersten Punkt schließt die Kontur (z. B. eine Kammer). Punkte lassen sich ziehen. Maße stehen an jeder Kante.',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          const SizedBox(height: 6),
          Expanded(
            child: Focus(
              focusNode: _fokus,
              autofocus: true,
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.delete || e.logicalKey == LogicalKeyboardKey.backspace)) {
                  _loeschen();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: ClipRect(
                child: Listener(
                  onPointerDown: (e) => _klick(e.localPosition),
                  onPointerMove: (e) => _verschieben(e.localPosition),
                  onPointerUp: (_) => _ziehen = false,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _ProfilPainter(konturen: _konturen, offen: _offen, gewaehlt: _gewaehlt, zuBild: _zuBild, massstab: _massstab, raster: _raster),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(context, [..._konturen, if (_offen.length >= 3) [..._offen]]),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

class _ProfilPainter extends CustomPainter {
  _ProfilPainter({required this.konturen, required this.offen, required this.gewaehlt, required this.zuBild, required this.massstab, required this.raster});
  final Profil konturen;
  final List<Offset> offen;
  final (int, int)? gewaehlt;
  final Offset Function(Offset) zuBild;
  final double massstab, raster;

  void _mass(Canvas c, Offset a, Offset b) {
    final l = (b - a).distance;
    if (l < 0.01) return;
    final pa = zuBild(a), pb = zuBild(b);
    final tp = TextPainter(
      text: TextSpan(text: l.toStringAsFixed(l == l.roundToDouble() ? 0 : 1), style: const TextStyle(fontSize: 10, color: BsFarben.akzentDunkel, backgroundColor: Colors.white70)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, (pa + pb) / 2 - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    // Raster: fein je Raster, kräftig je 10 mm
    final fein = Paint()..color = const Color(0xFFF1F3F5), grob = Paint()..color = const Color(0xFFDEE2E6);
    final schritt = raster * massstab < 4 ? 5.0 : raster;
    final o = zuBild(Offset.zero);
    for (var x = 0.0; o.dx + x * massstab < size.width; x += schritt) {
      final px = o.dx + x * massstab;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), x % 10 == 0 ? grob : fein);
    }
    for (var y = 0.0; o.dy + y * massstab < size.height; y += schritt) {
      final py = o.dy + y * massstab;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), y % 10 == 0 ? grob : fein);
    }
    final flaeche = Paint()..color = const Color(0x33868E96);
    final linie = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF343A40);
    for (final (i, k) in konturen.indexed) {
      final pfad = Path()..addPolygon([for (final q in k) zuBild(q)], true);
      canvas.drawPath(pfad, flaeche);
      canvas.drawPath(pfad, linie);
      for (var j = 0; j < k.length; j++) {
        _mass(canvas, k[j], k[(j + 1) % k.length]);
      }
      for (final (j, q) in k.indexed) {
        canvas.drawCircle(zuBild(q), gewaehlt == (i, j) ? 5 : 3, Paint()..color = gewaehlt == (i, j) ? BsFarben.akzent : const Color(0xFF343A40));
      }
    }
    if (offen.isNotEmpty) {
      canvas.drawPath(Path()..addPolygon([for (final q in offen) zuBild(q)], false), linie..color = BsFarben.akzent);
      for (var j = 0; j + 1 < offen.length; j++) {
        _mass(canvas, offen[j], offen[j + 1]);
      }
      for (final (j, q) in offen.indexed) {
        canvas.drawCircle(zuBild(q), j == 0 ? 6 : 3, Paint()..color = BsFarben.akzent);
      }
    }
  }

  @override
  bool shouldRepaint(_ProfilPainter old) => true;
}
