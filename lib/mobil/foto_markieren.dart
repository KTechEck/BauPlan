import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Foto markieren in der App: Maß (Linie mit Wert), Pfeil, Kreis, Text –
/// mit dem Finger ziehen. Gleiches Format wie am PC (`medium.markierungen`):
/// a/b relativ zum Bild (0…1), art, text, farbe.
class FotoMarkierenSeite extends StatefulWidget {
  const FotoMarkierenSeite({super.key, required this.foto, this.marken = const [], this.massText});
  final List<int> foto;
  final List<Map<String, dynamic>> marken;

  /// Vorgabe für das erste Maß (z. B. der eingegebene Messwert „1250 mm“).
  final String? massText;

  @override
  State<FotoMarkierenSeite> createState() => _FotoMarkierenSeiteState();
}

class _FotoMarkierenSeiteState extends State<FotoMarkierenSeite> {
  ui.Image? _bild;
  late final List<Map<String, dynamic>> _marken = [...widget.marken];
  String _art = 'mass';
  int _farbe = 0xFFE03131;
  Offset? _a, _b;
  Rect _rect = Rect.zero;

  @override
  void initState() {
    super.initState();
    ui.decodeImageFromList(Uint8List.fromList(widget.foto), (b) {
      if (mounted) setState(() => _bild = b);
    });
  }

  Offset _rel(Offset p) => Offset(((p.dx - _rect.left) / _rect.width).clamp(0, 1), ((p.dy - _rect.top) / _rect.height).clamp(0, 1));

  Future<void> _fertigZiehen() async {
    final a = _a, b = _b;
    setState(() {
      _a = null;
      _b = null;
    });
    if (a == null) return;
    final ende = b ?? a;
    var text = '';
    if (_art == 'mass' || _art == 'text') {
      final ctrl = TextEditingController(text: _art == 'mass' && !_marken.any((m) => m['art'] == 'mass') ? (widget.massText ?? '') : '');
      final t = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(_art == 'mass' ? 'Maß an der Linie' : 'Text'),
          content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: _art == 'mass' ? 'z. B. 1250 mm' : 'z. B. Leerrohr DN 20')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('OK')),
          ],
        ),
      );
      if (t == null) return;
      text = t;
    }
    setState(() => _marken.add({
          'art': _art,
          'a': [_rel(a).dx, _rel(a).dy],
          'b': [_rel(ende).dx, _rel(ende).dy],
          if (text.isNotEmpty) 'text': text,
          'farbe': _farbe,
        }));
  }

  @override
  Widget build(BuildContext context) {
    final bild = _bild;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Im Foto markieren'),
        actions: [
          IconButton(tooltip: 'Letzte entfernen', onPressed: _marken.isEmpty ? null : () => setState(() => _marken.removeLast()), icon: const Icon(Icons.undo)),
          TextButton(onPressed: () => Navigator.pop(context, _marken), child: const Text('Fertig')),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: bild == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, c) {
                  final s = math.min(c.maxWidth / bild.width, c.maxHeight / bild.height);
                  final w = bild.width * s, h = bild.height * s;
                  _rect = Rect.fromLTWH((c.maxWidth - w) / 2, (c.maxHeight - h) / 2, w, h);
                  return GestureDetector(
                    onPanStart: (d) => setState(() => _a = d.localPosition),
                    onPanUpdate: (d) => setState(() => _b = d.localPosition),
                    onPanEnd: (_) => _fertigZiehen(),
                    onTapUp: (d) {
                      if (_art != 'text') return;
                      _a = d.localPosition;
                      _fertigZiehen();
                    },
                    child: CustomPaint(
                      size: Size(c.maxWidth, c.maxHeight),
                      painter: AppMarkierungsPainter(bild: bild, rect: _rect, marken: [
                        ..._marken,
                        if (_a != null && _b != null) {'art': _art, 'a': [_rel(_a!).dx, _rel(_a!).dy], 'b': [_rel(_b!).dx, _rel(_b!).dy], 'farbe': _farbe},
                      ]),
                    ),
                  );
                }),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(8),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'mass', icon: Icon(Icons.straighten), label: Text('Maß')),
                  ButtonSegment(value: 'pfeil', icon: Icon(Icons.arrow_outward), label: Text('Pfeil')),
                  ButtonSegment(value: 'kreis', icon: Icon(Icons.circle_outlined), label: Text('Kreis')),
                  ButtonSegment(value: 'text', icon: Icon(Icons.title), label: Text('Text')),
                ],
                selected: {_art},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _art = v.first),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final f in const [0xFFE03131, 0xFFFAB005, 0xFF2F9E44, 0xFF1C7ED6, 0xFFFFFFFF])
                  GestureDetector(
                    onTap: () => setState(() => _farbe = f),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: Color(f), shape: BoxShape.circle, border: Border.all(color: f == _farbe ? BsFarben.akzent : const Color(0xFFCED4DA), width: 3)),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(_art == 'text' ? 'Tippen, wo der Text stehen soll.' : 'Mit dem Finger von Anfang bis Ende ziehen.', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Zeichnet Foto und Markierungen (wie am PC).
class AppMarkierungsPainter extends CustomPainter {
  AppMarkierungsPainter({required this.bild, required this.rect, required this.marken});
  final ui.Image bild;
  final Rect rect;
  final List<Map<String, dynamic>> marken;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(bild, Rect.fromLTWH(0, 0, bild.width.toDouble(), bild.height.toDouble()), rect, Paint()..filterQuality = FilterQuality.medium);
    final dicke = math.max(2.0, rect.width / 300);
    for (final m in marken) {
      Offset pkt(String k) {
        final l = m[k] as List;
        return Offset(rect.left + (l[0] as num) * rect.width, rect.top + (l[1] as num) * rect.height);
      }

      final a = pkt('a'), b = pkt('b');
      final farbe = Color((m['farbe'] as num?)?.toInt() ?? 0xFFE03131);
      final stift = Paint()
        ..color = farbe
        ..strokeWidth = dicke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final text = m['text'] as String? ?? '';
      switch (m['art']) {
        case 'pfeil':
          canvas.drawLine(a, b, stift);
          final r = (b - a).direction;
          final k = dicke * 6;
          canvas.drawPath(
              Path()
                ..moveTo(b.dx, b.dy)
                ..lineTo(b.dx - k * math.cos(r - 0.45), b.dy - k * math.sin(r - 0.45))
                ..lineTo(b.dx - k * math.cos(r + 0.45), b.dy - k * math.sin(r + 0.45))
                ..close(),
              Paint()..color = farbe);
        case 'kreis':
          canvas.drawOval(Rect.fromPoints(a, b), stift);
        case 'mass':
          canvas.drawLine(a, b, stift);
          final n = Offset(-(b - a).dy, (b - a).dx) / math.max(1, (b - a).distance) * dicke * 4;
          canvas.drawLine(a - n, a + n, stift);
          canvas.drawLine(b - n, b + n, stift);
          _schrift(canvas, text, (a + b) / 2, farbe, dicke);
        case 'text':
          _schrift(canvas, text, a, farbe, dicke);
      }
    }
  }

  void _schrift(Canvas c, String t, Offset p, Color farbe, double dicke) {
    if (t.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: math.max(13, dicke * 7), color: farbe, fontWeight: FontWeight.w700, backgroundColor: Colors.black.withValues(alpha: 0.5))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant AppMarkierungsPainter old) => true;
}
