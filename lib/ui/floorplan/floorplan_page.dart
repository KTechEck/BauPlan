import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/aufmass.dart';
import '../../core/brandschutz.dart';
import '../../core/sparren.dart';
import '../../core/dach.dart' show wohnflaeche;
import '../../core/dxf.dart';
import '../../core/raumerkennung.dart';
import '../../core/wandmasse.dart';
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
import 'dach_dialog.dart';
import 'geschoss_3d.dart';
import 'einbaudetail_page.dart';
import 'floorplan_painter.dart';

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
    required this.umrisse,
    required this.bemassungen,
    required this.winkelmasse,
    required this.vorlage,
    required this.oeffnungen,
  });

  final List<WandAchse> achsen; // gleiche Reihenfolge wie waende
  final Map<String, (double, double)> flanken; // Seitenlängen je Wand
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
  Werkzeug _werkzeug = Werkzeug.wand;
  int _massAusrichtung = 0; // 0 direkt, 1 waagerecht, 2 senkrecht, 3 parallel zur Wand
  bool _seiteZu = false; // Eigenschaften rechts eingeklappt
  int _wandDicke = 240;
  String? _wandtypId; // null = freie Dicke
  int _rasterMm = 50;
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
    final flaechen = ProjectStore.erkenneAusWaenden(waende);
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
        if (verbinden[i]) achsen[i]
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
      flanken: {
        for (var i = 0; i < waende.length; i++)
          waende[i].id: flankenLaengen(achsen[i], verbinden[i] ? nachbarn : [achsen[i]]),
      },
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
    final radius = 10 / _massstab;
    final plan = _plan;
    final messen = _werkzeug == Werkzeug.mass;

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
    final flucht = naechster([
      for (final w in waende)
        if (_aufVerlaengerung(welt, w) case final f?) (f, 'Verlängerung Wand', radius),
    ]);
    if (flucht != null && (start == null || _winkelFang == 0)) return rund(flucht);

    return _rasterFang(welt);
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
    var bx = tol, by = tol;
    for (final w in _plan?.waende ?? const <Wand>[]) {
      for (final (px, py) in [(w.x1.toDouble(), w.y1.toDouble()), (w.x2.toDouble(), w.y2.toDouble())]) {
        if (frei.$1 && (welt.dx - px).abs() < bx && (welt.dy - py).abs() > tol) {
          bx = (welt.dx - px).abs();
          fx = px;
        }
        if (frei.$2 && (welt.dy - py).abs() < by && (welt.dx - px).abs() > tol) {
          by = (welt.dy - py).abs();
          fy = py;
        }
      }
    }
    if (fx != null) x = fx;
    if (fy != null) y = fy;
    if (fx != null || fy != null) _fangText = 'Flucht zu Wandende';
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
        Text('${mmText(b.laenge)} mm',
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
      XTypeGroup(label: 'Bilder und DXF', extensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp', 'dxf']),
    ]);
    if (datei == null || !mounted) return;
    final store = _s.store!;
    final alt = store.planvorlage(_s.geschossId!);
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
        if (o.art != OeffnungsArt.durchbruch) ...[
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
        if (_maus == null) _fangText = null;
      });
    }
    _randPruefen();
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
    final k = e.logicalKey;
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
      tastenkuerzelZeigen(context);
      return KeyEventResult.handled;
    }
    final k = e.logicalKey;
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
            tooltip: 'Optionen: Ecken verbinden, neue Wände',
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
              const PopupMenuItem(value: 'dach', child: ListTile(dense: true, leading: Icon(Icons.roofing), title: Text('Dachgeschoss: Dach, Sparren, Kniestock …'))),
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

  Widget _zeichenflaeche(_Plan plan, Raum? raum, ErkannterRaum? frei) {
    final raumBilder = _raumBilder(plan, raum, frei);
    return LayoutBuilder(builder: (context, c) {
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
            },
            onPointerMove: (e) {
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
                  waende: _versatz == Offset.zero ? plan.waende : _verschobeneVorschau(plan.waende),
                  raeume: raumBilder,
                  umrisse: _versatz == Offset.zero ? plan.umrisse : const {},
                  schichten: plan.schichten,
                  massstab: _massstab,
                  verschiebung: _verschiebung,
                  auswahl: _auswahl,
                  rahmen: _rahmen,
                  kettenStart: _kettenStart,
                  maus: _maus,
                  vorschauDicke: _zeichenDicke,
                  flanken: plan.flanken,
                  vorschauEnde: _form == 1 ? null : vorschauEnde,
                  vorschauRechteck: _form == 1 && start != null && vorschauEnde != null ? _rechteckAchse(start, vorschauEnde) : null,
                  vorschauFlanken: vorschauFlanken,
                  vorschauWinkel: vorschauWinkel,
                  massVoreinstellung: _massVoreinstellung,
                  fangText: (_werkzeug == Werkzeug.wand || _werkzeug == Werkzeug.mass) && _abstandWand == null
                      ? _fangText
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
      return Stack(children: [
        Positioned.fill(child: zeichnung),
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
      if (m != null) 'x ${mmText(m.dx)} · y ${mmText(m.dy)} mm',
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
      if (_versatz != Offset.zero) 'verschieben um x ${mmText(_versatz.dx)} · y ${mmText(_versatz.dy)} mm',
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
        if (lichteHoehe != null) zeile('lichte Höhe', '${mmText(lichteHoehe)} mm'),
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
                'Bezug: markiertes Ende – gemessen ab Achse, Innen- oder Außenecke · Wand ${mmText(w.laenge)} mm lang\n'
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
            for (final w in waende) {
              store.wandWandtypSetzen(w.id, v);
            }
            _rueckgaengig.add(() {
              for (final (id, typ, dicke) in alt) {
                typ != null ? store.wandWandtypSetzen(id, typ) : store.wandAendern(id, dicke: dicke);
              }
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
            ? 'Achse ${mmText(w.laenge)} mm'
            : 'Achse ${mmText(w.laenge)} · innen ${mmText(innen)} · außen ${mmText(aussen)} mm',
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
        Text('${mmText(w.laenge)} mm lang',
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
            store.wandWandtypSetzen(w.id, v);
            _rueckgaengig.add(() {
              if (altTyp != null) {
                store.wandWandtypSetzen(w.id, altTyp);
              } else {
                store.wandAendern(w.id, dicke: altDicke);
              }
            });
            _s.geaendert();
          },
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
              store.wandAendern(w.id, dicke: d);
              _rueckgaengig.add(() => store.wandAendern(w.id, dicke: alt));
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
        Text('von (${mmText(w.x1)} | ${mmText(w.y1)})  nach (${mmText(w.x2)} | ${mmText(w.y2)})',
            style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
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
