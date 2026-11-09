import 'dart:io';

import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/ui/fotos/foto_markieren_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Markierungen und Panorama am Foto', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_fm_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'F');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final bild = File('${tmp.path}/bild.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    final id = store.fotoImportieren(bild.path, geschossId: g);
    expect(store.fotoMarkierungen(id), isEmpty);
    final alt = store.fotoMarkierungenSetzen(id, [
      {'art': 'pfeil', 'a': [0.1, 0.1], 'b': [0.5, 0.5], 'farbe': 0xFFE03131, 'text': ''},
      {'art': 'mass', 'a': [0.2, 0.8], 'b': [0.8, 0.8], 'farbe': 0xFF1C7ED6, 'text': '1250 mm'},
    ]);
    expect(alt, isEmpty);
    expect(store.fotoMarkierungen(id).last['text'], '1250 mm');
    expect(store.fotoIstPanorama(id), isFalse);
    store.fotoPanoramaSetzen(id, true);
    expect(store.fotoIstPanorama(id), isTrue);
    expect(siehtNachPanoramaAus(6000, 3000), isTrue);
    expect(siehtNachPanoramaAus(4000, 3000), isFalse);
  });
}
