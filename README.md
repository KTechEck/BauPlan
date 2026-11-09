# BauSpur

Planung und Dokumentation der Gebäudesanierung – Desktop-Programm für Windows (Flutter).
Lastenheft und Oberflächenentwürfe liegen als Artifacts in Claude.

## Stand: Grundgerüst (Stufe 1, Schritt 1)

- Projekt anlegen und öffnen (Projektordner, z. B. auf der Synology)
  - Ordnerstruktur nach Datenmodell: `planstand/`, `eingang/`, `medien/`, `dokumente/`, `exporte/`, `backup/`
  - Projektdatenbank `projekt.bauspur` (SQLite) mit nummerierten Migrationen
  - Sperrdatei `projekt.lock` gegen gleichzeitiges Bearbeiten auf zwei PCs
  - Sicherung bei jedem Öffnen nach `backup/` (die letzten 20 Stände)
  - Änderungsprotokoll jeder Änderung (Tabelle `aenderung`)
- Hauptfenster mit Modulleiste, Projektbaum (Gebäude → Geschoss → Raum), Statusleiste
- Geschosse mit Bezugshöhen (RFB, FFB, Rohdecke, Meterriss), Räume mit eigenen Höhen
- Höhenrechner (Projekt-Seite): Umrechnen zwischen allen Bezügen, auch mit Raumhöhen
- Grundriss-Editor: Wände zeichnen (Raster, Endpunkt-Fang, rechtwinklig, Länge per Tastatur),
  auswählen, Dicke/Zustand ändern, löschen, Rückgängig, Zoom und Verschieben
- Einstellungen: Gewerke mit Farbe und Startsichtbarkeit
- Startbestand: 9 Gewerke und 33 Objekttypen

## Stand: Räume und Wandtypen (Stufe 1, Schritt 2)

- Datenbank-Migration 2: Materialien, Wandtypen mit Schichten, Bezugspunkt je Raum
  (bestehende Projekte werden beim Öffnen migriert und bekommen den Startbestand)
- Einstellungen → Bibliothek: Materialien (Kategorie, Farbe, Mengeneinheit) und Wandtypen
  (Schichten mit Material und Dicke, Schnittvorschau, Kopieren, Löschen)
- Startbestand: 16 Materialien, 5 Wandtypen (z. B. Außenwand KS 175 + WDVS 160)
- Grundriss: Wandtyp beim Zeichnen wählen oder einer Wand zuweisen; Dicke = Summe der Schichten,
  Schichten werden farbig gezeichnet, „Wand umdrehen“ spiegelt den Aufbau.
  Ändert sich ein Wandtyp, ziehen alle Wände dieses Typs nach.
- Raumerkennung: geschlossene Wandzüge (auch mit T-Stößen, Kreuzungen, durchlaufenden Wänden)
  werden als Flächen erkannt; lichte Fläche und lichter Umfang (Innenkante Wand). Abbruchwände
  zählen nicht. Räume finden ihre Fläche über einen Bezugspunkt und werden bei jeder
  Wandänderung nachgeführt; offene Wandzüge und zwei Räume in einer Fläche werden markiert.
- Raumwerkzeug (R): in eine erkannte Fläche klicken → Raum anlegen oder vorhandenen Raum zuordnen;
  rechts Fläche, Umfang, lichte Höhe, Rauminhalt; Projektbaum zeigt die Fläche.

## Einrichten (einmalig)

`Installieren.cmd` doppelklicken. Das Skript installiert Git, Visual Studio 2022 Community
(„Desktopentwicklung mit C++“), VS Code und das Flutter SDK, richtet das Projekt ein, lässt die Tests
laufen, baut das Programm und legt ein lokales Git-Repository an. Protokoll: `tools\install.log`.

Danach starten:

```powershell
cd $HOME\Documents\BauSpur
flutter run -d windows
```

Umzug auf einen anderen PC: siehe `tools\ENTWICKLUNG.md`.

## Bedienung Grundriss

| Aktion | Eingabe |
| --- | --- |
| Wand zeichnen | `W`, dann Punkte klicken |
| Genaue Länge und Winkel | nach dem ersten Punkt `Tab` → Länge (umschaltbar: Achsmaß oder Innenmaß – innen = Raumseite bis zur Innenseite der nächsten, rechtwinkligen Wand), nochmal `Tab` → Winkel (0° rechts, 90° oben), `Enter` setzt die Wand; ohne Winkel gibt die Maus die Richtung. Eine Ziffer tippen springt ebenfalls in die Länge |
| Schräge Wände | Winkelfang in der Werkzeugleiste: frei, 15°, 30° oder 45°-Schritte; `Umschalt` erzwingt 90° |
| Maße | Werkzeugleiste „Maße“ ohne Auswahl = Voreinstellung: innen + außen, nur Achse, nur innen, Achse + innen oder keine; mit gewählten Wänden stellt dasselbe Feld deren eigene Maße ein (Ecken und T-Stöße berücksichtigt) |
| Länge nachträglich ändern | Wand anklicken (oder doppelklicken) → rechts Länge eintippen, `Enter`; „Längen als“ in der Werkzeugleiste: Achsmaß oder Innenmaß; anschließende Wände wandern mit |
| Rechtwinklig erzwingen | `Umschalt` halten |
| Kette beenden | `Esc` oder denselben Punkt nochmal klicken |
| Auswahl | `V`, Wand oder Raum anklicken |
| Raum anlegen | `R`, in eine erkannte (graue) Fläche klicken |
| Planvorlage | Werkzeugleiste „Planvorlage“: Bild laden (PNG/JPG, wird nach `dokumente/plaene` kopiert), kalibrieren (zwei Punkte + echter Abstand), verschieben, Deckkraft, ein/aus |
| Tür / Fenster / Durchbruch | `O`, Art und Breite oben wählen, in eine Wand klicken; anklicken → Maße, Brüstung, Anschlag und Aufschlagseite ändern |
| Winkel bemaßen | `K`, zwei Wände mit gemeinsamer Ecke anklicken; Doppelklick auf den Bogen → Winkel eintippen, Wand dreht sich |
| Maße ändern | Doppelklick auf ein Wandmaß (oder die Wand) bzw. eine eigene Bemaßung → Wert eintippen, `Enter`; verbundene Wände folgen, gesperrte bleiben stehen; „Maß ausblenden“ blendet ein Wandmaß aus |
| Sperren / Ecken verbinden | rechts bei der Wand „Gesperrt“ und „Ecken verbinden“; Werkzeugleiste „Ecken“ (Projektvorgabe) und „Neue Wände“ |
| Bemaßen | `M`, zwei Punkte klicken (Wandecken, -enden, -mitten werden gefangen), Maßlinie mit der Maus versetzen, klicken; in der Auswahl anklicken und `Entf` |
| Fangen | Endpunkt, Wandecke (Innen-/Außenkante), Mitte, Lot, auf Wand (Abstand im Raster, Abstände zu beiden Enden am Cursor) |
| Start mit Abstand auf einer Wand | Maus auf die Wand, `Tab`, Abstand vom markierten Ende eintippen, `Enter` |
| Löschen / Rückgängig | `Entf` / `Strg+Z` |
| Ansicht verschieben | rechte/mittlere Maustaste, Leertaste + Ziehen, Touchpad mit zwei Fingern, Umschalt + Mausrad, Pfeiltasten; beim Zeichnen am Rand wandert die Ansicht mit |
| Zoomen | Mausrad oder Touchpad spreizen |
| Mehrere wählen | Rahmen aufziehen (nach rechts: ganz drin, nach links: angeschnitten), Umschalt+Klick, `Strg+A` |
| Auswahl verschieben | gewählte Wand ziehen (rastet aufs Raster) oder Pfeiltasten (mit Umschalt ×10); Räume wandern mit |

## Hinweise

- SQLite auf einem Netzlaufwerk ist nur für **einen** schreibenden PC gedacht. Genau dafür gibt es die
  Sperrdatei; die App schreibt später nur in `eingang/`.
- Alle Längen werden als ganze Millimeter gespeichert.

## Aufbau

```text
lib/
  app/        App, Farben, Theme
  core/       Höhenbezüge, Kennungen, IDs, Raumerkennung (ohne Flutter, testbar)
  data/       Schema/Migrationen, Projektordner + Datenbank, Startdaten, Programmeinstellungen
  state/      AppState (offenes Projekt, Modul, Auswahl)
  ui/         Startseite, Hauptfenster, Projektbaum, Dialoge, Einstellungen, Bibliothek
    floorplan/  Grundriss-Editor und Zeichnung
test/         Tests für Höhen, Kennungen, Raumerkennung, Datenbank, Oberfläche
```

## Modul Installation (Stufe 1, Schritt 4)

| Aktion | Eingabe |
| --- | --- |
| Objekt setzen | „Setzen“, Objekttyp wählen (nach Gewerk), klicken; Geräte fangen die Wandoberfläche |
| Leitung / Leerrohr | Punkte klicken, `Enter` oder gleicher Punkt beendet, Rücktaste nimmt den letzten Punkt zurück, `Umschalt` rechtwinklig |
| Fläche (Heizkreis) | Eckpunkte klicken, `Enter` schließt |
| Ebenen | rechts je Gewerk ein-/ausblenden |
| Eigenschaften | Objekt anklicken: Kennung, Höhe mit Bezug (Umrechnung in alle Bezüge), Lage, Status, Normkennzeichen |

Kennungen werden automatisch vergeben (Geschoss-Raum-Typ-Nummer, z. B. `EG-BAD-SD-03`) und bleiben stabil.

## Modul Fotos (Stufe 1, Schritt 5)

- „Fotos importieren“ (mehrere auf einmal); Ablage lesbar unter `medien/<Geschoss>/<Raum>/<Datum>_<Geschoss>-<Raum>_<Kurz-ID>.jpg`
- Nach dem Import: im Grundriss klicken, wo das Foto aufgenommen wurde, dann wohin die Kamera geschaut hat; das nächste unverortete Foto folgt automatisch
- Galerie rechts (Raum im Projektbaum wählen → nur dieser Raum), Foto anklicken: Vorschau, Notiz, „Zeigt Objekte“ (nahe Objekte zuerst), neu verorten, löschen

## Modul Kosten (Stufe 1, Schritt 6)

- Kostenliste: manuelle Positionen und Positionen „aus Plan“ (Stück, Meter, m² je Objekttyp und Produkt, automatisch nachgeführt); Klick auf eine Zeile bearbeitet Preis, MwSt., Status (geplant … bezahlt), Kostenart, Gewerk
- Summen netto/MwSt./brutto, bezahlt, je Gewerk; Filter nach Status und Gewerk
- Produkte mit Händlerpreisen; im Modul Installation am Objekt wählbar – das günstigste Angebot wird übernommen

## Modul Export (Stufe 1, Schritt 7)

- PDF mit Grundriss- und Installationsplänen je Geschoss (A3/A4 quer, Maßstab 1:50/1:100/1:200 oder passend, Plankopf) und Kostenliste; Ablage in `exporte/`

## Tastenkürzel

In allen Planmodulen gleich; `F1` zeigt die Übersicht (siehe `lib/ui/tastenkuerzel.dart`).

## Wandansicht (Stufe 2, Schritt 1)

- Aufruf: Grundriss → Wand wählen → „Ansicht <Raum>“; Installation → Doppelklick auf eine Wand
- Blick von der Raumseite: Wandfläche RFB … Rohdecke, Linien für FFB, Meterriss, Rohdecke; Türen/Fenster in Rohbaumaßen
- Dosen/Geräte in echter Höhe mit Kennung und Höhe samt Bezug, Leitungen in der Wand, Maßkette unten
- Setzen (P) und Verschieben per Ziehen (Lage und Höhe, 10-mm-Raster), Entf, Strg+Z; „andere Seite“ wechselt die Wandseite

## FBH-Verlegeplan (Stufe 2, Schritt 2)

- Heizkreis (Fläche, Gewerk Flächenheizung) anklicken: Verlegeabstand, Muster (Schnecke/Mäander), Randabstand, Zuleitung („vom Heizkreisverteiler“ rechnet den Weg zum nächsten HV)
- Verlegebild im Plan, Rohrlänge inkl. Vor- und Rücklauf, Warnung über 120 m
- Kostenliste: Heizrohr in Metern

## Deckenansicht, Heizkreisverteiler, Leitungen in der Wandansicht (Stufe 2, Schritt 3)

- Deckenansicht je Raum (`lib/ui/decke/`): von unten (gespiegelt, wie beim Montieren) oder von oben;
  Leuchten, Melder, Luftventile usw. mit `P` setzen, ziehen verschiebt (Abstände zu den Raumkanten),
  Unterkante abgehängte Decke, Erfassungsbereich von Präsenz-/Bewegungsmeldern. Öffnen über das
  Raumfeld im Grundriss, das Symbol am gewählten Raum im Projektbaum oder „Deckenansicht“ in der Installation.
- Heizkreisverteiler (`lib/core/verteiler.dart`, `lib/ui/verteiler/`): Montageart in der Installation,
  „Verteiler bearbeiten …“ öffnet den Editor (Abgänge, Ventile/Stellantriebe, Zuleitung, Stückliste,
  Belegung mit Heizkreisen). Der Schrank erscheint im Plan und im PDF in bzw. vor der nächsten Wand.
- Wandansicht: Werkzeug „Leitung“ (`L`) zeichnet Rohre mit Steigstrecken (Höhe je Punkt in
  `eigenschaften.z_abs`, die Länge zählt räumlich). Neuer Leitungstyp „Heizrohr / Anbindeleitung“ (HR, Migration 10).

## Rückmeldung 07.11. und Plan/Ist + Einkaufsliste (Stufe 2, Schritt 4)

- Grundriss: Längen als Achs-, Innen- oder Außenmaß; Wandlänge „Richtung bleibt“ oder „nur Eckpunkt“; Fang parallel/rechtwinklig
  zu schrägen Wänden, Verlängerung, Schnittpunkt von Fluchten, Flucht zu Wandenden; „Parallel zu …“, „Verlängern“;
  Bemaßung an einer Laibung verschiebt Tür/Fenster; Raumart und Balkon/Terrasse/Loggia als Bodenplatte (Migration 11).
- Installation: Objekte ziehen, erst Gewerk dann Gerät, Wand/Seite eines Geräts, „gehört zu Raum“, Wanddurchbruch (WD);
  Leitungen hängen über `eigenschaften.anfang/ende` zusammen (`lib/core/leitungsnetz.dart`): Übergänge in andere Ebenen,
  Nachbarwand, Bündel, Anschlusspunkte (`lib/core/anschluesse.dart`).
- Verteiler-Editor: Ventiltypen Vor-/Rücklauf, Thermometer, Überströmventil, STB, Schmutzfänger, Hinweise, Skizze.
- Kosten → „Plan/Ist“ (Fortschritt je Objektart, Kosten je Gewerk) und „Einkaufsliste“ (nach Händler, Verschnitt-Zuschlag,
  abhaken = bestellt, CSV und Handy-Abhakliste nach `exporte/`), Kern in `lib/core/auswertung.dart`.

## DXF-Import (Stufe 2, Schritt 5)

- Grundriss → Planvorlage → „Bild oder DXF laden …“: ASCII-DXF (LINE, LWPOLYLINE, POLYLINE, ARC, CIRCLE, TEXT, MTEXT, Blöcke)
  wird als Linienvorlage gezeichnet; Einheit aus `$INSUNITS` (mm/cm/m/Zoll), Kalibrieren und Verschieben wie bei Bildern.
- „Wände aus DXF übernehmen …“: Layer wählen; parallele Doppellinien (5–60 cm Abstand) werden zu Wänden mit dieser Dicke,
  Ecken werden geschlossen, damit die Raumerkennung greift; einzelne Linien optional mit Standarddicke. Kern: `lib/core/dxf.dart`.

## Modul Verteiler: Schrankplanung (Stufe 2, Schritt 6)

- Schränke (Zählerschrank, Unterverteiler, Netzwerk) mit Reihen und TE, Kennzeichen nach DIN EN 81346 (=UV1-F3); aus
  Verteiler-Objekten im Grundriss anlegbar. Migration 12: Tabellen `schrank`, `schrankgeraet`, `stromkreis`.
- Schrankansicht: Geräte (Hauptschalter, RCD, LS, FI/LS, SPD, KNX, Netzteil, Relais, Klemmen) setzen und ziehen; LS bekommt
  den RCD links davon als Vorschaltung und die am wenigsten belegte Phase; Belegung/Reserve, Last je Phase, Hinweise
  (fehlender RCD, Querschnitt zu Schutzorgan, Überlast, Schieflast, zu viele Kreise je RCD).
- Stromkreisliste mit Schutzorgan, Querschnitt, Leitung, Last, Räumen und Objekten („zeigen“ springt in die Installation);
  Zuordnung der Objekte in der Installation (Feld „Stromkreis“). Übersichtsschaltbild (einpolig) und Beschriftungsstreifen
  als PDF in echter Größe. Kern: `lib/core/schrank.dart`.
- Verdrahtung (Ansicht im Modul Verteiler): Drähte werden aus der Schrankplanung erzeugt (Einspeisung → Hauptschalter → FI → LS,
  LS → Klemme/Abgang mit N über den FI und PE), Kammschienen ersetzen Einzeldrähte; Aderfarben, Querschnitt nach Schutzorgan,
  geschätzte Längen, Filter nach Leiter oder Stromkreis, Verdrahtungsliste als CSV, Material in die Kostenliste,
  Hinweise (Kammschiene ohne Einspeisung, Abgang ohne Klemme). Klemmen bekommen „Abgang für Stromkreis“. Kern: `lib/core/verdrahtung.dart`.
- KNX und Home Assistant (Ansicht „KNX / Home Assistant“ im Modul Verteiler): KNX-Aktoren mit Aktortyp, Kanälen und
  physikalischer Adresse; Kanalbelegung Aktorkanal → Verbraucher; Gruppenadressen (dreistufig) automatisch aus der Belegung
  vorschlagen, bearbeiten, Doppelte erkennen; Export als ETS-CSV und Home-Assistant-YAML (`knx:`), beides nach `exporte/`
  und in die Zwischenablage. In der Installation: Home-Assistant-Entität und PA je Objekt. Kern: `lib/core/knx.dart`;
  Gruppenadressen in den Projekteinstellungen (`knx_gruppenadressen`).
- Netzwerkschrank: Patchfeld (12–48 Ports) Port → Netzwerkdose → Raum, als CSV.

## Eigene Sensoren und Signalleitungen (Stufe 2, Schritt 7)

- Einstellungen → Bibliothek → Eigene Sensoren: Vorlagen mit Kategorie, Montage, Versorgung, Protokoll, Maßen, Anschlüssen mit
  Aderfarbe, Home-Assistant-Entitäten als Vorlage, Dateien (Schaltplan, Firmware, STL …, in `dokumente/sensoren/`) und Notiz;
  Weitergabe als Inhaltspaket (JSON). Gespeichert in der Projekteinstellung `sensoren`.
- Installation: Objekt „Eigener Sensor“ bekommt eine Vorlage; Anschlüsse erscheinen als Andockpunkte in der Wandansicht,
  jede Instanz erhält eigene Entitäts-IDs. Signal-, Bus- und Netzwerkleitungen: Kabeltyp, Aderbelegung (Vorschlag nach dem
  Protokoll des angeschlossenen Sensors) und Topologie (Linie/Stern/Baum). Kern: `lib/core/sensoren.dart`.

## Lichtplaner (Stufe 2, Schritt 8)

- Deckenansicht: Leuchten mit Lichtstrom, Abstrahlwinkel, Lichtfarbe, Leistung, dimmbar; „Lichtverteilung“ zeigt die
  Beleuchtungsstärke auf der Arbeitsebene als Farbfläche (Em, Emin, U0, Anteil zu dunkler Fläche) gegen einen Zielwert je
  Raum (Vorschlag nach Raumname, einstellbar). Vereinfachte Abschätzung, keine lichttechnische Berechnung.
- LED-Streifen / Lichtband (L, neuer Objekttyp LB, Migration 13): W/m, lm/m, Spannung, Abstrahlrichtung, Kanäle;
  Netzteil mit 20 % Reserve, Einspeisungen nach Spannungsabfall; indirektes Licht geht pauschal in die Rechnung ein.
- Präsenz-/Bewegungsmelder: Erfassung sitzend, frontal, quer; nicht erfasste Flächen werden schraffiert.
- Lichtszenen je Raum mit Helligkeit je Leuchte/Streifen. Kern: `lib/core/licht.dart`.

## Modul Haustechnik: Technikraum und Schächte (Stufe 2, Schritt 9)

- Technikraum: Geräte mit echten Maßen (Wärmepumpe, Speicher, Puffer, MAG, Verteiler, Hausanschlüsse, Zähler-/Netzwerkschrank,
  Lüftungsgerät) setzen, ziehen, drehen (R); Wartungsfreiräume schraffiert; Vorlagen „Heizraum“ und „Technikraum“;
  Kollisionen (Überlappung, Gerät im Freiraum, außerhalb des Raums) und „Elektro unter wasserführender Leitung“.
  Geräte mit Maßen erscheinen in der Wandansicht als Rechteck. Daten in Objekt.eigenschaften (`geraet`, `masse`, `drehung`, `freiraum`, `montage`).
- Schächte & Trassen: Schacht, Kabelkanal, Kabelrinne, Leerrohrbündel, Deckentrasse mit Innenmaßen und Geschossen; Belegung aus
  Vorlagen oder aus Leitungen im Grundriss; Querschnitt nach Zonen (Abwasser unten … Daten oben), Füllgrad/Reserve, Regeln
  (Trennung Strom/Daten, warmgehend neben Elektro, Abschottung), Steigschema, Länge im Schacht in die Kostenliste.
  Gespeichert in der Projekteinstellung `schaechte`. Kern: `lib/core/technik.dart`.

## KI-Assistent (Stufe 2, Schritt 10)

- Neues Modul „KI-Assistent“: Planprüfung über alle Module mit festen Regeln (offene Wandzüge, Objekte ohne Raum, Heizkreislänge,
  Kreise ohne Verteilerabgang, Verteiler-Ausstattung, Elektro ohne Stromkreis, Licht unter Zielwert, Technikraum-Kollisionen,
  Elektro unter Wasser, Schrank-/Verdrahtungshinweise, doppelte Gruppenadressen, Schächte). Status je Hinweis: offen, erledigt,
  ignoriert, bewusst so geplant (Projekteinstellung `pruefung_status`, im Änderungsprotokoll). Klick springt zum Objekt.
- „KI-Prüfung“ und „Fragen“: lokales Sprachmodell mit Ollama-kompatibler Schnittstelle (Adresse/Modell in den Programm-
  einstellungen), Einschätzungen getrennt von den Regeln gekennzeichnet; Cloud nur, wenn eingeschaltet, und dann mit Vorschau
  dessen, was das Heimnetz verlässt. Fragen funktionieren auch ohne Modell als Stichwortsuche über Räume, Objekte, Stromkreise.
- Eigene Grenzwerte je Projekt (Kreislänge, Verteilerreserve, Abstand Elektro/Wasser, Licht). Kern: `lib/core/ki.dart`,
  Regeln in `lib/ui/assistent/projektpruefung.dart`. Der Assistent liest nur und schlägt vor.

## Stufe 3 (begonnen 07.11.)

- KI-Einrichtung (KI-Assistent → Einstellungen): prüft, ob Ollama läuft, installiert es per winget oder öffnet die
  Download-Seite, liest Arbeitsspeicher und Grafikkarte, empfiehlt und lädt ein passendes Modell (`lib/core/ki_einrichtung.dart`).
- Modul Bautagebuch (Migration 14): Tageseinträge (Räume, Gewerke, Stunden, Wetter, Wer; Fotos des Tages automatisch),
  Aufgaben mit Abhängigkeit und Wartungsintervall, Prüfprotokolle mit Vorlagen (Druckprobe, Isolationsmessung,
  Belegreifheizen …), Verlauf der Statuswechsel aus dem Änderungsprotokoll.
- Export: Hausdokumentation komplett (Deckblatt, Inhaltsverzeichnis, Pläne, Räume, Verteiler mit Stromkreisliste, KNX,
  Prüfprotokolle, Tagebuch, Fotos je Raum, Kosten) und Projekt als ZIP (neben dem Projektordner in `BauSpur-Sicherungen`).
- Fotos (Migration 15): Markieren mit Pfeil, Kreis, Rechteck, Maß und Text (Original bleibt unverändert);
  360°-Panoramen mit Rundumansicht.
