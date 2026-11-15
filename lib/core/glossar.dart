/// Fachbegriffe mit kurzer Erklärung, Einheit und was man eingibt – für das
/// Hilfe-Panel rechts. [stichworte] (klein geschrieben) verbinden einen
/// Begriff mit Feldbeschriftungen, damit die passende Erklärung erscheint,
/// sobald man in ein Feld klickt.
library;

class Begriff {
  const Begriff(this.bereich, this.name, this.kurz, {this.einheit = '', this.eingabe = '', this.stichworte = const []});
  final String bereich, name, kurz, einheit, eingabe;
  final List<String> stichworte;

  bool passt(String suche) {
    final s = suche.toLowerCase();
    return name.toLowerCase().contains(s) || kurz.toLowerCase().contains(s) || stichworte.any((w) => w.contains(s));
  }
}

const bereichAbgleich = 'Heizung und hydraulischer Abgleich';
const bereichBauphysik = 'Bauphysik und Heizlast';
const bereichFenster = 'Fenster, Türen, Bibliothek';
const bereichElektro = 'Elektro';
const bereichWasser = 'Wasser und Abwasser';
const bereichLueftung = 'Lüftung und Klima';
const bereichTechnik = 'Haustechnik (Wärmeerzeuger, Speicher)';
const bereichGrundriss = 'Grundriss, Höhen und Maße';
const bereichKeller = 'Keller, Sockel, Fassade, Putz';
const bereichStatik = 'Statik (nur Orientierung)';
const bereichWlan = 'WLAN und Außenanlagen';
const bereichKosten = 'Kosten und Einkauf';

const glossar = <Begriff>[
  // ------------------------------------------------ Abgleich
  Begriff(bereichAbgleich, 'Heizlast', 'Wärme, die ein Raum am kältesten Auslegungstag verliert und die die Heizung nachliefern muss (DIN EN 12831).',
      einheit: 'W (Watt)', eingabe: 'Kommt aus der Heizlastberechnung im Modul Bauphysik; nur von Hand eintragen, wenn ein Fachplaner sie geliefert hat.', stichworte: ['heizlast']),
  Begriff(bereichAbgleich, 'Leistung (Heizkörper/Heizkreis)', 'Wärme, die ein Heizkörper oder Fußbodenkreis bei den gewählten Temperaturen abgibt. Sie sollte die Heizlast des Raums decken.',
      einheit: 'W', eingabe: 'Normleistung vom Typenschild/Datenblatt (meist bei 75/65/20 °C). BauSpur rechnet sie auf die eigenen Vorlauf-/Rücklauftemperaturen um.', stichworte: ['leistung', 'normleistung', 'nennleistung']),
  Begriff(bereichAbgleich, 'Vorlauftemperatur', 'Temperatur des Heizwassers, das zum Heizkörper hinfließt. Je niedriger, desto effizienter (v. a. Wärmepumpe).',
      einheit: '°C', eingabe: 'Auslegungswert am kältesten Tag, z. B. 55 °C Heizkörper, 35 °C Fußbodenheizung.', stichworte: ['vorlauf', 'vl']),
  Begriff(bereichAbgleich, 'Rücklauftemperatur', 'Temperatur des abgekühlten Wassers, das vom Heizkörper zurückfließt.', einheit: '°C', eingabe: 'z. B. 45 °C bei 55 °C Vorlauf (10 K Spreizung).', stichworte: ['rücklauf', 'ruecklauf', 'rl']),
  Begriff(bereichAbgleich, 'Spreizung', 'Unterschied zwischen Vor- und Rücklauftemperatur. Kleine Spreizung = mehr Wasser muss fließen.',
      einheit: 'K (Kelvin, entspricht °C-Differenz)', eingabe: 'Heizkörper meist 10–15 K, Fußbodenheizung 5–8 K, Wärmepumpe eher 5–7 K.', stichworte: ['spreizung', 'delta t', 'Δt']),
  Begriff(bereichAbgleich, 'Volumenstrom / Massenstrom', 'Wie viel Heizwasser pro Stunde durch Heizkörper oder Kreis fließen muss: Leistung ÷ (1,163 × Spreizung).',
      einheit: 'l/h bzw. kg/h', eingabe: 'Wird berechnet. Zum Prüfen: 1000 W bei 10 K ≈ 86 l/h.', stichworte: ['volumenstrom', 'massenstrom', 'durchfluss', 'l/h']),
  Begriff(bereichAbgleich, 'Druckverlust', 'Widerstand, den Rohr, Ventil und Heizkörper dem Wasser entgegensetzen. Die Pumpe muss den größten Strang schaffen.',
      einheit: 'Pa, mbar, kPa (100 Pa = 1 mbar)', eingabe: 'Wird aus Rohrlänge, Nennweite und Durchfluss geschätzt.', stichworte: ['druckverlust', 'delta p', 'Δp']),
  Begriff(bereichAbgleich, 'kv-Wert', 'Durchfluss durch ein Ventil bei 1 bar Druckverlust. Kleiner kv = stärker gedrosselt. kvs = kv bei ganz offenem Ventil.',
      einheit: 'm³/h', eingabe: 'Ergebnis des Abgleichs; daraus folgt die Voreinstellung laut Herstellertabelle des Ventils.', stichworte: ['kv', 'kvs', 'kv-wert']),
  Begriff(bereichAbgleich, 'Voreinstellung / Ventilstufe', 'Stellung am Thermostatventil (z. B. 1–6 oder N), mit der der Durchfluss jedes Heizkörpers begrenzt wird – das ist der eigentliche Abgleich.',
      einheit: 'Stufe laut Hersteller', eingabe: 'Ventilhersteller/-typ wählen, BauSpur schlägt die Stufe aus dem kv-Wert vor. Am Ventil mit dem Einstellschlüssel einstellen.', stichworte: ['voreinstellung', 'ventilstufe', 'stufe', 'einstellwert']),
  Begriff(bereichAbgleich, 'Ventil offen / ungeregelt', 'Ventil ohne Voreinstellung: Heizkörper nahe der Pumpe bekommen zu viel Wasser, entfernte zu wenig. Typisch für „oben warm, hinten kalt“.',
      eingabe: 'Haken setzen, wenn ein Heizkörper bewusst voll offen bleibt (z. B. Referenzheizkörper oder ohne Thermostat).', stichworte: ['ventil offen', 'offen', 'ungeregelt']),
  Begriff(bereichAbgleich, 'Ventilautorität', 'Anteil des Ventils am Druckverlust des Strangs. Unter 0,3 regelt das Thermostat schlecht.', einheit: '0 … 1', stichworte: ['autorität', 'autoritaet']),
  Begriff(bereichAbgleich, 'Pumpenförderhöhe', 'Druck, den die Heizungspumpe aufbringen muss (größter Strang plus Reserve).', einheit: 'm Wassersäule (1 m ≈ 10 kPa)', eingabe: 'Ergebnis; an der Pumpe als Konstant-/Proportionaldruck einstellen.', stichworte: ['förderhöhe', 'foerderhoehe', 'pumpe']),
  Begriff(bereichAbgleich, 'Heizkörperexponent n', 'Wie stark die Heizkörperleistung bei niedrigeren Temperaturen sinkt.', einheit: 'ohne (meist 1,3; FBH 1,1)', eingabe: 'Aus dem Datenblatt, sonst 1,3 lassen.', stichworte: ['exponent']),
  Begriff(bereichAbgleich, 'Übertemperatur', 'Mittlere Heizwassertemperatur minus Raumtemperatur – bestimmt die Leistung des Heizkörpers.', einheit: 'K', stichworte: ['übertemperatur', 'uebertemperatur']),
  Begriff(bereichAbgleich, 'Verlegeabstand (FBH)', 'Abstand der Rohre der Fußbodenheizung. Enger = mehr Leistung, mehr Rohr.', einheit: 'mm (meist 100–200)', eingabe: 'Randzonen/Bad enger (100), Wohnräume 150, Schlafen 200.', stichworte: ['verlegeabstand', 'va']),
  Begriff(bereichAbgleich, 'Heizkreislänge', 'Rohrlänge eines Fußbodenkreises inkl. Zuleitung. Über ca. 100–120 m (16 mm Rohr) wird der Druckverlust zu groß – dann teilen.', einheit: 'm', stichworte: ['kreislänge', 'kreislaenge', 'heizkreis']),
  Begriff(bereichAbgleich, 'Wärmestromdichte', 'Leistung je m² Boden. Komfortgrenze Oberfläche: Wohnräume 29 °C, Randzonen 35 °C.', einheit: 'W/m²', stichworte: ['wärmestromdichte', 'w/m²']),
  Begriff(bereichAbgleich, 'Raumsolltemperatur', 'Temperatur, auf die der Raum ausgelegt wird.', einheit: '°C', eingabe: 'Wohnen 20, Bad 24, Schlafen 18–20, Flur 15–18.', stichworte: ['solltemperatur', 'raumtemperatur', 'innentemperatur', 'θint']),
  // ------------------------------------------------ Bauphysik
  Begriff(bereichBauphysik, 'U-Wert', 'Wärmedurchgangskoeffizient: Wie viel Wärme pro m² und Kelvin Temperaturunterschied durch ein Bauteil geht. Kleiner = besser gedämmt.',
      einheit: 'W/(m²·K)', eingabe: 'Wird aus den Schichten berechnet. Richtwerte: Außenwand neu ≤ 0,24, Dach ≤ 0,20, Fenster ≤ 1,3 (GEG-Sanierung).', stichworte: ['u-wert', 'u wert', 'u =']),
  Begriff(bereichBauphysik, 'Wärmeleitfähigkeit λ (Lambda)', 'Wie gut ein Baustoff Wärme leitet. Dämmstoffe 0,022–0,045, Ziegel 0,08–0,5, Beton 2,1.', einheit: 'W/(m·K)', eingabe: 'Vom Produktdatenblatt (Bemessungswert λB), sonst Vorgabe der Bibliothek.', stichworte: ['lambda', 'λ', 'wärmeleit', 'waermeleit']),
  Begriff(bereichBauphysik, 'Wärmedurchlasswiderstand R', 'Dämmwirkung einer Schicht: Dicke ÷ λ. Die Summe aller R plus Übergänge ergibt 1/U.', einheit: 'm²·K/W', stichworte: ['r-wert', 'durchlasswiderstand']),
  Begriff(bereichBauphysik, 'Rsi / Rse', 'Wärmeübergangswiderstände innen (0,13) und außen (0,04) – fest nach Norm, Dach/Boden etwas anders.', einheit: 'm²·K/W', stichworte: ['rsi', 'rse']),
  Begriff(bereichBauphysik, 'Dampfdiffusionswiderstand μ (My)', 'Wie stark ein Stoff Wasserdampf bremst im Vergleich zu Luft (μ = 1). Folie: sehr hoch.', einheit: 'ohne', eingabe: 'Datenblatt; bei Spanne den ungünstigeren Wert.', stichworte: ['μ', 'mu', 'diffusion']),
  Begriff(bereichBauphysik, 'sd-Wert', 'Diffusionsäquivalente Luftschichtdicke = μ × Dicke. Dampfbremse innen etwa sd 2–100 m, außen sollte die Schicht diffusionsoffener sein.', einheit: 'm', stichworte: ['sd', 'sd-wert']),
  Begriff(bereichBauphysik, 'Rohdichte ρ', 'Masse je m³ eines Baustoffs – wichtig für Wärmespeicherung und Schallschutz.', einheit: 'kg/m³', stichworte: ['rohdichte', 'dichte', 'ρ', 'rho']),
  Begriff(bereichBauphysik, 'Spezifische Wärmekapazität c', 'Energie, um 1 kg um 1 K zu erwärmen. Holz ~1600, Mineralisch ~1000.', einheit: 'J/(kg·K)', stichworte: ['wärmekapazität', 'waermekapazitaet', 'c (j']),
  Begriff(bereichBauphysik, 'Taupunkt / Tauwasser', 'Temperatur, bei der Luftfeuchte kondensiert. Liegt sie in der Wand, kann dort Wasser ausfallen (Glaser-Verfahren prüft das).', einheit: '°C', stichworte: ['taupunkt', 'tauwasser', 'glaser']),
  Begriff(bereichBauphysik, 'Temperaturfaktor fRsi', 'Maß für Schimmelgefahr an Ecken und Wärmebrücken. Muss ≥ 0,70 sein.', einheit: 'ohne', stichworte: ['frsi']),
  Begriff(bereichBauphysik, 'Wärmebrücke ψ (Psi)', 'Zusätzlicher Wärmeverlust an Kanten und Anschlüssen (Balkonplatte, Fensteranschluss, Sockel) je Meter.', einheit: 'W/(m·K)', eingabe: 'Pauschal 0,05 W/m²K auf alle Flächen, oder detailliert je Anschluss.', stichworte: ['wärmebrücke', 'waermebruecke', 'psi', 'ψ']),
  Begriff(bereichBauphysik, 'Norm-Außentemperatur', 'Kältester Auslegungstag am Standort (DIN/TS 12831-1), z. B. −12 °C in weiten Teilen Deutschlands.', einheit: '°C', eingabe: 'Aus Standort/PLZ in den Einstellungen.', stichworte: ['außentemperatur', 'aussentemperatur', 'θe']),
  Begriff(bereichBauphysik, 'Luftwechsel n', 'Wie oft die Raumluft pro Stunde ausgetauscht wird (Lüftungswärmeverlust).', einheit: '1/h', eingabe: 'Ohne Lüftungsanlage 0,5; mit Anlage aus deren Volumenstrom.', stichworte: ['luftwechsel']),
  Begriff(bereichBauphysik, 'n50 (Luftdichtheit)', 'Luftwechsel bei 50 Pa Druckunterschied im Blower-Door-Test. Neubau ≤ 3, mit Lüftungsanlage ≤ 1,5.', einheit: '1/h', stichworte: ['n50', 'blower']),
  Begriff(bereichBauphysik, 'Wärmerückgewinnung (WRG)', 'Anteil der Wärme aus der Abluft, den die Lüftungsanlage an die Zuluft zurückgibt.', einheit: '%', eingabe: 'Datenblatt des Lüftungsgeräts, typisch 75–90 %.', stichworte: ['wrg', 'rückgewinnung', 'rueckgewinnung']),
  Begriff(bereichBauphysik, 'Aufheizzuschlag', 'Zusatzleistung, damit Räume nach Absenkung wieder schnell warm werden. Bei Wärmepumpen meist 0.', einheit: 'W/m²', stichworte: ['aufheiz']),
  // ------------------------------------------------ Fenster
  Begriff(bereichFenster, 'Uw (Fenster gesamt)', 'U-Wert des ganzen Fensters (w = window): Glas, Rahmen und Randverbund zusammen. Der Wert, der für GEG und Heizlast zählt.',
      einheit: 'W/(m²·K)', eingabe: 'Vom Angebot/Datenblatt (für die echte Fenstergröße oder Normgröße 1,23 × 1,48 m). Ohne Angabe rechnet BauSpur aus Ug, Uf und ψg.', stichworte: ['uw']),
  Begriff(bereichFenster, 'Ug (Glas)', 'U-Wert nur der Verglasung (g = glazing). 2-fach ~1,1, 3-fach 0,5–0,7.', einheit: 'W/(m²·K)', eingabe: 'Steht auf dem Glasaufdruck/Datenblatt.', stichworte: ['ug']),
  Begriff(bereichFenster, 'Uf (Rahmen)', 'U-Wert des Rahmens (f = frame). Kunststoff/Holz 1,0–1,4; Passivhausrahmen < 0,8.', einheit: 'W/(m²·K)', eingabe: 'Datenblatt des Profilsystems.', stichworte: ['uf']),
  Begriff(bereichFenster, 'ψg (Randverbund)', 'Wärmebrücke am Glasrand durch den Abstandhalter. Warme Kante ~0,04, Alu ~0,08.', einheit: 'W/(m·K)', stichworte: ['ψg', 'psi-g', 'randverbund']),
  Begriff(bereichFenster, 'g-Wert', 'Gesamtenergiedurchlassgrad: Anteil der Sonnenenergie, der durchs Glas in den Raum kommt (Wärmegewinn im Winter, Überhitzung im Sommer).', einheit: '0 … 1 bzw. %', eingabe: '3-fach typ. 0,5; Sonnenschutzglas 0,3.', stichworte: ['g-wert', 'g wert']),
  Begriff(bereichFenster, 'Lichttransmission τv', 'Anteil des sichtbaren Lichts, der durchgeht.', einheit: '%', stichworte: ['lichttransmission', 'τv', 'tl']),
  Begriff(bereichFenster, 'Schalldämmmaß Rw', 'Wie stark das Fenster Lärm dämpft. +10 dB ≈ halb so laut empfunden.', einheit: 'dB', eingabe: 'Datenblatt (Schallschutzklasse 2 ≈ 30–34 dB).', stichworte: ['rw', 'schall']),
  Begriff(bereichFenster, 'RC-Klasse', 'Einbruchhemmung nach DIN EN 1627 (RC1N … RC6). Für Wohnhäuser meist RC2.', stichworte: ['rc', 'einbruch']),
  Begriff(bereichFenster, 'Rohbaumaß / Baurichtmaß', 'Öffnungsmaß im Rohbau. Das Fenster ist rundum ca. 10–15 mm kleiner (Fuge für Abdichtung).', einheit: 'mm', eingabe: 'Im Grundriss als Öffnungsbreite/-höhe; Bestellmaß rechnet BauSpur mit Fuge.', stichworte: ['rohbaumaß', 'rohbaumass', 'baurichtmaß', 'bestellmaß']),
  Begriff(bereichFenster, 'Brüstungshöhe', 'Höhe der Fensterunterkante über Fertigfußboden (FFB). Absturzsicherung ab 0,90 m (bis 12 m Höhe) bzw. Geländer nötig.', einheit: 'mm', stichworte: ['brüstung', 'bruestung', 'brh']),
  Begriff(bereichFenster, 'Sturz', 'Tragendes Bauteil über einer Öffnung. Sturzhöhe = Oberkante der Öffnung über FFB.', einheit: 'mm', stichworte: ['sturz']),
  Begriff(bereichFenster, 'Einbaulage', 'Wo das Fenster in der Wand sitzt: in der Dämmebene (energetisch am besten), Mitte oder innen bündig.', stichworte: ['einbaulage']),
  Begriff(bereichFenster, 'Ud (Tür)', 'U-Wert der ganzen Tür (d = door). Haustür neu ≤ 1,3.', einheit: 'W/(m²·K)', stichworte: ['ud']),
  Begriff(bereichFenster, 'Fensterbank: Überstand und Tropfkante', 'Außenfensterbank steht 30–50 mm vor die fertige Fassade, damit Wasser abtropft; Gefälle ≥ 5°.', einheit: 'mm', stichworte: ['überstand', 'ueberstand', 'tropfkante', 'fensterbank']),
  // ------------------------------------------------ Elektro
  Begriff(bereichElektro, 'Leitungsquerschnitt', 'Kupferquerschnitt einer Ader. Bestimmt, welcher Strom sicher fließen darf und wie viel Spannung verloren geht.', einheit: 'mm²', eingabe: '1,5 mm² bis B16 (Licht/Steckdosen), 2,5 mm² für lange Wege/B20, Herd 5×2,5 mm².', stichworte: ['querschnitt', 'mm²']),
  Begriff(bereichElektro, 'Spannungsfall', 'Spannung, die auf der Leitung verloren geht. Max. 3 % ab Zähler empfohlen (DIN 18015-1).', einheit: '%', eingabe: 'Wird aus Länge, Querschnitt und Strom berechnet.', stichworte: ['spannungsfall']),
  Begriff(bereichElektro, 'Leitungsschutzschalter (LS)', 'Sicherung gegen Überlast/Kurzschluss, z. B. B16 = Charakteristik B, 16 A.', einheit: 'A', eingabe: 'Charakteristik B für Haushalt, C für Motoren/Anlaufströme.', stichworte: ['absicherung', 'ls', 'sicherung', 'b16']),
  Begriff(bereichElektro, 'FI / RCD', 'Fehlerstromschutzschalter, schaltet ab, wenn Strom über den Menschen abfließt. 30 mA für Steckdosen Pflicht. Typ A/F/B je nach Gerät (Wallbox/WP oft Typ B).', einheit: 'mA', stichworte: ['fi', 'rcd', 'fehlerstrom']),
  Begriff(bereichElektro, 'Verlegeart', 'Wie die Leitung liegt (A1 in Dämmung, B2 im Rohr auf Wand, C direkt auf/in Wand). Beeinflusst die zulässige Belastung.', stichworte: ['verlegeart']),
  Begriff(bereichElektro, 'Häufung', 'Viele Leitungen nebeneinander werden wärmer – die zulässige Belastung sinkt (Faktor < 1).', stichworte: ['häufung', 'haeufung']),
  Begriff(bereichElektro, 'Installationszonen', 'Bereiche, in denen Leitungen laufen dürfen (DIN 18015-3): waagerecht 15–45 cm unter Decke/über Boden, senkrecht 10–30 cm neben Ecken/Öffnungen.', stichworte: ['installationszone']),
  Begriff(bereichElektro, 'IP-Schutzart', 'Schutz gegen Fremdkörper und Wasser (IP44 spritzwassergeschützt, IP65 strahlwassergeschützt). Bad und außen beachten.', stichworte: ['ip', 'schutzart']),
  Begriff(bereichElektro, 'Überspannungsschutz', 'Typ 1 (Blitzstrom, am Hausanschluss), Typ 2 (im Verteiler), Typ 3 (am Gerät). Für Neuanlagen vorgeschrieben.', stichworte: ['überspannung', 'ueberspannung', 'spd']),
  Begriff(bereichElektro, 'Isolationswiderstand / Schleifenimpedanz', 'Prüfwerte nach DIN VDE 0100-600: Isolation ≥ 1 MΩ; Schleifenimpedanz so klein, dass die Sicherung schnell genug auslöst.', einheit: 'MΩ, Ω', stichworte: ['isolation', 'schleifen', 'riso', 'zs']),
  // ------------------------------------------------ Wasser
  Begriff(bereichWasser, 'Nennweite DN / Außendurchmesser', 'Rohrgröße. DN ist grob der Innendurchmesser; Verbundrohr wird als Außendurchmesser × Wand angegeben (16×2).', einheit: 'mm', stichworte: ['dn', 'nennweite', 'durchmesser']),
  Begriff(bereichWasser, 'Spitzendurchfluss', 'Größter gleichzeitiger Wasserbedarf nach DIN 1988-300 – daraus folgt die Rohrgröße.', einheit: 'l/s', stichworte: ['spitzendurchfluss', 'l/s']),
  Begriff(bereichWasser, 'Fließdruck / Ruhedruck', 'Ruhedruck = Druck ohne Entnahme; Fließdruck = Druck an der Zapfstelle bei Entnahme (mind. 1 bar, Dusche besser 2).', einheit: 'bar', stichworte: ['fließdruck', 'fliessdruck', 'ruhedruck', 'druck']),
  Begriff(bereichWasser, 'Zirkulation', 'Warmwasser läuft im Kreis, damit es sofort warm aus der Leitung kommt. Mindestens 55 °C Rücklauf (Legionellen).', stichworte: ['zirkulation']),
  Begriff(bereichWasser, '3-Liter-Regel', 'In einer Warmwasserleitung ohne Zirkulation dürfen höchstens 3 l stehen (Hygiene).', einheit: 'l', stichworte: ['3-liter', 'stagnation']),
  Begriff(bereichWasser, 'Gefälle Abwasser', 'Neigung der Abwasserleitung, damit sie selbst leer läuft: 1–2 % (1–2 cm je Meter).', einheit: '%', stichworte: ['gefälle', 'gefaelle']),
  Begriff(bereichWasser, 'Anschlusswert DU', 'Abwassermenge eines Gegenstands nach DIN 1986-100 (WC 2,0; Dusche 0,6; Waschtisch 0,5).', einheit: 'l/s', stichworte: ['du', 'anschlusswert']),
  Begriff(bereichWasser, 'Rückstauebene', 'Höhe, bis zu der Abwasser aus dem Kanal zurückdrücken kann (meist Straßenoberkante). Darunter: Rückstausicherung/Hebeanlage.', stichworte: ['rückstau', 'rueckstau']),
  // ------------------------------------------------ Lüftung
  Begriff(bereichLueftung, 'Luftvolumenstrom', 'Luftmenge pro Stunde, die gefördert wird.', einheit: 'm³/h', eingabe: 'Je Raum aus DIN 1946-6, z. B. Bad 40, Küche 60, WC 20 m³/h Abluft.', stichworte: ['volumenstrom', 'm³/h', 'luftmenge']),
  Begriff(bereichLueftung, 'Lüftungsstufen (DIN 1946-6)', 'Feuchteschutz (immer, nutzerunabhängig), reduziert, Nennlüftung (normaler Betrieb), Intensiv.', stichworte: ['feuchteschutz', 'nennlüftung', 'nennlueftung', 'lüftungsstufe']),
  Begriff(bereichLueftung, 'Zuluft / Abluft / Überström', 'Zuluft in Wohn-/Schlafräume, Abluft aus Bad/Küche/WC, dazwischen Überströmbereiche (Türspalt, Überströmelement).', stichworte: ['zuluft', 'abluft', 'überström', 'ueberstroem']),
  Begriff(bereichLueftung, 'Schalldruckpegel', 'Lautstärke am Ventil/Gerät. Schlafräume ≤ 25 dB(A).', einheit: 'dB(A)', stichworte: ['schalldruck', 'db(a)']),
  // ------------------------------------------------ Haustechnik
  Begriff(bereichTechnik, 'JAZ / COP', 'Effizienz der Wärmepumpe: COP im Prüfpunkt, JAZ übers ganze Jahr (Wärme ÷ Strom). JAZ 3,5 = aus 1 kWh Strom werden 3,5 kWh Wärme.', einheit: 'ohne', stichworte: ['jaz', 'cop', 'scop']),
  Begriff(bereichTechnik, 'Bivalenzpunkt', 'Außentemperatur, unter der die Wärmepumpe Hilfe vom Heizstab/zweiten Erzeuger braucht.', einheit: '°C', stichworte: ['bivalenz']),
  Begriff(bereichTechnik, 'Heizkurve', 'Zusammenhang Außentemperatur → Vorlauftemperatur (Steigung und Niveau/Parallelverschiebung).', stichworte: ['heizkurve', 'steigung', 'niveau']),
  Begriff(bereichTechnik, 'Pufferspeicher', 'Wasserspeicher für Heizwasser: verlängert Laufzeiten, überbrückt Sperrzeiten.', einheit: 'l', eingabe: 'Grob 20–30 l je kW Wärmepumpenleistung, wenn ein Puffer nötig ist.', stichworte: ['puffer']),
  Begriff(bereichTechnik, 'Ausdehnungsgefäß (MAG)', 'Nimmt das größere Volumen warmen Wassers auf. Vordruck ≈ statische Höhe + 0,3 bar.', einheit: 'l, bar', stichworte: ['ausdehnung', 'mag', 'vordruck']),
  Begriff(bereichTechnik, 'Anlagendruck', 'Druck im Heizungssystem, kalt meist 1,5–2 bar im Einfamilienhaus.', einheit: 'bar', stichworte: ['anlagendruck', 'fülldruck']),
  Begriff(bereichTechnik, 'Sperrzeit (EVU)', 'Zeiten, in denen der Netzbetreiber den Wärmepumpenstrom abschalten darf (§14a EnWG).', einheit: 'h', stichworte: ['sperrzeit', 'evu', '14a']),
  Begriff(bereichTechnik, 'Legionellenschutz', 'Warmwasser regelmäßig auf ≥ 60 °C, Zirkulation ≥ 55 °C.', einheit: '°C', stichworte: ['legionell']),
  // ------------------------------------------------ Grundriss
  Begriff(bereichGrundriss, 'Achsmaß', 'Maß von Wandmitte zu Wandmitte – so zeichnet BauSpur die Wand.', einheit: 'mm', stichworte: ['achse', 'achsmaß']),
  Begriff(bereichGrundriss, 'Lichtes Maß / Innenmaß', 'Freier Abstand zwischen zwei Wandoberflächen im Raum.', einheit: 'mm', stichworte: ['licht', 'innen']),
  Begriff(bereichGrundriss, 'Rohbaumaß / Fertigmaß', 'Rohbau = ohne Putz/Bekleidung; fertig = mit Putz, Fliesen, Vorsatzschale. In BauSpur je Ansicht umschaltbar.', stichworte: ['rohbau', 'fertig']),
  Begriff(bereichGrundriss, 'RFB / FFB', 'Rohfußboden (Oberkante Decke/Bodenplatte) und Fertigfußboden (Oberkante Belag). Dazwischen: Dämmung, Estrich, Belag.', einheit: 'mm', stichworte: ['rfb', 'ffb', 'okff', 'fußboden']),
  Begriff(bereichGrundriss, 'Rohdecke / UK Decke', 'Unterkante der Rohdecke bzw. der fertigen Decke (abgehängt). Lichte Raumhöhe = UK Decke − FFB.', einheit: 'mm', stichworte: ['rohdecke', 'uk decke', 'ukdecke', 'raumhöhe']),
  Begriff(bereichGrundriss, 'Wandstärke / Dicke', 'Gesamte Wanddicke aus allen Schichten des Wandtyps.', einheit: 'mm', stichworte: ['dicke', 'wandstärke', 'stärke']),
  Begriff(bereichGrundriss, 'Außenbereich (Balkon/Terrasse)', 'Fläche ohne Wände ringsum: Rand ist eine offene Kante (Plattenrand), zählt nicht als Wohnfläche (Balkon nach WoFlV meist zu 1/4).', stichworte: ['balkon', 'terrasse', 'außenbereich', 'aussenbereich']),
  // ------------------------------------------------ Keller/Fassade
  Begriff(bereichKeller, 'Wassereinwirkungsklasse (DIN 18533)', 'W1-E Bodenfeuchte, W2-E drückendes Wasser, W3-E nicht drückendes Wasser auf Decken, W4-E Spritzwasser/Sockel.', stichworte: ['lastfall', 'w1-e', 'w2-e', 'wassereinwirkung', '18533']),
  Begriff(bereichKeller, 'Perimeterdämmung', 'Dämmung außen auf der Abdichtung im Erdreich (XPS/EPS-P), druckfest und wasserunempfindlich.', einheit: 'mm Dicke', stichworte: ['perimeter', 'xps']),
  Begriff(bereichKeller, 'Sockel / Spritzwasserbereich', 'Mindestens 30 cm über Gelände: dort andere Dämmung (Sockelplatte) und Abdichtung, Putz wasserabweisend.', einheit: 'mm', stichworte: ['sockel', 'spritzwasser']),
  Begriff(bereichKeller, 'KMB / PMBC', 'Kunststoffmodifizierte Bitumendickbeschichtung – übliche Kellerabdichtung außen, Trockenschichtdicke laut Lastfall (z. B. 3–4 mm).', einheit: 'mm', stichworte: ['kmb', 'pmbc', 'bitumen']),
  Begriff(bereichKeller, 'Noppenbahn / Drainage', 'Schutz der Abdichtung; Drainage leitet Sickerwasser ab (nur mit Vorflut erlaubt).', stichworte: ['noppen', 'drainage', 'dränage']),
  Begriff(bereichKeller, 'Putzprofile', 'Eckschutz-, Sockel-, Abschluss-, Tropfkanten-, Anputz- und Dehnfugenprofile. Mengen aus Kanten und Öffnungen.', einheit: 'm (Stablänge meist 2,5 m)', stichworte: ['putzprofil', 'eckwinkel', 'anputz', 'sockelprofil']),
  Begriff(bereichKeller, 'WDVS', 'Wärmedämmverbundsystem: Dämmplatte geklebt/gedübelt, Armierung mit Gewebe, Oberputz.', stichworte: ['wdvs', 'armierung']),
  // ------------------------------------------------ Statik
  Begriff(bereichStatik, 'tragende Wand', 'Wand, die Decken/Dach trägt. Durchbrüche und Abriss nur mit Statiker – BauSpur zeigt Hinweise, rechnet aber keine Statik.', stichworte: ['tragend']),
  Begriff(bereichStatik, 'Auflagerlänge', 'Wie weit ein Sturz/Träger auf der Wand aufliegt, meist ≥ 115–175 mm je Seite.', einheit: 'mm', stichworte: ['auflager']),
  Begriff(bereichStatik, 'Unterzug', 'Träger unter der Decke, der Lasten statt einer Wand aufnimmt.', stichworte: ['unterzug']),
  // ------------------------------------------------ WLAN / Außen
  Begriff(bereichWlan, 'Signalpegel (dBm)', 'Empfangsstärke: −50 sehr gut, −67 gut (Video/Telefonie), −75 schwach, unter −80 kaum nutzbar.', einheit: 'dBm', stichworte: ['dbm', 'pegel']),
  Begriff(bereichWlan, 'Wanddämpfung', 'Wie viel Signal eine Wand schluckt: Leichtbau 3–5 dB, Ziegel 6–10, Stahlbeton 15–25. Jede 3 dB = halbe Leistung.', einheit: 'dB', stichworte: ['dämpfung', 'daempfung']),
  Begriff(bereichWlan, 'Band 2,4 / 5 / 6 GHz', '2,4 GHz reicht weiter, ist aber langsamer und voller; 5/6 GHz schneller, aber stärker gedämpft.', stichworte: ['ghz', 'band']),
  Begriff(bereichWlan, 'Abflussbeiwert C', 'Anteil des Regens, der von einer Fläche abfließt (Dach 0,9–1,0; Pflaster 0,7; Rasen 0,1).', einheit: '0 … 1', stichworte: ['abflussbeiwert', 'beiwert']),
  Begriff(bereichWlan, 'Erdkabel NYY', 'Kabel für die Verlegung im Erdreich (NYY-J), 60–80 cm tief mit Warnband; NYM ist nicht erdtauglich.', stichworte: ['nyy', 'erdkabel']),
  // ------------------------------------------------ Kosten
  Begriff(bereichKosten, 'Verschnitt', 'Zuschlag für Abfall beim Zuschneiden (Fliesen 10–15 %, Laminat 5–10 %, Dämmung 5 %).', einheit: '%', stichworte: ['verschnitt']),
  Begriff(bereichKosten, 'Gebinde', 'Verkaufseinheit (Sack, Eimer, Paket). BauSpur rundet die Menge auf ganze Gebinde.', stichworte: ['gebinde']),
  Begriff(bereichKosten, 'Netto / Brutto', 'Brutto = Netto + 19 % MwSt. Angebote vergleichen immer gleich (meist brutto für Privat).', stichworte: ['netto', 'brutto', 'mwst']),
];

/// Bereiche, die zu einem Modul gehören (Name des Moduls wie in [Modul.name]).
const glossarJeModul = <String, List<String>>{
  'grundriss': [bereichGrundriss, bereichFenster, bereichKeller, bereichStatik],
  'installation': [bereichElektro, bereichWasser, bereichWlan, bereichAbgleich],
  'haustechnik': [bereichAbgleich, bereichTechnik, bereichLueftung],
  'verteiler': [bereichElektro],
  'bauteile': [bereichFenster, bereichBauphysik],
  'bauphysik': [bereichBauphysik, bereichAbgleich],
  'kosten': [bereichKosten],
  'export': [bereichKosten],
};

/// Bester Begriff zu einer Feldbeschriftung (z. B. „Spreizung (K)“).
Begriff? begriffZuFeld(String? beschriftung) {
  if (beschriftung == null || beschriftung.trim().isEmpty) return null;
  final t = beschriftung.toLowerCase();
  Begriff? best;
  var laenge = 0;
  for (final b in glossar) {
    for (final w in b.stichworte) {
      if (w.length < 2) continue;
      final treffer = w.length <= 3 ? RegExp('(^|[^a-zäöüß])${RegExp.escape(w)}([^a-zäöüß]|\$)').hasMatch(t) : t.contains(w);
      if (treffer && w.length > laenge) {
        best = b;
        laenge = w.length;
      }
    }
  }
  return best;
}
