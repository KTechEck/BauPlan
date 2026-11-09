import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/height.dart';
import '../../core/licht.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../tastenkuerzel.dart';
import '../widgets.dart';

/// Typen, die an oder in der Decke sitzen (Vorauswahl).
const deckenTypen = {'LE', 'PM', 'BM', 'LV', 'AP', 'KG', 'ES', 'DO', 'MP'};

bool istDeckenObjekt(Objekt o, Objekttyp? t) =>
    o.lage == 'an Decke' || o.lage == 'in Decke' || o.zBezug == Hoehenbezug.rohdecke || (t != null && deckenTypen.contains(t.kuerzel) && o.lage == null);

/// Deckenansicht eines Raums: von oben (deckungsgleich mit dem Grundriss)
/// oder von unten (gespiegelt, wie man beim Montieren hochschaut).
class DeckePage extends StatefulWidget {
  const DeckePage({super.key, required this.state, required this.raumId});
  final AppState state;
  final String raumId;

  @override
  State<DeckePage> createState() => _DeckePageState();
}

class _DeckePageState extends State<DeckePage> {
  final _eigFenster = EigenschaftenFenster();
  final _doppel = Doppelklick();
  final _fokus = FocusNode();
  bool _vonUnten = true;
  bool _setzen = false;
  String? _typId;
  String? _auswahl;
  final Set<String> _mehr = {}; // Mehrfachauswahl
  Offset? _rahmenA, _rahmenB; // Welt
  Offset? _ziehStart;
  Offset _versatz = Offset.zero;
  Offset? _maus;
  Size _flaeche = Size.zero;
  final List<VoidCallback> _rueckgaengig = [];
  bool _lichtAnzeigen = false; // Lichtverteilung als Farbfläche
  bool _ledZeichnen = false; // LED-Streifen zeichnen (L)
  final List<Offset> _ledEntwurf = [];
  LichtErgebnis? _licht;
  String? _lichtSchluessel;

  AppState get _s => widget.state;

  @override
  void dispose() {
    _fokus.dispose();
    super.dispose();
  }

  // Daten
  Raum? _raum;
  late Bezugshoehen _h;
  late List<Objekt> _objekte; // Deckenobjekte im Raum
  late List<Objekt> _leitungen;
  late Map<String, Objekttyp> _typen;
  late Map<String, Gewerk> _gewerke;
  late Rect _grenzen;

  bool _laden() {
    final store = _s.store!;
    final gid = _s.geschossId;
    final raum = gid == null ? null : store.raeume(gid).where((r) => r.id == widget.raumId).firstOrNull;
    final g = gid == null ? null : store.geschoss(gid);
    if (raum == null || raum.umriss == null || g == null) return false;
    _raum = raum;
    _h = raum.hoehen(g);
    _typen = {for (final t in store.objekttypen()) t.id: t};
    _gewerke = {for (final x in store.gewerke()) x.id: x};
    bool imRaum(Punkt p) => punktInPolygon(p, raum.umriss!);
    _objekte = [];
    _leitungen = [];
    for (final o in store.objekte(gid!)) {
      final t = _typen[o.typId];
      if (t == null || o.punkte.isEmpty) continue;
      if (t.geometrie == Geometrieart.punkt) {
        if ((o.raumId == raum.id || imRaum(o.punkte.first)) && istDeckenObjekt(o, t)) _objekte.add(o);
      } else if (t.geometrie == Geometrieart.linie && (o.lage == 'an Decke' || o.lage == 'in Decke')) {
        if (o.punkte.any(imRaum)) _leitungen.add(o);
      }
    }
    final xs = raum.umriss!.map((p) => p.x), ys = raum.umriss!.map((p) => p.y);
    _grenzen = Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
    return true;
  }

  // Bildschirm ↔ Welt (mit Spiegelung „von unten“)
  double get _massstab => math.max(0.01, math.min((_flaeche.width - 160) / _grenzen.width, (_flaeche.height - 160) / _grenzen.height));

  Offset _s2(Offset w) {
    final m = _massstab;
    final x = _vonUnten ? _grenzen.right - (w.dx - _grenzen.left) : w.dx;
    return Offset((_flaeche.width - _grenzen.width * m) / 2 + (x - _grenzen.left) * m,
        (_flaeche.height - _grenzen.height * m) / 2 + (w.dy - _grenzen.top) * m);
  }

  Offset _zuWelt(Offset b) {
    final m = _massstab;
    var x = (b.dx - (_flaeche.width - _grenzen.width * m) / 2) / m + _grenzen.left;
    final y = (b.dy - (_flaeche.height - _grenzen.height * m) / 2) / m + _grenzen.top;
    if (_vonUnten) x = _grenzen.right - (x - _grenzen.left);
    return Offset((x / 10).round() * 10.0, (y / 10).round() * 10.0);
  }

  String? _treffer(Offset welt) {
    final tol = 12 / _massstab;
    String? id;
    var best = tol;
    for (final o in _objekte) {
      final d = (Offset(o.punkte.first.x, o.punkte.first.y) - welt).distance;
      if (d < best) {
        best = d;
        id = o.id;
      }
    }
    if (id != null) return id;
    for (final o in _leitungen) {
      for (var i = 0; i + 1 < o.punkte.length; i++) {
        final d = _abstandStrecke(welt, Offset(o.punkte[i].x, o.punkte[i].y), Offset(o.punkte[i + 1].x, o.punkte[i + 1].y));
        if (d < best) {
          best = d;
          id = o.id;
        }
      }
    }
    return id;
  }


  static double _abstandStrecke(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = l2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    return (a + ab * t - p).distance;
  }

  /// Höhe eines Deckenobjekts über FFB.
  double _hoeheUeberFfb(Objekt o) {
    final zAbs = o.z != null && o.zBezug != null ? absolut(o.z!, o.zBezug!, _h) : _h.rohdecke;
    return (zAbs - _h.ffb).toDouble();
  }

  /// Leuchten des Raums für die Lichtrechnung.
  List<LichtQuelle> get _quellen => [
        for (final o in _objekte)
          if (_typen[o.typId]?.kuerzel == 'LE')
            (
              x: o.punkte.first.x,
              y: o.punkte.first.y,
              hoehe: _hoeheUeberFfb(o),
              lumen: (o.eigenschaften['lumen'] as num?)?.toDouble() ?? 800,
              winkel: (o.eigenschaften['winkel'] as num?)?.toDouble() ?? 90,
            ),
      ];

  /// Lichtstrom der LED-Streifen im Raum (für den indirekten Anteil).
  double get _indirektLumen => [
        for (final o in _leitungen)
          if (_typen[o.typId]?.kuerzel == 'LB') o.laenge / 1000 * ((o.eigenschaften['lm_pro_m'] as num?)?.toDouble() ?? 800)
      ].fold(0.0, (a, b) => a + b);

  int get _ziel {
    final m = _s.store!.einstellung<Map>('licht_ziel');
    return (m?[_raum!.id] as num?)?.toInt() ?? zielBeleuchtung(_raum!.name);
  }

  LichtErgebnis _lichtBerechnen() {
    final q = _quellen;
    final schluessel = '${_raum!.id}|${q.map((e) => '${e.x},${e.y},${e.hoehe},${e.lumen},${e.winkel}').join(';')}|$_indirektLumen|${_raum!.umriss!.length}';
    if (_lichtSchluessel != schluessel || _licht == null) {
      _licht = lichtraster(_raum!.umriss!, q, raster: math.max(100, math.max(_grenzen.width, _grenzen.height) / 40), indirektLumen: _indirektLumen);
      _lichtSchluessel = schluessel;
    }
    return _licht!;
  }

  void _ledAbschliessen() {
    final pts = List.of(_ledEntwurf);
    setState(_ledEntwurf.clear);
    if (pts.length < 2) return;
    final t = _typen.values.where((x) => x.kuerzel == 'LB').firstOrNull;
    if (t == null) return;
    final store = _s.store!;
    final id = store.objektAnlegen(
      geschossId: _s.geschossId!,
      typ: t,
      punkte: [for (final p in pts) Punkt(p.dx, p.dy)],
      raumId: _raum!.id,
      z: _raum!.ukDecke == null ? 0 : _h.rohdecke - _raum!.ukDecke!,
      zBezug: Hoehenbezug.rohdecke,
      lage: _raum!.ukDecke == null ? 'an Decke' : 'in Decke',
    );
    _rueckgaengig.add(() => store.objektLoeschen(id));
    _s.geaendert();
  }
  void _setzenBei(Offset w) {
    final t = _typen[_typId];
    if (t == null) return;
    final store = _s.store!;
    final id = store.objektAnlegen(
      geschossId: _s.geschossId!,
      typ: t,
      punkte: [Punkt(w.dx, w.dy)],
      raumId: _raum!.id,
      z: _raum!.ukDecke == null ? 0 : _h.rohdecke - _raum!.ukDecke!,
      zBezug: Hoehenbezug.rohdecke,
      lage: _raum!.ukDecke == null ? 'an Decke' : 'in Decke',
    );
    _rueckgaengig.add(() => store.objektLoeschen(id));
    _s.geaendert();
  }

  void _verschieben(String id, Offset d) {
    final o = _objekte.where((e) => e.id == id).firstOrNull;
    if (o == null || d == Offset.zero) return;
    final store = _s.store!;
    final p = o.punkte.first;
    final alt = store.objektAendern(id, {'geometrie': Objekt.geometrieText([Punkt(p.x + d.dx, p.y + d.dy)])});
    _rueckgaengig.add(() => store.objektAendern(id, alt));
    _s.geaendert();
  }

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
      if (_ledEntwurf.isNotEmpty) {
        setState(_ledEntwurf.clear);
      } else if (_auswahl == null && !_setzen && !_ledZeichnen) {
        Navigator.maybePop(context);
      } else {
        setState(() {
          _auswahl = null;
          _setzen = false;
          _ledZeichnen = false;
        });
      }
    } else if (_ledZeichnen && (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter)) {
      _ledAbschliessen();
    } else if (!strg && (k == LogicalKeyboardKey.keyV || k == LogicalKeyboardKey.keyP || k == LogicalKeyboardKey.keyL)) {
      setState(() {
        _setzen = k == LogicalKeyboardKey.keyP;
        _ledZeichnen = k == LogicalKeyboardKey.keyL;
        _ledEntwurf.clear();
      });
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        if (!_laden()) {
          return Scaffold(
              appBar: AppBar(title: const Text('Deckenansicht')),
              body: const Center(child: Text('Raum ohne Umriss – erst im Grundriss verorten.')));
        }
        final raum = _raum!;
        final punktTypen = _typen.values.where((t) => t.geometrie == Geometrieart.punkt).toList()
          ..sort((a, b) => (deckenTypen.contains(b.kuerzel) ? 1 : 0) - (deckenTypen.contains(a.kuerzel) ? 1 : 0));
        _typId ??= punktTypen.where((t) => t.kuerzel == 'LE').firstOrNull?.id ?? punktTypen.firstOrNull?.id;
        final gewaehlt = _objekte.where((o) => o.id == _auswahl).firstOrNull ?? _leitungen.where((o) => o.id == _auswahl).firstOrNull;
        _eigFenster.setzen(auswahl: gewaehlt != null, bauen: () => gewaehlt == null ? const SizedBox() : _details(gewaehlt));
        return Scaffold(
          backgroundColor: BsFarben.flaeche,
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: Text('Deckenansicht · ${raum.name} · ${_vonUnten ? 'von unten (gespiegelt)' : 'von oben'}'),
            actions: [
              TextButton.icon(
                onPressed: () => setState(() => _vonUnten = !_vonUnten),
                icon: const Icon(Sym.umdrehen),
                label: Text(_vonUnten ? 'von oben zeigen' : 'von unten zeigen'),
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
                  WerkzeugKnopf(symbol: Sym.auswahl, text: 'Auswahl', tooltip: 'Auswahl (V)', aktiv: !_setzen && !_ledZeichnen, onTap: () => setState(() {
                        _setzen = false;
                        _ledZeichnen = false;
                      })),
                  WerkzeugKnopf(symbol: Sym.setzen, text: 'Setzen', tooltip: 'Objekt setzen (P)', aktiv: _setzen, onTap: () => setState(() {
                        _setzen = true;
                        _ledZeichnen = false;
                      })),
                  WerkzeugKnopf(symbol: Sym.leitung, text: 'LED-Streifen', tooltip: 'LED-Streifen / Lichtband zeichnen (L): Punkte klicken, Enter beendet', aktiv: _ledZeichnen, onTap: () => setState(() {
                        _ledZeichnen = true;
                        _setzen = false;
                      })),
                ]),
                FilterChip(
                  label: const Text('Lichtverteilung'),
                  avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
                  selected: _lichtAnzeigen,
                  onSelected: (v) => setState(() => _lichtAnzeigen = v),
                ),
                DropdownButton<String>(
                  value: _typId,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final t in punktTypen)
                      DropdownMenuItem(
                        value: t.id,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 10, height: 10, color: Color(_gewerke[t.gewerkId]?.farbe ?? 0xFF888888)),
                          const SizedBox(width: 6),
                          Text('${t.name} (${t.kuerzel})'),
                        ]),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _typId = v;
                    _setzen = true;
                  }),
                ),
              ]),
            ),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: ClipRect(child: _flaecheWidget())),
                Container(
                  width: 290,
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: gewaehlt == null ? _aufbau(raum) : _eigFenster.seitenleiste(() => _details(gewaehlt)),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _flaecheWidget() => LayoutBuilder(builder: (context, c) {
        _flaeche = Size(c.maxWidth, c.maxHeight);
        return Focus(
          focusNode: _fokus,
          autofocus: true,
          onKeyEvent: _taste,
          child: MouseRegion(
            cursor: _setzen ? SystemMouseCursors.precise : SystemMouseCursors.basic,
            onHover: (e) => setState(() => _maus = _zuWelt(e.localPosition)),
            onExit: (_) => setState(() => _maus = null),
            child: Listener(
              onPointerDown: (e) {
                if (e.buttons == kPrimaryButton && _doppel.erkannt(e.localPosition)) _eigFenster.nachKlickOeffnen(context);
                if (e.buttons != kPrimaryMouseButton) return;
                _fokus.requestFocus();
                final w = _zuWelt(e.localPosition);
                if (_ledZeichnen) {
                  if (_ledEntwurf.isNotEmpty && (_ledEntwurf.last - w).distance < 1) {
                    _ledAbschliessen();
                  } else {
                    setState(() => _ledEntwurf.add(w));
                  }
                  return;
                }
                if (_setzen) {
                  _setzenBei(w);
                  return;
                }
                final id = _treffer(w);
                final zusatz = HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isControlPressed;
                setState(() {
                  if (id == null) {
                    if (!zusatz) _mehr.clear();
                    _rahmenA = w;
                    _rahmenB = w;
                  } else if (zusatz) {
                    if (_auswahl != null) _mehr.add(_auswahl!);
                    if (!_mehr.remove(id)) _mehr.add(id);
                  } else if (!_mehr.contains(id)) {
                    _mehr.clear();
                  }
                  _auswahl = id ?? (zusatz ? _auswahl : null);
                  _ziehStart = id == null ? null : w;
                  _versatz = Offset.zero;
                });
              },
              onPointerMove: (e) {
                if (_rahmenA != null) {
                  setState(() => _rahmenB = _zuWelt(e.localPosition));
                  return;
                }
                final s = _ziehStart;
                if (s != null) setState(() => _versatz = _zuWelt(e.localPosition) - s);
              },
              onPointerUp: (_) {
                final ra = _rahmenA, rb = _rahmenB;
                if (ra != null) {
                  final r = Rect.fromPoints(ra, rb ?? ra);
                  setState(() {
                    _rahmenA = null;
                    _rahmenB = null;
                    if (r.width > 20 || r.height > 20) {
                      for (final o in _objekte) {
                        if (o.punkte.isNotEmpty && r.contains(Offset(o.punkte.first.x, o.punkte.first.y))) _mehr.add(o.id);
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
                if (id != null) {
                  for (final x in (_mehr.contains(id) ? {..._mehr} : {id})) {
                    _verschieben(x, d);
                  }
                }
              },
              child: CustomPaint(size: Size.infinite, painter: _DeckenPainter(this)),
            ),
          ),
        );
      });

  Widget _aufbau(Raum raum) {
    final store = _s.store!;
    final abhaengung = raum.ukDecke == null ? null : _h.rohdecke - raum.ukDecke!;
    return ListView(children: [
      Text('Deckenaufbau', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text('Rohdecke ${mmText(_h.rohdecke)} mm (abs.)'),
      Text('FFB ${mmText(_h.ffb)} mm → lichte Höhe ${mmText((raum.ukDecke ?? _h.rohdecke) - _h.ffb)} mm'),
      const SizedBox(height: 12),
      SpeicherFeld(
        key: ValueKey('uk-${raum.ukDecke}'),
        initialValue: raum.ukDecke?.toString() ?? '',
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Unterkante Decke (abgehängt)',
          suffixText: 'mm',
          helperText: 'leer = keine Abhängung; absolute Höhe im Geschoss',
        ),
        onFieldSubmitted: (v) {
          final alt = raum.ukDecke;
          store.raumHoehenSetzen(raum.id, ukDecke: int.tryParse(v.trim()), ukDeckeLeeren: v.trim().isEmpty);
          _rueckgaengig.add(() => store.raumHoehenSetzen(raum.id, ukDecke: alt, ukDeckeLeeren: alt == null));
          _s.geaendert();
        },
      ),
      if (abhaengung != null) ...[
        const SizedBox(height: 8),
        Text('Abhängehöhe ${mmText(abhaengung)} mm – Leuchten und Melder sitzen „in Decke“.',
            style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      ],
      const Divider(height: 28),
      Text('${_objekte.length} Objekte an der Decke · ${_leitungen.length} Leitungen', style: const TextStyle(color: BsFarben.textLeise)),
      ..._lichtAbschnitt(raum),
      ..._szenenAbschnitt(raum),
      const SizedBox(height: 8),
      const Text(
        'Setzen (P): Leuchte, Melder, Ventil … in die Decke klicken. Ziehen verschiebt, Entf löscht.\n'
        'Präsenz- und Bewegungsmelder zeigen ihren Erfassungsbereich aus der Montagehöhe.\n'
        '„von unten“ ist gespiegelt – so, wie man beim Montieren hochschaut.',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
    ]);
  }


  void _eigAendern(Objekt o, Map<String, Object?> neu) {
    final store = _s.store!;
    final alt = store.objektAendern(o.id, {'eigenschaften': jsonEncode({...o.eigenschaften, ...neu})});
    _rueckgaengig.add(() => store.objektAendern(o.id, alt));
    _s.geaendert();
  }

  Widget _zahlFeld(Objekt o, String schluessel, String label, num vorgabe, {String? einheit}) => SpeicherFeld(
        key: ValueKey('$schluessel-${o.id}-${o.eigenschaften[schluessel]}'),
        initialValue: '${o.eigenschaften[schluessel] ?? vorgabe}',
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
        decoration: InputDecoration(labelText: label, suffixText: einheit),
        onFieldSubmitted: (v) => _eigAendern(o, {schluessel: int.tryParse(v) ?? vorgabe}),
      );

  /// Leuchte: Lichtstrom, Abstrahlwinkel, Lichtfarbe, Leistung, dimmbar.
  List<Widget> _leuchtenFelder(Objekt o) => [
        const SizedBox(height: 12),
        Text('Leuchte', style: Theme.of(context).textTheme.titleSmall),
        Row(children: [
          Expanded(child: _zahlFeld(o, 'lumen', 'Lichtstrom', 800, einheit: 'lm')),
          const SizedBox(width: 8),
          Expanded(child: _zahlFeld(o, 'winkel', 'Abstrahlwinkel', 90, einheit: '°')),
        ]),
        Row(children: [
          Expanded(child: _zahlFeld(o, 'kelvin', 'Lichtfarbe', 3000, einheit: 'K')),
          const SizedBox(width: 8),
          Expanded(child: _zahlFeld(o, 'watt', 'Leistung', 8, einheit: 'W')),
        ]),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('dimmbar'),
          value: o.eigenschaften['dimmbar'] as bool? ?? true,
          onChanged: (v) => _eigAendern(o, {'dimmbar': v}),
        ),
      ];

  /// LED-Streifen: Leistung und Lichtstrom je Meter, Spannung, Richtung, Kanäle; Netzteilprüfung.
  List<Widget> _ledFelder(Objekt o) {
    final spannung = o.eigenschaften['spannung'] as String? ?? '24 V';
    final wpm = (o.eigenschaften['w_pro_m'] as num?)?.toDouble() ?? 10;
    final p = ledPruefung(o.laenge, wpm, spannung);
    return [
      const SizedBox(height: 8),
      Text('Länge ${meterText(o.laenge)}'),
      Row(children: [
        Expanded(child: _zahlFeld(o, 'w_pro_m', 'Leistung', 10, einheit: 'W/m')),
        const SizedBox(width: 8),
        Expanded(child: _zahlFeld(o, 'lm_pro_m', 'Lichtstrom', 800, einheit: 'lm/m')),
      ]),
      DropdownButtonFormField<String>(
        key: ValueKey('sp-${o.id}-$spannung'),
        initialValue: spannung,
        decoration: const InputDecoration(labelText: 'Spannung'),
        items: [for (final s in const ['12 V', '24 V', '48 V', '230 V']) DropdownMenuItem(value: s, child: Text(s))],
        onChanged: (v) => _eigAendern(o, {'spannung': v}),
      ),
      DropdownButtonFormField<String>(
        key: ValueKey('ri-${o.id}-${o.eigenschaften['richtung']}'),
        initialValue: o.eigenschaften['richtung'] as String? ?? 'zur Decke',
        decoration: const InputDecoration(labelText: 'Abstrahlrichtung'),
        items: [for (final s in const ['zur Decke', 'zur Wand', 'nach unten']) DropdownMenuItem(value: s, child: Text(s))],
        onChanged: (v) => _eigAendern(o, {'richtung': v}),
      ),
      DropdownButtonFormField<String>(
        key: ValueKey('ka-${o.id}-${o.eigenschaften['kanaele']}'),
        initialValue: o.eigenschaften['kanaele'] as String? ?? 'einfarbig',
        decoration: const InputDecoration(labelText: 'Lichtfarbe / Kanäle'),
        items: [for (final s in const ['einfarbig', 'Tunable White', 'RGB', 'RGBW']) DropdownMenuItem(value: s, child: Text(s))],
        onChanged: (v) => _eigAendern(o, {'kanaele': v}),
      ),
      const SizedBox(height: 8),
      Text('Leistung ${p.leistung.toStringAsFixed(0)} W → Netzteil ${p.netzteil} W (20 % Reserve), ${p.einspeisungen} Einspeisung(en)'),
      for (final h in p.hinweise) Text('• $h', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
    ];
  }

  /// Lichtplanung des Raums: Zielwert, Ergebnis der Abschätzung, Lichtliste, Melder.
  List<Widget> _lichtAbschnitt(Raum raum) {
    final store = _s.store!;
    final e = _lichtBerechnen();
    final ziel = _ziel;
    final leuchten = [for (final o in _objekte) if (_typen[o.typId]?.kuerzel == 'LE') o];
    final streifen = [for (final o in _leitungen) if (_typen[o.typId]?.kuerzel == 'LB') o];
    final lumen = leuchten.fold<double>(0, (s, o) => s + ((o.eigenschaften['lumen'] as num?)?.toDouble() ?? 800)) + _indirektLumen;
    final watt = leuchten.fold<double>(0, (s, o) => s + ((o.eigenschaften['watt'] as num?)?.toDouble() ?? 8)) +
        streifen.fold<double>(0, (s, o) => s + o.laenge / 1000 * ((o.eigenschaften['w_pro_m'] as num?)?.toDouble() ?? 10));
    final flaeche = (raum.flaeche ?? 0) / 1e6;
    final melder = _melderKreise;
    final frei = melder.isEmpty ? const <Punkt>[] : nichtErfasst(raum.umriss!, melder);
    final rasterAnzahl = melder.isEmpty ? 0 : nichtErfasst(raum.umriss!, const []).length;
    String lx(double v) => '${v.round()} lx';
    return [
      const Divider(height: 28),
      Text('Licht', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      SpeicherFeld(
        key: ValueKey('ziel-${raum.id}-$ziel'),
        initialValue: '$ziel',
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Zielwert mittlere Beleuchtungsstärke', suffixText: 'lx'),
        onFieldSubmitted: (v) {
          final m = Map<String, dynamic>.from(store.einstellung<Map>('licht_ziel') ?? const {});
          final alt = Map<String, dynamic>.from(m);
          m[raum.id] = int.tryParse(v) ?? ziel;
          store.einstellungSetzen('licht_ziel', m);
          _rueckgaengig.add(() => store.einstellungSetzen('licht_ziel', alt));
          _s.geaendert();
        },
      ),
      const SizedBox(height: 8),
      Text('Em ${lx(e.mittel)} · Emin ${lx(e.minimum)} · U0 ${e.gleichmaessigkeit.toStringAsFixed(2).replaceAll('.', ',')}',
          style: TextStyle(fontWeight: FontWeight.w600, color: e.mittel < ziel ? const Color(0xFFB45309) : null)),
      Text('${(e.anteilUnter(ziel * 0.6) * 100).round()} % der Fläche unter 60 % des Zielwerts',
          style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Text(
          '${leuchten.length} Leuchten, ${streifen.length} LED-Streifen · ${lumen.round()} lm · ${watt.round()} W'
          '${flaeche > 0 ? ' · ${(watt / flaeche).toStringAsFixed(1).replaceAll('.', ',')} W/m²' : ''}',
          style: const TextStyle(fontSize: 12)),
      if (melder.isNotEmpty)
        Text(
            frei.isEmpty
                ? 'Präsenzmelder erfassen den ganzen Raum (sitzend).'
                : 'Nicht erfasst (sitzend): ca. ${(frei.length / math.max(1, rasterAnzahl) * 100).round()} % der Fläche – im Bild schraffiert.',
            style: TextStyle(fontSize: 12, color: frei.isEmpty ? null : const Color(0xFFB45309))),
      const SizedBox(height: 4),
      const Text(
          'Vereinfachte Abschätzung zum Vergleichen von Varianten (Arbeitsebene 0,75 m, ohne Reflexionen), keine lichttechnische Berechnung.',
          style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
    ];
  }

  /// Erfassungskreise (sitzend) der Melder im Raum: Mitte, Radius.
  List<(Punkt, double)> get _melderKreise => [
        for (final o in _objekte)
          if (_typen[o.typId]?.kuerzel == 'PM' || _typen[o.typId]?.kuerzel == 'BM') (o.punkte.first, erfassung(_hoeheUeberFfb(o)).praesenz / 2),
      ];

  // ------------------------------------------------------ Lichtszenen

  String? _szene; // gewählte Szene im Seitenfeld

  List<Map<String, dynamic>> _szenen() => [
        for (final m in (_s.store!.einstellung<List>('lichtszenen') ?? const [])) Map<String, dynamic>.from(m as Map),
      ];

  void _szenenSpeichern(List<Map<String, dynamic>> neu) {
    final store = _s.store!;
    final alt = store.einstellung<List>('lichtszenen');
    store.einstellungSetzen('lichtszenen', neu);
    _rueckgaengig.add(() => store.einstellungSetzen('lichtszenen', alt));
    _s.geaendert();
  }

  /// Lichtszenen des Raums (z. B. „Kochen“, „Abend“): Helligkeit je Leuchte bzw. LED-Streifen.
  List<Widget> _szenenAbschnitt(Raum raum) {
    final alle = _szenen();
    final hier = [for (final sz in alle) if (sz['raum'] == raum.id) sz];
    final lichter = [
      for (final o in [..._objekte, ..._leitungen])
        if (_typen[o.typId]?.kuerzel == 'LE' || _typen[o.typId]?.kuerzel == 'LB') o
    ];
    final aktiv = hier.where((sz) => sz['id'] == _szene).firstOrNull;
    return [
      const Divider(height: 28),
      Row(children: [
        Text('Lichtszenen', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        IconButton(
          tooltip: 'Szene anlegen',
          icon: const Icon(Sym.hinzufuegen, size: 18),
          onPressed: lichter.isEmpty
              ? null
              : () async {
                  final name = await texteingabe(context, titel: 'Lichtszene', feld: 'Name', vorschlag: hier.isEmpty ? 'Hell' : 'Abend');
                  if (name == null || name.trim().isEmpty) return;
                  final id = '${DateTime.now().microsecondsSinceEpoch}';
                  _szenenSpeichern([
                    ...alle,
                    {'id': id, 'name': name.trim(), 'raum': raum.id, 'werte': {for (final o in lichter) o.id: 100}},
                  ]);
                  setState(() => _szene = id);
                },
        ),
      ]),
      if (lichter.isEmpty) const Text('Erst Leuchten oder LED-Streifen setzen.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Wrap(spacing: 6, children: [
        for (final sz in hier)
          ChoiceChip(
            label: Text(sz['name'] as String),
            selected: sz['id'] == _szene,
            onSelected: (v) => setState(() => _szene = v ? sz['id'] as String : null),
          ),
      ]),
      if (aktiv != null) ...[
        for (final o in lichter)
          Row(children: [
            SizedBox(width: 90, child: Text(o.kennung, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Slider(
                value: ((aktiv['werte'] as Map?)?[o.id] as num? ?? 0).toDouble().clamp(0, 100),
                max: 100,
                divisions: 20,
                label: '${((aktiv['werte'] as Map?)?[o.id] as num? ?? 0).round()} %',
                onChanged: (v) => _szenenSpeichern([
                  for (final sz in alle)
                    if (sz['id'] == aktiv['id'])
                      {...sz, 'werte': {...Map<String, dynamic>.from(sz['werte'] as Map? ?? const {}), o.id: v.round()}}
                    else
                      sz,
                ]),
              ),
            ),
            SizedBox(width: 36, child: Text('${((aktiv['werte'] as Map?)?[o.id] as num? ?? 0).round()} %', style: const TextStyle(fontSize: 11))),
          ]),
        TextButton.icon(
          onPressed: () {
            _szenenSpeichern([for (final sz in alle) if (sz['id'] != aktiv['id']) sz]);
            setState(() => _szene = null);
          },
          icon: const Icon(Sym.loeschen, size: 18),
          label: const Text('Szene löschen'),
        ),
      ],
    ];
  }
  Widget _details(Objekt o) {
    final t = _typen[o.typId];
    final store = _s.store!;
    final zAbs = o.z != null && o.zBezug != null ? absolut(o.z!, o.zBezug!, _h) : _h.rohdecke;
    return ListView(children: [
      Text(t?.name ?? '', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Text(o.kennung, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text('Montagehöhe ${mmText(zAbs - _h.ffb)} mm über FFB'),
      if (t?.kuerzel == 'PM' || t?.kuerzel == 'BM')
        Text('Erfassung Ø ca. ${meterText(erfassung((zAbs - _h.ffb).toDouble()).praesenz)} sitzend, ${meterText(erfassung((zAbs - _h.ffb).toDouble()).frontal)} frontal, ${meterText(erfassung((zAbs - _h.ffb).toDouble()).quer)} quer gehend'),
      if (t?.kuerzel == 'LE') ..._leuchtenFelder(o),
      if (t?.kuerzel == 'LB') ..._ledFelder(o),
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

/// Grober Erfassungsdurchmesser eines Decken-Präsenzmelders für sitzende
/// Tätigkeit: etwa die 1,5-fache Montagehöhe über Arbeitsebene (0,8 m).
double erfassungsDurchmesser(int montagehoeheUeberFfb) => math.max(0, (montagehoeheUeberFfb - 800) * 1.5 + 800).toDouble();

class _DeckenPainter extends CustomPainter {
  _DeckenPainter(this.s);
  final _DeckePageState s;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final umriss = s._raum!.umriss!;
    final pfad = Path()..addPolygon([for (final p in umriss) s._s2(Offset(p.x, p.y))], true);
    canvas.drawPath(pfad, Paint()..color = const Color(0xFFF4F1EA));
    canvas.drawPath(pfad, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = BsFarben.wandBestand);
    // Leitungen an der Decke
    for (final o in s._leitungen) {
      final farbe = Color(s._gewerke[s._typen[o.typId]?.gewerkId]?.farbe ?? 0xFF888888);
      canvas.drawPath(
        Path()..addPolygon([for (final p in o.punkte) s._s2(Offset(p.x, p.y))], false),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = farbe,
      );
    }
    // Lichtverteilung als Farbfläche (Arbeitsebene)
    if (s._lichtAnzeigen) {
      final e = s._lichtBerechnen();
      final ziel = s._ziel.toDouble();
      final halb = e.raster / 2;
      canvas.save();
      canvas.clipPath(pfad);
      for (final (p, lux) in e.zellen) {
        final a = s._s2(Offset(p.x - halb, p.y - halb)), b = s._s2(Offset(p.x + halb, p.y + halb));
        canvas.drawRect(Rect.fromPoints(a, b), Paint()..color = Color(lichtFarbe(lux, ziel)));
      }
      canvas.restore();
      final legende = TextPainter(
        text: TextSpan(
          text: 'Lichtverteilung: blau = dunkel, gelb = Zielwert ${ziel.round()} lx, weiß = doppelt so hell · Em ${e.mittel.round()} lx',
          style: const TextStyle(fontSize: 11, color: BsFarben.textLeise),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      legende.paint(canvas, Offset(12, size.height - 22));
    }
    // Nicht erfasste Bereiche der Präsenzmelder (schraffiert)
    final melder = s._melderKreise;
    if (melder.isNotEmpty) {
      final frei = nichtErfasst(umriss, melder);
      final stift = Paint()
        ..color = const Color(0xFFB91C1C).withValues(alpha: 0.35)
        ..strokeWidth = 1;
      for (final p in frei) {
        final c = s._s2(Offset(p.x, p.y));
        final r = 125 * s._massstab;
        canvas.drawLine(c + Offset(-r, r), c + Offset(r, -r), stift);
      }
    }
    // LED-Streifen: leuchtender Saum
    for (final o in s._leitungen) {
      if (s._typen[o.typId]?.kuerzel != 'LB') continue;
      final weg = Path()..addPolygon([for (final p in o.punkte) s._s2(Offset(p.x, p.y))], false);
      canvas.drawPath(
          weg,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFFFD43B).withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      if (o.id == s._auswahl) {
        canvas.drawPath(
            weg,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = BsFarben.akzent);
      }
    }
    // LED-Streifen im Entstehen
    if (s._ledEntwurf.isNotEmpty) {
      final pts = [for (final p in s._ledEntwurf) s._s2(p), if (s._maus != null) s._s2(s._maus!)];
      canvas.drawPath(
          Path()..addPolygon(pts, false),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFFE67700));
    }
    // Objekte
    for (final o in s._objekte) {
      final t = s._typen[o.typId];
      final farbe = Color(s._gewerke[t?.gewerkId]?.farbe ?? 0xFF888888);
      var w = Offset(o.punkte.first.x, o.punkte.first.y);
      if (o.id == s._auswahl || (s._mehr.contains(s._auswahl) && s._mehr.contains(o.id))) w += s._versatz;
      final c = s._s2(w);
      if (t?.kuerzel == 'PM' || t?.kuerzel == 'BM') {
        final zAbs = o.z != null && o.zBezug != null ? absolut(o.z!, o.zBezug!, s._h) : s._h.rohdecke;
        final r = erfassungsDurchmesser(zAbs - s._h.ffb) / 2 * s._massstab;
        canvas.drawCircle(c, r, Paint()..color = farbe.withValues(alpha: 0.08));
        canvas.drawCircle(c, r, Paint()
          ..style = PaintingStyle.stroke
          ..color = farbe.withValues(alpha: 0.5));
      }
      final gewaehlt = o.id == s._auswahl || s._mehr.contains(o.id);
      canvas.drawCircle(c, gewaehlt ? 10 : 8, Paint()..color = Colors.white);
      canvas.drawCircle(c, gewaehlt ? 10 : 8, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = gewaehlt ? 3 : 2
        ..color = farbe);
      final tp = TextPainter(
        text: TextSpan(text: t?.kuerzel ?? '?', style: TextStyle(fontSize: 8, color: farbe, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      final kt = TextPainter(
        text: TextSpan(text: o.kennung, style: TextStyle(fontSize: 9, color: farbe, backgroundColor: Colors.white70)),
        textDirection: TextDirection.ltr,
      )..layout();
      kt.paint(canvas, c + const Offset(11, -6));
      if (gewaehlt) {
        // Abstände zu den Raumkanten
        final g = s._grenzen;
        final abst = [
          (w.dx - g.left, Offset(g.left, w.dy)),
          (g.right - w.dx, Offset(g.right, w.dy)),
          (w.dy - g.top, Offset(w.dx, g.top)),
          (g.bottom - w.dy, Offset(w.dx, g.bottom)),
        ];
        for (final (wert, ziel) in abst) {
          final z = s._s2(ziel);
          canvas.drawLine(c, z, Paint()
            ..color = BsFarben.akzent
            ..strokeWidth = 0.8);
          final lt = TextPainter(
            text: TextSpan(text: mmText(wert), style: const TextStyle(fontSize: 10, color: BsFarben.akzentDunkel, backgroundColor: Colors.white)),
            textDirection: TextDirection.ltr,
          )..layout();
          lt.paint(canvas, (c + z) / 2 - Offset(lt.width / 2, lt.height / 2));
        }
      }
    }
    final m = s._maus;
    if (m != null && s._setzen) {
      final c = s._s2(m);
      final p = Paint()
        ..color = BsFarben.akzentDunkel
        ..strokeWidth = 1;
      canvas.drawLine(c.translate(-8, 0), c.translate(8, 0), p);
      canvas.drawLine(c.translate(0, -8), c.translate(0, 8), p);
    }
    final hinweis = TextPainter(
      text: TextSpan(
        text: s._vonUnten ? 'Blick von unten – links und rechts vertauscht' : 'Blick von oben – wie im Grundriss',
        style: const TextStyle(fontSize: 11, color: BsFarben.textLeise),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hinweis.paint(canvas, const Offset(12, 10));
    final ra = s._rahmenA, rb = s._rahmenB;
    if (ra != null && rb != null) {
      final r = Rect.fromPoints(s._s2(ra), s._s2(rb));
      canvas.drawRect(r, Paint()..color = BsFarben.akzent.withValues(alpha: 0.08));
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..color = BsFarben.akzent);
    }
  }

  @override
  bool shouldRepaint(covariant _DeckenPainter old) => true;
}
