import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Installationssymbole für Grundriss und Pläne, angelehnt an DIN EN 60617-11.
/// [c] ist die Mitte, [r] der Radius in Pixeln, [richtung] zeigt von der Wand
/// in den Raum (Steckdosen und Schalter zeigen mit ihrem Anschluss zur Wand).
void geraetSymbol(Canvas canvas, Offset c, double r, String kuerzel, Color farbe, {Offset richtung = const Offset(0, -1), double deckkraft = 1, bool quadrat = false}) {
  final stift = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.4, r / 4.5)
    ..color = farbe.withValues(alpha: math.max(0.35, deckkraft))
    ..strokeCap = StrokeCap.round;
  final fuellung = Paint()..color = Colors.white.withValues(alpha: deckkraft);
  final voll = Paint()..color = farbe.withValues(alpha: math.max(0.35, deckkraft));
  final l = richtung.distance == 0 ? const Offset(0, -1) : richtung / richtung.distance;
  final q = Offset(-l.dy, l.dx); // quer zur Richtung
  final wand = c - l * r; // Punkt zur Wand hin

  void kreis([double f = 1]) {
    canvas.drawCircle(c, r * f, fuellung);
    canvas.drawCircle(c, r * f, stift);
  }

  void rechteck(double b, double h) {
    final p = Path()
      ..moveTo((c + q * b - l * h).dx, (c + q * b - l * h).dy)
      ..lineTo((c - q * b - l * h).dx, (c - q * b - l * h).dy)
      ..lineTo((c - q * b + l * h).dx, (c - q * b + l * h).dy)
      ..lineTo((c + q * b + l * h).dx, (c + q * b + l * h).dy)
      ..close();
    canvas.drawPath(p, fuellung);
    canvas.drawPath(p, stift);
  }

  void text(String t, {double f = 0.9}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: r * f, color: farbe, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  /// Halbkreis, der zur Wand hin offen ist (Steckdose).
  void steckdose({int fach = 1, bool schutz = true}) {
    final rect = Rect.fromCircle(center: c, radius: r);
    final winkel = math.atan2(l.dy, l.dx);
    canvas.drawArc(rect, winkel - math.pi / 2, math.pi, true, fuellung);
    canvas.drawArc(rect, winkel - math.pi / 2, math.pi, false, stift);
    canvas.drawLine(c + q * r, c - q * r, stift);
    canvas.drawLine(c, wand, stift); // Anschluss zur Wand
    if (schutz) canvas.drawLine(c + l * r * 0.2 + q * r * 0.6, c + l * r * 0.2 - q * r * 0.6, stift); // Schutzkontakt
    for (var i = 1; i < fach; i++) {
      canvas.drawArc(Rect.fromCircle(center: c + l * (r * 0.35 * i), radius: r), winkel - math.pi / 2, math.pi, false, stift);
    }
  }

  switch (kuerzel) {
    case 'SD':
      steckdose();
    case 'HD': // Herdanschluss
      steckdose();
      canvas.drawLine(c + l * r * 0.55 - q * r * 0.3, c + l * r * 0.55 + q * r * 0.3, stift);
    case 'SC': // Schalter: Kreis mit Hebel
    case 'TA': // Taster
      kreis(0.55);
      canvas.drawLine(c, c + (l + q) * (r * 1.1), stift);
      canvas.drawLine(c + (l + q) * (r * 1.1), c + (l + q) * (r * 1.1) + q * (r * 0.45), stift);
      if (kuerzel == 'TA') canvas.drawCircle(c, r * 0.22, voll);
      canvas.drawLine(c, wand, stift);
    case 'DS': // Dimmer
      kreis(0.55);
      canvas.drawLine(c, c + (l + q) * (r * 1.1), stift);
      text('↕', f: 0.7);
    case 'LE': // Leuchte: Kreis mit Kreuz
    case 'LB':
      kreis();
      final d = r * 0.7071;
      canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), stift);
      canvas.drawLine(c + Offset(-d, d), c + Offset(d, -d), stift);
    case 'PM': // Präsenzmelder: Kreis mit Erfassungsbögen
    case 'BM':
      kreis(0.6);
      for (final f in [0.85, 1.1]) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: r * f), -math.pi * 0.8, math.pi * 0.6, false, stift);
      }
      text(kuerzel == 'PM' ? 'P' : 'B', f: 0.7);
    case 'RM': // Rauchmelder
      rechteck(r, r);
      text('S', f: 1);
    case 'ND': // Netzwerkdose
      rechteck(r, r * 0.8);
      text('TP', f: 0.75);
      canvas.drawLine(c - l * r * 0.8, wand - l * r * 0.2, stift);
    case 'AP': // Antenne / Sat
      rechteck(r, r * 0.8);
      text('TV', f: 0.75);
    case 'RT': // Raumthermostat
      rechteck(r, r);
      text('ϑ', f: 1.1);
    case 'HK': // Heizkörper
      rechteck(r * 1.6, r * 0.6);
      for (var i = -2; i <= 2; i++) {
        canvas.drawLine(c + q * (r * 0.5 * i) - l * r * 0.5, c + q * (r * 0.5 * i) + l * r * 0.5, stift);
      }
    case 'HV': // Heizkreisverteiler (Schrank wird separat gezeichnet)
      rechteck(r, r * 0.7);
      text('HV', f: 0.7);
    case 'WT': // Waschtisch
      rechteck(r * 1.3, r * 0.9);
      canvas.drawOval(Rect.fromCenter(center: c + l * r * 0.1, width: r * 1.6, height: r * 1.0), stift);
    case 'WC':
      rechteck(r * 0.9, r * 0.4);
      canvas.drawOval(Rect.fromCenter(center: c + l * r * 0.9, width: r * 1.3, height: r * 1.6), fuellung);
      canvas.drawOval(Rect.fromCenter(center: c + l * r * 0.9, width: r * 1.3, height: r * 1.6), stift);
    case 'DU': // Dusche / Bodenablauf
      rechteck(r, r);
      canvas.drawCircle(c, r * 0.3, stift);
    case 'WD': // Wanddurchbruch (eigene Darstellung im Plan)
      kreis(0.6);
    case 'VB': // Verbindungselement: kleine Raute
    case 'VH':
      final p = Path()
        ..moveTo(c.dx, c.dy - r * 0.7)
        ..lineTo(c.dx + r * 0.7, c.dy)
        ..lineTo(c.dx, c.dy + r * 0.7)
        ..lineTo(c.dx - r * 0.7, c.dy)
        ..close();
      canvas.drawPath(p, voll);
    case 'AV': // Absperrarmatur: zwei Dreiecke (Schleife)
      final p = Path()
        ..moveTo((c - q * r).dx, (c - q * r - l * r * 0.6).dy)
        ..lineTo((c + q * r).dx, (c + q * r + l * r * 0.6).dy)
        ..lineTo((c + q * r).dx, (c + q * r - l * r * 0.6).dy)
        ..lineTo((c - q * r).dx, (c - q * r + l * r * 0.6).dy)
        ..close();
      canvas.drawPath(p, fuellung);
      canvas.drawPath(p, stift);
    case 'ES': // Elektronischer Sensor / Fühler
      kreis(0.7);
      text('ϑ', f: 0.9);
    default:
      if (quadrat) {
        rechteck(r, r);
      } else {
        kreis();
      }
      text(kuerzel, f: 0.75);
  }
}
