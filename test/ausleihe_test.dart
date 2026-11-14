import 'dart:io';

import 'package:bauspur/core/ipad_austausch.dart';
import 'package:bauspur/core/speicher.dart';
import 'package:bauspur/core/zip_schreiben.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Ausleihe: PC gesperrt, zweites iPad abgewiesen, Rückgabe mit neuen Dateien, PC wieder frei', () async {
    final tmp = Directory.systemTemp.createTempSync('bauspur_ausleihe_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Haus');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    store.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 4000, y2: 0, dicke: 240);
    final state = AppState(AppSettings.inDatei(File(p.join(tmp.path, 'e.json'))))..store = store;
    expect(await state.dienst.starten(port: 0), isTrue);
    addTearDown(state.dienst.stoppen);
    final pc = PcSpeicher('127.0.0.1:${state.dienst.port}', code: state.speicher.code);

    final zip = await pc.projektAusleihen('ipad-1', 'iPad');
    expect(store.nurLesen, isTrue);
    expect(() => store.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 0, y2: 3000, dicke: 240), throwsA(anything), reason: 'PC ist gesperrt');
    await expectLater(pc.projektAusleihen('ipad-2', 'anderes iPad'), throwsA(isA<StateError>()));

    // auf dem „iPad“: entpacken, ändern, Foto dazu, zurückgeben
    final ipad = Directory(p.join(tmp.path, 'ipad', 'Haus'))..createSync(recursive: true);
    projektEntpacken(zip, ipad.path);
    final seit = DateTime.now().subtract(const Duration(seconds: 2));
    final kopie = ProjectStore.oeffnen(ipad.path);
    kopie.wandAnlegen(geschossId: g, x1: 4000, y1: 0, x2: 4000, y2: 3000, dicke: 240);
    try {
      kopie.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    kopie.schliessen();
    File(p.join(ipad.path, 'medien', 'ipad_foto.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    final rueck = ordnerPacken(ipad.path, nach: seit, immer: {datenbankDatei}, aus: {'backup', 'projekt.lock', ausleiheDatei});
    // falsches Gerät wird abgewiesen
    await expectLater(pc.projektZurueckgeben('ipad-2', rueck), throwsA(isA<StateError>()));
    await pc.projektZurueckgeben('ipad-1', rueck);

    final neu = state.store!;
    expect(neu.nurLesen, isFalse);
    expect(neu.waende(g).length, 2, reason: 'Änderung vom iPad übernommen');
    expect(File(p.join(neu.ordner, 'medien', 'ipad_foto.jpg')).existsSync(), isTrue, reason: 'Foto vom iPad kam mit');
    expect(Ausleihe.lesen(neu.ordner), isNull);
    expect(neu.sicherungen(), isNotEmpty);
    neu.wandAnlegen(geschossId: g, x1: 0, y1: 3000, x2: 4000, y2: 3000, dicke: 240); // wieder frei
    neu.schliessen();
  });

  test('ZIP-Schreiber und -Leser passen zusammen', () {
    final z = ZipSchreiber()
      ..hinzu('a.txt', [104, 105])
      ..hinzu('ordner/b.bin', List.generate(1000, (i) => i % 256));
    final daten = z.fertig();
    final tmp = Directory.systemTemp.createTempSync('bauspur_zip_');
    expect(projektEntpacken(daten, tmp.path), 2);
    expect(File(p.join(tmp.path, 'ordner', 'b.bin')).lengthSync(), 1000);
    tmp.deleteSync(recursive: true);
  });
}
