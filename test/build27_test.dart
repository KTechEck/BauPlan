import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bauspur/core/exif.dart';
import 'package:bauspur/core/leitung_wand.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/schrank_models.dart';
import 'package:bauspur/ui/bauteile/gewaehrleistung_dialog.dart';
import 'package:bauspur/ui/export/akte.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kleinstes JPEG mit EXIF-Block (II, IFD0 → ExifIFD → DateTimeOriginal).
List<int> jpegMitExif(String datum) {
  final dt = [...ascii.encode(datum), 0]; // 20 Byte
  final tiff = BytesBuilder();
  void u16(int v) => tiff.add([v & 0xFF, v >> 8]);
  void u32(int v) => tiff.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  tiff.add(ascii.encode('II'));
  u16(42);
  u32(8); // IFD0 bei 8
  // IFD0: 1 Eintrag (ExifIFD-Zeiger)
  u16(1);
  u16(0x8769);
  u16(4);
  u32(1);
  u32(26); // ExifIFD bei 26
  u32(0);
  // ExifIFD bei 26: 1 Eintrag DateTimeOriginal
  u16(1);
  u16(0x9003);
  u16(2);
  u32(dt.length);
  u32(44); // Text bei 44
  u32(0);
  tiff.add(dt);
  final t = tiff.toBytes();
  final app1 = [...ascii.encode('Exif'), 0, 0, ...t];
  final len = app1.length + 2;
  return [0xFF, 0xD8, 0xFF, 0xE1, len >> 8, len & 0xFF, ...app1, 0xFF, 0xD9];
}

void main() {
  test('EXIF-Aufnahmedatum', () {
    expect(exifAufnahme(jpegMitExif('2025:06:14 09:30:12')), DateTime(2025, 6, 14, 9, 30, 12));
    expect(exifAufnahme([0xFF, 0xD8, 0xFF, 0xD9]), isNull);
    expect(exifAufnahme([1, 2, 3]), isNull);
  });

  test('Bohrschutz: Sperrzonen und DIN-Installationszonen', () {
    final z = bohrSperrzonen(const [WandTeil(id: 'a', text: 'NYM', x: 1000, z: 300, x2: 3000, z2: 300, breite: 20)], sicherheit: 100);
    expect(z.single.$1, 890);
    expect(z.single.$4, 410);
    final d = dinInstallationszonen(laenge: 4000, ffb: 0, decke: 2500, oeffnungen: const [(1000, 1900)]);
    expect(d.length, 6);
    expect(d.first, (0, 2050, 4000, 2350));
  });

  test('Mängel, Etiketten, Raumbuch, Fotobericht, Hausakte, Gewährleistung', () async {
    final tmp = Directory.systemTemp.createTempSync('bauspur_b27_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Akte');
    try {
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      for (final (x1, y1, x2, y2) in [(0, 0, 4000, 0), (4000, 0, 4000, 3000), (4000, 3000, 0, 3000), (0, 3000, 0, 0)]) {
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
      }
      final r = store.raumAnlegen(geschossId: g, name: 'Küche', kuerzel: 'KU', flaeche: store.flaechenErkennen(g).single);
      final id = store.aufgabeAnlegen(titel: 'Fliese gesprungen', art: 'mangel', raumId: r);
      final a = store.aufgaben().firstWhere((x) => x.id == id);
      expect(a.art, 'mangel');
      final typ = {for (final t in store.objekttypen()) t.kuerzel: t};
      final nd = store.objektAnlegen(geschossId: g, typ: typ['ND']!, raumId: r, punkte: const [Punkt(500, 500)]);
      store.objektAnlegen(geschossId: g, typ: typ['LT']!, punkte: const [Punkt(0, 0), Punkt(1000, 0)]);
      final s = store.schrankAnlegen(name: 'Netzwerk', kennzeichen: 'NW1', art: SchrankArt.netzwerk);
      store.schrankAendern(s, {'eigenschaften': jsonEncode({'patch': {'7': nd}})});
      final uv = store.schrankAnlegen(name: 'UV', kennzeichen: 'UV1');
      final ls = store.geraetAnlegen(schrankId: uv, reihe: 0, position: 0, art: GeraeteArt.ls, kennzeichen: '-F1', nennstrom: 16, charakteristik: 'B');
      store.stromkreisAnlegen(schrankId: uv, nummer: '1', bezeichnung: 'Steckdosen Küche', schutzId: ls);
      final et = etikettenSammeln(store, {'kabel', 'dosen', 'sicherungen'});
      expect(et.where((e) => e.art == 'Netzwerkdose').single.zeile1, 'NW1-7');
      expect(et.where((e) => e.art == 'Sicherung').single.zeile1, '=UV1-F1  B16');
      expect(et.any((e) => e.art == 'Kabel'), isTrue);
      final (pdf, csv) = await etikettenSpeichern(store, et, 'Band 12 mm (z. B. P-touch)');
      expect(File(pdf).lengthSync(), greaterThan(500));
      expect(File(csv).readAsStringSync(), contains('Steckdosen Küche'));
      final rb = await raumbuchPdf(store);
      expect(File(rb).existsSync(), isTrue);
      final fb = await fotoberichtPdf(store);
      expect(File(fb).existsSync(), isTrue);
      store.einstellungSetzen('gewaehrleistung', [
        {'id': 'x', 'produkt': 'Wärmepumpe', 'hersteller': 'H', 'haendler': 'Hd', 'kauf': '2024-12-01', 'jahre': 2},
      ]);
      expect(gewaehrleistungBaldAus(store, heute: DateTime(2026, 11, 1)).single.produkt, 'Wärmepumpe');
      expect(gewaehrleistungBaldAus(store, heute: DateTime(2025, 6, 1)), isEmpty);
      final akte = await hausakteErstellen(store, hausdoku: false);
      expect(File('$akte/index.html').readAsStringSync(), contains('Raumbuch.pdf'));
      expect(File('$akte.zip').lengthSync(), greaterThan(1000));
      expect(File('$akte/02_Elektro/Stromlaufplan_UV1.pdf').existsSync(), isTrue);
      expect(File('$akte/06_Einkauf_Gewaehrleistung/Gewaehrleistung.csv').existsSync(), isTrue);
    } finally {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    }
  });
}
