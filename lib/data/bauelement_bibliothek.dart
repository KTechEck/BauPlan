import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/bauelemente.dart';
import 'project_store.dart';

/// Bauelemente-Bibliothek dieses PCs (JSON-Datei) mit Datenblättern.
/// Verwendete Elemente werden zusätzlich ins Projekt kopiert
/// (Projekteinstellung `bauelemente`), damit Projekte vollständig bleiben.
class BauelementBibliothek {
  BauelementBibliothek(this.ordner) {
    _laden();
  }

  final Directory ordner;
  final List<Bauelement> _liste = [];

  File get _datei => File(p.join(ordner.path, 'bibliothek.json'));
  File get _geloeschtDatei => File(p.join(ordner.path, 'grundbestand_geloescht.json'));
  Directory get datenblattOrdner => Directory(p.join(ordner.path, 'datenblaetter'));

  List<Bauelement> get alle => List.unmodifiable(_liste);

  List<Bauelement> inKategorie(BauelementKategorie k) => [for (final e in _liste) if (e.kategorie == k) e]..sort((a, b) => a.anzeige.compareTo(b.anzeige));

  Bauelement? element(String? id) => id == null ? null : _liste.where((e) => e.id == id).firstOrNull;

  void _laden() {
    if (!_datei.existsSync()) {
      _liste.addAll([...beispielElemente(), ...materialBeispiele()]);
      _speichern();
      return;
    }
    try {
      final l = jsonDecode(_datei.readAsStringSync()) as List;
      _liste.addAll([for (final m in l) Bauelement.ausJson(Map<String, dynamic>.from(m as Map))]);
      // neue Einträge der Grundbibliothek nachtragen – außer was der Nutzer gelöscht hat
      final weg = _geloescht();
      final da = {for (final e in _liste) e.id};
      final neu = [for (final e in [...beispielElemente(), ...materialBeispiele()]) if (!da.contains(e.id) && !weg.contains(e.id)) e];
      if (neu.isNotEmpty) {
        _liste.addAll(neu);
        _speichern();
      }
    } catch (_) {
      // beschädigt: Sicherung behalten, leer weiter
      _datei.copySync('${_datei.path}.defekt');
    }
  }

  void _speichern() {
    ordner.createSync(recursive: true);
    _datei.writeAsStringSync(const JsonEncoder.withIndent(' ').convert([for (final e in _liste) e.toJson()]));
  }

  String neueId() => 'be-${DateTime.now().microsecondsSinceEpoch}';

  void speichern(Bauelement e) {
    final i = _liste.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      _liste[i] = e;
    } else {
      _liste.add(e);
    }
    _speichern();
  }

  Set<String> _geloescht() {
    try {
      return {for (final x in jsonDecode(_geloeschtDatei.readAsStringSync()) as List) '$x'};
    } catch (_) {
      return {};
    }
  }

  void loeschen(String id) {
    _liste.removeWhere((e) => e.id == id);
    _speichern();
    // Grundbestand: merken, damit er nicht wiederkommt
    if (id.startsWith('bsp-')) {
      _geloeschtDatei.writeAsStringSync(jsonEncode([..._geloescht(), id]));
    }
  }

  /// Gelöschte Einträge der Grundbibliothek wiederherstellen.
  int grundbestandWiederherstellen() {
    final da = {for (final e in _liste) e.id};
    final neu = [for (final e in [...beispielElemente(), ...materialBeispiele()]) if (!da.contains(e.id)) e];
    _liste.addAll(neu);
    _speichern();
    if (_geloeschtDatei.existsSync()) _geloeschtDatei.deleteSync();
    return neu.length;
  }

  /// Datenblatt in die Bibliothek kopieren; gibt den Dateinamen zurück.
  String datenblattAblegen(File quelle, String elementId) {
    datenblattOrdner.createSync(recursive: true);
    final name = '${elementId}_${p.basename(quelle.path)}';
    quelle.copySync(p.join(datenblattOrdner.path, name));
    return name;
  }

  File? datenblattDatei(Bauelement e) => e.datenblatt == null ? null : File(p.join(datenblattOrdner.path, e.datenblatt!));

  /// Element im Projekt ablegen (Kopie) und zurückgeben.
  static void insProjekt(ProjectStore store, Bauelement e) {
    final m = Map<String, dynamic>.from(store.einstellung<Map>('bauelemente') ?? const {});
    m[e.id] = e.toJson();
    store.einstellungSetzen('bauelemente', m);
  }

  /// Element aus Projekt (bevorzugt) oder Bibliothek.
  Bauelement? fuerProjekt(ProjectStore store, String? id) {
    if (id == null) return null;
    final m = store.einstellung<Map>('bauelemente')?[id];
    if (m != null) return Bauelement.ausJson(Map<String, dynamic>.from(m as Map));
    return element(id);
  }

  /// Alle Elemente einer Kategorie aus Bibliothek und Projekt (ohne Doppelte).
  List<Bauelement> auswahl(ProjectStore? store, BauelementKategorie k) {
    final l = inKategorie(k);
    final ids = {for (final e in l) e.id};
    final projekt = store?.einstellung<Map>('bauelemente') ?? const {};
    for (final m in projekt.values) {
      final e = Bauelement.ausJson(Map<String, dynamic>.from(m as Map));
      if (e.kategorie == k && !ids.contains(e.id)) l.add(e);
    }
    return l;
  }
}

/// Startbestand, damit man sieht, wie Einträge aussehen (frei änderbar).
List<Bauelement> beispielElemente() => [
      Bauelement(id: 'bsp-fenster-kunststoff-3fach', kategorie: BauelementKategorie.fenster, name: 'Kunststofffenster 82 mm, 3-fach (Beispiel)', daten: {
        'rahmenmaterial': 'Kunststoff',
        'bautiefe': 82,
        'ansichtsbreite': 117,
        'fluegelart': 'Dreh-Kipp',
        'verglasung': '3-fach',
        'glasaufbau': '4/16/4/16/4 Ar',
        'glasdicke': 44,
        'uw': 0.8,
        'ug': 0.6,
        'uf': 1.0,
        'psi_g': 0.04,
        'g_wert': 0.5,
        'rw': 34,
      }),
      Bauelement(id: 'bsp-fenster-holzalu', kategorie: BauelementKategorie.fenster, name: 'Holz-Alu-Fenster 88 mm, 3-fach (Beispiel)', daten: {
        'rahmenmaterial': 'Holz-Alu',
        'bautiefe': 88,
        'ansichtsbreite': 120,
        'verglasung': '3-fach',
        'uw': 0.75,
        'ug': 0.5,
        'uf': 1.1,
        'g_wert': 0.5,
      }),
      Bauelement(id: 'bsp-haustuer', kategorie: BauelementKategorie.tuer, name: 'Haustür Aluminium 90 mm (Beispiel)', daten: {
        'tuerart': 'Haustür',
        'rahmenmaterial': 'Aluminium',
        'blattdicke': 90,
        'bautiefe': 90,
        'ud': 0.8,
        'rc': 'RC2',
      }),
      Bauelement(id: 'bsp-innentuer', kategorie: BauelementKategorie.tuer, name: 'Innentür Röhrenspan mit Umfassungszarge (Beispiel)', daten: {
        'tuerart': 'Innentür',
        'rahmenmaterial': 'Holzwerkstoff',
        'blattdicke': 40,
        'zarge': 'Umfassungszarge',
        'klimaklasse': 'I',
      }),
      Bauelement(id: 'bsp-vorbaurollladen', kategorie: BauelementKategorie.sonnenschutz, name: 'Vorbaurollladen 165 mm, Motor (Beispiel)', daten: {
        'system': 'Vorbaurollladen',
        'antrieb': 'Motor 230 V',
        'leistung': 110,
        'kastenhoehe': 165,
        'kastentiefe': 165,
        'fuehrung_breite': 53,
        'fuehrung_tiefe': 22,
        'behang': 'Alu 37 mm ausgeschäumt',
        'fc': 0.3,
      }),
      Bauelement(id: 'bsp-aufsatzrollladen', kategorie: BauelementKategorie.sonnenschutz, name: 'Aufsatzrollladen auf Fensterrahmen (Beispiel)', daten: {
        'system': 'Aufsatzrollladen',
        'antrieb': 'Motor KNX',
        'kastenhoehe': 210,
        'kastentiefe': 82,
        'usb': 0.85,
        'psi_kasten': 0.04,
        'fc': 0.3,
      }),
      Bauelement(id: 'bsp-raffstore', kategorie: BauelementKategorie.sonnenschutz, name: 'Raffstore 80 mm Lamelle (Beispiel)', daten: {
        'system': 'Raffstore / Außenjalousie',
        'antrieb': 'Motor 230 V',
        'kastenhoehe': 300,
        'kastentiefe': 140,
        'behang': 'Lamelle 80 mm, randgebördelt',
        'fc': 0.25,
      }),
      Bauelement(id: 'bsp-ls-b16', kategorie: BauelementKategorie.schrankgeraet, name: 'Leitungsschutzschalter B16 1-polig (Beispiel)', daten: {
        'geraeteart': 'ls',
        'te': 1,
        'pole': 1,
        'nennstrom': 16,
        'charakteristik': 'B',
        'schaltvermoegen': 6,
      }),
      Bauelement(id: 'bsp-rcd-40', kategorie: BauelementKategorie.schrankgeraet, name: 'FI-Schutzschalter 40 A 30 mA 4-polig Typ A (Beispiel)', daten: {
        'geraeteart': 'rcd',
        'te': 4,
        'pole': 4,
        'nennstrom': 40,
        'fehlerstrom': 30,
        'rcd_typ': 'A',
      }),
      Bauelement(id: 'bsp-knx-schaltaktor', kategorie: BauelementKategorie.schrankgeraet, name: 'KNX-Schaltaktor 8fach 16 A (Beispiel)', daten: {
        'geraeteart': 'knx',
        'te': 4,
        'kanaele': 8,
        'aktortyp': 'Schalt',
        'strom_kanal': 16,
        'busstrom': 10,
      }),
      Bauelement(id: 'bsp-steckdose', kategorie: BauelementKategorie.elektro, name: 'SCHUKO-Steckdose 1fach (Beispiel)', daten: {
        'typ': 'Steckdose',
        'fach': 1,
        'montage': 'Unterputz',
        'dosentiefe': 61,
        'ip': 'IP20',
        'nennstrom': 16,
      }),
      Bauelement(id: 'bsp-wp-innen', kategorie: BauelementKategorie.technik, name: 'Wärmepumpe Innengerät mit Speicher (Beispiel)', daten: {
        'technikart': 'Wärmepumpe Innengerät',
        'breite': 600,
        'tiefe': 680,
        'hoehe': 1900,
        'gewicht': 160,
        'freiraum_vorne': 700,
        'freiraum_seite': 100,
        'leistung_kw': 8,
        'anschluss': '400 V',
        'volumen': 200,
      }),
      Bauelement(id: 'bsp-hk-22', kategorie: BauelementKategorie.heizkoerper, name: 'Kompaktheizkörper Typ 22 600/1000 (Beispiel)', daten: {
        'hk_art': 'Kompaktheizkörper',
        'hk_typ': '22',
        'bauhoehe': 600,
        'baulaenge': 1000,
        'bautiefe': 100,
        'q_norm': 1653,
        'exponent': 1.33,
      }),
    ];

/// Material-Startbestand (frei änderbar): Dämmstoffe, Fugen, Leitungen, Rohre, Dosen.
List<Bauelement> materialBeispiele() {
  Bauelement m(String id, BauelementKategorie k, String name, Map<String, dynamic> d) =>
      Bauelement(id: 'bsp-mat-$id', kategorie: k, name: name, daten: d);
  return [
    m('xps20', BauelementKategorie.daemmstoff, 'XPS-Platte 20 mm (Styrodur)', {'daemmart': 'XPS (Styrodur)', 'lambda': 0.033, 'dicke': 20, 'brandklasse': 'E', 'format': '1250 × 600 mm', 'einheit': 'Platte'}),
    m('xps40', BauelementKategorie.daemmstoff, 'XPS-Platte 40 mm (Styrodur)', {'daemmart': 'XPS (Styrodur)', 'lambda': 0.034, 'dicke': 40, 'brandklasse': 'E', 'einheit': 'Platte'}),
    m('eps140', BauelementKategorie.daemmstoff, 'EPS-Fassadendämmplatte WLS 035, 140 mm', {'daemmart': 'EPS (Styropor)', 'lambda': 0.035, 'dicke': 140, 'einheit': 'm²'}),
    m('casi30', BauelementKategorie.daemmstoff, 'Kalziumsilikatplatte 30 mm (Innenlaibung)', {'daemmart': 'Kalziumsilikat', 'lambda': 0.06, 'dicke': 30, 'brandklasse': 'A1', 'einheit': 'Platte'}),
    m('pir30', BauelementKategorie.daemmstoff, 'PIR-Laibungsplatte 30 mm', {'daemmart': 'PUR/PIR', 'lambda': 0.026, 'dicke': 30, 'einheit': 'Platte'}),
    m('kompri', BauelementKategorie.dichtstoff, 'Kompriband 600 Pa, 10–20 mm', {'dichtart': 'Kompriband (vorkomprimiert)', 'lambda': 0.048, 'fuge_von': 10, 'fuge_bis': 20, 'schlagregen': 600, 'einheit': 'Rolle'}),
    m('3e', BauelementKategorie.dichtstoff, 'Multifunktionsband 3E', {'dichtart': 'Multifunktionsband (3E)', 'lambda': 0.048, 'fuge_von': 8, 'fuge_bis': 18, 'einheit': 'Rolle'}),
    m('pu', BauelementKategorie.dichtstoff, 'PU-Montageschaum (Fensterbau)', {'dichtart': 'PU-Montageschaum', 'lambda': 0.035, 'einheit': 'Kartusche'}),
    m('folie_i', BauelementKategorie.dichtstoff, 'Fensteranschlussfolie innen', {'dichtart': 'Fensterfolie innen (luftdicht)', 'sd': 20, 'einheit': 'Rolle'}),
    m('nym315', BauelementKategorie.kabel, 'NYM-J 3×1,5 mm²', {'kabeltyp': 'NYM-J', 'adern': 3, 'querschnitt': 1.5, 'aussendurchmesser': 8.5, 'einheit': 'm', 'gebinde': 'Ring 100 m'}),
    m('nym325', BauelementKategorie.kabel, 'NYM-J 3×2,5 mm²', {'kabeltyp': 'NYM-J', 'adern': 3, 'querschnitt': 2.5, 'aussendurchmesser': 9.5, 'einheit': 'm'}),
    m('nym525', BauelementKategorie.kabel, 'NYM-J 5×2,5 mm²', {'kabeltyp': 'NYM-J', 'adern': 5, 'querschnitt': 2.5, 'aussendurchmesser': 11, 'einheit': 'm'}),
    m('knx', BauelementKategorie.kabel, 'KNX-Busleitung J-Y(St)Y 2×2×0,8', {'kabeltyp': 'J-Y(St)Y', 'adern': 4, 'querschnitt': 0.5, 'aussendurchmesser': 5.5, 'farbe': 'grün', 'einheit': 'm'}),
    m('cat7', BauelementKategorie.kabel, 'Netzwerkkabel Cat.7 S/FTP', {'kabeltyp': 'Cat.7', 'adern': 8, 'aussendurchmesser': 7.5, 'einheit': 'm'}),
    m('m20', BauelementKategorie.rohr, 'Leerrohr flexibel M20', {'rohrart': 'Leerrohr flexibel', 'nennweite': 'M20', 'aussendurchmesser': 20, 'innendurchmesser': 14.1, 'druckfest': '320 N (mittel)', 'halogenfrei': true, 'einheit': 'm'}),
    m('m25', BauelementKategorie.rohr, 'Leerrohr flexibel M25', {'rohrart': 'Leerrohr flexibel', 'nennweite': 'M25', 'aussendurchmesser': 25, 'innendurchmesser': 18.3, 'einheit': 'm'}),
    m('m32', BauelementKategorie.rohr, 'Leerrohr flexibel M32', {'rohrart': 'Leerrohr flexibel', 'nennweite': 'M32', 'aussendurchmesser': 32, 'innendurchmesser': 24.3, 'einheit': 'm'}),
    m('pex16', BauelementKategorie.rohr, 'PE-Xa Heizrohr 16×2', {'rohrart': 'PE-Xa Heizrohr', 'nennweite': '16×2', 'aussendurchmesser': 16, 'innendurchmesser': 12, 'einheit': 'm'}),
    m('up', BauelementKategorie.dose, 'Unterputz-Gerätedose 60 mm, 45 mm tief', {'dosenart': 'Unterputz-Gerätedose', 'durchmesser': 60, 'tiefe': 45, 'bohrung': 68, 'einfuehrungen': 'M20', 'einheit': 'Stk'}),
    m('up_tief', BauelementKategorie.dose, 'Geräteverbindungsdose tief 61 mm', {'dosenart': 'Unterputz-Geräteverbindungsdose (tief)', 'durchmesser': 60, 'tiefe': 61, 'bohrung': 68, 'einfuehrungen': 'M25', 'einheit': 'Stk'}),
    m('hw', BauelementKategorie.dose, 'Hohlwanddose 68 mm, 47 mm tief', {'dosenart': 'Hohlwanddose', 'durchmesser': 68, 'tiefe': 47, 'bohrung': 68, 'einheit': 'Stk'}),
    m('hw_e', BauelementKategorie.dose, 'Hohlwand-Elektronikdose 61 mm tief', {'dosenart': 'Hohlwand-Elektronikdose', 'durchmesser': 68, 'tiefe': 61, 'bohrung': 68, 'einheit': 'Stk'}),
    m('up_elektronik', BauelementKategorie.dose, 'Elektronikdose UP 60 mm, 61 mm tief, Trennsteg', {'dosenart': 'Elektronikdose UP (tief, mit Trennsteg)', 'durchmesser': 60, 'tiefe': 61, 'bohrung': 68, 'einfuehrungen': 'M25', 'einheit': 'Stk'}),
    m('up_doppel', BauelementKategorie.dose, 'Doppeldose UP 2fach (Achsabstand 71 mm)', {'dosenart': 'Doppeldose / Gerätedose 2fach', 'durchmesser': 60, 'tiefe': 47, 'bohrung': 68, 'einheit': 'Stk'}),
    m('up_netz', BauelementKategorie.dose, 'Datendose UP 60 mm tief (Netzwerk)', {'dosenart': 'Netzwerk-/Datendose UP', 'durchmesser': 60, 'tiefe': 61, 'bohrung': 68, 'einfuehrungen': 'M25', 'einheit': 'Stk'}),
    m('hw_abzweig', BauelementKategorie.dose, 'Hohlwand-Abzweigdose 74 mm', {'dosenart': 'Hohlwand-Abzweigdose', 'durchmesser': 74, 'tiefe': 47, 'bohrung': 74, 'einheit': 'Stk'}),
    m('beton', BauelementKategorie.dose, 'Betondose 60 mm, 68 mm tief', {'dosenart': 'Betondose', 'durchmesser': 60, 'tiefe': 68, 'einheit': 'Stk'}),
    m('luftdicht', BauelementKategorie.dose, 'Luftdichte Gerätedose 60 mm', {'dosenart': 'Dämmstoffdose (luftdicht)', 'durchmesser': 60, 'tiefe': 47, 'bohrung': 68, 'luftdicht': true, 'einheit': 'Stk'}),
    m('erhoehung10', BauelementKategorie.dose, 'Dosenerhöhung 10–30 mm (Fliesen/Dämmung)', {'dosenart': 'Dosenerhöhung / Ausgleichsring', 'durchmesser': 60, 'tiefe': 30, 'einheit': 'Stk'}),
    m('systemplatte', BauelementKategorie.daemmstoff, 'FBH-Tackerplatte EPS 30-2 mm (WLS 040)', {'daemmart': 'Systemplatte FBH (Noppe/Tacker)', 'lambda': 0.04, 'dicke': 30, 'einheit': 'm²'}),
    m('randstreifen', BauelementKategorie.daemmstoff, 'Randdämmstreifen PE 8×150 mm mit Folienlasche', {'daemmart': 'Randdämmstreifen (PE)', 'dicke': 8, 'einheit': 'm'}),
    m('pert16', BauelementKategorie.rohr, 'PE-RT Heizrohr 16×2 mit Sauerstoffsperre', {'rohrart': 'PE-Xa Heizrohr', 'nennweite': '16×2', 'aussendurchmesser': 16, 'innendurchmesser': 12, 'einheit': 'm'}),
    m('mv16', BauelementKategorie.rohr, 'Mehrschichtverbundrohr 16×2', {'rohrart': 'Mehrschichtverbundrohr', 'nennweite': '16×2', 'aussendurchmesser': 16, 'innendurchmesser': 12, 'einheit': 'm'}),
    m('tacker', BauelementKategorie.verbinder, 'Tackernadeln für Heizrohr 14–17 mm', {'verbinderart': 'Rohrhalter / Abstandsschelle', 'einheit': 'Stk'}),
    m('tiefgrund', BauelementKategorie.baustoff, 'Tiefengrund LF (Gebinde 10 l)', {'stoffart': 'Grundierung', 'verbrauch_m2': 0.1, 'einheit': 'l'}),
    m('dispersion', BauelementKategorie.baustoff, 'Dispersionsfarbe innen weiß, Klasse 2', {'stoffart': 'Farbe/Anstrich', 'verbrauch_m2': 0.15, 'einheit': 'l'}),
    m('dichtschlaemme', BauelementKategorie.baustoff, 'Flexible Dichtschlämme 2K', {'stoffart': 'Dichtschlämme', 'verbrauch_m2': 1.5, 'einheit': 'kg'}),
    m('fliesenkleber', BauelementKategorie.baustoff, 'Flexkleber C2 TE S1', {'stoffart': 'Mörtel/Kleber', 'verbrauch_m2': 3.0, 'einheit': 'kg'}),
    m('wdvs_kleber', BauelementKategorie.baustoff, 'WDVS Klebe- und Armierungsmörtel', {'stoffart': 'WDVS-Kleber/Armierung', 'verbrauch_m2': 5.0, 'einheit': 'kg'}),
    m('fugenmoertel', BauelementKategorie.baustoff, 'Flexfugenmörtel grau', {'stoffart': 'Fugenmörtel', 'verbrauch_m2': 0.4, 'einheit': 'kg'}),
    m('klemmring16', BauelementKategorie.verbinder, 'Klemmringverschraubung 16×2 × 3/4" Eurokonus', {'verbinderart': 'Klemmringverschraubung', 'einheit': 'Stk'}),
  ];
}
