import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// Eintrag im Bautagebuch: was wann gemacht wurde.
class TagebuchEintrag {
  TagebuchEintrag({
    required this.id,
    required this.datum,
    required this.text,
    this.stunden = 0,
    this.raeume = const [],
    this.gewerke = const [],
    this.wetter = '',
    this.personen = '',
  });
  final String id;
  final DateTime datum;
  final String text;
  final double stunden;
  final List<String> raeume; // Raum-IDs
  final List<String> gewerke; // Gewerk-IDs
  final String wetter;
  final String personen;

  static TagebuchEintrag ausZeile(Row r) => TagebuchEintrag(
        id: r['id'] as String,
        datum: DateTime.parse(r['datum'] as String),
        text: r['text'] as String? ?? '',
        stunden: ((r['stunden_hundertstel'] as int?) ?? 0) / 100,
        raeume: [for (final x in jsonDecode(r['raeume'] as String? ?? '[]') as List) x as String],
        gewerke: [for (final x in jsonDecode(r['gewerke'] as String? ?? '[]') as List) x as String],
        wetter: r['wetter'] as String? ?? '',
        personen: r['personen'] as String? ?? '',
      );
}

enum AufgabenStatus {
  offen('offen'),
  inArbeit('in Arbeit'),
  erledigt('erledigt');

  const AufgabenStatus(this.label);
  final String label;
}

/// Aufgabe mit Raum, Gewerk, Fälligkeit und Abhängigkeit; Wartungen wiederholen sich.
class Aufgabe {
  Aufgabe({
    required this.id,
    required this.titel,
    this.beschreibung = '',
    this.raumId,
    this.gewerkId,
    this.faellig,
    this.status = AufgabenStatus.offen,
    this.abhaengigVon,
    this.intervallTage,
    this.erledigtAm,
  });
  final String id;
  final String titel;
  final String beschreibung;
  final String? raumId;
  final String? gewerkId;
  final DateTime? faellig;
  final AufgabenStatus status;
  final String? abhaengigVon; // muss vorher erledigt sein
  final int? intervallTage; // Wartung: wiederkehrend
  final DateTime? erledigtAm;

  bool get istWartung => intervallTage != null && intervallTage! > 0;

  static Aufgabe ausZeile(Row r) => Aufgabe(
        id: r['id'] as String,
        titel: r['titel'] as String,
        beschreibung: r['beschreibung'] as String? ?? '',
        raumId: r['raum_id'] as String?,
        gewerkId: r['gewerk_id'] as String?,
        faellig: r['faellig'] == null ? null : DateTime.parse(r['faellig'] as String),
        status: AufgabenStatus.values.where((s) => s.name == r['status']).firstOrNull ?? AufgabenStatus.offen,
        abhaengigVon: r['abhaengig_von'] as String?,
        intervallTage: r['intervall_tage'] as int?,
        erledigtAm: r['erledigt_am'] == null ? null : DateTime.parse(r['erledigt_am'] as String),
      );
}

/// Prüfprotokoll bzw. Messwert (Druckprobe, Isolationsmessung, Belegreifheizen …).
class Pruefprotokoll {
  Pruefprotokoll({
    required this.id,
    required this.art,
    required this.datum,
    this.raumId,
    this.objektId,
    this.messwerte = const {},
    this.ergebnis = 'bestanden',
    this.pruefer = '',
    this.notiz = '',
  });
  final String id;
  final String art;
  final DateTime datum;
  final String? raumId;
  final String? objektId;
  final Map<String, String> messwerte;
  final String ergebnis; // bestanden, nicht bestanden, offen
  final String pruefer;
  final String notiz;

  static Pruefprotokoll ausZeile(Row r) => Pruefprotokoll(
        id: r['id'] as String,
        art: r['art'] as String,
        datum: DateTime.parse(r['datum'] as String),
        raumId: r['raum_id'] as String?,
        objektId: r['objekt_id'] as String?,
        messwerte: Map<String, String>.from(jsonDecode(r['messwerte'] as String? ?? '{}') as Map),
        ergebnis: r['ergebnis'] as String? ?? 'bestanden',
        pruefer: r['pruefer'] as String? ?? '',
        notiz: r['notiz'] as String? ?? '',
      );
}

/// Vorlagen für Prüfprotokolle mit ihren Messwert-Feldern.
const pruefVorlagen = <String, List<String>>{
  'Druckprobe Heizung/FBH': ['Prüfdruck bar', 'Dauer min', 'Druckabfall bar', 'Medium'],
  'Druckprobe Trinkwasser': ['Prüfdruck bar', 'Dauer min', 'Druckabfall bar', 'Verfahren'],
  'Isolationsmessung (Elektrofachkraft)': ['Stromkreis', 'Riso MΩ', 'Prüfspannung V', 'Messgerät'],
  'Schleifenimpedanz / RCD-Prüfung': ['Stromkreis', 'Zs Ω', 'Auslösezeit ms', 'IΔn mA'],
  'Belegreifheizen Estrich': ['Beginn', 'Ende', 'Vorlauftemperatur °C', 'CM-Messung %'],
  'Dichtheitsprüfung Abwasser': ['Prüfdruck mbar', 'Dauer min', 'Ergebnis'],
  'Sonstige Messung': ['Messwert', 'Einheit'],
};

/// Abhängigkeit erfüllt? (Vorgängeraufgabe erledigt oder keine.)
bool aufgabeFrei(Aufgabe a, Iterable<Aufgabe> alle) {
  if (a.abhaengigVon == null) return true;
  final vor = alle.where((x) => x.id == a.abhaengigVon).firstOrNull;
  return vor == null || vor.status == AufgabenStatus.erledigt;
}

/// Nächstes Fälligkeitsdatum einer Wartung nach Erledigung.
DateTime naechsteWartung(Aufgabe a, DateTime erledigt) => erledigt.add(Duration(days: a.intervallTage ?? 365));
