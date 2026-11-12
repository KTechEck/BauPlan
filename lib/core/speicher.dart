import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Speicherwege für den Abgleich PC ↔ App. Alles läuft über gewöhnliches
/// HTTP bzw. Dateien – gleich auf Windows, iPhone und Android, ohne
/// Sonderweg eines Herstellers.
///
/// Drei Arten (am PC unter Einstellungen › Speicher und Abgleich):
/// - `pc`: nur dieser PC. Die App spricht im WLAN direkt mit BauSpur ([PcDienst]).
/// - `netz`: Ordner auf einem NAS oder Netzwerkrechner; die App erreicht ihn
///   über WebDAV oder ebenfalls über den PC.
/// - `cloud`: WebDAV-Speicher im Internet; PC und App gleichen beide dorthin ab.
const bauspurPort = 47824;
const planstandPfad = 'planstand/planstand.json';

/// Ablage mit Pfaden relativ zum Austauschordner (`planstand/…`, `eingang/…`).
abstract class Speicher {
  String get bezeichnung;
  Future<Uint8List?> lesen(String pfad);
  Future<bool> schreiben(String pfad, List<int> daten);

  /// Namen im Ordner; Unterordner enden auf `/`.
  Future<List<String>> liste(String ordner);
  Future<bool> loeschen(String pfad);
}

bool _pfadErlaubt(String pfad) => !pfad.contains('..') && !pfad.contains('\\') && !pfad.startsWith('/') && !pfad.contains(':');

/// Gewöhnlicher Ordner (Projektordner, Netzlaufwerk, Freigabe).
class OrdnerSpeicher implements Speicher {
  OrdnerSpeicher(this.pfad);
  final String pfad;

  @override
  String get bezeichnung => pfad;

  @override
  Future<Uint8List?> lesen(String rel) async {
    final f = File(p.join(pfad, rel));
    return await f.exists() ? await f.readAsBytes() : null;
  }

  @override
  Future<bool> schreiben(String rel, List<int> daten) async {
    final f = File(p.join(pfad, rel));
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(daten, flush: true);
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
    return true;
  }

  @override
  Future<List<String>> liste(String ordner) async {
    final d = Directory(p.join(pfad, ordner));
    if (!await d.exists()) return [];
    return [
      await for (final e in d.list())
        if (!p.basename(e.path).endsWith('.tmp')) e is Directory ? '${p.basename(e.path)}/' : p.basename(e.path)
    ];
  }

  @override
  Future<bool> loeschen(String rel) async {
    final f = File(p.join(pfad, rel));
    if (await f.exists()) await f.delete();
    return true;
  }
}

HttpClient _client({bool unsicher = false, Duration zeit = const Duration(seconds: 6)}) {
  final c = HttpClient()
    ..connectionTimeout = zeit
    ..idleTimeout = const Duration(seconds: 5);
  // Eigene Geräte im Heimnetz (NAS) haben oft ein selbst signiertes Zertifikat.
  if (unsicher) c.badCertificateCallback = (_, __, ___) => true;
  return c;
}

Future<Uint8List> _rumpf(HttpClientResponse r) async {
  final b = BytesBuilder(copy: false);
  await for (final teil in r) {
    b.add(teil);
  }
  return b.takeBytes();
}

/// WebDAV: NAS (Synology, QNAP, Fritz!Box-NAS …), Nextcloud und viele Cloud-Speicher.
class WebDavSpeicher implements Speicher {
  WebDavSpeicher(String url, {this.benutzer = '', this.passwort = '', this.unsicher = false})
      : basis = Uri.parse(url.trim().endsWith('/') ? url.trim() : '${url.trim()}/');
  final Uri basis;
  final String benutzer, passwort;
  final bool unsicher;
  final _angelegt = <String>{};

  @override
  String get bezeichnung => basis.host;

  Uri _uri(String rel) => basis.resolve(rel.split('/').map(Uri.encodeComponent).join('/'));

  Future<HttpClientResponse> _anfrage(String methode, String rel, {List<int>? daten, Map<String, String> kopf = const {}}) async {
    final c = _client(unsicher: unsicher);
    try {
      final a = await c.openUrl(methode, _uri(rel));
      if (benutzer.isNotEmpty) a.headers.set('Authorization', 'Basic ${base64Encode(utf8.encode('$benutzer:$passwort'))}');
      kopf.forEach(a.headers.set);
      if (daten != null) {
        a.contentLength = daten.length;
        a.add(daten);
      }
      return await a.close().timeout(const Duration(seconds: 60));
    } finally {
      c.close();
    }
  }

  @override
  Future<Uint8List?> lesen(String rel) async {
    final r = await _anfrage('GET', rel);
    final b = await _rumpf(r);
    return r.statusCode == 200 ? b : null;
  }

  Future<void> _ordnerAnlegen(String rel) async {
    final teile = rel.split('/')..removeLast();
    var pfad = '';
    for (final t in teile) {
      pfad = '$pfad$t/';
      if (_angelegt.add(pfad)) await (await _anfrage('MKCOL', pfad)).drain<void>();
    }
  }

  @override
  Future<bool> schreiben(String rel, List<int> daten) async {
    await _ordnerAnlegen(rel);
    final r = await _anfrage('PUT', rel, daten: daten);
    await r.drain<void>();
    return r.statusCode >= 200 && r.statusCode < 300;
  }

  @override
  Future<List<String>> liste(String ordner) async {
    final rel = ordner.isEmpty || ordner.endsWith('/') ? ordner : '$ordner/';
    final r = await _anfrage('PROPFIND', rel, kopf: {'Depth': '1'});
    final text = utf8.decode(await _rumpf(r), allowMalformed: true);
    if (r.statusCode != 207 && r.statusCode != 200) return [];
    final selbst = _uri(rel).path.replaceAll(RegExp(r'/+$'), '');
    final aus = <String>[];
    for (final m in RegExp(r'<(?:[A-Za-z0-9]+:)?href[^>]*>([^<]+)</', caseSensitive: false).allMatches(text)) {
      var h = m.group(1)!.trim();
      if (h.contains('://')) h = Uri.parse(h).path;
      final istOrdner = h.endsWith('/');
      final pfad = Uri.decodeFull(h.replaceAll(RegExp(r'/+$'), ''));
      if (pfad == Uri.decodeFull(selbst) || pfad.isEmpty) continue;
      aus.add('${pfad.split('/').last}${istOrdner ? '/' : ''}');
    }
    return aus;
  }

  @override
  Future<bool> loeschen(String rel) async {
    final r = await _anfrage('DELETE', rel);
    await r.drain<void>();
    return r.statusCode < 300 || r.statusCode == 404;
  }
}

/// Unterordner eines Speichers als eigener Speicher (z. B. je Projekt).
class UnterSpeicher implements Speicher {
  UnterSpeicher(this.innen, this.ordner);
  final Speicher innen;
  final String ordner;
  String _p(String rel) => rel.isEmpty ? ordner : '$ordner/$rel';

  @override
  String get bezeichnung => '${innen.bezeichnung} › $ordner';
  @override
  Future<Uint8List?> lesen(String pfad) => innen.lesen(_p(pfad));
  @override
  Future<bool> schreiben(String pfad, List<int> daten) => innen.schreiben(_p(pfad), daten);
  @override
  Future<List<String>> liste(String o) => innen.liste(_p(o));
  @override
  Future<bool> loeschen(String pfad) => innen.loeschen(_p(pfad));
}

/// Falscher oder fehlender Kopplungscode.
class CodeFalsch implements Exception {
  @override
  String toString() => 'Kopplungscode stimmt nicht';
}

/// Die App spricht direkt mit BauSpur auf dem PC ([PcDienst]).
class PcSpeicher implements Speicher {
  PcSpeicher(this.adresse, {this.code = ''});

  /// `192.168.1.20` oder `192.168.1.20:47824`.
  final String adresse;
  final String code;

  @override
  String get bezeichnung => adresse;

  Uri _uri(String teil) {
    final a = adresse.contains(':') ? adresse : '$adresse:$bauspurPort';
    return Uri.parse('http://$a/$teil');
  }

  Future<HttpClientResponse> _anfrage(String methode, String teil, {List<int>? daten}) async {
    final c = _client(zeit: const Duration(seconds: 3));
    try {
      final a = await c.openUrl(methode, _uri(teil));
      a.headers.set('x-bauspur-code', code);
      if (daten != null) {
        a.contentLength = daten.length;
        a.add(daten);
      }
      final r = await a.close().timeout(const Duration(seconds: 60));
      if (r.statusCode == 401) {
        await r.drain<void>();
        throw CodeFalsch();
      }
      return r;
    } finally {
      c.close();
    }
  }

  @override
  Future<Uint8List?> lesen(String pfad) async {
    final r = await _anfrage('GET', 'datei/$pfad');
    final b = await _rumpf(r);
    return r.statusCode == 200 ? b : null;
  }

  @override
  Future<bool> schreiben(String pfad, List<int> daten) async {
    final r = await _anfrage('PUT', 'datei/$pfad', daten: daten);
    await r.drain<void>();
    return r.statusCode == 200;
  }

  @override
  Future<List<String>> liste(String ordner) async {
    final r = await _anfrage('GET', 'liste/$ordner');
    final b = await _rumpf(r);
    return r.statusCode == 200 ? (jsonDecode(utf8.decode(b)) as List).cast<String>() : [];
  }

  @override
  Future<bool> loeschen(String pfad) async => false;

  /// Prüft Adresse und Code; liefert die Auskunft des PCs.
  Future<Map<String, dynamic>> pruefen() async {
    final r = await _anfrage('GET', 'pruefen');
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(await _rumpf(r))) as Map);
  }
}

/// Kleiner Dienst in BauSpur am PC: gibt der App im Heimnetz den Planstand
/// und nimmt Erfassungen an. Ohne Kopplungscode gibt es nur den Namen des PCs.
class PcDienst {
  PcDienst({required this.ordner, required this.code, required this.auskunft, this.beiEingang});

  /// Austauschordner des offenen Projekts (null: kein Projekt offen).
  final String? Function() ordner;
  final String Function() code;
  final Map<String, dynamic> Function() auskunft;
  final void Function()? beiEingang;

  HttpServer? _server;
  String? fehler;
  int? get port => _server?.port;
  bool get laeuft => _server != null;

  Future<bool> starten({int port = bauspurPort}) async {
    await stoppen();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      fehler = null;
      _server!.listen((a) => _bedienen(a).catchError((Object _) {}));
      return true;
    } catch (e) {
      fehler = '$e';
      return false;
    }
  }

  Future<void> stoppen() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  Future<void> _antwort(HttpRequest a, int status, [Object? json]) async {
    a.response.statusCode = status;
    if (json != null) {
      a.response.headers.contentType = ContentType.json;
      a.response.add(utf8.encode(jsonEncode(json)));
    }
    await a.response.close();
  }

  Future<void> _bedienen(HttpRequest a) async {
    final teile = a.uri.pathSegments;
    final kopf = teile.isEmpty ? '' : teile.first;
    if (kopf == 'bauspur') return _antwort(a, 200, {'dienst': 'bauspur', ...auskunft()});
    if (a.headers.value('x-bauspur-code') != code()) {
      // bremst das Durchprobieren von Codes
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return _antwort(a, 401);
    }
    if (kopf == 'pruefen') return _antwort(a, 200, {'dienst': 'bauspur', ...auskunft()});
    final basis = ordner();
    final rel = teile.skip(1).join('/');
    if (basis == null) return _antwort(a, 503, {'fehler': 'Am PC ist kein Projekt geöffnet.'});
    if (!_pfadErlaubt(rel) || !(rel.startsWith('planstand') || rel.startsWith('eingang'))) return _antwort(a, 403);
    final lokal = OrdnerSpeicher(basis);
    if (kopf == 'liste' && a.method == 'GET') return _antwort(a, 200, await lokal.liste(rel));
    if (kopf == 'datei' && a.method == 'GET') {
      final b = await lokal.lesen(rel);
      if (b == null) return _antwort(a, 404);
      a.response.add(b);
      return a.response.close();
    }
    if (kopf == 'datei' && a.method == 'PUT' && rel.startsWith('eingang/') && !rel.contains('_archiv')) {
      final b = BytesBuilder(copy: false);
      await for (final t in a) {
        b.add(t);
      }
      await lokal.schreiben(rel, b.takeBytes());
      if (rel.endsWith('.json')) beiEingang?.call();
      return _antwort(a, 200);
    }
    return _antwort(a, 404);
  }
}

String neuerCode() => (Random.secure().nextInt(900000) + 100000).toString();

/// Eigene IPv4-Adressen im Heimnetz.
Future<List<String>> eigeneAdressen() async {
  try {
    final netze = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final n in netze)
        for (final a in n.addresses)
          if (!a.isLoopback && !a.address.startsWith('169.254.')) a.address
    ];
  } catch (_) {
    return [];
  }
}

typedef GefundenerPc = ({String adresse, String name, String projekt});

/// Auskunft eines BauSpur-PCs (ohne Code), sonst null.
Future<GefundenerPc?> pcAuskunft(String adresse, {Duration zeit = const Duration(seconds: 2)}) async {
  final a = adresse.contains(':') ? adresse : '$adresse:$bauspurPort';
  final c = _client(zeit: zeit);
  try {
    final r = await (await c.getUrl(Uri.parse('http://$a/bauspur'))).close().timeout(zeit);
    final m = jsonDecode(utf8.decode(await _rumpf(r).timeout(zeit))) as Map;
    if (m['dienst'] != 'bauspur') return null;
    return (adresse: a, name: '${m['name'] ?? 'PC'}', projekt: '${m['projekt'] ?? ''}');
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

/// Sucht BauSpur-PCs im eigenen Heimnetz: fragt alle Adressen des eigenen
/// Netzes (x.y.z.1–254) kurz an. Braucht keine Rundrufe und damit auf dem
/// iPhone keine Sonderfreigabe – nur die Erlaubnis „Lokales Netzwerk“.
Future<List<GefundenerPc>> pcSuchen({int port = bauspurPort, List<String>? adressen, Duration zeit = const Duration(milliseconds: 900)}) async {
  final ziele = <String>{...?adressen};
  if (adressen == null) {
    for (final eigen in await eigeneAdressen()) {
      final t = eigen.split('.');
      if (t.length != 4) continue;
      for (var i = 1; i < 255; i++) {
        ziele.add('${t[0]}.${t[1]}.${t[2]}.$i');
      }
    }
  }
  final offen = await Future.wait(ziele.map((z) async {
    try {
      final s = await Socket.connect(z, port, timeout: zeit);
      s.destroy();
      return z;
    } catch (_) {
      return null;
    }
  }));
  final gefunden = await Future.wait(offen.whereType<String>().map((z) => pcAuskunft('$z:$port')));
  return gefunden.whereType<GefundenerPc>().toList();
}

/// Abgleich des PCs mit einem fernen Speicher (Cloud): Planstand hochladen,
/// Erfassungen aus `eingang/` in den lokalen Austauschordner holen und fern löschen.
/// Fotos zuerst, damit der PC nur vollständige Einträge übernimmt.
Future<int> fernAbgleich(Speicher fern, String lokalOrdner, {bool planstandHochladen = true}) async {
  final lokal = OrdnerSpeicher(lokalOrdner);
  if (planstandHochladen) {
    final plan = await lokal.lesen(planstandPfad);
    if (plan != null) await fern.schreiben(planstandPfad, plan);
  }
  final namen = (await fern.liste('eingang')).where((n) => !n.endsWith('/')).toList()
    ..sort((a, b) => (a.endsWith('.json') ? 1 : 0).compareTo(b.endsWith('.json') ? 1 : 0));
  var n = 0;
  for (final name in namen) {
    final b = await fern.lesen('eingang/$name');
    if (b == null) continue;
    await lokal.schreiben('eingang/$name', b);
    await fern.loeschen('eingang/$name');
    if (name.endsWith('.json')) n++;
  }
  return n;
}

/// Speichereinstellung dieses PCs (in den Programmeinstellungen).
class SpeicherEinstellung {
  SpeicherEinstellung([Map<String, dynamic>? m]) : daten = {...?m};
  final Map<String, dynamic> daten;

  /// `pc`, `netz` oder `cloud`.
  String get art => const ['pc', 'netz', 'cloud'].contains(daten['art']) ? daten['art'] as String : 'pc';
  bool get dienst => daten['dienst'] as bool? ?? true;
  int get port => (daten['port'] as num?)?.toInt() ?? bauspurPort;
  String get code => daten['code'] as String? ?? '';
  String get netzPfad => (daten['netz_pfad'] as String? ?? '').trim();
  String get url => (daten['url'] as String? ?? '').trim();
  String get benutzer => daten['benutzer'] as String? ?? '';
  String get passwort => daten['passwort'] as String? ?? '';
  bool get unsicher => daten['unsicher'] as bool? ?? false;

  /// Ferner Speicher für das Projekt (nur Cloud), sonst null.
  Speicher? fern(String projekt) =>
      art == 'cloud' && url.isNotEmpty ? UnterSpeicher(WebDavSpeicher(url, benutzer: benutzer, passwort: passwort, unsicher: unsicher), projekt) : null;
}
