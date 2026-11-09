import 'dart:convert';
import 'dart:io';

import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/ui/installation/heizkreise_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Anbindeleitungen gebündelt: je Kreis VL+RL, rechtwinklig, Zuleitung gesetzt, erneut zeichnen ersetzt', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_bd_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'B');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    // Raum 4 × 3 m, rechts davon Flur mit dem Verteiler; Tür in der rechten Wand
    final ecken = [(0, 0), (4000, 0), (4000, 3000), (0, 3000)];
    String? rechts;
    for (var i = 0; i < 4; i++) {
      final id = store.wandAnlegen(geschossId: g, x1: ecken[i].$1, y1: ecken[i].$2, x2: ecken[(i + 1) % 4].$1, y2: ecken[(i + 1) % 4].$2, dicke: 175);
      if (ecken[i].$1 == 4000 && ecken[(i + 1) % 4].$1 == 4000) rechts = id;
    }
    store.oeffnungAnlegen(wandId: rechts!, art: OeffnungsArt.tuer, abstand: 1000, breite: 885, hoehe: 2010);
    Objekttyp typ(String k) => store.objekttypen().firstWhere((t) => t.kuerzel == k);
    final hv = store.objektAnlegen(geschossId: g, typ: typ('HV'), punkte: const [Punkt(6000, 500)]);
    final k1 = store.objektAnlegen(geschossId: g, typ: typ('HK'), punkte: const [Punkt(100, 100), Punkt(1900, 100), Punkt(1900, 2900), Punkt(100, 2900)]);
    final k2 = store.objektAnlegen(geschossId: g, typ: typ('HK'), punkte: const [Punkt(2100, 100), Punkt(3900, 100), Punkt(3900, 2900), Punkt(2100, 2900)]);
    for (final k in [k1, k2]) {
      store.objektAendern(k, {'eigenschaften': jsonEncode({'zugang': 0.1})});
    }
    final objekte = store.objekte(g);
    final kreise = objekte.where((o) => o.id == k1 || o.id == k2).toList();
    final v = objekte.firstWhere((o) => o.id == hv);
    expect(anbindeleitungenBuendeln(store, g, kreise, v), 4);
    final hr = typ('HR');
    var leitungen = store.objekte(g).where((o) => o.typId == hr.id).toList();
    expect(leitungen.length, 4);
    for (final l in leitungen) {
      for (var i = 0; i + 1 < l.punkte.length; i++) {
        final a = l.punkte[i], b = l.punkte[i + 1];
        expect((a.x - b.x).abs() < 1 || (a.y - b.y).abs() < 1, isTrue, reason: 'rechtwinklig');
      }
    }
    expect(store.objekte(g).firstWhere((o) => o.id == k1).eigenschaften['zuleitung_mm'], greaterThan(1000));
    // erneut: ersetzt statt verdoppelt
    anbindeleitungenBuendeln(store, g, kreise, v);
    leitungen = store.objekte(g).where((o) => o.typId == hr.id).toList();
    expect(leitungen.length, 4);
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });
}
