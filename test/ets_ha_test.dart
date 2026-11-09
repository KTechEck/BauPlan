import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bauspur/core/ets_projekt.dart';
import 'package:bauspur/core/ha_live.dart';
import 'package:bauspur/core/knx.dart';
import 'package:bauspur/core/zip_lesen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimaler ZIP-Schreiber für die Tests (Deflate oder gespeichert).
Uint8List zipBauen(Map<String, List<int>> dateien, {bool packen = true, Set<String> verschluesselt = const {}}) {
  final out = BytesBuilder();
  final zentral = BytesBuilder();
  var n = 0;
  void u16(BytesBuilder b, int v) => b.add([v & 255, (v >> 8) & 255]);
  void u32(BytesBuilder b, int v) => b.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  for (final e in dateien.entries) {
    final name = utf8.encode(e.key);
    final daten = packen ? ZLibEncoder(raw: true).convert(e.value) : e.value;
    final flags = verschluesselt.contains(e.key) ? 1 : 0;
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, flags);
    u16(out, packen ? 8 : 0);
    u16(out, 0);
    u16(out, 0);
    u32(out, 0);
    u32(out, daten.length);
    u32(out, e.value.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(daten);
    u32(zentral, 0x02014b50);
    u16(zentral, 20);
    u16(zentral, 20);
    u16(zentral, flags);
    u16(zentral, packen ? 8 : 0);
    u16(zentral, 0);
    u16(zentral, 0);
    u32(zentral, 0);
    u32(zentral, daten.length);
    u32(zentral, e.value.length);
    u16(zentral, name.length);
    u16(zentral, 0);
    u16(zentral, 0);
    u16(zentral, 0);
    u16(zentral, 0);
    u32(zentral, 0);
    u32(zentral, offset);
    zentral.add(name);
    n++;
  }
  final zOffset = out.length, z = zentral.toBytes();
  out.add(z);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, n);
  u16(out, n);
  u32(out, z.length);
  u32(out, zOffset);
  u16(out, 0);
  return out.toBytes();
}

const _xml = '''<?xml version="1.0" encoding="utf-8"?>
<KNX xmlns="http://knx.org/xml/project/21">
  <Project Id="P-0123">
    <Installations>
      <Installation Name="">
        <Topology>
          <Area Id="A1" Address="1" Name="Haus">
            <Line Id="L1" Address="1" Name="Linie 1">
              <DeviceInstance Id="D1" Address="10" Name="Schaltaktor 8fach &amp; Strom" />
              <DeviceInstance Id="D2" Address="11" Name="Dimmaktor" />
            </Line>
          </Area>
        </Topology>
        <GroupAddresses>
          <GroupRanges>
            <GroupRange Name="Licht" RangeStart="2048" RangeEnd="4095">
              <GroupRange Name="Schalten" RangeStart="2048" RangeEnd="2303">
                <GroupAddress Id="G1" Address="2048" Name="Küche Licht schalten" DatapointType="DPST-1-1" />
                <GroupAddress Id="G2" Address="2049" Name="Bad Licht" DatapointType="DPST-1-1" />
              </GroupRange>
              <GroupRange Name="Status" RangeStart="2304" RangeEnd="2559">
                <GroupAddress Id="G3" Address="2304" Name="Küche Licht Status" DatapointType="DPST-1-1" />
              </GroupRange>
            </GroupRange>
          </GroupRanges>
        </GroupAddresses>
      </Installation>
    </Installations>
  </Project>
</KNX>''';

void main() {
  group('ZIP und ETS', () {
    test('ZIP lesen, gepackt und gespeichert', () {
      for (final packen in [true, false]) {
        final z = ZipArchiv(zipBauen({'a.txt': utf8.encode('Hallo Ä'), 'b/c.txt': utf8.encode('x' * 1000)}, packen: packen));
        expect(z.namen, containsAll(['a.txt', 'b/c.txt']));
        expect(z.text('a.txt'), 'Hallo Ä');
        expect(z.text('b/c.txt')!.length, 1000);
        expect(z.lesen('fehlt'), isNull);
      }
      expect(() => ZipArchiv(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    });

    test('knxproj: Gruppenadressen, Bereichsnamen, Geräte mit PA', () {
      final daten = zipBauen({
        'knx_master.xml': utf8.encode('<KNX/>'),
        'P-0123/project.xml': utf8.encode('<KNX><Project><ProjectInformation Name="Haus Künsztler" /></Project></KNX>'),
        'P-0123/0.xml': utf8.encode(_xml),
      });
      final p = knxprojLesen(daten);
      expect(p.name, 'Haus Künsztler');
      expect([for (final g in p.gas) g.adresse], ['1/0/0', '1/0/1', '1/1/0']);
      expect(p.gas.first.name, 'Küche Licht schalten');
      expect(p.hauptNamen[1], 'Licht');
      expect(p.mittelNamen['1/1'], 'Status');
      expect([for (final g in p.geraete) g.pa], ['1.1.10', '1.1.11']);
      expect(p.geraete.first.name, 'Schaltaktor 8fach & Strom');
    });

    test('knxproj: eingebettetes und passwortgeschütztes Projekt', () {
      final innen = zipBauen({'0.xml': utf8.encode(_xml)});
      expect(knxprojLesen(zipBauen({'P-0123.zip': innen}, packen: false)).gas.length, 3);
      final geschuetzt = zipBauen({'P-0123.zip': innen}, packen: false, verschluesselt: {'P-0123.zip'});
      expect(() => knxprojLesen(geschuetzt), throwsA(isA<EtsFehler>().having((e) => e.meldung, 'meldung', contains('Passwort'))));
      expect(() => knxprojLesen(zipBauen({'x.txt': [1]})), throwsA(isA<EtsFehler>()));
    });

    test('ETS-CSV lesen (Komma und Semikolon)', () {
      const csv = '"Group name","Address","Central","Unfiltered","Description","DatapointType","Security"\n'
          '"Licht","1/-/-","","","","","Auto"\n'
          '"Schalten","1/0/-","","","","","Auto"\n'
          '"Küche Licht schalten","1/0/0","","","","DPST-1-1","Auto"\n'
          '"Bad ""Spiegel""","1/0/5","","","","DPST-1-1","Auto"\n';
      final p = etsCsvLesen(csv);
      expect(p.gas.length, 2);
      expect(p.gas.last.name, 'Bad "Spiegel"');
      expect(p.hauptNamen[1], 'Licht');
      final p2 = etsCsvLesen(etsText(Uint8List.fromList(latin1.encode('Name;Adresse;DPT\nKüche;2/1/3;DPST-5-1\n'))));
      expect(p2.gas.single.adresse, '2/1/3');
      expect(p2.gas.single.name, 'Küche');
      // Eigener Export lässt sich wieder einlesen.
      final eigen = [Gruppenadresse(id: 'a', haupt: 3, mittel: 2, unter: 1, name: 'Test', funktion: 'temperatur')];
      expect(etsCsvLesen(etsCsv(eigen)).gas.single.dpt, 'DPST-9-1');
    });

    test('Abgleich und Übernahme', () {
      final bauspur = [
        Gruppenadresse(id: 'a', haupt: 1, mittel: 0, unter: 0, name: 'Küche Licht schalten', objekte: ['o1']),
        Gruppenadresse(id: 'b', haupt: 1, mittel: 0, unter: 1, name: 'Bad Licht schalten'),
        Gruppenadresse(id: 'c', haupt: 1, mittel: 3, unter: 0, name: 'Flur Helligkeit', funktion: 'helligkeit'),
      ];
      final ets = etsXmlLesen(_xml).gas;
      final ab = gaAbgleich(bauspur, ets);
      expect({for (final z in ab) z.adresse: z.art}, {
        '1/0/0': AbgleichArt.gleich,
        '1/0/1': AbgleichArt.nameAnders,
        '1/1/0': AbgleichArt.nurEts,
        '1/3/0': AbgleichArt.nurBauspur,
      });
      var n = 0;
      final neu = etsUebernehmen(bauspur, ab, namenUebernehmen: true, neueId: () => 'n${n++}');
      expect(neu.length, 4);
      expect(neu.firstWhere((g) => g.adresse == '1/0/1').name, 'Bad Licht');
      expect(neu.firstWhere((g) => g.adresse == '1/1/0').funktion, 'status');
      expect(neu.firstWhere((g) => g.adresse == '1/0/0').objekte, ['o1']);
      expect(gaAbgleich(neu, ets).where((z) => z.art != AbgleichArt.gleich).single.art, AbgleichArt.nurBauspur);
      // DPT-Abweichung
      final d = gaAbgleich([Gruppenadresse(id: 'x', haupt: 1, mittel: 0, unter: 0, name: 'Küche Licht schalten', funktion: 'temperatur')], ets);
      expect(d.first.art, AbgleichArt.dptAnders);
      expect(dptKurz('DPST-9-1'), '9.001');
      final pa = paAbgleich({'1.1.10': '-K1', '1.1.20': '-K2'}, etsXmlLesen(_xml).geraete);
      expect(pa.gleich, ['1.1.10']);
      expect(pa.nurBauspur, ['1.1.20']);
      expect([for (final g in pa.nurEts) g.pa], ['1.1.11']);
    });
  });

  group('Home Assistant live', () {
    test('Sperren: Token, Heimnetz, Fremdzugriff nur mit https', () {
      expect(const HaEinstellung().sperre, contains('Token'));
      expect(const HaEinstellung(token: 't').sperre, isNull);
      expect(const HaEinstellung(adresse: 'https://abc.ui.nabu.casa', token: 't').sperre, contains('Heimnetz'));
      expect(const HaEinstellung(adresse: 'http://abc.example.org', token: 't', fremdzugriff: true).sperre, contains('https'));
      expect(const HaEinstellung(adresse: 'https://abc.ui.nabu.casa', token: 't', fremdzugriff: true).sperre, isNull);
      final e = HaEinstellung.ausJson(const HaEinstellung(adresse: 'http://192.168.1.5:8123', token: 'x').toJson());
      expect(e.lokal, isTrue);
      expect(e.token, 'x');
    });

    test('Abgleich und Vorschlag', () {
      const ha = [
        HaEntitaet(id: 'light.kueche_decke', zustand: 'on', name: 'Küche Decke'),
        HaEntitaet(id: 'light.bad_spiegel', zustand: 'unavailable'),
        HaEntitaet(id: 'switch.flur_steckdose', zustand: 'off'),
        HaEntitaet(id: 'sun.sun', zustand: 'above_horizon'),
      ];
      final z = <HaZuordnung>[
        (entity: 'light.kueche_decke', objektId: 'o1', objekt: 'LE-01', rolle: 'Objekt'),
        (entity: 'light.bad_spiegel', objektId: 'o2', objekt: 'LE-02', rolle: 'Objekt'),
        (entity: 'switch.flur_steckdose_links', objektId: 'o3', objekt: 'SD-01', rolle: 'KNX-Vorschlag'),
      ];
      final a = haAbgleichen(z, ha);
      expect(a.gefunden.single.$2.zustandText, 'an');
      expect(a.nichtErreichbar.single.$1.objekt, 'LE-02');
      expect(a.fehlt.single.objekt, 'SD-01');
      expect([for (final e in a.unzugeordnet) e.id], ['switch.flur_steckdose']);
      expect(haVorschlag('switch.flur_steckdose_links', a.unzugeordnet)?.id, 'switch.flur_steckdose');
      expect(haVorschlag('light.wohnen', a.unzugeordnet), isNull);
    });

    test('Verbindung gegen einen lokalen Testserver', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        if (r.headers.value('authorization') != 'Bearer geheim') {
          r.response.statusCode = 401;
        } else if (r.uri.path == '/api/config') {
          r.response.write(jsonEncode({'location_name': 'Zuhause', 'version': '2026.11.0'}));
        } else {
          r.response.write(jsonEncode([
            {'entity_id': 'sensor.bad_temp', 'state': '21.5', 'attributes': {'unit_of_measurement': '°C', 'friendly_name': 'Bad'}},
            {'entity_id': 'light.a', 'state': 'off', 'attributes': {}},
          ]));
        }
        r.response.close();
      });
      final v = HaVerbindung(HaEinstellung(adresse: 'http://127.0.0.1:${server.port}', token: 'geheim'));
      expect(await v.pruefen(), 'Zuhause (Version 2026.11.0)');
      final z = await v.zustaende();
      expect(z.map((e) => e.id), ['light.a', 'sensor.bad_temp']);
      expect(z.last.zustandText, '21.5 °C');
      final falsch = HaVerbindung(HaEinstellung(adresse: 'http://127.0.0.1:${server.port}', token: 'falsch'));
      await expectLater(falsch.zustaende(), throwsA(isA<HttpException>()));
      v.schliessen();
      falsch.schliessen();
      await server.close(force: true);
    });
  });
}
