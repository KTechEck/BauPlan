import 'dart:io';
import 'dart:ui' as ui;

import 'package:bauspur/core/stromlaufplan.dart';
import 'package:bauspur/data/schrank_models.dart';
import 'package:bauspur/ui/verteiler/stromlaufplan_ansicht.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

SchrankGeraet _g(String id, GeraeteArt art, String kz, {int reihe = 0, int pos = 0, int pole = 1, String? phase, String? vor, int? n, int? fi, Map<String, dynamic> e = const {}}) =>
    SchrankGeraet(
      id: id,
      schrankId: 's',
      reihe: reihe,
      position: pos,
      breite: art.breite(pole),
      art: art,
      kennzeichen: kz,
      pole: pole,
      phase: phase,
      vorgeschaltetId: vor,
      nennstrom: n,
      fehlerstrom: fi,
      eigenschaften: e,
    );

final _schrank = Schrank(id: 's', geschossId: null, objektId: null, name: 'UV Erdgeschoss', kennzeichen: 'UV1', art: SchrankArt.unterverteiler, reihen: 4, teJeReihe: 12);

(List<SchrankGeraet>, List<Stromkreis>) _beispiel({int lsAnzahl = 4}) {
  final geraete = [
    _g('q1', GeraeteArt.hauptschalter, '-Q1', pole: 3, n: 63),
    _g('spd', GeraeteArt.spd, '-F1', pos: 3),
    _g('fi1', GeraeteArt.rcd, '-F2', reihe: 1, pole: 3, n: 40, fi: 30),
    for (var i = 0; i < lsAnzahl; i++) _g('ls$i', GeraeteArt.ls, '-F${10 + i}', reihe: 1, pos: 4 + i, phase: ['L1', 'L2', 'L3'][i % 3], vor: 'fi1', n: 16),
    _g('fils', GeraeteArt.fils, '-F30', reihe: 2, phase: 'L2', n: 16, fi: 30),
    _g('herd', GeraeteArt.ls, '-F31', reihe: 2, pos: 2, pole: 3, phase: '3P', n: 16),
    _g('k1', GeraeteArt.knx, '-K1', reihe: 3, e: {'aktortyp': 'Schalt', 'kanaele': 8, 'pa': '1.1.10'}),
    _g('x1', GeraeteArt.klemme, '-X1', reihe: 3, pos: 5, e: {'stromkreis': 'k0'}),
  ];
  final kreise = [
    for (var i = 0; i < lsAnzahl; i++) Stromkreis(id: 'k$i', schrankId: 's', nummer: '${i + 1}', bezeichnung: 'Steckdosen Wohnzimmer Nord $i', schutzId: 'ls$i', leistung: 1500),
    Stromkreis(id: 'kb', schrankId: 's', nummer: '20', bezeichnung: 'Bad', schutzId: 'fils'),
    Stromkreis(id: 'kh', schrankId: 's', nummer: '21', bezeichnung: 'Herd', schutzId: 'herd', leitung: 'NYM-J 5x2,5', querschnitt: 250),
    Stromkreis(id: 'kx', schrankId: 's', nummer: '99', bezeichnung: 'ohne Schutz'),
  ];
  return (geraete, kreise);
}

const _verbraucher = <String, List<SlpVerbraucher>>{
  'k0': [
    (kennung: 'SD-01', kuerzel: 'SD', typ: 'Steckdose', raum: 'Wohnen', knxKanal: null),
    (kennung: 'SD-02', kuerzel: 'SD', typ: 'Steckdose', raum: 'Wohnen', knxKanal: null),
  ],
  'k1': [(kennung: 'LE-01', kuerzel: 'LE', typ: 'Leuchte', raum: 'Küche', knxKanal: 'k1:A')],
};

void main() {
  test('Stromlaufplan: Blätter, Querverweise, Betriebsmittelliste, Hinweise', () {
    final (geraete, kreise) = _beispiel();
    final plan = stromlaufplanErzeugen(schrank: _schrank, geraete: geraete, kreise: kreise, verbraucher: _verbraucher, projekt: 'Haus', datum: DateTime(2026, 11, 8));
    // Einspeisung, SPD, FI + 4 LS, FI/LS, Herd = 9 Spalten → ein Stromkreisblatt + Liste
    expect(plan.blaetter.map((b) => b.titel), ['Einspeisung und Stromkreise', 'Betriebsmittelliste']);
    expect(plan.orte['q1'], ['1.1']);
    expect(plan.orte['spd'], ['1.2']);
    expect(plan.orte['fi1'], ['1.3']);
    expect(plan.orte['ls0'], ['1.4']);
    expect(plan.orte['ls3'], ['1.7']);
    expect(plan.orte['fils'], ['1.8']);
    expect(plan.orte['herd'], ['1.9']);
    expect(plan.orte['k1'], ['1.5:A']); // Aktorkontakt im Pfad von SK 2
    expect(plan.orte['x1'], ['1.4']);
    expect(plan.hinweise.single, contains('Stromkreis 99'));
    String texte(SlpBlatt b) => [for (final z in b.zeichen) if (z is ZText) z.text].join('|');
    final t1 = texte(plan.blaetter.first);
    expect(t1, contains('-F10'));
    expect(t1, contains('SK 1'));
    expect(t1, contains('2x SD'));
    expect(t1, contains('-W21'));
    expect(t1, contains('1 von 2'));
    expect(t1, contains('=UV1 UV Erdgeschoss'));
    final liste = texte(plan.blaetter.last);
    expect(liste, contains('=UV1-F10'));
    expect(liste, contains('/1.5:A'));
    expect(liste, contains('PA 1.1.10'));
    expect(liste, contains('Hinweise'));
    // Alles liegt innerhalb des Blattes.
    for (final b in plan.blaetter) {
      for (final z in b.zeichen) {
        if (z is ZLinie) {
          expect(z.x1 >= 0 && z.x2 <= blattBreite && z.y1 >= 0 && z.y2 <= blattHoehe, isTrue);
        }
      }
    }
  });

  test('Große FI-Gruppe läuft auf das nächste Blatt weiter', () {
    final (geraete, kreise) = _beispiel(lsAnzahl: 16);
    final plan = stromlaufplanErzeugen(schrank: _schrank, geraete: geraete, kreise: kreise, verbraucher: _verbraucher);
    expect(plan.blaetter.length, 3);
    expect(plan.orte['ls10'], ['1.14']);
    expect(plan.orte['ls11'], ['2.1']);
    final t2 = [for (final z in plan.blaetter[1].zeichen) if (z is ZText) z.text];
    expect(t2, contains('von /1 (-F2)'));
    final t1 = [for (final z in plan.blaetter[0].zeichen) if (z is ZText) z.text];
    expect(t1, contains('/2.1'));
  });

  test('Phase am falschen FI wird gemeldet', () {
    final geraete = [
      _g('fi', GeraeteArt.rcd, '-F1', phase: 'L1'),
      _g('ls', GeraeteArt.ls, '-F2', pos: 2, phase: 'L3', vor: 'fi'),
    ];
    final plan = stromlaufplanErzeugen(schrank: _schrank, geraete: geraete, kreise: const []);
    expect(plan.hinweise.single, contains('-F2'));
    expect(umbrechen('Steckdosen Wohnzimmer Nord und Süd und noch mehr', 12, maxZeilen: 2).length, 2);
  });

  test('PDF und Bildschirmbild entstehen', () async {
    final (geraete, kreise) = _beispiel(lsAnzahl: 16);
    final plan = stromlaufplanErzeugen(schrank: _schrank, geraete: geraete, kreise: kreise, verbraucher: _verbraucher, projekt: 'Haus Muster');
    final pdf = await stromlaufplanPdf(plan);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final ziel = Platform.environment['BAUSPUR_BILD'];
    if (ziel != null) {
      final arial = File('C:/Windows/Fonts/arial.ttf');
      if (arial.existsSync()) await (FontLoader('Arial')..addFont(Future.value(ByteData.sublistView(arial.readAsBytesSync())))).load();
      File('$ziel/stromlaufplan.pdf').writeAsBytesSync(pdf);
      for (final b in plan.blaetter) {
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        c.drawRect(const Rect.fromLTWH(0, 0, 420 * 4, 297 * 4), Paint()..color = Colors.white);
        SlpPainter(b, 4, schrift: 'Arial').paint(c, const Size(420 * 4, 297 * 4));
        final img = await rec.endRecording().toImage(420 * 4, 297 * 4);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$ziel/blatt${b.nr}.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
    }
  });
}
