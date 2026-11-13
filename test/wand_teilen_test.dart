import 'package:bauspur/core/aufmass.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/austausch.dart';
import 'package:bauspur/core/geschossuebergreifend.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Angrenzender Raum: gemeinsame Wand einmal, durchgehende Wand geteilt, Innenmaße je Raum', () {
    final tmp = Directory.systemTemp.createTempSync('pr');
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'P');
    final g = s.geschosse(s.gebaeude().single.id).single.id;
    void rechteck(int x0, int y0, int x1, int y1) {
      final e = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)];
      for (var i = 0; i < 4; i++) {
        s.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 240);
      }
    }
    rechteck(0, 0, 4000, 3000);
    final rechte = s.waende(g)[1];
    s.oeffnungAnlegen(wandId: rechte.id, art: OeffnungsArt.tuer, abstand: 1200, breite: 900, hoehe: 2010);
    rechteck(4000, 1000, 6000, 2500);
    expect(s.waendeAnAnschluessenTeilen(g), greaterThan(0));
    final w = s.waende(g);
    expect(w.length, 9); // A: 3 + 3 Stücke an x = 4000, B: 3 (doppelte Wand weg)
    final m = wandMasse(w, const []);
    final mitte = w.firstWhere((x) => x.x1 == 4000 && x.x2 == 4000 && {x.y1, x.y2}.containsAll({1000, 2500}));
    expect({m[mitte.id]!.links.round(), m[mitte.id]!.rechts.round()}, contains(1260)); // Raum B innen
    expect(s.alleOeffnungen().single.wandId, mitte.id);
    s.schliessen();
  });

  test('Wanddicke ändern: lichtes Innenmaß bleibt, Nachbarwände ziehen mit, Winkel bleiben', () {
    final tmp = Directory.systemTemp.createTempSync('pr');
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'P');
    final g = s.geschosse(s.gebaeude().single.id).single.id;
    const e = [(0, 0), (4000, 0), (4000, 3000), (0, 3000)];
    for (var i = 0; i < 4; i++) {
      s.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 240);
    }
    s.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'B', flaeche: s.flaechenErkennen(g).single);
    final vorher = s.raeume(g).single.flaeche!;
    final oben = s.waende(g).first;
    wandDickeMitInnenmass(s, oben, () => s.wandAendern(oben.id, dicke: 365));
    final w = s.waende(g);
    expect(w.first.y1, closeTo(-62, 1)); // Achse um die halbe Mehrdicke nach außen
    expect(w[1].y1, closeTo(-62, 1)); // rechte Wand verlängert, bleibt senkrecht
    expect(w[1].x1, w[1].x2);
    expect(s.flaechenErkennen(g).single.flaeche, closeTo(vorher, 2000));
    s.schliessen();
  });

  test('Steigleitung über Geschosse, Treppe mit Podest, Kamin-Typ', () {
    final tmp = Directory.systemTemp.createTempSync('pr');
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'P');
    final geb = s.gebaeude().single.id;
    final eg = s.geschosse(geb).single.id;
    final og = s.geschossAnlegen(gebaeudeId: geb, name: 'Obergeschoss', kuerzel: 'OG', rfb: 0, ffb: 0, rohdecke: 2600, meterriss: 1000);
    final typen = s.objekttypen();
    expect(typen.where((t) => t.kuerzel == 'SR').length, 3);
    expect(typen.any((t) => t.kuerzel == 'KM'), isTrue);
    final sr = typen.firstWhere((t) => t.kuerzel == 'SR');
    final id = s.objektAnlegen(geschossId: eg, typ: sr, punkte: [punktAus([500, 500])]);
    s.objektAendern(id, {'eigenschaften': '{"bis_geschoss":"$og"}'});
    expect(durchgehendeObjekte(s, og).single.id, id);
    final tr = typen.firstWhere((t) => t.kuerzel == 'TR');
    final t = s.objektAnlegen(geschossId: eg, typ: tr, punkte: [punktAus([0, 0]), punktAus([3500, 0])]);
    s.objektAendern(t, {'eigenschaften': '{"hoehe":2800,"steigungen":16,"podest_nach":8,"podest_tiefe":1000}'});
    final b = treppeBerechnen(s.objekte(eg).firstWhere((o) => o.id == t));
    expect(b.steigung, 175);
    expect(b.auftritt, closeTo(2500 / 14, 0.1));
    s.schliessen();
  });
}
