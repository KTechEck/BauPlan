import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/speicher.dart';

/// Zugriff auf den Projektordner (bis zum NAS: der OneDrive-Projektordner).
/// Die App liest nur `planstand/` und schreibt nur nach `eingang/`.
abstract class ProjektOrdner {
  Future<String?> name();
  Future<String?> waehlen();
  Future<Uint8List?> lesen(String pfad);
  Future<bool> schreiben(String pfad, List<int> daten);

  /// Was die App im Ordner sieht (zur Fehlersuche).
  Future<String> info();
}

/// iPhone/iPad: Ordner über die Dateien-App gewählt, dauerhaft gemerkt (nativer Kanal).
class KanalOrdner implements ProjektOrdner {
  static const _k = MethodChannel('bauspur/ordner');

  @override
  Future<String?> name() => _k.invokeMethod<String>('name');

  @override
  Future<String?> waehlen() => _k.invokeMethod<String>('waehlen');

  @override
  Future<Uint8List?> lesen(String pfad) => _k.invokeMethod<Uint8List>('lesen', {'pfad': pfad});

  @override
  Future<bool> schreiben(String pfad, List<int> daten) async =>
      await _k.invokeMethod<bool>('schreiben', {'pfad': pfad, 'daten': Uint8List.fromList(daten)}) ?? false;

  @override
  Future<String> info() async => await _k.invokeMethod<String>('info') ?? '';
}

/// Für Tests und den PC: ein normaler Ordner.
class LokalOrdner implements ProjektOrdner {
  LokalOrdner(this.pfad);
  String? pfad;

  @override
  Future<String?> name() async => pfad == null ? null : p.basename(pfad!);

  @override
  Future<String?> waehlen() async => name();

  @override
  Future<Uint8List?> lesen(String rel) async {
    if (pfad == null) return null;
    final f = File(p.join(pfad!, rel));
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  @override
  Future<bool> schreiben(String rel, List<int> daten) async {
    if (pfad == null) return false;
    final f = File(p.join(pfad!, rel));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(daten);
    return true;
  }

  @override
  Future<String> info() async {
    if (pfad == null) return 'kein Ordner gewählt';
    final d = Directory(pfad!);
    return [
      'Ordner: $pfad',
      for (final u in ['', 'planstand', 'eingang'])
        '${u.isEmpty ? '/' : u}: ${Directory(p.join(d.path, u)).existsSync() ? Directory(p.join(d.path, u)).listSync().map((e) => p.basename(e.path)).join(', ') : '(fehlt)'}',
    ].join('\n');
  }
}

/// Handy und Tablet (iPhone wie Android): der Austauschordner liegt nicht auf
/// dem Gerät, sondern wird über das Netz erreicht – direkt bei BauSpur am PC
/// oder über WebDAV (NAS, Cloud). Der zuletzt gelesene Planstand bleibt auf dem
/// Gerät, damit Nachschlagen auch ohne Verbindung geht.
class FernOrdner implements ProjektOrdner {
  FernOrdner(this.einstellungen, this.zwischenspeicher, {this.suche = pcSuchen});
  final MobilEinstellungen einstellungen;
  final Directory zwischenspeicher;
  final Future<List<GefundenerPc>> Function() suche;

  /// Letzte Störung (für die Anzeige), null wenn der letzte Zugriff klappte.
  String? fehler;
  DateTime? _letzteSuche;

  Map<String, dynamic> get _v => einstellungen.verbindung;
  bool get istPc => _v['art'] != 'webdav';
  bool get eingerichtet => istPc ? '${_v['adresse'] ?? ''}'.isNotEmpty : '${_v['url'] ?? ''}'.isNotEmpty;
  File get _planKopie => File(p.join(zwischenspeicher.path, 'planstand_kopie.json'));

  Speicher? speicher() {
    if (!eingerichtet) return null;
    if (istPc) return PcSpeicher('${_v['adresse']}', code: '${_v['code'] ?? ''}');
    final dav = WebDavSpeicher('${_v['url']}', benutzer: '${_v['benutzer'] ?? ''}', passwort: '${_v['passwort'] ?? ''}', unsicher: _v['unsicher'] == true);
    final projekt = '${_v['projekt'] ?? ''}';
    return projekt.isEmpty ? dav : UnterSpeicher(dav, projekt);
  }

  /// Hat der PC im Heimnetz eine neue Adresse bekommen, sucht die App ihn
  /// selbst wieder (höchstens alle zwei Minuten).
  Future<bool> _pcWiederfinden() async {
    if (!istPc || _v['auto'] == false) return false;
    final jetzt = DateTime.now();
    if (_letzteSuche != null && jetzt.difference(_letzteSuche!) < const Duration(minutes: 2)) return false;
    _letzteSuche = jetzt;
    final gefunden = await suche();
    final treffer = gefunden.where((g) => g.name == _v['pc_name']).firstOrNull ?? (gefunden.length == 1 ? gefunden.first : null);
    if (treffer == null || treffer.adresse == _v['adresse']) return false;
    _v['adresse'] = treffer.adresse;
    einstellungen.speichern();
    return true;
  }

  Future<T> _mit<T>(Future<T> Function(Speicher s) tun) async {
    final s = speicher();
    if (s == null) throw StateError('nicht eingerichtet');
    try {
      final r = await tun(s);
      fehler = null;
      return r;
    } on CodeFalsch {
      fehler = 'Der Kopplungscode stimmt nicht mehr.';
      rethrow;
    } catch (e) {
      if (await _pcWiederfinden()) {
        final r = await tun(speicher()!);
        fehler = null;
        return r;
      }
      fehler = istPc ? 'PC nicht erreichbar (anderes WLAN oder BauSpur am PC geschlossen).' : 'Speicher nicht erreichbar.';
      rethrow;
    }
  }

  @override
  Future<String?> name() async => !eingerichtet
      ? null
      : istPc
          ? '${_v['pc_name'] ?? _v['adresse']}'
          : Uri.tryParse('${_v['url']}')?.host ?? 'WebDAV';

  @override
  Future<String?> waehlen() => name();

  @override
  Future<Uint8List?> lesen(String pfad) async {
    Uint8List? b;
    try {
      b = await _mit((s) => s.lesen(pfad));
    } catch (_) {}
    if (pfad != planstandPfad) return b;
    try {
      if (b != null) {
        _planKopie.writeAsBytesSync(b);
      } else if (_planKopie.existsSync()) {
        b = _planKopie.readAsBytesSync();
      }
    } catch (_) {}
    return b;
  }

  @override
  Future<bool> schreiben(String pfad, List<int> daten) async {
    try {
      return await _mit((s) => s.schreiben(pfad, daten));
    } catch (_) {
      return false;
    }
  }

  /// Verbindung trennen (auch die Kopie des Planstands verwerfen).
  void trennen() {
    einstellungen.verbindung = {};
    einstellungen.speichern();
    try {
      if (_planKopie.existsSync()) _planKopie.deleteSync();
    } catch (_) {}
  }

  @override
  Future<String> info() async {
    if (!eingerichtet) return 'noch nicht verbunden';
    final projekt = '${_v['projekt'] ?? ''}';
    final zeilen = <String>[istPc ? 'BauSpur-PC: ${_v['pc_name'] ?? ''} (${_v['adresse']})' : 'WebDAV: ${_v['url']}${projekt.isEmpty ? '' : ' › $projekt'}'];
    try {
      final namen = await _mit((s) => s.liste('planstand'));
      zeilen.add('planstand: ${namen.isEmpty ? '(leer – Projekt am PC öffnen)' : namen.join(', ')}');
    } catch (e) {
      zeilen.add(fehler ?? '$e');
    }
    return zeilen.join('\n');
  }
}

/// Einstellungen der App (kleine Seite laut Lastenheft): Benutzer, Fotoqualität,
/// zuletzt gewählter Raum und Gewerk.
class MobilEinstellungen {
  MobilEinstellungen._(this._datei);
  final File? _datei;
  String benutzer = '';
  int fotoQualitaet = 80;
  String? geschoss, raum, gewerk;

  /// Verbindung zum Speicher: art (pc/webdav), adresse, code, pc_name, auto, url, benutzer, passwort, unsicher, projekt.
  Map<String, dynamic> verbindung = {};

  static Future<MobilEinstellungen> laden({Directory? ordner}) async {
    final dir = ordner ?? await getApplicationDocumentsDirectory();
    final s = MobilEinstellungen._(File(p.join(dir.path, 'bauspur_mobil.json')));
    try {
      final m = jsonDecode(s._datei!.readAsStringSync()) as Map;
      s.benutzer = m['benutzer'] as String? ?? '';
      s.fotoQualitaet = (m['foto'] as num?)?.toInt() ?? 80;
      s.geschoss = m['geschoss'] as String?;
      s.raum = m['raum'] as String?;
      s.gewerk = m['gewerk'] as String?;
      s.verbindung = Map<String, dynamic>.from(m['verbindung'] as Map? ?? const {});
    } catch (_) {}
    return s;
  }

  void speichern() {
    try {
      _datei?.writeAsStringSync(jsonEncode({'benutzer': benutzer, 'foto': fotoQualitaet, 'geschoss': geschoss, 'raum': raum, 'gewerk': gewerk, 'verbindung': verbindung}));
    } catch (_) {}
  }
}

/// Offline-Puffer: jede Erfassung liegt zuerst auf dem Gerät und wird
/// übertragen, sobald der Projektordner erreichbar ist.
class Puffer {
  Puffer(this.ordner);
  final Directory ordner;

  static Future<Puffer> laden({Directory? basis}) async {
    final dir = Directory(p.join((basis ?? await getApplicationDocumentsDirectory()).path, 'puffer'))..createSync(recursive: true);
    return Puffer(dir);
  }

  List<File> get wartend => ordner.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// Erfassung ablegen; [foto] wird als `<name>.jpg` daneben gespeichert.
  String ablegen(Map<String, dynamic> eintrag, {List<int>? foto}) {
    final zeit = DateTime.now().toUtc();
    final stempel = zeit.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final id = '${stempel}_${zeit.microsecondsSinceEpoch.toRadixString(36)}';
    final e = {...eintrag, 'id': id, 'zeit': zeit.toIso8601String()};
    if (foto != null) {
      File(p.join(ordner.path, '$id.jpg')).writeAsBytesSync(foto);
      e['datei'] = '$id.jpg';
    }
    File(p.join(ordner.path, '$id.json')).writeAsStringSync(jsonEncode(e));
    return id;
  }

  /// Wartende Erfassungen nach `eingang/` schreiben: erst das Foto, dann die
  /// Beschreibung (der PC übernimmt nur vollständige Einträge).
  Future<int> uebertragen(ProjektOrdner ziel) async {
    var n = 0;
    for (final json in wartend) {
      final name = p.basenameWithoutExtension(json.path);
      final foto = File(p.join(ordner.path, '$name.jpg'));
      try {
        if (foto.existsSync() && !await ziel.schreiben('eingang/$name.jpg', foto.readAsBytesSync())) break;
        if (!await ziel.schreiben('eingang/$name.json', json.readAsBytesSync())) break;
      } catch (_) {
        break;
      }
      json.deleteSync();
      if (foto.existsSync()) foto.deleteSync();
      n++;
    }
    return n;
  }
}
