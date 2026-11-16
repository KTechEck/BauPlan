import 'dart:io';

import 'package:bauspur/core/wandaufbau.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

Wand _w(String id, int x1, int y1, int x2, int y2, {Map<String, dynamic>? e}) => Wand(
      id: id,
      geschossId: 'g',
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      dicke: 200,
      zustand: WandZustand.bestand,
      eigenschaften: e ?? {},
    );

/// x-Werte der beiden Eckpunkte am Ende der waagrechten Wand.
List<double> _endeX(List<Wand> ws) {
  final u = wandUmrisse(ws)['a']!;
  return [u[1].x, u[2].x]..sort();
}

void main() {
  test('Anschlussarten verschieben das Wandende', () {
    List<Wand> ecke(Map<String, dynamic>? e) => [_w('a', 0, 0, 4000, 0, e: e), _w('b', 4000, 0, 4000, 3000)];
    // Gehrung: Ecken bei 3900 und 4100
    final g = _endeX(ecke(null));
    expect(g[0], closeTo(3900, 1));
    expect(g[1], closeTo(4100, 1));
    // stumpf: endet an der Innenkante der anderen Wand
    final s = _endeX(ecke({'anschluss_b': {'art': 'stumpf'}}));
    expect(s[0], closeTo(3900, 1));
    expect(s[1], closeTo(3900, 1));
    // durchlaufend: bis zur Außenkante
    final d = _endeX(ecke({'anschluss_b': {'art': 'durch'}}));
    expect(d[0], closeTo(4100, 1));
    expect(d[1], closeTo(4100, 1));
    // eingebunden 60 mm
    final ein = _endeX(ecke({'anschluss_b': {'art': 'eingebunden', 'tiefe': 60}}));
    expect(ein[0], closeTo(3960, 1));
    expect(ein[1], closeTo(3960, 1));
  });

  test('Wirksamer Anschluss aus Nachbar und Baustoff', () {
    final a = _w('a', 0, 0, 4000, 0, e: {'kern': {'m': 'st', 'd': 100}});
    final b = _w('b', 4000, 0, 4000, 3000, e: {'kern': {'m': 'zi', 'd': 240}});
    String? name(String? id) => id == 'st' ? 'Metallständerwand' : 'Hochlochziegel';
    expect(anschlussWirksam(a, false, b, baustoffName: name).art, AnschlussArt.stumpf);
    expect(anschlussWirksam(b, true, a, baustoffName: name).art, AnschlussArt.durch);
    // Einstellung der Nachbarwand wird gespiegelt
    final b2 = _w('b', 4000, 0, 4000, 3000, e: {'anschluss_a': {'art': 'durch'}});
    expect(anschlussWirksam(_w('a', 0, 0, 4000, 0), false, b2).art, AnschlussArt.stumpf);
    expect(anschlussJson((art: AnschlussArt.eingebunden, tiefe: 80, schichtenDurch: false)), {'art': 'eingebunden', 'tiefe': 80});
  });

  test('Kern aus Wandtyp wählbar, Aufbau-Vorlagen speichern', () {
    final sch = [Schicht('putz', 15), Schicht('daemm', 160), Schicht('ziegel', 120)];
    expect(ausWandtyp(sch).kern, 160, reason: 'ohne Vorgabe die dickste Schicht');
    final k = ausWandtyp(sch, kern: 2);
    expect(k.kern, 120);
    expect((k.eigenschaften['aufbau_l'] as List).length, 1);
    expect(k.eigenschaften['aufbau_r'], isNull);

    final tmp = Directory.systemTemp.createTempSync('bauspur_b37_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'V');
    expect(aufbauVorlagen(store), isEmpty);
    aufbauVorlagenSetzen(store, [(name: 'WDVS 160', schichten: [(material: 'kleber', dicke: 5), (material: 'eps', dicke: 160)])]);
    final v = aufbauVorlagen(store);
    expect(v.single.name, 'WDVS 160');
    expect(v.single.schichten.map((s) => s.dicke), [5, 160]);
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });
}
