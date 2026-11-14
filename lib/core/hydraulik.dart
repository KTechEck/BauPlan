import 'dart:math' as math;

/// Hydraulischer Abgleich einer Flächenheizung (Heizkreisverteiler):
/// Soll-Volumenstrom je Kreis aus Leistung und Spreizung, Druckverlust aus
/// Rohrlänge, Voreinstellung der Ventile so, dass alle Kreise beim gleichen
/// Differenzdruck am Verteiler ihren Sollwert bekommen (Verfahren B,
/// vereinfacht). Richtwerte für die Planung – Herstellerangaben gehen vor.
class AbgleichEinstellung {
  const AbgleichEinstellung({
    this.spreizung = 5,
    this.spezLeistung = 50,
    this.rohrInnen = 12,
    this.zuschlag = 0.3,
    this.kvStufen = standardKvStufen,
    this.kvOffen = 2.0,
    this.verteilerVerlust = 2000,
  });

  /// Vorlauf − Rücklauf in K (Fußbodenheizung typ. 5–7 K).
  final double spreizung;

  /// Leistung je m², wenn für den Raum keine Heizlast vorliegt (W/m²).
  final double spezLeistung;

  /// Innendurchmesser des Heizrohrs (mm), z. B. 16 × 2 → 12 mm.
  final double rohrInnen;

  /// Zuschlag für Bögen, Verschraubungen und Ventile auf den Rohrverlust (Anteil).
  final double zuschlag;

  /// kv-Werte der Voreinstellstufen (Stufe 1 … n), m³/h bei 1 bar.
  final List<double> kvStufen;

  /// kv des voll geöffneten Ventils (m³/h).
  final double kvOffen;

  /// Druckverlust Verteiler, Zuleitung und Erzeugeranschluss pauschal (Pa).
  final double verteilerVerlust;

  /// Beispielwerte eines üblichen Rücklaufventils mit Voreinstellung – an den Hersteller anpassen.
  static const standardKvStufen = [0.10, 0.20, 0.35, 0.50, 0.75, 1.00, 1.40, 2.00];

  Map<String, dynamic> toJson() => {
        'spreizung': spreizung,
        'spez_leistung': spezLeistung,
        'rohr_innen': rohrInnen,
        'zuschlag': zuschlag,
        'kv_stufen': kvStufen,
        'kv_offen': kvOffen,
        'verteiler_pa': verteilerVerlust,
      };

  static AbgleichEinstellung ausJson(Map? m) {
    if (m == null) return const AbgleichEinstellung();
    double z(String k, double d) => (m[k] as num?)?.toDouble() ?? d;
    final kv = [for (final x in (m['kv_stufen'] as List? ?? const [])) if (x is num && x > 0) x.toDouble()];
    return AbgleichEinstellung(
      spreizung: z('spreizung', 5).clamp(1, 30),
      spezLeistung: z('spez_leistung', 50),
      rohrInnen: z('rohr_innen', 12).clamp(5, 40),
      zuschlag: z('zuschlag', 0.3).clamp(0, 3),
      kvStufen: kv.isEmpty ? standardKvStufen : kv,
      kvOffen: z('kv_offen', 2.0),
      verteilerVerlust: z('verteiler_pa', 2000),
    );
  }

  AbgleichEinstellung mit({double? spreizung, double? spezLeistung, double? rohrInnen, double? zuschlag, List<double>? kvStufen, double? kvOffen}) =>
      AbgleichEinstellung(
        spreizung: spreizung ?? this.spreizung,
        spezLeistung: spezLeistung ?? this.spezLeistung,
        rohrInnen: rohrInnen ?? this.rohrInnen,
        zuschlag: zuschlag ?? this.zuschlag,
        kvStufen: kvStufen ?? this.kvStufen,
        kvOffen: kvOffen ?? this.kvOffen,
        verteilerVerlust: verteilerVerlust,
      );
}

/// Ein Heizkreis für den Abgleich.
class AbgleichKreis {
  const AbgleichKreis({required this.id, required this.name, this.raum = '', required this.flaeche, required this.rohrlaenge, required this.leistung, this.abgang, this.istLMin, this.istStufe, this.leistungVonHand = false});
  final String id, name, raum;
  final double flaeche; // m²
  final double rohrlaenge; // m (inkl. Vor- und Rücklauf der Anbindung)
  final double leistung; // W
  final int? abgang; // 1 …
  final double? istLMin; // eingestellt/gemessen am Durchflussmesser
  final int? istStufe; // eingestellte Voreinstellung
  final bool leistungVonHand;
}

/// Ergebnis je Kreis.
class AbgleichErgebnis {
  AbgleichErgebnis({required this.kreis, required this.volumenstrom, required this.geschwindigkeit, required this.druckverlust, required this.ventilVerlust, required this.kvSoll, required this.stufe, required this.hinweise});
  final AbgleichKreis kreis;
  final double volumenstrom; // l/h
  final double geschwindigkeit; // m/s
  final double druckverlust; // Pa, Rohr inkl. Zuschlag
  final double ventilVerlust; // Pa, am Ventil abzudrosseln
  final double kvSoll; // m³/h
  final int? stufe; // Voreinstellstufe (1 …), null = voll offen
  final List<String> hinweise;

  double get lMin => volumenstrom / 60;
  double get waermeProQm => kreis.flaeche <= 0 ? 0 : kreis.leistung / kreis.flaeche;

  /// Abweichung des eingestellten Durchflusses vom Soll in % (null ohne Ist-Wert).
  double? get abweichung => kreis.istLMin == null || lMin <= 0 ? null : (kreis.istLMin! - lMin) / lMin * 100;
}

/// Gesamtergebnis.
class Abgleich {
  Abgleich(this.kreise, this.foerderhoehe, this.volumenstrom);
  final List<AbgleichErgebnis> kreise;

  /// Nötiger Differenzdruck am Verteiler inkl. pauschalem Verteilerverlust (Pa).
  final double foerderhoehe;

  /// Summe der Volumenströme (l/h).
  final double volumenstrom;

  double get foerderhoeheM => foerderhoehe / 9810;
  AbgleichErgebnis? get unguenstigster => kreise.isEmpty ? null : kreise.reduce((a, b) => a.druckverlust >= b.druckverlust ? a : b);
}

/// Wasser bei ca. 30 °C.
const _rho = 995.7; // kg/m³
const _nu = 0.80e-6; // m²/s

/// Volumenstrom in l/h aus Leistung (W) und Spreizung (K).
double volumenstromLh(double leistungW, double spreizungK) => spreizungK <= 0 ? 0 : leistungW / (1.163 * spreizungK);

/// Druckverlust eines Rohrs (Pa): Darcy-Weisbach, laminar 64/Re, sonst Blasius.
({double pa, double v}) rohrDruckverlust(double lh, double innenMm, double laengeM) {
  final d = innenMm / 1000;
  final a = math.pi * d * d / 4;
  final v = lh / 1000 / 3600 / a;
  if (v <= 0) return (pa: 0, v: 0);
  final re = v * d / _nu;
  final lambda = re < 2300 ? 64 / re : 0.3164 * math.pow(re, -0.25);
  return (pa: lambda * laengeM / d * _rho * v * v / 2, v: v);
}

/// Abgleich berechnen.
Abgleich abgleichBerechnen(List<AbgleichKreis> kreise, AbgleichEinstellung e) {
  final roh = <(AbgleichKreis, double, double, double)>[]; // Kreis, l/h, v, Pa
  for (final k in kreise) {
    final lh = volumenstromLh(k.leistung, e.spreizung);
    final r = rohrDruckverlust(lh, e.rohrInnen, k.rohrlaenge);
    roh.add((k, lh, r.v, r.pa * (1 + e.zuschlag)));
  }
  if (roh.isEmpty) return Abgleich(const [], 0, 0);
  // unguenstigster Kreis: Rohr + voll offenes Ventil
  double ventil(double lh, double kv) => kv <= 0 ? 0 : math.pow(lh / 1000 / kv, 2) * 1e5;
  final ziel = roh.map((r) => r.$4 + ventil(r.$2, e.kvOffen)).reduce(math.max);
  final stufen = [...e.kvStufen]..sort();
  final aus = <AbgleichErgebnis>[];
  for (final (k, lh, v, pa) in roh) {
    final dv = math.max(ventil(lh, e.kvOffen), ziel - pa);
    final kv = dv <= 0 ? e.kvOffen : (lh / 1000) / math.sqrt(dv / 1e5);
    int? stufe;
    if (kv < e.kvOffen * 0.97 && stufen.isNotEmpty) {
      // Stufe mit dem nächstliegenden kv (logarithmisch)
      var best = double.infinity;
      for (var i = 0; i < stufen.length; i++) {
        final d = (math.log(stufen[i]) - math.log(kv)).abs();
        if (d < best) {
          best = d;
          stufe = i + 1;
        }
      }
    }
    final h = <String>[
      if (k.rohrlaenge > 120) 'Kreis ${k.rohrlaenge.round()} m lang – über 120 m (Herstellergrenze prüfen, ggf. teilen)',
      if (v > 0.8) 'Fließgeschwindigkeit ${v.toStringAsFixed(2).replaceAll('.', ',')} m/s – Geräusche möglich (über 0,8 m/s)',
      if (pa > 25000) 'Druckverlust ${(pa / 1000).toStringAsFixed(0)} kPa – Kreis teilen oder größeres Rohr',
      if (k.flaeche > 0 && k.leistung / k.flaeche > 100) 'Über 100 W/m² – Oberflächentemperatur kritisch, Verlegeabstand verringern oder Zusatzheizfläche',
      if (k.leistung <= 0) 'Keine Leistung – Heizlast des Raums fehlt',
    ];
    aus.add(AbgleichErgebnis(kreis: k, volumenstrom: lh, geschwindigkeit: v, druckverlust: pa, ventilVerlust: dv, kvSoll: kv, stufe: stufe, hinweise: h));
  }
  return Abgleich(aus, ziel + e.verteilerVerlust, roh.fold(0, (s, r) => s + r.$2));
}

/// Leistung je Kreis: Heizlast des Raums nach Flächenanteil auf die Kreise im
/// Raum verteilt, abzüglich der Leistung anderer Heizflächen ([andere], W);
/// ohne Heizlast spezifische Leistung × Fläche.
Map<String, double> leistungAufteilen(
  List<({String id, String? raum, double flaeche, double? vonHand})> kreise,
  Map<String, double> heizlastRaum,
  double spezLeistung, {
  Map<String, double> andere = const {},
}) {
  final summe = <String, double>{};
  for (final k in kreise) {
    if (k.raum != null && k.vonHand == null) summe[k.raum!] = (summe[k.raum!] ?? 0) + k.flaeche;
  }
  return {
    for (final k in kreise)
      k.id: k.vonHand ??
          (k.raum != null && heizlastRaum[k.raum] != null && (summe[k.raum] ?? 0) > 0
              ? math.max(0, heizlastRaum[k.raum]! - (andere[k.raum] ?? 0)) * k.flaeche / summe[k.raum]!
              : spezLeistung * k.flaeche),
  };
}
