import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/app_settings.dart';
import '../data/austausch.dart';
import '../data/bauelement_bibliothek.dart';
import '../data/project_store.dart';

enum Modul {
  projekt('Projekt'),
  grundriss('Grundriss'),
  installation('Installation'),
  haustechnik('Haustechnik'),
  verteiler('Verteiler'),
  bauteile('Bibliothek'),
  bauphysik('Bauphysik'),
  assistent('KI-Assistent'),
  fotos('Fotos'),
  kosten('Kosten'),
  tagebuch('Tagebuch'),
  export('Export'),
  einstellungen('Einstellungen');

  const Modul(this.label);
  final String label;
}

/// Zentraler Zustand der Anwendung: offenes Projekt, gewähltes Modul,
/// gewähltes Geschoss. Widgets hören über ListenableBuilder darauf.
class AppState extends ChangeNotifier {
  AppState(this.settings);

  final AppSettings settings;

  /// Bauelemente-Bibliothek dieses PCs (Fenster, Türen, Geräte …).
  late final BauelementBibliothek bibliothek = BauelementBibliothek(Directory(p.join(settings.ordner.path, 'bauelemente')));
  ProjectStore? store;
  Modul modul = Modul.grundriss;
  String? geschossId;
  String? raumId;

  /// Bereich, den die Einstellungen beim nächsten Öffnen zeigen sollen (z. B. „ki“).
  String? einstellungenZiel;

  /// Objekt, das die Installation anwählen soll (z. B. aus dem Projektbaum).
  String? objektAuswahl;

  /// Objekte, die eine andere Ansicht hervorheben lässt (z. B. Verbraucher eines Stromkreises).
  Set<String> markiert = {};

  /// Erhöht sich bei jeder Datenänderung, damit Ansichten neu laden.
  int revision = 0;

  Timer? _planstandTimer, _eingangTimer;

  /// Letzte Meldung aus dem App-Eingang (für die Glocke/Statuszeile).
  String? eingangMeldung;

  /// Planstand für die App ablegen (verzögert, damit viele kleine Änderungen nur einmal schreiben).
  /// In Widget-Tests keine Hintergrund-Timer (der Austausch hat eigene Tests).
  static final bool _imTest = Platform.environment.containsKey('FLUTTER_TEST');

  void _planstandVormerken() {
    if (_imTest) return;
    _planstandTimer?.cancel();
    _planstandTimer = Timer(const Duration(seconds: 3), () {
      final st = store;
      if (st == null) return;
      try {
        planstandSchreiben(st);
      } catch (_) {}
    });
  }

  /// Neue Erfassungen der App übernehmen (beim Öffnen und alle 30 s).
  void eingangPruefen() {
    final st = store;
    if (st == null) return;
    try {
      final r = eingangUebernehmen(st);
      if (r.uebernommen > 0 || r.fehler > 0) {
        eingangMeldung = '${r.uebernommen} Erfassung(en) aus der App übernommen${r.fehler > 0 ? ', ${r.fehler} fehlerhaft' : ''}';
        geaendert();
      }
    } catch (_) {}
  }

  void projektOeffnen(ProjectStore s) {
    store?.schliessen();
    store = s;
    _eingangTimer?.cancel();
    if (!_imTest) {
      _eingangTimer = Timer.periodic(const Duration(seconds: 30), (_) => eingangPruefen());
      Timer.run(() {
        eingangPruefen();
        _planstandVormerken();
      });
    }
    settings.merkeProjekt(s.ordner);
    final geb = s.gebaeude();
    geschossId = geb.isEmpty ? null : s.geschosse(geb.first.id).firstOrNull?.id;
    raumId = null;
    modul = Modul.grundriss;
    notifyListeners();
  }

  void projektSchliessen() {
    _eingangTimer?.cancel();
    _planstandTimer?.cancel();
    final st = store;
    if (st != null) {
      try {
        planstandSchreiben(st);
      } catch (_) {}
    }
    store?.schliessen();
    store = null;
    geschossId = null;
    raumId = null;
    notifyListeners();
  }

  void modulWaehlen(Modul m) {
    modul = m;
    notifyListeners();
  }

  void geschossWaehlen(String id) {
    geschossId = id;
    raumId = null;
    notifyListeners();
  }

  void raumWaehlen(String? id) {
    raumId = id;
    notifyListeners();
  }

  /// Nach jeder Änderung an Projektdaten aufrufen.
  void geaendert() {
    revision++;
    _planstandVormerken();
    notifyListeners();
  }
}
