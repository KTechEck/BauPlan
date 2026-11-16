import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/wandaufbau.dart';

/// Kompaktes Menü am Wandknoten: Anschlussarten als Bildchen. Liefert die
/// gewählte Einstellung oder null (abgebrochen). „Andere Wand läuft durch“ ist
/// [AnschlussArt.stumpf] für diese Wand.
Future<Anschluss?> anschlussMenue(BuildContext context, Offset global, Anschluss aktuell) async {
  var tiefe = aktuell.tiefe > 0 ? aktuell.tiefe : 60;
  return showMenu<Anschluss>(
    context: context,
    position: RelativeRect.fromLTRB(global.dx + 8, global.dy + 8, global.dx + 9, global.dy + 9),
    constraints: const BoxConstraints(maxWidth: 330),
    items: [
      PopupMenuItem<Anschluss>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: StatefulBuilder(
          builder: (c, setM) => Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('Wandanschluss', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF212529))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (art, text) in const [
                  (AnschlussArt.auto, 'Automatisch'),
                  (AnschlussArt.gehrung, 'Gehrung'),
                  (AnschlussArt.durch, 'Diese durch'),
                  (AnschlussArt.stumpf, 'Andere durch'),
                  (AnschlussArt.eingebunden, 'Eingebunden'),
                ])
                  Tooltip(
                    message: switch (art) {
                      AnschlussArt.auto => 'Nach Baustoff: Leichtbau stößt stumpf an Massivwand, sonst Gehrung',
                      AnschlussArt.gehrung => 'Beide Wände treffen sich auf Gehrung',
                      AnschlussArt.durch => 'Diese Wand läuft durch, die andere stößt an',
                      AnschlussArt.stumpf => 'Die andere Wand läuft durch, diese stößt stumpf an',
                      AnschlussArt.eingebunden => 'Diese Wand stößt an und greift in die andere ein',
                    },
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.pop(c, (art: art, tiefe: art == AnschlussArt.eingebunden ? tiefe : 0, schichtenDurch: aktuell.schichtenDurch)),
                      child: Container(
                        width: 92,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: aktuell.art == art ? BsFarben.akzent : BsFarben.rand, width: aktuell.art == art ? 2 : 1),
                          color: aktuell.art == art ? BsFarben.akzentHell.withValues(alpha: 0.5) : Colors.white,
                        ),
                        child: Column(children: [
                          SizedBox(width: 60, height: 46, child: CustomPaint(painter: _AnschlussBild(art))),
                          const SizedBox(height: 4),
                          Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF343A40))),
                        ]),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Einbindetiefe', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 300,
                    divisions: 30,
                    value: tiefe.toDouble().clamp(0, 300),
                    label: '$tiefe mm',
                    onChanged: (v) => setM(() => tiefe = v.round()),
                  ),
                ),
                Text('$tiefe mm', style: const TextStyle(fontSize: 12)),
              ]),
            ]),
          ),
        ),
      ),
    ],
  );
}

/// Bildchen: diese Wand waagrecht (orange), die andere senkrecht (grau).
class _AnschlussBild extends CustomPainter {
  _AnschlussBild(this.art);
  final AnschlussArt art;

  @override
  void paint(Canvas canvas, Size size) {
    const d = 12.0;
    final w = size.width, h = size.height;
    final diese = Paint()..color = BsFarben.akzent;
    final andere = Paint()..color = const Color(0xFF868E96);
    final linie = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2;
    // andere Wand: rechts, von oben nach unten; diese: oben, von links nach rechts
    final x0 = w - d - 4, y0 = 4.0;
    switch (art) {
      case AnschlussArt.gehrung || AnschlussArt.auto:
        canvas.drawPath(Path()..addPolygon([Offset(0, y0), Offset(x0 + d, y0), Offset(x0, y0 + d), Offset(0, y0 + d)], true), diese);
        canvas.drawPath(Path()..addPolygon([Offset(x0 + d, y0), Offset(x0 + d, h), Offset(x0, h), Offset(x0, y0 + d)], true), andere);
        canvas.drawLine(Offset(x0 + d, y0), Offset(x0, y0 + d), linie);
        if (art == AnschlussArt.auto) {
          final tp = TextPainter(text: const TextSpan(text: 'A', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF212529))), textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(8, y0 + d + 6));
        }
      case AnschlussArt.durch:
        canvas.drawRect(Rect.fromLTWH(0, y0, x0 + d, d), diese);
        canvas.drawRect(Rect.fromLTWH(x0, y0 + d, d, h - y0 - d), andere);
        canvas.drawLine(Offset(x0, y0 + d), Offset(x0 + d, y0 + d), linie);
      case AnschlussArt.stumpf:
        canvas.drawRect(Rect.fromLTWH(x0, y0, d, h - y0), andere);
        canvas.drawRect(Rect.fromLTWH(0, y0, x0, d), diese);
        canvas.drawLine(Offset(x0, y0), Offset(x0, y0 + d), linie);
      case AnschlussArt.eingebunden:
        canvas.drawRect(Rect.fromLTWH(x0, y0, d, h - y0), andere);
        canvas.drawRect(Rect.fromLTWH(0, y0, x0 + d / 2, d), diese);
        canvas.drawLine(Offset(x0 + d / 2, y0), Offset(x0 + d / 2, y0 + d), linie);
    }
  }

  @override
  bool shouldRepaint(covariant _AnschlussBild old) => old.art != art;
}
