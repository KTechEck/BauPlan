import 'dart:math' as math;

import '../data/schrank_models.dart';

/// Kammschiene (Phasenschiene) auf einer Gerätereihe: verbindet die
/// Eingänge der Geräte von TE [von] bis vor [bis]; gespeist von [einspeisung].
class Kammschiene {
  Kammschiene({required this.id, required this.reihe, required this.von, required this.bis, this.art = '1P+N', this.einspeisung});
  final String id;
  final int reihe;
  final int von, bis;
  final String art; // 1P, 1P+N, 3P, 3P+N
  final String? einspeisung; // Gerät, dessen Ausgang die Schiene speist

  int get laenge => bis - von;
  bool deckt(SchrankGeraet g) => g.reihe == reihe && g.position >= von && g.ende <= bis;

  Map<String, dynamic> toJson() => {'id': id, 'reihe': reihe, 'von': von, 'bis': bis, 'art': art, 'einspeisung': einspeisung};
  static Kammschiene ausJson(Map<String, dynamic> m) => Kammschiene(
        id: m['id'] as String,
        reihe: (m['reihe'] as num).toInt(),
        von: (m['von'] as num).toInt(),
        bis: (m['bis'] as num).toInt(),
        art: m['art'] as String? ?? '1P+N',
        einspeisung: m['einspeisung'] as String?,
      );
}

List<Kammschiene> kammschienen(Schrank s) =>
    [for (final k in (s.eigenschaften['kammschienen'] as List? ?? const [])) Kammschiene.ausJson(Map<String, dynamic>.from(k as Map))];

/// Ein Draht im Schrank.
class Draht {
  Draht({
    required this.nr,
    required this.von,
    required this.nach,
    required this.leiter,
    required this.querschnitt,
    required this.laenge,
    this.vonGeraet,
    this.nachGeraet,
    this.stromkreis,
  });
  final int nr;
  final String von; // z. B. „-Q1:2“
  final String nach; // z. B. „-F1:1“
  final String leiter; // L1, L2, L3, N, PE
  final int querschnitt; // Hundertstel mm²
  final double laenge; // mm, geschätzt
  final String? vonGeraet, nachGeraet;
  final String? stromkreis;

  String get farbe => aderfarbe(leiter);
}

String aderfarbe(String leiter) => switch (leiter) {
      'L1' => 'braun',
      'L2' => 'schwarz',
      'L3' => 'grau',
      'N' => 'blau',
      'PE' => 'grün-gelb',
      _ => 'schwarz',
    };

const _teMm = 17.5, _reiheMm = 125.0, _reserveMm = 150.0;

/// Geschätzte Drahtlänge zwischen zwei Geräten (Wege über die Kanäle).
double drahtLaenge(SchrankGeraet? a, SchrankGeraet? b) {
  if (a == null || b == null) return 300;
  final dx = ((a.position + a.breite / 2) - (b.position + b.breite / 2)).abs() * _teMm;
  final dy = (a.reihe - b.reihe).abs() * _reiheMm;
  return dx + dy + _reserveMm;
}

/// Querschnitt eines Drahts im Schrank nach dem Nennstrom des Geräts davor.
int drahtQuerschnitt(int? nennstrom) {
  final n = nennstrom ?? 16;
  if (n <= 16) return 150;
  if (n <= 20) return 250;
  if (n <= 25) return 400;
  if (n <= 32) return 600;
  if (n <= 40) return 1000;
  return 1600;
}

List<String> _leiter(SchrankGeraet g) {
  if (g.phase == '3P' || g.pole >= 3 || g.art == GeraeteArt.hauptschalter) return ['L1', 'L2', 'L3'];
  return [g.phase ?? 'L1'];
}

/// Verdrahtung aus der Schrankplanung erzeugen: Einspeisung → Hauptschalter →
/// FI → LS (oder Kammschiene), LS → Klemme bzw. Abgang, N über den FI, PE.
List<Draht> verdrahtung(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
  final draehte = <Draht>[];
  final nach = {for (final g in geraete) g.id: g};
  final schienen = kammschienen(s);
  var nr = 0;
  void draht(String von, String nachT, String leiter, int q, SchrankGeraet? a, SchrankGeraet? b, {String? kreis}) {
    draehte.add(Draht(
      nr: ++nr,
      von: von,
      nach: nachT,
      leiter: leiter,
      querschnitt: q,
      laenge: drahtLaenge(a, b),
      vonGeraet: a?.id,
      nachGeraet: b?.id,
      stromkreis: kreis,
    ));
  }

  bool ueberSchiene(SchrankGeraet g) => schienen.any((k) => k.deckt(g) && k.einspeisung != null && k.einspeisung != g.id);

  final haupt = geraete.where((g) => g.art == GeraeteArt.hauptschalter).firstOrNull;
  final rcds = [for (final g in geraete) if (g.art == GeraeteArt.rcd) g];
  // Einspeisung
  if (haupt != null) {
    for (final l in [..._leiter(haupt), 'N']) {
      draht('Einspeisung', '${haupt.kennzeichen}:${l == 'N' ? 'N' : '1'}', l, drahtQuerschnitt(haupt.nennstrom), null, haupt);
    }
  }
  // Hauptschalter → FI
  for (final r in rcds) {
    if (ueberSchiene(r)) continue;
    final leiter = r.pole >= 4 ? ['L1', 'L2', 'L3', 'N'] : [r.phase ?? 'L1', 'N'];
    for (final l in leiter) {
      draht(haupt == null ? 'Einspeisung' : '${haupt.kennzeichen}:2', '${r.kennzeichen}:${l == 'N' ? 'N' : '1'}', l,
          drahtQuerschnitt(r.nennstrom), haupt, r);
    }
  }
  // Vorgeschaltetes Gerät → LS / FI/LS
  for (final g in geraete) {
    if (g.art != GeraeteArt.ls && g.art != GeraeteArt.fils) continue;
    if (ueberSchiene(g)) continue;
    final vor = nach[g.vorgeschaltetId] ?? haupt;
    for (final l in _leiter(g)) {
      draht(vor == null ? 'Einspeisung' : '${vor.kennzeichen}:2', '${g.kennzeichen}:1', l, drahtQuerschnitt(g.nennstrom), vor, g);
    }
    if (g.art == GeraeteArt.fils) {
      draht(vor == null ? 'N-Schiene' : '${vor.kennzeichen}:N', '${g.kennzeichen}:N', 'N', drahtQuerschnitt(g.nennstrom), vor, g);
    }
  }
  // Abgänge je Stromkreis: L vom Schutzorgan, N vom FI, PE von der PE-Schiene
  final klemmen = [for (final g in geraete) if (g.art == GeraeteArt.klemme) g];
  for (final k in kreise) {
    final schutz = nach[k.schutzId];
    if (schutz == null) continue;
    final klemme = klemmen.where((x) => x.eigenschaften['stromkreis'] == k.id).firstOrNull;
    final ziel = klemme == null ? 'Abgang ${k.nummer}' : '${klemme.kennzeichen}:1';
    final nZiel = klemme == null ? 'Abgang ${k.nummer} N' : '${klemme.kennzeichen}:N';
    final peZiel = klemme == null ? 'Abgang ${k.nummer} PE' : '${klemme.kennzeichen}:PE';
    for (final l in _leiter(schutz)) {
      draht('${schutz.kennzeichen}:2', ziel, l, k.querschnitt, schutz, klemme, kreis: k.id);
    }
    final nQuelle = schutz.art == GeraeteArt.fils ? schutz : nach[schutz.vorgeschaltetId];
    if (klemme != null) {
      draht(nQuelle == null ? 'N-Schiene' : '${nQuelle.kennzeichen}:N', nZiel, 'N', k.querschnitt, nQuelle ?? schutz, klemme, kreis: k.id);
      draht('PE-Schiene', peZiel, 'PE', k.querschnitt, null, klemme, kreis: k.id);
    }
  }
  return draehte;
}

/// Material für die Kostenliste: Draht in Metern je Querschnitt und Farbe,
/// Kammschienen in TE, Aderendhülsen.
List<(String, double, String)> verdrahtungsMaterial(List<Draht> draehte, List<Kammschiene> schienen) {
  final draht = <String, double>{};
  for (final d in draehte) {
    final q = (d.querschnitt / 100).toStringAsFixed(d.querschnitt % 100 == 0 ? 0 : 1).replaceAll('.', ',');
    final schluessel = 'H07V-K $q mm² ${d.farbe}';
    draht[schluessel] = (draht[schluessel] ?? 0) + d.laenge / 1000;
  }
  final te = <String, int>{};
  for (final k in schienen) {
    te['Kammschiene ${k.art}'] = (te['Kammschiene ${k.art}'] ?? 0) + k.laenge;
  }
  return [
    for (final e in draht.entries) (e.key, (e.value * 10).ceil() / 10, 'm'),
    for (final e in te.entries) (e.key, e.value.toDouble(), 'TE'),
    if (draehte.isNotEmpty) ('Aderendhülsen', draehte.length * 2.0, 'Stk'),
  ];
}

/// Hinweise zur Verdrahtung.
List<String> verdrahtungsHinweise(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
  final h = <String>[];
  final nach = {for (final g in geraete) g.id: g};
  for (final k in kammschienen(s)) {
    if (k.einspeisung == null || nach[k.einspeisung] == null) {
      h.add('Kammschiene Reihe ${k.reihe + 1} (TE ${k.von + 1}–${k.bis}) ohne Einspeisung.');
    }
    final geraeteDarauf = geraete.where((g) => k.deckt(g)).length;
    if (geraeteDarauf == 0) h.add('Kammschiene Reihe ${k.reihe + 1} verbindet keine Geräte.');
  }
  final klemmen = geraete.where((g) => g.art == GeraeteArt.klemme).toList();
  if (klemmen.isNotEmpty) {
    for (final k in kreise) {
      if (!klemmen.any((x) => x.eigenschaften['stromkreis'] == k.id)) h.add('Stromkreis ${k.nummer} ${k.bezeichnung}: Abgang ohne Klemme.');
    }
  }
  for (final g in geraete.where((g) => g.art == GeraeteArt.ls)) {
    final vor = nach[g.vorgeschaltetId];
    if (vor != null && vor.art == GeraeteArt.rcd) {
      // N des Stromkreises muss über denselben FI laufen – im Modell immer so, nur Hinweis bei 3P-LS an 2P-FI
      if (_leiter(g).length == 3 && vor.pole < 4) h.add('${g.kennzeichen} ist dreipolig, ${vor.kennzeichen} aber nur zweipolig.');
    }
  }
  return h;
}

/// Gesamtlänge der Drähte in Metern.
double drahtGesamt(List<Draht> d) => d.fold<double>(0, (s, x) => s + x.laenge) / 1000;

/// Für die Darstellung: Mittelpunkt eines Geräts in TE/Reihe.
(double, int) geraeteMitte(SchrankGeraet g) => (g.position + g.breite / 2, g.reihe);

/// Größte Kammschienenlänge, die in eine Reihe passt.
int maxSchiene(Schrank s, int von) => math.max(0, s.teJeReihe - von);
