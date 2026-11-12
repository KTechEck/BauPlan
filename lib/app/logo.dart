import 'dart:ui';

/// BauSpur-Logo „Bauplan-Linie“: eine orange Linie (die Spur) zeichnet auf
/// dunklem Planraster ein Haus. Entworfen auf 120 × 120 Einheiten.
/// [rund]: abgerundete Kachel mit durchsichtigen Ecken (Windows), sonst
/// vollflächig (iPhone schneidet die Ecken selbst).
void logoZeichnen(Canvas c, double groesse, {bool rund = true}) {
  c.save();
  c.scale(groesse / 120);
  const flaeche = Rect.fromLTWH(0, 0, 120, 120);
  if (rund) c.clipRRect(RRect.fromRectAndRadius(flaeche, const Radius.circular(26)));
  c.drawRect(flaeche, Paint()..color = const Color(0xFF0F2A43));
  // Raster nur, wo es noch als Raster erkennbar ist
  if (groesse >= 48) {
    final raster = Paint()
      ..color = const Color(0x17FFFFFF)
      ..strokeWidth = 1.5;
    for (var i = 20.0; i < 120; i += 20) {
      c.drawLine(Offset(i, 0), Offset(i, 120), raster);
      c.drawLine(Offset(0, i), Offset(120, i), raster);
    }
  }
  final klein = groesse < 40;
  final spur = Path()
    ..moveTo(22, 94)
    ..lineTo(42, 94)
    ..lineTo(42, 60)
    ..lineTo(68, 36)
    ..lineTo(94, 60)
    ..lineTo(94, 94)
    ..lineTo(62, 94)
    ..lineTo(62, 74);
  c.drawPath(
    spur,
    Paint()
      ..color = const Color(0xFFF97316)
      ..style = PaintingStyle.stroke
      ..strokeWidth = klein ? 11 : 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
  final weiss = Paint()..color = const Color(0xFFFFFFFF);
  c.drawCircle(const Offset(22, 94), klein ? 7 : 6, weiss);
  c.drawCircle(const Offset(62, 74), klein ? 8 : 7, weiss);
  if (!klein) c.drawCircle(const Offset(62, 74), 3, Paint()..color = const Color(0xFFF97316));
  c.restore();
}
