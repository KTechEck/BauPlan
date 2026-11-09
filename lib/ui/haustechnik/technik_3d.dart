import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/drei_d.dart';
import '../../core/raumerkennung.dart';

/// 3D-Ansicht eines Raums: Boden, Wände (durchscheinend), Geräte als Quader,
/// Leitungen mit ihrem Durchmesser. Ziehen dreht, Mausrad zoomt, rechte
/// Maustaste verschiebt. Kollisionen werden rot markiert.
class Raum3dAnsicht extends StatefulWidget {
  const Raum3dAnsicht({
    super.key,
    required this.umriss,
    required this.raumhoehe,
    required this.geraete,
    required this.leitungen,
    this.farben = const {},
    this.auswahl,
    this.onAuswahl,
    this.waende = const [],
    this.ebenen = const [],
  });

  /// Wände des Geschosses als Quader (durchscheinend, ohne Kollisionsprüfung).
  final List<Quader> waende;

  /// Verlegeebenen als waagerechte Flächen: (Name, Höhe über FFB, Farbe).
  final List<(String, double, Color)> ebenen;

  final List<Punkt> umriss;
  final double raumhoehe;
  final List<Quader> geraete;
  final List<Leitung3d> leitungen;

  /// Farbe je ID (Gerät oder Leitung).
  final Map<String, Color> farben;
  final String? auswahl;
  final ValueChanged<String?>? onAuswahl;

  @override
  State<Raum3dAnsicht> createState() => _Raum3dAnsichtState();
}

class _Raum3dAnsichtState extends State<Raum3dAnsicht> {
  late Kamera _k;
  Offset? _letzte;
  bool _verschieben = false;

  @override
  void initState() {
    super.initState();
    final xs = widget.umriss.map((p) => p.x), ys = widget.umriss.map((p) => p.y);
    final mx = (xs.reduce(math.min) + xs.reduce(math.max)) / 2, my = (ys.reduce(math.min) + ys.reduce(math.max)) / 2;
    final groesse = math.max(xs.reduce(math.max) - xs.reduce(math.min), ys.reduce(math.max) - ys.reduce(math.min));
    _k = Kamera(ziel: V3(mx, my, widget.raumhoehe / 3), abstand: math.max(4000, groesse * 1.8));
  }

  @override
  Widget build(BuildContext context) {
    final koll = kollisionen3d(widget.geraete, widget.leitungen);
    return Stack(children: [
      Positioned.fill(
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) setState(() => _k = _k.mit(abstand: _k.abstand * (e.scrollDelta.dy > 0 ? 1.12 : 1 / 1.12)));
          },
          onPointerDown: (e) {
            _letzte = e.localPosition;
            _verschieben = e.buttons == kSecondaryMouseButton || e.buttons == kMiddleMouseButton;
          },
          onPointerMove: (e) {
            final l = _letzte;
            if (l == null) return;
            final d = e.localPosition - l;
            _letzte = e.localPosition;
            setState(() {
              if (_verschieben) {
                final f = _k.abstand / _k.brennweite;
                final ca = math.cos(_k.azimut), sa = math.sin(_k.azimut);
                final dx = -d.dx * f, dy = d.dy * f;
                _k = _k.mit(ziel: _k.ziel + V3(dx * ca + dy * sa, -dx * sa + dy * ca, 0));
              } else {
                _k = _k.mit(azimut: _k.azimut + d.dx * 0.008, neigung: _k.neigung + d.dy * 0.006);
              }
            });
          },
          onPointerUp: (_) => _letzte = null,
          child: CustomPaint(
            painter: _Raum3dPainter(widget, _k, koll.ids),
            child: const SizedBox.expand(),
          ),
        ),
      ),
      Positioned(
        left: 12,
        bottom: 12,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(koll.hinweise.isEmpty ? 'Keine Kollisionen ✓' : '${koll.hinweise.length} Kollisionen',
                style: TextStyle(fontWeight: FontWeight.w600, color: koll.hinweise.isEmpty ? const Color(0xFF2F9E44) : const Color(0xFFB91C1C))),
            for (final h in koll.hinweise.take(6)) Text('• $h', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            const Text('Ziehen dreht · Mausrad zoomt · rechte Maustaste verschiebt', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
          ]),
        ),
      ),
    ]);
  }
}

class _Raum3dPainter extends CustomPainter {
  _Raum3dPainter(this.w, this.k, this.kollision);
  final Raum3dAnsicht w;
  final Kamera k;
  final Set<String> kollision;

  @override
  void paint(Canvas canvas, Size size) {
    final mitte = Offset(size.width / 2, size.height / 2);
    final m = math.min(size.width, size.height) / 900;
    (Offset, double) p(V3 v) {
      final (x, y, t) = k.projizieren(v);
      return (mitte + Offset(x, y) * m, t);
    }

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF7F8F5));
    // Elemente mit Tiefe sammeln und von hinten nach vorne zeichnen
    final teile = <(double, void Function())>[];
    final u = w.umriss;
    // Boden
    final boden = Path()..addPolygon([for (final q in u) p(V3(q.x, q.y, 0)).$1], true);
    canvas.drawPath(boden, Paint()..color = const Color(0xFFE9E4D8));
    canvas.drawPath(boden, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black38);
    // Raster 1 m auf dem Boden
    final xs = u.map((q) => q.x), ys = u.map((q) => q.y);
    final rp = Paint()
      ..color = Colors.black12
      ..strokeWidth = 0.6;
    for (var x = (xs.reduce(math.min) / 1000).ceil() * 1000.0; x < xs.reduce(math.max); x += 1000) {
      canvas.drawLine(p(V3(x, ys.reduce(math.min), 0)).$1, p(V3(x, ys.reduce(math.max), 0)).$1, rp);
    }
    for (var y = (ys.reduce(math.min) / 1000).ceil() * 1000.0; y < ys.reduce(math.max); y += 1000) {
      canvas.drawLine(p(V3(xs.reduce(math.min), y, 0)).$1, p(V3(xs.reduce(math.max), y, 0)).$1, rp);
    }
    // Verlegeebenen als durchscheinende Ebenen über der ganzen Fläche
    for (final (name, z, farbe) in w.ebenen) {
      final pr = [for (final q in u) p(V3(q.x, q.y, z))];
      final tiefe = pr.map((e) => e.$2).reduce((a, b) => a + b) / pr.length;
      teile.add((
        tiefe + 80,
        () {
          final pfad = Path()..addPolygon([for (final e in pr) e.$1], true);
          canvas.drawPath(pfad, Paint()..color = farbe.withValues(alpha: 0.12));
          canvas.drawPath(pfad, Paint()
            ..style = PaintingStyle.stroke
            ..color = farbe.withValues(alpha: 0.6));
          _text(canvas, name, pr.first.$1 + const Offset(30, -14), farbe: farbe);
        }
      ));
    }
    // Wände des Geschosses als Quader
    for (final g in w.waende) {
      final e = g.ecken;
      const flaechen = [
        [4, 5, 6, 7],
        [0, 1, 5, 4],
        [1, 2, 6, 5],
        [2, 3, 7, 6],
        [3, 0, 4, 7],
      ];
      for (final (i, f) in flaechen.indexed) {
        final pr = [for (final n in f) p(e[n])];
        final tiefe = pr.map((x) => x.$2).reduce((a, b) => a + b) / 4;
        teile.add((
          tiefe + 20,
          () {
            final pfad = Path()..addPolygon([for (final x in pr) x.$1], true);
            canvas.drawPath(pfad, Paint()..color = (i == 0 ? const Color(0xFF868E96) : const Color(0xFFADB5BD)).withValues(alpha: i == 0 ? 0.55 : 0.18));
            canvas.drawPath(pfad, Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.6
              ..color = Colors.black26);
          }
        ));
      }
    }
    // Raumumriss als durchscheinende Flächen (nur ohne Geschosswände)
    for (var i = 0; i < (w.waende.isEmpty ? u.length : 0); i++) {
      final a = u[i], b = u[(i + 1) % u.length];
      final ecken = [V3(a.x, a.y, 0), V3(b.x, b.y, 0), V3(b.x, b.y, w.raumhoehe), V3(a.x, a.y, w.raumhoehe)];
      final pr = [for (final e in ecken) p(e)];
      final tiefe = pr.map((e) => e.$2).reduce((x, y) => x + y) / 4;
      teile.add((
        tiefe + 50,
        () {
          final pfad = Path()..addPolygon([for (final e in pr) e.$1], true);
          canvas.drawPath(pfad, Paint()..color = const Color(0x22868E96));
          canvas.drawPath(pfad, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = Colors.black26);
        }
      ));
    }
    // Geräte
    for (final g in w.geraete) {
      final e = g.ecken;
      final farbe = kollision.contains(g.id) ? const Color(0xFFE03131) : (w.farben[g.id] ?? const Color(0xFF868E96));
      const flaechen = [
        [0, 1, 2, 3],
        [4, 5, 6, 7],
        [0, 1, 5, 4],
        [1, 2, 6, 5],
        [2, 3, 7, 6],
        [3, 0, 4, 7],
      ];
      for (final (i, f) in flaechen.indexed) {
        final pr = [for (final n in f) p(e[n])];
        final tiefe = pr.map((x) => x.$2).reduce((a, b) => a + b) / 4;
        teile.add((
          tiefe,
          () {
            final pfad = Path()..addPolygon([for (final x in pr) x.$1], true);
            final hell = i == 1 ? 0.95 : (i.isEven ? 0.75 : 0.85);
            canvas.drawPath(pfad, Paint()..color = Color.lerp(farbe, Colors.white, 1 - hell)!.withValues(alpha: w.auswahl == g.id ? 0.95 : 0.8));
            canvas.drawPath(pfad, Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w.auswahl == g.id ? 2 : 0.8
              ..color = Colors.black54);
          }
        ));
      }
      final (oben, t) = p(V3(g.x, g.y, g.z + g.h + 80));
      teile.add((t - 1, () => _text(canvas, g.name, oben)));
    }
    // Leitungen (Segmente einzeln einsortieren)
    for (final l in w.leitungen) {
      final farbe = kollision.contains(l.id) ? const Color(0xFFE03131) : (w.farben[l.id] ?? const Color(0xFF1C7ED6));
      for (var i = 0; i + 1 < l.punkte.length; i++) {
        final (a, ta) = p(l.punkte[i]);
        final (b, tb) = p(l.punkte[i + 1]);
        final tiefe = (ta + tb) / 2;
        final breite = math.max(2.0, l.durchmesser * k.brennweite / math.max(100, tiefe) * m);
        teile.add((
          tiefe - 1,
          () => canvas.drawLine(a, b, Paint()
            ..color = farbe
            ..strokeWidth = breite
            ..strokeCap = StrokeCap.round),
        ));
      }
      if (l.punkte.isNotEmpty) {
        final (a, ta) = p(l.punkte.first);
        teile.add((ta - 2, () => _text(canvas, l.name, a + const Offset(4, -14), farbe: farbe)));
      }
    }
    teile.sort((a, b) => b.$1.compareTo(a.$1));
    for (final t in teile) {
      t.$2();
    }
  }

  void _text(Canvas c, String t, Offset o, {Color farbe = Colors.black87}) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: 11, color: farbe, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, o - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _Raum3dPainter old) => true;
}
