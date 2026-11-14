import 'package:bauspur/core/aufmass.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/data/austausch.dart';
import 'package:bauspur/core/geschossuebergreifend.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Angrenzender Raum: Wand bleibt ganz, doppelte Wand weg, je Raum eine Messstrecke', () {
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
    rechteck(4000, 1000, 6000, 2500); // linke Wand liegt auf der rechten Wand von A
    expect(s.doppelteWaendeEntfernen(g), 1);
    final w = s.waende(g);
    expect(w.length, 7);
    final fl = s.flaechenErkennen(g)..sort((a, b) => a.flaeche.compareTo(b.flaeche));
    final b = s.raumAnlegen(geschossId: g, name: 'B', kuerzel: 'B', flaeche: fl.first);
    final a = s.raumAnlegen(geschossId: g, name: 'A', kuerzel: 'A', flaeche: fl.last);
    final mitte = w.firstWhere((x) => x.x1 == 4000 && x.x2 == 4000);
    final st = {...raumStuecke(mitte, true, s.raeume(g)), ...raumStuecke(mitte, false, s.raeume(g))};
    expect(st[b]!.$2 - st[b]!.$1, closeTo(1260, 1)); // B: nur sein Stück
    expect(st[a]!.$2 - st[a]!.$1, closeTo(2760, 1)); // A: Wand läuft durch
    // je Raum genau eine Messstrecke je Seite: A hat 4 Seiten
    var n = 0;
    for (final x in s.waende(g)) {
      for (final l in [true, false]) {
        if (raumStuecke(x, l, s.raeume(g)).containsKey(a)) n++;
      }
    }
    expect(n, 4);
    s.schliessen();
  });

  test('Geteilte Wandstücke werden wieder zu einer Wand', () {
    final tmp = Directory.systemTemp.createTempSync('pr');
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'P');
    final g = s.geschosse(s.gebaeude().single.id).single.id;
    s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 1000, y2: 0, dicke: 240);
    final b = s.wandAnlegen(geschossId: g, x1: 1000, y1: 0, x2: 4000, y2: 0, dicke: 240);
    s.oeffnungAnlegen(wandId: b, art: OeffnungsArt.tuer, abstand: 500, breite: 900, hoehe: 2010);
    expect(s.waendeZusammenfuehren(g), 1);
    final w = s.waende(g).single;
    expect(w.laenge, 4000);
    expect(s.alleOeffnungen().single.abstand, 1500);
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

  test('Wand aus zwei geraden Stücken: eine lichte Länge je Raum, keine Splittermaße', () {
    final tmp = Directory.systemTemp.createTempSync('pr');
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'P');
    final g = s.geschosse(s.gebaeude().single.id).single.id;
    // linke Wand aus zwei Stücken mit unterschiedlichem Zustand (wird nicht zusammengeführt)
    s.wandAnlegen(geschossId: g, x1: 0, y1: 4000, x2: 0, y2: 2500, dicke: 300);
    s.wandAnlegen(geschossId: g, x1: 0, y1: 2500, x2: 0, y2: 0, dicke: 300, zustand: WandZustand.neu);
    s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 3000, y2: 0, dicke: 300);
    s.wandAnlegen(geschossId: g, x1: 3000, y1: 0, x2: 3000, y2: 4000, dicke: 300);
    s.wandAnlegen(geschossId: g, x1: 3000, y1: 4000, x2: 0, y2: 4000, dicke: 300);
    expect(s.waendeZusammenfuehren(g), 0);
    final r = s.raumAnlegen(geschossId: g, name: 'T', kuerzel: 'T', flaeche: s.flaechenErkennen(g).single);
    final m = wandMasse(s.waende(g), s.raeume(g));
    final links = [for (final w in s.waende(g)) if (w.x1 == 0 && w.x2 == 0) m[w.id]!];
    final stuecke = [for (final x in links) ...x.stueckeLinks.entries, for (final x in links) ...x.stueckeRechts.entries].where((e) => e.key == r).toList();
    expect(stuecke.length, 1); // nur einmal beschriftet
    expect(stuecke.single.value.$2 - stuecke.single.value.$1, closeTo(3700, 2)); // 4000 − 2 × 150
    s.schliessen();
  });

  test('Verkleidung je Raum und je Wandseite: Fertigmaß zieht die anstoßenden Wände ab', () {
    final tmp = Directory.systemTemp.createTempSync('pr');
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'P');
    final g = s.geschosse(s.gebaeude().single.id).single.id;
    const e = [(0, 0), (4000, 0), (4000, 3000), (0, 3000)];
    for (var i = 0; i < 4; i++) {
      s.wandAnlegen(geschossId: g, x1: e[i].$1, y1: e[i].$2, x2: e[(i + 1) % 4].$1, y2: e[(i + 1) % 4].$2, dicke: 240);
    }
    final rid = s.raumAnlegen(geschossId: g, name: 'Bad', kuerzel: 'B', flaeche: s.flaechenErkennen(g).single);
    s.raumEigenschaftenSetzen(rid, {'verkleidung': {'art': 'GK auf UK', 'dicke': 62}});
    final w = s.waende(g), r = s.raeume(g).single;
    final mm = wandMasse(w, s.raeume(g));
    final oben = w.first;
    final links = mm[oben.id]!.raumLinks == rid;
    final g0 = mm[oben.id]!.grenzen;
    (int, int) ab() => endAbzuege(w, mm, verkleidungSeiten(s), oben, links, links ? g0.linksA : g0.rechtsA, links ? g0.linksB : g0.rechtsB, r);
    expect(ab(), (62, 62));
    // rechte Wand: Raumseite ohne Verkleidung
    final rechts = w[1];
    verkleidungSeiteSetzen(s, rechts.id, mm[rechts.id]!.raumLinks == rid, {'art': 'keine', 'dicke': 0});
    final (a, b) = ab();
    expect(a + b, 62);
    s.schliessen();
  });
}
