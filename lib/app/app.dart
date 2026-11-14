import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../main.dart' show fensterMerken;
import '../state/app_state.dart';
import '../ui/shell.dart';
import '../ui/start_page.dart';
import 'theme.dart';

class BauSpurApp extends StatefulWidget {
  const BauSpurApp({super.key, this.settings, this.touch = false});
  final AppSettings? settings;

  /// Tablet mit Finger/Stift: größere Bedienelemente, kein PC-Dienst.
  final bool touch;

  @override
  State<BauSpurApp> createState() => _BauSpurAppState();
}

class _BauSpurAppState extends State<BauSpurApp> {
  AppState? _state;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final vorab = widget.settings;
    if (vorab != null) {
      _state = AppState(vorab, touch: widget.touch);
    } else {
      AppSettings.laden().then((s) => setState(() => _state = AppState(s, touch: widget.touch)));
    }
    // Beim Beenden die Projektsperre freigeben.
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      _state?.store?.schliessen();
      final s = _state?.settings;
      if (s != null) await fensterMerken(s);
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return MaterialApp(
      title: 'BauSpur',
      debugShowCheckedModeBanner: false,
      theme: bauSpurTheme(touch: widget.touch),
      home: state == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : ListenableBuilder(
              listenable: state,
              builder: (context, _) =>
                  state.store == null ? StartPage(state: state) : Shell(state: state),
            ),
    );
  }
}
