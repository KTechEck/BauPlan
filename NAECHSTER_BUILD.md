# Für den nächsten geplanten Build

Tims Regel (2026-11-07): Änderungswünsche sammeln und erst zum nächsten geplanten Build einbauen –
außer er wünscht ausdrücklich „sofort“.

## Gesammelte Wünsche (Rückmeldung zum Build vom 07.11., als nächster Build umzusetzen)

**Stand 07.11. nachmittags: alle Punkte umgesetzt, dazu Plan/Ist + Einkaufsliste (Kosten-Modul) , DXF-Import (Planvorlage, Wände übernehmen) und Modul Verteiler (Schrankplanung, Stromkreise, Übersichtsschaltbild, Beschriftung, Verdrahtung mit Kammschienen und Verdrahtungsliste, KNX/Home Assistant, Patchfeld; Migration 12), eigene Sensoren und Signalleitungen , Lichtplaner (Migration 13) , Modul Haustechnik (Technikraum, Schächte) und KI-Assistent (Planprüfung, Fragen). Stufe 2 damit komplett. Analyze sauber, 131 Tests grün. Auf Tims Wunsch noch NICHT gebaut – kommt mit dem nächsten Build.**

Programm
- [x] Fenster „maximiert öffnen“ geht nicht: maximiert kurz und springt dann wieder auf klein.

Grundriss – Wände
- [x] Wandlänge ändern: wählen, ob die Wand in ihrer Richtung verlängert wird (Winkel bleibt, Nachbarn
      passen sich an) oder nur der Eckpunkt wandert (Winkel ändert sich).
- [x] Beim Eintippen wählbar, welches Maß gemeint ist: innen, außen oder Achse.
- [x] Winkelfang beim Zeichnen; Wand parallel zu einer anderen Wand setzen.
- [x] Eigene Bemaßungen ändern auch Wände und Türen (die Punkte, an denen sie anschlagen).
- [x] „Wand verlängern“: bestehende Wand über den Raum hinaus erweitern und daran einen neuen Raum zeichnen.
- [x] Fang beim Zeichnen: lotrecht und parallel zu anderen Wänden, weitere sinnvolle Fangpunkte
      (Verlängerung einer Wandachse, Schnittpunkt von Fluchtlinien, Wandmitte, Raster,
      15°-Schritte, Abstand zu Öffnungen).
- [x] Balkon/Terrasse zeichnen können – als Raumart ohne Wände, nur Bodenplatte.

Installation
- [x] Installation, die zu einem Raum gehört, im Nachbarraum verlegen + Wanddurchbruch
      (z. B. Leerrohr in der Wand vom SZ, Durchbruch, Steckdose im Wohnzimmer) – für alle Gewerke.
- [x] Objekte nach dem Setzen verschieben können.
- [x] Darstellen, an welcher Wand und Wandseite eine Steckdose sitzt (statt „auf dem Boden“) –
      Verbindung Grundriss ↔ Wandansicht.
- [x] Beim Setzen erst Gewerk wählen, dann das Gerät.
- [x] Leitung an der Wand: Übergabepunkt in eine andere Ebene festlegen („ab hier unter Estrich /
      in Decke / in Beton …“), Weiterzeichnen im Grundriss mit erkennbarem Zusammenhang (welche Leitung ist welche).
- [x] Übergabe über eine Wandecke berücksichtigen.
- [x] Am Verteiler mehrere Adern/Leitungen übersichtlich übereinander verlegen (Bündel).
- [x] Anschlusspunkte an Objekten: am Heizkreisverteiler je Abgang (Vor-/Rücklauf) passend zur
      Konfiguration; auch andere Objekte mit mehreren Anschlüssen.

Heizkreisverteiler-Editor
- [x] Mehr Ventiltypen.
- [x] Gewählte Zusatzausstattung im Schema skizzieren.

Danach: mit den nächsten Roadmap-Schritten weitermachen.

## Erledigt im Build vom 07.11.2026 (Deckenansicht)

- [x] Deckenansicht je Raum (von unten gespiegelt / von oben), Leuchten und Melder setzen,
      Abhängung (UK Decke), Erfassungsbereich Präsenz-/Bewegungsmelder, Abstände zu den Raumkanten.
- [x] FBH: Editor für den Heizkreisverteiler, Montageart in der Installation, Schrank im Plan und PDF.
- [x] Wandansicht: Werkzeug „Leitung“ (L) mit Steigstrecken; Leitungstyp „Heizrohr / Anbindeleitung“ (HR, Migration 10).

## Im Build vom 08.11.2026 13:00 (für Tims Test; am 07.11. abends war er doch nicht erstellt worden)

Alles oben plus Stufe 2 komplett und der Anfang von Stufe 3 (KI-Einrichtung, Bautagebuch, Hausdokumentation,
Fotomarkierungen/360°). Schema bis Migration 15. Neue Wünsche aus dem Test bitte hier unten sammeln.

## Fertig nach dem Build vom 08.11. 13:00 (noch NICHT gebaut, kommt mit dem nächsten Build)

Stufe 3 damit komplett. Analyze sauber, 153 Tests grün.
- [x] Stromlaufplan nach DIN (Normstufe B) im Modul Verteiler, Ansicht „Stromlaufplan“: Blätter A3 quer mit Spalten 1–14 und Schriftfeld,
      Sammelschienen L1–L3/N/PE, Einspeisung mit Hauptschalter, SPD, FI-Gruppen mit Unterschiene (läuft auf Folgeblätter weiter),
      je LS/FI-LS ein Strompfad mit KNX-Aktorkontakt, Klemmen, Kabel -W, Verbraucher; Betriebsmittelliste mit Querverweisen (Blatt.Spalte); PDF.
- [x] ETS-Projekt abgleichen (KNX / Home Assistant → „ETS-Projekt abgleichen“): .knxproj ohne Passwort oder ETS-CSV einlesen,
      Gruppenadressen und physikalische Adressen vergleichen, fehlende Adressen bzw. ETS-Namen übernehmen.
- [x] Home Assistant live (nur lesend): Zustände der zugeordneten Entitäten, fehlende und nicht zugeordnete Entitäten, Vorschlag zum Korrigieren;
      Token nur in den Einstellungen dieses PCs; Fremdzugriff (z. B. Nabu Casa) abschaltbar und nur über https.

## Rückmeldung zum Test vom 08.11. – umgesetzt (Build 08.11. abends)

Analyze sauber, 166 Tests grün. Schema bis Migration 16 (Eigenschaften für Baustoffe und Räume).

Fehler
- [x] Fenstergröße beim Start verbuggt.
- [x] Schrankeditor: bei mehreren Reihen kann man sich nicht bewegen (scrollen/verschieben).
- [x] Nach Änderungen in den Eigenschaften aktualisieren sich die Bauteile nicht.

Bedienung
- [x] Doppelklick öffnet in jedem Editor die Eigenschaften.
- [x] Geräte: Eigenschaften und Anlegen gut auffindbar, umfangreich wie im Lastenheft.
- [x] Auswahl zum Hinzufügen von Geräten gruppiert und per Dropdown.
- [x] Einmalige Einstellungen (nicht direkt zur Planung) in die Einstellungen, Menüs entlasten.
- [x] KI-Einrichtung: automatisch installieren, nur auswählen; Modellauswahl verständlich; Sprachmodell vom PC aus auf einem Server im Heimnetz einrichten.

Neu
- [x] Fenster-Editor: Fenster genau klassifizieren (Einbautiefe, Dicke, U-Wert …), Datenblatt importieren, per KI oder manuell anlegen.
- [x] Rollläden/Jalousien/Raffstore: verschiedene Systeme, einem Fenster zuordnen, ebenfalls mit Editor und Datenblatt-Import.
- [x] Werkzeug Deckenaufbau zeichnen.
- [x] Heizlastberechnung.
- [ ] Später: hydraulischer Abgleich anhand des Bauplans (Heizlast und Heizkörperleistung je Raum sind die Grundlage, schon da).

Was dazu gebaut wurde:
- Eigenschaften werden auch beim Verlassen eines Feldes übernommen (vorher nur mit Enter – daher „aktualisiert sich nicht“).
- Doppelklick öffnet die Eigenschaften als Fenster (Grundriss: Öffnungen/Räume; Wand und Maß springen wie bisher in die Länge).
- Linke Leiste gegliedert: Planen · Bauteile · Ausführen · Ausgeben.
- Modul Bauteile (Bibliothek für alle Projekte): Fenster, Türen, Rollläden/Jalousien/Raffstores, Fensterbänke, Elektro, Leuchten,
  Sensoren, Schaltschrankgeräte, Technikgeräte, Heizkörper, Sanitär; Datenblatt (PDF/Text) einlesen, Werte per Regeln oder KI.
- Bauteile zuordnen: Fenster/Tür + Sonnenschutz bei der Öffnung, Produkt bei Installationsobjekten, Technikgeräten und Schrankgeräten.
- Schrank: Geräteauswahl gruppiert per Dropdown (inkl. Bibliothek), Geräteeigenschaften umfangreich (Breite, Pole, RCD-Typ,
  Schaltvermögen, SPD-Typ, Verlustleistung, Busstrom …).
- Installation: Gerät/Objekt in einer gruppierten Auswahl (Gewerk → Gerät).
- Einbaudetail je Fenster/Tür: Einbaulage, Anschlussfuge, Laibungsdämmung außen/innen, 2D-Wärmebrückenrechnung (Ψ, fRsi, Uw eingebaut).
- Modul Bauphysik: Heizlast je Raum (DIN EN 12831 vereinfacht), Boden-/Deckenaufbauten zeichnen mit U-Wert, λ der Baustoffe,
  Heizkörperleistung bei Systemtemperatur.
- Einstellungen: KI-Assistent (neue Einrichtung), Prüfregeln, Standort und Klima.
- KI-Einrichtung: Ort wählen (dieser PC / Server im Heimnetz mit Suche, SSH, Synology-Docker, Windows), Fähigkeiten ankreuzen,
  „Alles einrichten“ installiert, startet und lädt automatisch.

## Gesammelte Wünsche (nach dem Build vom 08.11. abends)

- [ ] Wärmebrückenberechnung: technische Erklärungen dazu (was Ψ, fRsi, Uw eingebaut bedeuten, wie gerechnet wird) und Beratung bei erkannten
      Problemen mit Lösungsvorschlägen, wie sie sich vermeiden lassen (z. B. Einbaulage, Laibungsdämmung, Überdämmung des Rahmens).
- [ ] Hinweise, Warnungen, erkannte Probleme und Schwachstellen nicht als rechte Seitenleiste (verkleinert den Arbeitsbereich), sondern als
      Popup / Benachrichtigung rechts; kleine Hinweise bei falscher Eingabe direkt am Feld bzw. an der Schaltfläche, wo es Sinn ergibt.
- [ ] Projektbaum links (in den Planungsmodulen) als aufklappbare Liste: Gebäude → Geschoss → Raum → Reiter je Gewerk → Geräte/Objekte,
      sortiert und klassifiziert; Klick wählt das Objekt im Plan an.

### Große Testrückmeldung vom 08.11. nachmittags

Darstellung und Bedienung
- [ ] Gerätesymbole im Grundriss in den Einstellungen anpassbar: Darstellung, Text, Transparenz, was überhaupt angezeigt wird (mehrere Varianten).
- [ ] Werkzeugleiste: nur die Einstellungen zeigen, die für das gewählte Werkzeug gelten.
- [ ] Eigene Maße: wählbar, ob an der Wand ausgerichtet oder frei zwischen Punkten; Punkte direkt wählbar.
- [ ] Werkzeugerklärung rechts ausblendbar.
- [ ] Wandansicht: zoomen und verschieben.
- [ ] Setzen mit Umschalter: Gerät an der Stelle setzen und direkt dort ein Auswahlmenü öffnen, was gesetzt werden soll.
- [ ] Bauteile: Symbole fehlen.
- [ ] Eingabefelder bei Heizlast und im Schrankeditor verzerrt; Schrank: Auswahl zum Setzen zu weit am Rand.
- [ ] T-förmige Wandanschlüsse werden falsch verbunden dargestellt.
- [ ] Sprünge in zugehörige Editoren: direkt an passender Stelle und zentral im Menüband nach Kategorien.

Material und Einkauf
- [ ] Globale Materialbibliothek (an allen passenden Stellen nutzbar), z. B. Styrodur 20 mm mit Dämmwert; Werte aus Vorlagen oder von Hand.
- [ ] Erfassung von Einkäufen, später auch aus der App; Kassenzettel per KI scannen, erkannte Artikel zur Bestätigung/Korrektur anzeigen.
- [ ] Kategorie Werkzeug.
- [ ] Materialliste: was verbaut wird (Dosen, Leerrohr, Leitung …) aus dem Bestand übernehmen oder auf die Besorgungsliste setzen.

Fenster, Laibung, Wärmebrücke
- [ ] Dämmwert der Laibungsdämmung frei eingeben oder aus der Materialbibliothek wählen.
- [ ] Anschlussfuge: Schaum und Kompriband unterscheiden (unterschiedliche λ).
- [ ] Erklärtexte unter der Berechnung werden teilweise abgeschnitten.
- [ ] Rollladenschienen nach erfassten Maßen im Laibungsdetail zeichnen.
- [ ] Fliegengitter an verschiedenen Stellen zeichnen; Fliegengittertüren in verbreiterten Rollladenschienen (hinter dem geschlossenen Rollladen).

Wände und Bauteile
- [ ] Wandaufbau-Editor für Wandtypen, direkt aus dem Grundriss und zentral erreichbar.

Leitungen und Installation
- [ ] Leitungseditor: einblendbares Raster mit wählbarer Größe, wahlweise mit Fang.
- [ ] Klick auf den Schnittpunkt einer Leitung mit z. B. RFB = Übergabepunkt; Popup am Cursor fragt, wohin es weitergeht.
- [ ] Verlegeebenen anlegen (z. B. für Kabel und Leitungen).
- [ ] Voreinstellungen für Leitungen (Leerrohr M20 usw.) mit Maßen/Abmaßen; reale Abmaße auch bei Steckdosen und allen eingebauten Geräten, alle Gewerke.
- [ ] Schalter und Steckdosen mit gemeinsamer Abdeckung (Mehrfachrahmen) einstellen und darstellen.
- [ ] Beim Setzen einer Steckdose: Unterputzdose wählen und womit sie angefahren wird (z. B. Leerrohr M20 mit NYM 5×2,5 mm²) → Materialliste.

Schaltschrank
- [ ] Wichtige Eigenschaften am Gerät im Schrank anzeigen.
- [ ] Verdrahtung: ganzer Verteiler mit Anschlussraum, Klemmschienen, Ein- und Ausführungsöffnungen.

Fußbodenheizung
- [ ] Heizkreis setzen geht nicht: beim Schließen der Fläche fehlt der Fang.
- [ ] Heizkreis automatisch nach Raum setzen.
- [ ] Wählbar, wo der Zugang in den Heizbereich liegt.
- [ ] Anbinderohr mit dem Heizkreis verbinden.

Ergänzungen 08.11. 16:21 (Tim: „Fang an!“, Reihenfolge der Roadmap passt)
- [ ] Symbole statt Text, wo ein Symbol reicht (mit Tooltip), um alles zu verschlanken.
- [ ] Leitungen auch in der Breite darstellen (Durchmesser/Bündelbreite, nicht nur Tiefe).
- [ ] Später (Roadmap 5): Speicherort für die App wählbar – dieser PC, NAS oder anderer Netzwerk-PC (NAS gibt es noch nicht).

Arbeitsstand (wird beim Bauen fortgeschrieben, damit nach einer Pause nicht neu gesucht werden muss):
- Fertig: T-Stoß aus zwei Wandstücken (wandmasse.dart, Test), Eingabefelder global gefüllt statt Umrandung (theme.dart, behebt „verzerrt“ und abgeschnittene Hilfetexte), Modulleiste kompakter, FBH: Fang an Startpunkt/Raumecken/Wandoberfläche, Fläche durch Klick auf Startpunkt schließen, „Ganzer Raum“, Zugang (Schieberegler + zum Verteiler), Anbindeleitung an HK-Zugang (VL/RL) mit Länge als Zuleitung.
- Sichtprüfung: test/bildschirm_test.dart mit BAUSPUR_BILD=Ordner schreibt PNGs der Module (Roboto + Icons geladen).
- Fertig: Grundriss-Werkzeugleiste je Werkzeug (Wand/Raum/Maß/Auswahl), seltene Optionen im Menü (tune), Symbole statt Text, Wandaufbau-Knopf (layers) öffnet WandtypenAnsicht, Maß-Ausrichtung (direkt/waagerecht/senkrecht/parallel zur Wand), Erklärung rechts ausblendbar (AppSettings.hilfeAnzeigen; Grundriss + Wandansicht), Wandansicht Zoom (Mausrad) und Verschieben (rechte/mittlere Taste), Installation „Auswahl am Ort“ (ads_click) mit Menü an der Klickstelle.
- Fertig: Materialbibliothek = neue Kategorien in der Bauteil-Bibliothek (Dämmstoff, Baustoff, Dichtung, Kabel, Rohr, Dose, Kleinmaterial, Werkzeug; Beispiele bsp-mat-*), Symbole je Kategorie, Bestand (Einstellung bestand), Einkauf erfassen (lib/core/einkauf.dart, lib/ui/bauteile/einkauf_dialog.dart; Kassenzettel als Text/PDF per Regeln oder KI, Bild per Bildmodell ollamaBildFrage; Prüfen/Zuordnen/Neu anlegen), Einkäufe-Liste. Einbaudetail: Laibungsdämmstoff und Fugenmaterial aus der Bibliothek (fuge_lambda), Führungsschiene und Fliegengitter (Spannrahmen, Rollo, Tür in verbreiterter Schiene) gezeichnet. 168 Tests grün.
- Fertig: Wandansicht Raster (einblenden, Größe, Fang), Bezugslinien RFB/FFB/Rohdecke/UK Decke als Übergabepunkt mit Popup am Cursor (uebergang_ende), Leitungen mit Rohr + Kabeln aus der Bibliothek (rohr, kabel_liste, breite_mm → reale Breite in Plan und Wandansicht), Geräte: Dose (dose, dose_d, dose_t), Zuleitung (zuleitung_rohr, zuleitung_kabel), Abdeckrahmen 1–5-fach (rahmen) in der Wandansicht gezeichnet; Verlegeebenen (Objekt.lage) als Ebenen ein-/ausblendbar und für neue Objekte wählbar. 168 Tests grün.
- Fertig: Besorgungsliste (Plan − Bestand, CSV), Schrank: Gerätepalette links neben dem Schrank (statt Dropdown oben), Daten am Gerät (Phase, RCD-Typ, kA, PA, Kanäle), Verdrahtung mit Anschlussraum (N-/PE-Klemmschiene, Einführungen oben/unten); Einstellungen „Darstellung im Plan“ (Größe, Deckkraft, Flächen, Beschriftung, Form); Editoren-Menü oben rechts (apps). 171 Tests grün.
- BUILD 08.11. abends erstellt (siehe unten). Offen für später: Hinweise als Popup statt Seitenleiste, Wärmebrücken-Erklärungen/Beratung, Projektbaum mit Gewerken/Geräten (Notizen oben).

Entscheidung 08.11. 17:23 (Tim): echte iOS-App, ohne Apple-Entwicklerzugang – Neuanmeldung alle 7 Tage ist ok.
Weg (Roadmap 6): App in Flutter (gemeinsamer Code), Bau als .ipa über einen Cloud-Mac (z. B. GitHub Actions macOS oder Codemagic),
Installation am Windows-PC mit Sideloadly oder AltStore und kostenloser Apple-ID; AltStore kann im WLAN automatisch neu signieren.
Voraussetzungen: Code in ein privates GitHub-Repo (bisher kein git), Apple-ID, iTunes/iCloud für Windows.

Wünsche 08.11. 17:32 (für den nächsten Build):
- [ ] Schrank: Außenmaße (Breite × Höhe × Tiefe) eingeben; Anzeige und Prüfung, ob er in die Wand/Nische passt.
- [ ] Haustechnik in 3D eingeben (Höhe, Lage im Raum) und Technikraum aus der Zeichnung in 3D darstellen – Leitungen laufen übereinander (Kollisionen sichtbar).
- [ ] Sanitär und Heizung: Verbindungselemente erfassen und sortieren – Verschraubungen, Fittings, Winkel, T-Stücke, Übergänge, Halter/Schellen, Anschlüsse, Ventile; in Plänen setzbar, in Bibliothek/Material- und Besorgungsliste.

Arbeitsstand Build 3 (08.11. abends): erledigt Projektbaum (Gebäude→Geschoss→Raum→Gewerk→Typ→Gerät, Klick wählt in der Installation; AppState.objektAuswahl), Setzen „aus Liste | am Cursor“ als Umschalter, Geräte an der Wand (Fang setzt lage „in Wand“, Symbol sitzt an der Wand), Installationssymbole nach DIN EN 60617 (lib/ui/symbole_plan.dart). Weiter: Hinweise als Popup rechts, Wärmebrücke-Erklärungen, Schrank-Außenmaße, 3D-Haustechnik, Fittings.

### Abgleich aller Wünsche vom 08.11. (Stand 17:30)
Offen bzw. in Arbeit für diesen Build: Hinweise als Popup rechts + kleine Hinweise am Feld; Wärmebrücke Erklärungen/Beratung;
Schrank-Außenmaße; Haustechnik 3D + Technikraum 3D; Verbindungselemente Sanitär/Heizung; Geräte-Eigenschaften mit Reitern
(Allgemein, Produkt, Fotos, Dokumente, Kosten, Verlauf – Lastenheft); reale Abmaße für alle Gewerke (bisher Dosen, Rahmen, Leitungen, Technikgeräte).
Später (Roadmap): hydraulischer Abgleich, Speicherort PC/NAS/Netzwerk-PC, iOS-App (Sideloading), Einkauf aus der App.
Alles andere aus den Listen 12:20, 12:24, 15:17, 16:14, 16:21 und den Nachträgen 17:24/17:25 ist umgesetzt.
- Build 3 weiter: Meldungen als Fenster unten rechts (zeigeHinweis/zeigeFehler/zeigeWarnung, schwebend), Glocke in der Kopfleiste mit offenen Prüfhinweisen als Fenster rechts (lib/ui/hinweise.dart), Feldprüfung direkt am Feld (SpeicherFeld.pruefen), Wärmebrücke: Bewertung mit „Ausprobieren“-Vorschlägen + Erklärungen (waermebrueckeBeratung, wbErklaerungen). Weiter: Schrank-Außenmaße, 3D-Haustechnik, Fittings, Geräte-Reiter.
- Build 3 weiter: Schrank-Außenmaße + Einbauart + Prüfung Restwand (schrank.eigenschaften aussen/einbau), Technikraum 2D/3D (lib/core/drei_d.dart, lib/ui/haustechnik/technik_3d.dart; Kollisionen Leitung/Leitung und Leitung/Gerät), Unterkante über FFB je Gerät, Kategorien Verbindungselement + Armatur, Objekttypen VB/VH/AV (Migration 17), Formteil-Schätzung in der Besorgungsliste. Weiter: Geräte-Reiter, Abmaße alle Gewerke, Tests, Build.
- BUILD 08.11. 18:48 (data/app.so): zusätzlich Geräte-Eigenschaften mit Reitern (Allgemein, Produkt, Fotos, Verlauf; store.verlauf), reale Grundfläche aus dem Produkt im Plan (Breite×Tiefe bzw. Baulänge×Bautiefe, an der Wand ausgerichtet). 174 Tests grün, Schema bis Migration 17.
- Tim 08.11. 18:41: Startfenstergröße bestätigt (passt).

## Gesammelte Wünsche (nach dem Build vom 08.11. 18:48)
- [ ] Installation: Zurück-Knopf fehlt (Rückgängig/zurück sichtbar machen).
- [ ] Wandansicht: Werkzeugleiste verschwindet beim Zoomen (Leiste muss fest stehen bleiben, nur die Zeichnung zoomt).
- [ ] Wandtypen und eigene Sensoren aus den Einstellungen in das Modul „Bauteile“ verschieben; „Bauteile“ besser benennen (z. B. „Bibliothek“).
- [ ] Laibungsdämmstoff innen und außen getrennt aus der Bibliothek wählen.
- [ ] Optional eigener Dämmstoff zwischen Fenster(rahmen) und Laibung (Fuge/Überdämmung) wählbar.
- [ ] Installation: Mehrfachauswahl-Werkzeug (Rahmen aufziehen, Umschalt+Klick, gemeinsam verschieben/ändern/löschen).
- [ ] Schrank: gewähltes Gerät mit Entf löschen.
- [ ] Schrank: Gerätepalette links in der Breite ziehbar (breiter/schmaler).
- [ ] Schrank: Schrankliste links einklappbar, klappt erst beim Darüberfahren auf (verdeckt sonst die Arbeitsfläche).
- [ ] Schrank: in der Schrankansicht zoomen und verschieben wie in den anderen Editoren.
- [ ] Bibliothek „Neu“: Pflichtfelder (Bezeichnung, Hersteller, Artikelnummer) als Textfelder, technische Daten neben einem Schaubild je Art
      (z. B. Fitting mit Maßpfeilen; Elektrogeräte mit elektrischen Daten) statt nüchterner Liste.
- [ ] Bibliothek: Symbole in der Kategorienliste links fehlen (prüfen, ggf. größer/eigene Symbole).
- [ ] Kategorie Balkontür (zwischen Fenster und Tür), auch als Öffnungsart im Grundriss.
- [ ] Dachgeschoss planen (eigener großer Punkt): Dachform/-neigung, Sparren (Position, Abstand, Querschnitt), Zwischen- und
      Untersparrendämmung, Kniestock (Höhe, auch nicht über die ganze Breite gerade), Dachfenster, Decke aus Sparren/Kehlbalken separat einstellbar;
      Schnitt-/Wandansicht mit Dachschrägen, Flächen unter Schrägen (Wohnfläche), Heizlast über Dachflächen.
Tim 08.11. 20:49: Mit dem nächsten Build noch warten.
- [ ] Mehrfachrahmen richtig: mehrere Geräte in einem Rahmen verknüpfen (Rahmen als eigenes Objekt mit Plätzen; zweites Gerät direkt in einen
      freien Platz setzen), Beschriftung ohne Überdeckung (gemeinsames Schild „SD-01/02“ oder Liste neben dem Rahmen).
- [ ] Verdrahtung von Dose zu Dose: Zuleitung kommt entweder vom Verteiler/Stromkreis oder wird von einer anderen Dose weitergeführt
      (z. B. zwei Hohlwanddosen nebeneinander, nur eine angefahren). Vorschlag zum Datenmodell und zu Prüfungen:
      • je Gerät „gespeist von“: Stromkreis (Verteiler) oder anderes Gerät (Kette) – Kettenlänge, Leitung und Aderzahl je Abschnitt;
      • Aderbedarf je Gerät: Steckdose L/N/PE (3); Ausschalter L + geschaltetes L (+ N/PE bei Elektronik); Serienschalter 2 geschaltete L;
        Wechselschalter 2 Korrespondierende + L bzw. geschaltetes L; Taster/KNX nach Typ;
      • Kombination Schalter + Steckdose mit nur NYM-J 3×1,5: geht nur, wenn die Leuchte von dieser Dose aus weiter versorgt wird
        (Abgang mit geschaltetem L, z. B. NYM-J 3×1,5 zur Leuchte) – sonst braucht die Rückführung eine weitere Ader (4×1,5 bzw. 5×1,5);
      • Hinweis DIN 18015-2: Beleuchtung und Steckdosen möglichst auf getrennten Stromkreisen – dann 5×1,5 (L1 Steckdose, L2 Licht) oder zwei Leitungen;
      • Klemmraum: für Durchschleifen/Abzweigen tiefe Geräteverbindungsdosen (≥ 61 mm) bzw. Elektronikdosen; Prüfung „zu wenig Klemmraum“;
      • Belastung: alle Geräte der Kette zählen zum Stromkreis (Last, LS, Querschnitt).
- [ ] Mehr Unterputzdosen: tiefe Gerätedosen, Elektronikdosen, Netzwerk-/Multimediadosen, Dosenerhöhungen/Ausgleichsringe (als Dose bzw. Zubehör wählbar).
- [ ] Grundbibliothek ausbauen (umfangreicher Startbestand), alle Einträge bearbeitbar und löschbar (auch Beispiele).
- [ ] Bauteile kopieren: „Duplizieren“ prominent, Kopie öffnet direkt zum Ändern von Maß und Bezeichnung (z. B. Leitungswinkel 16 → 20 mm).
- [ ] Mehrfachauswahl per Rahmen um Bauteile (Installation, Schrank, Decke, Wandansicht).
Tim 08.11. 21:14: weiter warten, es kommt noch mehr.
- [ ] Eigene Verlegeebenen anlegen, die nicht Ober-/Unterkante eines Belags sind: z. B. „in der Dämmschicht unter dem Estrich“ mit Höhe
      bzw. Bezug auf den Boden-/Deckenaufbau (Schicht X des Aufbaus, Höhe ab RFB), Leerrohre darin verlegen und im Schnitt/3D zeigen;
      Ebenen je Projekt verwalten (Name, Höhe von–bis, Bezug, Farbe), in Installation wählbar und ein-/ausblendbar.
- [ ] Schaltschrank real darstellen (umschaltbar symbolisch/real): Gehäuse mit Außenmaßen, Anschlussraum oben und unten, Platz links/rechts
      neben den Hutschienen, Abdeckungen; Kabeleinführungen wählbar (viele kleine Würgenippel/Membranen oder breite Ausbrüche zum Aufstemmen,
      Anzahl/Lage oben, unten, hinten).
- [ ] Oberflächen beschichten: Wand-, Boden-, Decken- und Balkonflächen mit Beschichtungen belegen (Farbe, Grundierung, Dichtschlämme,
      Flüssigabdichtung, Fliesenkleber, WDVS-Kleber/Armierung …) – als Schichtsystem je Fläche mit Verbrauch je m², ergibt Material- und
      Besorgungsliste; WDVS-Kleber/Armierung optional direkt im Wandaufbau.
- [ ] Rollladen richtig: verbreiterte Führungsschiene mit ZWEI Kammern – vorne der Rollladenpanzer, dahinter in derselben Schiene das
      Fliegengitter (Insektenschutzrollo oder -tür läuft in der zweiten Kammer, bei geschlossenem Rollladen dahinter). Kein Motor-Thema.
      Im Laibungsdetail so zeichnen (Schienenbreite = Panzerkammer + Insektenschutzkammer), Maße der Schiene je Kammer eingebbar.
- [ ] Alle Bauteile (Rollladen, Fensterbank, Leuchte, Technikgerät, Fitting …): Eingabe über eine Skizze, an der die Maßfelder an den
      passenden Stellen stehen (Maßpfeile), statt reiner Liste; eigene zusätzliche Werte/Punkte ergänzbar (frei benannte Felder).

Tim 08.11. 21:19: FREIGABE – alles Gesammelte seit dem Build 18:48 jetzt umsetzen. Arbeitsstand Build 4:
- (begonnen)
- [ ] Heizkreise nach Räumen auswählen (im Heizkreisverteiler-Editor: Räume mit ihren Heizkreisen auflisten und Abgängen zuordnen; in der Installation Heizkreise eines Raums gemeinsam wählen).
- [ ] Heizkreise (Präzisierung 21:23): Vorschlag je Raum (Anzahl Kreise nach Fläche/max. Kreislänge), automatisch zeichnen mit Kollisionsprüfung
      (Wände, andere Kreise, Sperrflächen), Kreise möglichst gleich lang; Schnecke korrigieren (echte bifilare Schnecke mit VL/RL am Zugang),
      weitere Verlegearten (Mäander, Doppelmäander, gemischt: Randzone enger), Zugang VL/RL exakt am gezeichneten Rohranfang;
      Arbeitsweise wählbar: Fläche wählen → Zugang setzen → Muster wird gezeichnet / nach Raum automatisch / frei;
      Vor- und Rückläufe als Anbindeleitungen durch den Flur zum Heizkreisverteiler führen (Vorschlag, gebündelt).
- Arbeitsstand: Zurück-Knopf Installation ✓, ClipRect für alle Zeichenflächen (Leiste verschwindet nicht mehr) ✓, Schrank Zoom (Mausrad) + Verschieben (rechte/mittlere Taste) ✓.
- [ ] Heizkreis: Zugang VL/RL per Klick auf den Rand setzen (statt Schieberegler); statt „Produkt“: Heizrohr (Bibliothek Rohr), Systemplatte/
      Befestigung, Randdämmstreifen; Rohrlänge (m) + Klemmringverschraubungen in die Besorgungsliste.
- Arbeitsstand: Schrank Entf löscht, Palette ziehbar (120–420 px), Schrankliste eingeklappt (Hover öffnet, Pin hält offen) ✓.
- Arbeitsstand: Grundriss rechte Spalte einklappbar (Knopf oben, schmale Leiste zum Öffnen; Hilfe dauerhaft aus via AppSettings.hilfeAnzeigen) ✓. Als Nächstes: FBH-Verlegemuster neu (Bandspirale/Bandmäander, lib/core/fbh.dart).
- Arbeitsstand: FBH-Muster neu in lib/core/fbh.dart (verlegeplan: _schnecke Bandspirale, _maeander einfach/doppelt mit verschachtelten Wenden),
  test/fbh_muster_test.dart grün (kreuzungsfrei, VL/RL nebeneinander, Randzone). Zugang per Klick (_zugangFuer in installation_page, Vorschau am Rand, Esc),
  Musterauswahl alle 3 + Randzone/Abstand Randzone, HK-Material (fbhMaterialFelder/fbhBedarf: heizrohr, systemplatte, befestigung, randstreifen,
  verschraubung) in Allgemein + Reiter „Material“, Besorgungsliste rechnet HK nach fbhBedarf ✓. Als Nächstes: Vorschlag je Raum (gleiche Längen),
  Anbindeleitungen zum HV, HV-Editor „nach Räumen“.
- Arbeitsstand: Heizkreise fertig ✓ – flaecheTeilen/heizkreiseVorschlagen (gleich große Streifen, max. Kreislänge), Dialog
  lib/ui/installation/heizkreise_dialog.dart („Nach Räumen …“ in der Werkzeugleiste bei HK und im HV-Editor: Räume wählen → auf Abgänge legen
  bzw. Kreise vorschlagen), anbindeweg (rechtwinklig durch die Tür) + Knopf „Anbindeleitungen VL/RL zum Verteiler zeichnen“ (HR-Objekte).
  Alle 185 Tests grün. Alte fbh_test-Erwartungen an [vl, rl] angepasst. Als Nächstes: Bibliothek (Umbenennen, Wandtypen/Sensoren, Duplizieren, Balkontür).
- Tim 21:10–21:19 (gesammelt): Zeichenwerkzeug für eigene Bauteile (Rollladenschienen u. a. Profile frei zeichnen, mit Maßen);
  3D-Darstellung wie im Technikraum auch im normalen Grundriss; Änderungen (Bibliothek/Updates) wahlweise auf Gezeichnetes übertragen,
  nie automatisch (→ in Build 4 umgesetzt für Bibliothekselemente: Knopf „Ins Projekt übernehmen“).
- Arbeitsstand: Bibliothek umbenannt, Wandaufbauten/Baustoffe/Sensoren als Bereiche in der Bibliothek (aus Einstellungen raus, Apps-Menü springt hin),
  Duplizieren als Knopf, Grundbestand erweiterbar/löschbar (grundbestand_geloescht.json, „Grundbibliothek wiederherstellen“), mehr UP-Dosen,
  FBH-Material im Grundbestand, Balkontür (OeffnungsArt.balkontuer + Kategorie), Bemaßungsskizze mit Feldern am Maß + eigene Maße
  (lib/ui/bauteile/bauelement_skizze.dart), Rollladenschiene mit Fliegengitter-Kammer (Feld fliegengitter_tiefe) ✓.
- Arbeitsstand: Laibung innen mit λ + Material, Fuge Rahmen–Laibung auch mit Dämmstoffen, Rollladenschiene zweikammerig im Einbaudetail ✓. Als Nächstes: Mehrfachauswahl Installation.
- Arbeitsstand: Mehrfachauswahl Installation (Umschalt/Strg-Klick, Rahmen ziehen, gemeinsam verschieben/löschen, ein Rückgängig) ✓. Als Nächstes: Mehrfachrahmen.
- Arbeitsstand: Mehrfachrahmen als Gruppe (rahmen_gruppe/rahmen_pos; Gerät auf Gerät an der Wand → nächster 71-mm-Platz, gemeinsame Beschriftung, Symbole nebeneinander, „Zu Mehrfachrahmen verbinden“ bei Mehrfachauswahl, „Auflösen“) ✓. Als Nächstes: Verdrahtungskette.
- Arbeitsstand: Verdrahtungskette (lib/core/verdrahtungskette.dart; Gespeist von, Schaltung, Leuchte ab hier, Hinweise; Linie im Plan) ✓. Als Nächstes: eigene Verlegeebenen.
- Arbeitsstand: eigene Verlegeebenen (Projekteinstellung 'verlegeebenen': name, von/bis mm, Bezug, Schicht, Farbe; Ebenen-Liste + alle Lage-Auswahlen) ✓. Als Nächstes: Schrank echte Darstellung.
- Arbeitsstand: Schrank echte Darstellung (Chip „Echte Darstellung“, SchrankAufbau in eigenschaften.aufbau: Anschlussräume, Seitenraum, Einführungen) ✓. Als Nächstes: Oberflächen beschichten.
- Arbeitsstand: Oberflächen beschichten (lib/core/oberflaechen.dart, Bauphysik-Reiter „Oberflächen“, Vorlagen Anstrich/Dichtschlämme/Fliesen/WDVS/Putz, Grundbestand-Materialien mit verbrauch_m2, Besorgungsliste) ✓. Als Nächstes: Dachgeschoss.
- Arbeitsstand: Dachgeschoss (lib/core/dach.dart, lib/ui/floorplan/dach_dialog.dart; Grundriss → Optionen → „Dachgeschoss …“; Einstellung 'dach_<geschossId>':
  Sattel/Pult, Neigung, First-Richtung, Kniestock, Kehlbalken, Sparren, Zwischen-/Untersparrendämmung, Dachfenster; Schnitt-Vorschau, U-Wert,
  Wohnfläche WoFlV je Raum + im Raumfenster; Überlagerung im Grundriss: Sparren, First, 1-m-/2-m-Linien, Dachfenster; Heizlast nimmt das Dach als Decke) ✓.
  OFFEN für Build 5: Kniestock abschnittsweise (nicht gerade durch), Schrägen in der Wandansicht, Walmdach/Gauben, Dachfenster per Klick setzen,
  Zeichenwerkzeug für eigene Profile, 3D im normalen Grundriss.
- BUILD 4 ERSTELLT 08.11. 23:07 (data/app.so), 191 Tests grün, analyze sauber. Offene Punkte oben unter „OFFEN für Build 5“.
- Build 5 Arbeitsstand: Build-Nummer im Fenstertitel (lib/app/version.dart), Kniestock-Abschnitte (KniestockAbschnitt, kniestockBei, hoehenLinienAbschnitte), Dachschräge in der Wandansicht (schraffiert), Profil-Editor lib/ui/bauteile/profil_editor.dart (daten['profil'], im Einbaudetail als Schiene) ✓. Als Nächstes: 3D im Grundriss.

## Build 5 (Tim 09.11. 00:16–00:25: „alles machen, was ich wollte“)
URSACHE „nichts sichtbar“: build/flutter_assets (MaterialIcons-Subset) seit 07.11. 16:21 nicht erneuert → neue Symbole/Icon-Knöpfe unsichtbar.
Vor jedem Release: build/flutter_assets, build/windows/x64/runner/Release/data/flutter_assets und .dart_tool/flutter_build löschen; danach Datum der Schriftdatei prüfen, exe per touch aktualisieren.
Offen aus dem Abgleich: Rahmen-Mehrfachauswahl Schrank/Decke/Wandansicht, Skizze Fitting/Elektro, Einführungsart Schrank, WDVS im Wandaufbau,
Verlegeebenen in Schnitt/3D, HK-Sperrflächen + gebündelte Anbindung, 3D im Grundriss, Mehrfachrahmen mit freien Plätzen.
Erledigt Build 5 bisher: version.dart, Kniestock-Abschnitte, Schrägen Wandansicht, Profil-Editor, Bibliothek Entf/Strg+C/V/D, Installation Strg+C/V/D.
- Build 5 weiter: Rahmen-Mehrfachauswahl Schrank/Decke/Wandansicht, Skizzen für alle Kategorien (skizze_test), Schrank echt als Vorgabe + Einführungsart, Wände automatisch ausrichten (_waendeAusrichten, Einstellung wand_manuell, Öffnungen gespiegelt) ✓.
- BUILD 5 ERSTELLT 09.11. 01:53 (sauber neu, Symbolschrift 22 KB neu, exe getoucht), 195 Tests grün. Im Programm geprüft: Fenstertitel „Build 5“,
  Symbole in Leiste/Bibliothek/Grundriss, Einklapp-Knopf Hilfe, Maßskizze Fenster, Schrank echte Darstellung mit Würgenippeln.
  Zusätzlich: Mehrfachrahmen mit freien Plätzen (Rahmengröße, Fang auf freie Plätze), 3D-Geschoss (lib/ui/floorplan/geschoss_3d.dart, Knopf view_in_ar in
  Grundriss und Installation, Verlegeebenen als Flächen), WDVS-Klebemörtel im Wandaufbau, Sperrflächen-Hinweis im HK-Vorschlag, Wände beim Öffnen ausrichten.
  OFFEN Build 6: HK-Kreise wirklich um Sperrflächen herum verlegen, Anbindeleitungen aller Kreise gebündelt in einem Schritt, Skizzen-Feinschliff (Felder nicht über Linien).

## Build 6 (Tim 09.11. 01:57: „mit Build 6 anfangen und auch die App bauen“)
- iOS: main.dart ohne window_manager auf Mobil, start_page: Projekte im App-Dokumente-Ordner, ios/ per flutter create (Org de.bauspur, Dateifreigabe),
  .github/workflows/ios.yml (macos-15, Flutter 3.47.9, build ios --no-codesign → BauSpur.ipa als Artifact). Git-Repo lokal (main, 2 Commits).
  WARTET auf Tim: privates GitHub-Repo „bauspur“ anlegen + Link; dann git remote add origin … && git push -u origin main (Anmeldefenster bei Tim).
  Danach Tim: Sideloadly + iTunes (Win32), IPA aufspielen mit Apple-ID, alle 7 Tage neu.
- Offen Build 6: HK um Sperrflächen, Anbindeleitungen gebündelt, Skizzen-Feinschliff.
- BUILD 6 ERSTELLT 09.11. 02:17 (sauber neu), 200 Tests grün, Commit a6190a4: Sperrflächen (FbhEinstellung.sperren, flaecheOhneSperren mit Insel-Aussparung
  zur nächsten Seite, Schnecke um Sperren; Zeichnen per zwei Klicks / aus Geräten; Kreuzungs-Hinweis verlegeplanKreuzungen), gebündelte Anbindeleitungen
  (anbindeleitungenBuendeln in heizkreise_dialog.dart, Knopf im HV-Editor), Skizzenfelder weiß hinterlegt. iOS wartet auf GitHub-Repo von Tim.
