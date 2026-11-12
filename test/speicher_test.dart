import 'dart:convert';
import 'dart:io';

import 'package:bauspur/core/speicher.dart';
import 'package:bauspur/mobil/ordner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Kleiner WebDAV-Server für die Tests (GET, PUT, MKCOL, PROPFIND, DELETE mit Anmeldung).
Future<HttpServer> _webdav(Directory wurzel, {String benutzer = 'tim', String passwort = 'geheim'}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final erwartet = 'Basic ${base64Encode(utf8.encode('$benutzer:$passwort'))}';
  server.listen((a) async {
    final rel = a.uri.pathSegments.where((s) => s.isNotEmpty).join('/');
    final datei = File(p.join(wurzel.path, rel));
    final ordner = Directory(p.join(wurzel.path, rel));
    var status = 200;
    if (a.headers.value('authorization') != erwartet) {
      status = 401;
    } else if (a.method == 'MKCOL') {
      status = ordner.existsSync() ? 405 : 201;
      ordner.createSync(recursive: true);
    } else if (a.method == 'PUT') {
      if (!datei.parent.existsSync()) {
        status = 409;
      } else {
        final b = BytesBuilder();
        await for (final t in a) {
          b.add(t);
        }
        datei.writeAsBytesSync(b.takeBytes());
        status = 201;
      }
    } else if (a.method == 'GET') {
      if (datei.existsSync()) {
        a.response.add(datei.readAsBytesSync());
        await a.response.close();
        return;
      } else {
        status = 404;
      }
    } else if (a.method == 'DELETE') {
      if (datei.existsSync()) datei.deleteSync();
      status = 204;
    } else if (a.method == 'PROPFIND') {
      if (!ordner.existsSync()) {
        status = 404;
      } else {
        final basis = '/${rel.isEmpty ? '' : '${rel.split('/').map(Uri.encodeComponent).join('/')}/'}';
        final eintraege = [
          basis,
          for (final e in ordner.listSync()) '$basis${Uri.encodeComponent(p.basename(e.path))}${e is Directory ? '/' : ''}',
        ];
        a.response.statusCode = 207;
        a.response.write('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">${eintraege.map((h) => '<d:response><d:href>$h</d:href></d:response>').join()}</d:multistatus>');
        await a.response.close();
        return;
      }
    }
    a.response.statusCode = status;
    await a.response.close();
  });
  return server;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bauspur_speicher'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('PC-Dienst: Suche, Kopplungscode, Planstand lesen, Erfassung schreiben', () async {
    File(p.join(tmp.path, 'planstand', 'planstand.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"projekt":"Wohnhaus"}');
    var eingang = 0;
    String? offen = tmp.path;
    final dienst = PcDienst(ordner: () => offen, code: () => '123456', auskunft: () => {'name': 'WERKSTATT', 'projekt': 'Wohnhaus'}, beiEingang: () => eingang++);
    expect(await dienst.starten(port: 0), isTrue);
    addTearDown(dienst.stoppen);
    final adresse = '127.0.0.1:${dienst.port}';

    final gefunden = await pcSuchen(port: dienst.port!, adressen: ['127.0.0.1']);
    expect(gefunden.single.name, 'WERKSTATT');
    expect(gefunden.single.projekt, 'Wohnhaus');
    expect(gefunden.single.adresse, adresse);

    expect(() => PcSpeicher(adresse, code: '000000').lesen(planstandPfad), throwsA(isA<CodeFalsch>()));
    final pc = PcSpeicher(adresse, code: '123456');
    expect((await pc.pruefen())['name'], 'WERKSTATT');
    expect(utf8.decode((await pc.lesen(planstandPfad))!), contains('Wohnhaus'));
    expect(await pc.schreiben('eingang/a.jpg', [1, 2, 3]), isTrue);
    expect(await pc.schreiben('eingang/a.json', utf8.encode('{}')), isTrue);
    expect(File(p.join(tmp.path, 'eingang', 'a.jpg')).readAsBytesSync(), [1, 2, 3]);
    expect(eingang, 1);
    expect(await pc.liste('eingang'), containsAll(['a.jpg', 'a.json']));

    // Nur eingang/ ist beschreibbar, nichts außerhalb des Austauschs lesbar.
    expect(await pc.schreiben('planstand/planstand.json', [0]), isFalse);
    expect(await pc.lesen('projekt.db'), isNull);
    expect(await pc.schreiben('eingang/../x.json', [0]), isFalse);
    expect(File(p.join(tmp.path, 'x.json')).existsSync(), isFalse);

    // Kein Projekt offen: Auskunft ja, Daten nein.
    offen = null;
    expect(await pc.lesen(planstandPfad), isNull);
  });

  test('WebDAV: schreiben mit Ordnern, lesen, auflisten, löschen', () async {
    final server = await _webdav(tmp);
    addTearDown(() => server.close(force: true));
    final url = 'http://127.0.0.1:${server.port}/BauSpur';
    Directory(p.join(tmp.path, 'BauSpur')).createSync();
    final dav = WebDavSpeicher(url, benutzer: 'tim', passwort: 'geheim');
    final projekt = UnterSpeicher(dav, 'Haus Nr 5');
    expect(await projekt.schreiben(planstandPfad, utf8.encode('{"projekt":"x"}')), isTrue);
    expect(await projekt.schreiben('eingang/1.json', [1]), isTrue);
    expect(utf8.decode((await projekt.lesen(planstandPfad))!), '{"projekt":"x"}');
    expect(await dav.liste(''), ['Haus Nr 5/']);
    expect(await projekt.liste('eingang'), ['1.json']);
    expect(await projekt.loeschen('eingang/1.json'), isTrue);
    expect(await projekt.liste('eingang'), isEmpty);
    expect(await projekt.lesen('fehlt.json'), isNull);
    expect(await WebDavSpeicher(url, benutzer: 'tim', passwort: 'falsch').schreiben('a.txt', [1]), isFalse);
  });

  test('Cloud-Abgleich des PCs: Planstand hoch, Erfassungen herunter und fern gelöscht', () async {
    final fernOrdner = Directory(p.join(tmp.path, 'fern'))..createSync();
    final lokal = Directory(p.join(tmp.path, 'lokal'))..createSync();
    final server = await _webdav(fernOrdner);
    addTearDown(() => server.close(force: true));
    final fern = UnterSpeicher(WebDavSpeicher('http://127.0.0.1:${server.port}', benutzer: 'tim', passwort: 'geheim'), 'Wohnhaus');
    await OrdnerSpeicher(lokal.path).schreiben(planstandPfad, utf8.encode('{"v":1}'));
    // Das Handy hat schon etwas abgelegt.
    await fern.schreiben('eingang/20261112_a.json', utf8.encode('{"art":"notiz","datei":"20261112_a.jpg"}'));
    await fern.schreiben('eingang/20261112_a.jpg', [9, 9]);

    expect(await fernAbgleich(fern, lokal.path), 1);
    expect(File(p.join(fernOrdner.path, 'Wohnhaus', 'planstand', 'planstand.json')).readAsStringSync(), '{"v":1}');
    expect(File(p.join(lokal.path, 'eingang', '20261112_a.jpg')).readAsBytesSync(), [9, 9]);
    expect(File(p.join(lokal.path, 'eingang', '20261112_a.json')).existsSync(), isTrue);
    expect(await fern.liste('eingang'), isEmpty);
    expect(await fernAbgleich(fern, lokal.path), 0);
  });

  test('App: findet den PC unter neuer Adresse wieder, Planstand bleibt ohne Verbindung lesbar', () async {
    final pcOrdner = Directory(p.join(tmp.path, 'pc'))..createSync();
    final handy = Directory(p.join(tmp.path, 'handy'))..createSync();
    await OrdnerSpeicher(pcOrdner.path).schreiben(planstandPfad, utf8.encode('{"projekt":"Wohnhaus"}'));
    final dienst = PcDienst(ordner: () => pcOrdner.path, code: () => '654321', auskunft: () => {'name': 'WERKSTATT', 'projekt': 'Wohnhaus'});
    await dienst.starten(port: 0);
    final e = await MobilEinstellungen.laden(ordner: handy);
    // gemerkte Adresse stimmt nicht mehr (hier: ein Port, auf dem nichts läuft)
    e.verbindung = {'art': 'pc', 'adresse': '127.0.0.1:9', 'code': '654321', 'pc_name': 'WERKSTATT'};
    var suchen = 0;
    final ordner = FernOrdner(e, handy, suche: () async {
      suchen++;
      return dienst.laeuft ? [(adresse: '127.0.0.1:${dienst.port}', name: 'WERKSTATT', projekt: 'Wohnhaus')] : <GefundenerPc>[];
    });
    expect(await ordner.name(), 'WERKSTATT');
    expect(utf8.decode((await ordner.lesen(planstandPfad))!), contains('Wohnhaus'));
    expect(suchen, 1);
    expect(e.verbindung['adresse'], '127.0.0.1:${dienst.port}');
    expect((await MobilEinstellungen.laden(ordner: handy)).verbindung['adresse'], e.verbindung['adresse']);

    // Erfassung aus dem Puffer landet beim PC.
    final puffer = await Puffer.laden(basis: handy);
    puffer.ablegen({'art': 'notiz', 'text': 'Test'}, foto: [1, 2]);
    expect(await puffer.uebertragen(ordner), 1);
    expect(Directory(p.join(pcOrdner.path, 'eingang')).listSync().length, 2);

    // PC aus: Erfassung bleibt im Puffer, Planstand kommt aus der Kopie auf dem Gerät.
    await dienst.stoppen();
    puffer.ablegen({'art': 'notiz', 'text': 'später'});
    expect(await puffer.uebertragen(ordner), 0);
    expect(puffer.wartend.length, 1);
    expect(utf8.decode((await ordner.lesen(planstandPfad))!), contains('Wohnhaus'));
    expect(ordner.fehler, isNotNull);
  });

  test('Speichereinstellung: Vorgaben und Cloud-Speicher je Projekt', () {
    final leer = SpeicherEinstellung();
    expect(leer.art, 'pc');
    expect(leer.dienst, isTrue);
    expect(leer.port, bauspurPort);
    expect(leer.fern('Wohnhaus'), isNull);
    final cloud = SpeicherEinstellung({'art': 'cloud', 'url': 'https://beispiel.de/dav/BauSpur'});
    expect(cloud.fern('Wohnhaus')!.bezeichnung, 'beispiel.de › Wohnhaus');
    expect(neuerCode().length, 6);
  });
}
