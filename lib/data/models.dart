import 'dart:convert';
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import '../core/height.dart';
import '../core/raumerkennung.dart';

class Gebaeude {
  Gebaeude(this.id, this.name);
  final String id;
  final String name;

  static Gebaeude ausZeile(Row r) => Gebaeude(r['id'] as String, r['name'] as String);
}

class Geschoss {
  Geschoss({
    required this.id,
    required this.gebaeudeId,
    required this.name,
    required this.kuerzel,
    required this.hoehen,
  });

  final String id;
  final String gebaeudeId;
  final String name;
  final String kuerzel;
  final Bezugshoehen hoehen;

  static Geschoss ausZeile(Row r) => Geschoss(
        id: r['id'] as String,
        gebaeudeId: r['gebaeude_id'] as String,
        name: r['name'] as String,
        kuerzel: r['kuerzel'] as String,
        hoehen: Bezugshoehen(
          rfb: r['rfb_mm'] as int,
          ffb: r['ffb_mm'] as int,
          rohdecke: r['rohdecke_mm'] as int,
          meterriss: r['meterriss_mm'] as int,
        ),
      );
}

class Raum {
  Raum({
    required this.id,
    required this.geschossId,
    required this.name,
    required this.kuerzel,
    this.rfb,
    this.ffb,
    this.rohdecke,
    this.ukDecke,
    this.umriss,
    this.bezug,
    this.art = RaumArt.raum,
    this.eigenschaften = const {},
  });

  /// Zusatzdaten (Heizlast: Solltemperatur, Luftwechsel, Boden-/Deckenaufbau …).
  final Map<String, dynamic> eigenschaften;

  final String id;
  final String geschossId;
  final String name;
  final String kuerzel;
  final int? rfb;
  final int? ffb;
  final int? rohdecke;
  final int? ukDecke;

  /// Lichter Umriss in mm (Innenkante der Wände), sofern im Grundriss verortet.
  final List<Punkt>? umriss;

  /// Punkt im Raum, über den er seinen Wandzug wiederfindet.
  final Punkt? bezug;

  /// Raum, Balkon, Terrasse … – Balkon und Terrasse brauchen keine Wände (Bodenplatte).
  final RaumArt art;

  /// Bodenplatte ohne Wandzug: Umriss ist fest gezeichnet, nicht erkannt.
  bool get istBodenplatte => bezug == null && art != RaumArt.raum && umriss != null;

  bool get hatEigeneHoehen => rfb != null || ffb != null || rohdecke != null || ukDecke != null;

  /// Lichte Grundfläche in mm², null ohne Umriss.
  double? get flaeche => umriss == null ? null : polygonFlaeche(umriss!).abs();

  /// Lichter Umfang in mm, null ohne Umriss.
  double? get umfang => umriss == null ? null : polygonUmfang(umriss!);

  static List<Punkt>? umrissLesen(String? json) {
    if (json == null || json.isEmpty) return null;
    final l = jsonDecode(json) as List;
    if (l.length < 3) return null;
    return [for (final p in l) Punkt((p[0] as num).toDouble(), (p[1] as num).toDouble())];
  }

  static String umrissText(List<Punkt> p) => jsonEncode([
        for (final e in p) [e.x.round(), e.y.round()]
      ]);

  Bezugshoehen hoehen(Geschoss g) => g.hoehen.mitRaum(rfb: rfb, ffb: ffb, rohdecke: rohdecke);

  static Raum ausZeile(Row r) => Raum(
        id: r['id'] as String,
        geschossId: r['geschoss_id'] as String,
        name: r['name'] as String,
        kuerzel: r['kuerzel'] as String,
        rfb: r['rfb_mm'] as int?,
        ffb: r['ffb_mm'] as int?,
        rohdecke: r['rohdecke_mm'] as int?,
        ukDecke: r['uk_decke_mm'] as int?,
        umriss: umrissLesen(r['umriss'] as String?),
        bezug: r['bezug_x'] == null
            ? null
            : Punkt((r['bezug_x'] as int).toDouble(), (r['bezug_y'] as int).toDouble()),
        art: RaumArt.values.where((a) => a.name == (r['art'] as String?)).firstOrNull ?? RaumArt.raum,
        eigenschaften: _json(r, 'eigenschaften'),
      );
}

class Gewerk {
  Gewerk({
    required this.id,
    required this.name,
    required this.kuerzel,
    required this.farbe,
    required this.linie,
    required this.sichtbar,
  });

  final String id;
  final String name;
  final String kuerzel;
  final int farbe;
  final String linie;
  final bool sichtbar;

  static Gewerk ausZeile(Row r) => Gewerk(
        id: r['id'] as String,
        name: r['name'] as String,
        kuerzel: r['kuerzel'] as String,
        farbe: r['farbe'] as int,
        linie: r['linie'] as String,
        sichtbar: (r['sichtbar'] as int) == 1,
      );
}

enum WandZustand { bestand, neu, abbruch }

/// Welche Längen an einer Wand angezeigt werden.
enum MassAnzeige { innenAussen, achse, innen, achseInnen, keine }

extension MassAnzeigeText on MassAnzeige {
  String get label => switch (this) {
        MassAnzeige.innenAussen => 'innen + außen',
        MassAnzeige.achse => 'nur Achse',
        MassAnzeige.innen => 'nur innen',
        MassAnzeige.achseInnen => 'Achse + innen',
        MassAnzeige.keine => 'keine',
      };
}

extension WandZustandText on WandZustand {
  String get label => switch (this) {
        WandZustand.bestand => 'Bestand',
        WandZustand.neu => 'Neu',
        WandZustand.abbruch => 'Abbruch',
      };
}

class Wand {
  Wand({
    required this.id,
    required this.geschossId,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.dicke,
    required this.zustand,
    this.wandtypId,
    this.massanzeige,
    this.gesperrt = false,
    this.verbinden,
  });

  final String id;
  final String geschossId;
  final int x1, y1, x2, y2;
  final int dicke;
  final WandZustand zustand;
  final String? wandtypId;

  /// Welche Maße an dieser Wand stehen; null = Voreinstellung.
  final MassAnzeige? massanzeige;

  /// Gesperrte Wände ändern ihre Geometrie nicht (Länge, Lage, Löschen).
  final bool gesperrt;

  /// Ecken mit Nachbarwänden verschneiden: null = Projektvorgabe.
  final bool? verbinden;

  double get laenge => math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));

  WandAchse get achse =>
      WandAchse(Punkt(x1.toDouble(), y1.toDouble()), Punkt(x2.toDouble(), y2.toDouble()), dicke);

  static Wand ausZeile(Row r) => Wand(
        id: r['id'] as String,
        geschossId: r['geschoss_id'] as String,
        x1: r['x1'] as int,
        y1: r['y1'] as int,
        x2: r['x2'] as int,
        y2: r['y2'] as int,
        dicke: r['dicke_mm'] as int,
        zustand: WandZustand.values.firstWhere(
          (z) => z.name == r['zustand'],
          orElse: () => WandZustand.bestand,
        ),
        wandtypId: r['wandtyp_id'] as String?,
        massanzeige: MassAnzeige.values.where((m) => m.name == r['massanzeige']).firstOrNull,
        gesperrt: (r['gesperrt'] as int? ?? 0) == 1,
        verbinden: r['verbinden'] == null ? null : r['verbinden'] == 1,
      );
}

class Baustoff {
  Baustoff({
    required this.id,
    required this.name,
    required this.kategorie,
    required this.farbe,
    required this.einheit,
    this.eigenschaften = const {},
  });

  final String id;
  final String name;
  final String kategorie;
  final int farbe;
  final String einheit;

  /// Bauphysik: lambda (W/mK), rho (kg/m³), mu, c (J/kgK).
  final Map<String, dynamic> eigenschaften;

  static Baustoff ausZeile(Row r) => Baustoff(
        id: r['id'] as String,
        name: r['name'] as String,
        kategorie: r['kategorie'] as String,
        farbe: r['farbe'] as int,
        einheit: r['einheit'] as String,
        eigenschaften: _json(r, 'eigenschaften'),
      );
}

/// Eine Schicht eines Wandtyps, von der ersten Wandseite (links der
/// Zeichenrichtung) zur zweiten.
class Schicht {
  const Schicht(this.materialId, this.dicke);
  final String materialId;
  final int dicke;
}

class Wandtyp {
  Wandtyp({required this.id, required this.name, required this.schichten});

  final String id;
  final String name;
  final List<Schicht> schichten;

  int get dicke => schichten.fold(0, (s, e) => s + e.dicke);
}

/// Freie Bemaßung: Strecke von (x1|y1) nach (x2|y2), Maßlinie um [abstand]
/// mm links der Richtung versetzt (negativ = rechts).
class Bemassung {
  Bemassung({
    required this.id,
    required this.geschossId,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.abstand,
    this.versteckt = false,
  });

  final String id;
  final String geschossId;
  final int x1, y1, x2, y2;
  final int abstand;
  final bool versteckt;

  double get laenge => math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));

  static Bemassung ausZeile(Row r) => Bemassung(
        id: r['id'] as String,
        geschossId: r['geschoss_id'] as String,
        x1: r['x1'] as int,
        y1: r['y1'] as int,
        x2: r['x2'] as int,
        y2: r['y2'] as int,
        abstand: r['abstand_mm'] as int,
        versteckt: (r['versteckt'] as int? ?? 0) == 1,
      );
}

/// Winkelmaß zwischen zwei Wänden mit gemeinsamem Punkt.
class Winkelmass {
  Winkelmass({required this.id, required this.wand1Id, required this.wand2Id, this.versteckt = false});
  final String id;
  final String wand1Id;
  final String wand2Id;
  final bool versteckt;

  static Winkelmass ausZeile(Row r) =>
      Winkelmass(
          id: r['id'] as String,
          wand1Id: r['wand1_id'] as String,
          wand2Id: r['wand2_id'] as String,
          versteckt: (r['versteckt'] as int? ?? 0) == 1);
}

/// Hintergrundbild eines Geschosses. Lage: linke obere Bildecke bei
/// (x | y) mm, Maßstab in Mikrometer je Bildpunkt (ganzzahlig).
class Planvorlage {
  Planvorlage({
    required this.id,
    required this.geschossId,
    required this.datei,
    required this.x,
    required this.y,
    required this.umProPx,
    required this.deckkraft,
    required this.sichtbar,
  });

  final String id;
  final String geschossId;
  final String datei; // relativ zum Projektordner
  final int x, y;
  final int umProPx;
  final int deckkraft; // 0 … 100
  final bool sichtbar;

  double get mmProPx => umProPx / 1000;

  static Planvorlage ausZeile(Row r) => Planvorlage(
        id: r['id'] as String,
        geschossId: r['geschoss_id'] as String,
        datei: r['datei'] as String,
        x: r['x_mm'] as int,
        y: r['y_mm'] as int,
        umProPx: r['um_pro_px'] as int,
        deckkraft: r['deckkraft'] as int,
        sichtbar: (r['sichtbar'] as int) == 1,
      );
}

enum OeffnungsArt { tuer, fenster, balkontuer, durchbruch }


extension OeffnungsArtText on OeffnungsArt {
  String get label => switch (this) {
        OeffnungsArt.tuer => 'Tür',
        OeffnungsArt.fenster => 'Fenster',
        OeffnungsArt.balkontuer => 'Balkontür / Fenstertür',
        OeffnungsArt.durchbruch => 'Durchbruch',
      };

  /// Übliche Rohbaumaße (Breite, Höhe, Brüstung) in mm.
  (int, int, int) get standard => switch (this) {
        OeffnungsArt.tuer => (885, 2010, 0),
        OeffnungsArt.fenster => (1010, 1385, 900),
        OeffnungsArt.balkontuer => (1010, 2260, 0),
        OeffnungsArt.durchbruch => (800, 2010, 0),
      };

  /// verglast wie ein Fenster (Uw, Laibung, Einbaudetail, Sonnenschutz)
  bool get verglast => this == OeffnungsArt.fenster || this == OeffnungsArt.balkontuer;
}

/// Tür, Fenster oder Durchbruch in einer Wand. [abstand] ab Wandanfang
/// (Achse) bis zum Öffnungsanfang. Anschlag: Band links/rechts in
/// Wandrichtung; [aufgehenLinks]: Flügel schlägt zur linken Wandseite auf.
class Oeffnung {
  Oeffnung({
    required this.id,
    required this.wandId,
    required this.art,
    required this.abstand,
    required this.breite,
    required this.hoehe,
    required this.bruestung,
    required this.bandRechts,
    required this.aufgehenLinks,
    this.eigenschaften = const {},
  });

  /// Bauelement, Sonnenschutz, Einbaulage, Laibungsdämmung …
  final Map<String, dynamic> eigenschaften;

  final String id;
  final String wandId;
  final OeffnungsArt art;
  final int abstand, breite, hoehe, bruestung;
  final bool bandRechts;
  final bool aufgehenLinks;

  static Oeffnung ausZeile(Row r) => Oeffnung(
        id: r['id'] as String,
        wandId: r['wand_id'] as String,
        art: OeffnungsArt.values.where((a) => a.name == r['art']).firstOrNull ?? OeffnungsArt.durchbruch,
        abstand: r['abstand_mm'] as int,
        breite: r['breite_mm'] as int,
        hoehe: r['hoehe_mm'] as int,
        bruestung: r['bruestung_mm'] as int,
        bandRechts: (r['band_rechts'] as int) == 1,
        aufgehenLinks: (r['aufgehen_links'] as int) == 1,
        eigenschaften: _json(r, 'eigenschaften'),
      );
}

enum Geometrieart { punkt, linie, flaeche }

class Objekttyp {
  Objekttyp({
    required this.id,
    required this.gewerkId,
    required this.name,
    required this.kuerzel,
    required this.geometrie,
  });

  final String id;
  final String gewerkId;
  final String name;
  final String kuerzel;
  final Geometrieart geometrie;

  static Objekttyp ausZeile(Row r) => Objekttyp(
        id: r['id'] as String,
        gewerkId: r['gewerk_id'] as String,
        name: r['name'] as String,
        kuerzel: r['kuerzel'] as String,
        geometrie: Geometrieart.values.where((g) => g.name == r['geometrie']).firstOrNull ?? Geometrieart.punkt,
      );
}

enum ObjektStatus { geplant, verlegt, geprueft, verdeckt }

extension ObjektStatusText on ObjektStatus {
  String get label => switch (this) {
        ObjektStatus.geplant => 'geplant',
        ObjektStatus.verlegt => 'verlegt',
        ObjektStatus.geprueft => 'geprüft',
        ObjektStatus.verdeckt => 'verdeckt',
      };
}

/// Wo ein Objekt liegt (Lastenheft: auf RFB, im Estrich, in Wand, an Decke, im Schacht).
const objektLagen = ['auf RFB', 'im Estrich', 'unter Estrich', 'in Wand', 'auf Wand', 'durch Wand', 'an Decke', 'in Decke', 'in Beton', 'im Schacht'];

/// Geplantes oder dokumentiertes Element eines Gewerks.
class Objekt {
  Objekt({
    required this.id,
    required this.typId,
    required this.geschossId,
    required this.raumId,
    required this.kennung,
    required this.punkte,
    required this.z,
    required this.zBezug,
    required this.lage,
    required this.status,
    required this.normkennzeichen,
    this.produktId,
    this.eigenschaften = const {},
  });

  final String id;
  final String typId;
  final String geschossId;
  final String? raumId;
  final String kennung;
  final List<Punkt> punkte; // ein Punkt, Linienzug oder Umriss (mm)
  final int? z;
  final Hoehenbezug? zBezug;
  final String? lage;
  final ObjektStatus status;
  final String? normkennzeichen;
  final String? produktId;
  final Map<String, dynamic> eigenschaften; // gewerkspezifisch, z. B. Verlegeabstand

  /// Höhen je Stützpunkt (absolut im Geschoss), wenn die Leitung in einer
  /// Wandansicht gezeichnet wurde – sonst null (Leitung liegt waagerecht auf z).
  List<int>? get zPunkte {
    final l = eigenschaften['z_abs'];
    if (l is! List || l.length != punkte.length) return null;
    return [for (final e in l) (e as num).round()];
  }

  /// Länge des Linienzugs; mit Höhen je Punkt räumlich (inkl. Steigstrecken).
  double get laenge {
    final zs = zPunkte;
    var s = 0.0;
    for (var i = 0; i + 1 < punkte.length; i++) {
      final eben = (punkte[i + 1] - punkte[i]).laenge;
      s += zs == null ? eben : math.sqrt(eben * eben + math.pow(zs[i + 1] - zs[i], 2));
    }
    return s;
  }

  static List<Punkt> geometrieLesen(String json) {
    final l = jsonDecode(json) as List;
    return [for (final p in l) Punkt((p[0] as num).toDouble(), (p[1] as num).toDouble())];
  }

  static String geometrieText(List<Punkt> p) => jsonEncode([
        for (final e in p) [e.x.round(), e.y.round()]
      ]);

  static Objekt ausZeile(Row r) => Objekt(
        id: r['id'] as String,
        typId: r['typ_id'] as String,
        geschossId: r['geschoss_id'] as String,
        raumId: r['raum_id'] as String?,
        kennung: r['kennung'] as String,
        punkte: geometrieLesen(r['geometrie'] as String),
        z: r['z_mm'] as int?,
        zBezug: Hoehenbezug.values.where((b) => b.name == r['z_bezug']).firstOrNull,
        lage: r['lage'] as String?,
        status: ObjektStatus.values.where((s) => s.name == r['status']).firstOrNull ?? ObjektStatus.geplant,
        normkennzeichen: r['normkennzeichen'] as String?,
        produktId: r['produkt_id'] as String?,
        eigenschaften: _eigenschaftenLesen(r['eigenschaften'] as String?),
      );
}

/// Foto mit seinem Marker im Grundriss (Lage und Blickrichtung optional).
class Foto {
  Foto({
    required this.id,
    required this.datei,
    required this.aufnahme,
    required this.autor,
    required this.notiz,
    required this.geschossId,
    required this.x,
    required this.y,
    required this.richtung,
    required this.raumId,
    required this.objektIds,
  });

  final String id; // Medium-ID
  final String datei; // relativ zum Projektordner
  final DateTime aufnahme;
  final String autor;
  final String? notiz;
  final String geschossId;
  final int? x, y;
  final int? richtung; // Grad, 0 = nach rechts, 90 = nach oben
  final String? raumId;
  final List<String> objektIds;

  bool get verortet => x != null && y != null;

  static Foto ausZeile(Row r, List<String> objekte) => Foto(
        id: r['id'] as String,
        datei: r['datei'] as String,
        aufnahme: DateTime.tryParse(r['aufnahme'] as String? ?? '') ?? DateTime(2000),
        autor: r['autor'] as String? ?? '',
        notiz: r['notiz'] as String?,
        geschossId: r['geschoss_id'] as String,
        x: r['x_mm'] as int?,
        y: r['y_mm'] as int?,
        richtung: r['richtung'] as int?,
        raumId: r['raum_id'] as String?,
        objektIds: objekte,
      );
}

/// Wiederverwendbarer Katalogeintrag.
class Produkt {
  Produkt({
    required this.id,
    required this.name,
    required this.hersteller,
    required this.artikelnummer,
    required this.ean,
    required this.einheit,
    required this.platzhalter,
    required this.angebote,
  });

  final String id;
  final String name;
  final String? hersteller;
  final String? artikelnummer;
  final String? ean;
  final String einheit;
  final bool platzhalter;
  final List<Angebot> angebote;

  /// Günstigstes Angebot (netto) oder null.
  Angebot? get bestesAngebot =>
      angebote.isEmpty ? null : angebote.reduce((a, b) => a.preisCent <= b.preisCent ? a : b);

  static Produkt ausZeile(Row r, List<Angebot> angebote) => Produkt(
        id: r['id'] as String,
        name: r['name'] as String,
        hersteller: r['hersteller'] as String?,
        artikelnummer: r['artikelnummer'] as String?,
        ean: r['ean'] as String?,
        einheit: r['einheit'] as String,
        platzhalter: (r['platzhalter'] as int) == 1,
        angebote: angebote,
      );
}

/// Preis bei einem Händler (netto, ganze Cent; Steuersatz in Hundertstel-Prozent, 1900 = 19 %).
class Angebot {
  Angebot({
    required this.id,
    required this.produktId,
    required this.haendler,
    required this.link,
    required this.preisCent,
    required this.steuer,
    required this.datum,
  });

  final String id;
  final String produktId;
  final String haendler;
  final String? link;
  final int preisCent;
  final int steuer;
  final String? datum;

  static Angebot ausZeile(Row r) => Angebot(
        id: r['id'] as String,
        produktId: r['produkt_id'] as String,
        haendler: r['haendler'] as String,
        link: r['link'] as String?,
        preisCent: r['preis_cent'] as int,
        steuer: r['steuer'] as int,
        datum: r['preisdatum'] as String?,
      );
}

enum KostenStatus { geplant, angefragt, bestellt, geliefert, bezahlt }

extension KostenStatusText on KostenStatus {
  String get label => switch (this) {
        KostenStatus.geplant => 'geplant',
        KostenStatus.angefragt => 'angefragt',
        KostenStatus.bestellt => 'bestellt',
        KostenStatus.geliefert => 'geliefert',
        KostenStatus.bezahlt => 'bezahlt',
      };
}

const kostenarten = ['Material', 'Lohn', 'Gerät / Miete', 'Entsorgung', 'Planung', 'Sonstiges'];

/// Eine Ausgabe oder Planung. Menge in Tausendsteln (1000 = 1 Stück / 1 m),
/// Einzelpreis netto in Cent, Steuersatz in Hundertstel-Prozent.
class Kostenposition {
  Kostenposition({
    required this.id,
    required this.kostenart,
    required this.text,
    required this.produktId,
    required this.raumId,
    required this.gewerkId,
    required this.mengeMilli,
    required this.einheit,
    required this.einzelCent,
    required this.steuer,
    required this.status,
    required this.ausPlan,
  });

  final String id;
  final String kostenart;
  final String text;
  final String? produktId;
  final String? raumId;
  final String? gewerkId;
  final int mengeMilli;
  final String einheit;
  final int einzelCent;
  final int steuer;
  final KostenStatus status;
  final bool ausPlan;

  int get nettoCent => (mengeMilli * einzelCent / 1000).round();
  int get steuerCent => (nettoCent * steuer / 10000).round();
  int get bruttoCent => nettoCent + steuerCent;

  static Kostenposition ausZeile(Row r) => Kostenposition(
        id: r['id'] as String,
        kostenart: r['kostenart'] as String,
        text: r['text'] as String,
        produktId: r['produkt_id'] as String?,
        raumId: r['raum_id'] as String?,
        gewerkId: r['gewerk_id'] as String?,
        mengeMilli: r['menge_milli'] as int,
        einheit: r['einheit'] as String,
        einzelCent: r['einzel_cent'] as int,
        steuer: r['steuer'] as int,
        status: KostenStatus.values.where((s) => s.name == r['status']).firstOrNull ?? KostenStatus.geplant,
        ausPlan: r['herkunft'] == 'plan',
      );
}

/// 123456 Cent → „1.234,56 €“
String euroText(int cent) {
  final negativ = cent < 0;
  final c = cent.abs();
  final euro = (c ~/ 100).toString();
  final buf = StringBuffer();
  for (var i = 0; i < euro.length; i++) {
    if (i > 0 && (euro.length - i) % 3 == 0) buf.write('.');
    buf.write(euro[i]);
  }
  return '${negativ ? '−' : ''}$buf,${(c % 100).toString().padLeft(2, '0')} €';
}

/// „12,5“ → 1250 (Cent) bzw. für Mengen ×1000.
int? dezimalLesen(String text, int faktor) {
  final t = text.trim().replaceAll('.', '').replaceAll(',', '.').replaceAll('€', '').trim();
  final v = double.tryParse(t);
  return v == null ? null : (v * faktor).round();
}

String mengeText(int milli) {
  final v = milli / 1000;
  return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceAll('.', ',');
}

Map<String, dynamic> _eigenschaftenLesen(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    return jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}

/// Art eines Raums. Balkon, Terrasse und Loggia können ohne Wände als
/// Bodenplatte gezeichnet werden.
enum RaumArt {
  raum('Raum'),
  balkon('Balkon'),
  terrasse('Terrasse'),
  loggia('Loggia');

  const RaumArt(this.label);
  final String label;
}

/// JSON-Spalte lesen (fehlt in alten Zeilen oder ist leer → leere Map).
Map<String, dynamic> _json(Row r, String spalte) {
  try {
    final v = r[spalte];
    if (v is! String || v.isEmpty) return const {};
    return Map<String, dynamic>.from(jsonDecode(v) as Map);
  } catch (_) {
    return const {};
  }
}
