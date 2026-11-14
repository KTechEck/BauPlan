import 'package:bauspur/core/bauelemente.dart';
import 'package:bauspur/core/kanal_montage.dart';
import 'package:bauspur/core/kennung.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kabelkanal: Innen- und Außenecken, Endkappen, Stoßstellen', () {
    const raum = [Punkt(0, 0), Punkt(4000, 0), Punkt(4000, 3000), Punkt(0, 3000)];
    // an zwei Wänden entlang durch die Raumecke (4000|0): Innenecke
    final m = kanalFormteile(const [Punkt(1000, 20), Punkt(3980, 20), Punkt(3980, 2000)], raeume: const [raum]);
    expect(m['Innenecke'], 1);
    expect(m['Endkappe'], 2);
    expect(m['Stoßstellenabdeckung'], 2); // 4,96 m bei 2-m-Stangen
    // L-förmiger Raum: um die vorspringende Ecke (2000|1500) herum = Außenecke
    const l = [Punkt(0, 0), Punkt(4000, 0), Punkt(4000, 1500), Punkt(2000, 1500), Punkt(2000, 3000), Punkt(0, 3000)];
    final a = kanalFormteile(const [Punkt(3500, 1480), Punkt(1980, 1480), Punkt(1980, 2500)], raeume: const [l]);
    expect(a['Außenecke'], 1);
    // in der Wandansicht von waagerecht nach senkrecht: Flachwinkel
    final f = kanalFormteile(const [Punkt(0, 20), Punkt(1000, 20), Punkt(1000, 20)], z: const [1000, 1000, 2000]);
    expect(f['Flachwinkel'], 1);
  });

  test('Füllgrad und Befestigungsabstände', () {
    const k = KanalMasse(40, 40);
    final f = kanalFuellgrad(k, List.filled(10, 9.5));
    expect(f, closeTo(10 * 3.14159 * 9.5 * 9.5 / 4 / (36 * 36), 0.01));
    expect(fuellgradHinweis(0.3), isNull);
    expect(fuellgradHinweis(0.8), contains('Reserve'));
    expect(befestigungsabstand('Kupferrohr', 15), 1250);
    expect(befestigungsabstand('HT-Abwasserrohr', 50), 500);
    expect(befestigungsabstand('HT-Abwasserrohr', 50, senkrecht: true), 2000);
    expect(schellenAnzahl(const [Punkt(0, 0), Punkt(3000, 0)], 1000, 1500), 4);
    expect(schienenHalter(2000, halterAbstand: 1000), 3);
  });

  test('Gerätekategorien haben die gemeinsamen Gerätedaten, Kabelkanal/Montage sind Material', () {
    for (final k in [BauelementKategorie.elektro, BauelementKategorie.technik, BauelementKategorie.sanitaer, BauelementKategorie.leuchte]) {
      final keys = [for (final f in k.felder) f.schluessel];
      expect(keys, contains('einbauhoehe'), reason: k.name);
      expect(keys.toSet().length, keys.length, reason: 'doppelte Felder in ${k.name}');
    }
    expect(BauelementKategorie.kabelkanal.gruppe, BauelementGruppe.material);
    expect([for (final f in BauelementKategorie.montage.felder) f.schluessel], contains('halterabstand'));
  });

  test('Kennungsschema einstellbar', () {
    expect(naechsteKennung(geschoss: 'EG', raum: 'BAD', typ: 'SD', vorhandene: const ['EG-BAD-SD-01']), 'EG-BAD-SD-02');
    expect(naechsteKennung(geschoss: 'EG', raum: 'BAD', typ: 'SD', vorhandene: const [], trenner: '.', stellen: 3, mitRaum: false, praefix: 'hh'), 'HH.EG.SD.001');
  });
}
