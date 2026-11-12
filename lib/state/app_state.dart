import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app/version.dart';
import '../core/speicher.dart';
import '../data/app_settings.dart';
import '../data/austausch.dart';
import '../data/bauelement_bibliothek.dart';
import '../data/project_store.dart';
import '../ui/bauteile/einkauf_dialog.dart' show besorgungFuerApp;

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
  AppState(this.settings) {
    if (!_imTest) Timer.run(speicherAnwenden);
    // Planstand für die App: Besorgungsliste und Geräte aus der Bibliothek mitgeben
    zusatzEinkauf = (_) => besorgungFuerApp(this);
    bauelementLesen = (st, id) => bibliothek.fuerProjekt(st, id)?.toJson();
  }

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
        _planNeu = true;
        if (speicher.art == 'cloud') abgleichen();
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------- Speicher und Abgleich

  SpeicherEinstellung get speicher => SpeicherEinstellung(settings.speicher);

  /// Dienst für die App im Heimnetz (Planstand geben, Erfassungen annehmen).
  late final PcDienst dienst = PcDienst(
    ordner: () => store == null ? null : austauschOrdner(store!),
    code: () => speicher.code,
    auskunft: () => {'name': Platform.localHostname, 'projekt': store == null ? '' : p.basename(store!.ordner), 'build': bauspurBuild},
    beiEingang: () => Timer(const Duration(seconds: 1), eingangPruefen),
  );

  /// Störung beim Abgleich (Netzwerkordner oder Cloud nicht erreichbar), sonst null.
  String? speicherMeldung;
  DateTime? letzterAbgleich;
  bool _planNeu = true, _abgleichLaeuft = false;

  /// Speichereinstellung anwenden: Kopplungscode anlegen, Dienst starten/stoppen, Netzwerkordner prüfen.
  Future<void> speicherAnwenden() async {
    if (speicher.code.isEmpty) {
      settings.speicher = {...settings.speicher, 'code': neuerCode()};
      settings.speichern();
    }
    final s = speicher;
    if (!s.dienst) {
      await dienst.stoppen();
    } else if (!dienst.laeuft || dienst.port != s.port) {
      await dienst.starten(port: s.port);
    }
    _planNeu = true;
    await abgleichen();
    notifyListeners();
  }

  Future<void> _netzPruefen() async {
    final s = speicher;
    if (s.art != 'netz' || s.netzPfad.isEmpty) {
      netzAustauschBasis = null;
      if (s.art != 'cloud') speicherMeldung = null;
      return;
    }
    var ok = false;
    try {
      ok = await Directory(s.netzPfad).exists().timeout(const Duration(seconds: 4));
    } catch (_) {}
    netzAustauschBasis = ok ? s.netzPfad : null;
    speicherMeldung = ok ? null : 'Netzwerkordner nicht erreichbar – bis dahin bleibt alles im Projektordner.';
  }

  /// Abgleich: Netzwerkordner prüfen, Cloud abgleichen, Erfassungen übernehmen.
  Future<void> abgleichen() async {
    if (_abgleichLaeuft) return;
    _abgleichLaeuft = true;
    try {
      final vorher = netzAustauschBasis;
      await _netzPruefen();
      final st = store;
      if (st == null) return;
      if (netzAustauschBasis != vorher) {
        try {
          planstandSchreiben(st);
        } catch (_) {}
      }
      final fern = speicher.fern(p.basename(st.ordner));
      if (fern != null) {
        try {
          await fernAbgleich(fern, austauschOrdner(st), planstandHochladen: _planNeu);
          _planNeu = false;
          speicherMeldung = null;
        } catch (e) {
          speicherMeldung = 'Cloud-Speicher nicht erreichbar ($e)';
        }
      }
      letzterAbgleich = DateTime.now();
      if (store == st) eingangPruefen();
    } finally {
      _abgleichLaeuft = false;
    }
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
      _eingangTimer = Timer.periodic(const Duration(seconds: 30), (_) => abgleichen());
      Timer.run(() {
        try {
          planstandSchreiben(s);
        } catch (_) {}
        _planNeu = true;
        abgleichen();
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
        final fern = speicher.fern(p.basename(st.ordner));
        if (fern != null) fernAbgleich(fern, austauschOrdner(st)).catchError((Object _) => 0);
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
