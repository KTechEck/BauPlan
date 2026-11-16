import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../zwei_finger.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/aufmass.dart';
import '../../core/wandaufbau.dart';
import '../../data/sync.dart';
import '../../core/brandschutz.dart';
import '../../core/sparren.dart';
import '../../core/dach.dart' show wohnflaeche;
import '../../core/dxf.dart';
import '../../core/raumerkennung.dart';
import '../../core/wandmasse.dart';
import '../../data/bauelement_bibliothek.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';
import '../../state/app_state.dart';
import '../bibliothek.dart';
import '../dialogs.dart';
import '../decke/decke_page.dart';
import '../wandansicht/wandansicht_page.dart';
import '../project_tree.dart';
import '../tastenkuerzel.dart';
import '../../core/bauelemente.dart';
import '../bauteile/bauelement_wahl.dart';
import '../widgets.dart';
import 'aufmass_dialog.dart';
import 'sparren_dialog.dart';
import 'gelaende_dialog.dart';
import 'aufbau_dialog.dart';
import '../bauphysik/sonne_dialog.dart';
import 'dach_dialog.dart';
import 'geschoss_3d.dart';
import 'einbaudetail_page.dart';
import 'floorplan_painter.dart';
import 'statik.dart';
import 'fassade_dialog.dart';
import 'keller_dialog.dart';
import '../raumbild_dialog.dart';
import '../../core/pdf_bild.dart';
import '../../core/gebaeude.dart';
import '../../core/leitung_wand.dart' show geschossStapel;

enum Werkzeug { auswahl, wand, raum, oeffnung, mass, winkel }

/// Grundriss-Editor: Wände (frei oder mit Wandtyp) zeichnen, auswählen,
/// ändern, löschen; Räume aus geschlossenen Wandzügen anlegen.
class FloorplanPage extends StatefulWidget {
  const FloorplanPage({super.key, required this.state});
  final AppState state;

  @override
  State<FloorplanPage> createState() => _FloorplanPageState();
}

/// Alles, was sich nur bei Datenänderungen neu berechnen muss.
class _Plan {
  _Plan({
    required this.waende,
    required this.flaechen,
    required this.raeume,
    required this.raumZuFlaeche,
    required this.typen,
    required this.materialien,
    required this.schichten,
    required this.achsen,
    required this.flanken,
    this.raumStuecke = const {},
    required this.umrisse,
    required this.bemassungen,
    required this.winkelmasse,
    required this.vorlage,
    required this.oeffnungen,
    this.aufbau = const [],
  });

  /// Seitenaufbau als Bänder (Kern + Aufbau je Seite).
  final List<Aufbauband> aufbau;

  final List<WandAchse> achsen; // gleiche Reihenfolge wie waende
  final Map<String, (double, double)> flanken; // Seitenlängen je Wand
  final Map<String, List<(double, double, double, String)>> raumStuecke; // lichte Messstrecken je Raum
  final Map<String, List<Offset>> umrisse; // verschnittene Wandumrisse
  final List<Bemassung> bemassungen;
  final List<Winkelmass> winkelmasse;
  final Planvorlage? vorlage;
  final List<Oeffnung> oeffnungen;

  final List<Wand> waende;
  final List<ErkannterRaum> flaechen;
  final List<Raum> raeume;
  final Map<String, ErkannterRaum> raumZuFlaeche; // Raum-ID → aktuelle Fläche
  final List<Wandtyp> typen;
  final Map<String, Baustoff> materialien;
  final Map<String, List<SchichtBild>> schichten;

  List<Raum> raeumeIn(ErkannterRaum f) => [
        for (final r in raeume)
          if (identical(raumZuFlaeche[r.id], f)) r
      ];
}

class _FloorplanPageState extends State<FloorplanPage> {
  final _eigFenster = EigenschaftenFenster();
  final _doppel = Doppelklick();
  static const _dicken = [115, 175, 240, 300, 365, 425];
  static const _raster = [10, 50, 100, 250];

  final _fokus = FocusNode();
  double _massstab = 0.08; // Pixel pro mm
  Offset _verschiebung = const Offset(120, 120);
  // zuletzt benutztes Werkzeug bleibt beim Wechsel zwischen Modulen/Fenstern erhalten
  // (je Projekt; neues Projekt beginnt mit dem Wand-Werkzeug)
  static Werkzeug _letztesWerkzeug = Werkzeug.wand;
  static String? _werkzeugProjekt;
  Werkzeug get _werkzeug {
    if (_werkzeugProjekt != _s.store?.ordner) {
      _werkzeugProjekt = _s.store?.ordner;
      _letztesWerkzeug = Werkzeug.wand;
    }
    return _letztesWerkzeug;
  }

  set _werkzeug(Werkzeug w) => _letztesWerkzeug = w;
  int _massAusrichtung = 0; // 0 direkt, 1 waagerecht, 2 senkrecht, 3 parallel zur Wand
  bool _seiteZu = false; // Eigenschaften rechts eingeklappt
  late int _wandDicke = (widget.state.settings.darstellung['wand_dicke'] as num?)?.toInt() ?? 240;
  String? _wandtypId; // null = freie Dicke
  late int _rasterMm = (widget.state.settings.darstellung['raster_mm'] as num?)?.toInt() ?? 50;
  WandZustand _zustand = WandZustand.bestand;

  Offset? _kettenStart;
  Offset? _maus;
  Set<String> _auswahl = {}; // gewählte Wände

  // Auswahlwerkzeug: Ziehen verschiebt die Auswahl oder zieht einen Rahmen auf.
  Offset? _ziehStart; // Weltpunkt beim Drücken
  bool _verschiebtAuswahl = false;
  Offset _versatz = Offset.zero; // Vorschau beim Verschieben (mm, auf Raster)
  Rect? _rahmen; // Auswahlrahmen (Welt)
  bool _ansichtZiehen = false; // Leertaste + linke Maustaste

  Offset? _zeiger; // letzte Zeigerposition auf dem Bildschirm
  Timer? _randTimer; // schiebt die Ansicht, solange der Zeiger am Rand steht
  double _pzSkala = 1; // Touchpad-Zoom
  ErkannterRaum? _freieAuswahl; // gewählte Fläche ohne Raum
  int _winkelFang = 0; // 0 = frei (mit Fang auf waagerecht/senkrecht), sonst Schritt in Grad
  MassBezug _massBezug = MassBezug.achse; // wie eingetippte Längen gemeint sind
  bool _eckpunktModus = false; // Wandlänge ändern: nur Eckpunkt verschieben (Winkel ändert sich)
  String? _parallelFuer; // Wand, die beim nächsten Klick parallel zur angeklickten Wand ausgerichtet wird
  int _form = 0; // Wand zeichnen: 0 Linienzug, 1 Rechteck (Raum)
  bool _bodenplatte = false; // Raumwerkzeug: Balkon/Terrasse als Bodenplatte zeichnen
  final List<Offset> _plattePunkte = [];
  int _winkelBezug = 1; // Winkelmaß am 0 Achsscheitel, 1 Innenecke, 2 Außenecke
  bool _bemassungenSichtbar = true; // eigene Bemaßungen und Winkel zeigen (Projekteinstellung)
  String? _fangText; // was gerade gefangen wird (Anzeige am Cursor)
  (Offset, Offset)? _fangLinie; // gestrichelte Hilfslinie zum Fang (Flucht/Verlängerung)
  Wand? _fangWand; // Wand unter dem Fangpunkt
  Offset? _massA, _massB; // Bemaßung im Entstehen
  String? _massAuswahl; // gewählte Bemaßung
  String? _winkelAuswahl; // gewähltes Winkelmaß
  String? _winkelErste; // erste Wand beim Winkelmessen
  final _massWertCtrl = TextEditingController();
  final _massWertFokus = FocusNode();
  String? _massWertFuer;
  final _winkelWertCtrl = TextEditingController();
  final _winkelWertFokus = FocusNode();
  String? _winkelWertFuer;
  bool _eckenVerbinden = true; // Projektvorgabe (gespeichert)

  /// Geschoss darunter im Plan einblenden (Darstellung, je Benutzer).
  bool get _unterlage => _s.settings.darstellung['geschoss_darunter'] == true;

  /// Geschoss direkt unter dem aktuellen (nach Kürzel/Höhe sortiert) oder null.
  Geschoss? _geschossDarunter() {
    final store = _s.store!;
    final gid = _s.geschossId;
    if (gid == null) return null;
    final g = store.geschoss(gid);
    if (g == null) return null;
    final stapel = geschossStapel(store.geschosse(g.gebaeudeId));
    final i = stapel.indexWhere((x) => x.id == gid);
    return i > 0 ? stapel[i - 1] : null;
  }

  /// Verknüpfung oben → unten (Wand steht auf Wand), gelöste Paare ausgenommen.
  Map<String, String> _verknuepfungen(List<Wand> oben, Geschoss unten) {
    final store = _s.store!;
    final geloest = {for (final e in (store.einstellung<List>('geschoss_verknuepfung_geloest') ?? const [])) '$e'};
    WandAchse2 achse(Wand w) => (id: w.id, a: Punkt(w.x1.toDouble(), w.y1.toDouble()), b: Punkt(w.x2.toDouble(), w.y2.toDouble()), dicke: w.dicke);
    return wandVerknuepfungen([for (final w in oben) achse(w)], [for (final w in store.waende(unten.id)) achse(w)], geloest: geloest);
  }

  /// Hinweise zu Sondertüren: Tasche braucht freie Wand ohne Leitungen, Schiebetür Platz zum Schieben.
  List<Widget> _tuerHinweise(Oeffnung o, Wand? w) {
    final art = o.eigenschaften['tuerart'] as String? ?? 'dreh';
    if (w == null || (art != 'tasche' && art != 'schiebe')) return const [];
    final h = <String>[];
    final weg = o.bandRechts ? o.breite : -o.breite;
    final von = math.min(o.abstand + (o.bandRechts ? o.breite : 0), o.abstand + (o.bandRechts ? o.breite : 0) + weg).toDouble();
    final bis = math.max(o.abstand + (o.bandRechts ? o.breite : 0), o.abstand + (o.bandRechts ? o.breite : 0) + weg).toDouble();
    if (von < 0 || bis > w.laenge) h.add('Zu wenig Wand neben der Öffnung – Blatt braucht ${mmText(o.breite)} Platz (Anschlag wechseln?).');
    final andere = (_plan?.oeffnungen ?? const <Oeffnung>[]).where((x) => x.id != o.id && x.wandId == w.id && x.abstand < bis && x.abstand + x.breite > von);
    if (andere.isNotEmpty) h.add('Im Schiebebereich liegt eine weitere Öffnung.');
    if (art == 'tasche') {
      h.add('Taschenwand: im Taschenbereich keine Dosen, Leitungen oder Dübel (Wanddicke ≥ 100 mm für Schiebetürkasten).');
      if (w.dicke < 100) h.add('Wand nur ${w.dicke} mm dick – Schiebetürkasten braucht meist 100–125 mm.');
    }
    return [for (final t in h) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $t', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))))];
  }

  /// Schwelle/Höhensprung: Fertigfußböden der beiden Räume an der Tür.
  List<Widget> _schwellenHinweise(Oeffnung o, Wand? w) {
    final store = _s.store!;
    final plan = _plan;
    if (w == null || plan == null || w.laenge < 1) return const [];
    final g = store.geschoss(w.geschossId);
    if (g == null) return const [];
    final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge;
    final t = o.abstand + o.breite / 2;
    final mx = w.x1 + ux * t, my = w.y1 + uy * t;
    final d = w.dicke / 2 + 80;
    Raum? raumAn(double x, double y) => store.raeume(w.geschossId).where((r) => r.umriss != null && punktInPolygon(Punkt(x, y), r.umriss!)).firstOrNull;
    final a = raumAn(mx - uy * d, my + ux * d), b = raumAn(mx + uy * d, my - ux * d);
    int ffb(Raum? r) => r?.ffb ?? g.hoehen.ffb;
    final h = <String>[];
    final aussen = a == null || b == null || a.art != RaumArt.raum || b.art != RaumArt.raum;
    final diff = (ffb(a) - ffb(b)).abs();
    if (o.art == OeffnungsArt.balkontuer || (aussen && o.art == OeffnungsArt.tuer)) {
      h.add('Außentür/Balkontür: Abdichtung 150 mm über Belag hochführen (DIN 18531) oder barrierefrei ≤ 20 mm mit Rinne vor der Tür.');
    }
    if (diff > 0 && !aussen) {
      h.add('Höhensprung ${mmText(diff)} zwischen ${a.name} und ${b.name} – ${diff <= 20 ? 'Übergangsprofil/Anpassungsprofil' : (diff <= 40 ? 'Rampenprofil' : 'Stufe – Estrich anpassen oder Rampe')}.');
    }
    if (h.isEmpty) return const [];
    return [for (final x in h) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $x', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)))];
  }

  /// Statik-Helfer im Wandpanel: tragend, steht auf Wand darunter, Stürze über Öffnungen.
  List<Widget> _statikFelder(Wand w) {
    final store = _s.store!;
    final tragend = w.eigenschaften['tragend'] == true;
    final unten = _geschossDarunter();
    final plan = _plan;
    final verkn = unten == null || plan == null ? const <String, String>{} : _verknuepfungen(plan.waende, unten);
    final aufWand = verkn[w.id];
    final geloest = [for (final e in (store.einstellung<List>('geschoss_verknuepfung_geloest') ?? const [])) '$e'];
    final eigeneGeloest = geloest.where((e) => e.startsWith('${w.id}|')).toList();
    final oeff = [for (final o in plan?.oeffnungen ?? const <Oeffnung>[]) if (o.wandId == w.id && o.art != OeffnungsArt.nische) o];
    return [
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('tragende Wand'),
        subtitle: const Text('Statik-Helfer: Hinweise und Mappe für den Statiker, keine Berechnung', style: TextStyle(fontSize: 11)),
        value: tragend,
        onChanged: (v) {
          final alt = w.eigenschaften['tragend'];
          store.wandEigenschaftenSetzen(w.id, {'tragend': v ? true : null});
          _rueckgaengig.add(() => store.wandEigenschaftenSetzen(w.id, {'tragend': alt}));
          _s.geaendert();
        },
      ),
      if (unten != null)
        Row(children: [
          Icon(aufWand != null ? Icons.link : Icons.link_off, size: 16, color: BsFarben.textLeise),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              aufWand != null
                  ? 'steht auf einer Wand im ${unten.kuerzel} (automatisch erkannt)'
                  : eigeneGeloest.isNotEmpty
                      ? 'Verknüpfung zum ${unten.kuerzel} gelöst'
                      : 'keine Wand darunter im ${unten.kuerzel}${tragend ? ' – Lastabtragung klären!' : ''}',
              style: TextStyle(fontSize: 12, color: aufWand == null && tragend && eigeneGeloest.isEmpty ? const Color(0xFFB91C1C) : BsFarben.textLeise),
            ),
          ),
          if (aufWand != null)
            TextButton(
              onPressed: () {
                store.einstellungSetzen('geschoss_verknuepfung_geloest', [...geloest, '${w.id}|$aufWand']);
                _s.geaendert();
              },
              child: const Text('lösen'),
            ),
          if (eigeneGeloest.isNotEmpty)
            TextButton(
              onPressed: () {
                store.einstellungSetzen('geschoss_verknuepfung_geloest', [for (final e in geloest) if (!e.startsWith('${w.id}|')) e]);
                _s.geaendert();
              },
              child: const Text('wieder verknüpfen'),
            ),
        ]),
      if (tragend && oeff.isNotEmpty) ...[
        const SizedBox(height: 6),
        const Text('Öffnungen in der tragenden Wand (Richtwerte):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        for (final o in oeff)
          () {
            final r = sturzRichtwert(o.breite.toDouble(), wanddicke: w.dicke.toDouble());
            return Text('• ${o.art.label} ${mmText(o.breite)}: Sturz ≥ ${mmText(r.laenge)} (Auflager je ${mmText(r.auflager)}), ${r.art}',
                style: const TextStyle(fontSize: 12));
          }(),
      ],
    ];
  }
  bool? _neueVerbinden; // für neu gezeichnete Wände: null = Projektvorgabe
  int _abstandBezug = 0; // 0 Achse, 1 innen, 2 außen
  ui.Image? _vorlageBild;
  String? _vorlageDatei;
  int _vorlageModus = 0; // 0 aus, 1 kalibrieren, 2 verschieben
  List<Offset> _kalibrierPunkte = [];
  Offset _vorlageVersatz = Offset.zero;
  Offset? _vorlageZiehStart;
  OeffnungsArt _oeffnungArt = OeffnungsArt.tuer;
  int _oeffnungBreite = 885;
  String? _oeffnungAuswahl;
  (String, int, int, OeffnungsArt)? _oeffnungVorschau;
  Wand? _abstandWand; // offene Abstandseingabe für den Startpunkt
  bool _abstandVonA = true;
  final _abstandCtrl = TextEditingController();
  late final _abstandFokus = FocusNode(onKeyEvent: (n, e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _abstandAbbrechen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  });
  MassAnzeige _massVoreinstellung = MassAnzeige.innenAussen;

  // Länge einer gewählten Wand nachträglich ändern
  final _wandLaengeCtrl = TextEditingController();
  final _wandLaengeFokus = FocusNode();
  String? _wandLaengeFuer; // Wand + Modus, für die das Feld gefüllt ist
  bool _amAnfang = false; // Änderung am Anfang statt am Ende
  (String, DateTime)? _letzterWandKlick;

  // Maßeingabe beim Zeichnen (Tab springt hinein)
  final _laengeCtrl = TextEditingController();
  final _winkelCtrl = TextEditingController();
  late final _laengeFokus = FocusNode(onKeyEvent: (n, e) => _eingabeTaste(e, laenge: true));
  late final _winkelFokus = FocusNode(onKeyEvent: (n, e) => _eingabeTaste(e, laenge: false));
  String? _geschossBeiLetztemBuild;
  bool _eingepasst = false;
  Size _flaeche = Size.zero;

  _Plan? _plan;
  (int, String?)? _planStand;

  /// Rückgängig-Stapel: jede Aktion liefert ihre Umkehrung.
  final List<VoidCallback> _rueckgaengig = [];

  AppState get _s => widget.state;

  @override
  void dispose() {
    _randTimer?.cancel();
    _wandLaengeCtrl.dispose();
    _abstandCtrl.dispose();
    _massWertCtrl.dispose();
    _massWertFokus.dispose();
    _winkelWertCtrl.dispose();
    _winkelWertFokus.dispose();
    _abstandFokus.dispose();
    _wandLaengeFokus.dispose();
    _laengeCtrl.dispose();
    _winkelCtrl.dispose();
    _laengeFokus.dispose();
    _winkelFokus.dispose();
    _fokus.dispose();
    super.dispose();
  }

  _Plan _planLaden() {
    final stand = (_s.revision, _s.geschossId);
    final alt = _plan;
    if (alt != null && _planStand == stand) return alt;
    final store = _s.store!;
    final g = _s.geschossId;
    final waende = g == null ? <Wand>[] : store.waende(g);
    final flaechen = ProjectStore.erkenneAusWaenden([for (final w in waende) if (!w.teilhoch) w]);
    final raeume = g == null ? <Raum>[] : store.raeume(g);
    final zuordnung = <String, ErkannterRaum>{};
    for (final r in raeume) {
      final b = r.bezug;
      if (b == null) continue;
      final f = flaechen.where((f) => f.enthaelt(b)).firstOrNull;
      if (f != null) zuordnung[r.id] = f;
    }
    final materialien = {for (final m in store.materialien()) m.id: m};
    final typen = store.wandtypen();
    final achsen = [for (final w in waende) w.achse];
    _eckenVerbinden = store.einstellung<bool>('ecken_verbinden') ?? true;
    _winkelBezug = store.einstellung<int>('winkel_bezug') ?? 1;
    _bemassungenSichtbar = store.einstellung<bool>('bemassungen_sichtbar') ?? true;
    final mv = store.einstellung<String>('mass_anzeige');
    _massVoreinstellung = MassAnzeige.values.where((m) => m.name == mv).firstOrNull ?? MassAnzeige.innenAussen;
    final verbinden = [for (final w in waende) _verbindet(w)];
    final nachbarn = [
      for (var i = 0; i < waende.length; i++)
        if (verbinden[i] && !waende[i].istKante) achsen[i]
    ];
    final plan = _Plan(
      waende: waende,
      flaechen: flaechen,
      raeume: raeume,
      raumZuFlaeche: zuordnung,
      typen: typen,
      materialien: materialien,
      schichten: {
        for (final t in typen)
          t.id: [for (final s in t.schichten) (s.dicke, Color(materialien[s.materialId]?.farbe ?? 0xFFDDDDDD))],
      },
      achsen: achsen,
      aufbau: aufbauBaender(waende, verbindenStandard: store.einstellung<bool>('ecken_verbinden') ?? true, oeffnungen: g == null ? const [] : store.oeffnungen(g)),
      flanken: () {
        final roh = {
          for (var i = 0; i < waende.length; i++)
            waende[i].id: flankenLaengen(achsen[i], verbinden[i] ? nachbarn : [achsen[i]]),
        };
        // Fertigmaße: Wandverkleidung des Raums an beiden Enden abziehen
        if (store.einstellung<String>('massart') != 'fertig') return roh;
        final mm = wandMasse(waende, raeume, verbindenStandard: _eckenVerbinden);
        final seiten = verkleidungSeiten(store);
        final raumNach = {for (final r in raeume) r.id: r};
        double fertig(Wand w, bool links, double laenge) {
          final m = mm[w.id];
          final r = raumNach[links ? m?.raumLinks : m?.raumRechts];
          if (m == null || r == null) return laenge;
          final g = m.grenzen;
          final (a1, a2) = endAbzuege(waende, mm, seiten, w, links, links ? g.linksA : g.rechtsA, links ? g.linksB : g.rechtsB, r);
          return laenge - a1 - a2;
        }
        return {
          for (final w in waende)
            if (roh[w.id] != null) w.id: (fertig(w, true, roh[w.id]!.$1), fertig(w, false, roh[w.id]!.$2)),
        };
      }(),
      raumStuecke: () {
        // Wände an mehreren Räumen (oder nur teilweise an einem): je Raum seine lichte Strecke
        final mm = wandMasse(waende, raeume, verbindenStandard: _eckenVerbinden);
        final namen = {for (final r in raeume) r.id: r.name};
        final fertigModus = store.einstellung<String>('massart') == 'fertig';
        final seiten = verkleidungSeiten(store);
        final raumNach = {for (final r in raeume) r.id: r};
        final aus = <String, List<(double, double, double, String)>>{};
        for (final w in waende) {
          final m = mm[w.id];
          if (m == null) continue;
          final l = <(double, double, double, String)>[];
          for (final (seite, st, ta, tb, raum) in [
            (1.0, m.stueckeLinks, m.grenzen.linksA, m.grenzen.linksB, m.raumLinks),
            (-1.0, m.stueckeRechts, m.grenzen.rechtsA, m.grenzen.rechtsB, m.raumRechts),
          ]) {
            // Raumkante schon an einem anderen geraden Wandstück beschriftet: hier nichts
            if (st.isEmpty && raum != null) {
              l.add((0, 0, seite, ''));
              continue;
            }
            final teil = st.length > 1 || st.values.any((x) => (x.$1 - ta).abs() > 5 || (x.$2 - tb).abs() > 5);
            if (!teil) continue;
            for (final e in st.entries) {
              var (v1, v2) = (0, 0);
              if (fertigModus && raumNach[e.key] != null) (v1, v2) = endAbzuege(waende, mm, seiten, w, seite > 0, e.value.$1, e.value.$2, raumNach[e.key]!);
              l.add((e.value.$1 + v1, e.value.$2 - v2, seite, namen[e.key] ?? ''));
            }
          }
          if (l.isNotEmpty) aus[w.id] = l;
        }
        return aus;
      }(),
      bemassungen: g == null ? const [] : store.bemassungen(g),
      winkelmasse: g == null ? const [] : store.winkelmasse(g),
      vorlage: g == null ? null : store.planvorlage(g),
      oeffnungen: g == null ? const [] : store.oeffnungen(g),
      umrisse: {
        for (var i = 0; i < waende.length; i++)
          waende[i].id: [
            for (final p in wandUmriss(achsen[i], verbinden[i] ? nachbarn : [achsen[i]])) Offset(p.x, p.y)
          ],
      },
    );
    _plan = plan;
    _planStand = stand;
    return plan;
  }

  Wandtyp? get _gewaehlterTyp => _plan?.typen.where((t) => t.id == _wandtypId).firstOrNull;
  int get _zeichenDicke => _gewaehlterTyp?.dicke ?? _wandDicke;

  Offset _zuWelt(Offset bildschirm) => (bildschirm - _verschiebung) / _massstab;
  static Offset _o(Punkt p) => Offset(p.x, p.y);

  // ------------------------------------------------------------------ Fangen

  /// Fangen in dieser Reihenfolge: Wandende, Wandecke (Außen-/Innenkante),
  /// Wandmitte, Lot vom Kettenstart, auf der Wandachse (Abstand im Raster),
  /// sonst Raster mit Winkelfang. Setzt [_fangText] und [_fangWand] für
  /// die Anzeige und die Abstandseingabe.
  Offset _fangen(Offset welt, List<Wand> waende) {
    _fangText = null;
    _fangWand = null;
    _fangLinie = null;
    final radius = 10 / _massstab;
    final plan = _plan;
    final messen = _werkzeug == Werkzeug.mass;

    // 0. Gerade Verlängerung (180°) der Wand, an deren Ende die Kette beginnt:
    //    hat Vorrang vor dem Einrasten an Nachbarwänden (Umschalt schaltet ab).
    final kette = _kettenStart;
    if (!messen && kette != null && !HardwareKeyboard.instance.isShiftPressed) {
      final v = _verlaengerungsFang(welt, kette, waende, radius);
      if (v != null) return v;
    }

    Offset? naechster(Iterable<(Offset, String, double)> kandidaten) {
      Offset? treffer;
      var bester = double.infinity;
      for (final (p, text, fangradius) in kandidaten) {
        final d = (p - welt).distance;
        if (d < fangradius && d < bester) {
          bester = d;
          treffer = p;
          _fangText = text;
        }
      }
      return treffer;
    }

    Offset rund(Offset p) => Offset(p.dx.roundToDouble(), p.dy.roundToDouble());

    // 1. Wandenden – beim Zeichnen auch, wenn die Maus irgendwo im Endbereich
    //    der Wand steht; so docken Wände immer am Achsende an und verbinden sich.
    final ende = naechster([
      for (final w in waende)
        for (final p in [Offset(w.x1.toDouble(), w.y1.toDouble()), Offset(w.x2.toDouble(), w.y2.toDouble())])
          (p, 'Endpunkt', messen ? radius : math.max(radius, w.dicke * 0.8)),
    ]);
    if (ende != null) return ende;

    if (messen && plan != null) {
      // 2. Wandecken (Innen- und Außenkanten des verschnittenen Umrisses)
      final ecke = naechster([
        for (final w in waende)
          for (final p in plan.umrisse[w.id] ?? const <Offset>[]) (p, 'Wandecke', radius),
      ]);
      if (ecke != null) return rund(ecke);
      // 2b. Laibungen von Türen, Fenstern, Durchbrüchen
      final laibung = naechster([
        for (final o in plan.oeffnungen)
          if (plan.waende.where((w) => w.id == o.wandId).firstOrNull case final w?)
            for (final t in [o.abstand.toDouble(), (o.abstand + o.breite).toDouble()])
              for (final s in [-1.0, 1.0]) (_wandPunkt(w, t, s * w.dicke / 2), 'Laibung', radius),
      ]);
      if (laibung != null) return rund(laibung);
    }

    // 3. Wandmitte
    final mitte = naechster([
      for (final w in waende) (Offset((w.x1 + w.x2) / 2, (w.y1 + w.y2) / 2), 'Mitte', radius),
    ]);
    if (mitte != null) {
      _fangWandSetzen(waende, mitte);
      return rund(mitte);
    }

    // 3b. Schnittpunkt zweier Wandfluchten (verlängerte Achsen)
    if (!messen || _massA != null) {
      final schnitt = naechster([
        for (var i = 0; i < waende.length; i++)
          for (var j = i + 1; j < waende.length; j++)
            if (_achsenSchnitt(waende[i], waende[j]) case final s?) (s, 'Schnittpunkt Fluchten', radius),
      ]);
      if (schnitt != null) return rund(schnitt);
    }

    // 4. Lot vom Kettenstart auf eine Wand
    final start = _kettenStart ?? (messen ? _massA : null);
    if (start != null && _massB == null) {
      final lot = naechster([
        for (final w in waende)
          if (_lotFuss(start, w) case final f?) (f, 'Lot', radius),
      ]);
      if (lot != null) return rund(lot);
    }

    // 5. Auf der Wand: Achse (Zeichnen) oder Wandseite (Bemaßen), Abstand im Raster
    Wand? beste;
    var abstand = double.infinity;
    for (final w in waende) {
      final a = Offset(w.x1.toDouble(), w.y1.toDouble()), b = Offset(w.x2.toDouble(), w.y2.toDouble());
      final d = abstandZuStrecke(welt, a, b);
      if (d < math.max(radius, w.dicke / 2 + radius) && d < abstand) {
        abstand = d;
        beste = w;
      }
    }
    if (beste != null && (start == null || _winkelFang == 0 || messen)) {
      final w = beste;
      final a = Offset(w.x1.toDouble(), w.y1.toDouble());
      final u = (Offset(w.x2.toDouble(), w.y2.toDouble()) - a) / w.laenge;
      final quer = (welt - a).dx * u.dy - (welt - a).dy * u.dx; // >0: links der Richtung (Bildschirm)
      var t = (((welt - a).dx * u.dx + (welt - a).dy * u.dy) / _rasterMm).round() * _rasterMm.toDouble();
      t = t.clamp(0.0, w.laenge);
      if (!messen && (t < w.dicke || t > w.laenge - w.dicke)) {
        // dicht am Ende: ans Ende, nicht knapp davor (sonst steht die alte Wand über)
        final p = t < w.laenge / 2 ? a : Offset(w.x2.toDouble(), w.y2.toDouble());
        _fangText = 'Endpunkt';
        return p;
      }
      Offset p;
      if (messen && quer.abs() > w.dicke / 4) {
        p = a + u * t + Offset(u.dy, -u.dx) * (quer > 0 ? w.dicke / 2 : -w.dicke / 2);
        _fangText = 'Wandseite';
      } else {
        p = a + u * t;
        _fangText = 'auf Wand';
      }
      _fangWandSetzen(waende, a + u * t, wand: w);
      return rund(p);
    }

    // 6. Verlängerung einer Wandachse über ihr Ende hinaus
    Wand? fluchtWand;
    final flucht = naechster([
      for (final w in waende)
        if (_aufVerlaengerung(welt, w) case final f?) (f, 'Verlängerung Wand', radius),
    ]);
    if (flucht != null && (start == null || _winkelFang == 0)) {
      fluchtWand = waende.where((w) => _aufVerlaengerung(welt, w) == flucht).firstOrNull;
      if (fluchtWand != null) {
        final a = Offset(fluchtWand.x1.toDouble(), fluchtWand.y1.toDouble());
        final b = Offset(fluchtWand.x2.toDouble(), fluchtWand.y2.toDouble());
        _fangLinie = ((flucht - a).distance < (flucht - b).distance ? a : b, rund(flucht));
      }
      return rund(flucht);
    }

    return _rasterFang(welt);
  }

  /// Fang auf der geraden Verlängerung (180°) einer Wand, die am Kettenstart
  /// endet. Liegt auf der Flucht ein Wandende oder kreuzt sie eine Wandachse,
  /// rastet der Punkt dort ein, sonst im Raster entlang der Flucht.
  Offset? _verlaengerungsFang(Offset welt, Offset kette, List<Wand> waende, double radius) {
    Offset? u;
    Wand? basis;
    var besteQuer = double.infinity;
    double t = 0;
    for (final w in waende) {
      final a = Offset(w.x1.toDouble(), w.y1.toDouble()), b = Offset(w.x2.toDouble(), w.y2.toDouble());
      final Offset anderes;
      if ((a - kette).distance < 1) {
        anderes = b;
      } else if ((b - kette).distance < 1) {
        anderes = a;
      } else {
        continue;
      }
      final l = (kette - anderes).distance;
      if (l < 1) continue;
      final r = (kette - anderes) / l;
      final v = welt - kette;
      final tt = v.dx * r.dx + v.dy * r.dy;
      if (tt < radius) continue;
      final quer = (v.dx * r.dy - v.dy * r.dx).abs();
      // Fangbreite: mindestens 14 px, weiter draußen bis ~4°, höchstens 40 px
      final tol = math.max(14 / _massstab, math.min(tt * 0.07, 40 / _massstab));
      if (quer < tol && quer < besteQuer) {
        besteQuer = quer;
        u = r;
        basis = w;
        t = tt;
      }
    }
    if (u == null || basis == null) return null;
    final richtung = u;
    // Einrastziele auf der Flucht: Wandenden genau auf der Linie, Kreuzung mit Wandachsen
    double? ziel;
    String text = 'Verlängerung 180°';
    var bester = radius * 1.5;
    for (final w in waende) {
      if (w.id == basis.id) continue;
      final a = Offset(w.x1.toDouble(), w.y1.toDouble()), b = Offset(w.x2.toDouble(), w.y2.toDouble());
      for (final p in [a, b]) {
        final v = p - kette;
        final s = v.dx * richtung.dx + v.dy * richtung.dy;
        final q = (v.dx * richtung.dy - v.dy * richtung.dx).abs();
        if (s > 1 && q < 1 && (s - t).abs() < bester) {
          bester = (s - t).abs();
          ziel = s;
          text = 'Verlängerung 180° bis Wandende';
        }
      }
      // Schnitt der Flucht mit der Achse von w (innerhalb der Wand)
      final d = b - a;
      final kreuz = richtung.dx * d.dy - richtung.dy * d.dx;
      if (kreuz.abs() < 1e-6 * d.distance) continue;
      final ak = a - kette;
      final s = (ak.dx * d.dy - ak.dy * d.dx) / kreuz;
      final g = (ak.dx * richtung.dy - ak.dy * richtung.dx) / kreuz;
      if (s > 1 && g >= -0.001 && g <= 1.001 && (s - t).abs() < bester) {
        bester = (s - t).abs();
        ziel = s;
        text = 'Verlängerung 180° bis Wand';
      }
    }
    final laenge = ziel ?? math.max(1, (t / _rasterMm).round()) * _rasterMm.toDouble();
    final e = kette + richtung * laenge;
    final p = Offset(e.dx.roundToDouble(), e.dy.roundToDouble());
    _fangText = '$text · ${mmText(laenge)}';
    _fangLinie = (kette - richtung * basis.laenge, p);
    return p;
  }

  /// Punkt auf einer Wand: [t] entlang der Achse, [quer] links (positiv) der Richtung.
  static Offset _wandPunkt(Wand w, double t, double quer) {
    final a = Offset(w.x1.toDouble(), w.y1.toDouble());
    final u = (Offset(w.x2.toDouble(), w.y2.toDouble()) - a) / math.max(1.0, w.laenge);
    return a + u * t + Offset(u.dy, -u.dx) * quer;
  }
  /// Merkt sich die Wand unter dem Fangpunkt und ergänzt die Abstände zu beiden Enden.
  void _fangWandSetzen(List<Wand> waende, Offset p, {Wand? wand}) {
    final w = wand ??
        waende.where((w) => abstandZuStrecke(p, Offset(w.x1.toDouble(), w.y1.toDouble()),
                Offset(w.x2.toDouble(), w.y2.toDouble())) < 1).firstOrNull;
    if (w == null) return;
    _fangWand = w;
    final da = (p - Offset(w.x1.toDouble(), w.y1.toDouble())).distance;
    final db = w.laenge - da;
    _fangText = '${_fangText ?? 'auf Wand'} · ${mmText(da)} | ${mmText(db)}'
        '${_kettenStart == null ? ' · Tab: Abstand eingeben' : ''}';
  }

  /// Fußpunkt des Lots von [p] auf die Achse von [w], falls er auf der Wand liegt.
  static Offset? _lotFuss(Offset p, Wand w) {
    final a = Offset(w.x1.toDouble(), w.y1.toDouble());
    final d = Offset(w.x2.toDouble(), w.y2.toDouble()) - a;
    final l2 = d.dx * d.dx + d.dy * d.dy;
    if (l2 == 0) return null;
    final t = ((p - a).dx * d.dx + (p - a).dy * d.dy) / l2;
    if (t <= 0.001 || t >= 0.999) return null;
    final f = a + d * t;
    return (f - p).distance < 1 ? null : f;
  }


  /// Schnittpunkt der (unendlich verlängerten) Achsen zweier Wände, wenn er
  /// außerhalb mindestens einer der beiden Wände liegt (sonst ist es ein Endpunkt
  /// oder eine Kreuzung, die anders gefangen wird).
  static Offset? _achsenSchnitt(Wand w1, Wand w2) {
    final p = Offset(w1.x1.toDouble(), w1.y1.toDouble()), r = Offset((w1.x2 - w1.x1).toDouble(), (w1.y2 - w1.y1).toDouble());
    final q = Offset(w2.x1.toDouble(), w2.y1.toDouble()), s = Offset((w2.x2 - w2.x1).toDouble(), (w2.y2 - w2.y1).toDouble());
    final kreuz = r.dx * s.dy - r.dy * s.dx;
    if (kreuz.abs() < 1e-6 * r.distance * s.distance) return null; // parallel
    final qp = q - p;
    final t = (qp.dx * s.dy - qp.dy * s.dx) / kreuz;
    final u = (qp.dx * r.dy - qp.dy * r.dx) / kreuz;
    const eps = 0.001;
    final innen1 = t > -eps && t < 1 + eps, innen2 = u > -eps && u < 1 + eps;
    if (innen1 && innen2) return null;
    final x = p + r * t;
    if ((x - p).distance > 30000) return null;
    return x;
  }

  /// Fußpunkt auf der Verlängerung der Achse von [w] (vor dem Anfang oder hinter
  /// dem Ende, höchstens 20 m), wenn [p] nahe an dieser Flucht liegt.
  Offset? _aufVerlaengerung(Offset p, Wand w) {
    final a = Offset(w.x1.toDouble(), w.y1.toDouble());
    final d = Offset(w.x2.toDouble(), w.y2.toDouble()) - a;
    final l = d.distance;
    if (l < 1) return null;
    final u = d / l;
    final t = (p - a).dx * u.dx + (p - a).dy * u.dy;
    if (t >= 0 && t <= l) return null;
    if (t < -20000 || t > l + 20000) return null;
    final f = a + u * t;
    return (f - p).distance < 10 / _massstab ? f : null;
  }

  /// Richtungsfang beim Zeichnen: parallel oder rechtwinklig zu einer
  /// vorhandenen (schrägen) Wand, bis ±3°.
  Offset? _richtungsFang(Offset start, Offset welt) {
    final v = welt - start;
    if (v.distance < 1) return null;
    final winkel = math.atan2(v.dy, v.dx);
    double? bester;
    var abw = 3 * math.pi / 180;
    String? text;
    for (final w in _plan?.waende ?? const <Wand>[]) {
      final wa = math.atan2((w.y2 - w.y1).toDouble(), (w.x2 - w.x1).toDouble());
      for (final (zusatz, t) in [(0.0, 'parallel zur Wand'), (math.pi / 2, 'rechtwinklig zur Wand')]) {
        var d = (winkel - (wa + zusatz)) % math.pi;
        if (d > math.pi / 2) d -= math.pi;
        if (d.abs() < abw) {
          abw = d.abs();
          bester = winkel - d;
          text = t;
        }
      }
    }
    if (bester == null) return null;
    // waagerecht/senkrecht erledigt der Rechtwinkel-Fang
    final rest = bester % (math.pi / 2);
    if (rest.abs() < 1e-4 || (rest - math.pi / 2).abs() < 1e-4) return null;
    final l = math.max(1, (v.distance / _rasterMm).round()) * _rasterMm.toDouble();
    _fangText = text;
    final e = start + Offset(math.cos(bester), math.sin(bester)) * l;
    return Offset(e.dx.roundToDouble(), e.dy.roundToDouble());
  }
  Offset _rasterFang(Offset welt) {

    // 2. Raster
    var x = (welt.dx / _rasterMm).round() * _rasterMm.toDouble();
    var y = (welt.dy / _rasterMm).round() * _rasterMm.toDouble();

    // 3. Winkelfang: Richtung in festen Schritten, Länge auf das Raster
    final start = _kettenStart;
    if (start != null && _winkelFang > 0 && !HardwareKeyboard.instance.isShiftPressed) {
      final v = welt - start;
      if (v.distance < 1) return start;
      final schritt = _winkelFang * math.pi / 180;
      final w = (math.atan2(v.dy, v.dx) / schritt).round() * schritt;
      final l = math.max(1, (v.distance / _rasterMm).round()) * _rasterMm.toDouble();
      final e = start + Offset(math.cos(w), math.sin(w)) * l;
      return Offset(e.dx.roundToDouble(), e.dy.roundToDouble());
    }

    // 3b. Parallel oder rechtwinklig zu einer schrägen Wand
    if (start != null && _winkelFang == 0 && !HardwareKeyboard.instance.isShiftPressed) {
      final r = _richtungsFang(start, welt);
      if (r != null) return r;
    }

    // 4. Rechtwinklig zum Kettenstart: mit Umschalt immer, sonst bis ±5°
    if (start != null) {
      final dx = (x - start.dx).abs();
      final dy = (y - start.dy).abs();
      final umschalt = HardwareKeyboard.instance.isShiftPressed;
      const tan5 = 0.0875;
      if (umschalt ? dx >= dy : dy <= dx * tan5) {
        y = start.dy;
      } else if (umschalt ? dy > dx : dx <= dy * tan5) {
        x = start.dx;
      }
    }
    // 5. Flucht zu Wandenden: x oder y eines vorhandenen Endpunkts übernehmen
    //    (nur in der Achse, die der Rechtwinkel-Fang noch frei lässt)
    final tol = 8 / _massstab;
    final frei = start == null ? (true, true) : (x != start.dx, y != start.dy);
    double? fx, fy;
    Offset? qx, qy;
    var bx = tol, by = tol;
    for (final w in _plan?.waende ?? const <Wand>[]) {
      for (final (px, py) in [(w.x1.toDouble(), w.y1.toDouble()), (w.x2.toDouble(), w.y2.toDouble())]) {
        if (frei.$1 && (welt.dx - px).abs() < bx && (welt.dy - py).abs() > tol) {
          bx = (welt.dx - px).abs();
          fx = px;
          qx = Offset(px, py);
        }
        if (frei.$2 && (welt.dy - py).abs() < by && (welt.dx - px).abs() > tol) {
          by = (welt.dy - py).abs();
          fy = py;
          qy = Offset(px, py);
        }
      }
    }
    if (fx != null) x = fx;
    if (fy != null) y = fy;
    if (fx != null || fy != null) {
      _fangText = 'Flucht zu Wandende';
      final q = qy ?? qx;
      if (q != null) _fangLinie = (q, Offset(x, y));
    }
    return Offset(x, y);
  }

  // ---------------------------------------------------------------- Aktionen

  void _wandSetzen(Offset a, Offset b) {
    if ((b - a).distance < 1) return;
    final store = _s.store!;
    final id = store.wandAnlegen(
      geschossId: _s.geschossId!,
      x1: a.dx.round(),
      y1: a.dy.round(),
      x2: b.dx.round(),
      y2: b.dy.round(),
      dicke: _wandDicke,
      zustand: _zustand,
      wandtypId: _gewaehlterTyp?.id,
      verbinden: _neueVerbinden,
    );
    _rueckgaengig.add(() => store.wandLoeschen(id));
    store.doppelteWaendeEntfernen(_s.geschossId!);
    _s.geaendert();
  }

  String? _wandTreffer(Offset welt, List<Wand> waende, {double extraPx = 0}) {
    String? id;
    var bester = (8 + extraPx) / _massstab;
    for (final w in waende) {
      final d = abstandZuStrecke(
        welt,
        Offset(w.x1.toDouble(), w.y1.toDouble()),
        Offset(w.x2.toDouble(), w.y2.toDouble()),
      );
      if (d < bester + w.dicke / 2) {
        bester = d;
        id = w.id;
      }
    }
    return id;
  }

  ErkannterRaum? _flaecheBei(Offset welt, _Plan plan) {
    final p = Punkt(welt.dx, welt.dy);
    // kleinste Fläche zuerst, falls sich Umrisse berühren
    final kandidaten = plan.flaechen.where((f) => f.enthaelt(p)).toList()
      ..sort((a, b) => a.flaeche.compareTo(b.flaeche));
    return kandidaten.firstOrNull;
  }

  void _flaecheWaehlen(ErkannterRaum? f, _Plan plan) {
    if (f == null) {
      _freieAuswahl = null;
      _s.raumWaehlen(null);
      return;
    }
    final raeume = plan.raeumeIn(f);
    if (raeume.isNotEmpty) {
      _freieAuswahl = null;
      _s.raumWaehlen(raeume.first.id);
    } else {
      _freieAuswahl = f;
      _s.raumWaehlen(null);
    }
  }


  /// Bodenplatte (Balkon, Terrasse …) unter dem Punkt wählen.
  bool _bodenplatteWaehlen(Offset welt, _Plan plan) {
    final p = Punkt(welt.dx, welt.dy);
    final r = plan.raeume.where((r) => r.istBodenplatte && punktInPolygon(p, r.umriss!)).firstOrNull;
    if (r == null) return false;
    _freieAuswahl = null;
    _s.raumWaehlen(r.id);
    return true;
  }

  /// Punkt der Bodenplatte setzen; Klick auf den ersten Punkt schließt.
  void _plattenKlick(Offset p) {
    if (_plattePunkte.length >= 3 && (p - _plattePunkte.first).distance < 12 / _massstab) {
      _platteAbschliessen();
      return;
    }
    if (_plattePunkte.isNotEmpty && (p - _plattePunkte.last).distance < 1) return;
    setState(() => _plattePunkte.add(p));
  }

  Future<void> _platteAbschliessen() async {
    final punkte = List.of(_plattePunkte);
    setState(_plattePunkte.clear);
    if (punkte.length < 3) return;
    final name = await texteingabe(context, titel: 'Bodenplatte benennen', feld: 'Name (z. B. Balkon, Terrasse, Loggia)', vorschlag: 'Balkon');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final n = name.trim();
    final klein = n.toLowerCase();
    final art = klein.contains('terrass')
        ? RaumArt.terrasse
        : klein.contains('loggia')
            ? RaumArt.loggia
            : RaumArt.balkon;
    final store = _s.store!;
    final kuerzel = n.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöü]'), '');
    final id = store.bodenplatteAnlegen(
      geschossId: _s.geschossId!,
      name: n,
      kuerzel: (kuerzel.length >= 3 ? kuerzel.substring(0, 3) : 'BAL').toUpperCase(),
      art: art,
      umriss: [for (final q in punkte) Punkt(q.dx, q.dy)],
    );
    _rueckgaengig.add(() => store.raumLoeschen(id));
    _s.geaendert();
    _s.raumWaehlen(id);
  }
  Future<void> _raumAnlegen(ErkannterRaum f) async {
    final store = _s.store!;
    final g = store.geschoss(_s.geschossId!);
    if (g == null) return;
    final id = await raumDialog(context, store, g, flaeche: f);
    if (id == null || !mounted) return;
    _rueckgaengig.add(() => store.raumLoeschen(id));
    setState(() => _freieAuswahl = null);
    _s.geaendert();
    _s.raumWaehlen(id);
  }

  void _klick(Offset bildschirm) {
    if (_abstandWand != null) setState(() => _abstandWand = null);
    _fokus.requestFocus();
    if (_s.geschossId == null) return;
    final plan = _planLaden();
    final welt = _zuWelt(bildschirm);
    if (_werkzeug == Werkzeug.auswahl) {
      _auswahlDruecken(welt, plan);
      return;
    }
    if (_vorlageModus == 1) {
      _kalibrierKlick(welt, plan);
      return;
    }
    if (_werkzeug == Werkzeug.oeffnung) {
      _oeffnungSetzen(welt, plan);
      return;
    }
    if (_werkzeug == Werkzeug.winkel) {
      _winkelKlick(welt, plan);
      return;
    }
    if (_werkzeug == Werkzeug.mass) {
      _massKlick(_fangen(welt, plan.waende));
      return;
    }
    if (_werkzeug == Werkzeug.raum) {
      if (_bodenplatte) {
        _plattenKlick(_fangen(welt, plan.waende));
        return;
      }
      if (_bodenplatteWaehlen(welt, plan)) return;
      final f = _flaecheBei(welt, plan);
      setState(() {
        _auswahl = {};
        _flaecheWaehlen(f, plan);
      });
      if (f == null) {
        zeigeHinweis(context, 'Hier ist kein geschlossener Wandzug. Räume entstehen aus ringsum geschlossenen Wänden.');
      } else if (plan.raeumeIn(f).isEmpty) {
        _raumAnlegen(f);
      }
      return;
    }
    final p = _fangen(welt, plan.waende);
    setState(() {
      final start = _kettenStart;
      if (_form == 1 && start != null) {
        if ((p - start).dx.abs() > 1 && (p - start).dy.abs() > 1) _rechteckSetzen(start, p);
      } else if (start == null) {
        _kettenStart = p;
      } else if ((p - start).distance < 1) {
        _kettenStart = null; // gleicher Punkt = Kette beenden
      } else {
        _wandSetzen(start, p);
        _kettenStart = p;
      }
      _eingabeLeeren();
    });
  }

  // ------------------------------------------- Auswahl und Verschieben

  bool get _zusatzTaste =>
      HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isControlPressed;

  /// Maustaste runter mit dem Auswahlwerkzeug: Auf einer Wand beginnt das
  /// Verschieben (die Wand kommt dazu, falls nicht gewählt), daneben ein Rahmen.
  void _auswahlDruecken(Offset welt, _Plan plan) {
    final id = _wandTreffer(welt, plan.waende);
    if (_parallelFuer != null) {
      if (id != null) {
        _parallelAusrichten(id, plan);
      } else {
        setState(() => _parallelFuer = null);
      }
      return;
    }
    final jetzt = DateTime.now();
    final letzter = _letzterWandKlick;
    bool doppelt(String? k) =>
        k != null && !_zusatzTaste && letzter != null && letzter.$1 == k && jetzt.difference(letzter.$2).inMilliseconds < 450;
    void feldFokus(FocusNode f, TextEditingController c) => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          f.requestFocus();
          c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
        });

    // Öffnung in einer Wand: Klick wählt sie
    final oe = _oeffnungTreffer(welt, plan);
    if (oe != null) {
      setState(() {
        _oeffnungAuswahl = oe;
        _auswahl = {};
        _massAuswahl = null;
        _winkelAuswahl = null;
        _freieAuswahl = null;
        _ziehStart = null;
      });
      _s.raumWaehlen(null);
      return;
    }
    _oeffnungAuswahl = null;

    // Bemaßung oder Winkelmaß: Klick wählt, Doppelklick springt in den Wert
    final bm = id == null ? _bemassungTreffer(welt, plan) : null;
    final wm = id == null && bm == null ? _winkelTreffer(welt, plan) : null;
    if (bm != null || wm != null) {
      final k = bm ?? wm!;
      final zweimal = doppelt(k);
      _letzterWandKlick = zweimal ? null : (k, jetzt);
      setState(() {
        _massAuswahl = bm;
        _winkelAuswahl = wm;
        _auswahl = {};
        _freieAuswahl = null;
        _ziehStart = null;
      });
      _s.raumWaehlen(null);
      if (zweimal) bm != null ? feldFokus(_massWertFokus, _massWertCtrl) : feldFokus(_winkelWertFokus, _winkelWertCtrl);
      return;
    }
    _massAuswahl = null;
    _winkelAuswahl = null;

    // Doppelklick auf eine Wand oder ihr Maß daneben: Längeneingabe rechts
    final nah = id ?? _wandTreffer(welt, plan.waende, extraPx: 30);
    if (doppelt(nah)) {
      setState(() {
        _auswahl = {nah!};
        _ziehStart = null;
        _verschiebtAuswahl = false;
        _letzterWandKlick = null;
        _freieAuswahl = null;
      });
      _s.raumWaehlen(null);
      feldFokus(_wandLaengeFokus, _wandLaengeCtrl);
      return;
    }
    if (nah != null) _letzterWandKlick = (nah, jetzt);

    setState(() {
      _ziehStart = welt;
      _versatz = Offset.zero;
      _rahmen = null;
      if (id != null) {
        if (_zusatzTaste) {
          _auswahl = _auswahl.contains(id) ? ({..._auswahl}..remove(id)) : {..._auswahl, id};
          _verschiebtAuswahl = false;
        } else {
          if (!_auswahl.contains(id)) _auswahl = {id};
          _verschiebtAuswahl = true;
        }
        _freieAuswahl = null;
        _s.raumWaehlen(null);
      } else {
        _verschiebtAuswahl = false;
      }
    });
  }

  void _auswahlZiehen(Offset welt) {
    final start = _ziehStart;
    if (start == null) return;
    setState(() {
      if (_verschiebtAuswahl) {
        final d = welt - start;
        _versatz = Offset(
          (d.dx / _rasterMm).round() * _rasterMm.toDouble(),
          (d.dy / _rasterMm).round() * _rasterMm.toDouble(),
        );
      } else if ((welt - start).distance * _massstab > 4) {
        _rahmen = Rect.fromPoints(start, welt);
      }
    });
  }

  void _auswahlLoslassen(Offset welt, _Plan plan) {
    final start = _ziehStart;
    _ziehStart = null;
    if (start == null) return;
    if (_verschiebtAuswahl) {
      _verschiebtAuswahl = false;
      final v = _versatz;
      setState(() => _versatz = Offset.zero);
      _auswahlVerschieben(v.dx.round(), v.dy.round());
      return;
    }
    final r = _rahmen;
    if (r != null) {
      // Nach rechts aufgezogen: nur ganz enthaltene Wände; nach links: auch angeschnittene.
      final ganz = welt.dx >= start.dx;
      final treffer = <String>{
        for (final w in plan.waende)
          if (ganz ? _wandInRahmen(w, r) : _wandBeruehrtRahmen(w, r)) w.id
      };
      setState(() {
        _rahmen = null;
        _auswahl = _zusatzTaste ? {..._auswahl, ...treffer} : treffer;
        _freieAuswahl = null;
      });
      _s.raumWaehlen(null);
      return;
    }
    // Klick auf einen Sparren (ohne Wand darunter): seine Sparrenlage öffnen
    if (_wandTreffer(welt, plan.waende) == null && _s.settings.darstellung['sparren_aus'] != true && _s.geschossId != null) {
      final felder = sparrenfelder(_s.store!, _s.geschossId!);
      final id = sparrenfeldBei(felder, welt.dx, welt.dy, 8 / _massstab);
      if (id != null) {
        sparrenDialogZeigen(context, _s, _s.geschossId!, feldId: id).then((_) {
          if (mounted) setState(() {});
        });
        return;
      }
    }
    // Einfacher Klick ohne Wand: Raum oder Fläche wählen, Auswahl leeren.
    if (_wandTreffer(welt, plan.waende) == null) {
      setState(() {
        if (!_zusatzTaste) _auswahl = {};
        if (!_bodenplatteWaehlen(welt, plan)) _flaecheWaehlen(_flaecheBei(welt, plan), plan);
      });
    }
  }

  static bool _wandInRahmen(Wand w, Rect r) =>
      r.contains(Offset(w.x1.toDouble(), w.y1.toDouble())) && r.contains(Offset(w.x2.toDouble(), w.y2.toDouble()));

  static bool _wandBeruehrtRahmen(Wand w, Rect r) {
    final a = Offset(w.x1.toDouble(), w.y1.toDouble());
    final b = Offset(w.x2.toDouble(), w.y2.toDouble());
    if (r.contains(a) || r.contains(b)) return true;
    // Schnitt mit einer der vier Rahmenkanten
    final ecken = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    for (var i = 0; i < 4; i++) {
      if (_streckenSchneiden(a, b, ecken[i], ecken[(i + 1) % 4])) return true;
    }
    return false;
  }

  static bool _streckenSchneiden(Offset p1, Offset p2, Offset q1, Offset q2) {
    double kreuz(Offset a, Offset b, Offset c) => (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    final d1 = kreuz(q1, q2, p1), d2 = kreuz(q1, q2, p2);
    final d3 = kreuz(p1, p2, q1), d4 = kreuz(p1, p2, q2);
    return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0);
  }

  void _auswahlVerschieben(int dx, int dy) {
    final ids = _auswahl.toList();
    if (ids.isEmpty || (dx == 0 && dy == 0)) return;
    final store = _s.store!;
    store.waendeVerschieben(ids, dx, dy);
    _rueckgaengig.add(() => store.waendeVerschieben(ids, -dx, -dy));
    _s.geaendert();
  }

  void _alleWaehlen() {
    setState(() {
      _auswahl = {for (final w in _planLaden().waende) w.id};
      _freieAuswahl = null;
      _kettenStart = null;
      _werkzeug = Werkzeug.auswahl;
    });
    _s.raumWaehlen(null);
  }

  // ---------------------------------------------------------- Bemaßung

  /// Abstand der Maßlinie von der Strecke A–B (links positiv), auf 50 mm gerundet.
  double _massAbstand(Offset a, Offset b, Offset m) {
    final l = (b - a).distance;
    if (l < 1) return 0;
    final u = (b - a) / l;
    final nl = Offset(u.dy, -u.dx);
    final d = (m - a).dx * nl.dx + (m - a).dy * nl.dy;
    return (d / 50).round() * 50.0;
  }

  /// Zweiter Maßpunkt nach gewählter Ausrichtung: direkt, waagerecht,
  /// senkrecht oder parallel zur nächsten Wand am ersten Punkt.
  Offset _massAusgerichtet(Offset a, Offset p) {
    switch (_massAusrichtung) {
      case 1:
        return Offset(p.dx, a.dy);
      case 2:
        return Offset(a.dx, p.dy);
      case 3:
        final plan = _plan;
        if (plan == null) return p;
        Wand? naechste;
        var bester = double.infinity;
        for (final w in plan.waende) {
          final d = abstandZuStrecke(a, Offset(w.x1.toDouble(), w.y1.toDouble()), Offset(w.x2.toDouble(), w.y2.toDouble()));
          if (d < bester) {
            bester = d;
            naechste = w;
          }
        }
        if (naechste == null) return p;
        final r = Offset((naechste.x2 - naechste.x1).toDouble(), (naechste.y2 - naechste.y1).toDouble());
        final l = r.distance;
        if (l < 1) return p;
        final u = r / l;
        final t = (p - a).dx * u.dx + (p - a).dy * u.dy;
        return a + u * t;
      default:
        return p;
    }
  }

  (Offset, Offset, double)? _massVorschau() {
    final a = _massA, m = _maus;
    if (_werkzeug != Werkzeug.mass || a == null || m == null) return null;
    final b = _massB;
    if (b == null) return (a, _massAusgerichtet(a, m), 0);
    return (a, b, _massAbstand(a, b, m));
  }

  void _massKlick(Offset p) {
    final a = _massA, b = _massB;
    if (a == null) {
      setState(() => _massA = p);
    } else if (b == null) {
      final q = _massAusgerichtet(a, p);
      if ((q - a).distance >= 1) setState(() => _massB = q);
    } else {
      final store = _s.store!;
      final id = store.bemassungAnlegen(
        geschossId: _s.geschossId!,
        x1: a.dx.round(),
        y1: a.dy.round(),
        x2: b.dx.round(),
        y2: b.dy.round(),
        abstand: _massAbstand(a, b, _maus ?? p).round(),
      );
      _rueckgaengig.add(() => store.bemassungLoeschen(id));
      setState(() {
        _massA = null;
        _massB = null;
      });
      _s.geaendert();
    }
  }

  String? _bemassungTreffer(Offset welt, _Plan plan) {
    String? id;
    var bester = 8 / _massstab;
    for (final b in plan.bemassungen) {
      if (!_bemassungenSichtbar || b.versteckt) continue;
      final a = Offset(b.x1.toDouble(), b.y1.toDouble()), e = Offset(b.x2.toDouble(), b.y2.toDouble());
      final l = (e - a).distance;
      if (l < 1) continue;
      final u = (e - a) / l;
      final v = Offset(u.dy, -u.dx) * b.abstand.toDouble();
      final d = abstandZuStrecke(welt, a + v, e + v);
      if (d < bester) {
        bester = d;
        id = b.id;
      }
    }
    return id;
  }

  Widget _bemassungEigenschaften(Bemassung b) {
    final store = _s.store!;
    final schluessel = '${b.id}|${b.laenge.round()}';
    if (_massWertFuer != schluessel && !_massWertFokus.hasFocus) {
      _massWertFuer = schluessel;
      _massWertCtrl.text = b.laenge.round().toString();
    }
    return ListView(
      children: [
        const Text('Bemaßung', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text(massText(b.laenge),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
          controller: _massWertCtrl,
          focusNode: _massWertFokus,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Maß',
            suffixText: 'mm',
            helperText: 'eintippen, Enter – die Wände folgen',
          ),
          onSubmitted: (v) {
            final wert = int.tryParse(v.trim());
            if (wert == null || wert <= 0) return;
            final zurueck = store.bemassungAendern(b.id, wert);
            if (zurueck == null) {
              zeigeHinweis(context, 'Hier lässt sich nichts verschieben – die Punkte sind gesperrt oder gehören zu keiner Wand.');
              return;
            }
            _rueckgaengig.add(zurueck);
            _massWertFuer = null;
            _fokus.requestFocus();
            _s.geaendert();
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Bewegt wird der zweite Messpunkt (ist er gesperrt, der erste). Liegt er an der Laibung einer Tür oder eines Fensters, wandert die Öffnung. Liegt dort eine Wand in '
          'Maßrichtung, ändert sich ihre Länge samt verbundener Wände.',
          style: TextStyle(fontSize: 11, height: 1.4, color: BsFarben.textLeise),
        ),
        const SizedBox(height: 8),
        Text('von (${mmText(b.x1)} | ${mmText(b.y1)})  nach (${mmText(b.x2)} | ${mmText(b.y2)})',
            style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _auswahlLoeschen,
          icon: const Icon(Sym.loeschen),
          label: const Text('Bemaßung löschen (Entf)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final tabelle = _winkelAuswahl != null ? 'winkelmass' : 'bemassung';
            final id = _winkelAuswahl ?? _massAuswahl;
            if (id == null) return;
            final store = _s.store!;
            store.massVerstecken(tabelle, id, true);
            _rueckgaengig.add(() => store.massVerstecken(tabelle, id, false));
            setState(() {
              _winkelAuswahl = null;
              _massAuswahl = null;
            });
            _s.geaendert();
          },
          icon: const Icon(Sym.ausblenden),
          label: const Text('Ausblenden'),
        ),
      ],
    );
  }

  // ------------------------------------------------------- Winkelmaße

  /// Geometrie eines Winkelmaßes in Weltkoordinaten: Scheitel, Startwinkel,
  /// Überstreichung (Bogenmaß) und Winkel in Grad.
  (Offset, double, double, double)? _winkelLage(Winkelmass m, _Plan plan) {
    final a = plan.waende.where((w) => w.id == m.wand1Id).firstOrNull;
    final b = plan.waende.where((w) => w.id == m.wand2Id).firstOrNull;
    if (a == null || b == null) return null;
    final g = ProjectStore.winkelGeometrie(a, b);
    if (g == null) return null;
    final (v, fa, fb) = g;
    final start = math.atan2((fa.$2 - v.$2).toDouble(), (fa.$1 - v.$1).toDouble());
    var sweep = math.atan2((fb.$2 - v.$2).toDouble(), (fb.$1 - v.$1).toDouble()) - start;
    while (sweep > math.pi) {
      sweep -= 2 * math.pi;
    }
    while (sweep < -math.pi) {
      sweep += 2 * math.pi;
    }
    var scheitel = Offset(v.$1.toDouble(), v.$2.toDouble());
    if (_winkelBezug != 0) {
      // Innen- oder Außenecke: gemeinsame Ecken der verschnittenen Umrisse
      final ua = plan.umrisse[a.id] ?? const <Offset>[], ub = plan.umrisse[b.id] ?? const <Offset>[];
      final gemeinsam = [for (final q in ua) if (ub.any((r) => (r - q).distance < 2)) q];
      if (gemeinsam.isNotEmpty) {
        final mitte = start + sweep / 2;
        final halb = Offset(math.cos(mitte), math.sin(mitte));
        double innen(Offset q) => (q - scheitel).dx * halb.dx + (q - scheitel).dy * halb.dy;
        gemeinsam.sort((x, y) => innen(y).compareTo(innen(x)));
        scheitel = _winkelBezug == 1 ? gemeinsam.first : gemeinsam.last;
      }
    }
    return (scheitel, start, sweep, sweep.abs() * 180 / math.pi);
  }

  List<WinkelBild> _winkelBilder(_Plan plan) => [
        for (final m in plan.winkelmasse)
          if (_bemassungenSichtbar && !m.versteckt)
          if (_winkelLage(m, plan) case (final v, final s, final w, final grad))
            (v, s, w, winkelText(grad), m.id == _winkelAuswahl),
      ];

  String? _winkelTreffer(Offset welt, _Plan plan) {
    for (final m in plan.winkelmasse) {
      if (!_bemassungenSichtbar || m.versteckt) continue;
      final l = _winkelLage(m, plan);
      if (l == null) continue;
      final (v, s, w, _) = l;
      final d = (welt - v).distance * _massstab;
      if (d > 60) continue;
      var a = math.atan2(welt.dy - v.dy, welt.dx - v.dx) - s;
      while (a > math.pi) {
        a -= 2 * math.pi;
      }
      while (a < -math.pi) {
        a += 2 * math.pi;
      }
      if (w >= 0 ? (a >= 0 && a <= w) : (a <= 0 && a >= w)) return m.id;
    }
    return null;
  }

  void _winkelKlick(Offset welt, _Plan plan) {
    final id = _wandTreffer(welt, plan.waende);
    if (id == null) return;
    final erste = _winkelErste;
    if (erste == null || erste == id) {
      setState(() => _winkelErste = id);
      return;
    }
    final a = plan.waende.firstWhere((w) => w.id == erste);
    final b = plan.waende.firstWhere((w) => w.id == id);
    if (ProjectStore.winkelGeometrie(a, b) == null) {
      zeigeHinweis(context, 'Die beiden Wände haben keinen gemeinsamen Eckpunkt.');
      setState(() => _winkelErste = null);
      return;
    }
    final store = _s.store!;
    final m = store.winkelmassAnlegen(_s.geschossId!, erste, id);
    _rueckgaengig.add(() => store.winkelmassLoeschen(m));
    setState(() => _winkelErste = null);
    _s.geaendert();
  }

  Widget _winkelEigenschaften(Winkelmass m, _Plan plan) {
    final store = _s.store!;
    final l = _winkelLage(m, plan);
    final grad = l?.$4 ?? 0;
    final schluessel = '${m.id}|${grad.toStringAsFixed(1)}';
    if (_winkelWertFuer != schluessel && !_winkelWertFokus.hasFocus) {
      _winkelWertFuer = schluessel;
      _winkelWertCtrl.text = winkelText(grad).replaceAll('°', '');
    }
    return ListView(
      children: [
        const Text('Winkelmaß', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text(winkelText(grad), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
          controller: _winkelWertCtrl,
          focusNode: _winkelWertFokus,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*[.,]?[0-9]*'))],
          decoration: const InputDecoration(labelText: 'Winkel', suffixText: '°', helperText: 'eintippen, Enter'),
          onSubmitted: (v) {
            final g = double.tryParse(v.trim().replaceAll(',', '.'));
            if (g == null) return;
            final zurueck = store.winkelAendern(m.id, g);
            if (zurueck == null) {
              zeigeHinweis(context, 'Winkel geht nicht: beide Wände gesperrt oder Wert nicht zwischen 0 und 180°.');
              return;
            }
            _rueckgaengig.add(zurueck);
            _winkelWertFuer = null;
            _fokus.requestFocus();
            _s.geaendert();
          },
        ),
        const SizedBox(height: 8),
        const Text('Gedreht wird die zweite Wand um den Eckpunkt (ist sie gesperrt, die erste). '
            'Wände am fernen Ende ziehen mit.',
            style: TextStyle(fontSize: 11, height: 1.4, color: BsFarben.textLeise)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _auswahlLoeschen,
          icon: const Icon(Sym.loeschen),
          label: const Text('Winkelmaß löschen (Entf)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final tabelle = _winkelAuswahl != null ? 'winkelmass' : 'bemassung';
            final id = _winkelAuswahl ?? _massAuswahl;
            if (id == null) return;
            final store = _s.store!;
            store.massVerstecken(tabelle, id, true);
            _rueckgaengig.add(() => store.massVerstecken(tabelle, id, false));
            setState(() {
              _winkelAuswahl = null;
              _massAuswahl = null;
            });
            _s.geaendert();
          },
          icon: const Icon(Sym.ausblenden),
          label: const Text('Ausblenden'),
        ),
      ],
    );
  }

  /// Ob eine Wand ihre Ecken verschneidet (eigene Einstellung oder Projektvorgabe).
  bool _verbindet(Wand w) => w.verbinden ?? _eckenVerbinden;

  /// Flankengrenzen einer Wand mit denselben Nachbarn wie in der Darstellung.
  ({double linksA, double linksB, double rechtsA, double rechtsB}) _grenzen(Wand w, _Plan plan) {
    final i = plan.waende.indexWhere((e) => e.id == w.id);
    if (i < 0 || !_verbindet(w)) return flankenGrenzen(w.achse, const []);
    final nachbarn = [
      for (var j = 0; j < plan.waende.length; j++)
        if (_verbindet(plan.waende[j])) plan.achsen[j]
    ];
    return flankenGrenzen(plan.achsen[i], nachbarn);
  }

  // ------------------------------------------------------- Planvorlage

  /// Lädt das Bild der Planvorlage, wenn sich die Datei geändert hat.
  void _vorlageBildPruefen(Planvorlage? v) {
    final datei = v?.datei;
    if (datei == _vorlageDatei) return;
    _vorlageDatei = datei;
    _vorlageBild = null;
    _vorlageDxf = null;
    _dxfCacheSchluessel = null;
    if (datei == null) return;
    final pfad = p.join(_s.store!.ordner, datei);
    if (_istDxf(datei)) {
      () async {
        try {
          final d = await _dxfDatei(pfad);
          if (mounted && _vorlageDatei == datei) setState(() => _vorlageDxf = d);
        } catch (_) {
          if (mounted) zeigeFehler(context, 'DXF-Vorlage konnte nicht gelesen werden: ${p.basename(pfad)}');
        }
      }();
      return;
    }
    () async {
      try {
        final codec = await ui.instantiateImageCodec(await File(pfad).readAsBytes());
        final bild = (await codec.getNextFrame()).image;
        if (mounted && _vorlageDatei == datei) setState(() => _vorlageBild = bild);
      } catch (_) {
        if (mounted) zeigeFehler(context, 'Planvorlage konnte nicht geladen werden: ${p.basename(pfad)}');
      }
    }();
  }

  (ui.Image, Rect, double)? _vorlageDarstellung(_Plan plan) {
    final v = plan.vorlage, bild = _vorlageBild;
    if (v == null || bild == null || !v.sichtbar) return null;
    final ursprung = Offset(v.x.toDouble(), v.y.toDouble()) + _vorlageVersatz;
    final groesse = Size(bild.width * v.mmProPx, bild.height * v.mmProPx);
    return (bild, ursprung & groesse, v.deckkraft / 100);
  }

  Future<void> _vorlageLaden() async {
    final datei = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Bilder, PDF und DXF', extensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp', 'pdf', 'dxf']),
    ]);
    if (datei == null || !mounted) return;
    final store = _s.store!;
    final alt = store.planvorlage(_s.geschossId!);
    if (datei.path.toLowerCase().endsWith('.pdf')) {
      final m = await texteingabe(context,
          titel: 'PDF als Planvorlage', feld: 'Maßstab des Plans 1 : … (leer = danach kalibrieren)', vorschlag: '100');
      if (!mounted || m == null) return;
      final seite = await texteingabe(context, titel: 'PDF als Planvorlage', feld: 'Seite', vorschlag: '1');
      if (!mounted || seite == null) return;
      final s = (int.tryParse(seite.trim()) ?? 1) - 1;
      final ziel = p.join(Directory.systemTemp.path, 'bauspur_pdf', '${p.basenameWithoutExtension(datei.path)}_S${s + 1}.png');
      zeigeHinweis(context, 'PDF wird umgewandelt …');
      final r = await pdfSeiteAlsPng(datei.path, ziel, seite: s, dpi: 200);
      if (!mounted) return;
      if (r == null) {
        zeigeFehler(context, 'Die PDF-Seite ließ sich nicht umwandeln (geht nur unter Windows). Alternativ die Seite als Bild exportieren.');
        return;
      }
      final massstab = int.tryParse(m.trim());
      final id = store.planvorlageAnlegen(_s.geschossId!, r.png, umProPx: massstab == null ? 10000 : umProPxAusMassstab(r.dpi, massstab));
      _rueckgaengig.add(() {
        store.planvorlageLoeschen(id);
        if (alt != null) store.planvorlageWiederherstellen(alt.id);
      });
      _s.geaendert();
      if (massstab == null) {
        zeigeHinweis(context, 'PDF-Seite geladen. Jetzt kalibrieren: zwei Punkte mit bekanntem Abstand anklicken.');
        setState(() {
          _vorlageModus = 1;
          _kalibrierPunkte = [];
        });
      } else {
        zeigeHinweis(context, 'PDF-Seite ${s + 1} von ${r.seiten} geladen (1:$massstab). Maßstab bei Bedarf über „Kalibrieren“ prüfen.');
      }
      return;
    }
    if (_istDxf(datei.path)) {
      DxfZeichnung d;
      try {
        d = await _dxfDatei(datei.path);
      } catch (e) {
        if (mounted) zeigeFehler(context, 'Die DXF-Datei lässt sich nicht lesen (nur ASCII-DXF): $e');
        return;
      }
      final g = d.grenzen;
      if (g == null) {
        if (mounted) zeigeFehler(context, 'In der DXF-Datei sind keine Linien.');
        return;
      }
      final s = d.mmProEinheit;
      final id = store.planvorlageAnlegen(_s.geschossId!, datei.path, umProPx: (s * 1000).round(), deckkraft: 60);
      // linke obere Ecke der Zeichnung auf den Nullpunkt
      store.planvorlageAendern(id, x: (-g.$1 * s).round(), y: (g.$4 * s).round());
      _rueckgaengig.add(() {
        store.planvorlageLoeschen(id);
        if (alt != null) store.planvorlageWiederherstellen(alt.id);
      });
      _s.geaendert();
      if (!mounted) return;
      final einheit = switch (s) { 1 => 'mm', 10 => 'cm', 1000 => 'm', _ => '$s mm' };
      zeigeHinweis(context, 'DXF geladen (${d.zuege.length} Linien, Einheit $einheit). Maßstab bei Bedarf über „Kalibrieren“ prüfen.');
      // sobald die Vorlage gelesen ist: Wände übernehmen anbieten
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _vorlageDxf != null) _dxfWaendeDialog();
      });
      return;
    }
    final id = store.planvorlageAnlegen(_s.geschossId!, datei.path);
    _rueckgaengig.add(() {
      store.planvorlageLoeschen(id);
      if (alt != null) store.planvorlageWiederherstellen(alt.id);
    });
    _s.geaendert();
    if (mounted) {
      zeigeHinweis(context, 'Planvorlage geladen. Jetzt kalibrieren: zwei Punkte mit bekanntem Abstand anklicken.');
      setState(() {
        _vorlageModus = 1;
        _kalibrierPunkte = [];
      });
    }
  }

  /// Klick im Kalibriermodus: zwei Punkte, dann echten Abstand abfragen.
  Future<void> _kalibrierKlick(Offset welt, _Plan plan) async {
    final v = plan.vorlage;
    if (v == null) return;
    setState(() => _kalibrierPunkte = [..._kalibrierPunkte, welt]);
    if (_kalibrierPunkte.length < 2) return;
    final (p1, p2) = (_kalibrierPunkte[0], _kalibrierPunkte[1]);
    final gemessen = (p2 - p1).distance;
    final eingabe = await texteingabe(context,
        titel: 'Kalibrieren', feld: 'Echter Abstand der beiden Punkte in mm', vorschlag: gemessen.round().toString());
    setState(() {
      _kalibrierPunkte = [];
      _vorlageModus = 0;
    });
    final echt = int.tryParse(eingabe?.trim() ?? '');
    if (echt == null || echt <= 0 || gemessen < 1) return;
    // Maßstab so ändern, dass der erste Punkt an seiner Stelle bleibt
    final faktor = echt / gemessen;
    final neuUm = (v.umProPx * faktor).round();
    final ursprung = Offset(v.x.toDouble(), v.y.toDouble());
    final neuUrsprung = p1 - (p1 - ursprung) * faktor;
    final store = _s.store!;
    store.planvorlageAendern(v.id, umProPx: neuUm, x: neuUrsprung.dx.round(), y: neuUrsprung.dy.round());
    _rueckgaengig.add(() => store.planvorlageAendern(v.id, umProPx: v.umProPx, x: v.x, y: v.y));
    _s.geaendert();
  }

  void _vorlageVerschiebenFertig() {
    final v = _plan?.vorlage;
    final d = _vorlageVersatz;
    setState(() {
      _vorlageVersatz = Offset.zero;
      _vorlageZiehStart = null;
    });
    if (v == null || d == Offset.zero) return;
    final store = _s.store!;
    store.planvorlageAendern(v.id, x: v.x + d.dx.round(), y: v.y + d.dy.round());
    _rueckgaengig.add(() => store.planvorlageAendern(v.id, x: v.x, y: v.y));
    _s.geaendert();
  }


  // ------------------------------------------------------ DXF-Vorlage

  DxfZeichnung? _vorlageDxf;
  (String, int, int, int, Offset)? _dxfCacheSchluessel;
  (List<List<Offset>>, List<(Offset, String, double)>)? _dxfCache;

  static bool _istDxf(String? datei) => datei != null && datei.toLowerCase().endsWith('.dxf');

  /// DXF-Datei lesen (UTF-8, sonst Latin-1 wie bei älteren CAD-Programmen).
  static Future<DxfZeichnung> _dxfDatei(String pfad) async {
    final bytes = await File(pfad).readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    return dxfLesen(text);
  }

  /// DXF-Vorlage in Weltkoordinaten (zwischengespeichert, bis Lage oder Maßstab sich ändern).
  (List<List<Offset>>, List<(Offset, String, double)>, double)? _vorlageLinien(_Plan plan) {
    final v = plan.vorlage, d = _vorlageDxf;
    if (v == null || d == null || !v.sichtbar || !_istDxf(v.datei)) return null;
    final schluessel = (v.datei, v.x, v.y, v.umProPx, _vorlageVersatz);
    if (_dxfCacheSchluessel != schluessel) {
      final s = v.mmProPx;
      final ox = v.x + _vorlageVersatz.dx, oy = v.y + _vorlageVersatz.dy;
      Offset w(Punkt q) {
        final r = DxfZeichnung.zuWelt(q, ursprungX: ox, ursprungY: oy, mmProEinheit: s);
        return Offset(r.x, r.y);
      }

      _dxfCache = (
        [
          for (final z in d.zuege) [for (final q in z.punkte) w(q), if (z.geschlossen && z.punkte.length > 2) w(z.punkte.first)],
        ],
        [for (final t in d.texte) (w(t.ort), t.text, t.hoehe * s)],
      );
      _dxfCacheSchluessel = schluessel;
    }
    final (l, t) = _dxfCache!;
    return (l, t, v.deckkraft / 100);
  }

  /// Wände aus einer DXF-Vorlage übernehmen: Layer wählen, Doppellinien
  /// werden zu Wänden mit ihrer Dicke, einzelne Linien optional mit Standarddicke.
  Future<void> _dxfWaendeDialog() async {
    final v = _plan?.vorlage, d = _vorlageDxf;
    if (v == null || d == null) return;
    final anzahl = d.anzahlJeLayer;
    final layer = anzahl.keys.toList()..sort();
    // Layer mit „wand“ im Namen vorwählen
    final gewaehlt = {for (final l in layer) if (l.toLowerCase().contains('wand') || l.toLowerCase().contains('wall')) l};
    var einzeln = false;
    var dicke = _wandDicke;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Wände aus DXF übernehmen'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Layer mit Wänden wählen. Zwei parallele Linien im Abstand 5–60 cm werden zu einer Wand mit dieser Dicke.',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(shrinkWrap: true, children: [
                  for (final l in layer)
                    CheckboxListTile(
                      dense: true,
                      value: gewaehlt.contains(l),
                      title: Text(l),
                      secondary: Text('${anzahl[l]}'),
                      onChanged: (x) => setD(() => x == true ? gewaehlt.add(l) : gewaehlt.remove(l)),
                    ),
                ]),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: einzeln,
                title: const Text('einzelne Linien ebenfalls als Wand'),
                onChanged: (x) => setD(() => einzeln = x ?? false),
              ),
              if (einzeln)
                DropdownButton<int>(
                  value: _dicken.contains(dicke) ? dicke : _dicken.first,
                  items: [for (final x in _dicken) DropdownMenuItem(value: x, child: Text('Dicke $x mm'))],
                  onChanged: (x) => setD(() => dicke = x ?? dicke),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: gewaehlt.isEmpty ? null : () => Navigator.pop(c, true), child: const Text('Übernehmen')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final s = v.mmProPx;
    Punkt w(Punkt q) => DxfZeichnung.zuWelt(q, ursprungX: v.x.toDouble(), ursprungY: v.y.toDouble(), mmProEinheit: s);
    final strecken = <(Punkt, Punkt)>[
      for (final z in d.zuege)
        if (gewaehlt.contains(z.layer) && !z.bogen)
          for (var i = 0; i + 1 < z.punkte.length + (z.geschlossen ? 1 : 0); i++)
            (w(z.punkte[i]), w(z.punkte[(i + 1) % z.punkte.length])),
    ];
    final vorschlaege = waendeVerbinden(waendeErkennen(strecken, standardDicke: dicke.toDouble(), einzelLinien: einzeln));
    if (vorschlaege.isEmpty) {
      zeigeHinweis(context, 'Auf diesen Layern wurden keine Wände erkannt.');
      return;
    }
    final store = _s.store!;
    final ids = [
      for (final x in vorschlaege)
        store.wandAnlegen(
          geschossId: _s.geschossId!,
          x1: x.a.x.round(),
          y1: x.a.y.round(),
          x2: x.b.x.round(),
          y2: x.b.y.round(),
          dicke: x.dicke.round(),
          zustand: _zustand,
        ),
    ];
    _rueckgaengig.add(() {
      for (final id in ids) {
        store.wandLoeschen(id);
      }
    });
    _s.geaendert();
    zeigeHinweis(context, '${ids.length} Wände übernommen. Ecken prüfen und mit „Ecken verbinden“ schließen, wo nötig.');
  }
  Widget _vorlageMenue(_Plan plan) {
    final v = plan.vorlage;
    final store = _s.store!;
    return PopupMenuButton<String>(
      tooltip: 'Planvorlage: Bild, Scan oder DXF-Zeichnung als Hintergrund',
      onSelected: (a) {
        switch (a) {
          case 'laden':
            _vorlageLaden();
          case 'kalibrieren':
            setState(() {
              _vorlageModus = 1;
              _kalibrierPunkte = [];
            });
            zeigeHinweis(context, 'Zwei Punkte mit bekanntem Abstand auf der Vorlage anklicken.');
          case 'dxfwaende':
            _dxfWaendeDialog();
          case 'verschieben':
            setState(() => _vorlageModus = _vorlageModus == 2 ? 0 : 2);
          case 'sichtbar':
            store.planvorlageAendern(v!.id, sichtbar: !v.sichtbar);
            _s.geaendert();
          case 'entfernen':
            store.planvorlageLoeschen(v!.id);
            _rueckgaengig.add(() => store.planvorlageWiederherstellen(v.id));
            _s.geaendert();
          default:
            if (a.startsWith('deck')) {
              store.planvorlageAendern(v!.id, deckkraft: int.parse(a.substring(4)));
              _s.geaendert();
            }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'laden', child: Text(v == null ? 'Bild oder DXF laden …' : 'andere Vorlage laden …')),
        if (v != null && _istDxf(v.datei)) const PopupMenuItem(value: 'dxfwaende', child: Text('Wände aus DXF übernehmen …')),
        if (v != null) ...[
          const PopupMenuItem(value: 'kalibrieren', child: Text('Kalibrieren (zwei Punkte + Abstand)')),
          PopupMenuItem(value: 'verschieben', child: Text(_vorlageModus == 2 ? 'Verschieben beenden' : 'Verschieben')),
          PopupMenuItem(value: 'sichtbar', child: Text(v.sichtbar ? 'Ausblenden' : 'Einblenden')),
          for (final d in const [25, 50, 75, 100])
            PopupMenuItem(value: 'deck$d', child: Text('Deckkraft $d %${v.deckkraft == d ? '  ✓' : ''}')),
          const PopupMenuItem(value: 'entfernen', child: Text('Vorlage entfernen')),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Sym.planvorlage, size: 18, color: _vorlageModus != 0 ? BsFarben.akzentDunkel : null),
          const SizedBox(width: 4),
          Text(
            switch (_vorlageModus) {
              1 => 'Kalibrieren …',
              2 => 'Vorlage verschieben',
              _ => 'Planvorlage',
            },
            style: TextStyle(color: _vorlageModus != 0 ? BsFarben.akzentDunkel : null),
          ),
        ]),
      ),
    );
  }

  // --------------------------------------------------------- Öffnungen

  static const _oeffnungsBreiten = {
    OeffnungsArt.tuer: [635, 760, 885, 1010, 1135, 1260],
    OeffnungsArt.fenster: [510, 635, 760, 885, 1010, 1135, 1260, 1510, 1760, 2010],
    OeffnungsArt.balkontuer: [760, 885, 1010, 1135, 1260, 1510, 1760, 2010],
    OeffnungsArt.durchbruch: [500, 625, 750, 875, 1000, 1250, 1500, 2000],
    OeffnungsArt.nische: [200, 300, 400, 500, 600, 800, 1000, 1200],
  };

  /// Lage einer neuen Öffnung unter dem Zeiger: Wand und Abstand (auf Raster).
  (String, int, int, OeffnungsArt)? _oeffnungVorschauBerechnen(Offset welt, _Plan plan) {
    final id = _wandTreffer(welt, plan.waende);
    if (id == null) return null;
    final w = plan.waende.firstWhere((e) => e.id == id);
    final l = w.laenge;
    final b = _oeffnungBreite;
    if (l < b + 1) return null;
    final a = Offset(w.x1.toDouble(), w.y1.toDouble());
    final u = (Offset(w.x2.toDouble(), w.y2.toDouble()) - a) / l;
    final t = (welt - a).dx * u.dx + (welt - a).dy * u.dy - b / 2;
    final ab = ((t / _rasterMm).round() * _rasterMm).clamp(0, (l - b).floor());
    return (id, ab, b, _oeffnungArt);
  }

  void _oeffnungSetzen(Offset welt, _Plan plan) {
    final v = _oeffnungVorschauBerechnen(welt, plan);
    if (v == null) {
      zeigeHinweis(context, 'Öffnungen sitzen in einer Wand – auf eine Wand klicken, die lang genug ist.');
      return;
    }
    final (wandId, abstand, breite, art) = v;
    final (_, hoehe, bruestung) = art.standard;
    final store = _s.store!;
    final id = store.oeffnungAnlegen(
        wandId: wandId, art: art, abstand: abstand, breite: breite, hoehe: hoehe, bruestung: bruestung);
    _rueckgaengig.add(() => store.oeffnungLoeschen(id));
    _s.geaendert();
  }

  String? _oeffnungTreffer(Offset welt, _Plan plan) {
    for (final o in plan.oeffnungen) {
      final w = plan.waende.where((e) => e.id == o.wandId).firstOrNull;
      if (w == null || w.laenge < 1) continue;
      final a = Offset(w.x1.toDouble(), w.y1.toDouble());
      final u = (Offset(w.x2.toDouble(), w.y2.toDouble()) - a) / w.laenge;
      final t = (welt - a).dx * u.dx + (welt - a).dy * u.dy;
      final q = ((welt - a).dx * u.dy - (welt - a).dy * u.dx).abs();
      final rand = 4 / _massstab;
      if (t >= o.abstand - rand && t <= o.abstand + o.breite + rand && q <= w.dicke / 2 + rand) return o.id;
    }
    return null;
  }

  Widget _oeffnungEigenschaften(Oeffnung o, _Plan plan) {
    final store = _s.store!;
    final w = plan.waende.where((e) => e.id == o.wandId).firstOrNull;
    void aendern(Map<String, Object?> felder) {
      final alt = store.oeffnungAendern(o.id, felder);
      if (alt.isEmpty) return;
      _rueckgaengig.add(() => store.oeffnungAendern(o.id, alt));
      _s.geaendert();
    }

    Widget zahl(String label, String feld, int wert, {int? max}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SpeicherFeld(
            key: ValueKey('oe-$feld-${o.id}-$wert'),
            initialValue: '$wert',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, suffixText: 'mm'),
            onFieldSubmitted: (v) {
              var n = int.tryParse(v.trim());
              if (n == null) return;
              if (max != null) n = n.clamp(0, max);
              aendern({feld: n});
              _fokus.requestFocus();
            },
          ),
        );

    final wandLaenge = w?.laenge.floor() ?? 100000;
    return ListView(
      children: [
        const Text('Öffnung', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text('${o.art.label} ${mmText(o.breite)} × ${mmText(o.hoehe)}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        DropdownButtonFormField<OeffnungsArt>(
          key: ValueKey('oe-art-${o.id}-${o.art.name}'),
          initialValue: o.art,
          decoration: const InputDecoration(labelText: 'Art'),
          items: [for (final a in OeffnungsArt.values) DropdownMenuItem(value: a, child: Text(a.label))],
          onChanged: (a) {
            if (a == null) return;
            final (_, h, br) = a.standard;
            aendern({'art': a.name, 'hoehe_mm': h, 'bruestung_mm': br});
          },
        ),
        const SizedBox(height: 10),
        zahl('Breite (Rohbau)', 'breite_mm', o.breite, max: wandLaenge - o.abstand),
        zahl('Höhe (Rohbau)', 'hoehe_mm', o.hoehe),
        zahl('Brüstung', 'bruestung_mm', o.bruestung),
        zahl('Abstand vom Wandanfang', 'abstand_mm', o.abstand, max: wandLaenge - o.breite),
        if (o.art == OeffnungsArt.nische) ...[
          SpeicherFeld(
            key: ValueKey('nt-${o.id}-${o.eigenschaften['tiefe']}'),
            initialValue: '${o.eigenschaften['tiefe'] ?? 100}',
            decoration: const InputDecoration(labelText: 'Tiefe der Nische', suffixText: 'mm'),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onFieldSubmitted: (t) => aendern({'eigenschaften': jsonEncode({...o.eigenschaften, 'tiefe': int.tryParse(t) ?? 100})}),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => aendern({'aufgehen_links': o.aufgehenLinks ? 0 : 1}),
            icon: const Icon(Icons.swap_vert, size: 18),
            label: const Text('Wandseite wechseln'),
          ),
          const Text('Nischen in Dusch- und Wannenbereichen zählen in der Abdichtung mit (Laibungen).',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        ],
        if (o.art == OeffnungsArt.tuer || o.art == OeffnungsArt.balkontuer)
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: () => aendern({'band_rechts': o.bandRechts ? 0 : 1}),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Anschlag wechseln'),
            ),
            OutlinedButton.icon(
              onPressed: () => aendern({'aufgehen_links': o.aufgehenLinks ? 0 : 1}),
              icon: const Icon(Icons.swap_vert, size: 18),
              label: const Text('Aufschlagseite wechseln'),
            ),
          ]),
        if (o.art == OeffnungsArt.tuer) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('tuerart-${o.id}-${o.eigenschaften['tuerart']}'),
            initialValue: o.eigenschaften['tuerart'] as String? ?? 'dreh',
            decoration: const InputDecoration(labelText: 'Türart'),
            items: const [
              DropdownMenuItem(value: 'dreh', child: Text('Drehtür')),
              DropdownMenuItem(value: 'wandbuendig', child: Text('wandbündige Tür (verdeckte Zarge)')),
              DropdownMenuItem(value: 'schiebe', child: Text('Schiebetür vor der Wand')),
              DropdownMenuItem(value: 'tasche', child: Text('Taschen-/Schiebetür in der Wand')),
              DropdownMenuItem(value: 'pendel', child: Text('Pendeltür')),
            ],
            onChanged: (v) => aendern({'eigenschaften': jsonEncode({...o.eigenschaften, 'tuerart': v})}),
          ),
          ..._tuerHinweise(o, w),
        ],
        if (o.art == OeffnungsArt.tuer || o.art == OeffnungsArt.balkontuer) ..._schwellenHinweise(o, w),
        if (o.art != OeffnungsArt.durchbruch && o.art != OeffnungsArt.nische) ...[
          const Divider(height: 24),
          BauelementWahl(
            state: _s,
            label: o.art == OeffnungsArt.tuer ? 'Tür aus der Bibliothek' : '${o.art.label} aus der Bibliothek',
            wert: o.eigenschaften['bauelement'] as String?,
            kategorien: switch (o.art) {
              OeffnungsArt.tuer => const [BauelementKategorie.tuer],
              OeffnungsArt.balkontuer => const [BauelementKategorie.balkontuer, BauelementKategorie.fenster],
              _ => const [BauelementKategorie.fenster],
            },
            nurKategorien: true,
            onChanged: (e) => aendern({'eigenschaften': jsonEncode({...o.eigenschaften, 'bauelement': e?.id}..removeWhere((_, v) => v == null))}),
          ),
          const SizedBox(height: 8),
          BauelementWahl(
            state: _s,
            label: 'Rollladen / Jalousie / Raffstore',
            wert: o.eigenschaften['sonnenschutz'] as String?,
            kategorien: const [BauelementKategorie.sonnenschutz],
            nurKategorien: true,
            onChanged: (e) => aendern({'eigenschaften': jsonEncode({...o.eigenschaften, 'sonnenschutz': e?.id}..removeWhere((_, v) => v == null))}),
          ),
          const SizedBox(height: 10),
          if (o.eigenschaften['einbau'] is Map)
            Builder(builder: (_) {
              final ein = Map<String, dynamic>.from(o.eigenschaften['einbau'] as Map);
              final psi = (ein['psi'] as num?)?.toDouble();
              final f = (ein['f_rsi'] as num?)?.toDouble();
              return Text(
                [
                  'Einbaulage ${ein['einbaulage'] ?? '–'} mm, Laibungsdämmung ${ein['laibung'] ?? 0} mm',
                  if (psi != null) 'Ψ = ${psi.toStringAsFixed(3).replaceAll('.', ',')} W/(mK)',
                  if (f != null) 'fRsi = ${f.toStringAsFixed(2).replaceAll('.', ',')} ${f >= 0.7 ? '✓' : '– Schimmelgefahr!'}',
                ].join('\n'),
                style: TextStyle(fontSize: 12, color: f != null && f < 0.7 ? const Color(0xFFB91C1C) : BsFarben.textLeise),
              );
            }),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: w == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EinbaudetailPage(state: _s, oeffnungId: o.id, wand: w))),
            icon: const Icon(Icons.thermostat_outlined, size: 18),
            label: const Text('Einbaudetail und Wärmebrücke …'),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _auswahlLoeschen,
          icon: const Icon(Sym.loeschen),
          label: Text('${o.art.label} löschen (Entf)'),
        ),
      ],
    );
  }

  // ---------------------------------------------------- Rechteckraum

  /// Achsrechteck aus zwei Eckpunkten; im Innenmaß-Modus sind die Punkte
  /// die Innenecken, die Achse liegt dann eine halbe Wanddicke außen.
  Rect _rechteckAchse(Offset a, Offset b) {
    final r = Rect.fromPoints(a, b);
    return switch (_massBezug) {
      MassBezug.achse => r,
      MassBezug.innen => r.inflate(_zeichenDicke / 2),
      MassBezug.aussen => r.deflate(_zeichenDicke / 2),
    };
  }

  /// Vier Wände als geschlossenes Rechteck; danach gleich den Raum benennen.
  void _rechteckSetzen(Offset a, Offset b) {
    final r = _rechteckAchse(a, b);
    if (r.width < 100 || r.height < 100) return;
    final ecken = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    final store = _s.store!;
    final ids = <String>[];
    for (var i = 0; i < 4; i++) {
      final p = ecken[i], q = ecken[(i + 1) % 4];
      ids.add(store.wandAnlegen(
        geschossId: _s.geschossId!,
        x1: p.dx.round(),
        y1: p.dy.round(),
        x2: q.dx.round(),
        y2: q.dy.round(),
        dicke: _wandDicke,
        zustand: _zustand,
        wandtypId: _gewaehlterTyp?.id,
        verbinden: _neueVerbinden,
      ));
    }
    _rueckgaengig.add(() {
      for (final id in ids) {
        store.wandLoeschen(id);
      }
    });
    // angrenzender Raum: die gemeinsame Wand nicht doppelt anlegen
    store.doppelteWaendeEntfernen(_s.geschossId!);
    setState(() {
      _kettenStart = null;
      _eingabeLeeren();
    });
    _s.geaendert();
    final plan = _planLaden();
    final f = _flaecheBei(r.center, plan);
    if (f != null && plan.raeumeIn(f).isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _raumAnlegen(f);
      });
    }
  }

  // ------------------------------------------------ Ansicht verschieben

  /// Steht der Zeiger beim Zeichnen, Verschieben oder Rahmenziehen am Rand
  /// der Zeichenfläche, wandert die Ansicht mit – der Arbeitsbereich ist
  /// unbegrenzt.
  void _randPruefen() {
    final z = _zeiger;
    final aktiv = _kettenStart != null || _verschiebtAuswahl || _rahmen != null;
    if (z == null || !aktiv || _flaeche.isEmpty) {
      _randTimer?.cancel();
      _randTimer = null;
      return;
    }
    _randTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _randSchritt());
  }

  void _randSchritt() {
    final z = _zeiger;
    if (!mounted || z == null) return;
    const rand = 28.0, tempo = 14.0;
    var dx = 0.0, dy = 0.0;
    if (z.dx < rand) dx = tempo * (1 - z.dx / rand).clamp(0.2, 1.0);
    if (z.dx > _flaeche.width - rand) dx = -tempo * (1 - (_flaeche.width - z.dx) / rand).clamp(0.2, 1.0);
    if (z.dy < rand) dy = tempo * (1 - z.dy / rand).clamp(0.2, 1.0);
    if (z.dy > _flaeche.height - rand) dy = -tempo * (1 - (_flaeche.height - z.dy) / rand).clamp(0.2, 1.0);
    if (dx == 0 && dy == 0) {
      _randTimer?.cancel();
      _randTimer = null;
      return;
    }
    setState(() => _verschiebung += Offset(dx, dy));
    _zeigerBewegt(z, gedrueckt: _ziehStart != null);
  }

  /// Zeigerbewegung verarbeiten (auch wenn nur die Ansicht darunter wandert).
  void _zeigerBewegt(Offset bildschirm, {required bool gedrueckt}) {
    _zeiger = bildschirm;
    final welt = _zuWelt(bildschirm);
    if (_werkzeug == Werkzeug.auswahl && gedrueckt && !_ansichtZiehen) {
      _auswahlZiehen(welt);
    } else {
      setState(() {
        _maus = _werkzeug == Werkzeug.wand || _werkzeug == Werkzeug.mass ? _fangen(welt, _planLaden().waende) : null;
        _oeffnungVorschau = _werkzeug == Werkzeug.oeffnung ? _oeffnungVorschauBerechnen(welt, _planLaden()) : null;
        if (_maus == null) {
          _fangText = null;
          _fangLinie = null;
        }
      });
    }
    _randPruefen();
  }

  final _zf = ZweiFinger();

  /// Maus-/Stift-/Fingerdruck auf der Zeichenfläche.
  void _druck(PointerDownEvent e) {
              if (e.buttons == kPrimaryButton && _doppel.erkannt(e.localPosition)) {
                _eigFenster.nachKlickOeffnen(context, sperre: () => _auswahl.isNotEmpty || _massAuswahl != null || _winkelAuswahl != null);
              }
              if (e.buttons != kPrimaryMouseButton) return;
              if (_vorlageModus == 2) {
                _fokus.requestFocus();
                setState(() => _vorlageZiehStart = _zuWelt(e.localPosition));
                return;
              }
              if (_ansichtZiehen) {
                _fokus.requestFocus();
                return;
              }
              _klick(e.localPosition);
            }

  void _ansichtSchieben(Offset bildschirmDelta) => setState(() => _verschiebung += bildschirmDelta);

  void _zoomen(double faktor, Offset um) {
    final neu = (_massstab * faktor).clamp(0.005, 2.0).toDouble();
    final welt = _zuWelt(um);
    setState(() {
      _massstab = neu;
      _verschiebung = um - welt * neu;
    });
  }

  // ------------------------------------------------------ Maßeingabe

  int? get _eingabeLaenge {
    final l = int.tryParse(_laengeCtrl.text.trim());
    return l != null && l > 0 ? l : null;
  }

  double? get _eingabeWinkel => double.tryParse(_winkelCtrl.text.trim().replaceAll(',', '.'));

  /// Winkel einer Richtung in Grad: 0° = nach rechts, 90° = nach oben.
  static double winkelVon(Offset v) {
    final w = math.atan2(-v.dy, v.dx) * 180 / math.pi;
    return w < 0 ? w + 360 : w;
  }

  static String winkelText(double w) {
    final r = (w * 10).round() / 10;
    final t = r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1).replaceAll('.', ',');
    return '$t°';
  }

  /// Ende der Vorschauwand: Maus, oder aus eingegebener Länge und/oder Winkel.
  Offset? _vorschauEnde() {
    final start = _kettenStart;
    if (start == null) return null;
    final maus = _maus;
    final l = _eingabeLaenge;
    final w = _eingabeWinkel;
    if (l == null && w == null) return maus;
    if (_form == 1) {
      // Rechteck: Breite (Länge-Feld) und Tiefe (Winkel-Feld), Richtung von der Maus
      final m = maus ?? start + const Offset(1, 1);
      final bx = (m.dx >= start.dx ? 1 : -1) * (l ?? (m.dx - start.dx).abs().round());
      final ty = (m.dy >= start.dy ? 1 : -1) * (w?.round() ?? (m.dy - start.dy).abs().round());
      return start + Offset(bx.toDouble(), ty.toDouble());
    }
    Offset richtung;
    if (w != null) {
      final r = w * math.pi / 180;
      richtung = Offset(math.cos(r), -math.sin(r));
    } else {
      final v = (maus ?? start + const Offset(1, 0)) - start;
      richtung = v.distance < 1 ? const Offset(1, 0) : v / v.distance;
    }
    double laenge;
    if (l != null) {
      laenge = l + _massKorrektur(start, richtung);
    } else {
      final v = (maus ?? start) - start;
      laenge = math.max(0, v.dx * richtung.dx + v.dy * richtung.dy);
    }
    final e = start + richtung * laenge;
    return Offset(e.dx.roundToDouble(), e.dy.roundToDouble());
  }

  /// Unterschied Achsmaß − Innenmaß für eine Wand ab [start] in [richtung]:
  /// am Anfang so viel, wie die Innenseite an der vorhandenen Wand kürzer ist
  /// (ohne Anschluss: halbe Wanddicke), am Ende die halbe Dicke für die
  /// nächste, rechtwinklig anschließende Wand.
  double _abzugInnen(Offset start, Offset richtung) {
    final d = _zeichenDicke;
    final plan = _planLaden();
    const probe = 10000.0;
    final a = Punkt(start.dx, start.dy);
    final b = Punkt(start.dx + richtung.dx * probe, start.dy + richtung.dy * probe);
    final achse = WandAchse(a, b, d);
    final angeschlossen = plan.achsen.any((o) => _punktAufAchse(a, o));
    double anfang;
    if (angeschlossen) {
      final (l, r) = flankenLaengen(achse, [...plan.achsen, achse]);
      anfang = probe - math.min(l, r);
    } else {
      anfang = d / 2;
    }
    return anfang + d / 2;
  }

  /// Achsmaß − eingegebenes Maß (innen positiv, außen negativ).
  double _massKorrektur(Offset start, Offset richtung) => switch (_massBezug) {
        MassBezug.achse => 0,
        MassBezug.innen => _abzugInnen(start, richtung),
        MassBezug.aussen => -_zuschlagAussen(start, richtung),
      };

  /// Unterschied Außenmaß − Achsmaß, Gegenstück zu [_abzugInnen].
  double _zuschlagAussen(Offset start, Offset richtung) {
    final d = _zeichenDicke;
    final plan = _planLaden();
    const probe = 10000.0;
    final a = Punkt(start.dx, start.dy);
    final b = Punkt(start.dx + richtung.dx * probe, start.dy + richtung.dy * probe);
    final achse = WandAchse(a, b, d);
    final angeschlossen = plan.achsen.any((o) => _punktAufAchse(a, o));
    double anfang;
    if (angeschlossen) {
      final (l, r) = flankenLaengen(achse, [...plan.achsen, achse]);
      anfang = math.max(l, r) - probe;
    } else {
      anfang = d / 2;
    }
    return anfang + d / 2;
  }

  /// Umschalter Achsmaß / Innenmaß / Außenmaß.
  Widget _massBezugWahl(void Function(MassBezug) setzen) => SegmentedButton<MassBezug>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final b in MassBezug.values) ButtonSegment(value: b, label: Text(b.label), tooltip: b.erklaerung),
        ],
        selected: {_massBezug},
        onSelectionChanged: (s) => setzen(s.first),
      );

  static bool _punktAufAchse(Punkt p, WandAchse o) {
    final d = o.b - o.a;
    final l2 = d.skalar(d);
    if (l2 == 0) return (o.a - p).laenge <= 1;
    final t = ((p - o.a).skalar(d) / l2).clamp(0.0, 1.0);
    return (o.a + d * t - p).laenge <= 1;
  }

  /// Enter: Wand mit eingegebenem Maß setzen, Eingabe bleibt für die nächste Wand offen.
  void _eingabeAnwenden() {
    final start = _kettenStart;
    if (start == null || (_eingabeLaenge == null && _eingabeWinkel == null)) return;
    if (_form == 1) {
      final ende = _vorschauEnde();
      if (ende != null) _rechteckSetzen(start, ende);
      return;
    }
    final ende = _vorschauEnde();
    if (ende == null || (ende - start).distance < 1) return;
    setState(() {
      _wandSetzen(start, ende);
      _kettenStart = ende;
      _laengeCtrl.clear();
      _winkelCtrl.clear();
    });
    if (_winkelFokus.hasFocus) _laengeFokus.requestFocus();
  }

  void _eingabeLeeren() {
    _laengeCtrl.clear();
    _winkelCtrl.clear();
  }

  /// Tasten in den Eingabefeldern: Tab wechselt das Feld, Esc zurück zur Zeichnung.
  KeyEventResult _eingabeTaste(KeyEvent e, {required bool laenge}) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = TastenBelegung.uebersetzen(e.logicalKey);
    if (k == LogicalKeyboardKey.tab) {
      (laenge ? _winkelFokus : _laengeFokus).requestFocus();
      final c = laenge ? _winkelCtrl : _laengeCtrl;
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      setState(_eingabeLeeren);
      _fokus.requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _eingabeAnwenden();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Kern (tragende Schicht) und Aufbau je Seite.
  List<Widget> _kernFelder(Wand w, _Plan plan) {
    final store = _s.store!;
    final km = kernMaterial(w);
    String seite(bool links) => WandSeite.berechnen(w, plan.waende, plan.raeume, _eckenVerbinden, links).raum?.name ?? (links ? 'Seite A (außen)' : 'Seite B (außen)');
    String kurz(bool links) {
      final b = aufbau(w, links);
      if (b.isEmpty) return 'kein Aufbau';
      final s0 = b.first.schichten;
      final t = s0.map((x) => '${plan.materialien[x.material]?.name ?? '?'} ${x.dicke}').join(' + ');
      return b.length == 1 ? (t.isEmpty ? 'leer' : t) : '${b.length} Bereiche · $t …';
    }

    return [
      const SizedBox(height: 10),
      const Text('Kern (tragend, verbindet die Ecken)', style: TextStyle(fontWeight: FontWeight.w600)),
      Row(children: [
        Expanded(
          child: DropdownButton<String?>(
            isExpanded: true,
            value: plan.materialien.containsKey(km) ? km : null,
            hint: const Text('Baustoff des Kerns'),
            items: [
              for (final m in plan.materialien.values)
                DropdownMenuItem(value: m.id, child: Row(children: [Container(width: 12, height: 12, color: Color(m.farbe)), const SizedBox(width: 6), Expanded(child: Text(m.name, overflow: TextOverflow.ellipsis))])),
            ],
            onChanged: (v) {
              final alt = w.eigenschaften['kern'];
              store.wandEigenschaftenSetzen(w.id, {'kern': {...(alt as Map? ?? const {}), 'm': v, 'd': w.dicke}});
              _rueckgaengig.add(() => store.wandEigenschaftenSetzen(w.id, {'kern': alt}));
              _s.geaendert();
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: SpeicherFeld(
            key: ValueKey('kern-${w.id}-${w.dicke}'),
            initialValue: '${w.dicke}',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Kerndicke', suffixText: 'mm', isDense: true),
            onFieldSubmitted: (t) {
              final d = int.tryParse(t);
              if (d == null || d <= 0 || d == w.dicke) return;
              final koord = {for (final x in plan.waende) x.id: (x.x1, x.y1, x.x2, x.y2)};
              final alt = w.dicke, altK = w.eigenschaften['kern'];
              wandDickeMitInnenmass(store, w, () {
                store.wandAendern(w.id, dicke: d);
                store.wandEigenschaftenSetzen(w.id, {'kern': {...(altK as Map? ?? const {}), 'd': d}});
              });
              _rueckgaengig.add(() {
                store.wandAendern(w.id, dicke: alt);
                store.wandEigenschaftenSetzen(w.id, {'kern': altK});
                store.waendeKoordinatenSetzen(koord);
              });
              _s.geaendert();
            },
          ),
        ),
      ]),
      for (final links in [true, false])
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('Aufbau ${seite(links)}'),
          subtitle: Text(kurz(links), maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: () {
            final alt = w.eigenschaften[links ? 'aufbau_l' : 'aufbau_r'];
            aufbauDialog(context, store, w, links, seite(links), geaendert: _s.geaendert).then((_) {
              _rueckgaengig.add(() => store.wandEigenschaftenSetzen(w.id, {links ? 'aufbau_l' : 'aufbau_r': alt}));
              if (mounted) setState(() {});
            });
          },
        ),
    ];
  }

  /// Teilstück einer durchgehenden Wand mit eigenem Wandtyp: Wand an „von“
  /// und „bis“ teilen, dem Mittelstück den Typ geben (Innenseite bleibt fest).
  /// Die Stücke bleiben automatisch verbunden. Strg+Z stellt alles wieder her.
  Future<void> _teilstueckDialog(Wand w, _Plan plan) async {
    final store = _s.store!;
    final raeume = store.raeume(w.geschossId);
    final stuecke = <(String, double, double)>[
      for (final links in [true, false])
        for (final e in raumStuecke(w, links, raeume).entries)
          (raeume.where((r) => r.id == e.key).firstOrNull?.name ?? 'Raum', e.value.$1, e.value.$2),
    ];
    final von = TextEditingController(text: '0'), bis = TextEditingController(text: '${w.laenge.round()}');
    String? typId = w.wandtypId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Teilstück mit eigenem Wandtyp'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Wand ${mmText(w.laenge.round())} lang. Das Stück zwischen „von“ und „bis“ (ab Wandanfang) bekommt den gewählten Wandtyp; '
                  'die Ecken verbinden sich weiter automatisch.', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              if (stuecke.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Schnell: Stück an einem Raum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Wrap(spacing: 6, children: [
                  for (final (n, a, b) in stuecke)
                    ActionChip(
                      label: Text('$n (${mmText(a.round())}–${mmText(b.round())})'),
                      onPressed: () => setD(() {
                        von.text = '${a.round()}';
                        bis.text = '${b.round()}';
                      }),
                    ),
                ]),
              ],
              Row(children: [
                Expanded(child: TextField(controller: von, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'von', suffixText: 'mm'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: bis, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'bis', suffixText: 'mm'))),
              ]),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: typId,
                decoration: const InputDecoration(labelText: 'Wandtyp des Teilstücks'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('ohne (freie Dicke)')),
                  for (final t in plan.typen) DropdownMenuItem(value: t.id, child: Text('${t.name} · ${t.dicke} mm', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => typId = v,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Teilen und zuweisen')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final a = (double.tryParse(von.text.trim()) ?? 0).clamp(0.0, w.laenge), b = (double.tryParse(bis.text.trim()) ?? w.laenge).clamp(0.0, w.laenge);
    if (b - a < 20) return;
    // Stand vorher für Strg+Z
    Map<String, Object?> zeile(Map<String, Object?> r) => {for (final k in r.keys) k: r[k]};
    final vorher = [
      for (final r in store.db.select('SELECT * FROM wand WHERE geschoss_id = ?', [w.geschossId])) {'t': 'wand', 'id': r['id'], 'zeile': zeile(r)},
      for (final r in store.db.select('SELECT o.* FROM oeffnung o JOIN wand x ON x.id = o.wand_id WHERE x.geschoss_id = ?', [w.geschossId]))
        {'t': 'oeffnung', 'id': r['id'], 'zeile': zeile(r)},
    ];
    final idsVorher = {for (final x in vorher) if (x['t'] == 'wand') x['id']};
    String mitte = w.id;
    if (b < w.laenge - 10) store.wandTeilen(w.id, b);
    if (a > 10) mitte = store.wandTeilen(w.id, a) ?? w.id;
    final m = store.waende(w.geschossId).where((x) => x.id == mitte).firstOrNull;
    if (m != null && m.wandtypId != typId) {
      wandDickeMitInnenmass(store, m, () => typId == null ? store.wandAendern(m.id, dicke: w.dicke) : store.wandWandtypSetzen(m.id, typId));
    }
    _rueckgaengig.add(() {
      for (final x in store.waende(w.geschossId)) {
        if (!idsVorher.contains(x.id)) store.db.execute('DELETE FROM wand WHERE id = ?', [x.id]);
      }
      aenderungenAnwenden(store, [for (final x in vorher) Map<String, dynamic>.from(x)]);
    });
    setState(() => _auswahl = {mitte});
    _s.geaendert();
  }

  /// Parallele Nachbarwände in Verlängerung mit versetzter Achse (Absatz):
  /// Knöpfe, um eine Seite oder die Achse bündig zu machen.
  List<Widget> _fluchtFelder(Wand w) {
    final store = _s.store!;
    if (w.laenge < 1 || w.gesperrt) return const [];
    final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge;
    final nlx = uy, nly = -ux;
    final alle = store.waende(w.geschossId);
    final raeume = store.raeume(w.geschossId);
    final mm = wandMasse(alle, raeume, verbindenStandard: _eckenVerbinden)[w.id];
    String seite(String? raumId, String sonst) => raeume.where((r) => r.id == raumId).firstOrNull?.name ?? sonst;
    final aus = <Widget>[];
    for (final o in alle) {
      if (o.id == w.id || o.laenge < 1 || o.istKante || o.teilhoch) continue;
      final ox = (o.x2 - o.x1) / o.laenge, oy = (o.y2 - o.y1) / o.laenge;
      if ((ox * uy - oy * ux).abs() > 0.01) continue; // nicht parallel
      final off = (o.x1 - w.x1) * nlx + (o.y1 - w.y1) * nly;
      if (off.abs() < 1 || off.abs() > 400) continue;
      // in Verlängerung: ein Ende der Nachbarwand nahe einem Ende dieser Wand (entlang der Achse)
      double t(int x, int y) => (x - w.x1) * ux + (y - w.y1) * uy;
      final ts = [t(o.x1, o.y1), t(o.x2, o.y2)];
      if (!ts.any((v) => v.abs() < 400 || (v - w.laenge).abs() < 400)) continue;
      final hw = w.dicke / 2, ho = o.dicke / 2;
      final varianten = <(String, double)>[
        ('Seite ${seite(mm?.raumLinks, 'außen')} bündig', off + ho - hw),
        ('Seite ${seite(mm?.raumRechts, 'außen')} bündig', off - ho + hw),
        ('Achse fluchten', off),
      ];
      aus.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Absatz zur Nachbarwand (${mmText(off.abs().round())} versetzt) – bündig machen:', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
      ));
      aus.add(Wrap(spacing: 6, runSpacing: 4, children: [
        for (final (text, d) in varianten)
          if (d.abs() >= 1)
            OutlinedButton(
              onPressed: () {
                store.wandQuerVersetzen(w.id, d);
                _rueckgaengig.add(() => store.wandQuerVersetzen(w.id, -d));
                _s.geaendert();
              },
              child: Text(text),
            ),
      ]));
      break;
    }
    return aus;
  }

  /// Wände am Rand eines Balkons/einer Terrasse, hinter denen kein Innenraum
  /// liegt, zur offenen Kante machen (rückgängig machbar).
  void _raenderAlsKante(Raum r) {
    final store = _s.store!;
    final u = r.umriss!;
    final innen = [for (final x in store.raeume(r.geschossId)) if (x.id != r.id && x.art == RaumArt.raum && x.umriss != null) x.umriss!];
    final alt = <String, Map<String, Object?>>{};
    for (final w in store.waende(r.geschossId)) {
      if (w.istKante || w.teilhoch || w.laenge < 1) continue;
      final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge;
      final mx = (w.x1 + w.x2) / 2, my = (w.y1 + w.y2) / 2;
      final d = w.dicke / 2 + 60;
      final a = Punkt(mx - uy * d, my + ux * d), b = Punkt(mx + uy * d, my - ux * d);
      final anA = punktInPolygon(a, u), anB = punktInPolygon(b, u);
      if (anA == anB) continue; // grenzt nicht an diesen Raum
      final andere = anA ? b : a;
      if (innen.any((p) => punktInPolygon(andere, p))) continue; // dahinter liegt ein Innenraum: echte Wand
      alt[w.id] = {'art': w.eigenschaften['art'], 'hoehe': w.eigenschaften['hoehe'], 'gelaender': w.eigenschaften['gelaender']};
      store.wandEigenschaftenSetzen(w.id, {'art': 'kante', 'hoehe': null, 'gelaender': true});
    }
    if (alt.isEmpty) {
      zeigeHinweis(context, 'Keine Außenwand an diesem Raum gefunden.');
      return;
    }
    _rueckgaengig.add(() {
      for (final e in alt.entries) {
        store.wandEigenschaftenSetzen(e.key, e.value);
      }
    });
    _s.geaendert();
    zeigeHinweis(context, '${alt.length} Wand/Wände als offene Kante mit Geländer – Strg+Z macht es rückgängig');
  }

  void _auswahlLoeschen() {
    final store = _s.store!;
    final ids = _auswahl.toList();
    final oe = _oeffnungAuswahl;
    if (oe != null) {
      store.oeffnungLoeschen(oe);
      _rueckgaengig.add(() => store.oeffnungWiederherstellen(oe));
      setState(() => _oeffnungAuswahl = null);
      _s.geaendert();
      return;
    }
    final wm = _winkelAuswahl;
    if (wm != null) {
      store.winkelmassLoeschen(wm);
      _rueckgaengig.add(() => store.winkelmassWiederherstellen(wm));
      setState(() => _winkelAuswahl = null);
      _s.geaendert();
      return;
    }
    final bm = _massAuswahl;
    if (bm != null) {
      store.bemassungLoeschen(bm);
      _rueckgaengig.add(() => store.bemassungWiederherstellen(bm));
      setState(() => _massAuswahl = null);
      _s.geaendert();
      return;
    }
    if (ids.isNotEmpty) {
      for (final id in ids) {
        store.wandLoeschen(id);
      }
      _rueckgaengig.add(() {
        for (final id in ids) {
          store.wandWiederherstellen(id);
        }
      });
      setState(() => _auswahl = {});
      _s.geaendert();
      return;
    }
    final raum = _s.raumId;
    if (raum != null) _raumLoeschen(raum);
  }

  void _raumLoeschen(String id) {
    final store = _s.store!;
    store.raumLoeschen(id);
    _rueckgaengig.add(() => store.raumWiederherstellen(id));
    _s.raumWaehlen(null);
    _s.geaendert();
  }

  void _rueckgaengigMachen() {
    if (_rueckgaengig.isEmpty) return;
    _rueckgaengig.removeLast()();
    setState(() {
      _auswahl = {};
      _freieAuswahl = null;
    });
    _s.geaendert();
  }

  void _einpassen() {
    final waende = _planLaden().waende;
    if (waende.isEmpty || _flaeche.isEmpty) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final w in waende) {
      minX = math.min(minX, math.min(w.x1, w.x2).toDouble());
      minY = math.min(minY, math.min(w.y1, w.y2).toDouble());
      maxX = math.max(maxX, math.max(w.x1, w.x2).toDouble());
      maxY = math.max(maxY, math.max(w.y1, w.y2).toDouble());
    }
    final breite = math.max(1000.0, maxX - minX);
    final hoehe = math.max(1000.0, maxY - minY);
    final m = math.min((_flaeche.width - 120) / breite, (_flaeche.height - 120) / hoehe);
    setState(() {
      _massstab = m.clamp(0.005, 2.0).toDouble();
      _verschiebung = Offset(
        (_flaeche.width - breite * _massstab) / 2 - minX * _massstab,
        (_flaeche.height - hoehe * _massstab) / 2 - minY * _massstab,
      );
    });
  }


  /// Richtet die Wand [_parallelFuer] parallel zu [ziel] aus: das Ende
  /// („ändern am“) dreht um das andere Ende, die Länge bleibt.
  void _parallelAusrichten(String ziel, _Plan plan) {
    final id = _parallelFuer;
    setState(() => _parallelFuer = null);
    final w = plan.waende.where((e) => e.id == id).firstOrNull;
    final z = plan.waende.where((e) => e.id == ziel).firstOrNull;
    if (w == null || z == null || w.id == z.id) return;
    final zu = Offset((z.x2 - z.x1).toDouble(), (z.y2 - z.y1).toDouble());
    if (zu.distance < 1) return;
    var u = zu / zu.distance;
    final fest = _amAnfang ? Offset(w.x2.toDouble(), w.y2.toDouble()) : Offset(w.x1.toDouble(), w.y1.toDouble());
    final bewegt = _amAnfang ? Offset(w.x1.toDouble(), w.y1.toDouble()) : Offset(w.x2.toDouble(), w.y2.toDouble());
    final jetzt = bewegt - fest;
    if (jetzt.dx * u.dx + jetzt.dy * u.dy < 0) u = -u;
    final ziel2 = fest + u * w.laenge;
    final store = _s.store!;
    final alt = store.wandEndeVersetzen(w.id, amAnfang: _amAnfang, x: ziel2.dx.round(), y: ziel2.dy.round());
    if (alt.isEmpty) {
      zeigeFehler(context, 'Geht nicht – die Wand oder eine anschließende Wand ist gesperrt (oder sie ist schon parallel).');
      return;
    }
    _rueckgaengig.add(() => store.waendeKoordinatenSetzen(alt));
    _s.geaendert();
  }

  /// Wand über ihr Ende hinaus verlängern: Wandwerkzeug, Kette beginnt am Ende
  /// mit der Richtung der Wand – Länge eintippen (Tab) oder klicken.
  void _verlaengernStarten(Wand w) {
    final a = Offset(w.x1.toDouble(), w.y1.toDouble()), b = Offset(w.x2.toDouble(), w.y2.toDouble());
    final (start, richtung) = _amAnfang ? (a, a - b) : (b, b - a);
    setState(() {
      _werkzeug = Werkzeug.wand;
      _auswahl = {};
      _eingabeLeeren();
      _kettenStart = start;
      _winkelCtrl.text = winkelText(winkelVon(richtung)).replaceAll('°', '').replaceAll(',', '.');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _laengeFokus.requestFocus();
    });
  }
  void _werkzeugWaehlen(Werkzeug w) => setState(() {
        _werkzeug = w;
        _kettenStart = null;
        _eingabeLeeren();
        _massA = null;
        _massB = null;
      });

  KeyEventResult _taste(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent && e.logicalKey == LogicalKeyboardKey.space) {
      _ansichtZiehen = false;
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.f1) {
      tastenkuerzelZeigen(context, einstellungen: _s.settings);
      return KeyEventResult.handled;
    }
    final k = TastenBelegung.uebersetzen(e.logicalKey);
    final strg = HardwareKeyboard.instance.isControlPressed;
    if (strg && k == LogicalKeyboardKey.keyZ) {
      _rueckgaengigMachen();
      return KeyEventResult.handled;
    }
    if (strg && k == LogicalKeyboardKey.keyA) {
      _alleWaehlen();
      return KeyEventResult.handled;
    }
    if (_plattePunkte.isNotEmpty && (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter)) {
      _platteAbschliessen();
      return KeyEventResult.handled;
    }
    if (_plattePunkte.isNotEmpty && k == LogicalKeyboardKey.backspace) {
      setState(_plattePunkte.removeLast);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space) {
      _ansichtZiehen = true; // Leertaste halten + ziehen = Ansicht verschieben
      return KeyEventResult.handled;
    }
    final pfeil = switch (k) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    if (pfeil != null) {
      if (_auswahl.isNotEmpty) {
        // Auswahl um einen Rasterschritt verschieben, mit Umschalt zehn.
        final schritt = _rasterMm * (HardwareKeyboard.instance.isShiftPressed ? 10 : 1);
        _auswahlVerschieben((pfeil.dx * schritt).round(), (pfeil.dy * schritt).round());
      } else {
        _ansichtSchieben(-pfeil * 80);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      setState(() {
        _kettenStart = null;
        _parallelFuer = null;
        _plattePunkte.clear();
        _eingabeLeeren();
        _massA = null;
        _massB = null;
        _massAuswahl = null;
        _winkelAuswahl = null;
        _winkelErste = null;
        _oeffnungAuswahl = null;
        _vorlageModus = 0;
        _kalibrierPunkte = [];
        _auswahl = {};
        _freieAuswahl = null;
        _rahmen = null;
        _ziehStart = null;
        _verschiebtAuswahl = false;
        _versatz = Offset.zero;
      });
      _s.raumWaehlen(null);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      _auswahlLoeschen();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _eingabeAnwenden();
      return KeyEventResult.handled;
    }
    if (_kettenStart == null && _werkzeug == Werkzeug.wand && k == LogicalKeyboardKey.tab) {
      // Tab über einer Wand: Startpunkt mit Abstand vom näheren Wandende eingeben
      final w = _fangWand, m = _maus;
      if (w != null && m != null) {
        final da = (m - Offset(w.x1.toDouble(), w.y1.toDouble())).distance;
        setState(() {
          _abstandWand = w;
          _abstandVonA = da <= w.laenge / 2;
          _abstandCtrl.text = (_abstandVonA ? da : w.laenge - da).round().toString();
          _abstandCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _abstandCtrl.text.length);
        });
      } else {
        zeigeHinweis(context, 'Für einen Startpunkt mit Abstand die Maus auf eine Wand stellen und Tab drücken.');
      }
      return KeyEventResult.handled;
    }
    if (_kettenStart != null && k == LogicalKeyboardKey.tab) {
      // Tab: in die Längeneingabe springen (nochmal Tab → Winkel)
      setState(() {});
      _laengeFokus.requestFocus();
      _laengeCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _laengeCtrl.text.length);
      return KeyEventResult.handled;
    }
    final zeichen = e.character;
    if (_kettenStart != null && zeichen != null && RegExp(r'^\d$').hasMatch(zeichen)) {
      // Ziffer tippen startet die Längeneingabe direkt
      setState(() => _laengeCtrl.text = zeichen);
      _laengeFokus.requestFocus();
      _laengeCtrl.selection = const TextSelection.collapsed(offset: 1);
      return KeyEventResult.handled;
    }
    if (_kettenStart == null && !strg) {
      final w = switch (k) {
        LogicalKeyboardKey.keyW => Werkzeug.wand,
        LogicalKeyboardKey.keyV => Werkzeug.auswahl,
        LogicalKeyboardKey.keyR => Werkzeug.raum,
        LogicalKeyboardKey.keyM => Werkzeug.mass,
        LogicalKeyboardKey.keyK => Werkzeug.winkel,
        LogicalKeyboardKey.keyO => Werkzeug.oeffnung,
        _ => null,
      };
      if (w != null) {
        _werkzeugWaehlen(w);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (_geschossBeiLetztemBuild != _s.geschossId) {
      _geschossBeiLetztemBuild = _s.geschossId;
      _kettenStart = null;
      _auswahl = {};
      _freieAuswahl = null;
      _eingepasst = false;
      _rueckgaengig.clear();
    }
    final plan = _planLaden();
    _vorlageBildPruefen(plan.vorlage);
    if (_wandtypId != null && _gewaehlterTyp == null) _wandtypId = null; // Typ gelöscht
    // Gelöschte oder fremde Wände fallen aus der Auswahl.
    final gewaehlt = plan.waende.where((w) => _auswahl.contains(w.id)).toList();
    if (gewaehlt.length != _auswahl.length) _auswahl = {for (final w in gewaehlt) w.id};
    final auswahl = gewaehlt.length == 1 ? gewaehlt.single : null;
    final raum = plan.raeume.where((r) => r.id == _s.raumId).firstOrNull;
    final frei = _freieAuswahl;
    // Nach Datenänderungen gehört die freie Auswahl evtl. zu einer alten Berechnung.
    final freiAktuell = frei == null
        ? null
        : plan.flaechen.where((f) => f.enthaelt(frei.innenpunkt) && plan.raeumeIn(f).isEmpty).firstOrNull;
    Widget seitenInhalt() => _oeffnungAuswahl != null && plan.oeffnungen.any((o) => o.id == _oeffnungAuswahl)
              ? _oeffnungEigenschaften(plan.oeffnungen.firstWhere((o) => o.id == _oeffnungAuswahl), plan)
              : _winkelAuswahl != null && plan.winkelmasse.any((m) => m.id == _winkelAuswahl)
              ? _winkelEigenschaften(plan.winkelmasse.firstWhere((m) => m.id == _winkelAuswahl), plan)
              : _massAuswahl != null && plan.bemassungen.any((b) => b.id == _massAuswahl)
              ? _bemassungEigenschaften(plan.bemassungen.firstWhere((b) => b.id == _massAuswahl))
              : auswahl != null
              ? _wandEigenschaften(auswahl, plan)
              : gewaehlt.length > 1
                  ? _mehrfachAuswahl(gewaehlt, plan)
                  : raum != null
                  ? _raumEigenschaften(raum, plan)
                  : freiAktuell != null
                      ? _freieFlaeche(freiAktuell)
                      : _hilfe(plan);
    final etwasGewaehlt = _oeffnungAuswahl != null || _winkelAuswahl != null || _massAuswahl != null || gewaehlt.isNotEmpty || raum != null || freiAktuell != null;
    _eigFenster.setzen(
      auswahl: etwasGewaehlt,
      bauen: seitenInhalt,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProjectTree(state: _s),
        Expanded(
          child: Column(
            children: [
              _werkzeugleiste(plan),
              Expanded(
                child: _s.geschossId == null
                    ? const Center(child: Text('Links ein Geschoss wählen oder anlegen.'))
                    : ClipRect(child: _zeichenflaeche(plan, raum, freiAktuell)),
              ),
              _statuszeile(),
            ],
          ),
        ),
        if ((etwasGewaehlt && !_seiteZu) || (!etwasGewaehlt && _s.settings.hilfeAnzeigen))
          Container(
            width: 300,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: BsFarben.rand)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: etwasGewaehlt ? 'Eigenschaften einklappen' : 'Hilfe ausblenden',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    if (etwasGewaehlt) {
                      _seiteZu = true;
                    } else {
                      _s.settings.hilfeAnzeigen = false;
                      _s.settings.speichern();
                    }
                  }),
                  icon: const Icon(Icons.keyboard_double_arrow_right),
                ),
              ),
              Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: _eigFenster.seitenleiste(seitenInhalt))),
            ]),
          )
        else
          // eingeklappt: schmale Leiste zum Wiederaufklappen
          Material(
            color: Colors.white,
            child: InkWell(
              onTap: () => setState(() {
                if (etwasGewaehlt) {
                  _seiteZu = false;
                } else {
                  _s.settings.hilfeAnzeigen = true;
                  _s.settings.speichern();
                }
              }),
              child: Container(
                width: 28,
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: BsFarben.rand))),
                child: Column(children: [
                  const SizedBox(height: 10),
                  const Icon(Icons.keyboard_double_arrow_left, size: 18, color: BsFarben.textLeise),
                  const SizedBox(height: 8),
                  RotatedBox(
                    quarterTurns: 1,
                    child: Text(etwasGewaehlt ? 'Eigenschaften' : 'Hilfe', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                  ),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _werkzeugleiste(_Plan plan) {
    Widget knopf(Werkzeug w, IconData icon, String tip) => WerkzeugKnopf(
          symbol: icon,
          text: tip.split(' (').first.split(' /').first,
          tooltip: tip,
          aktiv: _werkzeug == w,
          onTap: () => _werkzeugWaehlen(w),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: BsFarben.rand)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: const Color(0xFFF0F1ED), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              knopf(Werkzeug.auswahl, Sym.auswahl, 'Auswahl (V)'),
              knopf(Werkzeug.wand, Sym.wand, 'Wand (W)'),
              knopf(Werkzeug.raum, Sym.raum, 'Raum (R): in einen geschlossenen Wandzug klicken'),
              knopf(Werkzeug.oeffnung, Sym.oeffnung, 'Öffnung (O): Tür, Fenster oder Durchbruch in eine Wand klicken'),
              knopf(Werkzeug.mass, Sym.bemassen, 'Maß (M): zwei Punkte klicken, dann Maßlinie setzen'),
              knopf(Werkzeug.winkel, Sym.winkel, 'Winkel (K): zwei Wände mit gemeinsamer Ecke anklicken'),
            ]),
          ),
          if (_werkzeug == Werkzeug.wand) ...[
          _auswahlFeld<String?>(
            'Wandtyp',
            _wandtypId,
            [null, ...plan.typen.map((t) => t.id)],
            (v) {
              final t = plan.typen.where((e) => e.id == v).firstOrNull;
              return t == null ? 'ohne (freie Dicke)' : '${t.name} · ${t.dicke} mm';
            },
            (v) => setState(() => _wandtypId = v),
          ),
          if (_wandtypId == null)
            _auswahlFeld<int>('Dicke', _wandDicke, _dicken, (v) => '$v mm', (v) => setState(() => _wandDicke = v)),
          IconButton(
            tooltip: 'Wandaufbauten bearbeiten (Wandtypen)',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(
                    builder: (_) => Scaffold(appBar: AppBar(title: const Text('Wandaufbauten')), body: WandtypenAnsicht(state: _s))))
                .then((_) => mounted ? setState(() {}) : null),
            icon: const Icon(Icons.layers_outlined),
          ),
          _auswahlFeld<WandZustand>('Zustand', _zustand, WandZustand.values, (v) => v.label,
              (v) => setState(() => _zustand = v)),
          ],
          _auswahlFeld<int>('Raster', _rasterMm, _raster, (v) => '$v mm', (v) => setState(() => _rasterMm = v)),
          if (_werkzeug == Werkzeug.wand) ...[
          Tooltip(
            message: 'Wand zeichnen als Linienzug oder als Rechteck (zwei Ecken bzw. Tab: Breite × Tiefe) – das Rechteck wird gleich als Raum angelegt.',
            child: _auswahlFeld<int>('Form', _form, const [0, 1], (v) => v == 0 ? 'Linienzug' : 'Rechteck (Raum)', (v) => setState(() {
                  _form = v;
                  _kettenStart = null;
                  _werkzeug = Werkzeug.wand;
                })),
          ),
          ],
          if (_werkzeug == Werkzeug.raum)
          Tooltip(
            message: 'Raumwerkzeug (R):Räume entstehen aus geschlossenen Wandzügen. Balkon, Terrasse oder Loggia ohne '
                'Wände: Umriss der Bodenplatte Punkt für Punkt klicken, Klick auf den ersten Punkt oder Enter schließt.',
            child: _auswahlFeld<bool>('Raum', _bodenplatte, const [false, true], (v) => v ? 'Bodenplatte (Balkon …)' : 'aus Wänden',
                (v) => setState(() {
                      _bodenplatte = v;
                      _plattePunkte.clear();
                      _werkzeug = Werkzeug.raum;
                    })),
          ),
          if (_werkzeug == Werkzeug.wand || _werkzeug == Werkzeug.auswahl) ...[
          if (_werkzeug == Werkzeug.wand)
          Tooltip(
            message: 'Winkelfang beim Zeichnen. „frei“ rastet nur nahe waagerecht/senkrecht ein; '
                'Umschalt erzwingt immer 90°. Jeder Winkel geht auch per Tab-Eingabe.',
            child: _auswahlFeld<int>('Winkel', _winkelFang, const [0, 15, 30, 45],
                (v) => v == 0 ? 'frei' : '$v°-Schritte', (v) => setState(() => _winkelFang = v)),
          ),
          Tooltip(
            message: 'Wie eingetippte Wandlängen gemeint sind – beim Zeichnen (Tab) und rechts bei einer '
                'gewählten Wand. Achsmaß: Wandmitte bis Wandmitte. Innenmaß: Raumseite bis zur '
                'Innenseite der anschließenden Wand. Außenmaß: Außenseite bis Außenseite.',
            child: _auswahlFeld<MassBezug>('Längen als', _massBezug, MassBezug.values, (v) => v.label,
                (v) => setState(() => _massBezug = v)),
          ),
          _massFeld(plan),
          ],
          if (_werkzeug == Werkzeug.mass)
            Tooltip(
              message: 'Wie die Maßlinie ausgerichtet wird: direkt zwischen den Punkten, waagerecht, senkrecht oder parallel zur Wand am ersten Punkt.',
              child: _auswahlFeld<int>('Maß', _massAusrichtung, const [0, 1, 2, 3],
                  (v) => const ['direkt (Punkt zu Punkt)', 'waagerecht', 'senkrecht', 'parallel zur Wand'][v], (v) => setState(() {
                        _massAusrichtung = v;
                        _massB = null;
                      })),
            ),
          if (_werkzeug == Werkzeug.mass || _werkzeug == Werkzeug.auswahl)
          PopupMenuButton<String>(
            tooltip: 'Eigene Bemaßungen und Winkelmaße ein- oder ausblenden',
            onSelected: (a) {
              final store = _s.store!;
              if (a == 'alle') {
                store.einstellungSetzen('bemassungen_sichtbar', !_bemassungenSichtbar);
              } else if (a == 'zeigen' && _s.geschossId != null) {
                final ids = store.versteckteMasseZeigen(_s.geschossId!);
                _rueckgaengig.add(() {
                  for (final (t, id) in ids) {
                    store.massVerstecken(t, id, true);
                  }
                });
              }
              _s.geaendert();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'alle', child: Text(_bemassungenSichtbar ? 'Alle eigenen Maße ausblenden' : 'Eigene Maße einblenden')),
              const PopupMenuItem(value: 'zeigen', child: Text('Einzeln ausgeblendete wieder zeigen')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_bemassungenSichtbar ? Sym.einblenden : Sym.ausblenden, size: 18),
                const SizedBox(width: 4),
                const Text('Eigene Maße'),
              ]),
            ),
          ),
          if (_werkzeug == Werkzeug.winkel)
            _auswahlFeld<int>('Winkel am', _winkelBezug, const [0, 1, 2], (v) => const ['Achse', 'Innenecke', 'Außenecke'][v], (v) {
              _s.store!.einstellungSetzen('winkel_bezug', v);
              _s.geaendert();
            }),
          if (_werkzeug == Werkzeug.oeffnung) ...[
            _auswahlFeld<OeffnungsArt>('Art', _oeffnungArt, OeffnungsArt.values, (v) => v.label, (v) => setState(() {
                  _oeffnungArt = v;
                  _oeffnungBreite = v.standard.$1;
                })),
            _auswahlFeld<int>('Breite', _oeffnungBreite, _oeffnungsBreiten[_oeffnungArt]!, (v) => '$v mm',
                (v) => setState(() => _oeffnungBreite = v)),
          ],
          _vorlageMenue(plan),
          // Seltene Projekteinstellungen gebündelt in einem Menü
          PopupMenuButton<String>(
            tooltip: 'Optionen: Ecken verbinden, neue Wände, Maße je Zoom',
            icon: const Icon(Icons.tune),
            onSelected: (a) {
              switch (a) {
                case 'ecken':
                  _s.store!.einstellungSetzen('ecken_verbinden', !_eckenVerbinden);
                  _s.geaendert();
                case 'neu_std':
                  setState(() => _neueVerbinden = null);
                case 'neu_an':
                  setState(() => _neueVerbinden = true);
                case 'neu_aus':
                  setState(() => _neueVerbinden = false);
                case 'mass_dichter' || 'mass_lockerer' || 'schrift_groesser' || 'schrift_kleiner' || 'mass_zurueck':
                  final d = _s.settings.darstellung;
                  double w(String k) => (d[k] as num?)?.toDouble() ?? 1;
                  setState(() {
                    switch (a) {
                      case 'mass_dichter':
                        d['mass_dichte'] = (w('mass_dichte') / 1.25).clamp(0.5, 3.0);
                      case 'mass_lockerer':
                        d['mass_dichte'] = (w('mass_dichte') * 1.25).clamp(0.5, 3.0);
                      case 'schrift_groesser':
                        d['mass_schrift'] = (w('mass_schrift') * 1.15).clamp(0.7, 2.0);
                      case 'schrift_kleiner':
                        d['mass_schrift'] = (w('mass_schrift') / 1.15).clamp(0.7, 2.0);
                      default:
                        d
                          ..remove('mass_dichte')
                          ..remove('mass_schrift')
                          ..remove('mass_ab')
                          ..remove('beide_ab');
                    }
                  });
                  _s.settings.speichern();
                case 'wandmodell_zurueck':
                  final gz = _s.geschossId;
                  if (gz != null) {
                    frage(context,
                            titel: 'Wandmodell zurücksetzen?',
                            text: 'Die Wände dieses Geschosses bekommen den Stand vor der Umstellung auf „Kern + Aufbau“ zurück (Lage, Dicke, Wandtyp). '
                                'Änderungen an Wänden seit der Umstellung gehen dabei verloren.',
                            ja: 'Zurücksetzen')
                        .then((ok) {
                      if (ok && _s.store!.wandmodellZurueck(gz)) _s.geaendert();
                    });
                  }
                case 'gelaende':
                  gelaendeDialog(context, _s);
                case 'sonne':
                  sonneDialog(context, _s);
                case 'sparren_neu':
                  if (_s.geschossId != null) {
                    sparrenDialogZeigen(context, _s, _s.geschossId!).then((_) {
                      if (mounted) setState(() {});
                    });
                  }
                case 'sparren_aus':
                  setState(() => _s.settings.darstellung['sparren_aus'] = _s.settings.darstellung['sparren_aus'] != true);
                  _s.settings.speichern();
                case 'raster':
                  setState(() => _s.settings.darstellung['raster_aus'] = _s.settings.darstellung['raster_aus'] != true);
                  _s.settings.speichern();
                case 'schwellen':
                  masseSchwellenDialog(context, _s).then((_) {
                    if (mounted) setState(() {});
                  });
                case 'unterlage':
                  setState(() => _s.settings.darstellung['geschoss_darunter'] = !_unterlage);
                  _s.settings.speichern();
                case 'statiker':
                  statikerMappeErstellen(context, _s);
                case 'fassade':
                  if (_s.geschossId != null) fassadeDialog(context, _s);
                case 'keller':
                  if (_s.geschossId != null) kellerSockelDialog(context, _s);
                case 'raumbild':
                  if (_s.geschossId != null) raumbildDialog(context, _s);
                case 'dach':
                  if (_s.geschossId != null) {
                    dachBearbeiten(context, _s.store!, _s.geschossId!, () {
                      _s.geaendert();
                      if (mounted) setState(() {});
                    });
                  }
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'ecken', checked: _eckenVerbinden, child: const Text('Ecken verbinden (Gehrung/T-Stoß), Projektvorgabe')),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false, child: Text('Neue Wände')),
              CheckedPopupMenuItem(value: 'neu_std', checked: _neueVerbinden == null, child: const Text('wie Projektvorgabe')),
              CheckedPopupMenuItem(value: 'neu_an', checked: _neueVerbinden == true, child: const Text('verbinden')),
              CheckedPopupMenuItem(value: 'neu_aus', checked: _neueVerbinden == false, child: const Text('nicht verbinden')),
              const PopupMenuDivider(),
              PopupMenuItem(
                  enabled: false,
                  child: Text('Maße im Plan (je Zoom): Dichte ${((_s.settings.darstellung['mass_dichte'] as num?)?.toDouble() ?? 1).toStringAsFixed(2).replaceAll('.', ',')}, '
                      'Schrift ${(((_s.settings.darstellung['mass_schrift'] as num?)?.toDouble() ?? 1) * 100).round()} %')),
              const PopupMenuItem(value: 'mass_dichter', child: Text('Mehr Maße zeigen (dichter)')),
              const PopupMenuItem(value: 'mass_lockerer', child: Text('Weniger Maße zeigen (lockerer)')),
              const PopupMenuItem(value: 'schrift_groesser', child: Text('Maßschrift größer')),
              const PopupMenuItem(value: 'schrift_kleiner', child: Text('Maßschrift kleiner')),
              const PopupMenuItem(value: 'schwellen', child: Text('Ab welchem Zoom Maße erscheinen …')),
              const PopupMenuItem(value: 'mass_zurueck', child: Text('Maße zurücksetzen')),
              CheckedPopupMenuItem(value: 'raster', checked: _s.settings.darstellung['raster_aus'] == true, child: const Text('Raster ausblenden')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'dach', child: ListTile(dense: true, leading: Icon(Icons.roofing), title: Text('Dachgeschoss: Dach, Sparren, Kniestock …'))),
              if (_s.geschossId != null && _s.store!.einstellung<Map>('wandmodell_vorher_${_s.geschossId}') != null)
                const PopupMenuItem(value: 'wandmodell_zurueck', child: ListTile(dense: true, leading: Icon(Icons.restore), title: Text('Wandmodell: alten Stand wiederherstellen …'))),
              const PopupMenuItem(value: 'sonne', child: ListTile(dense: true, leading: Icon(Icons.wb_sunny_outlined), title: Text('Sonne, Verschattung, PV …'))),
              const PopupMenuItem(value: 'gelaende', child: ListTile(dense: true, leading: Icon(Icons.landscape_outlined), title: Text('Gelände ums Haus …'))),
              const PopupMenuItem(value: 'sparren_neu', child: ListTile(dense: true, leading: Icon(Icons.view_week_outlined), title: Text('Sparrenlage über das Geschoss …'))),
              CheckedPopupMenuItem(value: 'sparren_aus', checked: _s.settings.darstellung['sparren_aus'] != true, child: const Text('Sparren im Grundriss zeigen')),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(value: 'unterlage', checked: _unterlage, child: const Text('Geschoss darunter einblenden (Wände, Verknüpfung)')),
              const PopupMenuItem(value: 'statiker', child: ListTile(dense: true, leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Mappe für den Statiker (PDF) …'))),
              const PopupMenuItem(value: 'fassade', child: ListTile(dense: true, leading: Icon(Icons.home_work_outlined), title: Text('WDVS, Fassade und Balkon …'))),
              const PopupMenuItem(value: 'keller', child: ListTile(dense: true, leading: Icon(Icons.foundation), title: Text('Keller, Sockel, Putzprofile, Fensterbänke …'))),
              const PopupMenuItem(value: 'raumbild', child: ListTile(dense: true, leading: Icon(Icons.auto_awesome), title: Text('KI-Raumbild …'))),
            ],
          ),
          IconButton(tooltip: 'Alles zeigen', onPressed: _einpassen, icon: const Icon(Sym.allesZeigen)),
          IconButton(tooltip: '3D-Ansicht des Geschosses', onPressed: () => geschoss3dZeigen(context, _s), icon: const Icon(Icons.view_in_ar)),
          Builder(builder: (context) {
            final n = aufmassOffen(_s.store!);
            return IconButton(
              tooltip: n == 0 ? 'Aufmaß (Maße von der Baustelle)' : '$n Maß(e) vom Handy prüfen und übernehmen',
              onPressed: () => aufmassDialogZeigen(context, _s),
              icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.straighten)),
            );
          }),
          IconButton(
            tooltip: 'Rückgängig (Strg+Z)',
            onPressed: _rueckgaengig.isEmpty ? null : _rueckgaengigMachen,
            icon: const Icon(Sym.rueckgaengig),
          ),
          IconButton(
            tooltip: _s.settings.hilfeAnzeigen ? 'Erklärungen rechts ausblenden' : 'Erklärungen rechts einblenden',
            isSelected: _s.settings.hilfeAnzeigen,
            onPressed: () => setState(() {
              _s.settings.hilfeAnzeigen = !_s.settings.hilfeAnzeigen;
              _s.settings.speichern();
            }),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
    );
  }

  /// „Maße“ in der Werkzeugleiste: ohne Auswahl die Voreinstellung,
  /// mit gewählten Wänden deren eigene Einstellung.
  Widget _massFeld(_Plan plan) {
    final gewaehlt = plan.waende.where((w) => _auswahl.contains(w.id)).toList();
    if (gewaehlt.isEmpty) {
      return Tooltip(
        message: 'Voreinstellung: welche Maße an allen Wänden ohne eigene Einstellung stehen. '
            'Mit gewählter Wand stellst du hier die Maße dieser Wand ein.',
        child: _auswahlFeld<MassAnzeige>('Maße (Voreinstellung)', _massVoreinstellung, MassAnzeige.values,
            (v) => v.label, (v) {
          _s.store!.einstellungSetzen('mass_anzeige', v.name);
          _s.geaendert();
        }),
      );
    }
    final werte = gewaehlt.map((w) => w.massanzeige).toSet();
    final store = _s.store!;
    // '' = Voreinstellung, sonst Name; null = verschiedene Werte
    final aktuell = werte.length == 1 ? (werte.single?.name ?? '') : null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(gewaehlt.length == 1 ? 'Maße (diese Wand) ' : 'Maße (${gewaehlt.length} Wände) ',
          style: const TextStyle(fontSize: 12, color: BsFarben.akzentDunkel, fontWeight: FontWeight.w600)),
      DropdownButton<String>(
        value: aktuell,
        hint: const Text('verschiedene'),
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem(value: '', child: Text('Standard (folgt Voreinstellung)')),
          for (final m in MassAnzeige.values) DropdownMenuItem(value: m.name, child: Text(m.label)),
        ],
        onChanged: (v) {
          if (v == null) return;
          final neu = v.isEmpty ? null : MassAnzeige.values.byName(v);
          final alt = [for (final w in gewaehlt) (w.id, w.massanzeige)];
          store.waendeMassanzeigeSetzen([for (final w in gewaehlt) w.id], neu);
          _rueckgaengig.add(() {
            for (final (id, a) in alt) {
              store.waendeMassanzeigeSetzen([id], a);
            }
          });
          _s.geaendert();
        },
      ),
    ]);
  }

  Widget _auswahlFeld<T>(String label, T wert, List<T> werte, String Function(T) text, void Function(T) setzen) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        DropdownButton<T>(
          value: wert,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [for (final v in werte) DropdownMenuItem(value: v, child: Text(text(v)))],
          onChanged: (v) {
            if (v != null || null is T) setzen(v as T);
          },
        ),
      ],
    );
  }

  List<RaumBild> _raumBilder(_Plan plan, Raum? auswahl, ErkannterRaum? frei) {
    final bilder = <RaumBild>[];
    final belegt = <ErkannterRaum>{};
    for (final r in plan.raeume) {
      final f = plan.raumZuFlaeche[r.id];
      final umriss = f?.licht ?? r.umriss;
      if (umriss == null) continue;
      final mehrere = f != null && plan.raeumeIn(f).length > 1;
      if (f != null) {
        if (belegt.contains(f)) continue; // nur einmal beschriften
        belegt.add(f);
      }
      final namen = f == null ? r.name : plan.raeumeIn(f).map((e) => e.name).join(' / ');
      bilder.add(RaumBild(
        umriss: [for (final p in umriss) _o(p)],
        beschriftung: namen,
        unterzeile: r.istBodenplatte
            ? '${r.art.label} · ${flaecheText(r.flaeche!)}'
            : f == null
                ? 'Wandzug offen'
                : flaecheText(f.flaeche),
        innenpunkt: _o(f?.innenpunkt ?? punktImInneren(umriss)),
        ausgewaehlt: auswahl != null && (auswahl.id == r.id || (f != null && plan.raeumeIn(f).contains(auswahl))),
        warnung: !r.istBodenplatte && (f == null || mehrere),
        bodenplatte: r.istBodenplatte,
      ));
    }
    for (final f in plan.flaechen) {
      if (belegt.contains(f)) continue;
      bilder.add(RaumBild(
        umriss: [for (final p in f.licht) _o(p)],
        beschriftung: flaecheText(f.flaeche),
        innenpunkt: _o(f.innenpunkt),
        zugeordnet: false,
        ausgewaehlt: frei != null && identical(frei, f),
      ));
    }
    // Bodenplatte im Entstehen (mit Mauspunkt)
    final entwurf = [..._plattePunkte, if (_plattePunkte.isNotEmpty && _maus != null) _maus!];
    if (entwurf.length >= 2) {
      bilder.add(RaumBild(
        umriss: entwurf,
        beschriftung: entwurf.length >= 3 ? flaecheText(polygonFlaeche([for (final q in entwurf) Punkt(q.dx, q.dy)]).abs()) : '',
        innenpunkt: entwurf.reduce((a, b) => a + b) / entwurf.length.toDouble(),
        ausgewaehlt: true,
        bodenplatte: true,
      ));
    }
    return bilder;
  }

  final _flaecheKey = GlobalKey();

  /// Gewähltes Objekt rechts neben das Eigenschaften-Fenster rücken.
  void _inBlickRuecken(double rechteKante) {
    final box = _flaecheKey.currentContext?.findRenderObject() as RenderBox?;
    final plan = _plan;
    if (box == null || plan == null || !mounted) return;
    Offset? welt;
    final o = plan.oeffnungen.where((x) => x.id == _oeffnungAuswahl).firstOrNull;
    final w = o == null ? plan.waende.where((x) => _auswahl.contains(x.id)).firstOrNull : plan.waende.where((x) => x.id == o.wandId).firstOrNull;
    if (w != null && w.laenge > 0) {
      final t = o == null ? w.laenge / 2 : o.abstand + o.breite / 2;
      welt = Offset(w.x1 + (w.x2 - w.x1) * t / w.laenge, w.y1 + (w.y2 - w.y1) * t / w.laenge);
    } else if (_s.raumId != null) {
      final r = _s.store!.raeume(_s.geschossId ?? '').where((x) => x.id == _s.raumId).firstOrNull;
      if (r?.umriss != null) {
        final p = punktImInneren(r!.umriss!);
        welt = Offset(p.x, p.y);
      }
    }
    if (welt == null) return;
    final links = box.localToGlobal(Offset.zero).dx;
    final frei0 = math.max(0.0, rechteKante - links);
    if (frei0 > _flaeche.width - 120) return;
    final ziel = Offset(frei0 + (_flaeche.width - frei0) / 2, _flaeche.height / 2);
    final jetzt = welt * _massstab + _verschiebung;
    if (jetzt.dx > frei0 + 60 && jetzt.dx < _flaeche.width - 40) return; // schon gut sichtbar
    setState(() => _verschiebung += ziel - jetzt);
  }

  Widget _zeichenflaeche(_Plan plan, Raum? raum, ErkannterRaum? frei) {
    final raumBilder = _raumBilder(plan, raum, frei);
    _eigFenster.imBlick = _inBlickRuecken;
    return LayoutBuilder(key: _flaecheKey, builder: (context, c) {
      _flaeche = Size(c.maxWidth, c.maxHeight);
      if (!_eingepasst) {
        _eingepasst = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _einpassen();
        });
      }
      // Vorschau der gerade gezeichneten Wand mit Seitenlängen und Winkel
      final start = _kettenStart;
      final vorschauEnde = _vorschauEnde();
      (double, double)? vorschauFlanken;
      String? vorschauWinkel;
      if (_form == 0 && start != null && vorschauEnde != null && (vorschauEnde - start).distance >= 1) {
        final achse = WandAchse(Punkt(start.dx, start.dy), Punkt(vorschauEnde.dx, vorschauEnde.dy), _zeichenDicke);
        var (fl, fr) = flankenLaengen(achse, [...plan.achsen, achse]);
        // Im Innenmaß-Modus: freies Ende so zeigen, als schlösse die nächste
        // Wand rechtwinklig an – dann passt die Anzeige zur Eingabe.
        final endeFrei = !plan.achsen.any((o) => _punktAufAchse(achse.b, o));
        if (_massBezug != MassBezug.achse && endeFrei && (fl - fr).abs() >= 1) {
          final h = _zeichenDicke / 2;
          if (fl < fr) {
            fl -= h;
            fr += h;
          } else {
            fr -= h;
            fl += h;
          }
        }
        vorschauFlanken = (fl, fr);
        vorschauWinkel = '∠ ${winkelText(winkelVon(vorschauEnde - start))}';
      }
      final zeichnung = Focus(
        focusNode: _fokus,
        autofocus: true,
        onKeyEvent: _taste,
        child: MouseRegion(
          cursor: _ansichtZiehen
              ? SystemMouseCursors.grab
              : _verschiebtAuswahl
                  ? SystemMouseCursors.move
                  : switch (_werkzeug) {
                      Werkzeug.wand => SystemMouseCursors.precise,
                      Werkzeug.raum => SystemMouseCursors.click,
                      Werkzeug.mass => SystemMouseCursors.precise,
                      Werkzeug.winkel => SystemMouseCursors.click,
                      Werkzeug.oeffnung => SystemMouseCursors.click,
                      Werkzeug.auswahl => SystemMouseCursors.basic,
                    },
          onHover: (e) => _zeigerBewegt(e.localPosition, gedrueckt: false),
          onExit: (_) => setState(() {
            _maus = null;
            // Beim Zeichnen weiterlaufen lassen, sonst Randfahrt beenden.
            if (_ziehStart == null) {
              _zeiger = null;
              _randPruefen();
            }
          }),
          child: Listener(
            onPointerDown: (e) {
              if (_zf.runter(e)) return;
              _druck(e);
            },
            onPointerMove: (e) {
              if (_zf.ausloesenBeiBewegung(e) case final w?) _druck(w);
              if (_zf.zweiFinger(e) case final g?) {
                _ansichtSchieben(g.verschiebung);
                _zoomen(g.faktor, g.mitte);
                return;
              }
              if (_zf.aktiv) return;
              final vs = _vorlageZiehStart;
              if (vs != null) {
                setState(() => _vorlageVersatz = _zuWelt(e.localPosition) - vs);
                return;
              }
              if ((e.buttons & (kMiddleMouseButton | kSecondaryMouseButton)) != 0 ||
                  (_ansichtZiehen && (e.buttons & kPrimaryMouseButton) != 0)) {
                _ansichtSchieben(e.delta);
              } else {
                _zeigerBewegt(e.localPosition, gedrueckt: (e.buttons & kPrimaryMouseButton) != 0);
              }
            },
            onPointerUp: (e) {
              final h = _zf.hoch(e);
              if (h.wartend case final w?) _druck(w);
              if (h.geste) return;
              if (_vorlageZiehStart != null) {
                _vorlageVerschiebenFertig();
                return;
              }
              if (_werkzeug == Werkzeug.auswahl && _ziehStart != null) {
                _auswahlLoslassen(_zuWelt(e.localPosition), plan);
              }
              _randPruefen();
            },
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                if (HardwareKeyboard.instance.isShiftPressed) {
                  // Umschalt + Mausrad: Ansicht verschieben statt zoomen
                  _ansichtSchieben(Offset(-e.scrollDelta.dy, -e.scrollDelta.dx));
                } else {
                  _zoomen(e.scrollDelta.dy > 0 ? 0.88 : 1 / 0.88, e.localPosition);
                }
              }
            },
            // Touchpad: zwei Finger verschieben, Spreizen zoomt.
            onPointerPanZoomStart: (_) => _pzSkala = 1,
            onPointerPanZoomUpdate: (e) {
              _ansichtSchieben(e.panDelta);
              if (e.scale != _pzSkala && e.scale > 0) {
                _zoomen(e.scale / _pzSkala, e.localPosition);
                _pzSkala = e.scale;
              }
            },
            child: ClipRect(
              child: CustomPaint(
                size: Size.infinite,
                painter: FloorplanPainter(
                  massDichte: (_s.settings.darstellung['mass_dichte'] as num?)?.toDouble() ?? 1,
                  massSchrift: (_s.settings.darstellung['mass_schrift'] as num?)?.toDouble() ?? 1,
                  raster: _s.settings.darstellung['raster_aus'] != true,
                  sparren: _s.settings.darstellung['sparren_aus'] == true || _s.geschossId == null
                      ? const []
                      : [
                          for (final f in sparrenfelder(_s.store!, _s.geschossId!))
                            for (final (a, b) in f.strecken) (Offset(a.$1, a.$2), Offset(b.$1, b.$2), f.breite, false),
                        ],
                  massAbPxJeM: (_s.settings.darstellung['mass_ab'] as num?)?.toDouble() ?? 25,
                  beideAbPxJeM: (_s.settings.darstellung['beide_ab'] as num?)?.toDouble() ?? 70,
                  waende: _versatz == Offset.zero ? plan.waende : _verschobeneVorschau(plan.waende),
                  raeume: raumBilder,
                  umrisse: _versatz == Offset.zero ? plan.umrisse : const {},
                  schichten: plan.schichten,
                  aufbau: [for (final b in plan.aufbau) if (b.imPlan) ([for (final p in b.polygon) Offset(p.x, p.y)], Color(plan.materialien[b.material]?.farbe ?? 0xFFE9E4DA))],
                  kernFarben: {for (final e in plan.materialien.entries) e.key: Color(e.value.farbe)},
                  massstab: _massstab,
                  verschiebung: _verschiebung,
                  auswahl: _auswahl,
                  rahmen: _rahmen,
                  kettenStart: _kettenStart,
                  maus: _maus,
                  vorschauDicke: _zeichenDicke,
                  flanken: plan.flanken,
                  raumStuecke: plan.raumStuecke,
                  vorschauEnde: _form == 1 ? null : vorschauEnde,
                  vorschauRechteck: _form == 1 && start != null && vorschauEnde != null ? _rechteckAchse(start, vorschauEnde) : null,
                  vorschauFlanken: vorschauFlanken,
                  vorschauWinkel: vorschauWinkel,
                  massVoreinstellung: _massVoreinstellung,
                  fangText: (_werkzeug == Werkzeug.wand || _werkzeug == Werkzeug.mass) && _abstandWand == null
                      ? _fangText
                      : null,
                  fangLinie: (_werkzeug == Werkzeug.wand || _werkzeug == Werkzeug.mass) && _abstandWand == null
                      ? _fangLinie
                      : null,
                  bemassungen: _bemassungenSichtbar ? [for (final b in plan.bemassungen) if (!b.versteckt) b] : const [],
                  massAuswahl: _massAuswahl,
                  massVorschau: _massVorschau(),
                  winkel: _winkelBilder(plan),
                  vorlage: _vorlageDarstellung(plan),
                  vorlageLinien: _vorlageLinien(plan),
                  oeffnungen: plan.oeffnungen,
                  oeffnungAuswahl: _oeffnungAuswahl,
                  oeffnungVorschau: _werkzeug == Werkzeug.oeffnung ? _oeffnungVorschau : null,
                  bezugPunkt: _vorlageModus == 1 && _kalibrierPunkte.isNotEmpty
                      ? _kalibrierPunkte.first
                      : _abstandWand == null
                      ? null
                      : (_abstandVonA
                          ? Offset(_abstandWand!.x1.toDouble(), _abstandWand!.y1.toDouble())
                          : Offset(_abstandWand!.x2.toDouble(), _abstandWand!.y2.toDouble())),
                ),
              ),
            ),
          ),
        ),
      );
      final dach = _s.geschossId == null ? null : dachLesen(_s.store!, _s.geschossId!);
      final dachRahmen = dach == null || !dach.aktiv ? null : gebaeuderahmen(plan.waende);
      final unten = _unterlage ? _geschossDarunter() : null;
      return Stack(children: [
        if (unten != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: CustomPaint(
                  painter: UnterlagePainter(
                    waende: _s.store!.waende(unten.id),
                    massstab: _massstab,
                    verschiebung: _verschiebung,
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(child: Opacity(opacity: unten != null ? 0.92 : 1, child: zeichnung)),
        if (unten != null)
          Positioned(
            right: 12,
            top: 12,
            child: Material(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('${unten.kuerzel} darunter gestrichelt · tragende Wände ohne Wand darunter rot',
                    style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
              ),
            ),
          ),
        if (unten != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: CustomPaint(
                  painter: UnterlagePainter(
                    waende: [
                      for (final w in plan.waende)
                        if (w.eigenschaften['tragend'] == true && !_verknuepfungen(plan.waende, unten).containsKey(w.id)) w
                    ],
                    massstab: _massstab,
                    verschiebung: _verschiebung,
                    warnung: true,
                  ),
                ),
              ),
            ),
          ),
        if (_s.settings.darstellung['wdvs_zeigen'] == true)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: CustomPaint(
                  painter: WdvsPainter(
                    waende: plan.waende,
                    seiten: aussenSeiten(plan.waende, _s.store!.raeume(_s.geschossId!)),
                    dicke: ((_s.store!.einstellung<Map>('wdvs') ?? const {})['dicke'] as num? ?? 160).toInt(),
                    massstab: _massstab,
                    verschiebung: _verschiebung,
                  ),
                ),
              ),
            ),
          ),
        if (dach != null && dachRahmen != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(child: CustomPaint(painter: DachPainter(d: dach, g: dachRahmen, massstab: _massstab, verschiebung: _verschiebung))),
            ),
          ),
        if (_abstandWand != null)
          Positioned(left: 12, top: 12, child: _abstandsEingabe()),
        if (_kettenStart != null && _werkzeug == Werkzeug.wand)
          Positioned(left: 12, top: 12, child: _masseingabe(vorschauEnde)),
      ]);
    });
  }

  Widget _statuszeile() {
    final m = _maus;
    final teile = <String>[
      'Bildschirm ca. 1 : ${(1 / (_massstab * 0.2645)).round()}',
      if (m != null) 'x ${mmText(m.dx)} · y ${massText(m.dy)}',
      if (_kettenStart != null) 'Tab: Länge und Winkel eingeben · Enter setzt · Esc beendet',
      if (_parallelFuer != null) 'Parallel ausrichten: Bezugswand anklicken · Esc bricht ab',
      if (_werkzeug == Werkzeug.raum) 'In eine erkannte Fläche klicken, um den Raum zu benennen',
      if (_vorlageModus == 1) 'Kalibrieren: ${_kalibrierPunkte.isEmpty ? "ersten" : "zweiten"} Punkt auf der Vorlage klicken',
      if (_vorlageModus == 2) 'Vorlage verschieben: mit gedrückter Maustaste ziehen · Esc beendet',
      if (_werkzeug == Werkzeug.oeffnung) '${_oeffnungArt.label} $_oeffnungBreite mm: in eine Wand klicken',
      if (_werkzeug == Werkzeug.winkel)
        _winkelErste == null ? 'Winkel: erste Wand anklicken' : 'Winkel: zweite Wand mit gemeinsamer Ecke anklicken',
      if (_werkzeug == Werkzeug.mass)
        _massA == null
            ? 'Bemaßen: ersten Punkt klicken (Wandecken und -enden werden gefangen)'
            : _massB == null
                ? 'zweiten Punkt klicken'
                : 'Maßlinie mit der Maus versetzen und klicken',
      if (_versatz != Offset.zero) 'verschieben um x ${mmText(_versatz.dx)} · y ${massText(_versatz.dy)}',
      if (_auswahl.length > 1) '${_auswahl.length} Wände gewählt',
      'Ansicht schieben: rechte/mittlere Maustaste, Leertaste+Ziehen, Pfeiltasten · Mausrad: zoomen · Umschalt: rechtwinklig',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: Colors.white,
      child: Text(teile.join('   ·   '),
          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
    );
  }

  // ------------------------------------------------------ Eigenschaften

  Widget _hilfe(_Plan plan) {
    final frei = plan.flaechen.where((f) => plan.raeumeIn(f).isEmpty).length;
    return ListView(
      children: [
        Text('Grundriss', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const Text(
          'Wand zeichnen (W): Klick setzt Punkte, jede weitere Wand schließt an. '
          'Länge eintippen und Enter für ein genaues Maß. Gleicher Punkt oder Esc beendet. '
          'Oben einen Wandtyp wählen, dann ergibt sich die Dicke aus den Schichten.\n\n'
          'Raum (R): Sobald Wände ringsum geschlossen sind, erscheint die lichte Fläche grau. '
          'Hineinklicken und benennen – Fläche und Umfang rechnet BauSpur und führt sie nach, '
          'wenn sich Wände ändern. Abbruchwände zählen dabei nicht.\n\n'
          'Auswahl (V): Wand oder Raum anklicken, rechts ändern, Entf löscht, Strg+Z macht rückgängig. '
          'Mehrere Wände: Rahmen aufziehen, Umschalt+Klick oder Strg+A für alles. Gewählte Wände mit '
          'der Maus ziehen oder mit den Pfeiltasten verschieben.\n\n'
          'Ansicht: Der Arbeitsbereich ist unbegrenzt. Mit rechter/mittlerer Maustaste, Leertaste + Ziehen, '
          'zwei Fingern auf dem Touchpad, Umschalt+Mausrad oder den Pfeiltasten verschieben. Beim Zeichnen '
          'wandert die Ansicht mit, wenn die Maus am Rand steht.',
          style: TextStyle(height: 1.45),
        ),
        if (frei > 0) ...[
          const SizedBox(height: 16),
          Text('$frei erkannte Fläche(n) ohne Raum.', style: const TextStyle(color: BsFarben.akzentDunkel)),
        ],
      ],
    );
  }

  Widget _freieFlaeche(ErkannterRaum f) {
    return ListView(
      children: [
        const Text('Erkannte Fläche', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text(flaecheText(f.flaeche),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Umfang ${meterText(f.umfang)} · lichte Maße (Innenkante Wand)',
            style: const TextStyle(color: BsFarben.textLeise)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _raumAnlegen(f),
          icon: const Icon(Icons.add),
          label: const Text('Raum anlegen'),
        ),
      ],
    );
  }

  Widget _raumEigenschaften(Raum r, _Plan plan) {
    final store = _s.store!;
    final g = store.geschoss(r.geschossId);
    final f = plan.raumZuFlaeche[r.id];
    final flaeche = f?.flaeche ?? r.flaeche;
    final umfang = f?.umfang ?? r.umfang;
    final h = g == null ? null : r.hoehen(g);
    final lichteHoehe = h == null ? null : (r.ukDecke ?? h.rohdecke) - h.ffb;
    final mitbewohner = f == null ? const <Raum>[] : plan.raeumeIn(f).where((e) => e.id != r.id).toList();
    final frei = plan.flaechen.where((e) => plan.raeumeIn(e).isEmpty).toList();

    Widget zeile(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: const TextStyle(color: BsFarben.textLeise))),
            Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        );

    return ListView(
      children: [
        Text('Raum · ${r.kuerzel}', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text(r.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        if (flaeche != null) zeile('Fläche (licht)', flaecheText(flaeche)),
        if (umfang != null) zeile('Umfang (licht)', meterText(umfang)),
        if (lichteHoehe != null) zeile('lichte Höhe', massText(lichteHoehe)),
        const SizedBox(height: 6),
        _verkleidungWahl(
          label: 'Wandverkleidung im Raum (Vorgabe für alle Wände)',
          aktuell: r.eigenschaften['verkleidung'] is Map ? Map<String, dynamic>.from(r.eigenschaften['verkleidung'] as Map) : null,
          setzen: (v) {
            final e = {...r.eigenschaften};
            v == null ? e.remove('verkleidung') : e['verkleidung'] = v;
            store.raumEigenschaftenSetzen(r.id, e);
            _s.geaendert();
          },
        ),
        Row(children: [
          const Expanded(child: Text('Maße im Grundriss als Fertigmaß (aus = Rohbau)', style: TextStyle(fontSize: 12))),
          Switch(
            value: store.einstellung<String>('massart') == 'fertig',
            onChanged: (v) {
              store.einstellungSetzen('massart', v ? 'fertig' : 'roh');
              _s.geaendert();
            },
          ),
        ]),
        ...() {
          final dach = dachLesen(store, r.geschossId);
          final gr = dach.aktiv ? gebaeuderahmen(store.waende(r.geschossId)) : null;
          if (gr == null || r.umriss == null) return const <Widget>[];
          final w = wohnflaeche(r.umriss!, dach, gr);
          return [zeile('Wohnfläche (WoFlV)', '${w.wohn.toStringAsFixed(2).replaceAll('.', ',')} m² unter Schrägen')];
        }(),
        if (flaeche != null && lichteHoehe != null)
          zeile('Rauminhalt', '${(flaeche * lichteHoehe / 1e9).toStringAsFixed(2).replaceAll('.', ',')} m³'),
        const SizedBox(height: 10),
        if (r.umriss == null)
          _hinweis('Noch nicht im Grundriss verortet. Mit dem Raumwerkzeug (R) in eine erkannte Fläche klicken '
              'und diesen Raum zuordnen.')
        else if (f == null && !r.istBodenplatte)
          _hinweis('Der Wandzug um diesen Raum ist offen. Angezeigt wird der letzte geschlossene Umriss.')
        else if (mitbewohner.isNotEmpty)
          _hinweis('Diese Fläche teilt sich der Raum mit ${mitbewohner.map((e) => e.name).join(', ')} – '
              'vermutlich fehlt eine Trennwand.'),
        if (r.umriss == null && frei.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('${frei.length} freie Fläche(n) im Geschoss', style: const TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 8),
        DropdownButtonFormField<RaumArt>(
          key: ValueKey('art-${r.id}-${r.art.name}'),
          initialValue: r.art,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Raumart',
            helperText: r.istBodenplatte ? 'Bodenplatte ohne Wände (Umriss fest gezeichnet)' : null,
          ),
          items: [for (final a in RaumArt.values) DropdownMenuItem(value: a, child: Text(a.label))],
          onChanged: (a) {
            if (a == null || a == r.art) return;
            final alt = r.art;
            store.raumArtSetzen(r.id, a);
            _rueckgaengig.add(() => store.raumArtSetzen(r.id, alt));
            _s.geaendert();
          },
        ),
        if (r.art != RaumArt.raum && !r.istBodenplatte && r.umriss != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _raenderAlsKante(r),
            icon: const Icon(Icons.border_style),
            label: const Text('Außenränder als offene Kante statt Wand'),
          ),
          const Text('Zählt nicht zur Wohnfläche voll (Balkon nach WoFlV meist 1/4). Rückgängig mit Strg+Z.',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        ],
        const SizedBox(height: 16),
        if (r.umriss != null) ...[
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DeckePage(state: _s, raumId: r.id))),
            icon: const Icon(Sym.decke),
            label: const Text('Deckenansicht'),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: () async {
            if (await raumUmbenennenDialog(context, store, r)) _s.geaendert();
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Umbenennen'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _raumLoeschen(r.id),
          icon: const Icon(Sym.loeschen),
          label: const Text('Raum löschen (Entf)'),
        ),
        const SizedBox(height: 12),
        const Text('Die Wände bleiben beim Löschen stehen; die Fläche wird wieder frei.',
            style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      ],
    );
  }

  /// Startpunkt auf einer Wand mit Abstand vom gewählten Wandende.
  Widget _abstandsEingabe() {
    final w = _abstandWand!;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _abstandCtrl,
                  focusNode: _abstandFokus,
                  autofocus: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Abstand vom Wandende', suffixText: 'mm'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _abstandAnwenden(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  setState(() => _abstandVonA = !_abstandVonA);
                  _abstandFokus.requestFocus();
                },
                child: const Text('anderes Ende'),
              ),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: 0, label: Text('Achse')),
                  ButtonSegment(value: 1, label: Text('innen')),
                  ButtonSegment(value: 2, label: Text('außen')),
                ],
                selected: {_abstandBezug},
                onSelectionChanged: (s) {
                  setState(() => _abstandBezug = s.first);
                  _abstandFokus.requestFocus();
                },
              ),
            ]),
            const SizedBox(height: 6),
            Text(
                'Bezug: markiertes Ende – gemessen ab Achse, Innen- oder Außenecke · Wand ${massText(w.laenge)} lang\n'
                'Enter setzt den Startpunkt · Esc bricht ab',
                style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
          ],
        ),
      ),
    );
  }

  Offset? _abstandPunkt() {
    final w = _abstandWand;
    final t = int.tryParse(_abstandCtrl.text.trim());
    final plan = _plan;
    if (w == null || t == null || plan == null) return null;
    final l = w.laenge;
    // Startparameter entlang der Achse je nach Bezug (Achsende, Innen- oder Außenecke)
    final g = _grenzen(w, plan);
    final linksInnen = (g.linksB - g.linksA) <= (g.rechtsB - g.rechtsA);
    double ab;
    if (_abstandVonA) {
      ab = switch (_abstandBezug) {
        1 => linksInnen ? g.linksA : g.rechtsA,
        2 => linksInnen ? g.rechtsA : g.linksA,
        _ => 0,
      };
    } else {
      ab = l -
          switch (_abstandBezug) {
            1 => linksInnen ? g.linksB : g.rechtsB,
            2 => linksInnen ? g.rechtsB : g.linksB,
            _ => l,
          };
    }
    final a = Offset(w.x1.toDouble(), w.y1.toDouble()), b = Offset(w.x2.toDouble(), w.y2.toDouble());
    final von = _abstandVonA ? a : b, nach = _abstandVonA ? b : a;
    final p = von + (nach - von) / l * (ab + t).clamp(0.0, l);
    return Offset(p.dx.roundToDouble(), p.dy.roundToDouble());
  }

  void _abstandAnwenden() {
    final p = _abstandPunkt();
    if (p == null) return;
    setState(() {
      _kettenStart = p;
      _abstandWand = null;
      _laengeCtrl.clear();
      _winkelCtrl.clear();
    });
    _fokus.requestFocus();
  }

  void _abstandAbbrechen() {
    setState(() => _abstandWand = null);
    _fokus.requestFocus();
  }

  /// Kleine Maßeingabe oben links in der Zeichnung (Tab springt hinein).
  Widget _masseingabe(Offset? vorschauEnde) {
    final start = _kettenStart!;
    final v = vorschauEnde == null ? null : vorschauEnde - start;
    final hinweisLaenge = v == null || v.distance < 1
        ? ''
        : (v.distance - _massKorrektur(start, v / v.distance)).round().toString();
    final hinweisWinkel = v == null || v.distance < 1 ? '' : winkelText(winkelVon(v)).replaceAll('°', '');
    Widget feld(String label, TextEditingController c, FocusNode f, String hinweis, String einheit, double breite) =>
        SizedBox(
          width: breite,
          child: TextField(
            controller: c,
            focusNode: f,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9]*[.,]?[0-9]*'))],
            decoration: InputDecoration(labelText: label, hintText: hinweis, suffixText: einheit),
            onChanged: (_) => setState(() {}),
          ),
        );
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              feld(_form == 1 ? 'Breite (${_massBezug.kurz})' : 'Länge (${_massBezug.kurz})',
                  _laengeCtrl, _laengeFokus, _form == 1 ? '' : hinweisLaenge, 'mm', 150),
              const SizedBox(width: 8),
              feld(_form == 1 ? 'Tiefe' : 'Winkel', _winkelCtrl, _winkelFokus, _form == 1 ? '' : hinweisWinkel, _form == 1 ? 'mm' : '°', _form == 1 ? 150 : 100),
            ]),
            const SizedBox(height: 8),
            _massBezugWahl(
              (b) {
                setState(() => _massBezug = b);
                _laengeFokus.requestFocus();
              },
            ),
            const SizedBox(height: 6),
            const Text('Tab wechselt · Enter setzt die Wand · Esc zurück\n0° = rechts, 90° = oben, 180° = links, 270° = unten',
                style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
          ],
        ),
      ),
    );
  }

  List<Wand> _verschobeneVorschau(List<Wand> waende) {
    final dx = _versatz.dx.round(), dy = _versatz.dy.round();
    return [
      for (final w in waende)
        _auswahl.contains(w.id)
            ? Wand(
                id: w.id,
                geschossId: w.geschossId,
                x1: w.x1 + dx,
                y1: w.y1 + dy,
                x2: w.x2 + dx,
                y2: w.y2 + dy,
                dicke: w.dicke,
                zustand: w.zustand,
                wandtypId: w.wandtypId,
                massanzeige: w.massanzeige,
                gesperrt: w.gesperrt,
                verbinden: w.verbinden,
              )
            : w,
    ];
  }

  Widget _mehrfachAuswahl(List<Wand> waende, _Plan plan) {
    final store = _s.store!;
    final laenge = waende.fold<double>(0, (s, w) => s + w.laenge);
    final typen = waende.map((w) => w.wandtypId).toSet();
    return ListView(
      children: [
        const Text('Auswahl', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text('${waende.length} Wände',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        Text('zusammen ${meterText(laenge)} lang', style: const TextStyle(color: BsFarben.textLeise)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          key: ValueKey('mtyp-${_auswahl.length}-${typen.join()}'),
          initialValue: typen.length == 1 ? typen.single : null,
          isExpanded: true,
          hint: const Text('verschiedene'),
          decoration: const InputDecoration(labelText: 'Wandtyp für alle'),
          items: [
            for (final t in plan.typen)
              DropdownMenuItem(value: t.id, child: Text('${t.name} · ${t.dicke} mm', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v == null) return;
            final alt = [for (final w in waende) (w.id, w.wandtypId, w.dicke)];
            final koord = {for (final x in plan.waende) x.id: (x.x1, x.y1, x.x2, x.y2)};
            for (final w in waende) {
              final aktuell = store.waende(w.geschossId).where((x) => x.id == w.id).firstOrNull ?? w;
              wandDickeMitInnenmass(store, aktuell, () => store.wandWandtypSetzen(w.id, v));
            }
            _rueckgaengig.add(() {
              for (final (id, typ, dicke) in alt) {
                typ != null ? store.wandWandtypSetzen(id, typ) : store.wandAendern(id, dicke: dicke);
              }
              store.waendeKoordinatenSetzen(koord);
            });
            _s.geaendert();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<WandZustand>(
          key: ValueKey('mzustand-${_auswahl.length}-${waende.map((w) => w.zustand.name).toSet().join()}'),
          initialValue: waende.map((w) => w.zustand).toSet().length == 1 ? waende.first.zustand : null,
          hint: const Text('verschiedene'),
          decoration: const InputDecoration(labelText: 'Zustand für alle'),
          items: [for (final z in WandZustand.values) DropdownMenuItem(value: z, child: Text(z.label))],
          onChanged: (z) {
            if (z == null) return;
            final alt = [for (final w in waende) (w.id, w.zustand)];
            for (final w in waende) {
              store.wandAendern(w.id, zustand: z);
            }
            _rueckgaengig.add(() {
              for (final (id, zz) in alt) {
                store.wandAendern(id, zustand: zz);
              }
            });
            _s.geaendert();
          },
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            onPressed: () {
              final ids = [for (final w in waende) w.id];
              final alle = waende.every((w) => w.gesperrt);
              final alt = [for (final w in waende) (w.id, w.gesperrt)];
              store.waendeSperren(ids, !alle);
              _rueckgaengig.add(() {
                for (final (id, g) in alt) {
                  store.waendeSperren([id], g);
                }
              });
              _s.geaendert();
            },
            icon: const Icon(Icons.lock_outline, size: 18),
            label: Text(waende.every((w) => w.gesperrt) ? 'alle entsperren' : 'alle sperren'),
          ),
          for (final (text, wert) in const [('verbinden', true), ('nicht verbinden', false), ('Standard', null)])
            OutlinedButton(
              onPressed: () {
                final alt = [for (final w in waende) (w.id, w.verbinden)];
                store.waendeVerbindenSetzen([for (final w in waende) w.id], wert);
                _rueckgaengig.add(() {
                  for (final (id, v) in alt) {
                    store.waendeVerbindenSetzen([id], v);
                  }
                });
                _s.geaendert();
              },
              child: Text('Ecken: $text'),
            ),
        ]),
        const Text(
          'Verschieben: eine gewählte Wand mit der Maus ziehen (rastet auf das Raster) oder Pfeiltasten '
          '(ein Rasterschritt, mit Umschalt zehn). Räume wandern mit.',
          style: TextStyle(fontSize: 12, height: 1.4, color: BsFarben.textLeise),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _auswahlLoeschen,
          icon: const Icon(Sym.loeschen),
          label: Text('${waende.length} Wände löschen (Entf)'),
        ),
      ],
    );
  }

  /// Auswahl einer Wandverkleidung: eigene Aufbauten aus der Bibliothek,
  /// Schnellwahl, „Eigener Aufbau …“ (öffnet die Bibliothek); bei Wandseiten
  /// zusätzlich „wie Raum“.
  Widget _verkleidungWahl({required String label, required Map<String, dynamic>? aktuell, required void Function(Map<String, dynamic>?) setzen, bool wieRaum = false}) {
    final store = _s.store!;
    final elemente = _s.bibliothek.auswahl(store, BauelementKategorie.verkleidung);
    const schnell = [('Putz', 15), ('GK direkt geklebt', 25), ('GK auf Unterkonstruktion', 62), ('Vorsatzschale 75 + GK', 90)];
    String wert(Map<String, dynamic>? v) => v == null
        ? (wieRaum ? 'raum' : 'keine')
        : v['element'] != null
            ? 'e:${v['element']}'
            : ((v['dicke'] as num?) ?? 0) == 0
                ? 'keine'
                : 's:${v['art'] ?? ''}|${v['dicke']}';
    final items = <String, String>{
      if (wieRaum) 'raum': 'wie Raum',
      'keine': 'keine (Rohbau)',
      for (final e in elemente) 'e:${e.id}': '${e.anzeige} · ${e.zahl('dicke')?.round() ?? 0} mm',
      for (final (art, d) in schnell) 's:$art|$d': '$art · $d mm',
    };
    final w = wert(aktuell);
    if (!items.containsKey(w)) items[w] = '${aktuell?['art'] ?? 'eigene'} · ${aktuell?['dicke'] ?? 0} mm';
    items['neu'] = 'Eigener Aufbau … (in der Bibliothek anlegen)';
    return DropdownButtonFormField<String>(
      key: ValueKey('verk-$label-$w-${elemente.length}'),
      initialValue: w,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
      onChanged: (v) {
        if (v == null) return;
        if (v == 'neu') {
          zeigeHinweis(context, 'Bibliothek › Material › „Wandverkleidung / Vorsatzschale“: neuen Aufbau anlegen (Dicke angeben), danach hier auswählen.');
          _s.modulWaehlen(Modul.bauteile);
          return;
        }
        if (v == 'raum') return setzen(null);
        if (v == 'keine') return setzen(wieRaum ? {'art': 'keine', 'dicke': 0} : null);
        if (v.startsWith('e:')) {
          final e = elemente.firstWhere((x) => x.id == v.substring(2));
          BauelementBibliothek.insProjekt(store, e);
          return setzen({'element': e.id, 'art': e.anzeige, 'dicke': e.zahl('dicke')?.round() ?? 0});
        }
        final t = v.substring(2).split('|');
        setzen({'art': t[0], 'dicke': int.tryParse(t[1]) ?? 0});
      },
    );
  }

  /// Zeigt, ob und was auf der Baustelle gemessen wurde (Aufmaß vom Handy).
  Widget _aufmassZeile(String id) {
    final store = _s.store!;
    final gemessen = aufmassGemessen(store)[id];
    final offen = aufmassListe(store).where((a) => a['status'] == 'offen' && a['id_ziel'] == id).length;
    if (gemessen == null && offen == 0) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Noch nicht vor Ort gemessen (grob gezeichnet).', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
        if (gemessen != null)
          Text('Gemessen: ${gemessen.entries.map((e) => '${e.key.replaceAll('_', ' ')} ${mmText((e.value as num).toDouble())}').join(', ')}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF2F9E44))),
        if (offen > 0)
          TextButton.icon(
            onPressed: () => aufmassDialogZeigen(context, _s),
            icon: const Icon(Icons.straighten, size: 16),
            label: Text('$offen Aufmaß vom Handy prüfen'),
          ),
      ]),
    );
  }

  Widget _hinweis(String text) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4)),
      );

  /// Längenfeld im Eigenschaftenbereich: Zahl eintippen, Enter.
  List<Widget> _laengeAendern(Wand w, _Plan plan) {
    final store = _s.store!;
    final (fl, fr) = plan.flanken[w.id] ?? (w.laenge, w.laenge);
    final innen = math.min(fl, fr), aussen = math.max(fl, fr);
    final anzeige = switch (_massBezug) { MassBezug.achse => w.laenge, MassBezug.innen => innen, MassBezug.aussen => aussen };
    final schluessel = '${w.id}|$_massBezug|${w.laenge.round()}|${innen.round()}';
    if (_wandLaengeFuer != schluessel && !_wandLaengeFokus.hasFocus) {
      _wandLaengeFuer = schluessel;
      _wandLaengeCtrl.text = anzeige.round().toString();
    }

    void anwenden() {
      final eingabe = int.tryParse(_wandLaengeCtrl.text.trim());
      if (eingabe == null || eingabe <= 0) return;
      final neueAchse = (w.laenge + eingabe - anzeige).round();
      if (neueAchse <= 0) {
        zeigeFehler(context, 'So kurz geht nicht – die Wand wäre kürzer als null.');
        return;
      }
      final alt = _eckpunktModus
          ? store.wandEckeVerschieben(w.id, neueAchse, amAnfang: _amAnfang)
          : store.wandLaengeAendern(w.id, neueAchse, amAnfang: _amAnfang);
      if (alt.isEmpty) {
        if (_eckpunktModus) zeigeFehler(context, 'Diese Länge lässt sich über den Eckpunkt nicht erreichen (oder eine Nachbarwand ist gesperrt).');
        return;
      }
      _rueckgaengig.add(() => store.waendeKoordinatenSetzen(alt));
      _wandLaengeFuer = null;
      _fokus.requestFocus();
      _s.geaendert();
    }

    return [
      TextField(
        controller: _wandLaengeCtrl,
        focusNode: _wandLaengeFokus,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'Länge (${_massBezug.kurz})',
          suffixText: 'mm',
          helperText: 'eintippen, Enter · Doppelklick auf die Wand springt hierher',
        ),
        onSubmitted: (_) => anwenden(),
      ),
      const SizedBox(height: 6),
      Text(
        (aussen - innen).abs() < 1
            ? 'Achse ${massText(w.laenge)}'
            : 'Achse ${mmText(w.laenge)} · innen ${mmText(innen)} · außen ${massText(aussen)}',
        style: const TextStyle(fontSize: 12, color: BsFarben.textLeise),
      ),
      const SizedBox(height: 8),
      Row(children: [
        const Text('ändern am ', style: TextStyle(fontSize: 12)),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: false, label: Text('Ende'), tooltip: 'Anfangspunkt bleibt stehen'),
            ButtonSegment(value: true, label: Text('Anfang'), tooltip: 'Endpunkt bleibt stehen'),
          ],
          selected: {_amAnfang},
          onSelectionChanged: (s) => setState(() => _amAnfang = s.first),
        ),
      ]),
      const SizedBox(height: 8),
      _massBezugWahl((b) => setState(() => _massBezug = b)),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: false, label: Text('Richtung bleibt'), tooltip: 'Wand wird in ihrer Richtung länger oder kürzer, Nachbarwände wandern mit'),
          ButtonSegment(value: true, label: Text('nur Eckpunkt'), tooltip: 'Nur der Eckpunkt gleitet entlang der Nachbarwand – der Winkel dieser Wand ändert sich'),
        ],
        selected: {_eckpunktModus},
        onSelectionChanged: (s) => setState(() => _eckpunktModus = s.first),
      ),
      const SizedBox(height: 4),
      Text(
          _eckpunktModus
              ? 'Der Eckpunkt gleitet entlang der anschließenden Wand, deren Richtung bleibt; der Winkel dieser Wand ändert sich.'
              : 'Anschließende Wände wandern mit, der Winkel bleibt, der Raum bleibt geschlossen.',
          style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
    ];
  }

  Widget _wandEigenschaften(Wand w, _Plan plan) {
    final store = _s.store!;
    final typ = plan.typen.where((t) => t.id == w.wandtypId).firstOrNull;
    return ListView(
      children: [
        const Text('Wand', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text('${massText(w.laenge)} lang',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final links in [true, false])
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => WandansichtPage(state: _s, wandId: w.id, links: links))),
              icon: const Icon(Icons.view_agenda_outlined, size: 18),
              label: Text('Ansicht ${WandSeite.berechnen(w, plan.waende, plan.raeume, _eckenVerbinden, links).raum?.name ?? (links ? 'Seite A' : 'Seite B')}'),
            ),
        ]),
        const SizedBox(height: 12),
        ..._laengeAendern(w, plan),
        _aufmassZeile(w.id),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          key: ValueKey('typ-${w.id}-${w.wandtypId}'),
          initialValue: typ?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Wandtyp'),
          items: [
            const DropdownMenuItem(value: null, child: Text('ohne (freie Dicke)')),
            for (final t in plan.typen)
              DropdownMenuItem(value: t.id, child: Text('${t.name} · ${t.dicke} mm', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            final altTyp = w.wandtypId;
            final altDicke = w.dicke;
            final koord = {for (final x in plan.waende) x.id: (x.x1, x.y1, x.x2, x.y2)};
            wandDickeMitInnenmass(store, w, () => store.wandWandtypSetzen(w.id, v));
            _rueckgaengig.add(() {
              if (altTyp != null) {
                store.wandWandtypSetzen(w.id, altTyp);
              } else {
                store.wandAendern(w.id, dicke: altDicke);
              }
              store.waendeKoordinatenSetzen(koord);
            });
            _s.geaendert();
          },
        ),
        if (hatKern(w)) ..._kernFelder(w, plan),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _teilstueckDialog(w, plan),
            icon: const Icon(Icons.content_cut, size: 16),
            label: const Text('Nur ein Teilstück anders (Wandtyp/Aufbau) …'),
          ),
        ),
        const SizedBox(height: 12),
        if (typ != null) ...[
          SchichtenVorschau(schichten: typ.schichten, materialien: plan.materialien, hoehe: 28),
          const SizedBox(height: 6),
          for (final s in typ.schichten)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(children: [
                Farbfeld(plan.materialien[s.materialId]?.farbe ?? 0xFFDDDDDD, groesse: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(plan.materialien[s.materialId]?.name ?? 'unbekanntes Material',
                      style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                ),
                Text('${s.dicke} mm', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          const SizedBox(height: 4),
          Text('Dicke ${typ.dicke} mm aus den Schichten', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              store.wandUmdrehen(w.id);
              _rueckgaengig.add(() => store.wandUmdrehen(w.id));
              _s.geaendert();
            },
            icon: const Icon(Sym.umdrehen),
            label: const Text('Wand umdrehen (Schichten spiegeln)'),
          ),
        ] else
          DropdownButtonFormField<int>(
            key: ValueKey('dicke-${w.id}-${w.dicke}'),
            initialValue: _dicken.contains(w.dicke) ? w.dicke : null,
            hint: Text('${w.dicke} mm'),
            decoration: const InputDecoration(labelText: 'Dicke'),
            items: [for (final d in _dicken) DropdownMenuItem(value: d, child: Text('$d mm'))],
            onChanged: (d) {
              if (d == null) return;
              final alt = w.dicke;
              final koord = {for (final x in plan.waende) x.id: (x.x1, x.y1, x.x2, x.y2)};
              wandDickeMitInnenmass(store, w, () => store.wandAendern(w.id, dicke: d));
              _rueckgaengig.add(() {
                store.wandAendern(w.id, dicke: alt);
                store.waendeKoordinatenSetzen(koord);
              });
              _s.geaendert();
            },
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<WandZustand>(
          key: ValueKey('zustand-${w.id}-${w.zustand.name}'),
          initialValue: w.zustand,
          decoration: const InputDecoration(labelText: 'Zustand'),
          items: [for (final z in WandZustand.values) DropdownMenuItem(value: z, child: Text(z.label))],
          onChanged: (z) {
            if (z == null) return;
            final alt = w.zustand;
            store.wandAendern(w.id, zustand: z);
            _rueckgaengig.add(() => store.wandAendern(w.id, zustand: alt));
            _s.geaendert();
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<WandArt>(
              key: ValueKey('wart-${w.id}-${w.art.name}'),
              isExpanded: true,
              initialValue: w.art,
              decoration: const InputDecoration(labelText: 'Höhe / Art'),
              items: [for (final a in WandArt.values) DropdownMenuItem(value: a, child: Text(a.label, overflow: TextOverflow.ellipsis))],
              onChanged: (a) {
                if (a == null) return;
                final alt = {'art': w.eigenschaften['art'], 'hoehe': w.eigenschaften['hoehe']};
                store.wandEigenschaftenSetzen(
                    w.id,
                    a == WandArt.raumhoch
                        ? {'art': null, 'hoehe': null}
                        : a == WandArt.kante
                            ? {'art': 'kante', 'hoehe': null}
                            : {'art': a.name, 'hoehe': w.hoehe ?? a.standardHoehe});
                _rueckgaengig.add(() => store.wandEigenschaftenSetzen(w.id, alt));
                _s.geaendert();
              },
            ),
          ),
          if (w.teilhoch) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: SpeicherFeld(
                key: ValueKey('whoehe-${w.id}-${w.hoehe}'),
                initialValue: '${w.hoehe ?? w.art.standardHoehe}',
                decoration: const InputDecoration(labelText: 'Höhe', suffixText: 'mm'),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onFieldSubmitted: (t) {
                  final h = int.tryParse(t);
                  if (h == null || h <= 0) return;
                  final alt = w.eigenschaften['hoehe'];
                  store.wandEigenschaftenSetzen(w.id, {'hoehe': h});
                  _rueckgaengig.add(() => store.wandEigenschaftenSetzen(w.id, {'hoehe': alt}));
                  _s.geaendert();
                },
              ),
            ),
          ],
        ]),
        if (w.teilhoch)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Teilhohe Wand: bildet keine Raumgrenze, im Plan heller mit Höhe gezeichnet.',
                style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          ),
        if (w.istKante) ...[
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Offene Kante: begrenzt den Balkon/die Terrasse, ist aber keine Wand (keine Wandfläche, kein Mauerwerk, keine Hüllfläche).',
                style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: w.gelaender,
            title: const Text('Geländer auf der Kante'),
            onChanged: (v) {
              final alt = w.eigenschaften['gelaender'];
              store.wandEigenschaftenSetzen(w.id, {'gelaender': v == true ? true : null});
              _rueckgaengig.add(() => store.wandEigenschaftenSetzen(w.id, {'gelaender': alt}));
              _s.geaendert();
            },
          ),
        ],
        const SizedBox(height: 12),
        ..._fluchtFelder(w),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: const Text('Erweitert', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Sparren, Brandschutz, Parallel/Verlängern, Sperren, Ecken, Statik', style: TextStyle(fontSize: 11)),
          children: [
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => sparrenDialogZeigen(context, _s, w.geschossId, wand: w),
          icon: const Icon(Icons.roofing, size: 18),
          label: Text('Sparren … (${sparrenfelder(store, w.geschossId).length} Felder im Geschoss)'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('fw-${w.id}-${wandFeuerwiderstand(store)[w.id]}'),
          initialValue: wandFeuerwiderstand(store)[w.id] ?? '–',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Brandschutz (Feuerwiderstand)', isDense: true),
          items: [for (final k in feuerwiderstandsKlassen) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (v) {
            wandFeuerwiderstandSetzen(store, [w.id], v);
            _s.geaendert();
          },
        ),
        const SizedBox(height: 8),
        for (final links in [true, false])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _verkleidungWahl(
              label: 'Verkleidung ${WandSeite.berechnen(w, plan.waende, plan.raeume, _eckenVerbinden, links).raum?.name ?? (links ? 'Seite A' : 'Seite B')}',
              aktuell: verkleidungSeiten(store)['${w.id}|${links ? 'l' : 'r'}'],
              wieRaum: true,
              setzen: (v) {
                verkleidungSeiteSetzen(store, w.id, links, v);
                _s.geaendert();
              },
            ),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            onPressed: w.gesperrt ? null : () => setState(() => _parallelFuer = w.id),
            icon: const Icon(Sym.parallel, size: 18),
            label: const Text('Parallel zu …'),
          ),
          OutlinedButton.icon(
            onPressed: () => _verlaengernStarten(w),
            icon: const Icon(Sym.verlaengern, size: 18),
            label: Text('Verlängern am ${_amAnfang ? 'Anfang' : 'Ende'}'),
          ),
        ]),
        if (_parallelFuer == w.id)
          _hinweis('Jetzt die Wand anklicken, zu der diese Wand parallel werden soll. Das Ende '
              '(„ändern am“) dreht sich, die Länge bleibt, anschließende Wände ziehen mit. Esc bricht ab.'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            onPressed: () {
              final alt = w.massanzeige;
              final neu = (w.massanzeige ?? _massVoreinstellung) == MassAnzeige.keine ? null : MassAnzeige.keine;
              store.waendeMassanzeigeSetzen([w.id], neu);
              _rueckgaengig.add(() => store.waendeMassanzeigeSetzen([w.id], alt));
              _s.geaendert();
            },
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: Text((w.massanzeige ?? _massVoreinstellung) == MassAnzeige.keine ? 'Maß einblenden' : 'Maß ausblenden'),
          ),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: w.gesperrt,
          title: const Text('Gesperrt'),
          subtitle: const Text('Länge und Lage bleiben bei Änderungen an anderen Wänden fest'),
          onChanged: (v) {
            store.waendeSperren([w.id], v);
            _rueckgaengig.add(() => store.waendeSperren([w.id], !v));
            _s.geaendert();
          },
        ),
        DropdownButtonFormField<String>(
          key: ValueKey('verb-${w.id}-${w.verbinden}'),
          initialValue: w.verbinden == null ? '' : (w.verbinden! ? 'an' : 'aus'),
          decoration: const InputDecoration(labelText: 'Ecken verbinden'),
          items: [
            DropdownMenuItem(value: '', child: Text('Standard (${_eckenVerbinden ? 'verbinden' : 'nicht verbinden'})')),
            const DropdownMenuItem(value: 'an', child: Text('verbinden')),
            const DropdownMenuItem(value: 'aus', child: Text('nicht verbinden')),
          ],
          onChanged: (v) {
            final alt = w.verbinden;
            store.waendeVerbindenSetzen([w.id], v == '' ? null : v == 'an');
            _rueckgaengig.add(() => store.waendeVerbindenSetzen([w.id], alt));
            _s.geaendert();
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('fest-${store.einstellung<String>('dicke_fest')}'),
          initialValue: store.einstellung<String>('dicke_fest') ?? 'auto',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Bei Dickenänderung bleibt fest', isDense: true),
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('automatisch (Raumseite, kleinerer Raum)')),
            DropdownMenuItem(value: 'links', child: Text('Seite A')),
            DropdownMenuItem(value: 'rechts', child: Text('Seite B')),
            DropdownMenuItem(value: 'mitte', child: Text('Wandmitte (beide Räume ändern sich)')),
          ],
          onChanged: (v) {
            store.einstellungSetzen('dicke_fest', v);
            _s.geaendert();
          },
        ),
        ..._statikFelder(w),
        const SizedBox(height: 12),
        Text('von (${mmText(w.x1)} | ${mmText(w.y1)})  nach (${mmText(w.x2)} | ${mmText(w.y2)})',
            style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _auswahlLoeschen,
          icon: const Icon(Sym.loeschen),
          label: const Text('Wand löschen (Entf)'),
        ),
      ],
    );
  }
}

/// Wie eine eingetippte Wandlänge gemeint ist.
enum MassBezug {
  achse('Achsmaß', 'Achse', 'Wandmitte bis Wandmitte'),
  innen('Innenmaß', 'innen', 'Raumseite, bis zur Innenseite der nächsten (rechtwinkligen) Wand'),
  aussen('Außenmaß', 'außen', 'Außenseite, bis zur Außenseite der nächsten (rechtwinkligen) Wand');

  const MassBezug(this.label, this.kurz, this.erklaerung);
  final String label;
  final String kurz;
  final String erklaerung;
}


/// Zoomschwellen der Maße: ab wie vielen Pixeln je Meter Maße erscheinen und
/// ab wann innen und außen beide stehen. Wirkt sofort, gilt für diesen PC.
Future<void> masseSchwellenDialog(BuildContext context, AppState s) {
  final d = s.settings.darstellung;
  double w(String k, double std) => (d[k] as num?)?.toDouble() ?? std;
  return showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Maße je Zoom'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Beim Herauszoomen blenden sich Maße aus, beim Hineinzoomen wieder ein. '
                'Gewählte Wände zeigen ihre Maße immer.', style: TextStyle(color: BsFarben.textLeise)),
            const SizedBox(height: 16),
            Text('Wandmaße erst ab ${w('mass_ab', 25).round()} px je Meter'),
            Slider(
              value: w('mass_ab', 25).clamp(5, 120),
              min: 5,
              max: 120,
              divisions: 23,
              onChanged: (v) => setD(() {
                d['mass_ab'] = v;
                if (w('beide_ab', 70) < v) d['beide_ab'] = v;
              }),
            ),
            Text('Innen und außen beide ab ${w('beide_ab', 70).round()} px je Meter (darunter nur innen)'),
            Slider(
              value: w('beide_ab', 70).clamp(5, 250),
              min: 5,
              max: 250,
              divisions: 49,
              onChanged: (v) => setD(() => d['beide_ab'] = math.max(v, w('mass_ab', 25))),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => setD(() => d
                ..remove('mass_ab')
                ..remove('beide_ab')),
              child: const Text('Standard')),
          FilledButton(
              onPressed: () {
                s.settings.speichern();
                Navigator.pop(c);
              },
              child: const Text('Fertig')),
        ],
      ),
    ),
  );
}
