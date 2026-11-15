import 'dart:convert';
import 'dart:async';
import 'dart:io';

import '../core/rollen.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app/version.dart';
import '../core/bauelemente.dart';
import '../core/speicher.dart';
import '../core/ipad_austausch.dart';
import '../data/app_settings.dart';
import '../data/austausch.dart';
import '../data/bauelement_bibliothek.dart';
import '../data/project_store.dart';
import '../ui/bauteile/einkauf_dialog.dart' show besorgungFuerApp;
import '../ui/tastenkuerzel.dart' show TastenBelegung;
import '../core/inhaltspaket.dart' show paketeAusOrdner;
import '../ui/widgets.dart' show MassEinheit;

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
  einkauf('Einkauf'),
  tagebuch('Tagebuch'),
  export('Export'),
  einstellungen('Einstellungen');

  const Modul(this.label);
  final String label;
}

/// Zentraler Zustand der Anwendung: offenes Projekt, gewähltes Modul,
/// gewähltes Geschoss. Widgets hören über ListenableBuilder darauf.
class AppState extends ChangeNotifier {
  AppState(this.settings, {this.touch = false}) {
    TastenBelegung.laden(settings);
    MassEinheit.setzen(settings.darstellung['einheit'] as String?);
    // Auf dem Tablet läuft kein PC-Dienst (das iPad holt Projekte vom PC)
    if (!_imTest && !touch) Timer.run(speicherAnwenden);
    // Planstand für die App: Besorgungsliste und Geräte aus der Bibliothek mitgeben
    zusatzEinkauf = (_) => besorgungFuerApp(this);
    bauelementLesen = (st, id) => bibliothek.fuerProjekt(st, id)?.toJson();
    verkleidungenLesen = (st) => [
          for (final e in bibliothek.auswahl(st, BauelementKategorie.verkleidung)) {'id': e.id, 'name': e.anzeige, 'dicke': e.zahl('dicke')?.round() ?? 0},
        ];
  }

  final AppSettings settings;

  /// Tablet mit Finger/Stift (volle BauSpur auf dem iPad).
  final bool touch;

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
    benutzer: (c) => store == null ? null : benutzerAus(store!.einstellung<List>('benutzer')).where((b) => b.code == c).firstOrNull?.auskunft,
    planFiltern: (b, nutzer) => utf8.encode(jsonEncode(planstandFuerBenutzer(Map<String, dynamic>.from(jsonDecode(utf8.decode(b)) as Map), nutzer))),
  )
    ..projektAusleihen = _projektAusleihen
    ..projektRueckgabe = _projektRueckgabe;

  /// Projekt an ein iPad ausleihen: Ausleihe vermerken, PC-Kopie nur lesbar, ganzen Ordner als ZIP liefern.
  Future<(int, List<int>?, String?)> _projektAusleihen(String geraet, String name) async {
    final st = store;
    if (st == null) return (503, null, 'Am PC ist kein Projekt geöffnet.');
    final a = Ausleihe.lesen(st.ordner);
    if (a != null && a.geraet != geraet) return (409, null, 'Das Projekt ist schon an „${a.name}“ ausgeliehen. Erst dort zurückgeben.');
    try {
      st.sicherungJetzt();
      if (a == null) Ausleihe(geraet: geraet, name: name, seit: DateTime.now(), amPc: true).schreiben(st.ordner);
      if (!st.nurLesen) st.nurLesenSetzen(true);
      notifyListeners();
      final tmp = Directory.systemTemp.createTempSync('bauspur_ipad_');
      final datei = p.join(tmp.path, 'projekt.zip');
      final r = await Process.run('tar', ['-a', '-c', '-f', datei, '--exclude=projekt.lock', '--exclude=backup', '--exclude=austausch', '--exclude=$ausleiheDatei', '-C', st.ordner, '.']);
      if (r.exitCode != 0) return (500, null, 'Packen fehlgeschlagen: ${r.stderr}');
      final b = File(datei).readAsBytesSync();
      tmp.deleteSync(recursive: true);
      return (200, b, null);
    } catch (e) {
      return (500, null, '$e');
    }
  }

  /// Rückgabe vom iPad: prüfen, sichern, Dateien übernehmen, Ausleihe beenden, Projekt neu öffnen.
  Future<String?> _projektRueckgabe(List<int> zip, String geraet) async {
    final st = store;
    if (st == null) return 'Am PC ist kein Projekt geöffnet – bitte das ausgeliehene Projekt öffnen.';
    final a = Ausleihe.lesen(st.ordner);
    if (a == null || a.geraet != geraet) return 'Das offene Projekt ist nicht an dieses iPad ausgeliehen.';
    final daten = Uint8List.fromList(zip);
    final fehler = rueckgabePruefen(daten);
    if (fehler != null) return fehler;
    final ordner = st.ordner;
    st.sicherungJetzt();
    projektSchliessen();
    final db = p.join(ordner, datenbankDatei);
    for (final rest in ['$db-wal', '$db-shm']) {
      if (File(rest).existsSync()) File(rest).deleteSync();
    }
    projektEntpacken(daten, ordner);
    Ausleihe.loeschen(ordner);
    projektOeffnen(ProjectStore.oeffnen(ordner));
    eingangMeldung = 'Projekt vom iPad „${a.name}“ zurück – Stand übernommen (vorher gesichert).';
    notifyListeners();
    return null;
  }

  /// Ausleihe von Hand aufheben (iPad-Änderungen gehen dann verloren).
  void ausleiheAufheben() {
    final st = store;
    if (st == null) return;
    Ausleihe.loeschen(st.ordner);
    st.nurLesenSetzen(false);
    notifyListeners();
  }

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
    if (st == null || st.nurLesen) return; // ausgeliehen: Erfassungen warten bis zur Rückgabe
    try {
      final r = eingangUebernehmen(st);
      if (r.uebernommen > 0 || r.fehler > 0) {
        eingangMeldung = '${r.uebernommen} Erfassung(en) aus der App übernommen${r.fehler > 0 ? ', ${r.fehler} fehlerhaft' : ''}';
        geaendert();
      }
    } catch (_) {}
  }

  /// Infos für die Glocke (z. B. automatisch geladene Inhaltspakete).
  final List<String> infos = [];

  /// Inhaltspakete aus dem eingestellten Ordner laden (nur neue Elemente).
  void _paketeAutomatisch() {
    final ordner = settings.darstellung['pakete_ordner'] as String?;
    if (ordner == null) return;
    try {
      final stand = {for (final e in (settings.darstellung['pakete_stand'] as Map? ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
      final r = paketeAusOrdner(ordner, {for (final e in bibliothek.alle) e.id}, stand);
      for (final e in r.neu.entries) {
        for (final el in e.value) {
          bibliothek.speichern(el);
        }
        infos.add('Inhaltspaket „${e.key}“: ${e.value.length} neue Elemente in die Bibliothek übernommen.');
      }
      settings.darstellung['pakete_stand'] = r.stand;
      settings.speichern();
    } catch (_) {}
  }

  void projektOeffnen(ProjectStore s) {
    store?.schliessen();
    store = s;
    if (Ausleihe.lesen(s.ordner)?.sperrt ?? false) s.nurLesenSetzen(true);
    _eingangTimer?.cancel();
    if (!_imTest && !touch) {
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
    if (!_imTest && !touch) _paketeAutomatisch();
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
