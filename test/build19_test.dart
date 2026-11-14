import 'dart:io';
import 'dart:typed_data';

import 'package:bauspur/core/bauelemente.dart';
import 'package:bauspur/core/inhaltspaket.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/export/wohnflaeche_page.dart';
import 'package:bauspur/ui/zwei_finger.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Inhaltspaket: Bibliothek hin und zurück, Vergleich neu/gleich/anders', () {
    final a = Bauelement(id: 'a', kategorie: BauelementKategorie.kabelkanal, name: 'Kanal 40×40', daten: const {'breite': 40, 'tiefe': 40});
    final b = Bauelement(id: 'b', kategorie: BauelementKategorie.elektro, name: 'Steckdose', daten: const {'einbauhoehe': 300});
    final text = bibliothekPaket([a, b], name: 'Test', datenblaetter: {'b_blatt.pdf': Uint8List.fromList([1, 2, 3])});
    final p = bibliothekPaketLesen(text);
    expect(p.name, 'Test');
    expect(p.elemente.map((e) => e.id), ['a', 'b']);
    expect(p.datenblaetter['b_blatt.pdf'], [1, 2, 3]);
    final v = paketVergleichen(p.elemente, [a, b.mit(name: 'Steckdose alt')]);
    expect(v.gleich.single.id, 'a');
    expect(v.anders.single.id, 'b');
    expect(v.neu, isEmpty);
    expect(() => bibliothekPaketLesen('{"format":"x"}'), throwsFormatException);
  });

  test('Wohnfläche: Zubehörräume zählen nicht, Balkon anteilig', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_wfl_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'W');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    for (final (x0, x1) in [(0, 4000), (4000, 8000)]) {
      final e = [(x0, 0), (x1, 0), (x1, 3000), (x0, 3000)];
      for (var i = 0; i < 4; i++) {
        store.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 100);
      }
    }
    final fl = store.flaechenErkennen(g)..sort((a, b) => a.innenpunkt.x.compareTo(b.innenpunkt.x));
    store.raumAnlegen(geschossId: g, name: 'Wohnen', kuerzel: 'WO', flaeche: fl.first);
    store.raumAnlegen(geschossId: g, name: 'Heizraum', kuerzel: 'HR', flaeche: fl.last);
    final s = AppState(AppSettings.inDatei(File('${tmp.path}/e.json')))..store = store;
    final z = wohnflaechen(s);
    final wohnen = z.firstWhere((x) => x.raum.name == 'Wohnen'), heiz = z.firstWhere((x) => x.raum.name == 'Heizraum');
    expect(wohnen.angerechnet, closeTo(wohnen.grund, 1e-9));
    expect(heiz.zaehlt, isFalse);
    expect(heiz.angerechnet, 0);
    expect(zubehoerraum('Kellerraum 2'), isTrue);
    expect(RaumArt.balkon.label, 'Balkon');
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Touch: zwei Finger zoomen, Tippen kommt beim Loslassen, Stift schaltet Finger aufs Schieben', () {
    final z = ZweiFinger();
    const maus = PointerDownEvent(pointer: 9, kind: PointerDeviceKind.mouse, position: Offset(5, 5));
    expect(z.runter(maus), isFalse);
    expect(z.runter(const PointerDownEvent(pointer: 1, kind: PointerDeviceKind.touch, position: Offset(100, 100))), isTrue);
    var h = z.hoch(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.touch, position: Offset(100, 100)));
    expect(h.wartend?.pointer, 1, reason: 'Tippen wird beim Loslassen ausgelöst');
    z.runter(const PointerDownEvent(pointer: 2, kind: PointerDeviceKind.touch, position: Offset(100, 100)));
    z.runter(const PointerDownEvent(pointer: 3, kind: PointerDeviceKind.touch, position: Offset(200, 100)));
    final g = z.zweiFinger(const PointerMoveEvent(pointer: 3, kind: PointerDeviceKind.touch, position: Offset(300, 100)));
    expect(g!.faktor, closeTo(2, 1e-9));
    h = z.hoch(const PointerUpEvent(pointer: 3, kind: PointerDeviceKind.touch));
    expect(h.geste, isTrue);
    z.hoch(const PointerUpEvent(pointer: 2, kind: PointerDeviceKind.touch));
    expect(z.runter(const PointerDownEvent(pointer: 4, kind: PointerDeviceKind.stylus, position: Offset(10, 10))), isFalse);
    z.runter(const PointerDownEvent(pointer: 5, kind: PointerDeviceKind.touch, position: Offset(50, 50)));
    final s = z.zweiFinger(const PointerMoveEvent(pointer: 5, kind: PointerDeviceKind.touch, position: Offset(70, 60)));
    expect(s!.verschiebung, const Offset(20, 10));
  });
}
