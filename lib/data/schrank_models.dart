import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// Art eines Schranks.
enum SchrankArt {
  zaehlerschrank('Zählerschrank'),
  unterverteiler('Unterverteiler'),
  netzwerk('Netzwerkschrank'),
  sonstiges('Sonstiger Schrank');

  const SchrankArt(this.label);
  final String label;
}

/// Gerätearten auf der Hutschiene mit Kennbuchstaben (DIN EN 81346-2) und
/// üblicher Breite in Teilungseinheiten (TE, 17,5 mm) je Pol.
enum GeraeteArt {
  hauptschalter('Hauptschalter', 'Q', 1, 3),
  rcd('FI / RCD', 'F', 0, 4),
  ls('Leitungsschutzschalter', 'F', 1, 1),
  fils('FI/LS', 'F', 0, 2),
  spd('Überspannungsschutz', 'F', 0, 4),
  knx('KNX-Aktor / -Gerät', 'K', 0, 4),
  netzteil('Netzteil', 'T', 0, 4),
  relais('Relais / Schütz', 'K', 0, 1),
  klemme('Reihenklemme', 'X', 0, 1),
  sonstiges('Sonstiges', 'U', 0, 2);

  const GeraeteArt(this.label, this.buchstabe, this.tePol, this.teFest);
  final String label;
  final String buchstabe;

  /// Breite je Pol (0 = feste Breite [teFest]).
  final int tePol;
  final int teFest;

  int breite(int pole) => tePol > 0 ? tePol * pole : teFest;
  bool get istSchutz => this == ls || this == fils || this == rcd || this == hauptschalter;
}

class Schrank {
  Schrank({
    required this.id,
    required this.geschossId,
    required this.objektId,
    required this.name,
    required this.kennzeichen,
    required this.art,
    required this.reihen,
    required this.teJeReihe,
    this.eigenschaften = const {},
  });

  final String id;
  final String? geschossId;
  final String? objektId; // Verteiler-Objekt im Grundriss
  final String name;
  final String kennzeichen; // z. B. UV1 → Betriebsmittel =UV1-F3
  final SchrankArt art;
  final int reihen;
  final int teJeReihe;
  final Map<String, dynamic> eigenschaften;

  static Schrank ausZeile(Row r) => Schrank(
        id: r['id'] as String,
        geschossId: r['geschoss_id'] as String?,
        objektId: r['objekt_id'] as String?,
        name: r['name'] as String,
        kennzeichen: r['kennzeichen'] as String,
        art: SchrankArt.values.where((a) => a.name == r['art']).firstOrNull ?? SchrankArt.unterverteiler,
        reihen: r['reihen'] as int,
        teJeReihe: r['te_je_reihe'] as int,
        eigenschaften: jsonDecode(r['eigenschaften'] as String? ?? '{}') as Map<String, dynamic>,
      );
}

class SchrankGeraet {
  SchrankGeraet({
    required this.id,
    required this.schrankId,
    required this.reihe,
    required this.position,
    required this.breite,
    required this.art,
    required this.kennzeichen,
    this.bezeichnung = '',
    this.pole = 1,
    this.nennstrom,
    this.charakteristik,
    this.fehlerstrom,
    this.phase,
    this.vorgeschaltetId,
    this.produktId,
    this.eigenschaften = const {},
  });

  final String id;
  final String schrankId;
  final int reihe; // 0 = oberste Reihe
  final int position; // erste belegte TE in der Reihe (0 …)
  final int breite; // TE
  final GeraeteArt art;
  final String kennzeichen; // z. B. -F3
  final String bezeichnung;
  final int pole;
  final int? nennstrom; // A
  final String? charakteristik; // B, C, …
  final int? fehlerstrom; // mA (RCD, FI/LS)
  final String? phase; // L1, L2, L3, 3P
  final String? vorgeschaltetId; // z. B. RCD vor einem LS
  final String? produktId;
  final Map<String, dynamic> eigenschaften;

  int get ende => position + breite; // erste freie TE dahinter

  /// Kurzbeschriftung, z. B. „B16“, „40 A / 30 mA“.
  String get kurz => switch (art) {
        GeraeteArt.ls => '${charakteristik ?? 'B'}${nennstrom ?? 16}',
        GeraeteArt.fils => '${charakteristik ?? 'B'}${nennstrom ?? 16} ${fehlerstrom ?? 30} mA',
        GeraeteArt.rcd => '${nennstrom ?? 40} A ${fehlerstrom ?? 30} mA',
        GeraeteArt.hauptschalter => '${nennstrom ?? 63} A',
        _ => bezeichnung.isEmpty ? art.label : bezeichnung,
      };

  static SchrankGeraet ausZeile(Row r) => SchrankGeraet(
        id: r['id'] as String,
        schrankId: r['schrank_id'] as String,
        reihe: r['reihe'] as int,
        position: r['position'] as int,
        breite: r['breite'] as int,
        art: GeraeteArt.values.where((a) => a.name == r['art']).firstOrNull ?? GeraeteArt.sonstiges,
        kennzeichen: r['kennzeichen'] as String,
        bezeichnung: r['bezeichnung'] as String? ?? '',
        pole: r['pole'] as int? ?? 1,
        nennstrom: r['nennstrom'] as int?,
        charakteristik: r['charakteristik'] as String?,
        fehlerstrom: r['fehlerstrom'] as int?,
        phase: r['phase'] as String?,
        vorgeschaltetId: r['vorgeschaltet_id'] as String?,
        produktId: r['produkt_id'] as String?,
        eigenschaften: jsonDecode(r['eigenschaften'] as String? ?? '{}') as Map<String, dynamic>,
      );
}

class Stromkreis {
  Stromkreis({
    required this.id,
    required this.schrankId,
    required this.nummer,
    this.bezeichnung = '',
    this.schutzId,
    this.querschnitt = 150,
    this.leitung = 'NYM-J 3x1,5',
    this.leistung = 0,
  });

  final String id;
  final String schrankId;
  final String nummer; // z. B. 1, 2, 3 …
  final String bezeichnung;
  final String? schutzId; // LS oder FI/LS
  final int querschnitt; // Hundertstel mm² (150 = 1,5 mm²)
  final String leitung;
  final int leistung; // geschätzte Last in W

  String get querschnittText => '${(querschnitt / 100).toStringAsFixed(querschnitt % 100 == 0 ? 0 : 1).replaceAll('.', ',')} mm²';

  static Stromkreis ausZeile(Row r) => Stromkreis(
        id: r['id'] as String,
        schrankId: r['schrank_id'] as String,
        nummer: r['nummer'] as String,
        bezeichnung: r['bezeichnung'] as String? ?? '',
        schutzId: r['schutz_id'] as String?,
        querschnitt: r['querschnitt'] as int? ?? 150,
        leitung: r['leitung'] as String? ?? '',
        leistung: r['leistung_w'] as int? ?? 0,
      );
}
