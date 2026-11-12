// Erzeugt das BauSpur-Logo (Entwurf H „Bauplan-Linie“) als PNG in allen
// Größen. Läuft nur mit gesetzter Umgebungsvariable BAUSPUR_LOGO (Zielordner).
// Danach tools/logo_einbauen.py ausführen (baut .ico und verteilt die iOS-Symbole).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/app/logo.dart';
import 'package:flutter_test/flutter_test.dart';

final _ziel = Platform.environment['BAUSPUR_LOGO'];

void main() {
  testWidgets('Logo-Dateien', (tester) async {
    if (_ziel == null) return;
    await tester.runAsync(() async {
      Future<void> bild(String name, int px, {required bool rund}) async {
        final r = ui.PictureRecorder();
        logoZeichnen(ui.Canvas(r), px.toDouble(), rund: rund);
        final img = await r.endRecording().toImage(px, px);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_ziel/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      }

      for (final px in [16, 20, 24, 32, 40, 48, 64, 128, 256, 512]) {
        await bild('rund_$px', px, rund: true);
      }
      for (final px in [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]) {
        await bild('voll_$px', px, rund: false);
      }
    });
  });
}
