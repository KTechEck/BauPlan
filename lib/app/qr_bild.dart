import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Inhalt des Kopplungs-QR-Codes: Adressen des PCs, Code und Name.
/// Die App liest ihn mit der Kamera und verbindet sich ohne Tippen.
String kopplungsText({required List<String> adressen, required String code, String name = ''}) =>
    Uri(scheme: 'bauspur', host: 'koppeln', queryParameters: {'a': adressen.join(','), 'c': code, if (name.isNotEmpty) 'n': name}).toString();

/// Liest einen Kopplungs-QR-Code; null, wenn es keiner ist.
({List<String> adressen, String code, String name})? kopplungLesen(String text) {
  final u = Uri.tryParse(text.trim());
  if (u == null || u.scheme != 'bauspur' || u.host != 'koppeln') return null;
  final a = (u.queryParameters['a'] ?? '').split(',').where((x) => x.trim().isNotEmpty).toList();
  final c = u.queryParameters['c'] ?? '';
  if (a.isEmpty || c.isEmpty) return null;
  return (adressen: a, code: c, name: u.queryParameters['n'] ?? '');
}

/// QR-Code als Bild (ohne weiteres Paket gezeichnet).
class QrBild extends StatelessWidget {
  const QrBild(this.daten, {super.key, this.groesse = 180});
  final String daten;
  final double groesse;

  @override
  Widget build(BuildContext context) {
    final qr = QrImage(QrCode.fromData(data: daten, errorCorrectLevel: QrErrorCorrectLevel.M));
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: CustomPaint(size: Size.square(groesse), painter: _QrPainter(qr)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.qr);
  final QrImage qr;

  @override
  void paint(Canvas canvas, Size size) {
    final n = qr.moduleCount;
    final m = size.width / n;
    final p = Paint()..color = Colors.black;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (qr.isDark(y, x)) canvas.drawRect(Rect.fromLTWH(x * m, y * m, m + 0.3, m + 0.3), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.qr != qr;
}
