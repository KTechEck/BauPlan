import 'dart:math' as math;

import 'raumerkennung.dart';

/// Raumweise Heizlast, vereinfacht nach DIN EN 12831-1 / DIN/TS 12831-1:
/// Transmission über Außenwände, Fenster/Türen, Boden und Decke, Wände zu
/// anders beheizten Nachbarräumen, pauschaler Wärmebrückenzuschlag ΔU_WB und
/// Lüftung mit Mindestluftwechsel. Keine Aufheizleistung.

/// Lage eines Boden- oder Deckenbauteils.
enum Gegen {
  beheizt('beheizter Raum'),
  unbeheizt('unbeheizter Raum (Keller, Dachboden)'),
  aussen('Außenluft (Dach, Auskragung)'),
  erdreich('Erdreich');

  const Gegen(this.label);
  final String label;
}

/// Bauteilaufbau (Decke, Boden, Dach) aus Schichten oben → unten.
class Aufbau {
  Aufbau({required this.id, required this.name, required this.art, required this.schichten});
  final String id;
  final String name;
  final Gegen art; // wogegen das Bauteil typischerweise grenzt
  final List<(String, int)> schichten; // Material-ID, Dicke mm

  int get dicke => schichten.fold(0, (s, x) => s + x.$2);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'art': art.name,
        'schichten': [for (final s in schichten) {'material': s.$1, 'dicke': s.$2}],
      };

  static Aufbau ausJson(Map<String, dynamic> m) => Aufbau(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        art: Gegen.values.where((g) => g.name == m['art']).firstOrNull ?? Gegen.beheizt,
        schichten: [
          for (final s in (m['schichten'] as List? ?? const []))
            ((s as Map)['material'] as String, (s['dicke'] as num).toInt()),
        ],
      );

  /// U-Wert mit Übergangswiderständen je nach Lage und Wärmestromrichtung.
  double uWert(double Function(String materialId) lambda, {bool alsDecke = true}) {
    var r = 0.0;
    for (final s in schichten) {
      r += s.$2 / 1000 / lambda(s.$1);
    }
    // Decke: Wärmestrom nach oben (Rsi 0,10); Boden: nach unten (Rsi 0,17)
    final rsi = alsDecke ? 0.10 : 0.17;
    final rse = switch (art) {
      Gegen.aussen => 0.04,
      Gegen.erdreich => 0.0,
      _ => alsDecke ? 0.10 : 0.17,
    };
    return 1 / (rsi + rse + r);
  }
}

/// Raumdaten für die Berechnung.
class HlRaum {
  HlRaum({
    required this.id,
    required this.name,
    required this.umriss,
    required this.hoehe,
    this.temperatur = 20,
    this.luftwechsel = 0.5,
    this.boden = Gegen.beheizt,
    this.uBoden = 0,
    this.decke = Gegen.beheizt,
    this.uDecke = 0,
    this.beheizt = true,
  });

  final String id;
  final String name;
  final List<Punkt> umriss; // mm
  final int hoehe; // lichte Höhe mm
  final double temperatur;
  final double luftwechsel; // 1/h
  final Gegen boden, decke;
  final double uBoden, uDecke;
  final bool beheizt;

  double get flaeche => polygonFlaeche(umriss).abs() / 1e6; // m²
  double get volumen => flaeche * hoehe / 1000; // m³
}

class HlWand {
  HlWand({required this.id, required this.a, required this.b, required this.dicke, required this.u, this.uInnen});
  final String id;
  final Punkt a, b;
  final int dicke;
  final double u; // U als Außenwand
  final double? uInnen; // U als Innenwand (andere Übergänge), sonst wie u
  double get laenge => math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
}

class HlOeffnung {
  HlOeffnung({required this.wandId, required this.abstand, required this.breite, required this.hoehe, required this.u, this.name = ''});
  final String wandId;
  final int abstand, breite, hoehe;
  final double u;
  final String name;
  double get flaeche => breite * hoehe / 1e6;
}

/// Einstellungen der Berechnung.
class HlParameter {
  const HlParameter({this.normAussen = -12, this.jahresmittel = 9, this.unbeheizt = 5, this.deltaUwb = 0.05});
  final double normAussen; // θe
  final double jahresmittel; // θm,e für Erdreich
  final double unbeheizt; // Temperatur unbeheizter Nachbarräume
  final double deltaUwb; // pauschaler Wärmebrückenzuschlag W/(m²K)
}

/// Ein Transmissionsposten.
class HlPosten {
  HlPosten(this.bauteil, this.flaeche, this.u, this.deltaT, this.leistung);
  final String bauteil;
  final double flaeche, u, deltaT, leistung;
}

class HlErgebnis {
  HlErgebnis(this.raum, this.posten, this.lueftung);
  final HlRaum raum;
  final List<HlPosten> posten;
  final double lueftung;
  double get transmission => posten.fold(0, (s, p) => s + p.leistung);
  double get gesamt => transmission + lueftung;
  double get proQm => raum.flaeche == 0 ? 0 : gesamt / raum.flaeche;
}

/// Seiten einer Wand abtasten: welcher Raum liegt links/rechts in jedem Abschnitt.
List<(double von, double bis, String? links, String? rechts)> wandSeiten(HlWand w, List<HlRaum> raeume, {double schritt = 100}) {
  final l = w.laenge;
  if (l < 1) return const [];
  final ux = (w.b.x - w.a.x) / l, uy = (w.b.y - w.a.y) / l;
  final nx = -uy, ny = ux; // links
  final abstand = w.dicke / 2 + 40;
  String? raumAn(Punkt p) => raeume.where((r) => r.umriss.length >= 3 && punktInPolygon(p, r.umriss)).firstOrNull?.id;
  final abschnitte = <(double, double, String?, String?)>[];
  final n = math.max(1, (l / schritt).ceil());
  for (var i = 0; i < n; i++) {
    final s0 = i * l / n, s1 = (i + 1) * l / n, sm = (s0 + s1) / 2;
    final px = w.a.x + ux * sm, py = w.a.y + uy * sm;
    final li = raumAn(Punkt(px + nx * abstand, py + ny * abstand));
    final re = raumAn(Punkt(px - nx * abstand, py - ny * abstand));
    if (abschnitte.isNotEmpty && abschnitte.last.$3 == li && abschnitte.last.$4 == re) {
      abschnitte[abschnitte.length - 1] = (abschnitte.last.$1, s1, li, re);
    } else {
      abschnitte.add((s0, s1, li, re));
    }
  }
  return abschnitte;
}

/// Heizlast aller Räume eines Geschosses.
List<HlErgebnis> heizlastBerechnen(List<HlRaum> raeume, List<HlWand> waende, List<HlOeffnung> oeffnungen, HlParameter p) {
  final nachId = {for (final r in raeume) r.id: r};
  final posten = {for (final r in raeume) r.id: <HlPosten>[]};
  final aussenFlaeche = {for (final r in raeume) r.id: 0.0};
  double temp(String? id) {
    final r = nachId[id];
    if (r == null) return p.normAussen;
    return r.beheizt ? r.temperatur : p.unbeheizt;
  }

  for (final w in waende) {
    final seiten = wandSeiten(w, raeume);
    final oe = oeffnungen.where((o) => o.wandId == w.id).toList();
    for (final (von, bis, links, rechts) in seiten) {
      for (final (raumId, anderer) in [(links, rechts), (rechts, links)]) {
        final r = nachId[raumId];
        if (r == null || !r.beheizt) continue;
        final aussen = anderer == null;
        final dT = r.temperatur - temp(anderer);
        // Öffnungen in diesem Abschnitt
        var aOeffnung = 0.0;
        for (final o in oe) {
          final mitte = o.abstand + o.breite / 2;
          if (mitte < von || mitte >= bis) continue;
          aOeffnung += o.flaeche;
          if (dT.abs() > 0.01) {
            posten[r.id]!.add(HlPosten(o.name.isEmpty ? (aussen ? 'Fenster/Tür außen' : 'Tür innen') : o.name, o.flaeche, o.u, dT, o.flaeche * o.u * dT));
          }
          if (aussen) aussenFlaeche[r.id] = aussenFlaeche[r.id]! + o.flaeche;
        }
        final a = math.max(0.0, (bis - von) / 1000 * r.hoehe / 1000 - aOeffnung);
        if (a <= 0 || dT.abs() < 0.01) continue;
        final u = aussen ? w.u : (w.uInnen ?? w.u);
        final bez = aussen ? 'Außenwand' : 'Innenwand zu ${nachId[anderer]?.name ?? '?'}';
        posten[r.id]!.add(HlPosten(bez, a, u, dT, a * u * dT));
        if (aussen) aussenFlaeche[r.id] = aussenFlaeche[r.id]! + a;
      }
    }
  }
  final ergebnisse = <HlErgebnis>[];
  for (final r in raeume.where((r) => r.beheizt)) {
    final l = posten[r.id]!;
    for (final (bez, gegen, u) in [('Boden', r.boden, r.uBoden), ('Decke', r.decke, r.uDecke)]) {
      if (gegen == Gegen.beheizt || u <= 0) continue;
      final a = r.flaeche;
      switch (gegen) {
        case Gegen.erdreich:
          final dT = r.temperatur - p.jahresmittel;
          l.add(HlPosten('$bez gegen Erdreich (fg1 1,45)', a, u, dT, 1.45 * a * u * dT));
        case Gegen.aussen:
          final dT = r.temperatur - p.normAussen;
          l.add(HlPosten('$bez gegen außen', a, u, dT, a * u * dT));
          aussenFlaeche[r.id] = aussenFlaeche[r.id]! + a;
        case Gegen.unbeheizt:
          final dT = r.temperatur - p.unbeheizt;
          l.add(HlPosten('$bez gegen unbeheizt', a, u, dT, a * u * dT));
        case Gegen.beheizt:
          break;
      }
    }
    final aA = aussenFlaeche[r.id]!;
    if (aA > 0 && p.deltaUwb > 0) {
      final dT = r.temperatur - p.normAussen;
      l.add(HlPosten('Wärmebrücken pauschal (ΔU ${p.deltaUwb.toStringAsFixed(2)})', aA, p.deltaUwb, dT, aA * p.deltaUwb * dT));
    }
    final lueftung = 0.34 * r.luftwechsel * r.volumen * (r.temperatur - p.normAussen);
    ergebnisse.add(HlErgebnis(r, l, lueftung));
  }
  return ergebnisse;
}

/// Norm-Innentemperatur nach Raumname (DIN/TS 12831-1, Wohngebäude).
double innenTemperaturVorschlag(String raumname) {
  final n = raumname.toLowerCase();
  if (n.contains('bad') || n.contains('dusche')) return 24;
  if (n.contains('flur') || n.contains('diele') || n.contains('treppe')) return 20;
  if (n.contains('abstell') || n.contains('lager') || n.contains('hwr') || n.contains('technik')) return 15;
  if (n.contains('keller') || n.contains('garage')) return 10;
  return 20;
}

/// Mindestluftwechsel nach Raumart (vereinfachte Richtwerte).
double luftwechselVorschlag(String raumname) {
  final n = raumname.toLowerCase();
  if (n.contains('bad') || n.contains('wc') || n.contains('dusche')) return 1.5;
  if (n.contains('küche') || n.contains('kueche')) return 1.0;
  return 0.5;
}

/// Leistung eines Heizkörpers bei anderen Systemtemperaturen (EN 442):
/// Q = Qn · (ΔT_ln / 49,83)^n.
double heizkoerperLeistung(double qNorm, double exponent, double vorlauf, double ruecklauf, double raum) {
  if (vorlauf <= raum || ruecklauf <= raum || vorlauf <= ruecklauf) return 0;
  final dtLn = (vorlauf - ruecklauf) / math.log((vorlauf - raum) / (ruecklauf - raum));
  return qNorm * math.pow(dtLn / 49.83, exponent);
}
