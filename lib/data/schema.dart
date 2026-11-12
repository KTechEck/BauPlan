/// Datenbank-Schema als nummerierte Migrationen.
/// Jede Migration ist eine Liste einzelner SQL-Anweisungen.
/// Neue Versionen werden NUR angehängt, nie geändert.
const List<List<String>> migrationen = [
  // Version 1 – Grundgerüst Stufe 1
  [
    '''CREATE TABLE projekt (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      adresse TEXT,
      einstellungen TEXT NOT NULL DEFAULT '{}',
      erstellt TEXT NOT NULL
    )''',
    '''CREATE TABLE gebaeude (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      reihenfolge INTEGER NOT NULL DEFAULT 0,
      geloescht TEXT
    )''',
    '''CREATE TABLE geschoss (
      id TEXT PRIMARY KEY,
      gebaeude_id TEXT NOT NULL REFERENCES gebaeude(id),
      name TEXT NOT NULL,
      kuerzel TEXT NOT NULL,
      reihenfolge INTEGER NOT NULL DEFAULT 0,
      rfb_mm INTEGER NOT NULL DEFAULT 0,
      ffb_mm INTEGER NOT NULL DEFAULT 0,
      rohdecke_mm INTEGER NOT NULL DEFAULT 2600,
      meterriss_mm INTEGER NOT NULL DEFAULT 1000,
      geloescht TEXT
    )''',
    '''CREATE TABLE raum (
      id TEXT PRIMARY KEY,
      geschoss_id TEXT NOT NULL REFERENCES geschoss(id),
      name TEXT NOT NULL,
      kuerzel TEXT NOT NULL,
      rfb_mm INTEGER,
      ffb_mm INTEGER,
      rohdecke_mm INTEGER,
      uk_decke_mm INTEGER,
      umriss TEXT,
      geloescht TEXT
    )''',
    '''CREATE TABLE gewerk (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      kuerzel TEXT NOT NULL,
      farbe INTEGER NOT NULL,
      linie TEXT NOT NULL DEFAULT 'solid',
      reihenfolge INTEGER NOT NULL DEFAULT 0,
      sichtbar INTEGER NOT NULL DEFAULT 1
    )''',
    '''CREATE TABLE objekttyp (
      id TEXT PRIMARY KEY,
      gewerk_id TEXT NOT NULL REFERENCES gewerk(id),
      name TEXT NOT NULL,
      kuerzel TEXT NOT NULL,
      geometrie TEXT NOT NULL,
      schema TEXT NOT NULL DEFAULT '{}'
    )''',
    '''CREATE TABLE wand (
      id TEXT PRIMARY KEY,
      geschoss_id TEXT NOT NULL REFERENCES geschoss(id),
      x1 INTEGER NOT NULL, y1 INTEGER NOT NULL,
      x2 INTEGER NOT NULL, y2 INTEGER NOT NULL,
      dicke_mm INTEGER NOT NULL DEFAULT 240,
      zustand TEXT NOT NULL DEFAULT 'bestand',
      wandtyp_id TEXT,
      geloescht TEXT
    )''',
    '''CREATE TABLE objekt (
      id TEXT PRIMARY KEY,
      typ_id TEXT NOT NULL REFERENCES objekttyp(id),
      geschoss_id TEXT NOT NULL REFERENCES geschoss(id),
      raum_id TEXT REFERENCES raum(id),
      bauteil TEXT,
      kennung TEXT NOT NULL,
      geometrie TEXT NOT NULL,
      z_mm INTEGER,
      z_bezug TEXT,
      lage TEXT,
      status TEXT NOT NULL DEFAULT 'geplant',
      eigenschaften TEXT NOT NULL DEFAULT '{}',
      produkt_id TEXT,
      normkennzeichen TEXT,
      erstellt TEXT NOT NULL,
      geaendert TEXT NOT NULL,
      geloescht TEXT
    )''',
    '''CREATE TABLE aenderung (
      nr INTEGER PRIMARY KEY AUTOINCREMENT,
      zeit TEXT NOT NULL,
      benutzer TEXT NOT NULL,
      tabelle TEXT NOT NULL,
      datensatz TEXT NOT NULL,
      aktion TEXT NOT NULL,
      daten TEXT
    )''',
    'CREATE INDEX idx_wand_geschoss ON wand(geschoss_id)',
    'CREATE INDEX idx_raum_geschoss ON raum(geschoss_id)',
    'CREATE INDEX idx_objekt_geschoss ON objekt(geschoss_id)',
  ],
  // Version 2 – Materialien, Wandtypen mit Schichten (Stufe 1, Schritt 2)
  [
    '''CREATE TABLE material (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      kategorie TEXT NOT NULL,
      farbe INTEGER NOT NULL,
      schraffur TEXT NOT NULL DEFAULT 'keine',
      einheit TEXT NOT NULL DEFAULT 'm²',
      reihenfolge INTEGER NOT NULL DEFAULT 0,
      geloescht TEXT
    )''',
    '''CREATE TABLE wandtyp (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      reihenfolge INTEGER NOT NULL DEFAULT 0,
      geloescht TEXT
    )''',
    '''CREATE TABLE wandtyp_schicht (
      id TEXT PRIMARY KEY,
      wandtyp_id TEXT NOT NULL REFERENCES wandtyp(id),
      reihenfolge INTEGER NOT NULL,
      material_id TEXT NOT NULL REFERENCES material(id),
      dicke_mm INTEGER NOT NULL,
      geloescht TEXT
    )''',
    'CREATE INDEX idx_schicht_wandtyp ON wandtyp_schicht(wandtyp_id)',
    'CREATE INDEX idx_wand_wandtyp ON wand(wandtyp_id)',
    // Bezugspunkt: Punkt im Raum, über den der Raum seinen Wandzug wiederfindet.
    'ALTER TABLE raum ADD COLUMN bezug_x INTEGER',
    'ALTER TABLE raum ADD COLUMN bezug_y INTEGER',
  ],
  // Version 3 – Maßanzeige je Wand (null = Voreinstellung des Grundrisses)
  [
    'ALTER TABLE wand ADD COLUMN massanzeige TEXT',
  ],
  // Version 4 – freie Bemaßungen im Grundriss
  [
    '''CREATE TABLE bemassung (
      id TEXT PRIMARY KEY,
      geschoss_id TEXT NOT NULL REFERENCES geschoss(id),
      x1 INTEGER NOT NULL, y1 INTEGER NOT NULL,
      x2 INTEGER NOT NULL, y2 INTEGER NOT NULL,
      abstand_mm INTEGER NOT NULL DEFAULT 500,
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    'CREATE INDEX idx_bemassung_geschoss ON bemassung(geschoss_id)',
  ],
  // Version 5 – Wände sperren, Ecken verbinden je Wand, Winkelmaße
  [
    'ALTER TABLE wand ADD COLUMN gesperrt INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE wand ADD COLUMN verbinden INTEGER', // null = Projektvorgabe, 0 = aus, 1 = an
    '''CREATE TABLE winkelmass (
      id TEXT PRIMARY KEY,
      geschoss_id TEXT NOT NULL REFERENCES geschoss(id),
      wand1_id TEXT NOT NULL REFERENCES wand(id),
      wand2_id TEXT NOT NULL REFERENCES wand(id),
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
  ],
  // Version 6 – Planvorlage je Geschoss, Öffnungen in Wänden
  [
    '''CREATE TABLE planvorlage (
      id TEXT PRIMARY KEY,
      geschoss_id TEXT NOT NULL REFERENCES geschoss(id),
      datei TEXT NOT NULL,
      x_mm INTEGER NOT NULL DEFAULT 0,
      y_mm INTEGER NOT NULL DEFAULT 0,
      um_pro_px INTEGER NOT NULL DEFAULT 10000,
      deckkraft INTEGER NOT NULL DEFAULT 50,
      sichtbar INTEGER NOT NULL DEFAULT 1,
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    '''CREATE TABLE oeffnung (
      id TEXT PRIMARY KEY,
      wand_id TEXT NOT NULL REFERENCES wand(id),
      art TEXT NOT NULL,
      abstand_mm INTEGER NOT NULL,
      breite_mm INTEGER NOT NULL,
      hoehe_mm INTEGER NOT NULL,
      bruestung_mm INTEGER NOT NULL DEFAULT 0,
      band_rechts INTEGER NOT NULL DEFAULT 0,
      aufgehen_links INTEGER NOT NULL DEFAULT 0,
      eigenschaften TEXT NOT NULL DEFAULT '{}',
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    'CREATE INDEX idx_oeffnung_wand ON oeffnung(wand_id)',
  ],
  // Version 7 – Fotos: Medium, Fotomarker im Grundriss, Zuordnung zu Objekten
  [
    '''CREATE TABLE medium (
      id TEXT PRIMARY KEY,
      datei TEXT NOT NULL,
      art TEXT NOT NULL DEFAULT 'foto',
      pruefsumme TEXT,
      aufnahme TEXT,
      autor TEXT,
      groesse INTEGER,
      notiz TEXT,
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    '''CREATE TABLE fotomarker (
      id TEXT PRIMARY KEY,
      medium_id TEXT NOT NULL REFERENCES medium(id),
      geschoss_id TEXT NOT NULL REFERENCES geschoss(id),
      x_mm INTEGER,
      y_mm INTEGER,
      richtung INTEGER,
      raum_id TEXT REFERENCES raum(id),
      bauteil TEXT
    )''',
    '''CREATE TABLE medienzuordnung (
      id TEXT PRIMARY KEY,
      medium_id TEXT NOT NULL REFERENCES medium(id),
      ziel_tabelle TEXT NOT NULL,
      ziel_id TEXT NOT NULL,
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    'CREATE INDEX idx_fotomarker_geschoss ON fotomarker(geschoss_id)',
    'CREATE INDEX idx_zuordnung_medium ON medienzuordnung(medium_id)',
  ],
  // Version 8 – Produkte, Händlerangebote, Kostenpositionen
  [
    '''CREATE TABLE produkt (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      hersteller TEXT,
      artikelnummer TEXT,
      ean TEXT,
      einheit TEXT NOT NULL DEFAULT 'Stk',
      bild TEXT,
      datenblatt TEXT,
      platzhalter INTEGER NOT NULL DEFAULT 0,
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    '''CREATE TABLE haendlerangebot (
      id TEXT PRIMARY KEY,
      produkt_id TEXT NOT NULL REFERENCES produkt(id),
      haendler TEXT NOT NULL,
      link TEXT,
      preis_cent INTEGER NOT NULL,
      steuer INTEGER NOT NULL DEFAULT 1900,
      preisdatum TEXT,
      geloescht TEXT
    )''',
    '''CREATE TABLE kostenposition (
      id TEXT PRIMARY KEY,
      kostenart TEXT NOT NULL DEFAULT 'Material',
      text TEXT NOT NULL,
      produkt_id TEXT REFERENCES produkt(id),
      objekt_id TEXT REFERENCES objekt(id),
      raum_id TEXT REFERENCES raum(id),
      gewerk_id TEXT REFERENCES gewerk(id),
      menge_milli INTEGER NOT NULL DEFAULT 1000,
      einheit TEXT NOT NULL DEFAULT 'Stk',
      einzel_cent INTEGER NOT NULL DEFAULT 0,
      steuer INTEGER NOT NULL DEFAULT 1900,
      lohn_cent INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'geplant',
      herkunft TEXT NOT NULL DEFAULT 'manuell',
      plan_schluessel TEXT,
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
  ],
  // Version 9 – eigene Bemaßungen und Winkelmaße einzeln ausblenden
  [
    'ALTER TABLE bemassung ADD COLUMN versteckt INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE winkelmass ADD COLUMN versteckt INTEGER NOT NULL DEFAULT 0',
  ],
  // Version 10 – Heizrohr als Leitungstyp der Flächenheizung (Startbestand in _migrieren)
  [],
  // Version 11 – Raumart (Raum, Balkon, Terrasse, Loggia); Bodenplatten ohne Wände;
  // Objekttyp Wanddurchbruch (Startbestand in _migrieren)
  [
    "ALTER TABLE raum ADD COLUMN art TEXT NOT NULL DEFAULT 'raum'",
  ],
  // Version 12 – Schränke (Zähler-/Unterverteiler), Geräte auf der Hutschiene, Stromkreise
  [
    '''CREATE TABLE schrank (
      id TEXT PRIMARY KEY,
      geschoss_id TEXT REFERENCES geschoss(id),
      objekt_id TEXT REFERENCES objekt(id),
      name TEXT NOT NULL,
      kennzeichen TEXT NOT NULL,
      art TEXT NOT NULL DEFAULT 'unterverteiler',
      reihen INTEGER NOT NULL DEFAULT 4,
      te_je_reihe INTEGER NOT NULL DEFAULT 12,
      eigenschaften TEXT NOT NULL DEFAULT '{}',
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    '''CREATE TABLE schrankgeraet (
      id TEXT PRIMARY KEY,
      schrank_id TEXT NOT NULL REFERENCES schrank(id),
      reihe INTEGER NOT NULL,
      position INTEGER NOT NULL,
      breite INTEGER NOT NULL,
      art TEXT NOT NULL,
      kennzeichen TEXT NOT NULL,
      bezeichnung TEXT NOT NULL DEFAULT '',
      pole INTEGER NOT NULL DEFAULT 1,
      nennstrom INTEGER,
      charakteristik TEXT,
      fehlerstrom INTEGER,
      phase TEXT,
      vorgeschaltet_id TEXT,
      produkt_id TEXT REFERENCES produkt(id),
      eigenschaften TEXT NOT NULL DEFAULT '{}',
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    '''CREATE TABLE stromkreis (
      id TEXT PRIMARY KEY,
      schrank_id TEXT NOT NULL REFERENCES schrank(id),
      nummer TEXT NOT NULL,
      bezeichnung TEXT NOT NULL DEFAULT '',
      schutz_id TEXT REFERENCES schrankgeraet(id),
      querschnitt INTEGER NOT NULL DEFAULT 150,
      leitung TEXT NOT NULL DEFAULT 'NYM-J 3x1,5',
      leistung_w INTEGER NOT NULL DEFAULT 0,
      eigenschaften TEXT NOT NULL DEFAULT '{}',
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    'CREATE INDEX idx_schrankgeraet_schrank ON schrankgeraet(schrank_id)',
    'CREATE INDEX idx_stromkreis_schrank ON stromkreis(schrank_id)',
  ],
  // Version 13 – Objekttyp LED-Streifen / Lichtband (Startbestand in _migrieren)
  [],
  // Version 14 – Bautagebuch, Aufgaben (mit Abhängigkeit und Wartungsintervall), Prüfprotokolle
  [
    '''CREATE TABLE tagebuch (
      id TEXT PRIMARY KEY,
      datum TEXT NOT NULL,
      text TEXT NOT NULL DEFAULT '',
      stunden_hundertstel INTEGER NOT NULL DEFAULT 0,
      raeume TEXT NOT NULL DEFAULT '[]',
      gewerke TEXT NOT NULL DEFAULT '[]',
      wetter TEXT NOT NULL DEFAULT '',
      personen TEXT NOT NULL DEFAULT '',
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    '''CREATE TABLE aufgabe (
      id TEXT PRIMARY KEY,
      titel TEXT NOT NULL,
      beschreibung TEXT NOT NULL DEFAULT '',
      raum_id TEXT REFERENCES raum(id),
      gewerk_id TEXT REFERENCES gewerk(id),
      faellig TEXT,
      status TEXT NOT NULL DEFAULT 'offen',
      abhaengig_von TEXT,
      intervall_tage INTEGER,
      erledigt_am TEXT,
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
    '''CREATE TABLE pruefprotokoll (
      id TEXT PRIMARY KEY,
      art TEXT NOT NULL,
      datum TEXT NOT NULL,
      raum_id TEXT REFERENCES raum(id),
      objekt_id TEXT REFERENCES objekt(id),
      messwerte TEXT NOT NULL DEFAULT '{}',
      ergebnis TEXT NOT NULL DEFAULT 'bestanden',
      pruefer TEXT NOT NULL DEFAULT '',
      notiz TEXT NOT NULL DEFAULT '',
      erstellt TEXT NOT NULL,
      geloescht TEXT
    )''',
  ],
  // Version 15 – Fotomarkierungen (Pfeile, Kreise, Text, Maße) und 360°-Panoramen
  [
    "ALTER TABLE medium ADD COLUMN markierungen TEXT NOT NULL DEFAULT '[]'",
    'ALTER TABLE medium ADD COLUMN panorama INTEGER NOT NULL DEFAULT 0',
  ],
  // Version 16 – Eigenschaften für Öffnungen (Bauelement, Einbau, Sonnenschutz), Baustoffe (Bauphysik) und Räume (Heizlast)
  [
    "ALTER TABLE material ADD COLUMN eigenschaften TEXT NOT NULL DEFAULT '{}'",
    "ALTER TABLE raum ADD COLUMN eigenschaften TEXT NOT NULL DEFAULT '{}'",
  ],
  // Version 17 – Objekttypen für Verbindungselemente (Fittings, Halter) und Armaturen (Startbestand in _migrieren)
  [],
  // Version 18 – Gewerk Brandschutz mit Rauchwarnmeldern, Feuerlöschern, Abschottungen … (Startbestand in _migrieren)
  [],
];
