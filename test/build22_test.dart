import 'dart:io';

import 'package:bauspur/core/bad.dart';
import 'package:bauspur/core/diktat.dart';
import 'package:bauspur/core/foto_zuordnung.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/typenschild.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Teilhohe Wand bildet keine Raumgrenze, Badtypen sind da', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_b22_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'B');
    try {
      final g = store.geschosse(store.gebaeude().single.id).single.id;
      for (final (x1, y1, x2, y2) in [(0, 0, 6000, 0), (6000, 0, 6000, 4000), (6000, 4000, 0, 4000), (0, 4000, 0, 0)]) {
        store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 240);
      }
      final trenn = store.wandAnlegen(geschossId: g, x1: 3000, y1: 0, x2: 3000, y2: 4000, dicke: 115);
      expect(store.flaechenErkennen(g).length, 2);
      store.wandEigenschaftenSetzen(trenn, {'art': WandArt.raumtrenner.name, 'hoehe': 1200});
      final w = store.waende(g).firstWhere((w) => w.id == trenn);
      expect(w.teilhoch, isTrue);
      expect(w.hoehe, 1200);
      expect(w.art, WandArt.raumtrenner);
      expect(store.flaechenErkennen(g).length, 1);
      store.wandEigenschaftenSetzen(trenn, {'art': null, 'hoehe': null});
      expect(store.flaechenErkennen(g).length, 2);
      final k = {for (final t in store.objekttypen()) t.kuerzel};
      expect(k.containsAll(['DU', 'WA', 'WC', 'WT']), isTrue);
    } finally {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    }
  });

  test('Abdichtung: Dusche in der Ecke, Wanne mit Brause, Nische', () {
    const raum = [Punkt(0, 0), Punkt(3000, 0), Punkt(3000, 2500), Punkt(0, 2500)];
    // Dusche 1000×1000 in der Ecke (0|0)
    const dusche = BadFlaeche(umriss: [Punkt(0, 0), Punkt(1000, 0), Punkt(1000, 1000), Punkt(0, 1000)], wanne: false);
    final e = abdichtungBerechnen(umriss: raum, flaechen: const [dusche], raumhoehe: 2500, nischen: const [(breite: 300, hoehe: 600, tiefe: 100, imSpritzbereich: true)]);
    expect(e.flaechen.first.klasse, 'W1-I'); // bodengleich → Boden W1-I
    expect(e.flaechen.first.m2, closeTo(7.5, 1e-9));
    // zwei Wände je 1,2 m (1 m + 20 cm) × 2 m = 4,8 m²
    expect(e.summeKlasse('W1-I'), closeTo(7.5 + 4.8 + (0.18 + 2 * 0.1 * 0.9), 1e-6));
    expect(e.innenecken, 4 + 1);
    expect(e.wandmanschetten, 2);
    expect(e.bodenmanschetten, 1);
    expect(e.hinweise.any((h) => h.contains('Gefälle')), isTrue);
    // ohne Ablauf, Wanne ohne Brause: Boden W0-I, Wand 0,8 m hoch
    const wanne = BadFlaeche(umriss: [Punkt(0, 1700), Punkt(1700, 1700), Punkt(1700, 2500), Punkt(0, 2500)], wanne: true, brause: false);
    final w = abdichtungBerechnen(umriss: raum, flaechen: const [wanne]);
    expect(w.flaechen.first.klasse, 'W0-I');
    expect(w.summeKlasse('W1-I'), greaterThan(0));
    expect(istNassraum('Bad OG', const {}), isTrue);
    expect(istNassraum('Bad OG', const {'nassraum': false}), isFalse);
    expect(istNassraum('Flur', const {}), isFalse);
    expect(istNassraum('Gäste-WC', const {}, hatDuscheOderWanne: true), isTrue);
    expect(badAbstaende([(kuerzel: 'WC', kennung: 'WC1', mitte: const Punkt(0, 0)), (kuerzel: 'WT', kennung: 'WT1', mitte: const Punkt(550, 0))]).length, 1);
  });

  test('Diktat: Satzzeichen, Aufgaben, Mängel, Messwerte', () {
    final t = diktatAufbereiten('steckdosen im bad gesetzt punkt aufgabe noch schlitz zumachen punkt mangel fliese hat einen riss punkt steckdose höhe 30 zentimeter');
    expect(t, startsWith('Steckdosen im bad gesetzt.'));
    final teile = diktatAuswerten(t);
    expect(teile.aufgaben.single, contains('schlitz zumachen'));
    expect(teile.maengel.single, contains('Fliese hat einen riss'));
    expect(teile.messwerte.single.wert, 30);
    expect(teile.messwerte.single.einheit, 'cm');
    final ki = kiDiktatLesen('Hier: {"notiz": "Bad fertig", "aufgaben": ["Silikon"], "maengel": []}');
    expect(ki!.aufgaben, ['Silikon']);
  });

  test('Typenschild aus Text', () {
    const text = 'VIESSMANN\nVitocal 250-A\nTyp: AWO-E-AC 251.A10\nSer.-Nr.: 7887123456789\nBaujahr 2023\n'
        '230 V ~ 50 Hz  16 A\nNennwärmeleistung 10,1 kW\nIPX4  R290  max. 3 bar';
    final t = typenschildLesen(text);
    expect(t.werte['hersteller'], 'Viessmann');
    expect(t.werte['seriennummer'], '7887123456789');
    expect(t.werte['baujahr'], 2023);
    expect(t.werte['leistung_w'], 10100);
    expect(t.werte['spannung_v'], 230);
    expect(t.werte['strom_a'], 16);
    expect(t.werte['frequenz_hz'], 50);
    expect(t.werte['schutzart'], 'IPX4');
    expect(t.werte['kaeltemittel'], 'R290');
    expect(t.werte['druck_bar'], 3);
    expect(t.werte['typ'], startsWith('AWO-E-AC'));
    final k = kiTypenschildLesen('{"hersteller": "Wilo", "leistung_w": 45, "typ": null}');
    expect(k!.werte, {'hersteller': 'Wilo', 'leistung_w': 45});
  });

  test('Fotos: Vorschlag aus der Aufnahmezeit', () {
    final t0 = DateTime(2026, 11, 14, 10);
    final v = zeitVorschlaege([
      (id: 'a', zeit: t0, raumId: 'bad'),
      (id: 'b', zeit: t0.add(const Duration(minutes: 3)), raumId: null),
      (id: 'c', zeit: t0.add(const Duration(hours: 2)), raumId: null),
    ]);
    expect(v.single.fotoId, 'b');
    expect(v.single.raumId, 'bad');
    expect(kiFotoLesen('{"raum": "Bad", "objekt": null, "beschreibung": "Fliesen"}')!.raum, 'Bad');
  });
}
