import 'dart:io';

import 'package:bauspur/core/ipad_austausch.dart';
import 'package:bauspur/core/speicher.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/sync.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/state/live_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Live-Abgleich: PC bleibt frei, Änderungen beidseitig, Datei, Konflikt sichtbar', () async {
    final tmp = Directory.systemTemp.createTempSync('bauspur_live_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'Haus');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final w1 = store.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 4000, y2: 0, dicke: 240);
    final pcState = AppState(AppSettings.inDatei(File(p.join(tmp.path, 'e.json'))))..store = store;
    expect(await pcState.dienst.starten(port: 0), isTrue);
    addTearDown(pcState.dienst.stoppen);
    final pc = PcSpeicher('127.0.0.1:${pcState.dienst.port}', code: pcState.speicher.code);

    // iPad holt live – PC bleibt beschreibbar
    final (zip, stand, zeit) = await pc.projektLive('ipad-1');
    expect(store.nurLesen, isFalse);
    final ordner = Directory(p.join(tmp.path, 'ipad', 'Haus'))..createSync(recursive: true);
    projektEntpacken(zip, ordner.path);
    SyncStand(pc: stand, dateienSeit: zeit, eigeneDateienSeit: DateTime.now(), adresse: '127.0.0.1:${pcState.dienst.port}', code: pcState.speicher.code, geraet: 'ipad-1').schreiben(ordner.path);
    final kopie = ProjectStore.oeffnen(ordner.path);
    final ipadState = AppState(AppSettings.inDatei(File(p.join(tmp.path, 'i.json'))), touch: true)..store = kopie;
    final live = LiveSync(ipadState, SyncStand.lesen(ordner.path)!)
      ..starten()
      ..stoppen(); // im Test von Hand abgleichen
    await live.abgleichen();
    expect(live.zustand.value.verbunden, isTrue, reason: live.zustand.value.fehler);

    // gleichzeitig: iPad legt Wand an + Einstellung, PC legt Wand an
    final ipadWand = kopie.wandAnlegen(geschossId: g, x1: 4000, y1: 0, x2: 4000, y2: 3000, dicke: 240);
    kopie.einstellungSetzen('test_ipad', 42);
    final pcWand = store.wandAnlegen(geschossId: g, x1: 0, y1: 3000, x2: 4000, y2: 3000, dicke: 175);
    // Foto auf dem iPad
    File(p.join(ordner.path, 'medien', 'ipad_foto.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    await live.abgleichen();
    expect(store.waende(g).map((w) => w.id), containsAll([w1, ipadWand, pcWand]));
    expect(kopie.waende(g).map((w) => w.id), containsAll([w1, ipadWand, pcWand]));
    expect(store.einstellung<num>('test_ipad'), 42);
    expect(File(p.join(store.ordner, 'medien', 'ipad_foto.jpg')).existsSync(), isTrue);

    // Konflikt: beide ändern dieselbe Wand – jüngere gewinnt, die andere ist gespeichert
    store.wandAendern(w1, dicke: 300);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    kopie.wandAendern(w1, dicke: 365);
    await live.abgleichen();
    expect(store.waende(g).firstWhere((w) => w.id == w1).dicke, 365);
    expect(kopie.waende(g).firstWhere((w) => w.id == w1).dicke, 365);
    expect(syncKonflikte(store), hasLength(1));
    expect((syncKonflikte(store).single['verlierer_zeile'] as Map)['dicke_mm'], 300);

    // offline: Änderungen warten
    await pcState.dienst.stoppen();
    kopie.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 0, y2: 3000, dicke: 240);
    await live.abgleichen();
    expect(live.zustand.value.verbunden, isFalse);
    expect(live.zustand.value.wartend, greaterThan(0));
    kopie.schliessen();
    store.schliessen();
  });
}
