import 'dart:math' as math;

/// Keller und Sockel als Planungshilfe: Kellertrockenlegung (Abdichtung nach
/// DIN 18533, Drainage nach DIN 4095, Horizontalsperre, Innenabdichtung,
/// Sanierputz), Kellerdämmung (Perimeter außen, innen, Kellerdecke),
/// Sockeldämmung (eigener Bereich um die Geländeoberkante), Putzprofile und
/// Fensterbänke mit Mengen. Richtwerte – Feuchtegutachten/Hersteller beachten.

// ------------------------------------------------------- Trockenlegung

/// Wassereinwirkung (DIN 18533).
enum Lastfall { bodenfeuchte, sickerwasser, drueckend }

extension LastfallText on Lastfall {
  String get label => switch (this) {
        Lastfall.bodenfeuchte => 'W1.1-E Bodenfeuchte / nicht drückendes Wasser (durchlässiger Boden)',
        Lastfall.sickerwasser => 'W1.2-E mit Drainage (bindiger Boden, Sickerwasser)',
        Lastfall.drueckend => 'W2.1-E drückendes Wasser (≤ 3 m Eintauchtiefe)',
      };
  /// Bitumendickbeschichtung (PMBC) Trockenschichtdicke-Verbrauch in l/m².
  double get pmbcLiterJeM2 => switch (this) { Lastfall.bodenfeuchte => 4.0, Lastfall.sickerwasser => 4.0, Lastfall.drueckend => 6.0 };
}

class KellerVorgaben {
  const KellerVorgaben({
    this.tiefe = 2200,
    this.sockelUeberGok = 300,
    this.lastfall = Lastfall.sickerwasser,
    this.aussenabdichtung = true,
    this.drainage = true,
    this.horizontalsperre = 'injektion',
    this.innenabdichtung = false,
    this.sanierputz = true,
    this.perimeterDicke = 120,
    this.innenDaemmung = 0,
    this.innenMaterial = 'Kalziumsilikat',
    this.deckenDaemmung = 100,
    this.nichtFreilegbar = const {},
  });
  final int tiefe; // mm unter Geländeoberkante bis Fundament
  final int sockelUeberGok; // Abdichtung über GOK hochziehen (≥ 300 mm)
  final Lastfall lastfall;
  final bool aussenabdichtung, drainage, innenabdichtung, sanierputz;
  final String horizontalsperre; // keine, injektion, saege, edelstahl
  final int perimeterDicke; // mm, 0 = keine
  final int innenDaemmung; // mm, 0 = keine
  final String innenMaterial;
  final int deckenDaemmung; // mm Kellerdecke unterseitig, 0 = keine
  final Set<String> nichtFreilegbar; // Wand-IDs (Nachbargrenze, Anbau …)

  Map<String, Object?> toJson() => {
        'tiefe': tiefe,
        'sockel': sockelUeberGok,
        'lastfall': lastfall.name,
        'aussen': aussenabdichtung,
        'drainage': drainage,
        'sperre': horizontalsperre,
        'innen': innenabdichtung,
        'sanierputz': sanierputz,
        'perimeter': perimeterDicke,
        'innendaemmung': innenDaemmung,
        'innenmaterial': innenMaterial,
        'decke': deckenDaemmung,
        'nicht_frei': nichtFreilegbar.toList(),
      };

  static KellerVorgaben ausJson(Map? m) => KellerVorgaben(
        tiefe: (m?['tiefe'] as num?)?.toInt() ?? 2200,
        sockelUeberGok: (m?['sockel'] as num?)?.toInt() ?? 300,
        lastfall: Lastfall.values.where((l) => l.name == m?['lastfall']).firstOrNull ?? Lastfall.sickerwasser,
        aussenabdichtung: m?['aussen'] as bool? ?? true,
        drainage: m?['drainage'] as bool? ?? true,
        horizontalsperre: m?['sperre'] as String? ?? 'injektion',
        innenabdichtung: m?['innen'] as bool? ?? false,
        sanierputz: m?['sanierputz'] as bool? ?? true,
        perimeterDicke: (m?['perimeter'] as num?)?.toInt() ?? 120,
        innenDaemmung: (m?['innendaemmung'] as num?)?.toInt() ?? 0,
        innenMaterial: m?['innenmaterial'] as String? ?? 'Kalziumsilikat',
        deckenDaemmung: (m?['decke'] as num?)?.toInt() ?? 100,
        nichtFreilegbar: {for (final e in (m?['nicht_frei'] as List? ?? const [])) '$e'},
      );
}

/// Eine Kellerwand: Länge außen (mm), Dicke (mm), freilegbar?
typedef KellerWand = ({String id, double laenge, int dicke, bool freilegbar});

class KellerErgebnis {
  KellerErgebnis(this.positionen, this.hinweise);
  final List<({String was, double menge, String einheit})> positionen;
  final List<String> hinweise;
}

/// Mengen der Trockenlegung und Dämmung für die Kellerwände.
/// [kellerHoeheInnen] lichte Höhe (mm), [deckenFlaeche] m² Kellerdecke.
KellerErgebnis kellerBerechnen(List<KellerWand> waende, KellerVorgaben v, {int kellerHoeheInnen = 2300, double deckenFlaeche = 0}) {
  final pos = <({String was, double menge, String einheit})>[];
  final h = <String>[];
  void plus(String was, double menge, String einheit) {
    if (menge > 0) pos.add((was: was, menge: menge, einheit: einheit));
  }

  final frei = waende.where((w) => w.freilegbar).toList();
  final lFrei = frei.fold<double>(0, (s, w) => s + w.laenge) / 1000;
  final lAlle = waende.fold<double>(0, (s, w) => s + w.laenge) / 1000;
  final hoeheAbdichtung = (v.tiefe + v.sockelUeberGok) / 1000;
  if (v.aussenabdichtung && lFrei > 0) {
    final f = lFrei * hoeheAbdichtung;
    plus('Erdaushub (Arbeitsraum ca. 1 m breit)', lFrei * (v.tiefe / 1000) * 1.0, 'm³');
    plus('Untergrund reinigen, Ausgleichsputz/Kratzspachtel', f, 'm²');
    plus('Grundierung (Bitumen-Voranstrich)', f * 0.25, 'l');
    plus('Bitumendickbeschichtung PMBC 2-lagig (${v.lastfall.name})', f * v.lastfall.pmbcLiterJeM2, 'l');
    if (v.lastfall == Lastfall.drueckend) plus('Verstärkungseinlage (Gewebe)', f * 1.1, 'm²');
    plus('Hohlkehle am Fundament (Dichtungsmörtel)', lFrei, 'm');
    plus('Schutz-/Noppenbahn', f * 1.1, 'm²');
    plus('Abschlussschiene Noppenbahn', lFrei, 'm');
  }
  if (v.drainage && lFrei > 0 && v.lastfall != Lastfall.drueckend) {
    plus('Drainrohr DN 100 (DIN 4095) mit Gefälle ≥ 0,5 %', lFrei * 1.05, 'm');
    plus('Spül-/Kontrollschacht (an jeder Ecke/Richtungswechsel)', math.max(4, frei.length).toDouble(), 'Stk');
    plus('Filtervlies', lFrei * 1.5, 'm²');
    plus('Drainkies 16/32', lFrei * 0.25, 'm³');
    h.add('Drainage nur mit Anschluss an eine Vorflut (Kanal mit Rückstausicherung, Sickeranlage) – Genehmigung prüfen.');
  }
  if (v.lastfall == Lastfall.drueckend) h.add('Drückendes Wasser: keine Drainage, sondern druckwasserdichte Abdichtung (W2.1-E) – Fachplanung.');
  if (v.horizontalsperre != 'keine' && lAlle > 0) {
    final dickeM = waende.isEmpty ? 0.36 : waende.map((w) => w.dicke).reduce(math.max) / 1000;
    switch (v.horizontalsperre) {
      case 'injektion':
        final loecher = (lAlle / 0.12).ceil() * (dickeM > 0.4 ? 2 : 1);
        plus('Bohrlöcher Horizontalsperre (Abstand 10–12 cm${dickeM > 0.4 ? ', 2 Reihen' : ''})', loecher.toDouble(), 'Stk');
        plus('Injektionscreme/-flüssigkeit (Richtwert)', lAlle * dickeM * 10 * 1.2, 'l');
      case 'saege':
        plus('Mauersägeverfahren mit Edelstahl-/Kunststoffplatte', lAlle, 'm');
      case 'edelstahl':
        plus('Chromstahlbleche einrammen', lAlle, 'm');
    }
    h.add('Vor der Horizontalsperre Feuchte und Salze messen (Darr-Methode/Salzanalyse) – danach richtet sich Verfahren und Sanierputz.');
  }
  final innenFlaeche = lAlle * kellerHoeheInnen / 1000;
  if (v.innenabdichtung) {
    plus('Innenabdichtung mineralische Dichtschlämme (2–3 Lagen)', innenFlaeche * 4.5, 'kg');
    plus('Dichtungskehle Wand/Boden', lAlle, 'm');
    for (final w in waende.where((w) => !w.freilegbar)) {
      h.add('Wand ${w.id.substring(0, math.min(6, w.id.length))}: außen nicht freilegbar – Innenabdichtung + Horizontalsperre.');
      break;
    }
  }
  if (v.sanierputz) {
    plus('Sanierputzsystem WTA (Vorspritz, Grundputz, Sanierputz)', innenFlaeche, 'm²');
    plus('Sanierputz Trockenmörtel (ca. 20 mm, 10 kg/m²/cm)', innenFlaeche * 20, 'kg');
  }
  if (v.perimeterDicke > 0 && lFrei > 0) {
    final f = lFrei * v.tiefe / 1000;
    plus('Perimeterdämmung XPS ${v.perimeterDicke} mm', f * 1.05, 'm²');
    plus('Perimeterkleber (bitumenfrei, punktweise)', f * 3, 'kg');
  }
  if (v.innenDaemmung > 0) {
    plus('Innendämmung ${v.innenMaterial} ${v.innenDaemmung} mm', innenFlaeche * 1.05, 'm²');
    h.add('Innendämmung nur kapillaraktiv/diffusionsoffen (z. B. Kalziumsilikat) und erst nach Trockenlegung – sonst Schimmel hinter der Dämmung.');
  }
  if (v.deckenDaemmung > 0 && deckenFlaeche > 0) {
    plus('Kellerdeckendämmung ${v.deckenDaemmung} mm (unterseitig)', deckenFlaeche * 1.05, 'm²');
    plus('Dämmplattenkleber / Tellerdübel', deckenFlaeche * 4, 'Stk');
  }
  if (v.sockelUeberGok < 300) h.add('Abdichtung mindestens 300 mm über Geländeoberkante führen (Spritzwasser).');
  return KellerErgebnis(pos, h);
}

/// U-Wert einer Kellerwand mit zusätzlicher Dämmung (λ 0,035 bzw. 0,06 Kalziumsilikat).
double uKellerwand(double uBestand, {int perimeter = 0, int innen = 0, String innenMaterial = 'Kalziumsilikat'}) {
  if (uBestand <= 0) return 0;
  var r = 1 / uBestand + perimeter / 1000 / 0.035;
  if (innen > 0) r += innen / 1000 / (innenMaterial.toLowerCase().contains('kalzium') ? 0.06 : 0.035);
  return 1 / r;
}

// ------------------------------------------------------------- Sockel

class SockelVorgaben {
  const SockelVorgaben({this.unterGok = 300, this.ueberGok = 300, this.daemmstoff = 'XPS 035', this.dicke = 120, this.putz = 'Sockelputz mit Dichtschlämme', this.kiesstreifen = true});
  final int unterGok, ueberGok, dicke;
  final String daemmstoff, putz;
  final bool kiesstreifen;
  Map<String, Object?> toJson() => {'unter': unterGok, 'ueber': ueberGok, 'daemmstoff': daemmstoff, 'dicke': dicke, 'putz': putz, 'kies': kiesstreifen};
  static SockelVorgaben ausJson(Map? m) => SockelVorgaben(
        unterGok: (m?['unter'] as num?)?.toInt() ?? 300,
        ueberGok: (m?['ueber'] as num?)?.toInt() ?? 300,
        daemmstoff: m?['daemmstoff'] as String? ?? 'XPS 035',
        dicke: (m?['dicke'] as num?)?.toInt() ?? 120,
        putz: m?['putz'] as String? ?? 'Sockelputz mit Dichtschlämme',
        kiesstreifen: m?['kies'] as bool? ?? true,
      );
}

const sockelDaemmstoffe = ['XPS 035', 'EPS-P (Perimeter) 035', 'Sockelplatte PU 026', 'Schaumglas 040'];

/// Sockeldämmung: eigener Bereich um die Geländeoberkante (unter GOK bis über
/// GOK), anderer Dämmstoff und Putz als die Fassade, Übergang zum WDVS über
/// das Sockelprofil. [laenge] = Sockellänge außen ohne Türen (m).
KellerErgebnis sockelBerechnen(double laenge, SockelVorgaben v, {int tueren = 0}) {
  final pos = <({String was, double menge, String einheit})>[];
  void plus(String was, double menge, String einheit) {
    if (menge > 0) pos.add((was: was, menge: menge, einheit: einheit));
  }

  final hoehe = (v.unterGok + v.ueberGok) / 1000;
  final f = laenge * hoehe;
  plus('Sockeldämmung ${v.daemmstoff} ${v.dicke} mm', f * 1.05, 'm²');
  plus('Abdichtung hinter dem Sockel (bis 300 mm über GOK)', laenge * (v.unterGok + 300) / 1000, 'm²');
  plus('Sockelkleber (bitumenfrei/mineralisch)', f * 4, 'kg');
  plus('Dübel im Bereich über GOK', laenge * v.ueberGok / 1000 * 4, 'Stk');
  plus(v.putz, laenge * v.ueberGok / 1000, 'm²');
  plus('Sockelabschlussprofil / Tropfkante zum WDVS', laenge, 'm');
  plus('Noppenbahn mit Abschlussleiste unter GOK', laenge * v.unterGok / 1000 * 1.1, 'm²');
  if (v.kiesstreifen) plus('Kiesstreifen 30 cm breit, 16/32', laenge * 0.3 * 0.2, 'm³');
  final h = [
    'Sockel ≠ Fassade: unter und knapp über Gelände nur feuchteunempfindliche Dämmstoffe (XPS/EPS-P/Schaumglas), kein Mineralwoll-WDVS.',
    'Spritzwasserzone 300 mm über GOK: Sockelputz mit Abdichtung, Kiesstreifen statt Pflaster direkt an der Wand.',
    if (tueren > 0) '$tueren Haus-/Terrassentür(en): Sockel an der Schwelle mit Abdichtungsanschluss ausführen.',
  ];
  return KellerErgebnis(pos, h);
}

// ---------------------------------------------------------- Putzprofile

/// Gängige Putz- und WDVS-Profile mit Stablänge (m).
const putzprofile = <String, (String gruppe, double stab)>{
  'Sockelprofil / Sockelschiene (WDVS)': ('Außen', 2.5),
  'Sockelabschlussprofil mit Tropfkante': ('Außen', 2.5),
  'Eckprofil mit Gewebe (Gebäudeecke)': ('Außen', 2.5),
  'Kantenschutzprofil Laibung (mit Gewebe)': ('Außen', 2.5),
  'Anputzleiste / Fensteranschlussprofil': ('Außen', 2.4),
  'Tropfkantenprofil Sturz (mit Gewebe)': ('Außen', 2.5),
  'Fensterbankanschlussprofil / Gleitabschluss': ('Außen', 2.0),
  'Balkon-Tropfkantenprofil (Plattenrand)': ('Außen', 2.0),
  'Dehnfugenprofil Fassade (E-/V-Form)': ('Außen', 2.5),
  'Putzabschlussprofil außen (Anschluss Holz/Metall)': ('Außen', 2.5),
  'Rollladenkasten-Anschlussprofil': ('Außen', 2.4),
  'Eckschutzschiene innen (Kantenschutz)': ('Innen', 2.5),
  'Putzabschlussprofil innen': ('Innen', 2.5),
  'Putzleiste / Sockelputzleiste innen': ('Innen', 2.5),
  'Dehnfugenprofil innen': ('Innen', 2.5),
  'Fensterbankanschluss innen (Fuge)': ('Innen', 2.0),
};

/// Mengen der Putzprofile aus dem Plan. Liefert Profil → Meter.
Map<String, double> putzprofileAusPlan({
  required double aussenEckenHoeheM, // Summe Gebäudeaußenecken × Höhe
  required List<({double b, double h, bool fenster, bool tuer})> oeffnungenAussen,
  required double sockelLaengeM,
  required double innenEckenHoeheM, // Summe vorspringende Innenecken (Raum) × Höhe
  required List<({double b, double h})> oeffnungenInnen, // Laibungen innen (Fenster/Türen ohne Zarge)
  double balkonRandM = 0,
  double dehnfugenM = 0,
}) {
  final m = <String, double>{};
  void plus(String k, double v) {
    if (v > 0) m[k] = (m[k] ?? 0) + v;
  }

  plus('Sockelprofil / Sockelschiene (WDVS)', sockelLaengeM);
  plus('Eckprofil mit Gewebe (Gebäudeecke)', aussenEckenHoeheM);
  for (final o in oeffnungenAussen) {
    final b = o.b / 1000, h = o.h / 1000;
    plus('Kantenschutzprofil Laibung (mit Gewebe)', 2 * h + b);
    plus('Anputzleiste / Fensteranschlussprofil', 2 * h + b + (o.fenster ? 0 : 0));
    plus('Tropfkantenprofil Sturz (mit Gewebe)', b);
    if (o.fenster) plus('Fensterbankanschlussprofil / Gleitabschluss', 0.2 * 2);
  }
  plus('Balkon-Tropfkantenprofil (Plattenrand)', balkonRandM);
  plus('Dehnfugenprofil Fassade (E-/V-Form)', dehnfugenM);
  plus('Eckschutzschiene innen (Kantenschutz)', innenEckenHoeheM);
  for (final o in oeffnungenInnen) {
    plus('Eckschutzschiene innen (Kantenschutz)', 2 * o.h / 1000 + o.b / 1000);
  }
  return m;
}

/// Stäbe je Profil mit Verschnitt.
int profilStaebe(String profil, double meter, {double verschnitt = 10}) {
  final stab = putzprofile[profil]?.$2 ?? 2.5;
  return (meter * (1 + verschnitt / 100) / stab).ceil();
}

// ---------------------------------------------------------- Fensterbänke

const fensterbankAussen = ['Aluminium (gekantet)', 'Naturstein', 'Kunststein / Betonwerkstein', 'Klinker / Rollschicht', 'Titanzink', 'keine'];
const fensterbankInnen = ['Holz', 'Werzalit / Kunststoff', 'Naturstein', 'Agglo-Marmor', 'Fliese', 'Putz (keine Bank)', 'keine'];

typedef Fensterbank = ({double laenge, double tiefe, int endkappen, List<String> zubehoer, List<String> hinweise});

/// Außenfensterbank: Tiefe = Laibungstiefe + Dämmung + Überstand (≥ 40 mm),
/// Länge = Öffnung + Einbindung; Alu mit Bordprofilen/Gleitabschluss.
Fensterbank fensterbankAussenBerechnen({
  required String material,
  required double breite,
  required double laibungstiefe, // Wand außen bis Fenster
  double daemmung = 0, // WDVS-Dicke
  double ueberstand = 40,
  double gefaelleGrad = 8,
}) {
  final stein = material.contains('stein') || material.contains('Klinker');
  final einbindung = stein ? 2 * 20.0 : 2 * 5.0;
  final h = <String>[
    if (ueberstand < 30) 'Überstand ${ueberstand.round()} mm – mindestens 30–40 mm vor die Fassade, sonst läuft Wasser an der Wand ab.',
    if (gefaelleGrad < 5) 'Gefälle ${gefaelleGrad.round()}° – mindestens 5° (8 %) nach außen.',
    if (daemmung > 0 && !stein) 'Bei WDVS: Fensterbank mit Gleitabschluss/Bordprofil und Kompriband, Fensterbank-Anschlussprofil im Putz.',
    if (stein) 'Steinbank mit Tropfnase unten und seitlicher Aufkantung bzw. Einbindung in die Laibung; Fuge zum Fenster elastisch.',
  ];
  return (
    laenge: breite + einbindung,
    tiefe: laibungstiefe + daemmung + ueberstand,
    endkappen: stein ? 0 : 2,
    zubehoer: [if (!stein) 'Antidröhnband', if (!stein) 'Bordprofile/Gleitabschlüsse (Paar)', 'Kompriband/Dichtband Fensteranschluss', if (daemmung > 0) 'Dämmkeil unter der Bank'],
    hinweise: h,
  );
}

/// Innenfensterbank: Tiefe = Laibung innen + Überstand (20–30 mm), Länge = Öffnung + 2 × Seitenüberstand.
Fensterbank fensterbankInnenBerechnen({required String material, required double breite, required double laibungInnen, double ueberstand = 25, double seitlich = 25}) => (
      laenge: material.startsWith('Putz') || material == 'keine' ? 0 : breite + 2 * seitlich,
      tiefe: laibungInnen + ueberstand,
      endkappen: 0,
      zubehoer: [if (material == 'Holz' || material.startsWith('Werzalit')) 'Konsolen/Montagekleber'],
      hinweise: [if (material == 'Fliese') 'Geflieste Fensterbank: Gefälle zum Raum vermeiden, Anschluss Fenster mit Dichtband.'],
    );
