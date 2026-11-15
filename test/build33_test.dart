import 'dart:convert';
import 'dart:io';

import 'package:bauspur/core/aufmass.dart';
import 'package:bauspur/core/drei_d_szene.dart';
import 'package:bauspur/core/kabelwege.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/installation/geraete_bibliothek.dart';
import 'package:bauspur/ui/installation/kabel_suche.dart';
import 'package:bauspur/ui/installation/legende.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('3D-Geräte: Steckdose als Platte auf der Wand, Leuchte an der Decke', () {
    const a = Punkt(0, 0), b = Punkt(4000, 0);
    const w = Wand3d(id: 'w', a: a, b: b, dicke: 240, umriss: [Punkt(0, 120), Punkt(4000, 120), Punkt(4000, -120), Punkt(0, -120)], hoehe: 2500);
    final f = geraeteFlaechen([
      (id: 'sd', kuerzel: 'SD', p: const Punkt(1000, 200), z: null, masse: null, farbe: 0xFF1C7ED6, drehung: 0),
      (id: 'le', kuerzel: 'LE', p: const Punkt(2000, 1500), z: null, masse: null, farbe: 0xFFF59F00, drehung: 0),
    ], [w], 2500);
    final sd = f.where((x) => x.id == 'sd');
    expect(sd, isNotEmpty);
    // Platte liegt vor der Wandoberfläche (Grundriss-y 120…131 → 3D-y −120…−131), Mitte auf 300 mm
    expect(sd.expand((x) => x.ecken).every((e) => e.y <= -119 && e.y >= -135), isTrue);
    expect(sd.expand((x) => x.ecken).map((e) => e.z).reduce((x, y) => x > y ? x : y), closeTo(340, 1));
    expect(f.where((x) => x.id == 'le').expand((x) => x.ecken).every((e) => e.z >= 2400), isTrue);
  });

  test('Kabelwege über Geschosse, Kabelsuche, Legende, Gerätebibliothek, neue Installation vom Handy', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_b33_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'K');
    final geb = store.gebaeude().single.id;
    final eg = store.geschosse(geb).single.id;
    final og = store.geschossAnlegen(gebaeudeId: geb, name: '1. OG', kuerzel: 'OG', rfb: 0, ffb: 100, rohdecke: 2700, meterriss: 1100);
    final typ = {for (final t in store.objekttypen()) if (t.gewerkId == store.objekttypen().firstWhere((x) => x.kuerzel == 'SD').gewerkId) t.kuerzel: t};
    final vt = store.objektAnlegen(geschossId: eg, typ: typ['VT']!, punkte: const [Punkt(0, 0)]);
    final sr = store.objektAnlegen(geschossId: eg, typ: typ['SR']!, punkte: const [Punkt(3000, 0)]);
    final sd = store.objektAnlegen(geschossId: og, typ: typ['SD']!, punkte: const [Punkt(3000, 2000)]);
    final l1 = store.objektAnlegen(geschossId: eg, typ: typ['LT']!, punkte: const [Punkt(0, 0), Punkt(3000, 0)]);
    store.objektAendern(l1, {'eigenschaften': jsonEncode({'kabel': 'NYM-J 3x1,5', 'anfang': {'objekt': vt}, 'ende': {'objekt': sr}})});
    final l2 = store.objektAnlegen(geschossId: og, typ: typ['LT']!, punkte: const [Punkt(3000, 0), Punkt(3000, 2000)]);
    store.objektAendern(l2, {'eigenschaften': jsonEncode({'anfang': {'objekt': sr}, 'ende': {'objekt': sd}})});
    final wege = kabelwege(store);
    final k = wege.firstWhere((x) => x.leitungen.contains(l1));
    expect(k.leitungen, containsAll([l1, l2]), reason: 'über die Steigleitung verbunden');
    expect(k.geschosse, hasLength(2));
    expect(k.senkrecht, greaterThan(2));
    expect(k.meter, closeTo(3 + 2 + k.senkrecht + 1, 0.01));
    expect(k.kabel, 'NYM-J 3x1,5');
    expect(kabelzuglisteCsv(wege), contains('NYM-J 3x1,5'));

    final state = AppState(AppSettings.inDatei(File(p.join(tmp.path, 'e.json'))))..store = store;
    expect(kabelSuchen(state, 'NYM').map((t) => t.objekt.id), contains(l1));
    final leg = legendeBauen(store.objekte(og), {for (final t in store.objekttypen()) t.id: t}, {for (final g in store.gewerke()) g.id: g});
    expect(leg.map((z) => z.kuerzel), containsAll(['SD', 'LT']));
    final eintraege = geraeteEintraege(state);
    expect(eintraege.any((e) => e.typ.kuerzel == 'SD' && e.produkt != null), isTrue, reason: 'Beispiel-Steckdose aus der Bibliothek');
    favoritUmschalten(state, 'typ:${typ['SD']!.id}');
    expect(geraeteFavoriten(state), ['typ:${typ['SD']!.id}']);

    // Handy: Steckdose vor Ort aufgenommen
    final w = store.wandAnlegen(geschossId: og, x1: 0, y1: 0, x2: 4000, y2: 0, dicke: 240);
    aufmassAblegen(store, {'ziel': 'objekt_neu', 'id': 'neu-1', 'feld': 'x', 'wert': 1500, 'seite': 'r', 'geschoss': og, 'wand': w, 'feld_json': {'typ': 'SD', 'h': 300}});
    final a = aufmassListe(store).last;
    expect(aufmassAnwenden(store, a), isNull);
    final neu = store.objekte(og).where((o) => o.typId == typ['SD']!.id && o.id != sd).single;
    expect(neu.z, 300);
    expect(neu.punkte.first.y.abs(), closeTo(120, 1));
    store.schliessen();
  });
}
