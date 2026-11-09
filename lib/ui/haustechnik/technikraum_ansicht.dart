import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/height.dart';
import '../../core/raumerkennung.dart';
import '../../core/technik.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../core/bauelemente.dart';
import '../bauteile/bauelement_wahl.dart';
import '../../core/drei_d.dart';
import '../widgets.dart';
import 'technik_3d.dart';

/// Technik- und Heizraumplaner: Geräte mit echten Maßen und Wartungsfreiräumen
/// im Grundriss eines Raums, Kollisionen und Hinweise.
class TechnikraumAnsicht extends StatefulWidget {
  const TechnikraumAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<TechnikraumAnsicht> createState() => _TechnikraumAnsichtState();
}

class _TechnikraumAnsichtState extends State<TechnikraumAnsicht> {
  bool _drei = false; // 3D-Ansicht
  final _eigFenster = EigenschaftenFenster();
  final _doppel = Doppelklick();
  String? _raumId;
  String? _auswahl;
  TechnikVorlage? _setzen;
  Offset? _ziehStart;
  Offset _versatz = Offset.zero;
  final List<VoidCallback> _rueckgaengig = [];
  // Abbildung
  Rect _grenzen = Rect.zero;
  Size _flaeche = Size.zero;

  AppState get _s => widget.state;

  double get _massstab => _grenzen.isEmpty
      ? 0.1
      : math.max(0.01, math.min((_flaeche.width - 80) / _grenzen.width, (_flaeche.height - 80) / _grenzen.height));
  Offset _zuBild(Offset w) => Offset((_flaeche.width - _grenzen.width * _massstab) / 2 + (w.dx - _grenzen.left) * _massstab,
      (_flaeche.height - _grenzen.height * _massstab) / 2 + (w.dy - _grenzen.top) * _massstab);
  Offset _zuWelt(Offset b) {
    final x = (b.dx - (_flaeche.width - _grenzen.width * _massstab) / 2) / _massstab + _grenzen.left;
    final y = (b.dy - (_flaeche.height - _grenzen.height * _massstab) / 2) / _massstab + _grenzen.top;
    return Offset((x / 10).round() * 10.0, (y / 10).round() * 10.0);
  }

  void _rueck() {
    if (_rueckgaengig.isEmpty) return;
    _rueckgaengig.removeLast()();
    _s.geaendert();
  }

  static TechnikGeraet? geraetAus(Objekt o) {
    final m = o.eigenschaften['masse'];
    if (m is! List || m.length < 3 || o.punkte.isEmpty) return null;
    final f = Map<String, dynamic>.from(o.eigenschaften['freiraum'] as Map? ?? const {});
    return (
      id: o.id,
      name: o.eigenschaften['geraet'] as String? ?? o.kennung,
      x: o.punkte.first.x,
      y: o.punkte.first.y,
      b: (m[0] as num).toInt(),
      t: (m[1] as num).toInt(),
      drehung: (o.eigenschaften['drehung'] as num?)?.toInt() ?? 0,
      vorn: (f['vorn'] as num?)?.toInt() ?? 0,
      links: (f['links'] as num?)?.toInt() ?? 0,
      rechts: (f['rechts'] as num?)?.toInt() ?? 0,
    );
  }

  String _anlegen(TechnikVorlage v, Offset w, Raum raum, Geschoss g, {int drehung = 0}) {
    final store = _s.store!;
    final typ = store.objekttypen().where((t) => t.kuerzel == v.typ).firstOrNull ?? store.objekttypen().firstWhere((t) => t.geometrie == Geometrieart.punkt);
    final h = raum.hoehen(g);
    final z = switch (v.montage) {
      'Wand' => math.max(300, 1800 - v.h),
      'Decke' => (h.rohdecke - h.ffb) - v.h,
      _ => 0,
    };
    final id = store.objektAnlegen(
      geschossId: g.id,
      typ: typ,
      punkte: [Punkt(w.dx, w.dy)],
      raumId: raum.id,
      z: z,
      zBezug: Hoehenbezug.ffb,
      lage: v.montage == 'Decke' ? 'an Decke' : (v.montage == 'Wand' ? 'auf Wand' : 'auf RFB'),
    );
    store.objektAendern(id, {
      'eigenschaften': jsonEncode({
        'geraet': v.name,
        'masse': [v.b, v.t, v.h],
        'montage': v.montage,
        'drehung': drehung,
        'freiraum': {'vorn': v.vorn, 'links': v.links, 'rechts': v.rechts, 'oben': v.oben},
      }),
    });
    return id;
  }

  void _vorlageEinfuegen(String name, Raum raum, Geschoss g) {
    final namen = raumVorlagen[name] ?? const [];
    final umriss = raum.umriss!;
    final xs = umriss.map((p) => p.x), ys = umriss.map((p) => p.y);
    var x = xs.reduce(math.min) + 100;
    final y0 = ys.reduce(math.min) + 100;
    final ids = <String>[];
    for (final n in namen) {
      final v = technikVorlagen.firstWhere((e) => e.name == n);
      ids.add(_anlegen(v, Offset(x + v.b / 2, y0 + v.t / 2), raum, g));
      x += v.b + 100;
    }
    final store = _s.store!;
    _rueckgaengig.add(() {
      for (final id in ids) {
        store.objektLoeschen(id);
      }
    });
    _s.geaendert();
    zeigeHinweis(context, '${ids.length} Geräte an der oberen Wand eingefügt – jetzt an ihren Platz ziehen.');
  }

  /// 3D-Ansicht des Raums: Geräte als Quader (Höhe über FFB), Leitungen mit
  /// ihren Höhen je Punkt und Durchmesser; Kollisionen werden gemeldet.
  Widget _dreiD(Raum raum, Geschoss g, List<Objekt> objekte, Map<String, Objekttyp> typen, Map<String, Gewerk> gewerke) {
    final store = _s.store!;
    final h = raum.hoehen(g);
    double zUeberFfb(Objekt o, double vorgabe) => o.z == null || o.zBezug == null ? vorgabe : (absolut(o.z!, o.zBezug!, h) - h.ffb).toDouble();
    final farben = <String, Color>{};
    final geraete = <Quader>[];
    for (final o in objekte) {
      final ge = geraetAus(o);
      if (ge == null) continue;
      final m = (o.eigenschaften['masse'] as List).map((e) => (e as num).toDouble()).toList();
      final wand = o.eigenschaften['montage'] == 'Wand';
      geraete.add(Quader(
        id: o.id,
        name: ge.name,
        x: ge.x,
        y: ge.y,
        z: zUeberFfb(o, wand ? 900 : 0),
        b: m[0],
        t: m[1],
        h: m[2],
        drehung: ge.drehung,
      ));
      farben[o.id] = Color(gewerke[typen[o.typId]?.gewerkId]?.farbe ?? 0xFF868E96);
    }
    final leitungen = <Leitung3d>[];
    for (final o in store.objekte(g.id)) {
      if (o.punkte.length < 2 || typen[o.typId]?.geometrie != Geometrieart.linie) continue;
      if (!(o.raumId == raum.id || o.punkte.any((p) => punktInPolygon(p, raum.umriss!)))) continue;
      final zs = o.zPunkte;
      final z0 = zUeberFfb(o, 0);
      leitungen.add(Leitung3d(
        id: o.id,
        name: o.kennung,
        durchmesser: (o.eigenschaften['breite_mm'] as num?)?.toDouble() ?? 20,
        punkte: [
          for (var i = 0; i < o.punkte.length; i++) V3(o.punkte[i].x, o.punkte[i].y, zs != null && i < zs.length ? zs[i] - h.ffb.toDouble() : z0),
        ],
      ));
      farben[o.id] = Color(gewerke[typen[o.typId]?.gewerkId]?.farbe ?? 0xFF1C7ED6);
    }
    return Raum3dAnsicht(
      key: ValueKey('3d-${raum.id}-${_s.revision}'),
      umriss: raum.umriss!,
      raumhoehe: ((raum.ukDecke ?? h.rohdecke) - h.ffb).toDouble(),
      geraete: geraete,
      leitungen: leitungen,
      farben: farben,
      auswahl: _auswahl,
    );
  }

  void _eig(Objekt o, Map<String, Object?> neu) {
    final store = _s.store!;
    final alt = store.objektAendern(o.id, {'eigenschaften': jsonEncode({...o.eigenschaften, ...neu})});
    _rueckgaengig.add(() => store.objektAendern(o.id, alt));
    _s.geaendert();
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final raeume = [
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id))
            if (r.umriss != null) (r, g),
    ];
    if (raeume.isEmpty) {
      return const Center(child: Text('Erst im Grundriss einen Raum anlegen (z. B. Heizraum oder Technikraum).'));
    }
    final technisch = raeume.where((e) => RegExp('heiz|technik|hwr|hausanschluss|keller', caseSensitive: false).hasMatch(e.$1.name));
    _raumId ??= (technisch.isNotEmpty ? technisch.first : raeume.first).$1.id;
    final (raum, g) = raeume.firstWhere((e) => e.$1.id == _raumId, orElse: () => raeume.first);
    final umriss = raum.umriss!;
    final xs = umriss.map((p) => p.x), ys = umriss.map((p) => p.y);
    _grenzen = Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
    final objekte = [
      for (final o in store.objekte(g.id))
        if (o.punkte.length == 1 && (o.raumId == raum.id || punktInPolygon(o.punkte.first, umriss))) o
    ];
    final geraete = [for (final o in objekte) if (geraetAus(o) case final x?) x];
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final gewerke = {for (final x in store.gewerke()) x.id: x};
    final h = raum.hoehen(g);
    double zUeberFfb(Objekt o) => o.z == null || o.zBezug == null ? 300 : (absolut(o.z!, o.zBezug!, h) - h.ffb).toDouble();
    final elektro = [
      for (final o in objekte)
        if (gewerke[typen[o.typId]?.gewerkId]?.kuerzel == 'EL' && geraetAus(o) == null)
          (name: o.kennung, x: o.punkte.first.x, y: o.punkte.first.y, z: zUeberFfb(o)),
    ];
    final wasser = [
      for (final o in store.objekte(g.id))
        if (o.punkte.length >= 2 && const {'SA', 'HZ', 'FH'}.contains(gewerke[typen[o.typId]?.gewerkId]?.kuerzel) && typen[o.typId]?.geometrie == Geometrieart.linie)
          (
            name: o.kennung,
            punkte: o.punkte,
            z: o.zPunkte != null ? o.zPunkte!.reduce(math.max) - h.ffb.toDouble() : zUeberFfb(o),
          ),
    ];
    final hinweise = [...technikKollisionen(geraete, raum: umriss), ...elektroUnterWasser(elektro, wasser)];
    final gewaehlt = objekte.where((o) => o.id == _auswahl).firstOrNull;
    _eigFenster.setzen(
      auswahl: gewaehlt != null && geraetAus(gewaehlt) != null,
      bauen: () => gewaehlt == null ? const SizedBox() : ListView(children: _geraetFelder(gewaehlt)),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _rueck,
        const SingleActivator(LogicalKeyboardKey.keyR): () {
          if (gewaehlt != null && geraetAus(gewaehlt) != null) {
            _eig(gewaehlt, {'drehung': ((geraetAus(gewaehlt)!.drehung + 90) % 360)});
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<String>(
                value: raum.id,
                items: [for (final (r, gg) in raeume) DropdownMenuItem(value: r.id, child: Text('${gg.kuerzel} · ${r.name}'))],
                onChanged: (v) => setState(() {
                  _raumId = v;
                  _auswahl = null;
                }),
              ),
              DropdownButton<String?>(
                value: _setzen?.name,
                hint: const Text('Gerät setzen …'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('– Auswahl –')),
                  for (final v in technikVorlagen) DropdownMenuItem(value: v.name, child: Text('${v.name} (${v.b}×${v.t}×${v.h})')),
                ],
                onChanged: (v) => setState(() => _setzen = technikVorlagen.where((e) => e.name == v).firstOrNull),
              ),
              for (final name in raumVorlagen.keys)
                OutlinedButton.icon(
                  onPressed: () => _vorlageEinfuegen(name, raum, g),
                  icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
                  label: Text('Vorlage $name'),
                ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.crop_square, size: 18), label: Text('2D')),
                  ButtonSegment(value: true, icon: Icon(Icons.view_in_ar, size: 18), label: Text('3D')),
                ],
                selected: {_drei},
                onSelectionChanged: (v) => setState(() => _drei = v.first),
              ),
              IconButton(tooltip: 'Rückgängig (Strg+Z)', onPressed: _rueckgaengig.isEmpty ? null : _rueck, icon: const Icon(Sym.rueckgaengig)),
            ]),
          ),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_drei)
                Expanded(child: _dreiD(raum, g, objekte, typen, gewerke))
              else
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  _flaeche = Size(c.maxWidth, c.maxHeight);
                  return Listener(
                    onPointerDown: (e) {
                      if (e.buttons == kPrimaryButton && _doppel.erkannt(e.localPosition)) _eigFenster.nachKlickOeffnen(context);
                      final w = _zuWelt(e.localPosition);
                      final v = _setzen;
                      if (v != null) {
                        final id = _anlegen(v, w, raum, g);
                        final store = _s.store!;
                        _rueckgaengig.add(() => store.objektLoeschen(id));
                        setState(() {
                          _auswahl = id;
                          _setzen = null;
                        });
                        _s.geaendert();
                        return;
                      }
                      String? treffer;
                      for (final gg in geraete) {
                        if (punktInPolygon(Punkt(w.dx, w.dy), geraeteUmriss(gg))) treffer = gg.id;
                      }
                      treffer ??= objekte.where((o) => (Offset(o.punkte.first.x, o.punkte.first.y) - w).distance < 12 / _massstab).firstOrNull?.id;
                      setState(() {
                        _auswahl = treffer;
                        _ziehStart = treffer == null ? null : w;
                        _versatz = Offset.zero;
                      });
                    },
                    onPointerMove: (e) {
                      final s = _ziehStart;
                      if (s != null) setState(() => _versatz = _zuWelt(e.localPosition) - s);
                    },
                    onPointerUp: (_) {
                      final id = _auswahl, d = _versatz;
                      setState(() {
                        _ziehStart = null;
                        _versatz = Offset.zero;
                      });
                      final o = objekte.where((x) => x.id == id).firstOrNull;
                      if (o == null || d == Offset.zero) return;
                      final store = _s.store!;
                      final p = o.punkte.first;
                      final alt = store.objektAendern(o.id, {'geometrie': Objekt.geometrieText([Punkt(p.x + d.dx, p.y + d.dy)])});
                      _rueckgaengig.add(() => store.objektAendern(o.id, alt));
                      _s.geaendert();
                    },
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _TechnikPainter(
                        umriss: [for (final p in umriss) _zuBild(Offset(p.x, p.y))],
                        geraete: [
                          for (final gg in geraete)
                            gg.id == _auswahl && _versatz != Offset.zero
                                ? (id: gg.id, name: gg.name, x: gg.x + _versatz.dx, y: gg.y + _versatz.dy, b: gg.b, t: gg.t, drehung: gg.drehung, vorn: gg.vorn, links: gg.links, rechts: gg.rechts)
                                : gg,
                        ],
                        sonstige: [
                          for (final o in objekte)
                            if (geraetAus(o) == null) (Offset(o.punkte.first.x, o.punkte.first.y), typen[o.typId]?.kuerzel ?? '?', Color(gewerke[typen[o.typId]?.gewerkId]?.farbe ?? 0xFF888888)),
                        ],
                        zuBild: _zuBild,
                        massstab: _massstab,
                        auswahl: _auswahl,
                        kollision: {
                          for (final gg in geraete)
                            if (hinweise.any((x) => x.contains(gg.name))) gg.id,
                        },
                      ),
                    ),
                  );
                }),
              ),
              SizedBox(
                width: 320,
                child: Material(
                  color: Colors.white,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (gewaehlt != null && geraetAus(gewaehlt) != null) ...(_eigFenster.offen ? [const Text('Eigenschaften sind im eigenen Fenster geöffnet.')] : _geraetFelder(gewaehlt)) else ...[
                      Text(raum.name, style: Theme.of(context).textTheme.titleLarge),
                      Text('${geraete.length} Geräte mit Maßen · ${(raum.flaeche! / 1e6).toStringAsFixed(1).replaceAll('.', ',')} m²',
                          style: const TextStyle(color: BsFarben.textLeise)),
                      const SizedBox(height: 8),
                      const Text(
                          'Gerät oben wählen und in den Raum klicken oder eine Vorlage einfügen. Ziehen verschiebt, R dreht um 90°. '
                          'Schraffiert: Wartungsfreiraum vor dem Gerät. Die Wände des Raums zeigt die Wandansicht (im Grundriss Wand doppelklicken).',
                          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                    ],
                    const SizedBox(height: 16),
                    Text('Kollisionen und Hinweise', style: Theme.of(context).textTheme.titleSmall),
                    if (hinweise.isEmpty) const Text('Keine Kollisionen.', style: TextStyle(color: BsFarben.textLeise)),
                    for (final x in hinweise) Text('• $x', style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _geraetFelder(Objekt o) {
    final g = geraetAus(o)!;
    final m = (o.eigenschaften['masse'] as List).map((e) => (e as num).toInt()).toList();
    final f = Map<String, dynamic>.from(o.eigenschaften['freiraum'] as Map? ?? const {});
    Widget zahl(String label, int wert, void Function(int) setzen) => Expanded(
          child: SpeicherFeld(
            key: ValueKey('$label-${o.id}-$wert'),
            initialValue: '$wert',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, suffixText: 'mm'),
            onFieldSubmitted: (v) => setzen(int.tryParse(v) ?? wert),
          ),
        );
    return [
      Text(o.kennung, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      SpeicherFeld(
        key: ValueKey('gn-${o.id}-${g.name}'),
        initialValue: g.name,
        style: Theme.of(context).textTheme.titleLarge,
        decoration: const InputDecoration(border: InputBorder.none),
        onFieldSubmitted: (v) => _eig(o, {'geraet': v.trim()}),
      ),
      BauelementWahl(
        state: _s,
        wert: o.eigenschaften['bauelement'] as String?,
        kategorien: const [BauelementKategorie.technik, BauelementKategorie.heizkoerper, BauelementKategorie.schrankgeraet],
        onChanged: (e) {
          if (e == null) {
            _eig(o, {'bauelement': null});
            return;
          }
          int? z(String k) => e.zahl(k)?.toInt();
          _eig(o, {
            'bauelement': e.id,
            'geraet': e.anzeige,
            'masse': [z('breite') ?? m[0], z('tiefe') ?? m[1], z('hoehe') ?? m[2]],
            'freiraum': {
              ...f,
              if (z('freiraum_vorne') != null) 'vorn': z('freiraum_vorne'),
              if (z('freiraum_seite') != null) 'links': z('freiraum_seite'),
              if (z('freiraum_seite') != null) 'rechts': z('freiraum_seite'),
            },
          });
        },
      ),
      Row(children: [
        zahl('Breite', m[0], (v) => _eig(o, {'masse': [v, m[1], m[2]]})),
        const SizedBox(width: 8),
        zahl('Tiefe', m[1], (v) => _eig(o, {'masse': [m[0], v, m[2]]})),
        const SizedBox(width: 8),
        zahl('Höhe', m[2], (v) => _eig(o, {'masse': [m[0], m[1], v]})),
      ]),
      Row(children: [
        zahl('Unterkante über FFB (3D)', o.zBezug == Hoehenbezug.ffb ? (o.z ?? 0) : (o.z ?? 0), (v) {
          final store = _s.store!;
          final alt = store.objektAendern(o.id, {'z_mm': v, 'z_bezug': Hoehenbezug.ffb.name});
          _rueckgaengig.add(() => store.objektAendern(o.id, alt));
          _s.geaendert();
        }),
      ]),
      DropdownButtonFormField<String>(
        key: ValueKey('mo-${o.id}-${o.eigenschaften['montage']}'),
        initialValue: const ['Stand', 'Wand', 'Decke'].contains(o.eigenschaften['montage']) ? o.eigenschaften['montage'] as String : 'Stand',
        decoration: const InputDecoration(labelText: 'Montage'),
        items: [for (final x in const ['Stand', 'Wand', 'Decke']) DropdownMenuItem(value: x, child: Text(x))],
        onChanged: (v) => _eig(o, {'montage': v}),
      ),
      const SizedBox(height: 12),
      Text('Wartungsfreiraum', style: Theme.of(context).textTheme.titleSmall),
      Row(children: [
        zahl('vorn', (f['vorn'] as num?)?.toInt() ?? 0, (v) => _eig(o, {'freiraum': {...f, 'vorn': v}})),
        const SizedBox(width: 8),
        zahl('links', (f['links'] as num?)?.toInt() ?? 0, (v) => _eig(o, {'freiraum': {...f, 'links': v}})),
        const SizedBox(width: 8),
        zahl('rechts', (f['rechts'] as num?)?.toInt() ?? 0, (v) => _eig(o, {'freiraum': {...f, 'rechts': v}})),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Text('Drehung ${g.drehung}°'),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => _eig(o, {'drehung': (g.drehung + 90) % 360}),
          icon: const Icon(Icons.rotate_90_degrees_cw_outlined, size: 18),
          label: const Text('Drehen (R)'),
        ),
      ]),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () {
          final store = _s.store!;
          store.objektLoeschen(o.id);
          _rueckgaengig.add(() => store.objektWiederherstellen(o.id));
          setState(() => _auswahl = null);
          _s.geaendert();
        },
        icon: const Icon(Sym.loeschen),
        label: const Text('Gerät entfernen'),
      ),
    ];
  }
}

class _TechnikPainter extends CustomPainter {
  _TechnikPainter({
    required this.umriss,
    required this.geraete,
    required this.sonstige,
    required this.zuBild,
    required this.massstab,
    required this.auswahl,
    required this.kollision,
  });
  final List<Offset> umriss;
  final List<TechnikGeraet> geraete;
  final List<(Offset, String, Color)> sonstige;
  final Offset Function(Offset) zuBild;
  final double massstab;
  final String? auswahl;
  final Set<String> kollision;

  Path _pfad(List<Punkt> p) => Path()..addPolygon([for (final q in p) zuBild(Offset(q.x, q.y))], true);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final raum = Path()..addPolygon(umriss, true);
    canvas.drawPath(raum, Paint()..color = const Color(0xFFF4F1EA));
    canvas.drawPath(raum, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = BsFarben.wandBestand);
    for (final g in geraete) {
      // Wartungsfreiraum schraffiert
      if (g.vorn > 0) {
        final fr = _pfad(freiraumUmriss(g));
        canvas.save();
        canvas.clipPath(fr);
        final b = fr.getBounds();
        final stift = Paint()
          ..color = (kollision.contains(g.id) ? const Color(0xFFB91C1C) : const Color(0xFF1C7ED6)).withValues(alpha: 0.35)
          ..strokeWidth = 1;
        for (var x = b.left - b.height; x < b.right; x += 8) {
          canvas.drawLine(Offset(x, b.bottom), Offset(x + b.height, b.top), stift);
        }
        canvas.restore();
        canvas.drawPath(fr, Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF1C7ED6).withValues(alpha: 0.5));
      }
      final u = _pfad(geraeteUmriss(g));
      canvas.drawPath(u, Paint()..color = kollision.contains(g.id) ? const Color(0xFFFFE3E3) : const Color(0xFFE7F5FF));
      canvas.drawPath(u, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = g.id == auswahl ? 3 : 1.5
        ..color = kollision.contains(g.id) ? const Color(0xFFB91C1C) : const Color(0xFF1864AB));
      final c = zuBild(Offset(g.x, g.y));
      final tp = TextPainter(
        text: TextSpan(text: '${g.name}\n${g.b}×${g.t}', style: const TextStyle(fontSize: 10, color: Colors.black87)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: math.max(40, g.b * massstab));
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    for (final (p, k, f) in sonstige) {
      final c = zuBild(p);
      canvas.drawCircle(c, 7, Paint()..color = Colors.white);
      canvas.drawCircle(c, 7, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = f);
      final tp = TextPainter(text: TextSpan(text: k, style: TextStyle(fontSize: 7, color: f, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _TechnikPainter old) => true;
}
