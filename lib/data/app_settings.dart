import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Programmeinstellungen dieses PCs (nicht im Projekt gespeichert).
class AppSettings {
  AppSettings._(this._datei);

  /// Einstellungen in einer bestimmten Datei (für Tests).
  AppSettings.inDatei(File datei) : this._(datei);

  final File _datei;

  /// Ordner der Programmeinstellungen (auch für die Bauelemente-Bibliothek).
  Directory get ordner => _datei.parent;
  List<String> zuletztGeoeffnet = [];
  String design = 'hell';

  /// Fenster beim Start: 'maximiert' oder 'zuletzt' (Größe und Lage wie beim Schließen).
  String fensterStart = 'maximiert';
  List<double>? fensterLage; // x, y, Breite, Höhe
  bool fensterMaximiert = true;

  /// KI-Assistent: Adresse und Modell des lokalen Sprachmodells, Cloud erlaubt (JSON, siehe KiEinstellung).
  Map<String, dynamic>? ki;

  /// Home Assistant: Adresse, Zugangs-Token, Fremdzugriff (JSON, siehe HaEinstellung).
  Map<String, dynamic>? ha;

  /// Erklärungen der Werkzeuge rechts anzeigen.
  bool hilfeAnzeigen = true;

  /// Darstellung der Geräte im Plan: groesse, text, deckkraft, flaeche, form (siehe Einstellungen).
  Map<String, dynamic> darstellung = {};

  /// Speicher und Abgleich mit der App: art (pc/netz/cloud), Kopplungscode, Netzwerkordner, WebDAV (siehe SpeicherEinstellung).
  Map<String, dynamic> speicher = {};

  static Future<AppSettings> laden() async {
    final dir = await getApplicationSupportDirectory();
    final s = AppSettings._(File(p.join(dir.path, 'einstellungen.json')));
    if (s._datei.existsSync()) {
      try {
        final m = jsonDecode(s._datei.readAsStringSync()) as Map<String, dynamic>;
        s.zuletztGeoeffnet = (m['zuletztGeoeffnet'] as List?)?.cast<String>() ?? [];
        s.design = m['design'] as String? ?? 'hell';
        s.fensterStart = m['fensterStart'] as String? ?? 'maximiert';
        s.fensterLage = (m['fensterLage'] as List?)?.map((e) => (e as num).toDouble()).toList();
        s.fensterMaximiert = m['fensterMaximiert'] as bool? ?? true;
        s.ki = (m['ki'] as Map?)?.cast<String, dynamic>();
        s.ha = (m['ha'] as Map?)?.cast<String, dynamic>();
        s.hilfeAnzeigen = m['hilfe'] as bool? ?? true;
        s.darstellung = Map<String, dynamic>.from(m['darstellung'] as Map? ?? const {});
        s.speicher = Map<String, dynamic>.from(m['speicher'] as Map? ?? const {});
      } catch (_) {
        // Beschädigte Datei: mit Standardwerten weiter.
      }
    }
    return s;
  }

  void merkeProjekt(String ordner) {
    zuletztGeoeffnet
      ..remove(ordner)
      ..insert(0, ordner);
    if (zuletztGeoeffnet.length > 10) {
      zuletztGeoeffnet = zuletztGeoeffnet.sublist(0, 10);
    }
    speichern();
  }

  void vergissProjekt(String ordner) {
    zuletztGeoeffnet.remove(ordner);
    speichern();
  }

  void speichern() {
    _datei.parent.createSync(recursive: true);
    _datei.writeAsStringSync(jsonEncode({
      'zuletztGeoeffnet': zuletztGeoeffnet,
      'design': design,
      'fensterStart': fensterStart,
      'fensterLage': fensterLage,
      'fensterMaximiert': fensterMaximiert,
      'ki': ki,
      'ha': ha,
      'hilfe': hilfeAnzeigen,
      'darstellung': darstellung,
      'speicher': speicher,
    }));
  }
}
