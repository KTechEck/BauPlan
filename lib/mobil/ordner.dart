import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Einstellungen der App (kleine Seite laut Lastenheft): Benutzer, Fotoqualität,
/// zuletzt gewählter Raum und Gewerk.
class MobilEinstellungen {
  MobilEinstellungen._(this._datei);
  final File? _datei;
  String benutzer = '';
  int fotoQualitaet = 80;
  String? geschoss, raum, gewerk;

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
    } catch (_) {}
    return s;
  }

  void speichern() {
    try {
      _datei?.writeAsStringSync(jsonEncode({'benutzer': benutzer, 'foto': fotoQualitaet, 'geschoss': geschoss, 'raum': raum, 'gewerk': gewerk}));
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
