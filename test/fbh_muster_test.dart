import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/core/fbh.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _schneiden(Punkt a, Punkt b, Punkt c, Punkt d) {
  double k(Punkt o, Punkt p, Punkt q) => (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x);
  final d1 = k(c, d, a), d2 = k(c, d, b), d3 = k(a, b, c), d4 = k(a, b, d);
  return ((d1 > 1e-6 && d2 < -1e-6) || (d1 < -1e-6 && d2 > 1e-6)) && ((d3 > 1e-6 && d4 < -1e-6) || (d3 < -1e-6 && d4 > 1e-6));
}

int _kreuzungen(List<Punkt> zug) {
  var n = 0;
  for (var i = 0; i + 1 < zug.length; i++) {
    for (var j = i + 2; j + 1 < zug.length; j++) {
      if (_schneiden(zug[i], zug[i + 1], zug[j], zug[j + 1])) n++;
    }
  }
  return n;
}

void main() {
  const rechteck = [Punkt(0, 0), Punkt(4000, 0), Punkt(4000, 3000), Punkt(0, 3000)];
  const lForm = [Punkt(0, 0), Punkt(5000, 0), Punkt(5000, 2000), Punkt(2500, 2000), Punkt(2500, 4000), Punkt(0, 4000)];

  for (final m in Verlegemuster.values) {
    for (final (name, u) in [('Rechteck', rechteck), ('L-Form', lForm)]) {
      test('${m.label} $name: kreuzungsfrei, Anschlüsse nebeneinander am Zugang', () {
        final e = FbhEinstellung(muster: m, zugang: 0.1);
        final p = verlegeplan(u, e);
        expect(p.leer, isFalse);
        // ein durchgehender Rohrzug VL + RL ohne Kreuzung
        final ganz = [...p.vl, ...p.rl.skip(1)];
        expect(_kreuzungen(ganz), 0, reason: 'Rohr kreuzt sich');
        // Anschlüsse liegen nah beieinander (≤ 2·VA + Rand)
        if (m != Verlegemuster.maeander) expect((p.anschlussVl! - p.anschlussRl!).laenge, lessThan(400));
        // Rohrlänge plausibel: etwa Fläche / VA
        final soll = polygonFlaeche(u).abs() / e.abstand;
        expect(rohrlaenge(u, e), inInclusiveRange(soll * 0.6, soll * 1.4));
      });
    }
  }

  test('Randzone verdichtet die äußeren Windungen', () {
    final ohne = rohrlaenge(rechteck, const FbhEinstellung());
    final mit = rohrlaenge(rechteck, const FbhEinstellung(randzone: 600, abstandRand: 100));
    expect(mit, greaterThan(ohne));
  });

  test('Bilder der Verlegemuster', () async {
    final ziel = Platform.environment['BAUSPUR_BILD'];
    if (ziel == null) return;
    for (final m in Verlegemuster.values) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(const Rect.fromLTWH(0, 0, 700, 500), Paint()..color = Colors.white);
      const f = 0.12;
      final p = verlegeplan(lForm, FbhEinstellung(muster: m, zugang: 0.1));
      c.drawPath(Path()..addPolygon([for (final q in lForm) Offset(q.x * f + 20, q.y * f + 20)], true), Paint()..style = PaintingStyle.stroke);
      for (final (zug, farbe) in [(p.vl, Colors.red), (p.rl, Colors.blue)]) {
        c.drawPath(Path()..addPolygon([for (final q in zug) Offset(q.x * f + 20, q.y * f + 20)], false), Paint()
          ..style = PaintingStyle.stroke
          ..color = farbe
          ..strokeWidth = 1.5);
      }
      final img = await rec.endRecording().toImage(700, 500);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$ziel/fbh_${m.name}.png').writeAsBytesSync(png!.buffer.asUint8List());
    }
  });

  test('Fläche teilen: gleich große Streifen, Summe = Gesamtfläche', () {
    final teile = flaecheTeilen(lForm, 3);
    expect(teile.length, 3);
    final ges = polygonFlaeche(lForm).abs();
    for (final t in teile) {
      expect(polygonFlaeche(t).abs(), closeTo(ges / 3, ges * 0.01));
    }
  });

  test('Vorschlag je Raum hält die maximale Kreislänge ein', () {
    const gross = [Punkt(0, 0), Punkt(8000, 0), Punkt(8000, 5000), Punkt(0, 5000)];
    final v = heizkreiseVorschlagen(gross, FbhEinstellung.ausJson(const {'va_mm': 150}), ziel: const Punkt(0, 6000), maxLaenge: 100000);
    expect(v.length, greaterThan(1));
    for (final (u, eig) in v) {
      expect(rohrlaenge(u, FbhEinstellung.ausJson(eig)), lessThanOrEqualTo(100000));
      expect(eig['zuleitung_mm'], greaterThan(0));
    }
  });

  test('Anbindeweg führt durch die Tür und ist rechtwinklig', () {
    const tuer = (mitte: Punkt(4000, 1500), richtung: Punkt(0, 1), dicke: 240.0);
    final w = anbindeweg(const Punkt(500, 500), const Punkt(7000, 3500), raum: rechteck, tueren: const [tuer]);
    expect(w.first, const Punkt(500, 500));
    expect(w.last, const Punkt(7000, 3500));
    for (var i = 0; i + 1 < w.length; i++) {
      expect(w[i].x == w[i + 1].x || w[i].y == w[i + 1].y, isTrue);
    }
    // ein Segment kreuzt die Wand x = 4000 bei y = 1500
    expect(w.any((p) => p.y == 1500 && p.x < 4000) && w.any((p) => p.y == 1500 && p.x > 4000), isTrue);
  });

  for (final m in Verlegemuster.values) {
    test('Sperrflächen: ${m.label} verlegt um Küchenzeile und Dusche herum, kreuzungsfrei', () async {
      const sperren = [
        [Punkt(0, 0), Punkt(1800, 0), Punkt(1800, 600), Punkt(0, 600)], // Küchenzeile an der Wand
        [Punkt(3300, 2200), Punkt(4000, 2200), Punkt(4000, 3000), Punkt(3300, 3000)], // Dusche in der Ecke
      ];
      final e = FbhEinstellung(muster: m, zugang: 0.6, sperren: sperren);
      final p = verlegeplan(rechteck, e);
      expect(p.leer, isFalse);
      for (final q in [...p.vl, ...p.rl]) {
        for (final sp in sperren) {
          expect(punktInPolygon(q, sp), isFalse, reason: 'Rohrpunkt $q in Sperrfläche');
        }
      }
      final ziel = Platform.environment['BAUSPUR_BILD'];
      if (ziel != null) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(const Rect.fromLTWH(0, 0, 560, 420), Paint()..color = Colors.white);
      const f = 0.13;
      Offset o(Punkt q) => Offset(q.x * f + 20, q.y * f + 20);
      c.drawPath(Path()..addPolygon([for (final q in rechteck) o(q)], true), Paint()..style = PaintingStyle.stroke);
      for (final sp in sperren) {
        c.drawPath(Path()..addPolygon([for (final q in sp) o(q)], true), Paint()..color = const Color(0x55868E96));
      }
      for (final (zug, farbe) in [(p.vl, Colors.red), (p.rl, Colors.blue)]) {
        c.drawPath(Path()..addPolygon([for (final q in zug) o(q)], false), Paint()
          ..style = PaintingStyle.stroke
          ..color = farbe
          ..strokeWidth = 1.5);
      }
      final img = await rec.endRecording().toImage(560, 420);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$ziel/fbh_sperren_${m.name}.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
      expect(_kreuzungen([...p.vl, ...p.rl]), 0);
    });
  }

  test('Sperrfläche als Insel mitten im Raum: Rohr läuft drumherum', () {
    const insel = [Punkt(2200, 1300), Punkt(3000, 1300), Punkt(3000, 2000), Punkt(2200, 2000)];
    final p = verlegeplan(rechteck, const FbhEinstellung(zugang: 0.3, sperren: [insel]));
    expect(p.leer, isFalse);
    expect([...p.vl, ...p.rl].any((q) => punktInPolygon(q, insel)), isFalse);
    expect(verlegeplanKreuzungen(p), 0);
  });
}
