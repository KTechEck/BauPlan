import '../data/models.dart';
import '../data/project_store.dart';
import '../data/schrank_models.dart';
import 'auslegung.dart';
import 'fbh.dart';
import 'height.dart';
import 'leitung_wand.dart';

/// Vorgaben der Auslegung (Projekteinstellung `auslegung`).
class AuslegungVorgaben {
  const AuslegungVorgaben({
    this.art = Verlegeart.c,
    this.zVor = 0.3,
    this.duMax = 3,
    this.umgebung = 30,
    this.zuschlag = 10,
    this.reserve = 1.5,
    this.system = 'Mehrschichtverbund',
    this.spreizung = 10,
  });

  final Verlegeart art;
  final double zVor; // Ω bis zum Verteiler
  final double duMax; // %
  final double umgebung; // °C
  final double zuschlag; // % Verschnitt/Reserve für die Einkaufsliste
  final double reserve; // m je Stromkreis am Verteiler
  final String system; // Rohrsystem für Vorschläge
  final double spreizung; // K Heizung

  static AuslegungVorgaben ausJson(Map? j) {
    final m = j ?? const {};
    double z(String k, double d) => (m[k] as num?)?.toDouble() ?? d;
    return AuslegungVorgaben(
      art: Verlegeart.values.where((v) => v.name == m['art']).firstOrNull ?? Verlegeart.c,
      zVor: z('zvor', 0.3),
      duMax: z('du_max', 3),
      umgebung: z('umgebung', 30),
      zuschlag: z('zuschlag', 10),
      reserve: z('reserve', 1.5),
      system: m['system'] as String? ?? 'Mehrschichtverbund',
      spreizung: z('spreizung', 10),
    );
  }

  Map<String, Object?> toJson() => {
        'art': art.name,
        'zvor': zVor,
        'du_max': duMax,
        'umgebung': umgebung,
        'zuschlag': zuschlag,
        'reserve': reserve,
        'system': system,
        'spreizung': spreizung,
      };
}

AuslegungVorgaben auslegungVorgaben(ProjectStore store) => AuslegungVorgaben.ausJson(store.einstellung<Map>('auslegung'));

/// Angaben je Stromkreis (Projekteinstellung `kabel_auslegung` {kreisId: {...}}).
Map<String, dynamic> kreisAngaben(ProjectStore store, String kreisId) =>
    Map<String, dynamic>.from((store.einstellung<Map>('kabel_auslegung') ?? const {})[kreisId] as Map? ?? const {});

void kreisAngabenSetzen(ProjectStore store, String kreisId, Map<String, Object?> werte) {
  final alle = Map<String, dynamic>.from(store.einstellung<Map>('kabel_auslegung') ?? const {});
  final m = {...kreisAngaben(store, kreisId), ...werte}..removeWhere((k, v) => v == null);
  if (m.isEmpty) {
    alle.remove(kreisId);
  } else {
    alle[kreisId] = m;
  }
  store.einstellungSetzen('kabel_auslegung', alle);
}

/// Ein Stromkreis mit allem, was die Auslegung braucht.
class KreisAuslegung {
  KreisAuslegung({
    required this.schrank,
    required this.kreis,
    required this.schutz,
    required this.objekte,
    required this.leistung,
    required this.laenge,
    required this.laengeGeschaetzt,
    required this.eingabe,
    required this.ist,
    required this.vorschlag,
  });

  final Schrank schrank;
  final Stromkreis kreis;
  final SchrankGeraet? schutz;
  final List<Objekt> objekte;
  final double leistung;
  final double laenge;
  final bool laengeGeschaetzt;
  final KabelEingabe eingabe;
  final KabelErgebnis ist;
  final KabelErgebnis vorschlag;
}

typedef _Lage = ({Map<String, Geschoss> geschosse, Map<String, int> sockel, Map<String, Objekttyp> typen});

_Lage _lage(ProjectStore store) {
  final gs = [for (final geb in store.gebaeude()) ...store.geschosse(geb.id)];
  return (
    geschosse: {for (final g in gs) g.id: g},
    sockel: geschossSockel(gs),
    typen: {for (final t in store.objekttypen()) t.id: t},
  );
}

/// Kabellänge aus gezeichneten Leitungen eines Stromkreises (Typ LT), sonst null.
double? _gezeichnet(Iterable<Objekt> objekte, Map<String, Objekttyp> typen) {
  final l = [for (final o in objekte) if (typen[o.typId]?.geometrie == Geometrieart.linie && o.punkte.length >= 2) o.laenge];
  if (l.isEmpty) return null;
  return l.fold<double>(0, (s, v) => s + v) / 1000;
}

/// Auslegung aller Stromkreise eines Schranks.
List<KreisAuslegung> kreiseAuslegen(ProjectStore store, Schrank schrank, {AuslegungVorgaben? vorgaben}) {
  final v = vorgaben ?? auslegungVorgaben(store);
  final lage = _lage(store);
  final geraete = store.schrankGeraete(schrank.id);
  final alle = store.alleObjekte();
  final verteilerObjekt = schrank.objektId == null ? null : alle.where((o) => o.id == schrank.objektId).firstOrNull;
  final kreise = store.stromkreise(schrank.id);
  final aus = <KreisAuslegung>[];
  for (final k in kreise) {
    final angaben = kreisAngaben(store, k.id);
    final objekte = [for (final o in alle) if (o.eigenschaften['stromkreis'] == k.id) o];
    final punkte = [for (final o in objekte) if (lage.typen[o.typId]?.geometrie == Geometrieart.punkt) o];
    var leistung = k.leistung.toDouble();
    if (leistung <= 0) {
      for (final o in punkte) {
        final w = o.eigenschaften['leistung_w'];
        leistung += w is num ? w.toDouble() : (lage.typen[o.typId]?.kuerzel == 'SD' ? 200 : 0);
      }
    }
    final schutz = geraete.where((g) => g.id == k.schutzId).firstOrNull;
    final drehstrom = schutz != null && (schutz.pole >= 3 || schutz.phase == '3P');
    var laengeGeschaetzt = false;
    double laenge;
    if (angaben['laenge_m'] is num) {
      laenge = (angaben['laenge_m'] as num).toDouble();
    } else if (_gezeichnet(objekte, lage.typen) case final g?) {
      laenge = g + v.reserve;
    } else {
      laengeGeschaetzt = true;
      final vg = verteilerObjekt?.geschossId ?? schrank.geschossId;
      final vp = verteilerObjekt == null ? null : (verteilerObjekt.punkte.first.x, verteilerObjekt.punkte.first.y);
      final pts = <(double, double, double)>[];
      var zuschlag = 0.0;
      for (final o in punkte) {
        final g = lage.geschosse[o.geschossId];
        final h = g == null || o.z == null ? 1050.0 : (absolut(o.z!, o.zBezug ?? Hoehenbezug.ffb, g.hoehen) - g.hoehen.ffb).toDouble();
        pts.add((o.punkte.first.x, o.punkte.first.y, h));
        if (vg != null && o.geschossId != vg) {
          final d = ((lage.sockel[o.geschossId] ?? 0) - (lage.sockel[vg] ?? 0)).abs() / 1000;
          if (d > zuschlag) zuschlag = d;
        }
      }
      final g0 = lage.geschosse[vg ?? (punkte.isEmpty ? '' : punkte.first.geschossId)];
      final raumhoehe = g0 == null ? 2500.0 : (g0.hoehen.rohdecke - g0.hoehen.ffb).toDouble();
      final start = vp ??
          (pts.isEmpty ? (0.0, 0.0) : (pts.map((p) => p.$1).reduce((a, b) => a < b ? a : b), pts.map((p) => p.$2).reduce((a, b) => a < b ? a : b)));
      laenge = stromkreisLaengeSchaetzen(verteiler: start, geraete: pts, raumhoeheMm: raumhoehe, reserveM: v.reserve, geschossZuschlagM: zuschlag);
    }
    final art = Verlegeart.values.where((a) => a.name == angaben['art']).firstOrNull ?? v.art;
    final eingabe = KabelEingabe(
      leistungW: leistung,
      laengeM: laenge,
      drehstrom: drehstrom,
      cosPhi: (angaben['cos_phi'] as num?)?.toDouble() ?? 1,
      art: art,
      haeufung: (angaben['haeufung'] as num?)?.toInt() ?? 1,
      umgebungC: (angaben['umgebung'] as num?)?.toDouble() ?? v.umgebung,
      nennstrom: schutz?.nennstrom,
      charakteristik: schutz?.charakteristik ?? 'B',
      querschnitt: k.querschnitt / 100,
      zVorOhm: v.zVor,
      maxSpannungsfall: v.duMax,
      gleichzeitigkeit: (angaben['gleichzeitigkeit'] as num?)?.toDouble() ?? 1,
    );
    final vorschlag = kabelVorschlag(KabelEingabe(
      leistungW: eingabe.leistungW,
      laengeM: eingabe.laengeM,
      drehstrom: eingabe.drehstrom,
      cosPhi: eingabe.cosPhi,
      art: eingabe.art,
      haeufung: eingabe.haeufung,
      umgebungC: eingabe.umgebungC,
      charakteristik: eingabe.charakteristik,
      zVorOhm: eingabe.zVorOhm,
      maxSpannungsfall: eingabe.maxSpannungsfall,
      gleichzeitigkeit: eingabe.gleichzeitigkeit,
      // Steckdosenkreise: mindestens 16 A üblich – vorhandene Absicherung bleibt Vorgabe
      nennstrom: schutz?.nennstrom,
    ));
    aus.add(KreisAuslegung(
      schrank: schrank,
      kreis: k,
      schutz: schutz,
      objekte: objekte,
      leistung: leistung,
      laenge: laenge,
      laengeGeschaetzt: laengeGeschaetzt,
      eingabe: eingabe,
      ist: kabelPruefen(eingabe),
      vorschlag: vorschlag,
    ));
  }
  return aus;
}

// ------------------------------------------------------------------ Rohre

/// Kürzel der Rohrleitungen, die ausgelegt werden.
const rohrKuerzel = {'KW': Medium.trinkwasser, 'WW': Medium.trinkwasser, 'ZI': Medium.trinkwasser, 'VL': Medium.heizung, 'RL': Medium.heizung, 'HR': Medium.heizung};

class RohrAuslegung {
  RohrAuslegung({required this.objekt, required this.typ, required this.eingabe, required this.ist, required this.vorschlag, required this.rohrName});
  final Objekt objekt;
  final Objekttyp typ;
  final RohrEingabe eingabe;
  final RohrErgebnis ist;
  final RohrErgebnis vorschlag;
  final String? rohrName;
}

/// Summe der Berechnungsdurchflüsse aus `eigenschaften.entnahmen` {Art: Anzahl}.
double summeVr(Map<String, dynamic> eig) {
  var s = 0.0;
  for (final e in (eig['entnahmen'] as Map? ?? const {}).entries) {
    s += (entnahmeArten['${e.key}'] ?? 0) * ((e.value as num?)?.toDouble() ?? 0);
  }
  return s;
}

/// Auslegung aller Rohrleitungen (Trinkwasser, Heizung) im Projekt.
/// [innenVon] liefert den Innendurchmesser eines Bibliothek-Rohrs (id) oder null.
List<RohrAuslegung> rohreAuslegen(ProjectStore store, {AuslegungVorgaben? vorgaben, double? Function(String id)? innenVon, String? Function(String id)? nameVon}) {
  final v = vorgaben ?? auslegungVorgaben(store);
  final lage = _lage(store);
  final aus = <RohrAuslegung>[];
  for (final o in store.alleObjekte()) {
    final t = lage.typen[o.typId];
    final medium = rohrKuerzel[t?.kuerzel];
    if (t == null || medium == null || o.punkte.length < 2) continue;
    final e = o.eigenschaften;
    final rohrId = e['rohr'] as String?;
    final innen = (e['innen_mm'] as num?)?.toDouble() ?? (rohrId == null ? null : innenVon?.call(rohrId));
    final eingabe = RohrEingabe(
      medium: medium,
      laengeM: o.laenge / 1000,
      leistungW: (e['leistung_w'] as num?)?.toDouble() ?? 0,
      spreizungK: (e['spreizung_k'] as num?)?.toDouble() ?? v.spreizung,
      summeVr: summeVr(e),
      system: e['rohr_system'] as String? ?? v.system,
      innen: innen,
    );
    aus.add(RohrAuslegung(
      objekt: o,
      typ: t,
      eingabe: eingabe,
      ist: rohrPruefen(eingabe),
      vorschlag: rohrVorschlag(RohrEingabe(
        medium: medium,
        laengeM: eingabe.laengeM,
        leistungW: eingabe.leistungW,
        spreizungK: eingabe.spreizungK,
        summeVr: eingabe.summeVr,
        system: eingabe.system,
      )),
      rohrName: rohrId == null ? null : nameVon?.call(rohrId),
    ));
  }
  aus.sort((a, b) => a.typ.kuerzel != b.typ.kuerzel ? a.typ.kuerzel.compareTo(b.typ.kuerzel) : a.objekt.kennung.compareTo(b.objekt.kennung));
  return aus;
}

// ------------------------------------------------------- Kabel-/Rohrliste

/// Alle Leitungsstücke des Projekts: gezeichnete Kabel, Leerrohre, Rohre,
/// Heizrohr der Heizkreise, Kanäle und geschätzte Stromkreise ohne Zeichnung.
/// [name] liefert die Anzeige eines Bibliothekselements (id) oder null.
List<LeitungsStueck> leitungsStuecke(ProjectStore store, {String? Function(String id)? name, AuslegungVorgaben? vorgaben}) {
  final lage = _lage(store);
  final raum = <String, String>{
    for (final geb in store.gebaeude())
      for (final g in store.geschosse(geb.id))
        for (final r in store.raeume(g.id)) r.id: r.name,
  };
  final kreise = <String, Stromkreis>{
    for (final s in store.schraenke())
      for (final k in store.stromkreise(s.id)) k.id: k,
  };
  final aus = <LeitungsStueck>[];
  String nm(String? id, String sonst) => id == null ? sonst : (name?.call(id) ?? sonst);
  final kreiseGezeichnet = <String>{};
  for (final o in store.alleObjekte()) {
    final t = lage.typen[o.typId];
    if (t == null) continue;
    final e = o.eigenschaften;
    final woher = [lage.geschosse[o.geschossId]?.kuerzel, raum[o.raumId], o.kennung].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    if (t.kuerzel == 'HK') {
      final m = rohrlaenge(o.punkte, FbhEinstellung.ausJson(e)) / 1000 + ((e['zuleitung_mm'] as num?)?.toDouble() ?? 0) / 1000 * 2;
      aus.add((art: 'Rohr', bezeichnung: nm(e['rohr'] as String?, 'Heizrohr Fußbodenheizung'), laengeM: m, woher: woher, geschaetzt: false));
      continue;
    }
    if (t.geometrie != Geometrieart.linie || o.punkte.length < 2) continue;
    final m = o.laenge / 1000;
    final kabelListe = [for (final k in (e['kabel_liste'] as List? ?? const [])) '$k'];
    var erfasst = false;
    if (e['kabel'] is String && (e['kabel'] as String).isNotEmpty) {
      aus.add((art: 'Kabel', bezeichnung: e['kabel'] as String, laengeM: m, woher: woher, geschaetzt: false));
      erfasst = true;
    }
    for (final k in kabelListe) {
      aus.add((art: 'Kabel', bezeichnung: nm(k, 'Kabel'), laengeM: m, woher: woher, geschaetzt: false));
      erfasst = true;
    }
    final kreisId = e['stromkreis'] as String?;
    switch (t.kuerzel) {
      case 'LT':
        if (kreisId != null) kreiseGezeichnet.add(kreisId);
        if (!erfasst) {
          final k = kreise[kreisId];
          aus.add((art: 'Kabel', bezeichnung: e['leitung'] as String? ?? k?.leitung ?? 'Elektroleitung (Typ offen)', laengeM: m, woher: woher, geschaetzt: false));
        }
      case 'BL' when !erfasst:
        aus.add((art: 'Kabel', bezeichnung: 'KNX-Busleitung (J-Y(St)Y 2×2×0,8, grün)', laengeM: m, woher: woher, geschaetzt: false));
      case 'NK' when !erfasst:
        aus.add((art: 'Kabel', bezeichnung: 'CAT 7 S/FTP', laengeM: m, woher: woher, geschaetzt: false));
      case 'SL' when !erfasst:
        aus.add((art: 'Kabel', bezeichnung: 'Signalleitung (Typ offen)', laengeM: m, woher: woher, geschaetzt: false));
      case 'LR':
        aus.add((art: 'Leerrohr', bezeichnung: nm(e['rohr'] as String?, 'Leerrohr ${e['dn'] ?? 'M20'}'), laengeM: m, woher: woher, geschaetzt: false));
      case 'KK':
        aus.add((art: 'Kanal', bezeichnung: nm(e['kanal'] as String?, 'Kabelkanal'), laengeM: m, woher: woher, geschaetzt: false));
      case 'KW' || 'WW' || 'ZI' || 'AW' || 'VL' || 'RL' || 'HR' || 'KL':
        final rohr = e['rohr'] as String?;
        aus.add((
          art: 'Rohr',
          bezeichnung: rohr != null ? nm(rohr, t.name) : '${t.name}${e['dimension'] != null ? ' ${e['dimension']}' : ' (Dimension offen)'}',
          laengeM: m,
          woher: woher,
          geschaetzt: false,
        ));
      case 'LK':
        aus.add((art: 'Luftkanal', bezeichnung: nm(e['rohr'] as String?, 'Luftkanal ${e['dimension'] ?? ''}'.trim()), laengeM: m, woher: woher, geschaetzt: false));
      default:
        if (!erfasst && e['rohr'] is String) {
          aus.add((art: 'Rohr', bezeichnung: nm(e['rohr'] as String?, t.name), laengeM: m, woher: woher, geschaetzt: false));
        }
    }
  }
  // Stromkreise ohne gezeichnete Leitung: Länge schätzen
  for (final s in store.schraenke()) {
    for (final a in kreiseAuslegen(store, s, vorgaben: vorgaben)) {
      if (kreiseGezeichnet.contains(a.kreis.id) || a.objekte.isEmpty) continue;
      final leitung = a.kreis.leitung.trim().isEmpty ? leitungText(a.kreis.querschnitt / 100, drehstrom: a.eingabe.drehstrom) : a.kreis.leitung;
      aus.add((
        art: 'Kabel',
        bezeichnung: leitung,
        laengeM: a.laenge,
        woher: '${s.kennzeichen} Stromkreis ${a.kreis.nummer}${a.kreis.bezeichnung.isEmpty ? '' : ' ${a.kreis.bezeichnung}'}',
        geschaetzt: a.laengeGeschaetzt,
      ));
    }
  }
  return aus;
}

/// Was von der Kabel-/Rohrliste schon gekauft ist (Einstellung `leitung_gekauft` {Art|Bezeichnung: m}).
Map<String, double> leitungGekauft(ProjectStore store) => {
      for (final e in (store.einstellung<Map>('leitung_gekauft') ?? const {}).entries)
        if (e.value is num) '${e.key}': (e.value as num).toDouble(),
    };

void leitungGekauftSetzen(ProjectStore store, String schluessel, double? meter) {
  final m = Map<String, dynamic>.from(store.einstellung<Map>('leitung_gekauft') ?? const {});
  if (meter == null || meter <= 0) {
    m.remove(schluessel);
  } else {
    m[schluessel] = meter;
  }
  store.einstellungSetzen('leitung_gekauft', m);
}

String leitungSchluessel(LeitungsSumme s) => '${s.art}|${s.bezeichnung}';
