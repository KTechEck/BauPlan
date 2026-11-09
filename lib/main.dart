import 'dart:io';

import 'app/version.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'mobil/mobil_app.dart';
import 'mobil/ordner.dart';
import 'data/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iPhone/iPad: nur das Baustellen-Werkzeug (Erfassen + Nachschlagen), nicht das ganze Programm
  if (Platform.isIOS || Platform.isAndroid) {
    runApp(MobilApp(ordner: KanalOrdner(), einstellungen: await MobilEinstellungen.laden(), puffer: await Puffer.laden()));
    return;
  }
  final settings = await AppSettings.laden();
  // Fenstersteuerung nur auf dem PC (iPhone/iPad haben keine Fenster)
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: 'BauSpur – $bauspurBuild', minimumSize: Size(1000, 640)),
      () => fensterEinrichten(settings),
    );
  }
  runApp(BauSpurApp(settings: settings));
}

/// Fenster beim Start: unsichtbar in die richtige Lage bringen, dann zeigen.
/// So springt es nicht zwischen klein und maximiert hin und her.
Future<void> fensterEinrichten(AppSettings settings) async {
  final lage = settings.fensterLage;
  final gueltig = lage != null && lage.length == 4 && lage[2] >= 600 && lage[3] >= 400 && lage[0] > -200 && lage[1] > -50;
  final zuletzt = settings.fensterStart == 'zuletzt' && gueltig;
  final maximiert = !zuletzt || settings.fensterMaximiert;
  await windowManager.setOpacity(0);
  if (zuletzt) await windowManager.setBounds(Rect.fromLTWH(lage[0], lage[1], lage[2], lage[3]));
  await windowManager.show();
  if (maximiert) {
    await windowManager.maximize();
    // Windows meldet das Maximieren teils erst nach dem nächsten Nachrichtenumlauf.
    for (var i = 0; i < 10 && !await windowManager.isMaximized(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await windowManager.maximize();
    }
  }
  await windowManager.setOpacity(1);
  await windowManager.focus();
}

/// Merkt sich Größe und Lage des Fensters (für „wie zuletzt geschlossen“).
/// Bei maximiertem Fenster bleibt die zuletzt normale Lage gespeichert.
Future<void> fensterMerken(AppSettings s) async {
  try {
    s.fensterMaximiert = await windowManager.isMaximized();
    final b = await windowManager.getBounds();
    if (!s.fensterMaximiert && !await windowManager.isMinimized()) s.fensterLage = [b.left, b.top, b.width, b.height];
    s.speichern();
  } catch (_) {
    // ohne Fenstersteuerung (z. B. in Tests) nichts zu tun
  }
}
