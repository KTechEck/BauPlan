import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/drei_d.dart';
import '../../core/drei_d_szene.dart';
import '../../core/height.dart';
import '../../core/oberflaechen.dart';
import '../../core/raumerkennung.dart';
import '../../core/wandmasse.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import 'texturen3d.dart';
import '../../core/gelaende.dart';
import '../../core/wandaufbau.dart';
import '../../core/sonne.dart';
import '../bauphysik/sonne_dialog.dart';
import 'dach_dialog.dart' show dachLesen, gebaeuderahmen;
import '../../core/dach.dart' show dachFlaecheHoehe, dachstuhl, Holzteil;

/// Ganzes Geschoss in 3D: Wände mit Fenstern und Türen, Böden und Wände mit
/// Texturen je Material, Geräte und Leitungen. Ziehen dreht, Mausrad oder
/// zwei Finger zoomen, rechte Maustaste/Umschalt verschiebt.
Future<void> geschoss3dZeigen(BuildContext context, AppState state) async {
  final store = state.store;
  final gid = state.geschossId;
  if (store == null || gid == null) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: Text('3D – ${store.geschoss(gid)?.name ?? 'Geschoss'}')),
      body: Geschoss3d(state: state, geschossId: gid),
    ),
  ));
}

/// Alles, was die Szene braucht, aus dem Projekt gelesen.
class _Daten {
  _Daten(this.waende, this.oeffnungen, this.raeume, this.geraete, this.leitungen, this.farben, this.hoehe, this.mitte, this.groesse, this.geraete3d);
  final List<Geraet3d> geraete3d;
  final List<Wand3d> waende;
  final List<Oeffnung3d> oeffnungen;
  final List<Raum3d> raeume;
  final List<Quader> geraete;
  final List<Leitung3d> leitungen;
  final Map<String, Color> farben;
  final double hoehe;
  final V3 mitte;
  final double groesse;
}

_Daten? _lesen(AppState state, String geschossId) {
  final store = state.store!;
  final g = store.geschoss(geschossId);
  final waende = store.waende(geschossId);
  if (g == null || waende.isEmpty) return null;
  final h = g.hoehen;
  final hoehe = (h.rohdecke - h.ffb).toDouble();
  final baustoffe = {for (final m in store.materialien()) m.id: m};
  final typen = {for (final t in store.wandtypen()) t.id: t};
  String? schichtMaterial(String? typId, bool erste) {
    final t = typen[typId];
    if (t == null || t.schichten.isEmpty) return null;
    final s = erste ? t.schichten.first : t.schichten.last;
    return oberflaecheAusText(baustoffe[s.materialId]?.name ?? '');
  }

  final global = store.einstellung<bool>('ecken_verbinden') ?? true;
  final achsen = [for (final w in waende) w.achse];
  final verb = [for (final w in waende) w.verbinden ?? global];
  final nachbarn = [
    for (var i = 0; i < waende.length; i++)
      if (verb[i] && !waende[i].istKante) achsen[i]
  ];
  var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
  final w3 = <Wand3d>[];
  for (var i = 0; i < waende.length; i++) {
    final w = waende[i];
    if (w.istKante && !w.gelaender) continue; // offene Kante: nur der Boden
    x0 = math.min(x0, math.min(w.x1, w.x2).toDouble());
    y0 = math.min(y0, math.min(w.y1, w.y2).toDouble());
    x1 = math.max(x1, math.max(w.x1, w.x2).toDouble());
    y1 = math.max(y1, math.max(w.y1, w.y2).toDouble());
    w3.add(Wand3d(
      id: w.id,
      a: achsen[i].a,
      b: achsen[i].b,
      dicke: w.dicke,
      umriss: wandUmriss(achsen[i], verb[i] ? nachbarn : [achsen[i]]),
      hoehe: w.istKante ? 1000 : (w.teilhoch ? (w.hoehe ?? w.art.standardHoehe).toDouble() : hoehe),
      zustandFarbe: switch (w.zustand) {
        WandZustand.bestand => const Color(0xFF5B6168).toARGB32(),
        WandZustand.neu => BsFarben.wandNeu.toARGB32(),
        WandZustand.abbruch => BsFarben.wandAbbruch.toARGB32(),
      },
      materialLinks: w.istKante ? 'grau' : schichtMaterial(w.wandtypId, true),
      materialRechts: w.istKante ? 'grau' : schichtMaterial(w.wandtypId, false),
    ));
  }
  final oeff = <Oeffnung3d>[
    for (final o in store.oeffnungen(geschossId))
      if (o.art != OeffnungsArt.nische)
        (
          wandId: o.wandId,
          von: o.abstand.toDouble(),
          bis: (o.abstand + o.breite).toDouble(),
          unten: o.art == OeffnungsArt.tuer ? 0.0 : o.bruestung.toDouble(),
          oben: (o.art == OeffnungsArt.tuer ? o.hoehe : o.bruestung + o.hoehe).toDouble(),
          fenster: o.art == OeffnungsArt.fenster,
        ),
  ];
  String texte(Raum r, Flaechenart a) => [
        for (final b in beschichtungen(r.eigenschaften, a)) ...[b.text, baustoffe[b.material]?.name ?? ''],
      ].join(' ');
  final raeume = <Raum3d>[];
  for (final r in store.raeume(geschossId)) {
    final u = r.umriss;
    if (u == null || u.length < 3) continue;
    final eig = (r.eigenschaften['ansicht3d'] as Map?) ?? const {};
    final aussen = r.art != RaumArt.raum || r.eigenschaften['aussen'] == true;
    raeume.add((
      id: r.id,
      name: r.name,
      umriss: u,
      boden: eig['boden'] as String? ?? oberflaecheAusText(texte(r, Flaechenart.boden)) ?? bodenAusRaumname(r.name, aussen: aussen),
      waende: eig['waende'] as String? ?? oberflaecheAusText(texte(r, Flaechenart.waende)) ?? wandAusRaumname(r.name),
      aussen: aussen,
    ));
  }
  // erkannte Flächen ohne Raum: Estrich
  for (final f in store.flaechenErkennen(geschossId)) {
    if (raeume.any((r) => punktInPolygon(f.innenpunkt, r.umriss))) continue;
    raeume.add((id: '', name: '', umriss: f.licht, boden: 'estrich', waende: 'putz', aussen: false));
  }

  // Geräte und Leitungen (Höhe aus dem Objekt bzw. seiner Verlegeebene)
  final otypen = {for (final t in store.objekttypen()) t.id: t};
  final gewerke = {for (final x in store.gewerke()) x.id: x};
  final ebenen = <String, double>{};
  for (final e in (store.einstellung<List>('verlegeebenen') ?? const [])) {
    final m = Map<String, dynamic>.from(e as Map);
    final von = (m['von_mm'] as num?)?.toDouble(), bis = (m['bis_mm'] as num?)?.toDouble();
    if (von == null && bis == null) continue;
    final mitte = ((von ?? bis!) + (bis ?? von!)) / 2;
    ebenen['${m['name']}'] = switch (m['bezug']) {
      'unter FFB' => -mitte,
      'unter Decke' => hoehe - mitte,
      _ => mitte - (h.ffb - h.rfb),
    };
  }
  double zLage(String? lage) => switch (lage) {
        'im Estrich' => -40,
        'unter Estrich' => -(h.ffb - h.rfb) + 20,
        'auf RFB' => -(h.ffb - h.rfb) + 10,
        'an Decke' || 'in Decke' => hoehe - 30,
        _ => ebenen[lage] ?? 0,
      };
  double zUeberFfb(Objekt o, double vorgabe) => o.z == null || o.zBezug == null ? vorgabe : (absolut(o.z!, o.zBezug!, h) - h.ffb).toDouble();
  final farben = <String, Color>{};
  final geraete = <Quader>[];
  final geraete3d = <Geraet3d>[];
  final leitungen = <Leitung3d>[];
  for (final o in store.objekte(geschossId)) {
    final t = otypen[o.typId];
    if (t == null || o.punkte.isEmpty) continue;
    farben[o.id] = Color(gewerke[t.gewerkId]?.farbe ?? 0xFF868E96);
    switch (t.geometrie) {
      case Geometrieart.linie:
        if (o.punkte.length < 2) continue;
        final zs = o.zPunkte;
        final z0 = zUeberFfb(o, zLage(o.lage));
        leitungen.add(Leitung3d(
          id: o.id,
          name: o.kennung,
          durchmesser: (o.eigenschaften['breite_mm'] as num?)?.toDouble() ?? 20,
          punkte: [for (var i = 0; i < o.punkte.length; i++) V3(o.punkte[i].x, o.punkte[i].y, zs != null && i < zs.length ? zs[i] - h.ffb.toDouble() : z0)],
        ));
      case Geometrieart.punkt:
        final m = o.eigenschaften['masse'];
        final masse = m is List && m.length >= 3 ? [for (final x in m) (x as num).toDouble()] : [80.0, 60.0, 80.0];
        geraete3d.add((
          id: o.id,
          kuerzel: t.kuerzel,
          p: o.punkte.first,
          z: o.z == null || o.zBezug == null ? null : zUeberFfb(o, 0),
          masse: m is List && m.length >= 3 ? masse : null,
          farbe: farben[o.id]!.toARGB32(),
          drehung: (o.eigenschaften['drehung'] as num?)?.toInt() ?? 0,
        ));
        geraete.add(Quader(
          id: o.id,
          name: o.kennung,
          x: o.punkte.first.x,
          y: o.punkte.first.y,
          z: zUeberFfb(o, m is List ? 0 : 300),
          b: masse[0],
          t: masse[1],
          h: masse[2],
          drehung: (o.eigenschaften['drehung'] as num?)?.toInt() ?? 0,
        ));
      case Geometrieart.flaeche:
        break;
    }
  }
  return _Daten(w3, oeff, raeume, geraete, leitungen, farben, hoehe, V3((x0 + x1) / 2, -(y0 + y1) / 2, hoehe / 3),
      math.max(x1 - x0, y1 - y0), geraete3d);
}

class Geschoss3d extends StatefulWidget {
  const Geschoss3d({super.key, required this.state, required this.geschossId});
  final AppState state;
  final String geschossId;

  @override
  State<Geschoss3d> createState() => _Geschoss3dState();
}

/// Vorbereitete Fläche: Textur, Texturkoordinaten (Pixel) und Schattierung.
class _Teil {
  _Teil(this.f, this.textur, this.tex, this.farbe, this.schluessel);
  final Flaeche3d f;
  final Textur3d? textur;
  final List<Offset> tex;
  final Color farbe;
  final String schluessel; // gleiche Schlüssel werden zusammen gezeichnet
}

class _Geschoss3dState extends State<Geschoss3d> {
  Orbit? _k;
  _Daten? _d;
  List<_Teil> _teile = const [];
  Object? _stand;

  /// Sonne: an/aus, Tag und Minute des Tages (Ortszeit).
  bool _sonne = false;
  DateTime _sonneTag = DateTime(DateTime.now().year, 6, 21);
  int _sonneMinute = 15 * 60;

  /// Richtung zur Sonne (rechtshändig) oder null (aus / unter dem Horizont).
  V3? get _sonnenVektor {
    if (!_sonne) return null;
    final store = widget.state.store!;
    final ort = Map<String, dynamic>.from(store.einstellung<Map>('standort') ?? const {});
    final st = sonnenstand((ort['lat'] as num?)?.toDouble() ?? 51.0, (ort['lon'] as num?)?.toDouble() ?? 10.0, _sonneTag.add(Duration(minutes: _sonneMinute)));
    if (st.hoehe <= 0.5) return null;
    final r = sonnenRichtungPlan(st.azimut, st.hoehe, (store.einstellung<num>('norden_grad') ?? 0).toDouble());
    final h = st.hoehe * math.pi / 180;
    return V3(r.x * math.cos(h), -r.y * math.cos(h), math.sin(h));
  }
  int _schnitt = 0; // 0 voll, 1 halbhoch, 2 Grundriss
  bool _texturen = true, _technik = true, _namen = true, _dach = true, _dachstuhl = true, _gelaende = true;
  final _zeiger = <int, Offset>{};
  Offset? _letzte;
  bool _verschieben = false;
  double _pzSkala = 1;
  Size _groesse = const Size(800, 600);

  double get _schnittHoehe => switch (_schnitt) { 1 => 1300.0, 2 => 250.0, _ => double.infinity };

  void _aufbauen() {
    final stand = (widget.state.revision, _schnitt, _texturen, _sonne, _sonneTag, _sonneMinute ~/ 30);
    if (stand == _stand) return;
    _stand = stand;
    _d = _lesen(widget.state, widget.geschossId);
    final d = _d;
    if (d == null) return;
    _k ??= Orbit(ziel: d.mitte, abstand: math.max(5000, d.groesse * 1.5));
    final dachE = dachLesen(widget.state.store!, widget.geschossId);
    final dachG = dachE.aktiv ? gebaeuderahmen(widget.state.store!.waende(widget.geschossId)) : null;
    final szene = geschossSzene(
      waende: d.waende,
      oeffnungen: d.oeffnungen,
      raeume: d.raeume,
      schnitt: _schnittHoehe,
      // Dachgeschoss: Wände enden an der Dachschräge (Kniestock, Giebel)
      oben: dachG == null ? null : (p) => dachFlaecheHoehe(dachE, dachG, p),
    );
    // Geräte als Quader dazu (rechtshändig: y gespiegelt)
    final flaechen = [...szene];
    // Aufbau je Wandseite (Putz, WDVS …) als dünne Körper vor dem Kern
    {
      final store = widget.state.store!;
      final mats = {for (final m in store.materialien()) m.id: m};
      final h = math.min(d.hoehe, _schnittHoehe);
      for (final b in aufbauBaender(store.waende(widget.geschossId), oeffnungen: store.oeffnungen(widget.geschossId), raumhoehe: d.hoehe)) {
        final poly = b.polygon;
        final name = mats[b.material]?.name ?? '';
        final key = oberflaecheAusText(name) ?? 'aussenputz';
        for (final (z0, z1raw) in b.hoehen ?? [(0.0, d.hoehe)]) {
          final z1 = math.min(z1raw, h);
          if (z1 - z0 < 1) continue;
          V3 w3(Punkt p, double z) => V3(p.x, -p.y, z);
          flaechen.add(Flaeche3d([for (final p in poly.reversed) w3(p, z1)], [for (final p in poly.reversed) (p.x, -p.y)], 'schnitt',
              normale: const V3(0, 0, 1), art: 'schnitt', farbe: mats[b.material]?.farbe ?? 0xFFE9E4DA, id: b.wandId));
          if (b.aussen) {
            final a = poly[3], e = poly[2];
            final mitte = Punkt((poly[0].x + poly[1].x) / 2, (poly[0].y + poly[1].y) / 2);
            final dx = e.x - a.x, dy = e.y - a.y;
            var nx = dy, ny = -dx;
            final l = math.sqrt(nx * nx + ny * ny);
            if (l < 1) continue;
            nx /= l;
            ny /= l;
            if ((a.x - mitte.x) * nx + (a.y - mitte.y) * ny < 0) {
              nx = -nx;
              ny = -ny;
            }
            // in Kacheln (sauberes Sortieren, Textur)
            final n = math.max(1, (l / 900).ceil()), m = math.max(1, ((z1 - z0) / 900).ceil());
            for (var i = 0; i < n; i++) {
              final pa = Punkt(a.x + dx * i / n, a.y + dy * i / n), pe = Punkt(a.x + dx * (i + 1) / n, a.y + dy * (i + 1) / n);
              for (var k = 0; k < m; k++) {
                final za = z0 + (z1 - z0) * k / m, zb = z0 + (z1 - z0) * (k + 1) / m;
                final ta = l * i / n, te = l * (i + 1) / n;
                flaechen.add(Flaeche3d([w3(pa, za), w3(pe, za), w3(pe, zb), w3(pa, zb)], [(ta, za), (te, za), (te, zb), (ta, zb)], key,
                    normale: V3(nx, -ny, 0), id: b.wandId));
              }
            }
          }
        }
      }
    }
    // Gelände im Erdgeschoss (Höhen zu ±0 = FFB EG)
    if (_gelaende) {
      final store = widget.state.store!;
      final punkte = gelaendeLesen(store.einstellung<Object>('gelaende'));
      final gs = [for (final geb in store.gebaeude()) ...store.geschosse(geb.id)];
      final eg = gs.where((g) => g.kuerzel.toUpperCase().contains('EG')).firstOrNull ?? gs.firstOrNull;
      if (punkte.isNotEmpty && eg?.id == widget.geschossId && d.waende.isNotEmpty) {
        var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
        for (final w in d.waende) {
          for (final q in [w.a, w.b]) {
            x0 = math.min(x0, q.x);
            y0 = math.min(y0, q.y);
            x1 = math.max(x1, q.x);
            y1 = math.max(y1, q.y);
          }
        }
        flaechen.addAll(gelaendeFlaechen(
          x0: x0 - 8000,
          y0: y0 - 8000,
          x1: x1 + 8000,
          y1: y1 + 8000,
          hoehe: (x, y) => gelaendeHoehe(punkte, x, y)!,
          haus: (x0 - 100, y0 - 100, x1 + 100, y1 + 100),
        ));
      }
    }
    // Dach mit Dachstuhl (Dachgeschoss mit Dachform)
    if ((_dach || _dachstuhl) && _schnitt == 0) {
      final store = widget.state.store!;
      final dach = dachLesen(store, widget.geschossId);
      final g = dach.aktiv ? gebaeuderahmen(store.waende(widget.geschossId)) : null;
      if (g != null) {
        final u = dach.ueberstand.toDouble();
        if (_dach) {
          flaechen.addAll(dachFlaechen(
            x0: g.x0 - u,
            y0: g.y0 - u,
            x1: g.x1 + u,
            y1: g.y1 + u,
            hoehe: (x, y) => dachFlaecheHoehe(dach, g, Punkt(x, y)) + dach.sparrenHoehe + 60,
          ));
        }
        for (final (i, t) in (_dachstuhl ? dachstuhl(dach, g) : const <Holzteil>[]).indexed) {
          flaechen.addAll(balkenFlaechen('holz-$i', t.x1, t.y1, t.z1, t.x2, t.y2, t.z2, t.b, t.h, farbe: t.name.contains('pfette') ? 0xFFA9744A : 0xFFC9935F));
        }
      }
    }
    if (_technik) {
      final g3 = _schnitt == 0 ? d.geraete3d : [for (final g in d.geraete3d) if (g.z != null || !const {'LE', 'RW', 'WR', 'CM', 'PM', 'BM', 'AP', 'LV'}.contains(g.kuerzel)) g];
      flaechen.addAll(geraeteFlaechen(g3, d.waende, d.hoehe));
    }
    const licht = V3(0.35, -0.45, 0.82);
    final ln = _sonnenVektor ?? normiert(licht);
    _teile = [
      for (final f in flaechen)
        () {
          final o = oberflaeche3d(f.material);
          final t = _texturen && f.farbe == null && f.art != 'glas' ? textur3d(o) : null;
          final hell = f.art == 'boden' ? 1.0 : (0.66 + 0.34 * math.max(0.0, f.n.skalar(ln)));
          final basis = Color(f.farbe ?? o.farbe);
          final farbe = Color.from(alpha: f.deckkraft, red: basis.r * hell, green: basis.g * hell, blue: basis.b * hell);
          final tex = t == null ? const <Offset>[] : [for (final (u, v) in f.uv) Offset(u * t.bild.width / t.mmB, -v * t.bild.height / t.mmH)];
          return _Teil(f, t, tex, farbe, t == null ? 'flach' : (o.art == 'fliesen' ? 'fliesen_${o.kachelB}x${o.kachelH}' : o.art));
        }(),
    ];
  }

  void _zoom(double f) => setState(() => _k = _k!.mit(abstand: _k!.abstand * f));

  void _drehen(Offset d) => setState(() => _k = _k!.mit(azimut: _k!.azimut - d.dx * 0.008, neigung: _k!.neigung + d.dy * 0.006));

  void _schieben(Offset d) {
    final k = _k!;
    final (r, _, f) = k.basis;
    final vor = normiert(V3(f.x, f.y, 0));
    final s = math.max(k.abstand, 2500) / (math.min(_groesse.width, _groesse.height) * 0.95);
    setState(() => _k = k.mit(ziel: k.ziel + r * (-d.dx * s) + vor * (d.dy * s)));
  }

  void _ansicht(String a) {
    final d = _d;
    if (d == null) return;
    setState(() {
      switch (a) {
        case 'oben':
          _k = Orbit(azimut: -math.pi / 2, neigung: 1.5607, abstand: math.max(5000, d.groesse * 1.6), ziel: V3(d.mitte.x, d.mitte.y, 0));
        case 'iso':
          _k = Orbit(ziel: d.mitte, abstand: math.max(5000, d.groesse * 1.5));
        case 'vorne':
          _k = Orbit(azimut: -math.pi / 2, neigung: 0.25, abstand: math.max(5000, d.groesse * 1.5), ziel: d.mitte);
      }
    });
  }

  void _begehen(Raum3d r) {
    final p = punktImInneren(r.umriss);
    setState(() {
      _schnitt = 0;
      _k = Orbit(azimut: _k?.azimut ?? -2.2, neigung: 0.02, abstand: 1, ziel: V3(p.x, -p.y, 1600));
    });
  }

  @override
  Widget build(BuildContext context) {
    _aufbauen();
    final d = _d;
    if (d == null) return const Center(child: Text('Noch keine Wände in diesem Geschoss.'));
    final koll = kollisionen3d(d.geraete, d.leitungen);
    return Stack(children: [
      Positioned.fill(
        child: LayoutBuilder(builder: (context, c) {
          _groesse = c.biggest;
          return Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                if (HardwareKeyboard.instance.isShiftPressed) {
                  _schieben(Offset(-e.scrollDelta.dx, -e.scrollDelta.dy) * 0.5);
                } else {
                  _zoom(e.scrollDelta.dy > 0 ? 1.12 : 1 / 1.12);
                }
              }
            },
            onPointerPanZoomStart: (_) => _pzSkala = 1,
            onPointerPanZoomUpdate: (e) {
              if (e.scale > 0 && (e.scale - _pzSkala).abs() > 0.001) {
                _zoom(_pzSkala / e.scale);
                _pzSkala = e.scale;
              }
              if (e.panDelta != Offset.zero) _drehen(e.panDelta);
            },
            onPointerDown: (e) {
              _zeiger[e.pointer] = e.localPosition;
              _letzte = e.localPosition;
              _verschieben = e.kind == PointerDeviceKind.mouse &&
                  (e.buttons == kSecondaryMouseButton || e.buttons == kMiddleMouseButton || HardwareKeyboard.instance.isShiftPressed);
            },
            onPointerMove: (e) {
              final alt = _zeiger[e.pointer];
              if (_zeiger.length >= 2 && alt != null) {
                // zwei Finger: Abstand = Zoom, Mitte = Verschieben
                final ids = _zeiger.keys.take(2).toList();
                final andere = _zeiger[ids.first == e.pointer ? ids[1] : ids.first]!;
                final d0 = (alt - andere).distance, d1 = (e.localPosition - andere).distance;
                if (d0 > 5 && d1 > 5) _zoom(d0 / d1);
                _schieben((e.localPosition - alt) / 2);
                _zeiger[e.pointer] = e.localPosition;
                return;
              }
              _zeiger[e.pointer] = e.localPosition;
              final l = _letzte;
              if (l == null) return;
              final delta = e.localPosition - l;
              _letzte = e.localPosition;
              _verschieben ? _schieben(delta) : _drehen(delta);
            },
            onPointerUp: (e) {
              _zeiger.remove(e.pointer);
              _letzte = _zeiger.values.firstOrNull;
            },
            onPointerCancel: (e) {
              _zeiger.remove(e.pointer);
              _letzte = null;
            },
            child: CustomPaint(
              painter: _GeschossPainter(_teile, _k!, d, technik: _technik, namen: _namen, kollision: koll.ids, sonne: _sonnenVektor),
              child: const SizedBox.expand(),
            ),
          );
        }),
      ),
      Positioned(right: 12, top: 12, child: _bedienung(d)),
      Positioned(
        left: 12,
        bottom: 12,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (_technik)
              Text(koll.hinweise.isEmpty ? 'Keine Kollisionen ✓' : '${koll.hinweise.length} Kollisionen',
                  style: TextStyle(fontWeight: FontWeight.w600, color: koll.hinweise.isEmpty ? const Color(0xFF2F9E44) : const Color(0xFFB91C1C))),
            if (_technik)
              for (final h in koll.hinweise.take(4)) Text('• $h', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            const Text('Ziehen dreht · Mausrad/zwei Finger zoomen · rechte Maustaste oder Umschalt verschiebt',
                style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
          ]),
        ),
      ),
    ]);
  }

  Widget _bedienung(_Daten d) {
    final echte = d.raeume.where((r) => r.id.isNotEmpty).toList();
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Container(
      width: 270,
      padding: const EdgeInsets.all(8),
      constraints: BoxConstraints(maxHeight: math.max(200, _groesse.height - 40)),
      child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 2, children: [
          IconButton(tooltip: 'Hineinzoomen', icon: const Icon(Icons.zoom_in), onPressed: () => _zoom(1 / 1.3)),
          IconButton(tooltip: 'Herauszoomen', icon: const Icon(Icons.zoom_out), onPressed: () => _zoom(1.3)),
          IconButton(tooltip: 'Von oben', icon: const Icon(Icons.crop_square), onPressed: () => _ansicht('oben')),
          IconButton(tooltip: 'Von vorne (Süden)', icon: const Icon(Icons.panorama_horizontal), onPressed: () => _ansicht('vorne')),
          IconButton(tooltip: 'Schräg von oben (Start)', icon: const Icon(Icons.view_in_ar), onPressed: () => _ansicht('iso')),
        ]),
        const Text('Wände', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: 0, label: Text('voll')),
            ButtonSegment(value: 1, label: Text('halb')),
            ButtonSegment(value: 2, label: Text('Grundriss')),
          ],
          selected: {_schnitt},
          onSelectionChanged: (s) => setState(() => _schnitt = s.first),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: [
          FilterChip(label: const Text('Texturen'), selected: _texturen, onSelected: (v) => setState(() => _texturen = v)),
          FilterChip(
              label: const Text('Technik'),
              selected: _technik,
              onSelected: (v) => setState(() {
                    _technik = v;
                    _stand = null;
                  })),
          FilterChip(label: const Text('Namen'), selected: _namen, onSelected: (v) => setState(() => _namen = v)),
          FilterChip(
              avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
              label: const Text('Sonne'),
              selected: _sonne,
              onSelected: (v) => setState(() => _sonne = v)),
          FilterChip(
              label: const Text('Gelände'),
              selected: _gelaende,
              onSelected: (v) => setState(() {
                    _gelaende = v;
                    _stand = null;
                  })),
          FilterChip(
              label: const Text('Dachhaut'),
              selected: _dach,
              onSelected: (v) => setState(() {
                    _dach = v;
                    _stand = null;
                  })),
          FilterChip(
              label: const Text('Dachstuhl'),
              selected: _dachstuhl,
              onSelected: (v) => setState(() {
                    _dachstuhl = v;
                    _stand = null;
                  })),
        ]),
        if (_sonne) ...[
          const SizedBox(height: 6),
          DropdownButton<int>(
            isDense: true,
            isExpanded: true,
            value: _sonneTag.month == 3 && _sonneTag.day == 21 ? 3 : (_sonneTag.month == 6 && _sonneTag.day == 21 ? 6 : (_sonneTag.month == 12 && _sonneTag.day == 21 ? 12 : 0)),
            items: const [
              DropdownMenuItem(value: 3, child: Text('21. März / Sept. (Tagundnachtgleiche)')),
              DropdownMenuItem(value: 6, child: Text('21. Juni (höchster Stand)')),
              DropdownMenuItem(value: 12, child: Text('21. Dezember (tiefster Stand)')),
              DropdownMenuItem(value: 0, child: Text('heute')),
            ],
            onChanged: (v) => setState(() {
              final j = DateTime.now().year;
              _sonneTag = v == 0 ? DateTime(j, DateTime.now().month, DateTime.now().day) : DateTime(j, v!, 21);
            }),
          ),
          Row(children: [
            Text('${(_sonneMinute ~/ 60).toString().padLeft(2, '0')}:${(_sonneMinute % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(min: 300, max: 1320, divisions: 68, value: _sonneMinute.toDouble().clamp(300, 1320), onChanged: (v) => setState(() => _sonneMinute = v.round())),
            ),
          ]),
          if (_sonnenVektor == null) const Text('Sonne unter dem Horizont', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
          TextButton(onPressed: () => sonneDialog(context, widget.state), child: const Text('Standort, Fenster-Sonnenstunden, PV …')),
        ],
        const SizedBox(height: 6),
        if (echte.isNotEmpty)
          PopupMenuButton<Raum3d>(
            tooltip: 'Im Raum stehen und umsehen (Augenhöhe 1,60 m)',
            onSelected: _begehen,
            itemBuilder: (_) => [for (final r in echte) PopupMenuItem(value: r, child: Text(r.name))],
            child: const ListTile(dense: true, leading: Icon(Icons.directions_walk), title: Text('Raum begehen …')),
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.texture),
          title: const Text('Oberflächen je Raum …'),
          onTap: () => _oberflaechenDialog(context, echte),
        ),
      ]),)
    ),
    );
  }

  Future<void> _oberflaechenDialog(BuildContext context, List<Raum3d> raeume) async {
    final store = widget.state.store!;
    final boden = [for (final o in oberflaechen3d) if (!['farbe', 'putz', 'ziegel', 'klinker', 'ks', 'porenbeton', 'gipskarton', 'holz', 'daemmung'].contains(o.art) || o.key == 'mosaik') o];
    final wand = [for (final o in oberflaechen3d) if (!['parkett', 'dielen', 'teppich', 'vinyl', 'estrich', 'pflaster'].contains(o.art)) o];
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) {
        final alle = {for (final r in store.raeume(widget.geschossId)) r.id: r};
        Widget wahl(Raum raum, String feld, List<Oberflaeche3d> liste, String aktuell) {
          final eig = (raum.eigenschaften['ansicht3d'] as Map?) ?? const {};
          final gesetzt = eig[feld] as String?;
          return DropdownButton<String>(
            isExpanded: true,
            value: gesetzt ?? '',
            items: [
              DropdownMenuItem(value: '', child: Text('automatisch (${oberflaeche3d(aktuell).label})', overflow: TextOverflow.ellipsis)),
              for (final o in liste) DropdownMenuItem(value: o.key, child: Text(o.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              final neu = Map<String, dynamic>.from(raum.eigenschaften);
              final a = Map<String, dynamic>.from(eig);
              if (v == null || v.isEmpty) {
                a.remove(feld);
              } else {
                a[feld] = v;
              }
              if (a.isEmpty) {
                neu.remove('ansicht3d');
              } else {
                neu['ansicht3d'] = a;
              }
              store.raumEigenschaftenSetzen(raum.id, neu);
              widget.state.geaendert();
              setD(() {});
              setState(() {});
            },
          );
        }

        return AlertDialog(
          title: const Text('Oberflächen in 3D'),
          content: SizedBox(
            width: 620,
            child: ListView(shrinkWrap: true, children: [
              const Text('Ohne Auswahl nimmt BauSpur die Beschichtungen des Raums, sonst den Raumnamen (Bad = Fliesen …). '
                  'Außenseiten kommen aus der äußersten Schicht des Wandtyps.', style: TextStyle(color: BsFarben.textLeise)),
              const SizedBox(height: 10),
              for (final r in raeume)
                if (alle[r.id] case final raum?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 130, child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Expanded(child: wahl(raum, 'boden', boden, r.boden)),
                      const SizedBox(width: 8),
                      Expanded(child: wahl(raum, 'waende', wand, r.waende)),
                    ]),
                  ),
            ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fertig'))],
        );
      }),
    );
  }
}

class _GeschossPainter extends CustomPainter {
  _GeschossPainter(this.teile, this.k, this.d, {required this.technik, required this.namen, required this.kollision, this.sonne});
  final List<_Teil> teile;

  /// Richtung zur Sonne (rechtshändig) – zeichnet Schatten der Wände auf den Boden.
  final V3? sonne;
  final Orbit k;
  final _Daten d;
  final bool technik, namen;
  final Set<String> kollision;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE9EEF2), Color(0xFFF7F7F4)])
              .createShader(rect));
    final auge = k.auge;
    final (r, o, f) = k.basis;
    final fpx = math.min(size.width, size.height) * 0.95;
    final c = Offset(size.width / 2, size.height / 2);
    const nah = 40.0;
    (Offset, double) p(V3 v) {
      final q = v - auge;
      final z = q.skalar(f);
      final zz = math.max(z, 1.0);
      return (c + Offset(q.skalar(r) * fpx / zz, -q.skalar(o) * fpx / zz), z);
    }

    // Böden zuerst (alle in einer Ebene), dann alles andere von hinten nach vorne
    final boeden = <String, (List<Offset>, List<Offset>, List<Color>, Textur3d?)>{};
    final reihe = <(double, _Teil, List<Offset>)>[];
    for (final t in teile) {
      final fl = t.f;
      if (!fl.beidseitig && fl.n.skalar(auge - fl.mitte) <= 0) continue;
      final pr = [for (final e in fl.ecken) p(e)];
      if (pr.any((x) => x.$2 < nah)) continue;
      final pos = [for (final x in pr) x.$1];
      if (fl.art == 'boden') {
        final b = boeden.putIfAbsent(t.schluessel + (t.textur == null ? '${t.farbe.toARGB32()}' : ''), () => (<Offset>[], <Offset>[], <Color>[], t.textur));
        _dreiecke(pos, t, b.$1, b.$2, b.$3);
        continue;
      }
      // Geräte sitzen auf der Wand: etwas nach vorne ziehen, damit große Wandkacheln sie nicht überdecken
      reihe.add((pr.fold(0.0, (s, x) => s + x.$2) / pr.length - (fl.art == 'geraet' ? 150 : 0), t, pos));
    }
    for (final b in boeden.values) {
      _zeichnen(canvas, b.$1, b.$2, b.$3, b.$4);
    }
    // Schatten der Wände auf dem Boden (Sonne an)
    final sv = sonne;
    if (sv != null && sv.z > 0.02) {
      canvas.saveLayer(rect, Paint()..color = const Color(0x52000000));
      final schwarz = Paint()..color = Colors.black;
      for (final w in d.waende) {
        if (w.umriss.length != 4) continue;
        final versatz = V3(-sv.x / sv.z * w.hoehe, -sv.y / sv.z * w.hoehe, 0);
        final unten = [for (final q in w.umriss) V3(q.x, -q.y, 0)];
        final oben = [for (final q in unten) q + versatz];
        final pu = [for (final q in unten) p(q)], po = [for (final q in oben) p(q)];
        if ([...pu, ...po].any((x) => x.$2 < nah)) continue;
        final pfad = Path()..addPolygon([for (final x in po) x.$1], true);
        for (var i = 0; i < 4; i++) {
          final j = (i + 1) % 4;
          pfad.addPolygon([pu[i].$1, pu[j].$1, po[j].$1, po[i].$1], true);
        }
        canvas.drawPath(pfad, schwarz);
      }
      canvas.restore();
    }
    // Leitungen einsortieren
    final linien = <(double, Offset, Offset, Color, double)>[];
    if (technik) {
      for (final l in d.leitungen) {
        final farbe = kollision.contains(l.id) ? const Color(0xFFE03131) : (d.farben[l.id] ?? const Color(0xFF1C7ED6));
        for (var i = 0; i + 1 < l.punkte.length; i++) {
          final (a, ta) = p(V3(l.punkte[i].x, -l.punkte[i].y, l.punkte[i].z));
          final (b, tb) = p(V3(l.punkte[i + 1].x, -l.punkte[i + 1].y, l.punkte[i + 1].z));
          if (ta < nah || tb < nah) continue;
          final tiefe = (ta + tb) / 2;
          linien.add((tiefe, a, b, farbe, math.max(1.5, l.durchmesser * fpx / tiefe)));
        }
      }
    }
    final alles = <(double, Object)>[
      for (final x in reihe) (x.$1, x),
      for (final l in linien) (l.$1 - 1, l),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    var pos = <Offset>[], tex = <Offset>[], col = <Color>[];
    String? schluessel;
    Textur3d? textur;
    void leeren() {
      if (pos.isNotEmpty) _zeichnen(canvas, pos, tex, col, textur);
      pos = [];
      tex = [];
      col = [];
      schluessel = null;
    }

    for (final (_, e) in alles) {
      if (e is (double, _Teil, List<Offset>)) {
        final (_, t, pp) = e;
        if (t.f.art == 'schnitt') {
          leeren();
          final pfad = Path()..addPolygon(pp, true);
          canvas.drawPath(pfad, Paint()..color = t.farbe);
          canvas.drawPath(pfad, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6
            ..color = const Color(0x55000000));
          continue;
        }
        final s = t.schluessel;
        if (s != schluessel) {
          leeren();
          schluessel = s;
          textur = t.textur;
        }
        _dreiecke(pp, t, pos, tex, col);
      } else if (e is (double, Offset, Offset, Color, double)) {
        leeren();
        canvas.drawLine(e.$2, e.$3, Paint()
          ..color = e.$4
          ..strokeWidth = e.$5
          ..strokeCap = StrokeCap.round);
      }
    }
    leeren();

    if (namen) {
      for (final rm in d.raeume) {
        if (rm.id.isEmpty) continue;
        final ip = punktImInneren(rm.umriss);
        final (q, t) = p(V3(ip.x, -ip.y, 30));
        if (t < nah * 5 || !rect.contains(q)) continue;
        final tp = TextPainter(
          text: TextSpan(text: rm.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2A30))),
          textDirection: TextDirection.ltr,
        )..layout();
        final box = Rect.fromCenter(center: q, width: tp.width + 10, height: tp.height + 4);
        canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = const Color(0xD9FFFFFF));
        tp.paint(canvas, box.topLeft + const Offset(5, 2));
      }
    }
  }

  void _dreiecke(List<Offset> pp, _Teil t, List<Offset> pos, List<Offset> tex, List<Color> col) {
    final idx = pp.length == 4 ? const [0, 1, 2, 0, 2, 3] : const [0, 1, 2];
    for (final i in idx) {
      pos.add(pp[i]);
      if (t.textur != null) tex.add(t.tex[i]);
      col.add(t.farbe);
    }
  }

  void _zeichnen(Canvas canvas, List<Offset> pos, List<Offset> tex, List<Color> col, Textur3d? t) {
    if (pos.isEmpty) return;
    if (t == null || tex.length != pos.length) {
      canvas.drawVertices(ui.Vertices(VertexMode.triangles, pos, colors: col), BlendMode.dst, Paint());
      return;
    }
    final paint = Paint()
      ..shader = ImageShader(t.bild, TileMode.repeated, TileMode.repeated, Matrix4.identity().storage)
      ..filterQuality = FilterQuality.low;
    canvas.drawVertices(ui.Vertices(VertexMode.triangles, pos, textureCoordinates: tex, colors: col), BlendMode.modulate, paint);
  }

  @override
  bool shouldRepaint(covariant _GeschossPainter old) => true;
}
