import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Werkzeuge zum Markieren.
enum MarkWerkzeug {
  pfeil('Pfeil', Icons.north_east),
  kreis('Kreis', Icons.circle_outlined),
  rechteck('Rechteck', Icons.crop_square),
  mass('Maß', Icons.straighten),
  text('Text', Icons.text_fields);

  const MarkWerkzeug(this.label, this.symbol);
  final String label;
  final IconData symbol;
}

const markFarben = [Color(0xFFE03131), Color(0xFFFFD43B), Color(0xFF1C7ED6), Color(0xFF2F9E44), Colors.white, Colors.black];

/// Foto markieren (Pfeile, Kreise, Rechtecke, Maße, Text). Koordinaten werden
/// relativ zum Bild (0 … 1) gespeichert, das Original bleibt unverändert.
class FotoMarkierenPage extends StatefulWidget {
  const FotoMarkierenPage({super.key, required this.state, required this.mediumId, required this.datei});
  final AppState state;
  final String mediumId;
  final String datei; // absoluter Pfad

  @override
  State<FotoMarkierenPage> createState() => _FotoMarkierenPageState();
}

class _FotoMarkierenPageState extends State<FotoMarkierenPage> {
  ui.Image? _bild;
  String? _fehler;
  MarkWerkzeug _werkzeug = MarkWerkzeug.pfeil;
  Color _farbe = markFarben.first;
  late List<Map<String, dynamic>> _marken = widget.state.store!.fotoMarkierungen(widget.mediumId);
  final List<List<Map<String, dynamic>>> _rueck = [];
  Offset? _start, _jetzt; // relativ 0 … 1
  Rect _bildRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final codec = await ui.instantiateImageCodec(await File(widget.datei).readAsBytes(), targetWidth: 2400);
        final b = (await codec.getNextFrame()).image;
        if (mounted) setState(() => _bild = b);
      } catch (e) {
        if (mounted) setState(() => _fehler = 'Bild kann nicht angezeigt werden (z. B. HEIC): $e');
      }
    }();
  }

  void _speichern(List<Map<String, dynamic>> neu) {
    final alt = widget.state.store!.fotoMarkierungenSetzen(widget.mediumId, neu);
    _rueck.add(alt);
    setState(() => _marken = neu);
    widget.state.geaendert();
  }

  Offset? _relativ(Offset lokal) {
    if (_bildRect.isEmpty) return null;
    return Offset(((lokal.dx - _bildRect.left) / _bildRect.width).clamp(0, 1), ((lokal.dy - _bildRect.top) / _bildRect.height).clamp(0, 1));
  }

  Future<void> _fertig(Offset a, Offset b) async {
    String text = '';
    if (_werkzeug == MarkWerkzeug.text || _werkzeug == MarkWerkzeug.mass) {
      final t = await texteingabe(context,
          titel: _werkzeug == MarkWerkzeug.text ? 'Text' : 'Maß', feld: _werkzeug == MarkWerkzeug.text ? 'Text' : 'Maß (z. B. 1250 mm)', vorschlag: '');
      if (t == null || t.trim().isEmpty) return;
      text = t.trim();
    }
    _speichern([
      ..._marken,
      {'art': _werkzeug.name, 'a': [a.dx, a.dy], 'b': [b.dx, b.dy], 'farbe': _farbe.toARGB32(), 'text': text},
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (_rueck.isEmpty) return;
          final alt = _rueck.removeLast();
          widget.state.store!.fotoMarkierungenSetzen(widget.mediumId, alt);
          setState(() => _marken = alt);
          widget.state.geaendert();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF212529),
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: const Text('Foto markieren'),
            actions: [
              TextButton.icon(
                onPressed: _marken.isEmpty ? null : () => _speichern([]),
                icon: const Icon(Sym.loeschen),
                label: const Text('alle entfernen'),
              ),
            ],
          ),
          body: Column(children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                for (final w in MarkWerkzeug.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(avatar: Icon(w.symbol, size: 16), label: Text(w.label), selected: _werkzeug == w, onSelected: (_) => setState(() => _werkzeug = w)),
                  ),
                const SizedBox(width: 16),
                for (final f in markFarben)
                  GestureDetector(
                    onTap: () => setState(() => _farbe = f),
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: f, shape: BoxShape.circle, border: Border.all(color: f == _farbe ? BsFarben.akzentDunkel : Colors.black26, width: f == _farbe ? 3 : 1)),
                    ),
                  ),
                const Spacer(),
                const Text('Ziehen zeichnet · Strg+Z rückgängig · Klick auf eine Markierung mit der rechten Maustaste löscht sie',
                    style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
              ]),
            ),
            Expanded(
              child: _fehler != null
                  ? Center(child: Text(_fehler!, style: const TextStyle(color: Colors.white)))
                  : _bild == null
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(builder: (context, c) {
                          final b = _bild!;
                          final s = math.min(c.maxWidth / b.width, c.maxHeight / b.height);
                          final w = b.width * s, h = b.height * s;
                          _bildRect = Rect.fromLTWH((c.maxWidth - w) / 2, (c.maxHeight - h) / 2, w, h);
                          return Listener(
                            onPointerDown: (e) {
                              final r = _relativ(e.localPosition);
                              if (r == null) return;
                              if (e.buttons == 2) {
                                // rechte Maustaste: nächste Markierung löschen
                                var best = -1;
                                var dist = 0.03;
                                for (var i = 0; i < _marken.length; i++) {
                                  final a = _marken[i]['a'] as List;
                                  final d = (Offset((a[0] as num).toDouble(), (a[1] as num).toDouble()) - r).distance;
                                  if (d < dist) {
                                    dist = d;
                                    best = i;
                                  }
                                }
                                if (best >= 0) _speichern([for (var i = 0; i < _marken.length; i++) if (i != best) _marken[i]]);
                                return;
                              }
                              setState(() {
                                _start = r;
                                _jetzt = r;
                              });
                            },
                            onPointerMove: (e) {
                              if (_start == null) return;
                              setState(() => _jetzt = _relativ(e.localPosition));
                            },
                            onPointerUp: (_) {
                              final a = _start, b2 = _jetzt;
                              setState(() {
                                _start = null;
                                _jetzt = null;
                              });
                              if (a == null || b2 == null) return;
                              if (_werkzeug != MarkWerkzeug.text && (b2 - a).distance < 0.005) return;
                              _fertig(a, b2);
                            },
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: MarkierungsPainter(
                                bild: b,
                                bildRect: _bildRect,
                                marken: [
                                  ..._marken,
                                  if (_start != null && _jetzt != null)
                                    {'art': _werkzeug.name, 'a': [_start!.dx, _start!.dy], 'b': [_jetzt!.dx, _jetzt!.dy], 'farbe': _farbe.toARGB32(), 'text': ''},
                                ],
                              ),
                            ),
                          );
                        }),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Zeichnet Bild und Markierungen (auch für Vorschauen nutzbar).
class MarkierungsPainter extends CustomPainter {
  MarkierungsPainter({required this.bild, required this.bildRect, required this.marken});
  final ui.Image bild;
  final Rect bildRect;
  final List<Map<String, dynamic>> marken;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(bild, Rect.fromLTWH(0, 0, bild.width.toDouble(), bild.height.toDouble()), bildRect, Paint()..filterQuality = FilterQuality.medium);
    final dicke = math.max(2.0, bildRect.width / 300);
    for (final m in marken) {
      Offset pkt(String k) {
        final l = m[k] as List;
        return Offset(bildRect.left + (l[0] as num) * bildRect.width, bildRect.top + (l[1] as num) * bildRect.height);
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
          final spitze = Path()
            ..moveTo(b.dx, b.dy)
            ..lineTo(b.dx - k * math.cos(r - 0.45), b.dy - k * math.sin(r - 0.45))
            ..lineTo(b.dx - k * math.cos(r + 0.45), b.dy - k * math.sin(r + 0.45))
            ..close();
          canvas.drawPath(spitze, Paint()..color = farbe);
        case 'kreis':
          canvas.drawOval(Rect.fromPoints(a, b), stift);
        case 'rechteck':
          canvas.drawRect(Rect.fromPoints(a, b), stift);
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
      text: TextSpan(
        text: t,
        style: TextStyle(fontSize: math.max(12, dicke * 7), color: farbe, fontWeight: FontWeight.w700, backgroundColor: Colors.black.withValues(alpha: 0.45)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant MarkierungsPainter old) => true;
}

/// 360°-Ansicht eines Panoramafotos (equirektangular): Ziehen dreht den
/// Blick ringsum, Mausrad zoomt. Vereinfachte Zylinderdarstellung.
class PanoramaPage extends StatefulWidget {
  const PanoramaPage({super.key, required this.datei, required this.titel});
  final String datei;
  final String titel;

  @override
  State<PanoramaPage> createState() => _PanoramaPageState();
}

class _PanoramaPageState extends State<PanoramaPage> {
  ui.Image? _bild;
  double _gier = 0; // 0 … 1 (ein Umlauf)
  double _neigung = 0.5; // 0 oben … 1 unten
  double _sicht = 0.25; // sichtbarer Anteil des Umlaufs
  String? _fehler;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final codec = await ui.instantiateImageCodec(await File(widget.datei).readAsBytes(), targetWidth: 4096);
        final b = (await codec.getNextFrame()).image;
        if (mounted) setState(() => _bild = b);
      } catch (e) {
        if (mounted) setState(() => _fehler = '$e');
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('360° · ${widget.titel}'),
        actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 16), child: Text('Blick ${(_gier * 360).round() % 360}°')))],
      ),
      body: _fehler != null
          ? Center(child: Text(_fehler!, style: const TextStyle(color: Colors.white)))
          : _bild == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, c) {
                  return Listener(
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) setState(() => _sicht = (_sicht * (e.scrollDelta.dy > 0 ? 1.1 : 0.9)).clamp(0.08, 0.6));
                    },
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() {
                        _gier = (_gier - d.delta.dx / c.maxWidth * _sicht) % 1;
                        _neigung = (_neigung - d.delta.dy / c.maxHeight * 0.5).clamp(0.0, 1.0);
                      }),
                      child: CustomPaint(size: Size.infinite, painter: _PanoramaPainter(_bild!, _gier, _neigung, _sicht)),
                    ),
                  );
                }),
    );
  }
}

class _PanoramaPainter extends CustomPainter {
  _PanoramaPainter(this.bild, this.gier, this.neigung, this.sicht);
  final ui.Image bild;
  final double gier, neigung, sicht;

  @override
  void paint(Canvas canvas, Size size) {
    final bw = bild.width.toDouble(), bh = bild.height.toDouble();
    final quelleB = bw * sicht;
    final quelleH = math.min(bh, quelleB * size.height / size.width);
    final top = (bh - quelleH) * neigung;
    final links = gier * bw - quelleB / 2;
    final p = Paint()..filterQuality = FilterQuality.medium;
    // bis zu drei Teilstücke, damit der Umlauf nahtlos weitergeht
    for (final versatz in [-bw, 0.0, bw]) {
      final l = links + versatz;
      final r = l + quelleB;
      final schnittL = math.max(l, 0.0), schnittR = math.min(r, bw);
      if (schnittR <= schnittL) continue;
      final zielL = (schnittL - l) / quelleB * size.width, zielR = (schnittR - l) / quelleB * size.width;
      canvas.drawImageRect(bild, Rect.fromLTRB(schnittL, top, schnittR, top + quelleH), Rect.fromLTRB(zielL, 0, zielR, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _PanoramaPainter old) => true;
}

/// Panorama am Seitenverhältnis erkennen (equirektangular ca. 2 : 1).
bool siehtNachPanoramaAus(int breite, int hoehe) => hoehe > 0 && (breite / hoehe - 2).abs() < 0.05;
