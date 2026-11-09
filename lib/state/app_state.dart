import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/app_settings.dart';
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

  void projektOeffnen(ProjectStore s) {
    store?.schliessen();
    store = s;
    settings.merkeProjekt(s.ordner);
    final geb = s.gebaeude();
    geschossId = geb.isEmpty ? null : s.geschosse(geb.first.id).firstOrNull?.id;
    raumId = null;
    modul = Modul.grundriss;
    notifyListeners();
  }

  void projektSchliessen() {
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
    notifyListeners();
  }
}
