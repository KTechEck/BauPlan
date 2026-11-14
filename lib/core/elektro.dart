import 'dart:math' as math;

import '../data/models.dart';
import '../data/project_store.dart';
import '../data/schrank_models.dart';
import 'auslegung_projekt.dart';

/// Elektro-Prüfhelfer (Planungshilfe, ersetzt keine Prüfung nach DIN VDE 0100-600):
/// Phasenlast je Verteiler, RCD/ÜSS/Reserve, Potentialausgleich und Erdung
/// als Checkliste, Verdrahtungsabgleich Plan ↔ Verteiler, Ausstattung nach
/// DIN 18015-2 und Plankopf-Angaben.

// --------------------------------------------------------------- Plankopf

/// Plankopf-Angaben (Projekteinstellung `plankopf`).
Map<String, String> plankopf(ProjectStore store) => {
      for (final e in (store.einstellung<Map>('plankopf') ?? const {}).entries) '${e.key}': '${e.value}',
    };

/// Projektzeile für Schriftfelder: Projekt · Ersteller · Rev.
String plankopfZeile(ProjectStore store, String projekt) {
  final k = plankopf(store);
  return [
    projekt,
    if ((k['ersteller'] ?? '').isNotEmpty) k['ersteller']!,
    if ((k['revision'] ?? '').isNotEmpty) 'Rev. ${k['revision']}',
  ].join(' · ');
}

// ------------------------------------------------------------- Phasenlast

/// Last je Außenleiter eines Verteilers (W). Drehstromkreise zählen zu je
/// einem Drittel, Kreise ohne Phase werden der schwächsten zugeschlagen.
Map<String, double> phasenlast(List<Stromkreis> kreise, List<SchrankGeraet> geraete, Map<String, double> lastJeKreis) {
  final l = {'L1': 0.0, 'L2': 0.0, 'L3': 0.0};
  final ohne = <double>[];
  for (final k in kreise) {
    final w = lastJeKreis[k.id] ?? k.leistung.toDouble();
    final s = geraete.where((g) => g.id == k.schutzId).firstOrNull;
    final ph = s?.phase;
    if (s != null && (s.pole >= 3 || ph == '3P')) {
      for (final x in l.keys) {
        l[x] = l[x]! + w / 3;
      }
    } else if (ph != null && l.containsKey(ph)) {
      l[ph] = l[ph]! + w;
    } else {
      ohne.add(w);
    }
  }
  ohne.sort((a, b) => b.compareTo(a));
  for (final w in ohne) {
    final x = l.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
    l[x] = l[x]! + w;
  }
  return l;
}

/// Schieflast-Hinweis (TAB: höchstens 4,6 kVA Unterschied zwischen den Außenleitern).
String? schieflastHinweis(Map<String, double> last) {
  if (last.isEmpty) return null;
  final mx = last.values.reduce(math.max), mn = last.values.reduce(math.min);
  if (mx - mn > 4600) {
    final hoch = last.entries.firstWhere((e) => e.value == mx).key, tief = last.entries.firstWhere((e) => e.value == mn).key;
    return 'Schieflast ${((mx - mn) / 1000).toStringAsFixed(1).replaceAll('.', ',')} kW zwischen $hoch und $tief – Stromkreise umverteilen (TAB max. 4,6 kVA).';
  }
  return null;
}

// --------------------------------------------------------------- Prüfung

class ElektroPunkt {
  ElektroPunkt(this.bereich, this.text, {this.ok = false, this.schluessel});
  final String bereich;
  final String text;
  final bool ok;

  /// Checklisten-Punkt zum Abhaken (Einstellung `elektro_pruefung`), sonst automatisch.
  final String? schluessel;
}

/// Checklisten-Punkte zum Abhaken (Schlüssel → Text).
const elektroCheckliste = <String, String>{
  'fundamenterder': 'Fundament-/Ringerder vorhanden und angeschlossen (DIN 18014)',
  'pa_schiene': 'Haupterdungsschiene (Potentialausgleichsschiene) gesetzt',
  'pa_wasser': 'Schutzpotentialausgleich: Wasserleitung, Gas, Heizung, Lüftung angeschlossen',
  'pa_bad': 'Bad: zusätzlicher Schutzpotentialausgleich geprüft (bei metallenen Rohren/Wanne)',
  'blitzschutz': 'Äußerer Blitzschutz geklärt (vorhanden oder nicht gefordert)',
  'erdung_messung': 'Erdungswiderstand gemessen und dokumentiert',
  'isolation': 'Isolationsmessung je Stromkreis durchgeführt',
  'rcd_test': 'RCD-Auslösung getestet (Zeit/Strom)',
};

/// Automatische Prüfung eines Verteilers plus Checkliste.
List<ElektroPunkt> elektroPruefen(ProjectStore store, Schrank s) {
  final h = <ElektroPunkt>[];
  final geraete = store.schrankGeraete(s.id);
  final kreise = store.stromkreise(s.id);
  // RCD je Kreis
  for (final k in kreise) {
    final sch = geraete.where((g) => g.id == k.schutzId).firstOrNull;
    if (sch == null) {
      h.add(ElektroPunkt('Schutz', 'Stromkreis ${k.nummer} ${k.bezeichnung}: kein Schutzorgan zugeordnet'));
      continue;
    }
    final rcd = sch.art == GeraeteArt.fils || geraete.any((g) => g.id == sch.vorgeschaltetId && (g.art == GeraeteArt.rcd || g.art == GeraeteArt.fils));
    if (!rcd && (sch.nennstrom ?? 16) <= 32) {
      h.add(ElektroPunkt('Schutz', 'Stromkreis ${k.nummer} ${k.bezeichnung}: ohne RCD 30 mA (Pflicht für Steckdosen bis 32 A und Außenbereich)'));
    }
  }
  // Überspannungsschutz
  final alleSchraenke = store.schraenke();
  final irgendwoSpd = alleSchraenke.any((x) => store.schrankGeraete(x.id).any((g) => g.art == GeraeteArt.spd));
  if (!irgendwoSpd) {
    h.add(ElektroPunkt('Überspannung', 'Kein Überspannungsschutz geplant – Typ 1+2 im Zählerschrank/Hauptverteiler (DIN VDE 0100-443/-534)'));
  } else if (!geraete.any((g) => g.art == GeraeteArt.spd) && s.art == SchrankArt.unterverteiler) {
    h.add(ElektroPunkt('Überspannung', 'Unterverteiler weiter als 10 m vom Hauptverteiler? Dann Typ 2 auch hier vorsehen.', ok: true));
  }
  // Reserve
  final belegt = geraete.fold<int>(0, (a, g) => a + g.breite);
  final gesamt = s.reihen * s.teJeReihe;
  if (gesamt > 0 && belegt / gesamt > 0.8) {
    h.add(ElektroPunkt('Reserve', 'Nur ${((1 - belegt / gesamt) * 100).round()} % Platz frei – mindestens 20 % Reserve einplanen (DIN 18015-1)'));
  }
  // Auslegung (Querschnitt/Absicherung/ΔU)
  for (final a in kreiseAuslegen(store, s)) {
    if (!a.ist.ok) h.add(ElektroPunkt('Auslegung', 'Stromkreis ${a.kreis.nummer}: ${a.ist.hinweise.first}'));
  }
  final last = phasenlast(kreise, geraete, {for (final a in kreiseAuslegen(store, s)) a.kreis.id: a.leistung});
  final sl = schieflastHinweis(last);
  if (sl != null) h.add(ElektroPunkt('Phasenlast', sl));
  return h;
}

/// Verdrahtungsabgleich: Plan (Installation) ↔ Verteiler.
List<ElektroPunkt> verdrahtungsabgleich(ProjectStore store) {
  final h = <ElektroPunkt>[];
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final kreise = <String, (Schrank, Stromkreis)>{
    for (final s in store.schraenke())
      for (final k in store.stromkreise(s.id)) k.id: (s, k),
  };
  final belegt = <String>{};
  const brauchtKreis = {'SD', 'LE', 'FA', 'LB', 'TA'};
  for (final o in store.alleObjekte()) {
    final kid = o.eigenschaften['stromkreis'] as String?;
    final k = typen[o.typId]?.kuerzel;
    if (kid != null) {
      if (!kreise.containsKey(kid)) {
        h.add(ElektroPunkt('Abgleich', '${o.kennung}: Stromkreis gelöscht oder unbekannt – neu zuordnen'));
      } else {
        belegt.add(kid);
      }
    } else if (brauchtKreis.contains(k) && o.eigenschaften['gespeist_von'] == null && o.eigenschaften['reserve'] != true) {
      h.add(ElektroPunkt('Abgleich', '${o.kennung} (${typen[o.typId]?.name}): keinem Stromkreis zugeordnet'));
    }
  }
  for (final e in kreise.entries) {
    if (!belegt.contains(e.key)) {
      h.add(ElektroPunkt('Abgleich', '${e.value.$1.kennzeichen} Stromkreis ${e.value.$2.nummer} ${e.value.$2.bezeichnung}: keine Verbraucher im Plan', ok: e.value.$2.bezeichnung.toLowerCase().contains('reserve')));
    }
  }
  return h;
}

// ------------------------------------------------------- DIN 18015-2

/// Ausstattungswert 1 (Mindest), 2 (Standard), 3 (Komfort).
/// Soll je Raum: Steckdosen, Beleuchtungsanschlüsse, Daten-/Kommunikationsanschlüsse.
({int sd, int licht, int daten}) ausstattungSoll(String raumName, double flaecheM2, int wert) {
  final n = raumName.toLowerCase();
  final gross = flaecheM2 > 20;
  (int, int, int) basis;
  if (RegExp(r'wohn|ess').hasMatch(n)) {
    basis = gross ? (9, 3, 2) : (7, 2, 2);
  } else if (RegExp(r'kind|spiel').hasMatch(n)) {
    basis = gross ? (8, 2, 2) : (6, 1, 2);
  } else if (RegExp(r'schlaf|eltern|gäste|gast').hasMatch(n)) {
    basis = gross ? (7, 2, 1) : (5, 1, 1);
  } else if (RegExp(r'arbeit|büro').hasMatch(n)) {
    basis = gross ? (9, 2, 2) : (7, 2, 2);
  } else if (RegExp(r'küche').hasMatch(n)) {
    basis = (7, 2, 1);
  } else if (RegExp(r'bad|dusch').hasMatch(n)) {
    basis = (3, 2, 0);
  } else if (RegExp(r'\bwc\b|gäste-wc|toilette').hasMatch(n)) {
    basis = (1, 1, 0);
  } else if (RegExp(r'flur|diele|gang|treppe').hasMatch(n)) {
    basis = flaecheM2 > 6 ? (2, 2, 0) : (1, 1, 0);
  } else if (RegExp(r'hwr|hauswirtschaft|wasch|technik|heiz').hasMatch(n)) {
    basis = (3, 1, 1);
  } else if (RegExp(r'abstell|kammer|speis').hasMatch(n)) {
    basis = (1, 1, 0);
  } else if (RegExp(r'terrasse|balkon|loggia').hasMatch(n)) {
    basis = (1, 1, 0);
  } else if (RegExp(r'keller|garage|hobby|werk').hasMatch(n)) {
    basis = (2, 1, 0);
  } else {
    basis = gross ? (6, 2, 1) : (4, 1, 1);
  }
  int skal(int v) => switch (wert) { 1 => math.max(v > 0 ? 1 : 0, (v * 0.7).round()), 3 => (v * 1.3).ceil(), _ => v };
  return (sd: skal(basis.$1), licht: skal(basis.$2), daten: skal(basis.$3));
}

/// Ist-Ausstattung eines Raums aus den Objekten: Steckdosen (je Einsatz),
/// Leuchten/Auslässe/LED-Streifen, Netzwerkdosen/Access Points.
({int sd, int licht, int daten}) ausstattungIst(Iterable<Objekt> objekte, Map<String, Objekttyp> typen) {
  var sd = 0, licht = 0, daten = 0;
  for (final o in objekte) {
    switch (typen[o.typId]?.kuerzel) {
      case 'SD':
        sd += ((o.eigenschaften['fach'] as num?) ?? 1).toInt();
      case 'LE' || 'LB':
        licht++;
      case 'ND' || 'AP':
        daten += ((o.eigenschaften['ports'] as num?) ?? 1).toInt();
    }
  }
  return (sd: sd, licht: licht, daten: daten);
}
