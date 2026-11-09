import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ki.dart' show adresseLokal;

/// Verbindungsdaten zu Home Assistant (Programmeinstellungen dieses PCs,
/// nicht im Projekt – der Zugangsschlüssel bleibt auf dem Rechner).
class HaEinstellung {
  const HaEinstellung({this.adresse = 'http://homeassistant.local:8123', this.token = '', this.fremdzugriff = false});
  final String adresse;
  final String token; // langlebiger Zugangs-Token aus dem HA-Profil
  final bool fremdzugriff; // Zugriff über das Internet (z. B. Nabu Casa) erlaubt

  bool get lokal => adresseLokal(adresse);
  bool get verschluesselt => Uri.tryParse(adresse)?.scheme == 'https';

  /// Grund, warum nicht verbunden werden darf, sonst null.
  String? get sperre {
    if (token.trim().isEmpty) return 'Zugangs-Token fehlt (Home Assistant → Profil → Sicherheit → Langlebige Zugangs-Token).';
    final u = Uri.tryParse(adresse.trim());
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) return 'Adresse ungültig, z. B. http://homeassistant.local:8123';
    if (!lokal && !fremdzugriff) return 'Die Adresse liegt nicht im Heimnetz. Fremdzugriff ist ausgeschaltet.';
    if (!lokal && !verschluesselt) return 'Fremdzugriff nur verschlüsselt (https://…).';
    return null;
  }

  Map<String, dynamic> toJson() => {'adresse': adresse, 'token': token, 'fremd': fremdzugriff};
  static HaEinstellung ausJson(Map<String, dynamic>? m) => m == null
      ? const HaEinstellung()
      : HaEinstellung(
          adresse: m['adresse'] as String? ?? 'http://homeassistant.local:8123',
          token: m['token'] as String? ?? '',
          fremdzugriff: m['fremd'] as bool? ?? false,
        );
}

/// Eine Entität mit aktuellem Zustand.
class HaEntitaet {
  const HaEntitaet({required this.id, required this.zustand, this.name = '', this.einheit = '', this.geaendert});
  final String id; // light.kueche
  final String zustand; // on, off, 21.5, unavailable …
  final String name; // friendly_name
  final String einheit;
  final DateTime? geaendert;

  String get domaene => id.split('.').first;
  bool get erreichbar => zustand != 'unavailable' && zustand != 'unknown';

  static HaEntitaet ausJson(Map<String, dynamic> m) {
    final a = Map<String, dynamic>.from(m['attributes'] as Map? ?? const {});
    return HaEntitaet(
      id: m['entity_id'] as String? ?? '',
      zustand: '${m['state'] ?? ''}',
      name: a['friendly_name'] as String? ?? '',
      einheit: a['unit_of_measurement'] as String? ?? '',
      geaendert: DateTime.tryParse(m['last_changed'] as String? ?? ''),
    );
  }

  /// Zustand lesbar auf Deutsch.
  String get zustandText => switch (zustand) {
        'on' => 'an',
        'off' => 'aus',
        'open' => 'offen',
        'closed' => 'geschlossen',
        'unavailable' => 'nicht erreichbar',
        'unknown' => 'unbekannt',
        'heat' => 'heizen',
        _ => einheit.isEmpty ? zustand : '$zustand $einheit',
      };
}

/// Nur lesende Verbindung zur REST-Schnittstelle von Home Assistant.
class HaVerbindung {
  HaVerbindung(this.einstellung, {HttpClient? client}) : _client = client ?? HttpClient();
  final HaEinstellung einstellung;
  final HttpClient _client;

  Future<dynamic> _holen(String pfad) async {
    final sperre = einstellung.sperre;
    if (sperre != null) throw StateError(sperre);
    final uri = Uri.parse('${einstellung.adresse.trim().replaceAll(RegExp(r'/+$'), '')}$pfad');
    final anfrage = await _client.getUrl(uri).timeout(const Duration(seconds: 8));
    anfrage.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${einstellung.token.trim()}');
    anfrage.headers.contentType = ContentType.json;
    final antwort = await anfrage.close().timeout(const Duration(seconds: 15));
    final text = await antwort.transform(utf8.decoder).join();
    if (antwort.statusCode == 401) throw const HttpException('Home Assistant lehnt den Zugangs-Token ab (401).');
    if (antwort.statusCode != 200) throw HttpException('Home Assistant antwortet mit ${antwort.statusCode}.');
    return jsonDecode(text);
  }

  /// Version prüfen (GET /api/config).
  Future<String> pruefen() async {
    final m = await _holen('/api/config') as Map;
    return '${m['location_name'] ?? 'Home Assistant'} (Version ${m['version'] ?? '?'})';
  }

  /// Alle Entitäten mit Zustand (GET /api/states).
  Future<List<HaEntitaet>> zustaende() async {
    final l = await _holen('/api/states') as List;
    return [for (final e in l) HaEntitaet.ausJson(Map<String, dynamic>.from(e as Map))]..sort((a, b) => a.id.compareTo(b.id));
  }

  void schliessen() => _client.close(force: true);
}

/// In BauSpur eingetragene Entität mit Herkunft.
typedef HaZuordnung = ({String entity, String objektId, String objekt, String rolle});

/// Ergebnis des Abgleichs BauSpur ↔ Home Assistant.
class HaAbgleich {
  HaAbgleich({required this.gefunden, required this.fehlt, required this.nichtErreichbar, required this.unzugeordnet});
  final List<(HaZuordnung, HaEntitaet)> gefunden;
  final List<HaZuordnung> fehlt; // in BauSpur eingetragen, in HA nicht vorhanden
  final List<(HaZuordnung, HaEntitaet)> nichtErreichbar;
  final List<HaEntitaet> unzugeordnet; // in HA, aber keinem Objekt zugeordnet
}

/// Domänen, die zu Objekten im Haus gehören (für „nicht zugeordnet“).
const haGeraeteDomaenen = {'light', 'switch', 'cover', 'climate', 'binary_sensor', 'sensor', 'fan', 'lock', 'valve', 'media_player'};

HaAbgleich haAbgleichen(List<HaZuordnung> bauspur, List<HaEntitaet> ha, {Set<String> domaenen = haGeraeteDomaenen}) {
  final nachId = {for (final e in ha) e.id: e};
  final zugeordnet = {for (final z in bauspur) z.entity};
  final gefunden = <(HaZuordnung, HaEntitaet)>[], weg = <(HaZuordnung, HaEntitaet)>[], fehlt = <HaZuordnung>[];
  for (final z in bauspur) {
    final e = nachId[z.entity];
    if (e == null) {
      fehlt.add(z);
    } else if (!e.erreichbar) {
      weg.add((z, e));
    } else {
      gefunden.add((z, e));
    }
  }
  return HaAbgleich(
    gefunden: gefunden,
    fehlt: fehlt,
    nichtErreichbar: weg,
    unzugeordnet: [for (final e in ha) if (!zugeordnet.contains(e.id) && domaenen.contains(e.domaene)) e],
  );
}

/// Ähnlichste HA-Entität zu einer fehlenden Zuordnung (gleiche Domäne,
/// meiste gemeinsame Wortteile) – als Vorschlag zum Korrigieren.
HaEntitaet? haVorschlag(String entity, List<HaEntitaet> kandidaten) {
  final dom = entity.split('.').first;
  final teile = entity.split('.').last.split('_').where((t) => t.length > 1).toSet();
  HaEntitaet? best;
  var bestWert = 0;
  for (final e in kandidaten) {
    if (e.domaene != dom) continue;
    final w = e.id.split('.').last.split('_').where(teile.contains).length;
    if (w > bestWert) {
      best = e;
      bestWert = w;
    }
  }
  return bestWert >= 2 || (teile.length == 1 && bestWert == 1) ? best : null;
}
