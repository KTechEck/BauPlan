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

## Build 7 (09.11. 22:47) – iPhone-App nach Lastenheft
Tim 09.11.: Er wollte NICHT das ganze Programm aufs iPhone. Umgesetzt laut Lastenheft Abschnitt 14 (Austausch bis zum NAS über den OneDrive-Projektordner, Tim: „Ja bitte“):
- PC: lib/data/austausch.dart – planstand/planstand.json (Lesekopie: Geschosse, Wände, Öffnungen, Räume, Objekte, Gewerke, Status, Einkaufsliste),
  geschrieben 3 s nach jeder Änderung und beim Schließen; eingang/*.json (+ .jpg) alle 30 s übernommen (Foto→Medium+Marker+Objekt, Status, Messwert/Material/Notiz
  → Tagebuch + objekt.eigenschaften.erfassungen, Einkauf → Kostenposition geliefert/geplant), danach nach eingang/_archiv. In Tests keine Timer (FLUTTER_TEST).
- iPhone: lib/mobil/ (ordner.dart: KanalOrdner über nativen Kanal „bauspur/ordner“ in ios/Runner/AppDelegate.swift mit Security-Scoped-Bookmark + NSFileCoordinator,
  Puffer offline, MobilEinstellungen; planstand.dart; mobil_app.dart: Erfassen/Grundriss+Bohr-Check/Einkauf/Mehr). main.dart startet auf iOS nur MobilApp.
- Swift-Teil ist hier nicht kompilierbar → erster Cloud-Build zeigt, ob er durchläuft. Commit 11ab16f, Push macht Tim (Push von hier wird blockiert).

## Build 9 (12.11. 14:53) – Speicherwege statt iCloud, Logo-Entwürfe
Tim 12.11.: iCloud-Abgleich hat nie funktioniert → ersetzt durch drei Speicherarten, Automatik, Android-tauglich (kein Apple-Sonderweg).
- lib/core/speicher.dart: Speicher (OrdnerSpeicher, WebDavSpeicher, UnterSpeicher, PcSpeicher), PcDienst (HTTP-Dienst in BauSpur, Port 47824,
  Kopplungscode im Kopf x-bauspur-code; /bauspur ohne Code, /pruefen, /datei/…, /liste/…; nur planstand/ lesbar, nur eingang/ beschreibbar),
  pcSuchen (fragt x.y.z.1–254 per TCP an – ohne Rundruf, daher auf iOS ohne Multicast-Freigabe), fernAbgleich (Cloud), SpeicherEinstellung.
- PC: AppSettings.speicher (art pc/netz/cloud, code, netz_pfad, url/benutzer/passwort, dienst, port); AppState.speicherAnwenden/abgleichen/dienst;
  austausch.dart: netzAustauschBasis (Netzwerkordner/<Projekt>), iCloud-Teil entfernt; Einstellungen › Speicher und Abgleich (lib/ui/speicher_einstellungen.dart).
- App: lib/mobil/ordner.dart FernOrdner (PC oder WebDAV, findet den PC bei neuer Adresse selbst wieder, Kopie des Planstands auf dem Gerät),
  lib/mobil/verbindung.dart (Suche, Code, Erweitert). main.dart nutzt FernOrdner auf iOS und Android; KanalOrdner/Swift-Kanal bleiben ungenutzt liegen.
  Info.plist: NSLocalNetworkUsageDescription, NSAllowsLocalNetworking.
- 207 Tests grün (test/speicher_test.dart mit Test-WebDAV-Server), Bilder: test/speicher_bild_test.dart (BAUSPUR_BILD).
- Im echten Build geprüft: Dienst antwortet auf allen Adressen des PCs, ohne Code 401, mit Code 200. Windows-Firewall-Regel für bauspur.exe fehlt noch (Tim muss zulassen).
- OFFEN: Logo – Tim wählt aus Entwürfen A–D (Thread), dann Symbole für Windows (.ico) und iOS (AppIcon) erzeugen. Android-Ordner (flutter create --platforms=android) noch nicht angelegt.
  OneDrive/iCloud als Cloud gehen nicht (kein WebDAV); bei Bedarf eigener Weg über Microsoft Graph. NAS-Weg ungetestet (kein NAS vorhanden).

## Build 10 (12.11. 15:05) – Logo
Tim wählte Entwurf H „Bauplan-Linie“ (dunkelblau #0F2A43 mit Planraster, orange Linie zeichnet das Haus). lib/app/logo.dart (logoZeichnen),
BauSpurLogo in widgets.dart nutzt es (Kopfleiste, Startseite). Symbole erzeugen: BAUSPUR_LOGO=<Ordner> flutter test test/logo_test.dart,
dann python tools/logo_einbauen.py <Ordner> (schreibt windows/runner/resources/app_icon.ico, iOS AppIcon, assets/logo/bauspur_logo.png).
209 Tests grün. Im Programm geprüft: Symbol der exe, Fenstertitel „Build 10“, Logo in Kopfleiste und Startseite.

## Build 11 (12.11. 21:45) – Baustellen-App, Aufmaß, Brandschutz, Anschlüsse
Tim 12.11. (nach Test Build 10 + iPhone): App zu schwach; QR-Kopplung, Wandansicht/Bohrhilfe, Maße anzeigen und bearbeiten
(PC grob zeichnen → Handy misst → PC übernimmt), Messwert im Foto, Material anders anzeigen, Einkaufsliste nach Lastenheft,
Rauchmelder/Brandschutz, fehlende Bibliothek-Einstellungen, Anschlusspositionen, iPhone ≠ iPad.
- Aufmaß: lib/core/aufmass.dart (wandMasse inkl. Raumstücke je Wandseite, aufmassAblegen/Anwenden/Planwert; Einstellungen `aufmass`, `aufmass_gemessen`;
  Ziele wand/oeffnung/raum/bemassung/raumseite – Teilstück einer langen Wand wirkt wie Bemaßung, Innenwand wandert). PC: lib/ui/floorplan/aufmass_dialog.dart,
  Lineal-Knopf mit Zähler in der Grundriss-Leiste, Wand-Eigenschaften zeigen „gemessen/grob“.
- Planstand Version 2 (austausch.dart): Wandseiten li/re/gr, Räume rl/rr + Stücke sl/sr, Höhen (h, hs über FFB), Öffnungen mit Höhe/Brüstung, Bemaßungen,
  Raumhöhe, offene Aufmaße, Aufgaben, Einkaufsliste nach Lastenheft (Kosten + Besorgungsliste über Hook `zusatzEinkauf`, Geräte über `bauelementLesen`).
  Eingang neu: aufmass, aufgabe, einkauf mit element (Bestand), Foto-Markierungen.
- App neu gegliedert: lib/mobil/kontext.dart (MobilKontext, iPhone/iPad-Weiche mobilGeraet), seiten/erfassen|plan|wandansicht|aufmass|einkauf|mehr.dart,
  foto_markieren.dart, qr_scannen.dart (mobile_scanner). iPhone: Erfassen/Plan/Räume/Einkauf/Mehr; iPad: NavigationRail, Plan + Räume nebeneinander (eigene iPad-Oberfläche folgt).
- QR: lib/app/qr_bild.dart (Paket qr, bauspur://koppeln?a=…&c=…&n=…), am PC in Speicher und Abgleich, App „Mit QR-Code koppeln“.
- Brandschutz: Gewerk BS (Migration 18, `_gewerkErgaenzen`), Typen RW/WR/CM/FL/BA/BK/SI/BW, lib/core/brandschutz.dart (Feuerwiderstand je Wand in
  Einstellung `brandschutz_waende`, Prüfregeln Rauchwarnmelder/Abstand/60 m²/Durchbruch ohne Abschottung), Bibliothek-Kategorie „Rauchmelder / Brandschutz“.
- Bibliothek: Händler + Händler-Link je Element, Maße für Elektro/Sensor, Anschlüsse mit Lage (lib/core/geraeteanschluesse.dart, lib/ui/bauteile/anschluss_editor.dart),
  Wandansicht PC nutzt sie als Andockpunkte. Besorgungsliste nach Händler gruppiert, Link öffnen, abhaken (Bestand).
- Pakete neu: qr, mobile_scanner, url_launcher. 217 Tests grün; Bilder: test/mobil_bild_test.dart, test/pc_bild_test.dart (BAUSPUR_BILD).
- Hinweis Sichtprüfung: Bildschirm war bei Tims Abwesenheit eingefroren (Uhr stand), Fensterfotos blieben weiß; Start über den Dienst geprüft (/bauspur meldet Build 11).

## Build 12 (12.11. 22:14) – Aufmaß erweitert (alle vier Punkte erledigt)
- [x] Aufmaß: Raum diagonal messen, daraus die Winkel bestimmen (Raum ist nicht rechtwinklig).
- [x] Aufmaß in der Höhe / in den Wandansichten: Dachschrägen messen, auch ungleiche Schrägen auf beiden Raumseiten,
      Räume mit Schräge UND waagrechter Decke (Kniestock, Schrägenhöhe, Deckenhöhe).
- [x] Sparrendecke und Dachsparren aufmessen (Lage, Abstand, Querschnitt) – am PC und in der App. Wahlweise je Raum oder fürs ganze Geschoss.
      Sparren können über die Außenwand hinausragen (Dachüberstand, über einen Balkon/Terrasse) – Sparren also nicht auf Raumgrenzen beschränken.
- [x] In der App auch Steckdosen, Türen und andere Objekte aufmessen (Position ab Ecke, Höhe, Maße) → am PC übernehmen.
- Umsetzung: aufmass.dart neue Ziele objekt (h, x ab Ecke über Wand+Seite), diagonale (Ecken i/j, Winkel per Kosinussatz → Winkelmaß
  wird angelegt und gesetzt), schraege (raum.eigenschaften['schraegen'] „wandId|l/r“ → kniestock, tiefe, decke; bezug = Wand-ID),
  sparren (lib/core/sparren.dart: Sparrenfeld mit Bezugslinie, Seite, Länge inkl. Überstand, Achsabstand, erster, Querschnitt, Neigung,
  Einzellagen pos_i; Einstellung sparren_<geschossId>; feld 'neu' legt das Feld aus der App an). „Alle übernehmen“ geht in Messreihenfolge.
- PC: Wand-Eigenschaften › „Sparren …“ (lib/ui/floorplan/sparren_dialog.dart, Vorschau), PC-Wandansicht zeigt aufgemessene Schrägen über den Dach-Hook.
- App: Wandansicht › Gerät antippen › aufmessen; „Dachschräge messen“ mit Profil; Raum-Aufmaß mit Diagonalen (Ecken A, B, C im Plan);
  Plan › „Sparren“ bzw. Wand › „Sparren ganzes Geschoss / nur Raum“ (lib/mobil/seiten/sparren.dart), Sparren im Plan braun.
- Offen/Ideen: Sparren im PC-Grundriss selbst zeichnen (bisher nur Vorschau im Dialog), Dachschrägen in Heizlast/Wohnfläche einrechnen.
- 220 Tests grün.

## Build 13 (Tim 13.11. 21:13: „Du kannst jetzt anfangen“)
Gilt für PC und App.
- [x] Schnittpunkte: Ein angrenzend gezeichneter Raum stößt an die Wandoberfläche, nicht an die Wandmitte. Gemessen/angezeigt wird das lichte Innenmaß
      (bisher wurde bis zur Mitte der gestoßenen Wand gerechnet).
- [x] Durchgehende Wände automatisch an den Anschlusspunkten teilen (bzw. je Raum eigenes Stück), damit jeder Raum seine eigenen Innenmaße hat
      und nicht nur die Gesamtlänge der durchlaufenden Wand messbar ist.
- [x] Wanddicke ändern: Das lichte Innenmaß bleibt fest (z. B. Bad bleibt gleich groß), Außenmaße und Nachbarräume passen sich an.
      Die Winkel bleiben unverändert, es wird nur skaliert bzw. verschoben.
- [x] Rohbaumaß und Fertigmaß unterscheiden: Verkleidung je Wand bzw. Wandseite schnell wählbar (z. B. GK auf Unterkonstruktion mit Dicke),
      beim Aufmaß einfach umschaltbar, ob roh oder fertig gemessen wurde. Nicht beide Maße nebeneinander anzeigen.
- [x] Maße je Zoomstufe ein- und ausblenden, damit alles lesbar bleibt (vor allem in der App). In den Einstellungen individuell einstellbar
      und auf Standard zurücksetzbar.
- [x] Treppe in ein anderes Geschoss einfügen, optional mit Zwischenpodest.
- [x] Kamin / Schornstein als einfügbares Element.
- [x] Rohre (und Leitungen) in der Wand über mehrere Geschosse (Steigleitung, Fallrohr).
- BUILD 13 ERSTELLT 13.11. 21:41 (sauber neu, 223 Tests grün, Migration 19). Umsetzung:
  1/2: store.waendeAnAnschluessenTeilen (beim Öffnen jedes Projekts, nach Wand/Rechteck zeichnen): teilt Wände an T-Stößen, entfernt
  doppelte Wände (ältere bleibt, Öffnungen wandern mit). wandmasse.flankenGrenzen(masse: true) für Maße: Seite mit Abzweig endet an dessen
  Oberfläche; Zeichnung (masse: false) bleibt ohne Kerbe. Test test/wand_teilen_test.dart.
  3: store.wandDickeVersetzen + aufmass.wandDickeMitInnenmass/festeSeite (Einstellung `dicke_fest` auto/links/rechts/mitte, auto = Raumseite
  bzw. kleinerer Raum); Nachbarwände entlang ihrer Richtung bis zur neuen Achse, Rückgängig über waendeKoordinatenSetzen.
  4: Wandverkleidung je Raum (raum.eigenschaften.verkleidung {art, dicke}; PC Raum-Eigenschaften, App Raum-Aufmaß, Aufmaß-Ziel verkleidung),
  Anzeige roh/fertig (PC Einstellung `massart`, App MobilEinstellungen.massart), Eingabe in der App „Rohbau/fertig gemessen“.
  App-Plan: Schrift bleibt beim Zoomen gleich groß, Maße ohne Platz werden ausgeblendet; Mehr › Maße im Plan: Dichte, Schriftgröße, Zurücksetzen.
  OFFEN: dasselbe Ein-/Ausblenden im PC-Grundriss (dort bisher feste Maße).
  5/6/7: Typen TR Treppe (Lauflinie), TP Podest, KM Kamin (Allgemein), SR Steigleitung in SA/HZ/EL; eigenschaften.bis_geschoss → Objekt
  erscheint in allen Geschossen dazwischen (lib/core/geschossuebergreifend.dart, Installation + Planstand); Treppenwerte (Höhe, Steigungen,
  Podest) im Installations-Panel mit Schrittmaßprüfung.

## Build 14 ERSTELLT 13.11. 22:50 (224 Tests) – Aufmaß-Korrektur
Umgesetzt: waendeAnAnschluessenTeilen entfernt; waendeZusammenfuehren (einmalig beim Öffnen, Flag `waende_zusammengefuehrt`),
doppelteWaendeEntfernen (auch enthaltene/teilweise überlappende Wand), raumStuecke aus Umrisskanten (eine Strecke je Raumseite),
PC-Painter _raumMasse (Messlinie je Raum auf seiner Seite, „Länge Raumname“), App: Wand-Blatt „Lichte Länge im Raum …“,
Raum-Aufmaß markiert nur die gewählte Strecke (GrundrissAnsicht.strecke), Plan beschriftet je Raumstück.
Offen: Tims echtes Projekt nach dem Öffnen prüfen (Raumzuordnung), Wandverkleidungen (Build 15), PC-Zoom-Ausblenden.

### (ursprüngliche Liste)
- [ ] Wände NICHT mehr teilen. Das automatische Teilen (store.waendeAnAnschluessenTeilen, läuft in Build 13 bei JEDEM Öffnen und nach dem
      Zeichnen) entfernen. Stattdessen eine Funktion, die geteilte Stücke wieder zusammenführt (kollinear, Ende an Ende, gleiche Dicke, gleicher
      Wandtyp und Zustand; Öffnungen umrechnen) und einmal auf Tims Projekt anwenden. Das Entfernen doppelter Wände darf bleiben.
      Eine Wand bleibt ein Bauteil. Geteilt wird nur die MESSSTRECKE in dem Raum, in den die Querwand stößt (Raumstücke sl/sr gibt es schon).
      Im Raum, in dem die Wand durchläuft, gilt die ganze Länge.
- [ ] Zuordnung der Räume falsch: prüfen, ob es an Build 13 liegt (Teilen beim Öffnen, neue Wand-IDs, _raeumeAbgleichen) oder daran, dass alte
      Projekte nicht neu gezeichnet wurden. Mit Tims echtem Projekt testen (vorher Kopie machen), rl/rr und Raumstücke prüfen.
- [ ] Optik beim Messen: Hervorgehoben wird nur die gemessene lichte Strecke, von Oberfläche zu Oberfläche, nicht die ganze Wand bis zur Mitte.
      Gilt für App (Plan, Wand-Blatt, Raum-Aufmaß: Messlinie mit Endstrichen, Raumseite) und PC (Grundriss-Markierung, Aufmaß-Dialog).
      Klar beschriften: „lichte Länge im Raum X“.
- [ ] Tims PC-Screenshot (13.11. 22:02): Wohnzimmer oben, Balkon unten (9260 innen), Querwand rechts zum Nachbarraum. Die Wand zwischen
      Wohnzimmer und Balkon ist an der Querwand geteilt; das linke Stück ist orange markiert, über die ganze Dicke bis zur Mitte der Querwand,
      Beschriftung „4860 innen“. Auf der Balkonseite läuft die Wand durch. Soll: ein Bauteil, nur die Messlinie auf der Wohnzimmerseite endet
      an der Oberfläche der Querwand. Die Auswahl-Markierung soll die gemessene Seite zeigen, nicht den ganzen Wandkörper. Oben stand „Längen als Achsmaß“:
      Bei gewählter Wand das gemeinte Maß (innen im Raum X) eindeutig zeigen.
- [ ] Tims App-Screenshot (Aufmaß Wohnzimmer): obere Wand in 239 + 247 cm geteilt (Querwand kommt nur von oben aus dem Nachbarraum),
      rechtes Stück über die ganze Dicke orange. Liste „0 von 10 Wänden“ für ein Rechteck; Wand 1/4/5 „(Teilstück)“ mehrfach mit 486 cm,
      Wand 2 und 3 je 386 cm. Ursachen prüfen: raumStuecke() nimmt Umriss-Ecken innerhalb 6 mm der Flankenlinie – bei geteilten Stücken trifft
      jedes Stück den ganzen Raumumriss → Doppelungen. Soll: je Raum genau eine Messstrecke pro Raumseite (Rechteck = 4), zusammenhängende
      kollineare Stücke zusammenfassen, Stück nur dort, wo es wirklich an den Raum grenzt (Überlappung von Flanke und Umrisskante, nicht nur Ecken).
- [ ] Die App selbst Schritt für Schritt durchspielen (Bildtests mit zwei Räumen und durchlaufender Wand) und mit Tims Screenshots abgleichen.
- [ ] Danach erst die Wandverkleidungen (unten).

## Gesammelt für Build 14 (Tim 13.11. 21:58 – erst umsetzen, wenn Tim es sagt)
- [ ] Wandverkleidungen frei anlegen und zentral in der Bibliothek verwalten (Name, Schichten/Dicke), statt fester Auswahl.
- [ ] Im Auswahlmenü ein Eintrag wie „Eigener Aufbau …“: Verkleidung je Raum UND je Wand(-seite) einzeln festlegbar
      (nicht jede Wand im Raum hat den gleichen Aufbau). Gilt für PC und App; Fertigmaße rechnen dann je Wandseite.
- [ ] Offen aus Build 13: Maße im PC-Grundriss je Zoomstufe ein-/ausblenden (wie in der App), Einstellung mit Zurücksetzen.
- Plan für Build 14 (Tim: morgen früh nach Limit-Reset starten): neue Bauelement-Kategorie „Wandverkleidung / Vorsatzschale“ (Gruppe Material,
  Felder Dicke, Unterkonstruktion, Beplankung, Lagen, Dämmung) → Anlegen/Bearbeiten über den vorhandenen Bibliothek-Editor. Zuordnung: Raum-Vorgabe in
  raum.eigenschaften.verkleidung {element, dicke, art}; je Wandseite Projekteinstellung `verkleidung_seiten` {"wandId|l": {...}} (überschreibt Raum).
  Auswahl PC (Raum-Panel + Wand-Panel je Seite) und App (Raum-Aufmaß + Wand-Blatt): Bibliothekselemente, Schnellwahl, „Eigener Aufbau …“.
  Fertigmaß genau: je Wandseite die Verkleidung der beiden anstoßenden Wände abziehen; PC rechnet es und gibt es im Planstand mit (w.fl / w.fr).
  PC-Grundriss: Maßtexte (floorplan_painter.dart, Wandmaße ab Zeile ~700) je Zoom ausblenden, Einstellung Dichte/Schrift + Zurücksetzen.

## Build 15 (13.11. 23:20, 225 Tests)
Gerade aneinanderstoßende Wandstücke beim Aufmaß wie eine Wand: raumStuecke kürzt Raumkanten nicht mehr auf die Wand (nur Überlappung nötig),
wandMasse beschriftet dieselbe Raumkante nur beim ersten Stück; PC/App lassen die übrigen Stücke innen unbeschriftet. Unterschiedliche Dicken
(Oberfläche springt) ergeben weiterhin zwei Maße. Offen: Tims Projekt prüfen, warum Stücke nicht zusammengeführt wurden (vermutlich Dicke/Wandtyp/Zustand
verschieden); Wandverkleidungen; PC-Zoom-Ausblenden.

## Build 16 (14.11. 07:58, 226 Tests) – Wandverkleidungen
Bauelement-Kategorie `verkleidung` („Wandverkleidung / Vorsatzschale“: dicke, unterkonstruktion, uk_dicke, beplankung, lagen, daemmung, oberflaeche).
Zuordnung: Raum-Vorgabe raum.eigenschaften.verkleidung {element?, art, dicke}; je Wandseite Einstellung `verkleidung_seiten` („wandId|l/r“, überschreibt).
PC: _verkleidungWahl (Raum-Panel, Wand-Panel je Seite; Einträge Bibliothek, Schnellwahl, „Eigener Aufbau …“ springt in die Bibliothek).
Fertigmaß: endAbzuege() zieht je Messstrecke die Verkleidung der anstoßenden Wände ab (PC-Grundriss, Planstand slf/srf/fl/fr).
App: Raum-Aufmaß + Wand-Blatt je Seite (Aufmaß-Ziele verkleidung, verkleidung_seite), Liste „Eigene Aufbauten“ aus dem Planstand (verkleidungen).
Offen: PC-Grundriss Maße je Zoom ein-/ausblenden; Tims Projekt nach Build 14/15 prüfen.

## Build 17 (in Arbeit, noch NICHT gebaut – Tim 14.11.: keine Builds zwischendrin, erst am Ende)
- [x] Belege/Kassenzettel: lib/core/texterkennung.dart (offline über Windows.Media.Ocr per PowerShell, Wörter nach Zeilen gruppiert,
      texterkennungBereinigen). Einkauf erfassen: Bilder werden automatisch erkannt, Knopf „Text erkennen (offline)“, Abschnitt „Belege vom Handy“
      (Einstellung `belege_offen`, Fotos unter belege/; beim Speichern erledigt). App: Kachel „Kassenbon“ (Eingang art beleg). Tests test/belege_test.dart.
- [x] Leitungen in der Wand (lib/core/leitung_wand.dart): eigenschaften verlegung (unterputz/schlitz/aufputz/vorwand/hohlwand/kanal), breite_mm
      (+ breite_hand), tiefe_mm = Überdeckung bis Vorderkante, schlitz_b/schlitz_t; Schlitzprüfung nach DIN EN 1996-1-1/NA (Richtwerte); Felder
      lib/ui/installation/leitung_lage_felder.dart (Installation + Wandansicht). Bohr-Check (core bohrCheck/bohrUrteil: Abstand bis Leitungskante,
      max. Bohrtiefe) am PC in der Wandansicht (Werkzeug B) und in der App (Bohrhilfe, Plan-Bohr-Check). Über Geschosse: geschossStapel/geschossSockel,
      Einstellung deckendicke {geschossId: mm}, leitungenAusAnderenGeschossen (z_abs über die Rohdecke) + Steigleitungen mit bis_geschoss gestrichelt in
      der Wandansicht (PC) bzw. als durchgehend im Planstand (App). Planstand: Objekte b/t/verlegung.
- [x] Heizung: verlegeplanUmSperren (Zellraster 2·VA + Spannbaum-Umrundung, rechtwinklig, lückenlos, kreuzungsfrei; Schnecke = Ringbänder, Mäander = Kamm);
      anbindungenBuendeln (Bündel je Tür parallel versetzt, Querlagen an der Türwand, Auffächern vor dem Verteiler, Ziele = verteilerAnschlussPunkte je Abgang).
      Hydraulischer Abgleich: lib/core/hydraulik.dart + abgleich_projekt.dart (Einstellung abgleich: Spreizung, W/m², Rohr innen, Zuschlag, kv-Stufen;
      Heizlast je Raum aus Einstellung heizlast_raeume, von der Bauphysik zwischengespeichert, oder raum.eigenschaften.heizlast_w; HK eigenschaften
      leistung_w, ist_l_min, ist_stufe). PC: Verteiler-Editor › „Hydraulischer Abgleich …“ (lib/ui/verteiler/abgleich_page.dart). App: Mehr › Hydraulischer
      Abgleich (Eingang art abgleich setzt ist_l_min/ist_stufe). Planstand: HV-Objekte mit abgleich-Liste.
- [x] Home Assistant live im Installationsplan (Knopf „Live“, lib/ui/installation/ha_live_ebene.dart, alle 10 s, nur lesend).
- [x] Revisionsöffnungen: Typ RO (Allgemein, Fläche; Migration 20), lib/core/revision.dart (mussZugaenglich: eigenschaften.zugaenglich, BK, AV, DO in Decke,
      netzteil verdeckt; Reichweite Einstellung revision_reichweite, Vorgabe 400 mm), Projektprüfung + Installations-Panel.
- [x] Rollen: lib/core/rollen.dart, Einstellung benutzer [{id,name,rolle,code,raeume,pruefpflicht}], eigener Kopplungscode je Benutzer; PcDienst erkennt
      den Benutzer am Code (Gast: kein Schreiben, Mitarbeit: autor/rolle/pruefen vom PC gesetzt, Planstand nur freigegebene Räume). Eingang: pruefen=true →
      eingang/_pruefen, Prüfliste in Einstellungen › Speicher und Abgleich (lib/ui/benutzer_rollen.dart). App: Rolle aus planstand.rolle, Gast ohne Erfassen.
- [x] PC-Grundriss: Maße je Zoom ausblenden (passt der Text nicht auf die Strecke, entfällt er), Optionsmenü: dichter/lockerer, Schrift, zurücksetzen
      (AppSettings.darstellung mass_dichte/mass_schrift).
- Tests: test/heizung_leitung_test.dart, test/rollen_revision_test.dart; 239 Tests grün, Analyze sauber.
- [x] (erledigt) Nächste große Schritte laut Tim/Koordinator (PC und App, am Stück, Lastenheft maßgeblich):
      1. Leitungen: Tiefe und Breite in der Wand (Schlitz/Unterputz), in Wandansicht und Bohrhilfe berücksichtigen.
      2. Heizung + hydraulischer Abgleich (Heizkreise, Durchfluss, Ventilvoreinstellung), Heizkreise um Sperrflächen, Anbindeleitungen gebündelt.
      3. Home Assistant live, Revisionsöffnungen, Rollen (Eigentümer / Mitarbeit / Gast).
      Danach EIN Build (flutter clean), alles prüfen.

## Build 18 (14.11. nachmittags gebaut)
Fertig: Kabelkanäle Typ KK (EL/NW) + Montageschiene MS (Migration 21), lib/core/kanal_montage.dart (Formteile Innen-/Außenecke, Flachwinkel,
Endkappe, Abzweig, Stoßstellen; Füllgrad; befestigungsabstand/schellenAnzahl/schienenHalter), lib/ui/installation/kanal_felder.dart (Kanal-, Schienen-,
Leitungs-Führungsfelder), Besorgungsliste mit Kanälen/Schienen/Schellen (Einstellung verschnitt_prozent), Wandansicht zeichnet Kanäle als Band.
Bibliothek: Kategorien kabelkanal, montage (+ Grundbestand), Gerätedaten (_gMontageart, einbauhoehe … in Gruppen geraetFeldGruppen), Einbauhöhe wird beim
Zuordnen übernommen. Geräte-Schaubild (anschluss_editor.dart): Ziehen, Bohrlöcher (daten.bohrungen), Freiräume, Maße antippen; Bohrlöcher in der Wandansicht.
Einstellungen (lib/ui/einstellungen_mehr.dart): Zeichnen (wand_dicke, raster_mm, Maße), Projekt und Geschosse (geschossAendern, Deckendicke, Sicherungen),
Planung und Vorgaben (verschnitt, Regeln, revision_reichweite, bohr_radius, Abgleich), Objekttypen (objekttypAnlegen, objekt_vorgaben), Kennungen (Einstellung
kennung), Benutzer und Rollen. Wartungsplan aus Geräten (lib/core/wartung.dart, Knopf in Aufgaben). Tests: kanal_geraete_test, build18_bild_test.
Offen: volle Testsuite + Analyze nach den letzten Änderungen (Wartungsplan), Test für Wartungsplan, dann Inhaltspakete (Bibliothek Export/Import),
Wohnflächen-Aufstellung, iPad-Oberfläche, KI-Assistent Stufe 2; danach EIN Build 18 (version.dart hochzählen, flutter clean).

Nachtrag Build 18: Touch-Gesten (lib/ui/zwei_finger.dart: zwei Finger zoomen/verschieben, erster Finger wird kurz zurückgehalten; Maus/Stift unverändert) in
Grundriss, Installation, Wandansicht. PC-Seite für iPad mit voller BauSpur: PcDienst projekt/zip (GET) und projekt/datenbank (PUT, nur Eigentümer-Code),
lib/core/ipad_austausch.dart, AppState._projektZip/ipadStandUebernehmen, Karte in Speicher und Abgleich. Tim 14.11.: iPad erst NACH dem Test von PC/iPhone.
Offen iPad: main.dart Tablet → volle BauSpur (BauSpurApp) statt MobilApp, Start-Seite „Projekt vom PC holen“ (PcSpeicher.projektHolen + projektEntpacken),
„Stand an den PC schicken“ (projektZurueck), iPad-Layout (größere Ziele, Seitenleisten einklappen, Stift). Außerdem offen: Inhaltspakete, Wohnflächen-Aufstellung.

## Build 19 (14.11.)
iPad = volle BauSpur (Tim: Umfang wie PC, iPad-optimiert): main.dart Tablet → BauSpurApp(touch: true), Modus-Datei bauspur_modus.txt (lib/ipad/ipad_projekt.dart:
geraeteModus/geraeteModusSetzen, Umschalter auf der Start-Seite bzw. in der Baustellen-App unter Mehr), Start-Seite „Projekt vom PC holen“ (PcSpeicher.projektHolen,
projektEntpacken, alter iPad-Stand wird umbenannt), Kopfleiste „An PC schicken“ (projektZurueck → PC: Speicher und Abgleich „Stand vom iPad übernehmen“).
Touch: bauSpurTheme(touch) größere Ziele, AppState.touch (kein PC-Dienst/Timer), Statusleiste aus, ZweiFinger mit Stiftbetrieb (nach Apple Pencil zeichnet nur der Stift).
Inhaltspakete: lib/core/inhaltspaket.dart (Format bauspur-bibliothek, Datenblätter base64), Bibliothek › Pakete (alle/Kategorie speichern, übernehmen mit Vergleich).
Wohnfläche WoFlV: lib/ui/export/wohnflaeche_page.dart (Ausgabe › Wohnfläche; Dach-Höhenstaffel, Balkon-Anteil Einstellung balkon_anteil, Zubehörräume, raum.eigenschaften.wohnflaeche).
Nicht getestet auf echtem iPad (kein Mac): erster Cloud-Build zeigt, ob alles läuft. Offen: iPad-Layout weiter verfeinern (Seitenleisten einklappen, Stift-Werkzeuge), KI-Assistent Stufe 2.

## Build 20 (14.11.) – iPad und PC ohne Konflikte (Tim: keine gegenseitige Behinderung, Fehlbedienung ausschließen)
Ausleihe (lib/core/ipad_austausch.dart, Datei ipad_ausleihe.json im Projektordner): iPad holt das Projekt (PcDienst GET projekt/zip mit x-bauspur-geraet),
PC vermerkt die Ausleihe und schaltet die Datenbank auf PRAGMA query_only (ProjectStore.nurLesenSetzen) → am PC technisch keine Änderung möglich, gelbe Leiste.
Zweites iPad wird abgewiesen (409). Rückgabe: iPad packt Datenbank + alle seit der Ausleihe geänderten Dateien (lib/core/zip_schreiben.dart, reines Dart), PUT
projekt/rueckgabe; PC prüft Gerät und SQLite, sichert, entpackt (löscht nichts), hebt Ausleihe auf, öffnet neu. iPad-Kopie danach „zurückgegeben“ = nur lesen.
Neu holen bei nicht zurückgegebener iPad-Kopie nur nach Warnung (alter Stand bleibt als _alt-Ordner). Eingang der Baustellen-App wartet während der Ausleihe.
„Ausleihe aufheben …“ am PC nur mit Warnung (iPad-Änderungen verloren). Test test/ausleihe_test.dart (Ende-zu-Ende über den Dienst).

## Build 21 (14.11.) – Roadmap Priorität 1
Gesamt-Roadmap vom 14.11. (Tim freigegeben) steht im Projektgedächtnis; Reihenfolge Prio 1, dann Abschnitte 1–10, „Später/Optional“ nicht.
- Wandzeichnen: gerade Verlängerung (180°) der Wand am Kettenstart hat Vorrang vor allen anderen Fängen (`_verlaengerungsFang`, Fangbreite 14–40 px,
  rastet an Wandenden auf der Flucht und an kreuzenden Wandachsen ein, sonst Raster), Umschalt schaltet ab. Gestrichelte Hilfslinie für Verlängerung,
  „Verlängerung Wand“ und „Flucht zu Wandende“ (FloorplanPainter.fangLinie).
- Kabel- und Rohrauslegung: lib/core/auslegung.dart (Iz nach DIN VDE 0298-4 Cu/PVC je Verlegeart A1–E, Häufung, Temperatur, Spannungsfall, Schleifen-
  impedanz/Abschaltbedingung, Vorschlag Querschnitt+LS; Rohre: Spitzendurchfluss DIN 1988-300, Heizung aus Leistung/Spreizung, v/R-Grenzen, Rohrmaße MV/Cu/Edelstahl),
  lib/core/auslegung_projekt.dart (Einstellungen `auslegung`, `kabel_auslegung` je Stromkreis, Länge gezeichnet/geschätzt/von Hand; Objekt.eigenschaften
  leistung_w, entnahmen, innen_mm, dimension, rohr_system). Seite lib/ui/verteiler/auslegung_page.dart (Verteiler › Stromkreise › „Kabelauslegung …“).
- Kabel-/Rohrliste: alle gezeichneten Kabel/Leerrohre/Rohre/Kanäle/Heizrohr + geschätzte Stromkreise, Zuschlag, Ringgrößen, Abhaken (Einstellung
  `leitung_gekauft`), CSV und HTML-Abhakliste nach exporte/, auch in der Einkaufsliste der iPhone-App (Eingang einkauf mit `leitung`).
  Erreichbar über Verteiler › Stromkreise und Bibliothek (Kabel-Symbol).
- Test test/auslegung_test.dart; 253 Tests grün.

## Build 22 (14.11.) – Roadmap 1 (KI lokal) + 2 (Bad, teilhohe Wände)
- Migration 22: wand.eigenschaften (hoehe, art = WandArt raumtrenner/schamwand/vorwand/bruestung), Badtypen DU/WA (Fläche), WC/WT/UR (Punkt) im Gewerk
  Sanitär (seed.dart badTypen). Teilhohe Wände bilden keine Raumgrenze (flaechenErkennen filtert, waendeZusammenfuehren trennt), werden heller mit
  gestrichelter Achse und „h = …“ gezeichnet, 3D nutzt die Höhe. Grundriss-Wandpanel: „Höhe / Art“ + Höhe. store.wandEigenschaftenSetzen.
- OeffnungsArt.nische (eine Wandseite, Seite über aufgehen_links, eigenschaften.tiefe), nicht in Heizlast.
- Bad: lib/core/bad.dart (istNassraum am Namen, lösbar über raum.eigenschaften.nassraum; abdichtungBerechnen nach DIN 18534: W1-I/W0-I, Zonen an
  Dusche/Wanne +20 cm, 2 m hoch bzw. 0,8 m bei Wanne ohne Brause, Sockelstreifen, Nischenlaibungen, Dichtband, Ecken, Manschetten, kg Flüssigabdichtung;
  badAbstaende DIN 18022). Dialog lib/ui/installation/bad_dialog.dart (Installation › Werkzeug „Bad“, auch „Abdichtung im Raum …“ an Dusche/Wanne).
  Objektfelder bodengleich/brause/abdichtung_hoehe; WC/WT ohne Produkt mit üblichen Maßen gezeichnet.
- KI lokal: Diktat (lib/core/diktat.dart: Windows-Spracherkennung System.Speech per PowerShell, Phrasen live, nur Text; diktatAufbereiten, diktatAuswerten
  → Aufgaben/Mängel/Messwerte, kiDiktatAnfrage), lib/ui/diktat_dialog.dart (DiktatKnopf, Tagebuch › „Diktat“ mit Bestätigung). iPhone: Kachel „Diktat“
  (Tastatur-Diktat) → Eingang notiz+diktat → PC legt Tagebuch + Aufgaben „bitte prüfen“ an.
  Typenschild: lib/core/typenschild.dart (Regeln + KI-JSON), lib/ui/installation/typenschild_dialog.dart (Objektfoto oder Datei, Windows-OCR, „Mit KI lesen“),
  speichert eigenschaften.typenschild (+ leistung_w). Fotos zuordnen: lib/core/foto_zuordnung.dart (Zeitnachbarn ±10 min, KI-Vorschlag),
  lib/ui/fotos/foto_zuordnen_dialog.dart (Fotos › „Zuordnen …“, nur Angehaktes).
- Tests test/build22_test.dart + Widget-Test Bad-Dialog; 259 Tests grün. Tims PC hat die deutsche Spracherkennung (de-DE) installiert.

## Build 23 (14.11.) – Roadmap 3 (Bauphysik/Gebäude) + 4 (Wasser)
- lib/core/gebaeude.dart: GEG Anlage 7 (GegBauteil.uMax, gegZusatzDaemmung), Schall (flaechenMasse, schalldaemmmass Massekurve, schallEmpfehlung 47/40 dB),
  Sonnenschutz (fcSonnenschutz, himmelsrichtung mit Einstellung `norden_grad`, sonneneintrag S), Treppe (treppeAuslegen DIN 18065, gelaenderHinweise LBO),
  Statik (sturzRichtwert), Geschosse (wandVerknuepfungen, gelöst über Einstellung `geschoss_verknuepfung_geloest` „oben|unten“).
- Bauphysik: neue Reiter Dämmung GEG, Schall, Sonnenschutz (lib/ui/bauphysik/gebaeude_ansichten.dart, rhoVon). Heizlast: n50-Infiltration, Lüftungsanlage mit WRG,
  Aufheizzuschlag (HlParameter n50/wrg/aufheiz, lueftungsLeistung; Einstellungen › Standort und Klima).
- Grundriss: Wand „tragend“ (wand.eigenschaften.tragend, Strich-Punkt auf der Achse), Wandpanel zeigt „steht auf Wand im EG“ (lösen/wieder verknüpfen) und Sturz-Richtwerte;
  Optionen: „Geschoss darunter einblenden“ (UnterlagePainter gestrichelt, tragende Wände ohne Wand darunter rot) und „Mappe für den Statiker (PDF)“
  (lib/ui/floorplan/statik.dart → exporte/Mappe Statiker.pdf).
- Treppe (TR): Kopfhöhe, Geländer optional (Höhe, Stababstand) mit Hinweisen. Brandschutz: CO-Melder-Hinweis nur bei Feuerstätte (KM, eigenschaften.feuerstaette, HZ Gas/Öl/Pellet/Ofen).
- Wasser: Migration 23 (Sanitär HA Hausanschluss/Wasserzähler, TV Trinkwasserverteiler, WM Wassermelder), lib/core/wasser.dart (DU-Werte, Qww, Nennweite, Gefälle,
  hausanschluss/Zähler, wassermelderYaml), Dialog lib/ui/installation/wasser_dialog.dart (Installation › „Wasser“: Abwasser je Leitung mit DN/Gefälle/Platz/Grundleitung,
  Trinkwasser-Spitzendurchfluss, Wassermelder je Raum mit „hier nicht nötig“ (raum.eigenschaften.kein_wassermelder), Hauptventil (AV.eigenschaften.hauptventil),
  HA-Automation → exporte/home_assistant/wassermelder.yaml).
- Tests test/build23_test.dart + Widget-Test Wasser/Bauphysik; 265 Tests grün.

## Build 24 (14.11.) – Roadmap 5 (Elektro, Netzwerk, Sicherheit)
- lib/core/elektro.dart: Plankopf (Einstellung `plankopf`: ersteller, firma, revision, adresse; plankopfZeile im Stromlaufplan-Schriftfeld), phasenlast je
  Außenleiter + schieflastHinweis (4,6 kVA), elektroPruefen (Kreis ohne Schutzorgan, ohne RCD, ÜSS fehlt, < 20 % Reserve, Auslegung, Schieflast),
  elektroCheckliste (Einstellung `elektro_pruefung`), verdrahtungsabgleich (Objekte ohne/mit gelöschtem Stromkreis, Kreise ohne Verbraucher),
  DIN 18015-2 ausstattungSoll/ausstattungIst (Einstellung `ausstattungswert` 1–3).
- Verteiler: Ansicht „Prüfung“ (lib/ui/verteiler/pruefung_ansicht.dart), Netzwerkschrank: Ansicht „Rack 19″“ (lib/core/rack.dart, lib/ui/verteiler/rack_ansicht.dart;
  schrank.eigenschaften rack/rack_he, rackPruefen, dosePort) mit Patchfeld daneben.
- LED-Streifen (Decke): Einspeisung einseitig/beidseitig/mittig, Zuleitung Netzteil→Streifen mit Spannungsfall und Querschnittsvorschlag (ledZuleitung),
  Netzteil-Ort mit Hinweis bei „Zwischendecke ohne Öffnung“. _zahlFeld nimmt Kommazahlen, wenn die Vorgabe double ist.
- Installation: Reserve (DO/LR/SD/ND, „verputzt, für später“, im Plan beschriftet, zählt nicht im Abgleich), Leerrohr-Ziel `ziel_schrank`, Netzwerkdose zeigt
  ihren Patchfeld-Port, Kamera/Bewegungsmelder mit Erfassungssektor (winkel, reichweite, drehung), Zutritt (ZU/TS) prüft Türöffner in der Nähe.
- Migration 24: NW KA Kamera, ZU Zutrittsleser, TS Türsprechstelle; EL TO Türöffner/Motorschloss.
- Tests test/build24_test.dart; 269 Tests grün.

## Build 25 (14.11.) – Roadmap 6 (Technikbereiche, Haustechnik)
- Technikbereiche (lib/core/technikbereich.dart): Räume mit Technik/Heiz/HWR im Namen automatisch (lösbar: Einstellung `technikbereich_aus`), eigene Bereiche
  als Raum oder Technikwand mit Schränken (Einstellung `technikbereiche`); Technikplaner wählt Bereiche, zeigt die Schränke; Dialog
  lib/ui/haustechnik/technikbereiche_dialog.dart. Neue Vorlagen „Technikwand Büro“, „Heizraum kompakt“ (+ Geräte Smart-Home-Verteiler, UV 230 V, WP kompakt).
- Hydraulikschema-Editor (lib/core/hydraulik_schema.dart, lib/ui/haustechnik/hydraulik_schema_ansicht.dart): 20 Symbole, Leitungsarten VL/RL/TWW/KW/Zirk/Sole/Signal,
  Ziehen, Drehen, Verknüpfung mit Grundriss-Objekt („Im Grundriss zeigen“), SVG-Ausgabe (Einstellung `hydraulikschema`).
- Regelung Technische Alternative (lib/core/ta_regler.dart, lib/ui/haustechnik/regelung_ansicht.dart): Regler UVR16x2/UVR610/RSM610/UVR1611/CAN-I/O45,
  E/A-Belegung mit Kapazitätswarnung, Fühlerkabel geschätzt (laufen in die Kabel-/Rohrliste), TAPPS2-Vorlage (Text), C.M.I.-Schemaseite (SVG mit Platzhaltern + CSV),
  Live-Werte über C.M.I.-JSON-API (nur Heimnetz, Zugang in AppSettings.cmi). Einstellung `ta_regelung`.
- Lüftung (lib/core/klima_lueftung.dart, lib/ui/haustechnik/lueftung_ansicht.dart): DIN 1946-6 vereinfacht (Nennlüftung, Stufen, Zu/Ab/Überström je Raum, Abluft-
  Mindestwerte, balanciert), Rohr-DN je Raum, Überströmquerschnitt, Hauptleitung, längster Luftkanal, eigene Komponenten im Druckverlust, Gerätegrenzen,
  Dämmhinweise, Kühloption mit Taupunkt (Einstellung `lueftung`).
- Kühlung & Klima: Taupunkt, Kühl-Vorlauf ≥ Taupunkt+2 K, Kühllast-Richtwert je Raum (Fenster nach Richtung/Fc), Gerätegröße, Vergleich mit Klimageräten (Einstellung `klima`).
- Tests test/build25_test.dart; 274 Tests grün.

## Build 26 (14.11.) – Roadmap 7 (Grundriss, Fassade)
- WDVS/Fassade/Balkon (lib/core/fassade.dart, lib/ui/floorplan/fassade_dialog.dart; Grundriss › Optionen „WDVS, Fassade und Balkon …“): Außenwände automatisch
  (aussenSeiten), Dämmfläche, Platten mit Verschnitt, Dübel mit Randzonen, Sockel/Sockelschiene, Laibungen, Kanten-/Anputz-/Tropfkantenprofile, Gewebe, U-Wert
  vorher/nachher mit GEG, Montageblöcke für Anbauteile außen, Durchdringungen (WD und Leitungen durch Außenwände), Balkon-Hinweise. „WDVS im Plan zeigen“
  (WdvsPainter, Darstellung wdvs_zeigen). Einstellung `wdvs`.
- Aufbauten: Vorlagen „Terrasse (Betonplatte)“ und „Bad mit FBH und Abdichtung“ (Schnitt gab es schon). Bodeneinbaustrahler: LE eigenschaften einbau/einbautiefe,
  Prüfung gegen den Bodenaufbau des Raums bis zur Abdichtung/Dämmung (bodenstrahlerPruefen).
- Migration 25: AL AD „Abgehängtes Deckenfeld / Schattenfuge“ (abhaengung_mm, schattenfuge_mm, led_fuge; Material GK/CD/UD/Abhänger/Schattenfugenprofil).
- Oberflächen: Sockelleisten je Raum (Länge ohne Türen, Stäbe, Innen-/Außenecken, Endkappen; raum.eigenschaften.sockelleiste, Bad/WC standardmäßig aus).
- Türen: Türart Drehtür/wandbündig/Schiebetür/Taschentür/Pendeltür (oeffnung.eigenschaften.tuerart) mit eigener Darstellung und Hinweisen (Platz, Tasche ohne
  Leitungen, Wanddicke); Schwelle/Höhensprung zwischen Räumen bzw. Außentür-Hinweis im Öffnungspanel.
- PDF als Planvorlage (lib/core/pdf_bild.dart: Windows.Data.Pdf per PowerShell → PNG, 200 dpi; Maßstab 1:… setzt den Vorlagenmaßstab direkt, sonst kalibrieren).
- Eigene Symbole (lib/ui/symbol_editor.dart: Linie/Kreis/Rechteck/Text auf ±20-Raster; Einstellungen `eigene_symbole`, `symbol_zuordnung`), in Installation und PDF-Plänen;
  „Eigenes Symbol für diesen Typ …“ im Objektpanel.
- Tests test/build26_test.dart (inkl. echter PDF-Umwandlung unter Windows); 277 Tests grün.

## Build 27 (14.11.) – Roadmap 8 (Baustelle/Einkauf) + 9 (Fotos/Hausakte)
- Nächster Einkauf (lib/ui/bauteile/naechster_einkauf.dart, Bibliothek-Symbol Tasche): noch zu beschaffen (Bibliothek + Kabel-/Rohrliste), vormerken (Einstellung
  `einkauf_plan`), „gekauft“ erhöht den Bestand, „noch da – nicht kaufen“ (Bestand > Bedarf), Werkzeug mitnehmen (Einstellungen `werkzeug`, `werkzeug_dabei`,
  Vorschläge je Gewerk, ★ passend zu offenen Aufgaben), Einkaufszettel als HTML.
- Migration 26: aufgabe.art (aufgabe/mangel/restarbeit) + objekt_id; Tagebuch › Aufgaben mit Filter und Knopf „Mangel“; Diktat legt Mängel als Art an.
- Bohrschutz-Karte in der Wandansicht (Werkzeug „Bohrschutz“: rot Leitungen/Dosen mit Sicherheitsabstand, gelb DIN-18015-3-Zonen; bohrSperrzonen,
  dinInstallationszonen in leitung_wand.dart; Einstellung bohr_sicherheit).
- Prüfprotokoll-Vorlagen: Spülen Trinkwasser/Heizung, Einstellwerte Heizkreise, Inbetriebnahme Wärmepumpe/Lüftung.
- Fotos: EXIF-Aufnahmedatum beim Import (lib/core/exif.dart), Pflichtfoto-Hinweis beim Status „verdeckt“ (abschaltbar, Darstellung pflichtfoto_hinweis),
  „Verdeckt ohne Foto“, Zeitleiste je Raum mit Vorher/Nachher-Schieber (lib/ui/fotos/foto_extras.dart).
- Ausgabe (lib/ui/export/akte.dart): Raumbuch (PDF), Fotobericht (PDF), Etiketten (Kabel, Netzwerkdosen mit Port, Sicherungen, Fühler; A4-Bögen,
  Band 12/24 mm, Kabelfahne; CSV für Etiketten-Software), Hausakte als Ordner mit Kategorien + ZIP + index.html (offline) mit Stromlaufplänen,
  Hydraulikschema, TAPPS2, Fotos nach Geschoss/Raum, Protokollen, Kabelliste, Gewährleistung, Belegen, Home-Assistant-YAML.
- Gewährleistung je Produkt (lib/ui/bauteile/gewaehrleistung_dialog.dart, Einstellung `gewaehrleistung`, Vorschläge aus Einkäufen ≥ 50 €).
- Tests test/build27_test.dart; 280 Tests grün.

## Build 28 (14.11.) – Roadmap 10 (Bedienung, Export) + Laufendes – Gesamt-Roadmap damit abgearbeitet
- Globale Suche (lib/ui/suche.dart): Strg+F / Strg+K oder Lupe in der Kopfleiste; Räume, Objekte (auch Typenschild), Aufgaben/Mängel, Tagebuch, Verteiler,
  Stromkreise, Bibliothek, Fotos, Module; Enter öffnet den ersten Treffer.
- Statusleiste vollständig (Shell: Geschoss mit Räumen/Objekten, offene Aufgaben/Mängel, Maßeinheit, Benutzer, nur-lesen, Build, gespeichert).
- Maßeinheit mm/cm/m (MassEinheit in widgets.dart, massText = Zahl + Einheit; Einstellungen › Darstellung; Eingaben bleiben mm).
- Tastenkürzel anpassen (TastenBelegung in tastenkuerzel.dart, darstellung.tasten; F1-Fenster mit Eingabefeldern, „Standard wiederherstellen“).
- Ersteinrichtung beim ersten Start (lib/ui/ersteinrichtung.dart; darstellung.ersteinrichtung) + jederzeit über die Startseite.
- Einstellungen als Vorlage (vorlagenSchluessel, Ordner vorlagen/ im Einstellungsordner; Ausgabe › „Einstellungen als Vorlage“, Startseite „Neues Projekt aus Vorlage“).
- Plankopf (Ausgabe › „Plankopf …“, Bearbeiter/Firma/Änderungsstand/Anschrift) in Plan-PDFs und Stromlaufplänen.
- Datenausgaben (lib/ui/export/daten_export.dart): CSV-Listen (Räume, Objekte, Stromkreise, Öffnungen, Aufgaben), DXF R12 je Geschoss (Ebenen je Zustand),
  SVG je Geschoss, PNG-Pläne, Fotos nach Raum und nach Gewerk, Home-Assistant-Bereiche + customize.yaml.
- Eigener Updater (lib/core/updater.dart: SHA-256 in Dart, Manifest bauspur_update.json, Sicherung des Programmordners, Austausch per PowerShell nach Beenden;
  Einstellungen › Darstellung › Programm-Update: Quelle, „Nach Update suchen“, „Diese Version bereitstellen“).
- Inhaltspakete automatisch (paketeAusOrdner; darstellung.pakete_ordner/pakete_stand) beim Öffnen eines Projekts, Meldung in der Glocke; Gewährleistung-Ablauf
  ebenfalls dezent in der Glocke.
- Vorschaubild-Cache (lib/ui/vorschaubild.dart, Projektordner/.vorschau/*.png) in Galerie und Zeitleiste.
- Laufend: Bauablauf-Hinweise in der Projektprüfung (verdeckt ohne Druckprobe/Dichtheit/Isolationsmessung; Einstellung bauablauf_aus, Schalter in Darstellung),
  Eigenleistung/Lohn in den Kosten ausblendbar (darstellung.eigenleistung_aus).
- Tests test/build28_test.dart; 283 Tests grün.

## Neues Paket (Tim 14.11. abends): Prio 1 Keller/Sockel/Putzprofile/Fensterbänke, dann WLAN + Außenbereich, dann KI-Raumbilder (OpenAI-Schnittstelle, austauschbar). Alarmanlage weiter nicht.
## Build 29 (14.11.) – Keller, Sockel, Putzprofile, Fensterbänke
- lib/core/keller_sockel.dart: Kellertrockenlegung (Lastfall DIN 18533 W1.1/W1.2/W2.1-E, Außenabdichtung PMBC, Hohlkehle, Noppenbahn, Drainage DIN 4095 mit
  Schächten/Vlies/Kies, Horizontalsperre Injektion/Mauersäge/Chromstahl, Innenabdichtung, Sanierputz WTA), Kellerdämmung (Perimeter, innen kapillaraktiv,
  Kellerdecke; uKellerwand), Sockeldämmung als eigener Bereich (unter/über GOK, XPS/EPS-P/PU/Schaumglas, Abdichtung, Sockelputz, Kiesstreifen),
  16 Putzprofile außen/innen mit Mengen aus dem Plan + Stäben, Fensterbänke außen (Alu/Naturstein/Kunststein/Klinker/Titanzink: Tiefe = Laibung + WDVS + Überstand,
  Bordprofile, Gefälle, Hinweise) und innen (Holz/Werzalit/Naturstein/…).
- Dialog lib/ui/floorplan/keller_dialog.dart (Grundriss › Optionen „Keller, Sockel, Putzprofile, Fensterbänke …“): Einstellungen `keller_<geschossId>`, `sockel`,
  `putzprofile` (Zusatzmengen), Öffnung eigenschaften fb_aussen/fb_innen/laibung_aussen/laibung_innen; Bestellliste, CSV.
- Tests test/build29_test.dart; 286 Tests grün.

## Build 30 (14.11.) – WLAN-Abdeckung und Außenbereich
- WLAN (lib/core/wlan.dart, lib/ui/installation/wlan_aussen.dart): Installation › „WLAN“ blendet die Ausleuchtung der Access Points (Typ AP, sendeleistung_dbm)
  als Farbraster ein (2,4/5/6 GHz, Freiraumdämpfung + Wanddämpfung nach Wandtyp, Gebäude + 3 m außen), „Auswertung …“ je Raum (Anteil ≥ −67 dBm, schwächster Punkt).
- Migration 27: Gewerk AU Außenanlagen (lib/core/aussen.dart aussenTypen): Außenleuchte, Poller, Bodeneinbaustrahler außen, Außensteckdose, Erdkabel, Außenkabel
  auf Putz, Regenfallrohr, Regenwasser-/Grundleitung, Zisterne, Rigole, Bewässerungsleitung, Regner, Bewässerungsventil, Außenwasserhahn, Garten-, Wegfläche.
- Installation › „Außen“: Regenwasser (Abfluss, Fallrohr-DN, Zisterne DIN 1989-1, Rigole), Bewässerung (Abdeckung der Gartenflächen, Zonen gegen l/min),
  Licht und Strom außen (Wege-Ausleuchtung, insektenfreundlich, IP, RCD), Kabel außen (Erdkabel: Graben/Schutzrohr/Sand/Warnband; auf Putz: UV-Rohr/Schellen/IP-Dosen;
  NYM-Warnungen). Einstellung `aussen`. Erd-/Außenkabel + Schutzrohr, Regenwasser- und Bewässerungsrohr laufen in die Kabel-/Rohrliste.
- Tests test/build30_test.dart; 289 Tests grün.

## Build 31 (14.11.) – KI-Raumbilder
- lib/core/raumbild.dart: Schnittstelle RaumbildAnbieter mit OpenAiBild (gpt-image-1, /v1/images/edits mit Planskizze bzw. /generations; Größe quer/hoch/quadrat,
  Qualität low/medium/high, Kosten-Richtwerte 0,02/0,07/0,25 €), GeminiBild (gemini-2.5-flash-image, generateContent mit inline_data), ComfyUiBild (eigener
  Server, API-Workflow-JSON mit %PROMPT%/%BILD%, Upload + /prompt + /history + /view). Prompt-Bau (englisch) aus Raumdaten, Stil, Tageszeit, Wünschen.
- lib/ui/raumbild_dialog.dart (Grundriss › Optionen „KI-Raumbild …“, Ausgabe › „KI-Raumbild …“): Raum, Stil, Licht, Planskizze als Vorlage (raumSkizze: Wände,
  Fenster blau, Türen gelb, Objekte mit Namen), Prompt änderbar, Anbieterwahl und Schlüssel (AppSettings.bildki, nur auf diesem PC), Einwilligung „darf an externen
  Dienst“, Kostenhinweis; Bilder unter Projekt/ki_bilder/, Galerie, „Zu den Fotos des Raums“.
- Tests test/build31_test.dart; 292 Tests grün. Echte Anfrage an OpenAI/Gemini nicht getestet (kein Schlüssel).

## Build 32 (15.11.) – Tims Testpunkte zu Build 31
- Grundriss: Maße und Raumnamen überdecken sich nicht mehr (Belegungsprüfung, Raumnamen zuerst, gewählte Wand immer), Raumname schrumpft/verliert Unterzeile
  in kleinen Räumen; Zoomschwellen `mass_ab` / `beide_ab` (px je m, Optionen „Ab welchem Zoom Maße erscheinen …“ und Einstellungen › Darstellung),
  „Raster ausblenden“ (`raster_aus`). Werkzeug bleibt nach Fensterwechsel (je Projekt gemerkt).
- 3D neu (lib/core/drei_d_szene.dart, lib/ui/floorplan/geschoss_3d.dart, texturen3d.dart): nicht mehr spiegelverkehrt (y gespiegelt, auch Technik-3D),
  Wände mit echten Fenstern/Türen (Brüstung, Sturz, Laibung, Glas), verschnittene Ecken, Böden je Raum, prozedurale Texturen (Putz, Farbe, Beton, Ziegel, Klinker,
  KS, Porenbeton, GK, Holz, Fliesen in Formaten, Parkett, Dielen, Vinyl, Teppich, Naturstein, Estrich, Pflaster, Dämmung), Material aus Beschichtungen/Wandtyp/
  Raumname, „Oberflächen je Raum …“ (`ansicht3d` im Raum). Zoom per Mausrad, Touchpad, zwei Fingern und Knöpfen; Wände voll/halb/Grundriss; Raum begehen.
- iPhone: Plan-Beschriftungen ohne Überlappung, Maße blenden sich je Zoom aus/ein; Geschossname statt Kürzel (1. OG). Kürzel folgt beim Umbenennen.
- iPad: 403 beim Projekt holen erklärt (mit Mitarbeiter-Code gekoppelt) – Eigentümer-Rolle darf holen.
- Hilfe-Panel rechts (lib/core/glossar.dart, lib/ui/hilfe_panel.dart; ?-Knopf in der Kopfleiste, `hilfe_panel`): ~110 Begriffe mit Bedeutung, Einheit, Eingabe;
  Klick in ein Feld zeigt den passenden Begriff („Gerade im Feld“).
- Installation: Hauptwerkzeuge oben, Gewerke-Leiste darunter (Elektro/Auslegung, Bad, Wasser, WLAN, Außenanlagen), Live in der Statuszeile.
- Balkon/Terrasse: Wandart „Offene Kante / Plattenrand“ (`art: kante`, `gelaender`), begrenzt den Raum, zählt nicht als Wand/Hülle, Plan zeichnet Plattenrand
  mit Geländerpfosten; Raum-Knopf „Außenränder als offene Kante statt Wand“ (Strg+Z).
- Einkauf als eigenes Modul (lib/ui/einkauf/einkauf_page.dart, lib/core/einkaufslisten.dart, Einstellung `einkaufslisten`): „Noch zu beschaffen“ aus Planung
  (Bibliothek, Kabel-/Rohrliste, Material-Kosten), benannte Einkäufe, von Hand ergänzen, Abhaken = gekauft (Bestand), Einkaufszettel-HTML, Kassenzettel verknüpfen.
  iPhone: Gruppierung „Einkauf“, Abhaken geht an den PC, Kassenzettel-Foto je Einkauf.
- Tests test/build32_test.dart, test/geschoss3d_bild_test.dart; 297 Tests grün.

## Vorgemerkt für Build 33 (erst nach Tims Test von Build 32)
- Ideen aus SCC-CAD (Ziemer) übernehmen, soweit passend (Recherche-Zusammenfassung an Tim).
- iPhone: Steckdosen und alle anderen Installationen aufmessen können; Reiter Aufmessen/Erfassen übersichtlich neu gliedern.
- Hilfe-Panel zeigt nur noch die Erklärung zum gewählten Feld (auch Auswahllisten), darunter Nachschlagen per Suche – schon im Code (nach Build 32), noch nicht gebaut.
- iPad „Projekt holen“: PC packt das Projekt selbst (ZipSchreiber) statt mit Windows-tar – behebt „Packen fehlgeschlagen: tar: null“ (im Code, noch nicht gebaut).
- Rückmeldung Tim zu B32 (vorgemerkt): 3D-Darstellung von Steckdosen/Installationen verbessern; Suche nach Kabel/Leitung, die im Plan hervorgehoben wird.
- Aus SCC-CAD für Build 33 (Tims Wahl): automatische Legende im Plan (Symbole + Montagehöhen, je Gewerk/Blatt); Kabelwege über mehrere Geschosse mit
  Kabelzugliste; Gerätebibliothek nach SCC-Vorbild auf Basis der bestehenden Bibliothek/Inhaltspakete: DIN-Symbole mit Suche, Favoriten, Schnellleiste,
  echte Produktdaten (Hersteller, Modell, Leistung, Maße), Bereiche Elektro, Sicherheit, Netzwerk, Smart Home.
- KERNPUNKT Build 33: Echtzeit-Synchronisation PC ↔ iPad statt Ausleihe mit PC-Sperre. PC bleibt einziger Datenbank-Schreiber; iPad arbeitet live gegen den
  PC-Dienst (jede Änderung als Aktion an den PC, Änderungen per Push/Abo sofort auf beiden Geräten), offline auf dem iPad mit Warteschlange und Abgleich je
  Objekt nach Wiederverbindung, Konflikte sichtbar (beide Stände zeigen, wählen) statt verlorener Daten. Ausleihe bleibt nur als Notlösung ohne Netz.

## Build 33 (15.11.) – Echtzeit-Sync, Kabelwege, Gerätebibliothek, Legende, iPhone-Installationsaufmaß
- Echtzeit-Abgleich PC ↔ iPad (lib/data/sync.dart, lib/state/live_sync.dart, Migration 28 `sync_log`): temporäre Trigger protokollieren jede Zeile,
  Einstellungen je Schlüssel; iPad „Projekt vom PC“ › „Live mitarbeiten“ (PC bleibt frei, Endpunkte projekt/live, projekt/sync, projekt/datei/…),
  Abgleich alle 3 s und 0,4 s nach jeder Änderung, Fotos/Dokumente mit, offline mit Warteschlange, Konflikt = jüngere Änderung gilt, andere unter
  `sync_konflikte` (PC-Statusleiste „n Konflikte“ › wiederherstellen). iPad-Kopfleiste „Live mit PC / Offline · n warten“. Ausleihe bleibt als Notlösung.
- iPad „Projekt holen“: PC packt selbst (ZipSchreiber, WAL-Checkpoint) statt Windows-tar.
- Hilfe-Panel: nur Erklärung zum gewählten Feld (auch Auswahllisten), darunter Nachschlagen.
- 3D: Geräte als Körper (geraeteFlaechen): Steckdose/Schalter/Datendose als Platte mit Einsatz bündig auf der nächsten Wand (Standardhöhen), Leuchten/
  Melder/AP/Luftventil als Scheibe an der Decke, Verteiler/HKV/Geräte als Kasten (echte Maße aus `masse`).
- Kabelsuche (lib/ui/installation/kabel_suche.dart): Feld in der Installation, Treffer gelb nachgezeichnet, Sprung über Geschosse; auch in Strg+F.
- Automatische Legende (lib/ui/installation/legende.dart): Overlay im Installationsplan (Knopf, `legende`), im PDF-Export unten rechts.
- Kabelwege über Geschosse + Kabelzugliste (lib/core/kabelwege.dart, kabelzugliste_dialog.dart): Leitungen über Fortsetzungen und gemeinsame
  Steigleitung SR verbunden, Senkrechte aus Geschosshöhen, +1 m Reserve, Stromkreise ohne Leitung geschätzt; CSV; Klick zeigt den Weg.
- Gerätebibliothek (lib/ui/installation/geraete_bibliothek.dart): Bereiche (Elektro, Licht, Netzwerk, Sicherheit, Smart Home, Sanitär, Heizung, Lüftung,
  Außen), Suche, Favoriten (`geraete_favoriten`, je PC) als Schnellleiste, Produkte aus der Bibliothek → neues Objekt übernimmt bauelement, masse, leistung_w.
- iPhone Raum-Aufmaß mit Reitern Wände/Öffnungen/Installationen/Höhe·Diagonalen; Installationen: ab Wandecke und Höhe messen; „Installation
  aufnehmen“ für Fehlendes → Aufmaß `objekt_neu` legt am PC das Objekt an.
- Tests test/build33_test.dart, test/live_sync_test.dart; 300 Tests grün.

## Vorgemerkt für Build 34 (Tims Test von Build 33, sammelt noch – erst bauen, wenn er fertig ist)
- SCHON IM CODE (nach Build 33): App-Aufmaß „Das Bauteil gibt es im Plan nicht mehr“ – Ursache: der Puffer der App (Puffer.ablegen) überschrieb die
  Wand-ID mit der Kennung der Erfassung. Behoben (App behält `id`, schickt zusätzlich `ziel_id`; PC nimmt `ziel_id`). Für bereits gesendete Maße findet
  der PC die Wand über Raum, Seite und Planlänge wieder (aufmassZielAufloesen) – an Tims offenem Flur-Maß geprüft. Braucht neuen PC-Build + neue IPA.
- App: Rückmeldung, ob ein Aufmaß am PC übernommen oder verworfen wurde; verworfene Maße in der App wieder als „neu messen“ zeigen.
- Offene Kante: anstoßende Wand wird abgeschnitten bzw. bekommt 45°-Gehrung – an offenen Kanten nicht verschneiden (automatisch), notfalls manuell
  Ecke wählbar.
- Wand Schlafzimmer → Balkon (5560 mm) zeichnet einen Absatz, auch mit anderem Wandtyp falsch dargestellt – prüfen.
- Wärmebrücken Einbaudetail/Fenster: Dämmstoff für die Leitungs-/Fugendämmung wählbar, danach Dicke; Werte ohne Enter übernehmen (sofort beim Tippen);
  Zwischenrahmen und Laibung richtig: eigener Punkt für Dämmung zwischen Fenster und Laibung; Option zusätzliche Schicht zwischen Wandausschnitt/Fuge
  (Dämmmaterial) und Fenster mit Materialwahl.
