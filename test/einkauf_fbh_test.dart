import 'package:bauspur/core/bauelemente.dart';
import 'package:bauspur/core/einkauf.dart';
import 'package:bauspur/core/fbh.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/bauelement_bibliothek.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kassenzettel ohne KI lesen', () {
    const bon = 'BAUMARKT MUSTER\n'
        '4006543 3 x Styrodur 2800 C 20mm   38,97\n'
        'Leerrohr M20 25m        12,49 A\n'
        '2 St UP-Dose 60mm tief   3,58\n'
        'Zwischensumme           55,04\n'
        'MwSt 19%                 8,79\n'
        'EC-Karte                55,04\n';
    final l = kassenzettelLesen(bon);
    expect(l.length, 3);
    expect(l.first.menge, 3);
    expect(l.first.text, contains('Styrodur'));
    expect(l.first.preisCent, 3897);
    expect(l[2].menge, 2);
    expect(l[2].einheit, 'Stk');
  });

  test('KI-Antwort zum Kassenzettel, Zuordnung und Kategorie', () {
    final r = kiKassenzettelLesen('{"haendler":"Bauhaus","datum":"2026-11-08","positionen":[{"text":"Kompriband 15/3","menge":"2","einheit":"Rolle","preis":"19,98"}]}')!;
    expect(r.haendler, 'Bauhaus');
    expect(r.datum, DateTime(2026, 11, 8));
    expect(r.positionen.single.menge, 2);
    expect(r.positionen.single.preisCent, 1998);
    final bib = materialBeispiele();
    expect(elementVorschlagen('Leerrohr flexibel M20 grau 50m', bib)?.id, 'bsp-mat-m20');
    expect(elementVorschlagen('Banane', bib), isNull);
    expect(kategorieRaten('Styrodur 2800 C 40 mm'), BauelementKategorie.daemmstoff);
    expect(kategorieRaten('NYM-J 5x2,5 50m'), BauelementKategorie.kabel);
    expect(kategorieRaten('Bit-Satz 32-teilig Bohrer'), BauelementKategorie.werkzeug);
  });

  test('Heizkreis-Zugang entlang des Umrisses', () {
    const q = [Punkt(0, 0), Punkt(4000, 0), Punkt(4000, 3000), Punkt(0, 3000)];
    final z = heizkreisZugang(q, 0.5 * 4000 / 14000); // Mitte der ersten Kante
    expect(z.mitte.x, closeTo(2000, 1));
    expect(z.vl.x, closeTo(1925, 1));
    expect(z.rl.x, closeTo(2075, 1));
    expect(zugangAnteil(q, const Punkt(4100, 1500)), closeTo((4000 + 1500) / 14000, 0.001));
  });
}
