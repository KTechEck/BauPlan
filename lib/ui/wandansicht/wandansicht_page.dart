import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/height.dart';
import '../../core/raumerkennung.dart';
import '../../core/anschluesse.dart';
import '../../core/geraeteanschluesse.dart';
import '../../core/leitungsnetz.dart';
import '../../core/verteiler.dart';
import '../../core/wandmasse.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../floorplan/floorplan_painter.dart' show abstandZuStrecke;
import '../tastenkuerzel.dart';
import '../widgets.dart';
import '../floorplan/dach_dialog.dart' show dachLesen, gebaeuderahmen;
import '../../core/dach.dart' show dachHoehe;

/// Geometrie einer Wandseite: Ursprung und Richtung der Ansicht (von der
/// Raumseite aus gesehen, x nach rechts), Länge der Seite, Raum davor.
class WandSeite {
  WandSeite({
    required this.wand,
    required this.links,
    required this.ursprung,
    required this.richtung,
    required this.normale,
    required this.laenge,
    required this.raum,
  });

  final Wand wand;
  final bool links; // Seite links der Zeichenrichtung (Bildschirm)
  final Offset ursprung; // Weltpunkt bei x = 0 auf der Wandoberfläche
  final Offset richtung; // Einheitsvektor x der Ansicht
  final Offset normale; // zeigt von der Wand in den Raum
  final double laenge;
  final Raum? raum;

  /// x in der Ansicht für einen Weltpunkt.
  double x(Offset welt) => (welt - ursprung).dx * richtung.dx + (welt - ursprung).dy * richtung.dy;

  /// Abstand vor der Wandoberfläche (positiv = im Raum).
  double vor(Offset welt) => (welt - ursprung).dx * normale.dx + (welt - ursprung).dy * normale.dy;

  Offset welt(double x) => ursprung + richtung * x;

  /// Berechnet die Seite aus der Wand, ihren verbundenen Nachbarn und den Räumen.
  static WandSeite berechnen(Wand w, List<Wand> alle, List<Raum> raeume, bool verbindenStandard, bool links) {
    final achsen = [for (final v in alle) v.achse];
    final i = alle.indexWhere((v) => v.id == w.id);
    final verbinden = w.verbinden ?? verbindenStandard;
    final nachbarn = [
      for (var j = 0; j < alle.length; j++)
        if (alle[j].verbinden ?? verbindenStandard) achsen[j]
    ];
    final achse = i < 0 ? w.achse : achsen[i];
    final g = flankenGrenzen(achse, verbinden ? nachbarn : [achse]);
    final a = Offset(w.x1.toDouble(), w.y1.toDouble());
    final u = (Offset(w.x2.toDouble(), w.y2.toDouble()) - a) / math.max(1.0, w.laenge);
    final nl = Offset(u.dy, -u.dx);
    final s = links ? 1.0 : -1.0;
    final tA = links ? g.linksA : g.rechtsA, tB = links ? g.linksB : g.rechtsB;
    // Von der Seite s aus gesehen läuft x nach rechts: links → von B nach A, rechts → von A nach B
    final ursprung = a + nl * (s * w.dicke / 2) + u * (links ? tB : tA);
    final richtung = links ? -u : u;
    final mitte = ursprung + richtung * ((tB - tA) / 2) + nl * (s * 150);
    Raum? raum;
    for (final r in raeume) {
      if (r.umriss != null && punktInPolygon(Punkt(mitte.dx, mitte.dy), r.umriss!)) raum = r;
    }
    return WandSeite(
      wand: w,
      links: links,
      ursprung: ursprung,
      richtung: richtung,
      normale: nl * s,
      laenge: tB - tA,
      raum: raum,
    );
  }
}

/// Ansicht einer Wandseite mit Öffnungen, Objekten und Bezugshöhen.
class WandansichtPage extends StatefulWidget {
  const WandansichtPage({super.key, required this.state, required this.wandId, required this.links});
  final AppState state;
  final String wandId;
  final bool links;

  @override
  State<WandansichtPage> createState() => _WandansichtPageState();
}

class _WandansichtPageState extends State<WandansichtPage> {
  final _eigFenster = EigenschaftenFenster();
  final _doppel = Doppelklick();
  final _fokus = FocusNode();
  late bool _links = widget.links;
  bool _setzen = false;
  bool _zeichnen = false; // Leitung / Rohr zeichnen (L)
  String? _leitungsTypId;
  final List<Offset> _entwurf = []; // (x, z) der Leitung im Entwurf
  String? _typId;
  String? _auswahl;
  final Set<String> _mehr = {}; // Mehrfachauswahl (Umschalt/Strg-Klick, Rahmen)
  Offset? _rahmenA, _rahmenB; // Ansichtskoordinaten (x, z)
  Offset? _ziehStart; // Ansicht-Koordinaten (x, z) beim Drücken
  Offset _versatz = Offset.zero;
  Offset? _maus; // (x, z) mm
  final List<VoidCallback> _rueckgaengig = [];
  Size _flaeche = Size.zero;

  AppState get _s => widget.state;

  @override
  void dispose() {
    _fokus.dispose();
    super.dispose();
  }

  // Ansichtsdaten
  late WandSeite _seite;
  late Bezugshoehen _h;
  late List<Oeffnung> _oeffnungen;
  late List<(Objekt, double, double)> _punkte; // Objekt, x, z absolut
  late List<(Objekt, double, double, double)> _leitungen; // Objekt, x1, x2, z
  late List<(Objekt, List<Offset>)> _zuege; // in der Ansicht gezeichnete Leitungen: (x, z) je Punkt
  /// Andockpunkte für Leitungen: Geräteanschlüsse und Enden von Leitungen, die hier
  /// ankommen (aus dem Grundriss oder um die Ecke von der Nachbarwand).
  late List<({Offset xz, String text, Map<String, dynamic> bezug})> _andock;
  late List<Objekt> _alleObjekte;
  late List<Wand> _alleWaende;
  late List<Raum> _alleRaeume;
  String? _fangText;
  int _rasterMm = 100; // Raster im Leitungseditor
  bool _rasterZeigen = false, _rasterFang = false;
  String? _fangLinie; // Bezugslinie (RFB, FFB, Rohdecke …), auf der der Fang liegt
  Map<String, dynamic>? _fangBezug;
  final List<Map<String, dynamic>?> _entwurfBezug = [];
  late Map<String, Objekttyp> _typen;
  late Map<String, Gewerk> _gewerke;

  bool _laden() {
    final store = _s.store!;
    final g = store.geschoss(_s.geschossId ?? '');
    final waende = g == null ? <Wand>[] : store.waende(g.id);
    final w = waende.where((e) => e.id == widget.wandId).firstOrNull;
    if (g == null || w == null) return false;
    final raeume = store.raeume(g.id);
    _alleWaende = waende;
    _alleRaeume = raeume;
    _seite = WandSeite.berechnen(w, waende, raeume, store.einstellung<bool>('ecken_verbinden') ?? true, _links);
    _h = _seite.raum?.hoehen(g) ?? g.hoehen;
    _oeffnungen = [for (final o in store.oeffnungen(g.id)) if (o.wandId == w.id) o];
    _typen = {for (final t in store.objekttypen()) t.id: t};
    _gewerke = {for (final x in store.gewerke()) x.id: x};
    _punkte = [];
    _leitungen = [];
    _zuege = [];
    final tiefe = w.dicke + 80.0; // was so weit in oder vor der Wand liegt, gehört dazu
    for (final o in store.objekte(g.id)) {
      final t = _typen[o.typId];
      if (t == null || o.punkte.isEmpty) continue;
      int? zAbs() => o.z == null || o.zBezug == null ? null : absolut(o.z!, o.zBezug!, _h);
      if (t.geometrie == Geometrieart.punkt) {
        final p = Offset(o.punkte.first.x, o.punkte.first.y);
        final x = _seite.x(p), vor = _seite.vor(p);
        if (x < -50 || x > _seite.laenge + 50 || vor < -tiefe || vor > 80) continue;
        _punkte.add((o, x, (zAbs() ?? _h.ffb + 300).toDouble()));
      } else if (t.geometrie == Geometrieart.linie) {
        final zs = o.zPunkte;
        if (zs != null) {
          final pts = [for (final q in o.punkte) Offset(q.x, q.y)];
          final hier = pts.every((p) {
            final x = _seite.x(p), vor = _seite.vor(p);
            return x > -50 && x < _seite.laenge + 50 && vor > -tiefe && vor < 80;
          });
          if (hier) _zuege.add((o, [for (var i = 0; i < pts.length; i++) Offset(_seite.x(pts[i]), zs[i].toDouble())]));
          continue;
        }
        for (var i = 0; i + 1 < o.punkte.length; i++) {
          final p = Offset(o.punkte[i].x, o.punkte[i].y), q = Offset(o.punkte[i + 1].x, o.punkte[i + 1].y);
          final vp = _seite.vor(p), vq = _seite.vor(q);
          if (vp < -tiefe || vp > 80 || vq < -tiefe || vq > 80) continue;
          final x1 = _seite.x(p), x2 = _seite.x(q);
          if ((x2 - x1).abs() < 1) continue;
          _leitungen.add((o, math.min(x1, x2), math.max(x1, x2), (zAbs() ?? _h.rfb).toDouble()));
        }
      }
    }
    // Andockpunkte
    _alleObjekte = store.objekte(g.id);
    _andock = [];
    for (final (o, x, z) in _punkte) {
      final t = _typen[o.typId];
      if (t == null) continue;
      for (final a in anschluesse(t.kuerzel, o.eigenschaften)) {
        _andock.add((xz: Offset(x + a.dx, z + a.dz), text: '${o.kennung} ${a.name}', bezug: {'objekt': o.id, 'anschluss': a.name}));
      }
      // Anschlüsse aus der Bibliothek (Lage am Gerät; Objektpunkt = Gerätemitte)
      final bel = widget.state.bibliothek.fuerProjekt(store, o.eigenschaften['bauelement'] as String?);
      if (bel != null) {
        final b = bel.zahl('breite') ?? bel.zahl('baulaenge') ?? 0, hh = bel.zahl('hoehe') ?? bel.zahl('bauhoehe') ?? 0;
        for (final a in geraeteAnschluesse(bel.daten)) {
          _andock.add((xz: Offset(x + a.x - b / 2, z + a.y - hh / 2), text: '${o.kennung} ${a.anzeige}${a.groesse.isEmpty ? '' : ' ${a.groesse}'}', bezug: {'objekt': o.id, 'anschluss': a.anzeige}));
        }
      }
    }
    final hierIds = {for (final (o, _) in _zuege) o.id};
    for (final o in _alleObjekte) {
      final t = _typen[o.typId];
      if (t?.geometrie != Geometrieart.linie || hierIds.contains(o.id) || o.punkte.length < 2) continue;
      final zs = o.zPunkte;
      for (final i in [0, o.punkte.length - 1]) {
        final p = Offset(o.punkte[i].x, o.punkte[i].y);
        final x = _seite.x(p), vor = _seite.vor(p);
        if (x < -5 || x > _seite.laenge + 5 || vor.abs() > 40) continue;
        final z = zs != null ? zs[i].toDouble() : (o.z != null && o.zBezug != null ? absolut(o.z!, o.zBezug!, _h) : _h.rfb).toDouble();
        final lage = zs != null ? 'Nachbarwand' : (o.lage ?? 'Grundriss');
        _andock.add((xz: Offset(x, z), text: '→ ${o.kennung} ($lage)', bezug: {'leitung': o.id}));
      }
    }
    return true;
  }

  // Bildschirm ↔ Ansicht (x mm, z mm absolut); Zoom und Verschiebung über _zoom/_pan
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Offset? _panStart;

  double get _massstabGrund {
    final b = _seite.laenge + 1200, hh = (_h.rohdecke - _h.rfb) + 1400;
    return math.max(0.01, math.min(_flaeche.width / b, _flaeche.height / hh));
  }

  double get _massstab => _massstabGrund * _zoom;

  Offset _ursprungBei(double m) {
    final b = (_seite.laenge + 1200) * m, hh = ((_h.rohdecke - _h.rfb) + 1400) * m;
    return Offset((_flaeche.width - b) / 2 + 600 * m, (_flaeche.height - hh) / 2 + 400 * m + (_h.rohdecke - _h.rfb) * m);
  }

  Offset get _ursprung => _ursprungBei(_massstab) + _pan;

  /// Mausrad: um den Cursor zoomen.
  void _zoomen(Offset cursor, double faktor) {
    final alt = _ursprung;
    final neuZoom = (_zoom * faktor).clamp(0.3, 20.0);
    final f = neuZoom / _zoom;
    final soll = cursor - (cursor - alt) * f;
    setState(() {
      _zoom = neuZoom;
      _pan += soll - (_ursprungBei(_massstab) + _pan);
    });
  }

  Offset _zuAnsicht(Offset b) {
    final m = _massstab, o = _ursprung;
    return Offset((b.dx - o.dx) / m, _h.rfb - (b.dy - o.dy) / m);
  }

  Offset _gerastert(Offset a) {
    final r = _rasterFang && _rasterMm > 0 ? _rasterMm.toDouble() : 10.0;
    return Offset((a.dx / r).round() * r, (a.dy / r).round() * r);
  }

  String? _treffer(Offset a) {
    final tol = 10 / _massstab;
    String? id;
    var bester = tol;
    for (final (o, x, z) in _punkte) {
      final d = (Offset(x, z) - a).distance;
      if (d < bester) {
        bester = d;
        id = o.id;
      }
    }
    return id;
  }

  void _objektSetzen(Offset a) {
    final t = _typen[_typId];
    if (t == null) return;
    final store = _s.store!;
    final welt = _seite.welt(a.dx);
    final id = store.objektAnlegen(
      geschossId: _s.geschossId!,
      typ: t,
      punkte: [Punkt(welt.dx, welt.dy)],
      raumId: _seite.raum?.id,
      z: a.dy.round() - _h.ffb,
      zBezug: Hoehenbezug.ffb,
      lage: 'in Wand',
    );
    _rueckgaengig.add(() => store.objektLoeschen(id));
    _s.geaendert();
  }

  void _verschieben(String id, Offset d) {
    final eintrag = _punkte.where((e) => e.$1.id == id).firstOrNull;
    if (eintrag == null || d == Offset.zero) return;
    final (o, x, z) = eintrag;
    final store = _s.store!;
    final welt = _seite.welt(x + d.dx);
    final bezug = o.zBezug ?? Hoehenbezug.ffb;
    final zNeu = (z + d.dy).round();
    final wert = (zNeu - _h.von(bezug)) * bezug.richtung;
    final alt = store.objektAendern(o.id, {
      'geometrie': Objekt.geometrieText([Punkt(welt.dx.roundToDouble(), welt.dy.roundToDouble())]),
      'z_mm': wert,
      'z_bezug': bezug.name,
    });
    _rueckgaengig.add(() => store.objektAendern(o.id, alt));
    _s.geaendert();
  }

  /// Verteilerschränke in dieser Ansicht: Rechteck (x links, x rechts, z unten, z oben).
  List<(Objekt, Rect)> get _schraenke => [
        for (final (o, x, z) in _punkte)
          if (_typen[o.typId]?.kuerzel == 'HV')
            () {
              final d = VerteilerDaten.ausJson(o.eigenschaften);
              return (o, Rect.fromLTRB(x - d.schrankBreite / 2, z, x + d.schrankBreite / 2, z + d.schrankHoehe));
            }(),
      ];

  /// Fang beim Leitungszeichnen: Objektmitte, Unterkante eines Verteilerschranks
  /// (Anschluss der Rohre), sonst Raster; Umschalt = waagerecht/senkrecht.
  Offset _leitungFangen(Offset roh) {
    final tol = 12 / _massstab;
    _fangText = null;
    _fangBezug = null;
    for (final a in _andock) {
      if ((a.xz - roh).distance < tol) {
        _fangText = a.text;
        _fangBezug = a.bezug;
        return a.xz;
      }
    }
    for (final (_, x, z) in _punkte) {
      if ((Offset(x, z) - roh).distance < tol) return Offset(x, z);
    }
    for (final (_, r) in _schraenke) {
      if (roh.dx >= r.left - tol && roh.dx <= r.right + tol && (roh.dy - r.top).abs() < tol) {
        return _gerastert(Offset(roh.dx.clamp(r.left, r.right), 0)).translate(0, r.top);
      }
    }
    var a = _gerastert(roh);
    if (HardwareKeyboard.instance.isShiftPressed && _entwurf.isNotEmpty) {
      final l = _entwurf.last;
      a = (a.dx - l.dx).abs() >= (a.dy - l.dy).abs() ? Offset(a.dx, l.dy) : Offset(l.dx, a.dy);
    }
    // Bezugslinien: Schnittpunkt = Übergabepunkt (z. B. „ab hier unter Estrich“)
    _fangLinie = null;
    final uk = _seite.raum?.ukDecke;
    for (final (z, name) in [(_h.rfb, 'RFB'), (_h.ffb, 'FFB'), (_h.rohdecke, 'Rohdecke'), if (uk != null) (uk, 'UK Decke')]) {
      if ((roh.dy - z).abs() < tol) {
        _fangLinie = name;
        _fangText = '$name – Übergabepunkt';
        return Offset(a.dx, z.toDouble());
      }
    }
    return a;
  }

  /// Klick auf eine Bezugslinie beim Leitungszeichnen: neben dem Cursor fragen,
  /// wohin die Leitung von hier aus weitergeht.
  Future<void> _uebergabeFragen(Offset global, String linie) async {
    final wahl = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx + 8, global.dy + 8, global.dx + 9, global.dy + 9),
      items: [
        PopupMenuItem<String>(enabled: false, height: 28, child: Text('Übergabe an $linie – wohin weiter?', style: const TextStyle(fontWeight: FontWeight.w600))),
        for (final l in uebergangsLagen) PopupMenuItem<String>(value: l, height: 34, child: Text('${uebergangsPfeil(l)}  ab hier $l')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: '', height: 34, child: Text('in der Wand weiterzeichnen')),
      ],
    );
    if (!mounted || wahl == null || wahl.isEmpty) return;
    _leitungAbschliessen(uebergangEnde: wahl);
  }

  /// Gezeichnete Leitung als Objekt anlegen: Weltpunkte auf der Wandoberfläche,
  /// Höhe je Punkt in `z_abs` (Steigstrecken zählen zur Länge).
  void _leitungAbschliessen({String? uebergangEnde}) {
    final t = _typen[_leitungsTypId];
    final pts = <Offset>[];
    for (final p in _entwurf) {
      if (pts.isEmpty || (pts.last - p).distance >= 1) pts.add(p);
    }
    final anfang = _entwurfBezug.firstOrNull, ende = _entwurfBezug.length == _entwurf.length ? _entwurfBezug.lastOrNull : null;
    setState(_entwurfLeeren);
    if (t == null || pts.length < 2) return;
    final store = _s.store!;
    final id = store.objektAnlegen(
      geschossId: _s.geschossId!,
      typ: t,
      punkte: [
        for (final p in pts)
          () {
            final w = _seite.welt(p.dx);
            return Punkt(w.dx.roundToDouble(), w.dy.roundToDouble());
          }(),
      ],
      raumId: _seite.raum?.id,
      z: pts.first.dy.round() - _h.ffb,
      zBezug: Hoehenbezug.ffb,
      lage: 'in Wand',
    );
    store.objektAendern(id, {
      'eigenschaften': jsonEncode({
        'z_abs': [for (final p in pts) p.dy.round()],
        'wand_id': _seite.wand.id,
        if (anfang != null) 'anfang': anfang,
        if (ende != null) 'ende': ende,
        if (uebergangEnde != null) 'uebergang_ende': uebergangEnde,
      }),
    });
    _rueckgaengig.add(() => store.objektLoeschen(id));
    _s.geaendert();
  }


  void _entwurfLeeren() {
    _entwurf.clear();
    _entwurfBezug.clear();
  }

  /// Nachbarwand an der linken bzw. rechten Kante dieser Ansicht öffnen –
  /// die Seite, die zum selben Raum zeigt (Leitung um die Ecke weiterführen).
  void _nachbarOeffnen(bool rechts) {
    final w = _seite.wand;
    // x = 0 liegt bei links-Seite am Wandende B, sonst am Anfang A
    final amB = _links != rechts;
    final (px, py) = amB ? (w.x2, w.y2) : (w.x1, w.y1);
    bool an(int x, int y) => (x - px).abs() <= 1 && (y - py).abs() <= 1;
    final verbinden = _s.store!.einstellung<bool>('ecken_verbinden') ?? true;
    final ecke = _seite.welt(rechts ? _seite.laenge : 0);
    for (final n in _alleWaende) {
      if (n.id == w.id || !(an(n.x1, n.y1) || an(n.x2, n.y2))) continue;
      WandSeite? beste;
      var abst = double.infinity;
      for (final l in [true, false]) {
        final s = WandSeite.berechnen(n, _alleWaende, _alleRaeume, verbinden, l);
        final x = s.x(ecke), vor = s.vor(ecke);
        // die Seite, auf der die Innenecke liegt (gleicher Raum)
        final d = vor.abs() + (s.raum?.id == _seite.raum?.id ? 0 : 1000) + math.min(x.abs(), (x - s.laenge).abs());
        if (d < abst) {
          abst = d;
          beste = s;
        }
      }
      if (beste == null) continue;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => WandansichtPage(state: _s, wandId: n.id, links: beste!.links)));
      return;
    }
    zeigeHinweis(context, 'An dieser Kante schließt keine Wand an.');
  }
  String? _trefferZug(Offset a) {
    final tol = 8 / _massstab;
    String? id;
    var bester = tol;
    for (final (o, pts) in _zuege) {
      for (var i = 0; i + 1 < pts.length; i++) {
        final d = abstandZuStrecke(a, pts[i], pts[i + 1]);
        if (d < bester) {
          bester = d;
          id = o.id;
        }
      }
    }
    return id;
  }

  void _werkzeug({bool setzen = false, bool zeichnen = false}) => setState(() {
        _setzen = setzen;
        _zeichnen = zeichnen;
        _entwurfLeeren();
      });

  KeyEventResult _taste(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final strg = HardwareKeyboard.instance.isControlPressed;
    if (k == LogicalKeyboardKey.f1) {
      tastenkuerzelZeigen(context);
    } else if (strg && k == LogicalKeyboardKey.keyZ) {
      if (_rueckgaengig.isNotEmpty) {
        _rueckgaengig.removeLast()();
        _s.geaendert();
      }
    } else if (k == LogicalKeyboardKey.delete && (_auswahl != null || _mehr.isNotEmpty)) {
      final ids = {..._mehr, if (_auswahl != null) _auswahl!};
      for (final id in ids) {
        _s.store!.objektLoeschen(id);
      }
      _rueckgaengig.add(() {
        for (final id in ids) {
          _s.store!.objektWiederherstellen(id);
        }
      });
      setState(() {
        _auswahl = null;
        _mehr.clear();
      });
      _s.geaendert();
    } else if (k == LogicalKeyboardKey.escape) {
      if (_entwurf.isNotEmpty) {
        setState(_entwurfLeeren);
      } else if (_auswahl == null && !_setzen && !_zeichnen) {
        Navigator.maybePop(context);
      } else {
        setState(() => _auswahl = null);
        _werkzeug();
      }
    } else if (_zeichnen && (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter)) {
      _leitungAbschliessen();
    } else if (_zeichnen && k == LogicalKeyboardKey.backspace && _entwurf.isNotEmpty) {
      setState(() {
        _entwurf.removeLast();
        if (_entwurfBezug.isNotEmpty) _entwurfBezug.removeLast();
      });
    } else if (!strg && k == LogicalKeyboardKey.keyV) {
      _werkzeug();
    } else if (!strg && k == LogicalKeyboardKey.keyP) {
      _werkzeug(setzen: true);
    } else if (!strg && k == LogicalKeyboardKey.keyL) {
      _werkzeug(zeichnen: true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Dachschräge an der Wandoberfläche (Dachgeschoss), Höhe über FFB je Ansichts-x.
  double? Function(double x)? _dachHoehe() {
    final store = _s.store;
    if (store == null) return null;
    final gid = _seite.wand.geschossId;
    final dach = dachLesen(store, gid);
    if (!dach.aktiv) return null;
    final g = gebaeuderahmen(store.waende(gid));
    if (g == null) return null;
    return (x) {
      final w = _seite.welt(x) + _seite.normale * 5;
      return dachHoehe(dach, g, Punkt(w.dx, w.dy));
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        if (!_laden()) {
          return Scaffold(appBar: AppBar(title: const Text('Wandansicht')), body: const Center(child: Text('Wand nicht gefunden.')));
        }
        final punktTypen = _typen.values.where((t) => t.geometrie == Geometrieart.punkt).toList();
        _typId ??= punktTypen.where((t) => t.kuerzel == 'SD').firstOrNull?.id ?? punktTypen.firstOrNull?.id;
        final linienTypen = _typen.values.where((t) => t.geometrie == Geometrieart.linie).toList();
        _leitungsTypId ??= linienTypen.where((t) => t.kuerzel == 'HR').firstOrNull?.id ??
            linienTypen.where((t) => t.kuerzel == 'VL').firstOrNull?.id ??
            linienTypen.firstOrNull?.id;
        final gewaehlterZug = _zuege.where((e) => e.$1.id == _auswahl).firstOrNull;
        final gewaehlt = _punkte.where((e) => e.$1.id == _auswahl).firstOrNull;
        _eigFenster.setzen(
          auswahl: gewaehlterZug != null || gewaehlt != null,
          bauen: () => gewaehlterZug != null ? _zugDetails(gewaehlterZug) : gewaehlt != null ? _details(gewaehlt) : const SizedBox(),
        );
        final titel = 'Wandansicht · ${_seite.raum?.name ?? 'Außenseite'} · ${mmText(_seite.laenge)} mm';
        return Scaffold(
          backgroundColor: BsFarben.flaeche,
          appBar: AppBar(
            title: Text(titel),
            backgroundColor: Colors.white,
            actions: [
              IconButton(
                tooltip: 'Nachbarwand links (Leitung um die Ecke weiterführen)',
                onPressed: () => _nachbarOeffnen(false),
                icon: const Icon(Icons.west),
              ),
              IconButton(
                tooltip: 'Nachbarwand rechts',
                onPressed: () => _nachbarOeffnen(true),
                icon: const Icon(Icons.east),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _links = !_links;
                  _auswahl = null;
                }),
                icon: const Icon(Sym.umdrehen),
                label: const Text('andere Seite'),
              ),
              IconButton(
                tooltip: 'Ganze Wand zeigen (Zoom zurücksetzen) – Mausrad zoomt, rechte/mittlere Maustaste verschiebt',
                onPressed: () => setState(() {
                  _zoom = 1;
                  _pan = Offset.zero;
                }),
                icon: const Icon(Sym.allesZeigen),
              ),
              IconButton(
                tooltip: 'Erklärungen rechts ein-/ausblenden',
                isSelected: _s.settings.hilfeAnzeigen,
                onPressed: () => setState(() {
                  _s.settings.hilfeAnzeigen = !_s.settings.hilfeAnzeigen;
                  _s.settings.speichern();
                }),
                icon: const Icon(Icons.help_outline),
              ),
              IconButton(tooltip: 'Tastenkürzel (F1)', onPressed: () => tastenkuerzelZeigen(context), icon: const Icon(Sym.hilfe)),
            ],
          ),
          body: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
              child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                WerkzeugGruppe(kinder: [
                  WerkzeugKnopf(symbol: Sym.auswahl, text: 'Auswahl', tooltip: 'Auswahl (V): ziehen verschiebt', aktiv: !_setzen && !_zeichnen, onTap: _werkzeug),
                  WerkzeugKnopf(symbol: Sym.setzen, text: 'Setzen', tooltip: 'Objekt setzen (P)', aktiv: _setzen, onTap: () => _werkzeug(setzen: true)),
                  WerkzeugKnopf(symbol: Sym.leitung, text: 'Leitung', tooltip: 'Leitung / Rohr zeichnen (L): Punkte klicken, Enter beendet', aktiv: _zeichnen, onTap: () => _werkzeug(zeichnen: true)),
                ]),
                DropdownButton<String>(
                  value: _zeichnen ? _leitungsTypId : _typId,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final t in _zeichnen ? linienTypen : punktTypen)
                      DropdownMenuItem(
                        value: t.id,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 10, height: 10, color: Color(_gewerke[t.gewerkId]?.farbe ?? 0xFF888888)),
                          const SizedBox(width: 6),
                          Text('${t.name} (${t.kuerzel})'),
                        ]),
                      ),
                  ],
                  onChanged: (v) {
                    if (_zeichnen) {
                      setState(() => _leitungsTypId = v);
                    } else {
                      _typId = v;
                      _werkzeug(setzen: true);
                    }
                  },
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Raster einblenden',
                    isSelected: _rasterZeigen,
                    onPressed: () => setState(() => _rasterZeigen = !_rasterZeigen),
                    icon: const Icon(Icons.grid_4x4),
                  ),
                  DropdownButton<int>(
                    value: _rasterMm,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [for (final r in const [25, 50, 100, 250, 500]) DropdownMenuItem(value: r, child: Text('$r mm'))],
                    onChanged: (v) => setState(() => _rasterMm = v ?? _rasterMm),
                  ),
                  IconButton(
                    tooltip: 'Am Raster fangen',
                    isSelected: _rasterFang,
                    onPressed: () => setState(() => _rasterFang = !_rasterFang),
                    icon: const Icon(Icons.filter_center_focus),
                  ),
                ]),
                Tooltip(
                  message: 'Leitung auf einer Bezugslinie (RFB, FFB, Rohdecke) anklicken = Übergabepunkt: BauSpur fragt, wohin es weitergeht.',
                  child: Text(
                    'RFB ${mmText(_h.rfb)} · FFB ${mmText(_h.ffb)} · Meterriss ${mmText(_h.meterriss)} · Rohdecke ${mmText(_h.rohdecke)} mm',
                    style: const TextStyle(fontSize: 12, color: BsFarben.textLeise),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: ClipRect(child: _ansicht())),
                if (gewaehlterZug != null || gewaehlt != null || _s.settings.hilfeAnzeigen)
                Container(
                  width: 280,
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: gewaehlterZug == null && gewaehlt == null
                      ? _hilfe()
                      : _eigFenster.seitenleiste(() => gewaehlterZug != null ? _zugDetails(gewaehlterZug) : _details(gewaehlt!)),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _ansicht() {
    return LayoutBuilder(builder: (context, c) {
      _flaeche = Size(c.maxWidth, c.maxHeight);
      return Focus(
        focusNode: _fokus,
        autofocus: true,
        onKeyEvent: _taste,
        child: MouseRegion(
          cursor: _setzen ? SystemMouseCursors.precise : SystemMouseCursors.basic,
          onHover: (e) => setState(() => _maus = _zeichnen ? _leitungFangen(_zuAnsicht(e.localPosition)) : _gerastert(_zuAnsicht(e.localPosition))),
          onExit: (_) => setState(() => _maus = null),
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _zoomen(e.localPosition, e.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15);
            },
            onPointerPanZoomUpdate: (e) {
              setState(() => _pan += e.panDelta);
              if (e.scale != 1) _zoomen(e.localPosition, e.scale.clamp(0.9, 1.1));
            },
            onPointerDown: (e) {
              if (e.buttons == kMiddleMouseButton || e.buttons == kSecondaryMouseButton) {
                _panStart = e.localPosition;
                return;
              }
              if (e.buttons == kPrimaryButton && _doppel.erkannt(e.localPosition)) _eigFenster.nachKlickOeffnen(context);
              if (e.buttons != kPrimaryMouseButton) return;
              _fokus.requestFocus();
              final a = _gerastert(_zuAnsicht(e.localPosition));
              if (_zeichnen) {
                final p = _leitungFangen(_zuAnsicht(e.localPosition));
                if (_entwurf.isNotEmpty && (_entwurf.last - p).distance < 1) {
                  _leitungAbschliessen(); // gleicher Punkt = fertig
                } else {
                  final linie = _fangLinie;
                  setState(() {
                    _entwurf.add(p);
                    _entwurfBezug.add(_fangBezug);
                  });
                  if (linie != null && _entwurf.length >= 2) _uebergabeFragen(e.position, linie);
                }
                return;
              }
              if (_setzen) {
                _objektSetzen(a);
                return;
              }
              final id = _treffer(_zuAnsicht(e.localPosition)) ?? _trefferZug(_zuAnsicht(e.localPosition));
              final zusatz = HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isControlPressed;
              setState(() {
                if (id == null) {
                  if (!zusatz) _mehr.clear();
                  _rahmenA = _zuAnsicht(e.localPosition);
                  _rahmenB = _rahmenA;
                } else if (zusatz) {
                  if (_auswahl != null) _mehr.add(_auswahl!);
                  if (!_mehr.remove(id)) _mehr.add(id);
                } else if (!_mehr.contains(id)) {
                  _mehr.clear();
                }
                _auswahl = id ?? (zusatz ? _auswahl : null);
                _ziehStart = id == null ? null : a;
                _versatz = Offset.zero;
              });
            },
            onPointerMove: (e) {
              final ps = _panStart;
              if (ps != null) {
                setState(() {
                  _pan += e.localPosition - ps;
                  _panStart = e.localPosition;
                });
                return;
              }
              if (_rahmenA != null) {
                setState(() => _rahmenB = _zuAnsicht(e.localPosition));
                return;
              }
              final s = _ziehStart;
              if (s == null) return;
              setState(() => _versatz = _gerastert(_zuAnsicht(e.localPosition)) - s);
            },
            onPointerUp: (_) {
              if (_panStart != null) {
                _panStart = null;
                return;
              }
              final ra = _rahmenA, rb = _rahmenB;
              if (ra != null) {
                final r = Rect.fromPoints(ra, rb ?? ra);
                setState(() {
                  _rahmenA = null;
                  _rahmenB = null;
                  if (r.width * _massstab > 4 || r.height * _massstab > 4) {
                    for (final (o, x, z) in _punkte) {
                      if (r.contains(Offset(x, z))) _mehr.add(o.id);
                    }
                    if (_mehr.isNotEmpty) _auswahl ??= _mehr.first;
                  }
                });
                return;
              }
              final id = _auswahl, d = _versatz;
              setState(() {
                _ziehStart = null;
                _versatz = Offset.zero;
              });
              if (id != null && d != Offset.zero) {
                for (final x in (_mehr.contains(id) ? {..._mehr} : {id})) {
                  _verschieben(x, d);
                }
              }
            },
            child: CustomPaint(
              size: Size.infinite,
              painter: _AnsichtPainter(
                dachHoehe: _dachHoehe(),
                seite: _seite,
                h: _h,
                oeffnungen: _oeffnungen,
                punkte: [
                  for (final (o, x, z) in _punkte)
                    () {
                      final mit = o.id == _auswahl || (_mehr.contains(_auswahl) && _mehr.contains(o.id));
                      return (o, mit ? x + _versatz.dx : x, mit ? z + _versatz.dy : z);
                    }()
                ],
                leitungen: _leitungen,
                zuege: _zuege,
                andock: [for (final a in _andock) (a.xz, a.text, a.bezug.containsKey('leitung'))],
                fangText: _zeichnen ? _fangText : null,
                schraenke: _schraenke,
                entwurf: List.of(_entwurf),
                typen: _typen,
                gewerke: _gewerke,
                auswahl: _auswahl,
                massstab: _massstab,
                ursprung: _ursprung,
                mehr: _mehr,
                rahmen: _rahmenA == null || _rahmenB == null ? null : Rect.fromPoints(_rahmenA!, _rahmenB!),
                maus: _setzen || _zeichnen ? _maus : null,
                raster: _rasterZeigen ? _rasterMm : 0,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _hilfe() => ListView(children: [
        Text('Wandansicht', style: Theme.of(context).textTheme.titleMedium),
        Text('${_punkte.length} Objekte · ${_zuege.length} Leitungen · ${_oeffnungen.length} Öffnungen',
            style: const TextStyle(color: BsFarben.textLeise)),
        const SizedBox(height: 8),
        Text(
          'Blick von ${_seite.raum?.name ?? 'außen'} auf die Wand. Unten die Maßkette ab der linken Wandkante, '
          'neben jedem Objekt die Höhe mit Bezug.\n\n'
          'Setzen (P): Objekttyp wählen und in die Wand klicken – Höhe über FFB.\n'
          'Auswahl (V): Objekt anklicken und ziehen (Lage und Höhe, 10-mm-Raster), Entf löscht, Strg+Z macht rückgängig.\n\n'
          'Leitung (L): Leitungstyp wählen (z. B. Heizrohr, Vorlauf) und Punkte klicken – auch senkrecht, etwa die Anbindeleitungen '
          'zum Heizkreisverteiler. Der Fang greift an Objekten und an der Unterkante des Verteilerschranks; Umschalt = waagerecht/senkrecht, '
          'Enter oder zweiter Klick auf denselben Punkt beendet, Rücktaste nimmt den letzten Punkt zurück.\n\n'
          'Türen und Fenster in Rohbaumaßen ab RFB. Leitungen erscheinen, wenn sie in oder an dieser Wand verlaufen.',
          style: const TextStyle(height: 1.45),
        ),
      ]);

  Widget _details((Objekt, double, double) e) {
    final (o, x, z) = e;
    final typ = _typen[o.typId];
    final store = _s.store!;
    return ListView(children: [
      Text(typ?.name ?? '', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Text(o.kennung, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Text('${mmText(x)} mm von der linken Wandkante'),
      Text('${mmText(_seite.laenge - x)} mm von der rechten Wandkante'),
      const SizedBox(height: 8),
      for (final b in Hoehenbezug.values) Text('${mmText(((z - _h.von(b)) * b.richtung).round())} ${b.label}'),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () {
          store.objektLoeschen(o.id);
          _rueckgaengig.add(() => store.objektWiederherstellen(o.id));
          setState(() => _auswahl = null);
          _s.geaendert();
        },
        icon: const Icon(Sym.loeschen),
        label: const Text('Löschen (Entf)'),
      ),
    ]);
  }


  /// Text zu einem Leitungsende: angeschlossenes Gerät oder fortgesetzte Leitung.
  String? _bezugText(Objekt o, String ende) {
    final b = leitungsBezug(o, ende);
    if (b == null) return null;
    final ziel = _alleObjekte.where((x) => x.id == (b['objekt'] ?? b['leitung'])).firstOrNull;
    if (ziel == null) return null;
    return b.containsKey('anschluss') ? 'Anschluss ${b['anschluss']} an ${ziel.kennung}' : 'Fortsetzung von/zu ${ziel.kennung}';
  }
  Widget _zugDetails((Objekt, List<Offset>) e) {
    final (o, pts) = e;
    final typ = _typen[o.typId];
    final store = _s.store!;
    var senkrecht = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      senkrecht += (pts[i + 1].dy - pts[i].dy).abs();
    }
    return ListView(children: [
      Text(typ?.name ?? '', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Text(o.kennung, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Text('Länge ${meterText(o.laenge)} (davon senkrecht ${meterText(senkrecht)})'),
      Text('${pts.length} Punkte, von ${mmText(pts.first.dy - _h.ffb)} bis ${mmText(pts.last.dy - _h.ffb)} mm über FFB'),
      const SizedBox(height: 12),
      for (final (ende, label) in const [('uebergang_anfang', 'Übergang am Anfang'), ('uebergang_ende', 'Übergang am Ende')])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DropdownButtonFormField<String?>(
            key: ValueKey('$ende-${o.id}-${o.eigenschaften[ende]}'),
            initialValue: uebergangsLagen.contains(o.eigenschaften[ende]) ? o.eigenschaften[ende] as String : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              const DropdownMenuItem(value: null, child: Text('– bleibt in der Wand –')),
              for (final l in uebergangsLagen) DropdownMenuItem(value: l, child: Text('${uebergangsPfeil(l)} ab hier $l')),
            ],
            onChanged: (v) {
              final neu = {...o.eigenschaften};
              if (v == null) {
                neu.remove(ende);
              } else {
                neu[ende] = v;
              }
              final alt = store.objektAendern(o.id, {'eigenschaften': jsonEncode(neu)});
              _rueckgaengig.add(() => store.objektAendern(o.id, alt));
              _s.geaendert();
            },
          ),
        ),
      for (final (ende, label) in const [('anfang', 'Anfang'), ('ende', 'Ende')])
        if (_bezugText(o, ende) case final t?) Text('$label: $t', style: const TextStyle(fontSize: 12)),
      if (leitungsZug(o.id, _alleObjekte).length > 1)
        Text(
            'Leitungszug: ${[for (final x in _alleObjekte) if (leitungsZug(o.id, _alleObjekte).contains(x.id)) x.kennung].join(' → ')}',
            style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const Text(
          'Im Grundriss an den Übergangspunkt anschließen (der Fang greift dort) – die Leitungen bleiben als ein Zug verbunden.',
          style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () {
          store.objektLoeschen(o.id);
          _rueckgaengig.add(() => store.objektWiederherstellen(o.id));
          setState(() => _auswahl = null);
          _s.geaendert();
        },
        icon: const Icon(Sym.loeschen),
        label: const Text('Löschen (Entf)'),
      ),
    ]);
  }
}

class _AnsichtPainter extends CustomPainter {
  _AnsichtPainter({
    required this.seite,
    required this.h,
    required this.oeffnungen,
    required this.punkte,
    required this.leitungen,
    required this.zuege,
    required this.andock,
    required this.fangText,
    required this.schraenke,
    required this.entwurf,
    required this.typen,
    required this.gewerke,
    required this.auswahl,
    required this.massstab,
    required this.ursprung,
    required this.maus,
    this.raster = 0,
    this.dachHoehe,
    this.mehr = const {},
    this.rahmen,
  });

  /// Mehrfachauswahl und Auswahlrahmen (Ansichtskoordinaten x, z).
  final Set<String> mehr;
  final Rect? rahmen;

  /// Höhe der Dachschräge über FFB an Ansichts-x (Dachgeschoss), sonst null.
  final double? Function(double x)? dachHoehe;

  /// Rasterweite in mm (0 = kein Raster).
  final int raster;

  final WandSeite seite;
  final Bezugshoehen h;
  final List<Oeffnung> oeffnungen;
  final List<(Objekt, double, double)> punkte;
  final List<(Objekt, double, double, double)> leitungen;
  final List<(Objekt, List<Offset>)> zuege;
  final List<(Offset, String, bool)> andock; // Lage, Text, Fortsetzung einer Leitung
  final String? fangText;
  final List<(Objekt, Rect)> schraenke;
  final List<Offset> entwurf;
  final Map<String, Objekttyp> typen;
  final Map<String, Gewerk> gewerke;
  final String? auswahl;
  final double massstab;
  final Offset ursprung; // Bildschirmpunkt für x = 0, z = RFB
  final Offset? maus;

  Offset _p(double x, double z) => Offset(ursprung.dx + x * massstab, ursprung.dy - (z - h.rfb) * massstab);

  void _text(Canvas c, String t, Offset p, {Color farbe = BsFarben.textLeise, double groesse = 11, bool mitte = false, bool fett = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(fontSize: groesse, color: farbe, fontWeight: fett ? FontWeight.w600 : FontWeight.w400,
            backgroundColor: Colors.white.withValues(alpha: 0.8)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, mitte ? p - Offset(tp.width / 2, tp.height / 2) : p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final l = seite.laenge;
    // Wandfläche
    final flaeche = Rect.fromPoints(_p(0, h.rohdecke.toDouble()), _p(l, h.rfb.toDouble()));
    canvas.drawRect(flaeche, Paint()..color = const Color(0xFFF1EEE6));
    if (raster > 0 && raster * massstab >= 4) {
      final rp = Paint()
        ..color = const Color(0x22000000)
        ..strokeWidth = 0.6;
      for (var x = 0.0; x <= l; x += raster) {
        canvas.drawLine(_p(x, h.rfb.toDouble()), _p(x, h.rohdecke.toDouble()), rp);
      }
      for (var z = (h.rfb / raster).ceil() * raster.toDouble(); z <= h.rohdecke; z += raster) {
        canvas.drawLine(_p(0, z), _p(l, z), rp);
      }
    }
    canvas.drawRect(flaeche, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = BsFarben.wandBestand);
    // Dachschräge: Fläche oberhalb der Schräge ist keine Wand mehr
    final dh = dachHoehe;
    if (dh != null) {
      final linie = <Offset>[];
      var unterDecke = false;
      for (var i = 0; i <= 200; i++) {
        final x = l * i / 200;
        final hz = dh(x);
        if (hz == null) continue;
        final z = math.min(h.ffb + hz, h.rohdecke.toDouble());
        if (z < h.rohdecke - 1) unterDecke = true;
        linie.add(_p(x, z));
      }
      if (unterDecke && linie.length > 1) {
        final schraege = Path()..moveTo(linie.first.dx, _p(0, h.rohdecke.toDouble()).dy);
        for (final q in linie) {
          schraege.lineTo(q.dx, q.dy);
        }
        schraege
          ..lineTo(linie.last.dx, _p(0, h.rohdecke.toDouble()).dy)
          ..close();
        canvas.drawPath(schraege, Paint()..color = const Color(0xFFE9ECEF));
        canvas.save();
        canvas.clipPath(schraege);
        final schraffur = Paint()
          ..color = const Color(0x338D6E63)
          ..strokeWidth = 1;
        for (var x = flaeche.left - flaeche.height; x < flaeche.right; x += 10) {
          canvas.drawLine(Offset(x, flaeche.bottom), Offset(x + flaeche.height, flaeche.top), schraffur);
        }
        canvas.restore();
        canvas.drawPath(Path()..addPolygon(linie, false), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF8D6E63));
        final tief = linie.reduce((a, b) => a.dy > b.dy ? a : b);
        _text(canvas, 'Dachschräge', tief + const Offset(6, -18), farbe: const Color(0xFF8D6E63), groesse: 10);
      }
    }
    // Bezugslinien
    for (final (z, name, farbe, gestrichelt) in [
      (h.ffb, 'FFB', const Color(0xFF2F9E44), false),
      (h.meterriss, 'Meterriss', BsFarben.akzent, true),
      (h.rohdecke, 'Rohdecke', BsFarben.wandBestand, false),
      (h.rfb, 'RFB', BsFarben.wandBestand, false),
    ]) {
      final a = _p(-300, z.toDouble()), b = _p(l + 300, z.toDouble());
      final p = Paint()
        ..color = farbe
        ..strokeWidth = 1;
      if (gestrichelt) {
        for (var x = a.dx; x < b.dx; x += 10) {
          canvas.drawLine(Offset(x, a.dy), Offset(math.min(x + 6, b.dx), a.dy), p);
        }
      } else {
        canvas.drawLine(a, b, p);
      }
      _text(canvas, '$name ${mmText(z)}', Offset(b.dx + 4, b.dy - 7), farbe: farbe, groesse: 10);
    }
    // Öffnungen: Achsparameter → x der Ansicht
    final w = seite.wand;
    final a0 = Offset(w.x1.toDouble(), w.y1.toDouble());
    final u = (Offset(w.x2.toDouble(), w.y2.toDouble()) - a0) / math.max(1.0, w.laenge);
    final kanten = <double>[0, l];
    for (final o in oeffnungen) {
      final x1 = seite.x(a0 + u * o.abstand.toDouble()), x2 = seite.x(a0 + u * (o.abstand + o.breite).toDouble());
      final r = Rect.fromPoints(_p(math.min(x1, x2), (h.rfb + o.bruestung + o.hoehe).toDouble()), _p(math.max(x1, x2), (h.rfb + o.bruestung).toDouble()));
      canvas.drawRect(r, Paint()..color = Colors.white);
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = BsFarben.wandBestand);
      if (o.art.verglast) {
        canvas.drawLine(r.topLeft, r.bottomRight, Paint()..color = Colors.black26);
        canvas.drawLine(r.topRight, r.bottomLeft, Paint()..color = Colors.black26);
      }
      _text(canvas, '${o.art.label} ${mmText(o.breite)} × ${mmText(o.hoehe)}', r.center, mitte: true, groesse: 10);
      if (o.bruestung > 0) _text(canvas, 'Brüstung ${mmText(o.bruestung)}', Offset(r.left + 2, r.bottom + 2), groesse: 9);
      kanten.addAll([math.min(x1, x2), math.max(x1, x2)]);
    }
    // Leitungen in der Wand
    for (final (o, x1, x2, z) in leitungen) {
      final farbe = Color(gewerke[typen[o.typId]?.gewerkId]?.farbe ?? 0xFF888888);
      canvas.drawLine(_p(x1, z), _p(x2, z), Paint()
        ..color = farbe
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round);
      _text(canvas, o.kennung, _p((x1 + x2) / 2, z) + const Offset(0, 4), farbe: farbe, groesse: 9);
    }
    // Verteilerschränke (Unterkante = Höhe des Verteilers)
    for (final (o, r) in schraenke) {
      final farbe = Color(gewerke[typen[o.typId]?.gewerkId]?.farbe ?? 0xFF888888);
      final rect = Rect.fromPoints(_p(r.left, r.bottom), _p(r.right, r.top));
      canvas.drawRect(rect, Paint()..color = farbe.withValues(alpha: o.id == auswahl ? 0.22 : 0.12));
      canvas.drawRect(rect, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = farbe);
      _text(canvas, 'Verteilerschrank ${mmText(r.width)} × ${mmText(r.height)}', Offset(rect.left + 4, rect.top + 4), farbe: farbe, groesse: 9);
    }
    // In der Ansicht gezeichnete Leitungen (mit Steigstrecken); deckungsgleiche
    // Strecken mehrerer Leitungen werden als Bündel nebeneinander gezeichnet.
    final versatz = buendelVersatz([for (final (_, pts) in zuege) pts]);
    for (var i = 0; i < zuege.length; i++) {
      final (o, pts) = zuege[i];
      final farbe = Color(gewerke[typen[o.typId]?.gewerkId]?.farbe ?? 0xFF888888);
      final gewaehlt = o.id == auswahl;
      final bild = versetzterZug([for (final q in pts) _p(q.dx, q.dy)], i, versatz, 5);
      canvas.drawPath(
        Path()..addPolygon(bild, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = farbe
          ..strokeWidth = math.max(gewaehlt ? 4.5 : 3.0, ((o.eigenschaften['breite_mm'] as num?)?.toDouble() ?? 0) * massstab)
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      final m = pts.length >= 2 ? (pts[0] + pts[1]) / 2 : pts.first;
      _text(canvas, '${o.kennung} · ${meterText(o.laenge)}', _p(m.dx, m.dy) + const Offset(5, 3), farbe: farbe, groesse: 9, fett: gewaehlt);
      // Übergang in eine andere Ebene an Anfang/Ende
      for (final (ende, p) in [('uebergang_anfang', bild.first), ('uebergang_ende', bild.last)]) {
        final lage = o.eigenschaften[ende];
        if (lage is! String) continue;
        canvas.drawCircle(p, 6, Paint()..color = Colors.white);
        canvas.drawCircle(p, 6, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = farbe);
        _text(canvas, uebergangsPfeil(lage), p, farbe: farbe, groesse: 9, mitte: true, fett: true);
        _text(canvas, 'ab hier $lage', p + const Offset(9, 2), farbe: farbe, groesse: 9);
      }
    }
    // Andockpunkte: Geräteanschlüsse und ankommende Leitungen
    for (final (q, text, fortsetzung) in andock) {
      final p = _p(q.dx, q.dy);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = fortsetzung ? BsFarben.akzentDunkel : const Color(0xFF495057);
      if (fortsetzung) {
        canvas.drawRect(Rect.fromCenter(center: p, width: 8, height: 8), paint);
        _text(canvas, text, p + const Offset(6, -14), farbe: BsFarben.akzentDunkel, groesse: 9);
      } else {
        canvas.drawCircle(p, 3, paint);
        if (massstab > 0.25) _text(canvas, text.split(' ').skip(1).join(' '), p + const Offset(-8, 5), groesse: 8);
      }
    }
    // Entwurf einer Leitung
    if (entwurf.isNotEmpty) {
      final e = [for (final q in entwurf) _p(q.dx, q.dy), if (maus != null) _p(maus!.dx, maus!.dy)];
      canvas.drawPath(
        Path()..addPolygon(e, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = BsFarben.akzent.withValues(alpha: 0.8)
          ..strokeWidth = 2.5,
      );
      var l = 0.0;
      final alle = [...entwurf, if (maus != null) maus!];
      for (var i = 0; i + 1 < alle.length; i++) {
        l += (alle[i + 1] - alle[i]).distance;
      }
      _text(canvas, meterText(l), e.last + const Offset(10, -18), farbe: BsFarben.akzentDunkel, groesse: 10, fett: true);
    }
    // Objekte mit Höhe
    for (final (o, x, z) in punkte) {
      // Technikgerät mit Maßen: Ansicht als Rechteck (Breite × Höhe ab Unterkante)
      final masse = o.eigenschaften['masse'];
      if (masse is List && masse.length >= 3) {
        final b = (masse[0] as num).toDouble(), hh = (masse[2] as num).toDouble();
        final r = Rect.fromPoints(_p(x - b / 2, z + hh), _p(x + b / 2, z));
        final f = Color(gewerke[typen[o.typId]?.gewerkId]?.farbe ?? 0xFF888888);
        canvas.drawRect(r, Paint()..color = f.withValues(alpha: 0.12));
        canvas.drawRect(r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = o.id == auswahl ? 2.5 : 1.4
          ..color = f);
        _text(canvas, '${o.eigenschaften['geraet'] ?? o.kennung}\n${b.round()} × ${hh.round()}', r.center, farbe: f, groesse: 9, mitte: true);
        kanten.addAll([x - b / 2, x + b / 2]);
        continue;
      }
      final typ = typen[o.typId];
      final farbe = Color(gewerke[typ?.gewerkId]?.farbe ?? 0xFF888888);
      final c = _p(x, z);
      final gewaehlt = o.id == auswahl || mehr.contains(o.id);
      final doseD = (o.eigenschaften['dose_d'] as num?)?.toDouble() ?? 68;
      final r = math.max(6.0, doseD * massstab / 2); // reale Dose
      // Abdeckrahmen (einzeln 80 × 80 mm, mehrfach im 71-mm-Raster)
      final rahmen = o.eigenschaften['rahmen'];
      if (rahmen is Map && massstab * 71 > 8) {
        final n = (rahmen['fach'] as num?)?.toInt() ?? 1;
        final senk = rahmen['richtung'] == 's';
        final inhalt = [for (final t in (rahmen['inhalt'] as List? ?? const [])) '$t'];
        final lang = 80 + (n - 1) * 71.0;
        final rr = senk ? Rect.fromCenter(center: _p(x, z - (n - 1) * 35.5), width: 80 * massstab, height: lang * massstab)
            : Rect.fromCenter(center: _p(x + (n - 1) * 35.5, z), width: lang * massstab, height: 80 * massstab);
        canvas.drawRRect(RRect.fromRectAndRadius(rr, Radius.circular(6 * massstab)), Paint()..color = Colors.white);
        canvas.drawRRect(RRect.fromRectAndRadius(rr, Radius.circular(6 * massstab)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = farbe.withValues(alpha: 0.7));
        for (var i = 1; i < n; i++) {
          final mi = senk ? _p(x, z - i * 71.0) : _p(x + i * 71.0, z);
          canvas.drawCircle(mi, r, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = farbe);
          if (i < inhalt.length) _text(canvas, inhalt[i], mi, farbe: farbe, groesse: 8, mitte: true, fett: true);
        }
      } else if (massstab * 80 > 10) {
        canvas.drawRect(Rect.fromCenter(center: c, width: 80 * massstab, height: 80 * massstab), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = farbe.withValues(alpha: 0.5));
      }
      canvas.drawCircle(c, r, Paint()..color = Colors.white);
      canvas.drawCircle(c, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = gewaehlt ? 3 : 2
        ..color = farbe);
      _text(canvas, typ?.kuerzel ?? '?', c, farbe: farbe, groesse: 8, mitte: true, fett: true);
      final bezug = o.zBezug ?? Hoehenbezug.ffb;
      final wert = ((z - h.von(bezug)) * bezug.richtung).round();
      _text(canvas, '${o.kennung}\n${mmText(wert)} ${bezug.kurz}', c + Offset(r + 4, -10), farbe: farbe, groesse: 9, fett: gewaehlt);
      kanten.add(x);
      if (gewaehlt) {
        // Hilfslinien zu den Wandkanten
        final p = Paint()
          ..color = BsFarben.akzent
          ..strokeWidth = 0.8;
        canvas.drawLine(_p(0, z), c, p);
        canvas.drawLine(_p(x, h.rfb.toDouble()), c, p);
      }
    }
    // Maßkette unten
    kanten.sort();
    final yKette = _p(0, h.rfb.toDouble()).dy + 26;
    final linie = Paint()
      ..color = const Color(0xFF3B5BA9)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(_p(0, 0).dx, yKette), Offset(_p(l, 0).dx, yKette), linie);
    double? letzte;
    for (final k in kanten) {
      final x = _p(k, 0).dx;
      canvas.drawLine(Offset(x - 4, yKette + 4), Offset(x + 4, yKette - 4), linie..strokeWidth = 1.6);
      if (letzte != null && k - letzte >= 1) {
        _text(canvas, mmText(k - letzte), Offset((x + _p(letzte, 0).dx) / 2, yKette - 9), farbe: const Color(0xFF3B5BA9), groesse: 10, mitte: true);
      }
      letzte = k;
    }
    _text(canvas, 'Gesamt ${mmText(l)}', Offset(_p(l / 2, 0).dx, yKette + 14), farbe: const Color(0xFF3B5BA9), groesse: 10, mitte: true, fett: true);
    // Vorschau beim Setzen
    final m = maus;
    if (m != null) {
      final c = _p(m.dx, m.dy);
      final p = Paint()
        ..color = BsFarben.akzentDunkel
        ..strokeWidth = 1;
      canvas.drawLine(c.translate(-8, 0), c.translate(8, 0), p);
      canvas.drawLine(c.translate(0, -8), c.translate(0, 8), p);
      _text(canvas, '${mmText(m.dx)} | ${mmText(m.dy - h.ffb)} über FFB', c + const Offset(10, 6), farbe: BsFarben.akzentDunkel, groesse: 10);
      if (fangText != null) _text(canvas, fangText!, c + const Offset(10, 22), farbe: BsFarben.akzentDunkel, groesse: 10, fett: true);
    }
    final rr = rahmen;
    if (rr != null) {
      final r = Rect.fromPoints(_p(rr.left, rr.top), _p(rr.right, rr.bottom));
      canvas.drawRect(r, Paint()..color = BsFarben.akzent.withValues(alpha: 0.08));
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..color = BsFarben.akzent);
    }
  }

  @override
  bool shouldRepaint(covariant _AnsichtPainter old) => true;
}
