import 'dart:math' as math;

import '../data/schrank_models.dart';

/// Belegung eines Schranks: belegte und freie Teilungseinheiten, Reserve.
({int gesamt, int belegt, int frei, double reserve}) belegung(Schrank s, Iterable<SchrankGeraet> geraete) {
  final gesamt = s.reihen * s.teJeReihe;
  final belegt = geraete.where((g) => g.reihe < s.reihen).fold<int>(0, (a, g) => a + g.breite);
  final frei = math.max(0, gesamt - belegt);
  return (gesamt: gesamt, belegt: belegt, frei: frei, reserve: gesamt == 0 ? 0 : frei / gesamt);
}

/// Ist der Bereich [position] … [position]+[breite] in [reihe] frei
/// (ohne das Gerät [ausser])?
bool platzFrei(Schrank s, Iterable<SchrankGeraet> geraete, int reihe, int position, int breite, {String? ausser}) {
  if (reihe < 0 || reihe >= s.reihen || position < 0 || position + breite > s.teJeReihe) return false;
  for (final g in geraete) {
    if (g.id == ausser || g.reihe != reihe) continue;
    if (position < g.ende && g.position < position + breite) return false;
  }
  return true;
}

/// Erster freier Platz für [breite] TE, ab [abReihe] und [abPosition].
(int, int)? freierPlatz(Schrank s, Iterable<SchrankGeraet> geraete, int breite, {int abReihe = 0, int abPosition = 0}) {
  for (var r = abReihe; r < s.reihen; r++) {
    for (var p = r == abReihe ? abPosition : 0; p + breite <= s.teJeReihe; p++) {
      if (platzFrei(s, geraete, r, p, breite)) return (r, p);
    }
  }
  return null;
}

/// Nächstes freies Kennzeichen mit dem Kennbuchstaben der Geräteart, z. B. -F4.
String naechstesKennzeichen(GeraeteArt art, Iterable<SchrankGeraet> geraete) {
  final muster = RegExp('^-${art.buchstabe}(\\d+)\$');
  var hoechste = 0;
  for (final g in geraete) {
    final m = muster.firstMatch(g.kennzeichen);
    if (m != null) hoechste = math.max(hoechste, int.parse(m.group(1)!));
  }
  return '-${art.buchstabe}${hoechste + 1}';
}

/// Vollständiges Betriebsmittelkennzeichen nach DIN EN 81346, z. B. =UV1-F3.
String betriebsmittel(Schrank s, SchrankGeraet g) => '=${s.kennzeichen}${g.kennzeichen}';

/// Last je Phase (W) aus den Stromkreisen und der Phase ihres Schutzorgans;
/// dreipolige Abgänge („3P“) verteilen sich gleichmäßig.
Map<String, int> phasenLast(Iterable<Stromkreis> kreise, Iterable<SchrankGeraet> geraete) {
  final nach = {for (final g in geraete) g.id: g};
  final last = {'L1': 0, 'L2': 0, 'L3': 0};
  for (final k in kreise) {
    final phase = nach[k.schutzId]?.phase;
    if (phase == '3P') {
      for (final p in last.keys.toList()) {
        last[p] = last[p]! + (k.leistung / 3).round();
      }
    } else if (phase != null && last.containsKey(phase)) {
      last[phase] = last[phase]! + k.leistung;
    }
  }
  return last;
}

/// Höchster zulässiger Nennstrom eines LS für einen Kupferquerschnitt bei
/// üblicher Verlegung in der Wand (vereinfachte Richtwerte, keine Auslegung).
int? maxNennstrom(int querschnittHundertstel) => switch (querschnittHundertstel) {
      <= 150 => 16,
      <= 250 => 20,
      <= 400 => 25,
      <= 600 => 32,
      <= 1000 => 40,
      <= 1600 => 63,
      _ => null,
    };

/// Plausibilitätshinweise (nur Hinweise – Auslegung und Abnahme durch eine
/// Elektrofachkraft).
List<String> schrankHinweise(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
  final h = <String>[];
  final nach = {for (final g in geraete) g.id: g};
  final b = belegung(s, geraete);
  if (b.reserve < 0.2) h.add('Weniger als 20 % Reserve im Schrank (${b.frei} TE frei).');
  for (final g in geraete) {
    if (g.ende > s.teJeReihe || g.reihe >= s.reihen) h.add('${g.kennzeichen} passt nicht in den Schrank.');
    if (g.art == GeraeteArt.ls) {
      final vor = nach[g.vorgeschaltetId];
      if (vor == null || (vor.art != GeraeteArt.rcd)) {
        h.add('${g.kennzeichen} (${g.kurz}) hat keinen vorgeschalteten FI/RCD – Endstromkreise bis 32 A brauchen 30 mA.');
      }
    }
    if ((g.art == GeraeteArt.ls || g.art == GeraeteArt.fils) && g.phase == null) {
      h.add('${g.kennzeichen}: keine Phase zugeordnet.');
    }
  }
  final rcds = geraete.where((g) => g.art == GeraeteArt.rcd);
  for (final r in rcds) {
    final n = geraete.where((g) => g.vorgeschaltetId == r.id).length;
    if (n > 6) h.add('${r.kennzeichen}: $n Stromkreise an einem FI – bei einer Auslösung fällt viel aus (Richtwert: höchstens 4–6).');
  }
  for (final k in kreise) {
    final schutz = nach[k.schutzId];
    if (schutz == null) {
      h.add('Stromkreis ${k.nummer} ${k.bezeichnung}: kein Schutzorgan zugeordnet.');
      continue;
    }
    final max = maxNennstrom(k.querschnitt);
    if (max != null && (schutz.nennstrom ?? 16) > max) {
      h.add('Stromkreis ${k.nummer}: ${schutz.kurz} ist für ${k.querschnittText} zu groß (Richtwert höchstens $max A).');
    }
    if (k.leistung > 0 && schutz.nennstrom != null) {
      final strom = k.leistung / (schutz.phase == '3P' ? 400 * math.sqrt(3) : 230);
      if (strom > schutz.nennstrom!) {
        h.add('Stromkreis ${k.nummer}: geschätzte Last ${strom.toStringAsFixed(1).replaceAll('.', ',')} A über ${schutz.nennstrom} A.');
      }
    }
  }
  final last = phasenLast(kreise, geraete);
  final werte = last.values.toList()..sort();
  if (werte.last - werte.first > 4600) {
    h.add('Schieflast: Unterschied zwischen den Phasen ${((werte.last - werte.first) / 1000).toStringAsFixed(1).replaceAll('.', ',')} kVA (Richtwert höchstens 4,6 kVA).');
  }
  return h;
}

/// Beschriftungsstreifen je Reihe: (Startposition, Breite, Text) – Leerstellen
/// werden als leere Felder zurückgegeben.
List<List<(int, int, String)>> beschriftung(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
  final kreisZu = <String, List<Stromkreis>>{};
  for (final k in kreise) {
    if (k.schutzId != null) kreisZu.putIfAbsent(k.schutzId!, () => []).add(k);
  }
  return [
    for (var r = 0; r < s.reihen; r++)
      () {
        final felder = <(int, int, String)>[];
        var pos = 0;
        for (final g in geraete.where((g) => g.reihe == r).toList()..sort((a, b) => a.position.compareTo(b.position))) {
          if (g.position > pos) felder.add((pos, g.position - pos, ''));
          final k = kreisZu[g.id];
          final text = [
            g.kennzeichen,
            if (k != null) k.map((e) => e.bezeichnung.isEmpty ? e.nummer : e.bezeichnung).join(', ') else if (g.bezeichnung.isNotEmpty) g.bezeichnung,
          ].join(' ');
          felder.add((g.position, g.breite, text));
          pos = g.ende;
        }
        if (pos < s.teJeReihe) felder.add((pos, s.teJeReihe - pos, ''));
        return felder;
      }(),
  ];
}
