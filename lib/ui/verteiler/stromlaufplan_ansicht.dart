import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/theme.dart';
import '../../core/stromlaufplan.dart';

/// Bildschirmansicht eines Stromlaufplans: Blattwahl und Zoom.
class StromlaufplanAnsicht extends StatefulWidget {
  const StromlaufplanAnsicht({super.key, required this.plan});
  final Stromlaufplan plan;

  @override
  State<StromlaufplanAnsicht> createState() => _StromlaufplanAnsichtState();
}

class _StromlaufplanAnsichtState extends State<StromlaufplanAnsicht> {
  int _blatt = 0;

  @override
  Widget build(BuildContext context) {
    final blaetter = widget.plan.blaetter;
    final b = blaetter[_blatt.clamp(0, blaetter.length - 1)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Material(
        color: Colors.white,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            for (final x in blaetter)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('Blatt ${x.nr}: ${x.titel}', style: const TextStyle(fontSize: 12)),
                  selected: x.nr == b.nr,
                  onSelected: (_) => setState(() => _blatt = x.nr - 1),
                ),
              ),
            if (widget.plan.hinweise.isNotEmpty)
              Tooltip(
                message: widget.plan.hinweise.join('\n'),
                child: Chip(
                  avatar: const Icon(Icons.info_outline, size: 16, color: Color(0xFFE67700)),
                  label: Text('${widget.plan.hinweise.length} Hinweise'),
                ),
              ),
          ]),
        ),
      ),
      Expanded(
        child: Container(
          color: BsFarben.zeichenflaeche,
          child: LayoutBuilder(builder: (context, c) {
            final massstab = ((c.maxWidth - 40) / blattBreite).clamp(0.5, 20.0);
            return InteractiveViewer(
              constrained: false,
              minScale: 0.3,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(400),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 6)]),
                  child: CustomPaint(
                    size: Size(blattBreite * massstab, blattHoehe * massstab),
                    painter: SlpPainter(b, massstab),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    ]);
  }
}

/// Zeichnet ein Blatt (mm) mit [massstab] Pixel je mm.
class SlpPainter extends CustomPainter {
  SlpPainter(this.blatt, this.massstab, {this.schrift});
  final SlpBlatt blatt;
  final double massstab;

  /// Schriftart (für Bilder aus Tests), sonst die des Programms.
  final String? schrift;

  @override
  void paint(Canvas canvas, Size size) {
    final m = massstab;
    Paint stift(double dicke) => Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = (dicke * m).clamp(0.6, 10);
    void gestrichelt(Offset a, Offset b, Paint p, List<double> muster) {
      final d = b - a;
      final laenge = d.distance;
      if (laenge == 0) return;
      final r = d / laenge;
      var pos = 0.0, i = 0;
      while (pos < laenge) {
        final l = muster[i % muster.length] * m;
        if (i.isEven) canvas.drawLine(a + r * pos, a + r * (pos + l).clamp(0, laenge), p);
        pos += l;
        i++;
      }
    }

    for (final z in blatt.zeichen) {
      switch (z) {
        case ZLinie():
          final a = Offset(z.x1 * m, z.y1 * m), b = Offset(z.x2 * m, z.y2 * m);
          if (z.strich) {
            gestrichelt(a, b, stift(z.dicke), const [1.5, 1.0]);
          } else if (z.strichpunkt) {
            gestrichelt(a, b, stift(z.dicke), const [6, 1, 0.6, 1]);
          } else {
            canvas.drawLine(a, b, stift(z.dicke));
          }
        case ZKreis():
          canvas.drawCircle(Offset(z.x * m, z.y * m), z.r * m, z.gefuellt ? (Paint()..color = Colors.black) : stift(z.dicke));
        case ZEllipse():
          canvas.drawOval(Rect.fromCenter(center: Offset(z.x * m, z.y * m), width: z.rx * 2 * m, height: z.ry * 2 * m), stift(z.dicke));
        case ZRechteck():
          final r = Rect.fromLTWH(z.x * m, z.y * m, z.b * m, z.h * m);
          if (z.strich) {
            final p = stift(z.dicke);
            for (final (a, b) in [(r.topLeft, r.topRight), (r.topRight, r.bottomRight), (r.bottomRight, r.bottomLeft), (r.bottomLeft, r.topLeft)]) {
              gestrichelt(a, b, p, const [1.5, 1.0]);
            }
          } else {
            canvas.drawRect(r, stift(z.dicke));
          }
        case ZPolylinie():
          final pfad = Path()..moveTo(z.punkte.first.$1 * m, z.punkte.first.$2 * m);
          for (final p in z.punkte.skip(1)) {
            pfad.lineTo(p.$1 * m, p.$2 * m);
          }
          canvas.drawPath(pfad, stift(z.dicke));
        case ZText():
          final tp = TextPainter(
            text: TextSpan(
              text: z.text,
              style: TextStyle(fontFamily: schrift, color: Colors.black, fontSize: z.groesse * m * 1.3, fontWeight: z.fett ? FontWeight.w700 : FontWeight.w400, height: 1),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final dx = switch (z.ausrichtung) {
            Ausrichtung.links => 0.0,
            Ausrichtung.mitte => -tp.width / 2,
            Ausrichtung.rechts => -tp.width,
          };
          final grundlinie = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
          tp.paint(canvas, Offset(z.x * m + dx, z.y * m - grundlinie));
      }
    }
  }

  @override
  bool shouldRepaint(SlpPainter alt) => alt.blatt != blatt || alt.massstab != massstab;
}

/// Text auf den Zeichensatz der PDF-Standardschrift beschränken.
String _pdfText(String s) => String.fromCharCodes(s
    .replaceAll('–', '-')
    .replaceAll('—', '-')
    .replaceAll('→', '->')
    .replaceAll('„', '"')
    .replaceAll('“', '"')
    .runes
    .map((c) => c < 256 ? c : 0x3F));

/// Stromlaufplan als PDF (A3 quer, ein Blatt je Seite, Maßstab 1:1).
Future<Uint8List> stromlaufplanPdf(Stromlaufplan plan, {String titel = 'Stromlaufplan'}) async {
  final doc = pw.Document(title: titel);
  final normal = PdfFont.helvetica(doc.document), fett = PdfFont.helveticaBold(doc.document);
  const mm = PdfPageFormat.mm;
  for (final b in plan.blaetter) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a3.landscape.copyWith(marginLeft: 0, marginTop: 0, marginRight: 0, marginBottom: 0),
      build: (c) => pw.CustomPaint(
        size: const PdfPoint(blattBreite * mm, blattHoehe * mm),
        painter: (g, size) {
          double y(double v) => size.y - v * mm;
          g.setStrokeColor(PdfColors.black);
          g.setFillColor(PdfColors.black);
          g.setLineCap(PdfLineCap.round);
          void strich(double dicke, {List<double>? muster}) {
            g.setLineWidth(dicke * mm);
            g.setLineDashPattern(muster == null ? const [] : [for (final x in muster) x * mm]);
          }

          for (final z in b.zeichen) {
            switch (z) {
              case ZLinie():
                strich(z.dicke, muster: z.strich ? const [1.5, 1.0] : (z.strichpunkt ? const [6, 1, 0.6, 1] : null));
                g
                  ..moveTo(z.x1 * mm, y(z.y1))
                  ..lineTo(z.x2 * mm, y(z.y2))
                  ..strokePath();
              case ZKreis():
                strich(z.dicke);
                g.drawEllipse(z.x * mm, y(z.y), z.r * mm, z.r * mm);
                z.gefuellt ? g.fillPath() : g.strokePath();
              case ZEllipse():
                strich(z.dicke);
                g
                  ..drawEllipse(z.x * mm, y(z.y), z.rx * mm, z.ry * mm)
                  ..strokePath();
              case ZRechteck():
                strich(z.dicke, muster: z.strich ? const [1.5, 1.0] : null);
                g
                  ..drawRect(z.x * mm, y(z.y + z.h), z.b * mm, z.h * mm)
                  ..strokePath();
              case ZPolylinie():
                strich(z.dicke);
                g.moveTo(z.punkte.first.$1 * mm, y(z.punkte.first.$2));
                for (final p in z.punkte.skip(1)) {
                  g.lineTo(p.$1 * mm, y(p.$2));
                }
                g.strokePath();
              case ZText():
                final f = z.fett ? fett : normal;
                final t = _pdfText(z.text);
                final pt = z.groesse * mm * 1.3;
                final breite = f.stringMetrics(t).width * pt;
                final dx = switch (z.ausrichtung) {
                  Ausrichtung.links => 0.0,
                  Ausrichtung.mitte => -breite / 2,
                  Ausrichtung.rechts => -breite,
                };
                g.drawString(f, pt, t, z.x * mm + dx, y(z.y));
            }
          }
          g.setLineDashPattern(const []);
        },
      ),
    ));
  }
  return doc.save();
}
