import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/core/abgleich_projekt.dart';
import 'package:bauspur/core/fbh.dart';
import 'package:bauspur/core/geschossuebergreifend.dart';
import 'package:bauspur/core/height.dart';
import 'package:bauspur/core/hydraulik.dart';
import 'package:bauspur/core/leitung_wand.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/verteiler.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/ui/installation/heizkreise_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _kreuzen(Punkt a, Punkt b, Punkt c, Punkt d) {
  double k(Punkt o, Punkt p, Punkt q) => (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x);
  final d1 = k(c, d, a), d2 = k(c, d, b), d3 = k(a, b, c), d4 = k(a, b, d);
  return ((d1 > 1e-6 && d2 < -1e-6) || (d1 < -1e-6 && d2 > 1e-6)) && ((d3 > 1e-6 && d4 < -1e-6) || (d3 < -1e-6 && d4 > 1e-6));
}

void main() {
  group('Leitung im Bauteil', () {
    test('Vorgaben, Schlitzmaße, sichere Bohrtiefe', () {
      final l = LeitungImBauteil.aus({'breite_mm': 20, 'verlegung': 'schlitz', 'tiefe_mm': 15});
      expect(l.verlegung, Verlegung.schlitz);
      expect(l.hinterkante, 35);
      expect(l.schlitzB, 40);
      expect(l.schlitzT(putz: 10), 25);
      expect(l.sicherBohren, 10);
      // ohne Angabe: aus der Lage
      expect(LeitungImBauteil.aus(const {}, lage: 'auf Wand').verlegung, Verlegung.aufputz);
    });

    test('Schlitzprüfung nach Richtwerten', () {
      expect(schlitzPruefen(wanddicke: 240, tiefe: 30, breite: 100, senkrecht: true), isNull);
      expect(schlitzPruefen(wanddicke: 115, tiefe: 30, breite: 50, senkrecht: true), contains('Statik'));
      expect(schlitzPruefen(wanddicke: 115, tiefe: 10, breite: 30, senkrecht: false), contains('nicht zulässig'));
    });

    test('Bohr-Check zieht die halbe Leitungsbreite ab und begrenzt die Bohrtiefe', () {
      const teile = [
        WandTeil(id: 'a', text: 'Leerrohr', x: 0, z: 1000, x2: 2000, z2: 1000, breite: 40, ueberdeckung: 20),
        WandTeil(id: 'b', text: 'Dose', x: 3000, z: 300, breite: 60),
      ];
      final t = bohrCheck(const Offset(500, 1015), teile);
      expect(t.first.abstand, 0); // trifft die 40 mm breite Leitung
      expect(t.first.maxBohrtiefe, 15);
      final (stufe, text) = bohrUrteil(t, inZone: false);
      expect(stufe, 2);
      expect(text, contains('15 mm'));
      expect(bohrUrteil(bohrCheck(const Offset(500, 1015), teile), inZone: false, bohrtiefe: 10).$1, 1);
      final frei = bohrCheck(const Offset(1500, 1300), teile);
      expect(frei.first.abstand, closeTo(280, 0.1));
      expect(bohrUrteil(frei, inZone: false).$1, 1);
    });

    test('Geschossreihenfolge und Leitung, die ins Geschoss darüber steigt', () {
      Geschoss g(String id, String k) => Geschoss(id: id, gebaeudeId: 'h', name: k, kuerzel: k, hoehen: const Bezugshoehen(rfb: 0, ffb: 120, rohdecke: 2600, meterriss: 1120));
      final st = geschossStapel([g('o', 'OG'), g('k', 'KG'), g('e', 'EG'), g('d', 'DG')]);
      expect([for (final x in st) x.kuerzel], ['KG', 'EG', 'OG', 'DG']);
      final sockel = geschossSockel([g('e', 'EG'), g('o', 'OG')]);
      expect(sockel['o'], 2800);
      final o = Objekt(
          id: 'x', typId: 't', geschossId: 'e', raumId: null, z: null, zBezug: null, lage: null, normkennzeichen: null, kennung: 'L1', punkte: const [Punkt(0, 0), Punkt(0, 0), Punkt(1000, 0)],
          status: ObjektStatus.geplant, eigenschaften: const {'z_abs': [1000, 3400, 3400]});
      // aus Sicht des OG (versatz EG − OG = −2800): Stück von 0 bis 600 über RFB OG
      final stuecke = leitungImGeschoss(o, -2800, 0, 2800);
      expect(stuecke.length, 1);
      expect(stuecke.first.first.$2, closeTo(0, 0.1));
      expect(stuecke.first.last.$2, closeTo(600, 0.1));
    });
  });

  group('Hydraulischer Abgleich', () {
    test('Volumenstrom, Druckverlust, Voreinstellung: der längste Kreis bleibt offen', () {
      const e = AbgleichEinstellung();
      expect(volumenstromLh(1163, 5), closeTo(200, 0.1));
      final a = abgleichBerechnen(const [
        AbgleichKreis(id: 'k1', name: 'HK1', flaeche: 12, rohrlaenge: 95, leistung: 900, abgang: 1),
        AbgleichKreis(id: 'k2', name: 'HK2', flaeche: 6, rohrlaenge: 40, leistung: 400, abgang: 2, istLMin: 1.2),
      ], e);
      final k1 = a.kreise[0], k2 = a.kreise[1];
      expect(k1.lMin, closeTo(900 / 1.163 / 5 / 60, 0.01));
      expect(k1.druckverlust, greaterThan(k2.druckverlust));
      expect(a.unguenstigster!.kreis.id, 'k1');
      expect(k1.stufe, isNull, reason: 'ungünstigster Kreis voll offen');
      expect(k2.stufe, isNotNull);
      expect(k2.stufe!, lessThan(e.kvStufen.length));
      expect(k2.abweichung, isNotNull);
      expect(a.foerderhoehe, greaterThan(k1.druckverlust));
    });

    test('Leistung nach Fläche auf die Kreise eines Raums, sonst W/m²', () {
      final m = leistungAufteilen([
        (id: 'a', raum: 'r', flaeche: 10.0, vonHand: null),
        (id: 'b', raum: 'r', flaeche: 5.0, vonHand: null),
        (id: 'c', raum: 'x', flaeche: 4.0, vonHand: null),
        (id: 'd', raum: 'r', flaeche: 5.0, vonHand: 700.0),
      ], {'r': 1500}, 50);
      expect(m['a'], closeTo(1000, 0.1));
      expect(m['b'], closeTo(500, 0.1));
      expect(m['c'], closeTo(200, 0.1));
      expect(m['d'], 700);
    });
  });

  test('Anbindeleitungen: Bündel aus zwei Räumen durch den Flur zu den Abgängen, ohne Kreuzung im Bündel', () async {
    final tmp = Directory.systemTemp.createTempSync('bauspur_bd2_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'B2');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    // zwei Räume 4 × 3,5 m nebeneinander, darunter ein Flur 1,5 m; Türen unten
    final waende = <String, (int, int, int, int)>{
      'oben': (0, 0, 8000, 0),
      'links': (0, 0, 0, 5000),
      'rechts': (8000, 0, 8000, 5000),
      'unten': (0, 5000, 8000, 5000),
      'mitte': (4000, 0, 4000, 3500),
      'flur': (0, 3500, 8000, 3500),
    };
    final ids = <String, String>{};
    for (final e in waende.entries) {
      final (x1, y1, x2, y2) = e.value;
      ids[e.key] = store.wandAnlegen(geschossId: g, x1: x1, y1: y1, x2: x2, y2: y2, dicke: 175);
    }
    store.oeffnungAnlegen(wandId: ids['flur']!, art: OeffnungsArt.tuer, abstand: 2500, breite: 885, hoehe: 2010);
    store.oeffnungAnlegen(wandId: ids['flur']!, art: OeffnungsArt.tuer, abstand: 5500, breite: 885, hoehe: 2010);
    const u1 = [Punkt(90, 90), Punkt(3910, 90), Punkt(3910, 3410), Punkt(90, 3410)];
    const u2 = [Punkt(4090, 90), Punkt(7910, 90), Punkt(7910, 3410), Punkt(4090, 3410)];
    final r1 = store.raumAnlegen(geschossId: g, name: 'Zimmer 1', kuerzel: 'Z1', flaeche: ErkannterRaum(achse: u1, licht: u1));
    final r2 = store.raumAnlegen(geschossId: g, name: 'Zimmer 2', kuerzel: 'Z2', flaeche: ErkannterRaum(achse: u2, licht: u2));
    Objekttyp typ(String k) => store.objekttypen().firstWhere((t) => t.kuerzel == k);
    final hv = store.objektAnlegen(geschossId: g, typ: typ('HV'), punkte: const [Punkt(800, 4950)]);
    final kreise = <String>[];
    for (final (raum, x0) in [(r1, 100), (r2, 4100)]) {
      for (final dx in [0, 1900]) {
        final id = store.objektAnlegen(geschossId: g, typ: typ('HK'), raumId: raum, punkte: [
          Punkt(x0 + dx + 0.0, 200), Punkt(x0 + dx + 1700.0, 200), Punkt(x0 + dx + 1700.0, 3300), Punkt(x0 + dx + 0.0, 3300),
        ]);
        store.objektAendern(id, {'eigenschaften': jsonEncode({'zugang': 0.6})});
        kreise.add(id);
      }
    }
    // Abgänge belegen
    final vd = VerteilerDaten(abgaenge: 4, kreise: kreise);
    store.objektAendern(hv, {'eigenschaften': jsonEncode(vd.toJson())});
    final v = store.objekte(g).firstWhere((o) => o.id == hv);
    final hk = store.objekte(g).where((o) => kreise.contains(o.id)).toList();
    expect(anbindeleitungenBuendeln(store, g, hk, v), 8);
    final hr = typ('HR');
    final leitungen = store.objekte(g).where((o) => o.typId == hr.id).toList();
    expect(leitungen.length, 8);
    for (final l in leitungen) {
      for (var i = 0; i + 1 < l.punkte.length; i++) {
        final a = l.punkte[i], b = l.punkte[i + 1];
        expect((a.x - b.x).abs() < 1 || (a.y - b.y).abs() < 1, isTrue, reason: 'rechtwinklig');
      }
    }
    final ziel = Platform.environment['BAUSPUR_BILD'];
    if (ziel != null) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(const Rect.fromLTWH(0, 0, 900, 600), Paint()..color = Colors.white);
      const f = 0.1;
      Offset o(Punkt q) => Offset(q.x * f + 30, q.y * f + 30);
      for (final w in store.waende(g)) {
        c.drawLine(o(Punkt(w.x1.toDouble(), w.y1.toDouble())), o(Punkt(w.x2.toDouble(), w.y2.toDouble())), Paint()
          ..strokeWidth = w.dicke * f
          ..color = Colors.grey);
      }
      for (final k in store.objekte(g)) {
        if (kreise.contains(k.id)) {
          final p = verlegeplan(k.punkte, FbhEinstellung.ausJson(k.eigenschaften));
          for (final (zug, farbe) in [(p.vl, Colors.red), (p.rl, Colors.blue)]) {
            c.drawPath(Path()..addPolygon([for (final q in zug) o(q)], false), Paint()
              ..style = PaintingStyle.stroke
              ..color = farbe.withValues(alpha: 0.4));
          }
        }
      }
      for (final l in leitungen) {
        c.drawPath(Path()..addPolygon([for (final q in l.punkte) o(q)], false), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = l.eigenschaften['leitung'] == 'VL' ? Colors.red.shade900 : Colors.blue.shade900);
      }
      c.drawCircle(o(const Punkt(800, 4950)), 5, Paint()..color = Colors.black);
      final img = await rec.endRecording().toImage(900, 600);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$ziel/buendel_flur.png').writeAsBytesSync(png!.buffer.asUint8List());
    }
    // Leitungen desselben Raums kreuzen sich nicht (im Raum und durch die Tür: die ersten drei Abschnitte)
    for (final raum in [r1, r2]) {
      final l = leitungen.where((o) => o.raumId == raum).toList();
      var n = 0;
      for (var i = 0; i < l.length; i++) {
        for (var j = i + 1; j < l.length; j++) {
          for (var a = 0; a + 1 < l[i].punkte.length && a < 3; a++) {
            for (var b = 0; b + 1 < l[j].punkte.length && b < 3; b++) {
              if (_kreuzen(l[i].punkte[a], l[i].punkte[a + 1], l[j].punkte[b], l[j].punkte[b + 1])) {
                n++;
                // ignore: avoid_print
                print('Kreuzung ${l[i].eigenschaften['leitung']} ${l[i].punkte} / ${l[j].eigenschaften['leitung']} ${l[j].punkte}');
              }
            }
          }
        }
      }
      expect(n, 0, reason: 'Kreuzungen im Bündel von $raum');
    }
    // Abgleich rechnet mit der neuen Anbindung
    final a = abgleichFuerVerteiler(store, store.objekte(g).firstWhere((o) => o.id == hv));
    expect(a.kreise.length, 4);
    expect(a.kreise.every((k) => k.lMin > 0), isTrue);

    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Leitung aus dem EG erscheint in der Wand des OG', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_gs_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'G');
    final geb = store.gebaeude().single.id;
    final eg = store.geschosse(geb).single.id;
    final og = store.geschossAnlegen(gebaeudeId: geb, name: 'Obergeschoss', kuerzel: 'OG', rfb: 0, ffb: 120, rohdecke: 2600, meterriss: 1120);
    final typ = store.objekttypen().firstWhere((t) => t.geometrie == Geometrieart.linie);
    final id = store.objektAnlegen(geschossId: eg, typ: typ, punkte: const [Punkt(1000, 0), Punkt(1000, 0)]);
    final h = store.geschoss(eg)!.hoehen;
    store.objektAendern(id, {'eigenschaften': jsonEncode({'z_abs': [1000, h.rohdecke - h.rfb + 200 + 1500]})});
    final fremd = leitungenAusAnderenGeschossen(store, og);
    expect(fremd.length, 1);
    expect(fremd.single.$2.last.$2, closeTo(1500, 1));
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });
}
