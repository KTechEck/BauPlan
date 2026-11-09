import 'dart:io';

import 'package:bauspur/core/dxf.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Baut eine kleine ASCII-DXF aus Gruppen (Code, Wert).
String dxf(List<(int, Object)> paare) => [for (final (c, w) in paare) '$c\n$w'].join('\n');

List<(int, Object)> linie(String layer, double x1, double y1, double x2, double y2) =>
    [(0, 'LINE'), (8, layer), (10, x1), (20, y1), (11, x2), (21, y2)];

/// Rechteckiger Raum als Doppellinien (innen und außen) in cm.
List<(int, Object)> raumCm() {
  // Achsrechteck 0..400 × 0..300 cm, Wand 24 cm: außen ±12, innen ∓12
  final r = <(int, Object)>[];
  for (final d in [-12.0, 12.0]) {
    final x0 = 0 - d, y0 = 0 - d, x1 = 400 + d, y1 = 300 + d;
    r
      ..addAll(linie('WAND', x0, y0, x1, y0))
      ..addAll(linie('WAND', x1, y0, x1, y1))
      ..addAll(linie('WAND', x1, y1, x0, y1))
      ..addAll(linie('WAND', x0, y1, x0, y0));
  }
  return r;
}

void main() {
  test('DXF lesen: Einheit, Linien, Polylinie, Bogen, Text, Block', () {
    final inhalt = dxf([
      (0, 'SECTION'), (2, 'HEADER'), (9, r'$INSUNITS'), (70, 5), (0, 'ENDSEC'),
      (0, 'SECTION'), (2, 'BLOCKS'),
      (0, 'BLOCK'), (2, 'TUER'), (10, 0), (20, 0),
      ...linie('0', 0, 0, 10, 0),
      (0, 'ENDBLK'),
      (0, 'ENDSEC'),
      (0, 'SECTION'), (2, 'ENTITIES'),
      ...linie('WAND', 0, 0, 100, 0),
      (0, 'LWPOLYLINE'), (8, 'MOEBEL'), (90, 3), (70, 1), (10, 0), (20, 0), (10, 50), (20, 0), (10, 50), (20, 50),
      (0, 'ARC'), (8, 'TUER'), (10, 0), (20, 0), (40, 80), (50, 0), (51, 90),
      (0, 'TEXT'), (8, 'TEXT'), (10, 20), (20, 30), (40, 5), (1, 'Wohnen'),
      (0, 'INSERT'), (8, 'TUEREN'), (2, 'TUER'), (10, 200), (20, 100), (50, 90),
      (0, 'ENDSEC'), (0, 'EOF'),
    ]);
    final d = dxfLesen(inhalt);
    expect(d.einheit, 5);
    expect(d.mmProEinheit, 10);
    expect(d.zuege.length, 4);
    expect(d.anzahlJeLayer['WAND'], 1);
    final poly = d.zuege.firstWhere((z) => z.layer == 'MOEBEL');
    expect(poly.geschlossen, isTrue);
    expect(poly.punkte.length, 3);
    final bogen = d.zuege.firstWhere((z) => z.layer == 'TUER');
    expect(bogen.bogen, isTrue);
    expect(bogen.punkte.last.y, closeTo(80, 1e-6));
    expect(d.texte.single.text, 'Wohnen');
    // Block um 90° gedreht bei (200|100), Layer „0“ erbt den Layer des INSERT
    final block = d.zuege.firstWhere((z) => z.layer == 'TUEREN');
    expect(block.punkte.last.x, closeTo(200, 1e-6));
    expect(block.punkte.last.y, closeTo(110, 1e-6));
    // Welt: y nach unten, mm
    final w = DxfZeichnung.zuWelt(const Punkt(10, 20), ursprungX: 0, ursprungY: 0, mmProEinheit: 10);
    expect((w.x, w.y), (100.0, -200.0));
  });

  test('Doppellinien werden zu Wänden, Ecken schließen sich zum Raum', () {
    final d = dxfLesen(dxf([
      (0, 'SECTION'), (2, 'HEADER'), (9, r'$INSUNITS'), (70, 5), (0, 'ENDSEC'),
      (0, 'SECTION'), (2, 'ENTITIES'), ...raumCm(), (0, 'ENDSEC'), (0, 'EOF'),
    ]));
    final s = d.mmProEinheit;
    final strecken = [
      for (final z in d.zuege)
        (DxfZeichnung.zuWelt(z.punkte[0], ursprungX: 0, ursprungY: 0, mmProEinheit: s),
            DxfZeichnung.zuWelt(z.punkte[1], ursprungX: 0, ursprungY: 0, mmProEinheit: s)),
    ];
    final roh = waendeErkennen(strecken, einzelLinien: false);
    expect(roh.length, 4);
    expect(roh.every((w) => (w.dicke - 240).abs() < 0.5), isTrue);
    final waende = waendeVerbinden(roh);
    // Achsen treffen sich jetzt an den Ecken
    final enden = [for (final w in waende) ...[w.a, w.b]];
    for (final e in enden) {
      expect(enden.where((q) => (q - e).laenge < 1).length, 2);
    }

    final tmp = Directory.systemTemp.createTempSync('bauspur_dxf_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'D');
    addTearDown(store.schliessen);
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    for (final w in waende) {
      store.wandAnlegen(
          geschossId: g, x1: w.a.x.round(), y1: w.a.y.round(), x2: w.b.x.round(), y2: w.b.y.round(), dicke: w.dicke.round());
    }
    final f = store.flaechenErkennen(g);
    expect(f.length, 1);
    expect(f.single.flaeche, closeTo(3760 * 2760, 5000)); // licht: Achse − Wanddicke
  });

  test('Einzelne Linien nur auf Wunsch, kurze Striche werden ignoriert', () {
    final strecken = [(const Punkt(0, 0), const Punkt(3000, 0)), (const Punkt(0, 500), const Punkt(50, 500))];
    expect(waendeErkennen(strecken, einzelLinien: false), isEmpty);
    final w = waendeErkennen(strecken, standardDicke: 115);
    expect(w.length, 1);
    expect(w.single.dicke, 115);
  });
}
