import 'dart:io';

import 'package:bauspur/core/aufmass.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/sparren.dart';
import 'package:bauspur/core/waermebruecke.dart';
import 'package:bauspur/core/wandmasse.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Aufmaß ohne gültige Wand-ID: Wand über Raum, Seite und Planlänge', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_b34_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'A');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    for (final (x1, y1, x2, y2) in [(0, 0, 5000, 0), (5000, 0, 5000, 3000), (5000, 3000, 0, 3600), (0, 3600, 0, 0)]) {
      store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
    }
    final raum = store.raumAnlegen(geschossId: g, name: 'Flur', kuerzel: 'FL', flaeche: store.flaechenErkennen(g).single);
    final m = wandMasse(store.waende(g), store.raeume(g));
    final w = store.waende(g).firstWhere((x) => x.y1 == 0 && x.y2 == 0);
    final seite = m[w.id]!.raumLinks == raum ? 'l' : 'r';
    final plan = seite == 'l' ? m[w.id]!.links : m[w.id]!.rechts;
    aufmassAblegen(store, {'ziel': 'wand', 'id': '20261115141111_falsch', 'feld': 'laenge', 'wert': 4700, 'seite': seite, 'bezug': 'innen', 'plan': plan.round(), 'geschoss': g, 'raum': raum});
    final a = aufmassListe(store).single;
    expect(aufmassZielAufloesen(store, a)['id_ziel'], w.id);
    expect(aufmassAnwenden(store, a), isNull);
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Offene Kante wird nicht verschnitten; Wand quer versetzen; Balkonseite gilt als außen', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_b34b_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'B');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final ids = [
      for (final (x1, y1, x2, y2) in [(0, 0, 4000, 0), (4000, 0, 4000, 2000), (4000, 2000, 0, 2000), (0, 2000, 0, 0)])
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240),
    ];
    store.wandEigenschaftenSetzen(ids[2], {'art': 'kante'});
    final ws = store.waende(g);
    final nb = [for (final w in ws) if (!w.istKante) w.achse];
    final rechts = ws.firstWhere((w) => w.id == ids[1]);
    final u = wandUmriss(rechts.achse, nb);
    // Ende an der Kante (y = 2000) gerade, ohne Gehrung
    expect(u[1].y, closeTo(u[2].y, 0.5));
    store.wandQuerVersetzen(ids[1], 80);
    final neu = store.waende(g).firstWhere((w) => w.id == ids[1]);
    expect((neu.x1 - 4000).abs(), 80);
    final oben = store.waende(g).firstWhere((w) => w.id == ids[0]);
    expect([oben.x1, oben.x2], contains(neu.x1), reason: 'anstoßende Wand wächst mit');
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Einbaudetail: Zusatzschicht rechnet mit; Sparrenlage über das ganze Geschoss', () {
    const schichten = [WbSchicht('Putz', 15, 0.8), WbSchicht('Ziegel', 365, 0.14), WbSchicht('Putz', 15, 0.7)];
    final ohne = waermebrueckeBerechnen(const EinbauDetail(schichten: schichten, einbaulage: 150), h: 10);
    final mit = waermebrueckeBerechnen(const EinbauDetail(schichten: schichten, einbaulage: 150, zusatz: 30, zusatzLambda: 0.03), h: 10);
    expect(mit.psi, isNot(closeTo(ohne.psi, 1e-6)));
    const d = EinbauDetail(schichten: schichten, fuge: 10, zusatz: 20);
    expect(d.spalt, 30);

    final waende = [
      Wand(id: 'a', geschossId: 'g', x1: 0, y1: 0, x2: 10000, y2: 0, dicke: 300, zustand: WandZustand.bestand),
      Wand(id: 'b', geschossId: 'g', x1: 10000, y1: 0, x2: 10000, y2: 8000, dicke: 300, zustand: WandZustand.bestand),
      Wand(id: 'c', geschossId: 'g', x1: 0, y1: 8000, x2: 10000, y2: 8000, dicke: 300, zustand: WandZustand.bestand),
    ];
    final f = sparrenlageGeschoss(waende, rx: 0, ry: 1, ueberstand: 500);
    final st = f.strecken;
    expect(st, isNotEmpty);
    // laufen von oben nach unten über das ganze Geschoss inkl. Überstand
    expect(st.first.$1.$2, closeTo(-650, 1));
    expect(st.first.$2.$2, closeTo(8650, 1));
    expect(st.map((s) => s.$1.$1).reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(10650));
    expect(sparrenfeldBei([f], st.first.$1.$1 + 2, 4000, 10), f.id);
    expect(sparrenfeldBei([f], -5000, -5000, 10), isNull);
    expect(const Punkt(0, 0), isNotNull);
  });
}
