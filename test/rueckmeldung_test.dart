import 'dart:io';

import 'package:bauspur/core/anschluesse.dart';
import 'package:bauspur/core/height.dart';
import 'package:bauspur/core/leitungsnetz.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/verteiler.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bauspur_rm_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  (ProjectStore, String) neu() {
    final s = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'R');
    return (s, s.geschosse(s.gebaeude().single.id).single.id);
  }

  Objekt linie(String id, List<Punkt> p, {Map<String, dynamic> e = const {}}) => Objekt(
        id: id,
        typId: 't',
        geschossId: 'g',
        raumId: null,
        kennung: id.toUpperCase(),
        punkte: p,
        z: 0,
        zBezug: Hoehenbezug.rfb,
        lage: null,
        status: ObjektStatus.geplant,
        normkennzeichen: null,
        eigenschaften: e,
      );

  group('Wände', () {
    test('Wandlänge über den Eckpunkt: Nachbarwand behält ihre Richtung, Winkel ändert sich', () {
      final (s, g) = neu();
      final a = s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 4000, y2: 0, dicke: 200);
      final b = s.wandAnlegen(geschossId: g, x1: 4000, y1: 0, x2: 4000, y2: 3000, dicke: 200);
      final alt = s.wandEckeVerschieben(a, 5000);
      expect(alt.length, 2);
      final wa = s.waende(g).firstWhere((w) => w.id == a), wb = s.waende(g).firstWhere((w) => w.id == b);
      expect(wa.laenge, closeTo(5000, 1.5));
      expect(wa.x2, 4000); // Ecke gleitet entlang der senkrechten Nachbarwand
      expect(wb.x1, 4000);
      expect(wb.y1, wa.y2);
      expect((wb.x2, wb.y2), (4000, 3000));
      s.waendeKoordinatenSetzen(alt);
      expect(s.waende(g).firstWhere((w) => w.id == a).x2, 4000);
      expect(s.waende(g).firstWhere((w) => w.id == a).y2, 0);
      s.schliessen();
    });

    test('Wandende versetzen nimmt anschließende Wände mit', () {
      final (s, g) = neu();
      final a = s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 4000, y2: 0, dicke: 200);
      s.wandAnlegen(geschossId: g, x1: 4000, y1: 0, x2: 4000, y2: 3000, dicke: 200);
      final alt = s.wandEndeVersetzen(a, amAnfang: false, x: 4500, y: 500);
      expect(alt.length, 2);
      expect(s.waende(g).where((w) => w.x1 == 4500 && w.y1 == 500).length, 1);
      s.schliessen();
    });

    test('Bemaßung an einer Laibung verschiebt die Öffnung', () {
      final (s, g) = neu();
      final w = s.wandAnlegen(geschossId: g, x1: 0, y1: 0, x2: 5000, y2: 0, dicke: 200);
      final o = s.oeffnungAnlegen(wandId: w, art: OeffnungsArt.tuer, abstand: 1000, breite: 885, hoehe: 2010);
      // Maß von der Wandkante (Anfang, Seite +y) bis zur linken Laibung
      final b = s.bemassungAnlegen(geschossId: g, x1: 0, y1: 100, x2: 1000, y2: 100, abstand: 300);
      final zurueck = s.bemassungAendern(b, 1200);
      expect(zurueck, isNotNull);
      expect(s.oeffnungen(g).firstWhere((e) => e.id == o).abstand, 1200);
      zurueck!();
      expect(s.oeffnungen(g).firstWhere((e) => e.id == o).abstand, 1000);
      s.schliessen();
    });

    test('Bodenplatte (Balkon) ohne Wände bleibt beim Abgleich erhalten', () {
      final (s, g) = neu();
      final id = s.bodenplatteAnlegen(
          geschossId: g,
          name: 'Balkon',
          kuerzel: 'BAL',
          art: RaumArt.balkon,
          umriss: const [Punkt(0, 0), Punkt(3000, 0), Punkt(3000, 1500), Punkt(0, 1500)]);
      s.wandAnlegen(geschossId: g, x1: 0, y1: -100, x2: 3000, y2: -100, dicke: 200); // löst Abgleich aus
      final r = s.raeume(g).firstWhere((e) => e.id == id);
      expect(r.art, RaumArt.balkon);
      expect(r.istBodenplatte, isTrue);
      expect(r.flaeche, closeTo(4.5e6, 1));
      s.raumArtSetzen(id, RaumArt.terrasse);
      expect(s.raeume(g).single.art, RaumArt.terrasse);
      s.schliessen();
    });

    test('Neues Projekt hat Wanddurchbruch und Heizrohr', () {
      final (s, _) = neu();
      final k = s.objekttypen().map((t) => t.kuerzel).toSet();
      expect(k.containsAll({'WD', 'HR'}), isTrue);
      s.schliessen();
    });
  });

  group('Leitungen', () {
    test('Leitungszug folgt den Bezügen an Anfang und Ende', () {
      final a = linie('a', const [Punkt(0, 0), Punkt(1000, 0)]);
      final b = linie('b', const [Punkt(1000, 0), Punkt(1000, 2000)], e: {
        'anfang': {'leitung': 'a'}
      });
      final c = linie('c', const [Punkt(1000, 2000), Punkt(3000, 2000)], e: {
        'anfang': {'leitung': 'b'}
      });
      final x = linie('x', const [Punkt(0, 500), Punkt(500, 500)]);
      expect(leitungsZug('a', [a, b, c, x]), {'a', 'b', 'c'});
      expect(leitungsZug('x', [a, b, c, x]), {'x'});
    });

    test('Bündel: deckungsgleiche Strecken bekommen unterschiedlichen Versatz', () {
      final v = buendelVersatz([
        const [Offset(0, 0), Offset(1000, 0)],
        const [Offset(200, 2), Offset(800, 2)],
        const [Offset(0, 500), Offset(1000, 500)],
      ]);
      expect(v[(0, 0)], isNot(v[(1, 0)]));
      expect(v.containsKey((2, 0)), isFalse);
      final z = versetzterZug(const [Offset(0, 0), Offset(100, 0)], 0, {(0, 0): 1}, 4);
      expect(z.first.dy.abs(), 4);
    });

    test('Verteiler hat je Abgang einen VL- und RL-Anschluss', () {
      final d = VerteilerDaten(abgaenge: 5);
      final a = anschluesse('HV', d.toJson());
      expect(a.where((e) => e.dz == 0).length, 10);
      expect(a.map((e) => e.name), containsAll(['1 VL', '1 RL', '5 VL', '5 RL', 'Zuleitung VL']));
      // Anschlüsse liegen innerhalb des Schranks
      for (final e in a) {
        expect(e.dx.abs(), lessThanOrEqualTo(d.schrankBreite / 2));
      }
      const wand = (a: Punkt(0, 0), b: Punkt(4000, 0), dicke: 240.0);
      final p = verteilerAnschlussPunkte(const Punkt(2000, 200), d, [wand]);
      expect(p.length, 10);
      expect(p.every((e) => (e.$2.y - 120).abs() < 0.01), isTrue); // Vorderkante Unterputz = Wandoberfläche
    });
  });

  group('Verteiler-Ausstattung', () {
    test('Ventiltypen und Zusatzausstattung: JSON, Stückliste, Hinweise', () {
      final d = VerteilerDaten(abgaenge: 4, pumpe: true, mischer: true)
        ..vorlaufVentil = 'Regulierventil mit Skala'
        ..ruecklaufVentil = 'Handregulierventil'
        ..thermometer = true;
      final z = VerteilerDaten.ausJson(d.toJson());
      expect(z.vorlaufVentil, 'Regulierventil mit Skala');
      expect(z.ruecklaufVentil, 'Handregulierventil');
      expect(z.durchflussmesser, isFalse);
      final liste = {for (final (t, n) in z.stueckliste()) t: n};
      expect(liste['Thermometer Vor-/Rücklauf'], 2);
      expect(liste['Regulierventil mit Skala (Vorlauf)'], 4);
      expect(z.hinweise().length, 3); // STB fehlt, Überström fehlt, Handventil mit Antrieb
      z
        ..temperaturbegrenzer = true
        ..ueberstroemventil = true
        ..ruecklaufVentil = ruecklaufVentile.first;
      expect(z.hinweise(), isEmpty);
    });

    test('Altdaten ohne Ventiltyp: Durchflussmesser-Schalter wird übernommen', () {
      expect(VerteilerDaten.ausJson({'durchflussmesser': false}).vorlaufVentil, 'keines');
      expect(VerteilerDaten.ausJson({}).vorlaufVentil, vorlaufVentile.first);
    });
  });
}
