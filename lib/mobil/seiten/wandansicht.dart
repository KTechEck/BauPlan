import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../kontext.dart';
import '../planstand.dart';
import 'aufmass.dart';

/// Ein Element in der Wandansicht (x ab linker Ecke, z über FFB, mm).
class _Teil {
  _Teil(this.o, this.x, this.z, {this.x2, this.z2});
  final Map<String, dynamic> o;
  final double x;
  final double? z;
  final double? x2, z2;
  bool get istLinie => x2 != null;
}

/// Wandansicht in der App: Wand von der Raumseite gesehen, mit Öffnungen,
/// Geräten und Leitungen in ihrer Höhe, Maßketten (Länge, Abstände ab Ecke,
/// Höhen über FFB) und Installationszonen. Maße antippen → nachmessen.
/// Bohrhilfe: Stelle antippen oder eingeben → was liegt in der Nähe, liegt
/// die Stelle in einer Installationszone, wie man sie anzeichnet.
class WandansichtSeite extends StatefulWidget {
  const WandansichtSeite({super.key, required this.k, required this.geschoss, required this.wand, required this.links});
  final MobilKontext k;
  final Map<String, dynamic> geschoss;
  final Map<String, dynamic> wand;
  final bool links;

  @override
  State<WandansichtSeite> createState() => _WandansichtSeiteState();
}

class _WandansichtSeiteState extends State<WandansichtSeite> {
  late bool _links = widget.links;
  bool _bohren = false, _zonen = true;
  Offset? _bohrpunkt; // x, z in mm
  final _tc = TransformationController();

  MobilKontext get k => widget.k;
  AppWandSeite get _seite => AppWandSeite(widget.wand, _links);

  List<({Map<String, dynamic> o, double x1, double x2, double z1, double z2})> _oeffnungen() {
    final s = _seite;
    return [
      for (final o in Planstand.liste(widget.geschoss['oeffnungen']))
        if (o['wand'] == widget.wand['id'])
          () {
            final t1 = (o['abstand'] as num).toDouble(), t2 = t1 + (o['breite'] as num).toDouble();
            final a = s.xAusT(t1), b = s.xAusT(t2);
            final z1 = o['art'] == 'fenster' ? (o['bruestung'] as num? ?? 0).toDouble() : 0.0;
            return (o: o, x1: math.min(a, b), x2: math.max(a, b), z1: z1, z2: z1 + (o['hoehe'] as num? ?? 2010).toDouble());
          }(),
    ];
  }

  List<_Teil> _teile() {
    final s = _seite;
    final l = s.laenge;
    final aus = <_Teil>[];
    bool nah(Offset p) {
      final v = s.vor(p), x = s.x(p);
      return v > -s.dicke - 60 && v < 350 && x > -80 && x < l + 80;
    }

    for (final o in Planstand.liste(widget.geschoss['objekte'])) {
      if (o['geometrie'] == 'flaeche') continue;
      final pts = punkte(o['punkte']);
      if (pts.isEmpty) continue;
      final h = (o['h'] as num?)?.toDouble();
      final hs = o['hs'] as List?;
      double? zVon(int i) => hs != null && i < hs.length && hs[i] is num ? (hs[i] as num).toDouble() : h;
      if (pts.length == 1) {
        if (nah(pts.first)) aus.add(_Teil(o, s.x(pts.first), h));
      } else {
        for (var i = 0; i + 1 < pts.length; i++) {
          if (nah(pts[i]) && nah(pts[i + 1])) {
            aus.add(_Teil(o, s.x(pts[i]), zVon(i), x2: s.x(pts[i + 1]), z2: zVon(i + 1)));
          } else if (nah(pts[i]) != nah(pts[i + 1])) {
            // Leitung kommt durch die Wand oder auf die Wand zu: Punkt an der Wand
            final p = nah(pts[i]) ? pts[i] : pts[i + 1];
            aus.add(_Teil(o, s.x(p), nah(pts[i]) ? zVon(i) : zVon(i + 1)));
          }
        }
      }
    }
    return aus;
  }

  /// Dachschrägen des Raums (vom PC übernommen oder hier gemessen).
  List<({AppWandSeite seite, double knie, double tiefe, double decke})> _schraegen() {
    final raum = k.plan.raum(_seite.raumId);
    if (raum == null) return const [];
    final r = raum.$1;
    final vomPc = Map<String, dynamic>.from(r['schraegen'] as Map? ?? const {});
    final schluessel = <String>{...vomPc.keys};
    for (final a in k.einstellungen.aufmass.keys) {
      final t = a.split('|'); // id|feld|seite|bezug
      if (t.length == 4 && t[0] == r['id'] && const {'kniestock', 'tiefe', 'decke'}.contains(t[1])) schluessel.add('${t[3]}|${t[2]}');
    }
    final aus = <({AppWandSeite seite, double knie, double tiefe, double decke})>[];
    for (final key in schluessel) {
      final t = key.split('|');
      final w = Planstand.liste(widget.geschoss['waende']).where((x) => x['id'] == t[0]).firstOrNull;
      if (w == null || t.length < 2) continue;
      double wert(String f) {
        final g = k.gemessen(r, f, seite: t[1], bezug: t[0]);
        return (g?.wert ?? ((vomPc[key] as Map?)?[f] as num?) ?? 0).toDouble();
      }

      final knie = wert('kniestock'), tiefe = wert('tiefe'), decke = wert('decke');
      if (knie > 0 && tiefe > 0) aus.add((seite: AppWandSeite(w, t[1] == 'l'), knie: knie, tiefe: tiefe, decke: decke > 0 ? decke : 99999));
    }
    return aus;
  }

  /// Oberkante der Wand an Stelle x (Dachschrägen berücksichtigt).
  List<double> _profil(double hoehe, int n) {
    final s = _seite;
    final sch = _schraegen();
    return [
      for (var i = 0; i <= n; i++)
        () {
          final p = s.ursprung + s.richtung * (s.laenge * i / n) + s.nl * (s.s * 5);
          var z = hoehe;
          for (final q in sch) {
            final d = q.seite.vor(p);
            if (d < -50) continue;
            final zz = d >= q.tiefe ? q.decke : q.knie + (q.decke - q.knie).clamp(0, 99999) * (d.clamp(0, q.tiefe) / q.tiefe);
            if (zz < z) z = zz.toDouble();
          }
          return z;
        }(),
    ];
  }

  void _schraegeMessen(BuildContext context) {
    final raum = k.plan.raum(_seite.raumId);
    if (raum == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diese Wandseite liegt in keinem Raum.')));
      return;
    }
    final r = raum.$1;
    final key = '${widget.wand['id']}|${_seite.seiteKurz}';
    final vomPc = (r['schraegen'] as Map?)?[key] as Map?;
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Dachschräge an dieser Wand: Kniestock (Wandhöhe bis Schrägenbeginn), waagrechte Tiefe von der Wand bis zur waagrechten Decke, '
                'Höhe der waagrechten Decke. Für jede Raumseite einzeln – ungleiche Schrägen sind kein Problem.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          ),
          for (final (f, t) in const [('kniestock', 'Kniestock (Höhe über FFB)'), ('tiefe', 'Tiefe der Schräge (waagrecht ab Wand)'), ('decke', 'Höhe waagrechte Decke (Kehlbalken)')])
            Builder(builder: (_) {
              final plan = ((vomPc?[f]) as num?) ?? 0;
              final a = massAnzeige(k, r, f, plan, seite: _seite.seiteKurz, bezug: '${widget.wand['id']}');
              return ListTile(
                leading: const Icon(Icons.roofing),
                title: Text(t),
                trailing: Text(plan == 0 && a.farbe == massGrob ? '–' : a.text, style: TextStyle(fontWeight: FontWeight.w700, color: a.farbe)),
                onTap: () async {
                  Navigator.pop(c);
                  final e = await massEingeben(context, titel: t, plan: plan, bisher: k.gemessen(r, f, seite: _seite.seiteKurz, bezug: '${widget.wand['id']}')?.wert);
                  if (e == null) return;
                  await k.massSenden(ziel: 'schraege', objekt: r, feld: f, wert: e.wert, plan: plan, seite: _seite.seiteKurz, bezug: '${widget.wand['id']}', raum: '${r['id']}', text: e.text, extra: {'wand': widget.wand['id']});
                  if (mounted) setState(() {});
                },
              );
            }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _seite;
    final g = widget.geschoss;
    final hoehe = raumHoehe(g, s.raumId).toDouble();
    final oeff = _oeffnungen();
    final teile = _teile();
    final laengeAnz = massAnzeige(k, widget.wand, 'laenge', s.laenge, seite: s.seiteKurz, bezug: 'innen');
    return Scaffold(
      appBar: AppBar(
        title: Text('Wand ${seitenName(k.plan, widget.wand, _links)}'),
        actions: [
          IconButton(
            tooltip: 'Andere Wandseite',
            onPressed: () => setState(() {
              _links = !_links;
              _bohrpunkt = null;
            }),
            icon: const Icon(Icons.flip),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(
              avatar: const Icon(Icons.straighten, size: 16),
              label: const Text('Maße'),
              selected: !_bohren,
              onSelected: (_) => setState(() => _bohren = false),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.hardware_outlined, size: 16),
              label: const Text('Bohrhilfe'),
              selected: _bohren,
              onSelected: (_) => setState(() => _bohren = true),
            ),
            FilterChip(label: const Text('Installationszonen'), selected: _zonen, onSelected: (v) => setState(() => _zonen = v)),
            if (_bohren) ActionChip(avatar: const Icon(Icons.keyboard, size: 16), label: const Text('Stelle eingeben'), onPressed: () => _stelleEingeben(context, hoehe)),
            if (!_bohren) ActionChip(avatar: const Icon(Icons.roofing, size: 16), label: const Text('Dachschräge messen'), onPressed: () => _schraegeMessen(context)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Text(
            _bohren
                ? 'Bohrstelle antippen oder eingeben. Rot = Leitung/Gerät näher als 10 cm, gelb = in Installationszone oder bis 30 cm, grün = frei.'
                : 'Maß antippen zum Nachmessen: Länge oben, Raumhöhe links, Öffnungen. Abstände unten ab linker Ecke, Höhen über Fertigfußboden.',
            style: const TextStyle(fontSize: 11, color: BsFarben.textLeise),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, aussen) {
            // Zeichnung so hoch wie nötig (Wand passt in die Breite), darunter die Maßliste
            final noetig = (aussen.maxWidth - 66) / math.max(500, s.laenge) * math.max(500, hoehe) + 104;
            final hz = noetig.clamp(240.0, aussen.maxHeight * 0.72);
            return Column(children: [
              SizedBox(
                height: hz,
                child: LayoutBuilder(builder: (context, c) {
            const rl = 46.0, rr = 20.0, ro = 40.0, ru = 64.0;
            final m = math.min((c.maxWidth - rl - rr) / math.max(500, s.laenge), (c.maxHeight - ro - ru) / math.max(500, hoehe));
            Offset zuBild(double x, double z) => Offset(rl + x * m, ro + (hoehe - z) * m);
            return GestureDetector(
              onTapUp: (d) {
                final b = _tc.toScene(d.localPosition);
                final x = (b.dx - rl) / m, z = hoehe - (b.dy - ro) / m;
                if (_bohren) {
                  if (x < -50 || x > s.laenge + 50 || z < -50 || z > hoehe + 50) return;
                  setState(() => _bohrpunkt = Offset(x.clamp(0, s.laenge), z.clamp(0, hoehe)));
                  _bohrBlatt(context, hoehe, oeff, teile);
                  return;
                }
                // Maße antippen
                if (b.dy < ro + 4 && b.dx > rl && b.dx < rl + s.laenge * m) {
                  wandLaengeMessen(context, k, widget.wand, _links).then((_) => setState(() {}));
                  return;
                }
                if (b.dx < rl - 4) {
                  final raum = k.plan.raum(s.raumId);
                  if (raum != null) raumHoeheMessen(context, k, raum.$1, g).then((_) => setState(() {}));
                  return;
                }
                for (final o in oeff) {
                  if (x >= o.x1 && x <= o.x2 && z >= o.z1 - 100 && z <= o.z2 + 100) {
                    _oeffnungMenue(context, o.o);
                    return;
                  }
                }
                for (final t in teile) {
                  if (!t.istLinie && t.z != null && (Offset(t.x, t.z!) - Offset(x, z)).distance * m < 20) {
                    _objektBlatt(context, t.o, t.x, t.z);
                    return;
                  }
                }
              },
              child: InteractiveViewer(
                transformationController: _tc,
                minScale: 1,
                maxScale: 10,
                child: CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _WandPainter(
                    laenge: s.laenge,
                    hoehe: hoehe,
                    m: m,
                    zuBild: zuBild,
                    oeffnungen: oeff,
                    teile: teile,
                    gewerke: k.plan.gewerke,
                    zonen: _zonen,
                    laengeText: laengeAnz.text,
                    laengeFarbe: laengeAnz.farbe,
                    hoeheText: () {
                      final r = k.plan.raum(s.raumId);
                      return r == null ? (text: mmCm(hoehe), farbe: massGrob) : massAnzeige(k, r.$1, 'hoehe', hoehe);
                    }(),
                    oeffnungText: (o, f) => massAnzeige(k, o, f, o[f] as num? ?? 0),
                    bohrpunkt: _bohrpunkt,
                    brandschutz: widget.wand['brandschutz'] as String?,
                    profil: _profil(hoehe, 60),
                  ),
                ),
              ),
            );
          }),
              ),
              const Divider(height: 1),
              Expanded(child: _massliste(oeff, teile, hoehe)),
            ]);
          }),
        ),
      ]),
    );
  }

  /// Liste der Maße auf dieser Wand: Öffnungen und Geräte mit Abstand ab Ecke und Höhe.
  Widget _massliste(List<({Map<String, dynamic> o, double x1, double x2, double z1, double z2})> oeff, List<_Teil> teile, double hoehe) {
    final s = _seite;
    final punkte = [for (final t in teile) if (!t.istLinie) t]..sort((a, b) => a.x.compareTo(b.x));
    final linien = {for (final t in teile) if (t.istLinie) t.o['id']: t.o};
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
      Text('Wand ${massAnzeige(k, widget.wand, 'laenge', s.laenge, seite: s.seiteKurz, bezug: 'innen').text} lang, Raumhöhe ${mmCm(hoehe)}, Dicke ${mmCm(s.dicke)}'
          '${widget.wand['brandschutz'] == null ? '' : ' · Brandschutz ${widget.wand['brandschutz']}'}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      for (final o in oeff)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(o.o['art'] == 'fenster' ? Icons.window_outlined : Icons.door_front_door_outlined, size: 20),
          title: Text('${switch (o.o['art']) { 'tuer' => 'Tür', 'fenster' => 'Fenster', 'balkontuer' => 'Balkontür', _ => 'Öffnung' }} ${mmCm(o.x2 - o.x1)} × ${mmCm(o.z2 - o.z1)}'),
          subtitle: Text('ab Ecke ${mmCm(o.x1)} bis ${mmCm(o.x2)}${o.z1 > 0 ? ' · Brüstung ${mmCm(o.z1)}' : ''}'),
          onTap: () => _oeffnungMenue(context, o.o),
        ),
      for (final t in punkte)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 10, backgroundColor: k.plan.gewerke[t.o['gewerk']]?.farbe ?? Colors.grey, child: Text('${t.o['typ']}', style: const TextStyle(fontSize: 7, color: Colors.white))),
          title: Text('${t.o['kennung']} · ${t.o['name']}'),
          subtitle: Text('${mmCm(t.x)} ab linker Ecke · ${t.z == null ? 'Höhe nicht geplant' : '${mmCm(t.z!)} über FFB'}'),
          onTap: () => _objektBlatt(context, t.o, t.x, t.z),
        ),
      for (final o in linien.values)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.timeline, size: 20, color: k.plan.gewerke[o['gewerk']]?.farbe),
          title: Text('${o['kennung']} · ${o['name']}'),
          subtitle: Text([if (o['lage'] != null) '${o['lage']}', if (o['kabel'] != null) '${o['kabel']}', if (o['h'] == null && o['hs'] == null) 'Höhe nicht geplant'].join(' · ')),
        ),
      if (oeff.isEmpty && teile.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Auf dieser Wand ist nichts geplant.', style: TextStyle(color: BsFarben.textLeise))),
    ]);
  }

  void _oeffnungMenue(BuildContext context, Map<String, dynamic> o) {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in oeffnungFelder.entries)
            if (!(e.key == 'bruestung' && o['art'] != 'fenster'))
              Builder(builder: (_) {
                final a = massAnzeige(k, o, e.key, o[e.key] as num? ?? 0);
                return ListTile(
                  leading: const Icon(Icons.straighten),
                  title: Text('${e.value} messen'),
                  trailing: Text(a.text, style: TextStyle(color: a.farbe, fontWeight: FontWeight.w700)),
                  onTap: () async {
                    Navigator.pop(c);
                    await oeffnungMessen(context, k, o, e.key, raum: _seite.raumId);
                    if (mounted) setState(() {});
                  },
                );
              }),
        ]),
      ),
    );
  }

  void _objektBlatt(BuildContext context, Map<String, dynamic> o, double x, double? z) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        Text('${o['kennung']} · ${o['name']}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('${mmCm(x)} ab linker Ecke · ${z == null ? 'Höhe nicht geplant' : '${mmCm(z)} über FFB (Mitte)'}', style: const TextStyle(fontWeight: FontWeight.w600)),
        if (o['geraet'] != null) Text('Gerät: ${(o['geraet'] as Map)['name']}'),
        if (o['produkt'] != null) Text('Produkt: ${o['produkt']}'),
        if (o['lage'] != null) Text('Lage: ${o['lage']}'),
        Text('Status: ${k.plan.status.where((s) => s.name == o['status']).firstOrNull?.label ?? o['status']}'),
        for (final a in _anschluesse(o)) Text('Anschluss ${a.$1}: ${mmCm(x + a.$2)} ab Ecke, ${z == null ? '?' : mmCm(z + a.$3)} hoch'),
        const Divider(),
        const Text('Aufmessen (geht an den PC zum Übernehmen)', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final (feld, titel, plan) in [('x', 'Abstand ab linker Ecke', x), ('h', 'Höhe über Fertigfußboden (Mitte)', z ?? 0)])
          Builder(builder: (c) {
            final a = massAnzeige(k, o, feld, plan);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.straighten),
              title: Text(titel),
              trailing: Text(a.text, style: TextStyle(fontWeight: FontWeight.w700, color: a.farbe)),
              onTap: () async {
                Navigator.pop(c);
                final r = await massEingeben(context, titel: '${o['kennung']}: $titel', plan: plan, bisher: k.gemessen(o, feld)?.wert);
                if (r == null) return;
                await k.massSenden(ziel: 'objekt', objekt: o, feld: feld, wert: r.wert, plan: plan, seite: _seite.seiteKurz, raum: _seite.raumId, text: r.text, extra: {'wand': widget.wand['id']});
                if (mounted) setState(() {});
              },
            );
          }),
      ]),
    );
  }

  void _stelleEingeben(BuildContext context, double hoehe) async {
    final xc = TextEditingController(), zc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bohrstelle'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: xc, autofocus: true, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'ab linker Ecke', suffixText: 'cm')),
          TextField(controller: zc, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'über Fertigfußboden', suffixText: 'cm')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Prüfen')),
        ],
      ),
    );
    final x = double.tryParse(xc.text), z = double.tryParse(zc.text);
    if (ok != true || x == null || z == null || !context.mounted) return;
    setState(() => _bohrpunkt = Offset(x * 10, z * 10));
    _bohrBlatt(context, hoehe, _oeffnungen(), _teile());
  }

  List<(String, double, double)> _anschluesse(Map<String, dynamic> o) {
    final g = o['geraet'];
    if (g is! Map) return const [];
    final d = Map<String, dynamic>.from(g['daten'] as Map? ?? const {});
    double zahl(String k) => (d[k] is num ? d[k] as num : num.tryParse('${d[k]}') ?? 0).toDouble();
    final b = zahl('breite'), h = zahl('hoehe');
    return [
      for (final a in (d['anschluesse'] as List? ?? const []))
        if (a is Map) ('${a['name'] ?? a['art']}', ((a['x'] as num?) ?? 0) - b / 2, ((a['y'] as num?) ?? 0) - h / 2),
    ];
  }

  void _bohrBlatt(BuildContext context, double hoehe, List<({Map<String, dynamic> o, double x1, double x2, double z1, double z2})> oeff, List<_Teil> teile) {
    final p = _bohrpunkt;
    if (p == null) return;
    final s = _seite;
    final treffer = <(Map<String, dynamic>, double, bool)>[]; // Objekt, Abstand, Höhe bekannt
    for (final t in teile) {
      double d;
      final bekannt = t.z != null && (!t.istLinie || t.z2 != null);
      if (!bekannt) {
        // Höhe unbekannt: nur waagrechter Abstand zählt (Leitung könnte überall laufen)
        d = t.istLinie ? (p.dx < math.min(t.x, t.x2!) ? math.min(t.x, t.x2!) - p.dx : (p.dx > math.max(t.x, t.x2!) ? p.dx - math.max(t.x, t.x2!) : 0)) : (t.x - p.dx).abs();
      } else if (t.istLinie) {
        d = abstandStrecke(p, Offset(t.x, t.z!), Offset(t.x2!, t.z2!));
      } else {
        d = (Offset(t.x, t.z!) - p).distance;
      }
      if (d <= 300) treffer.add((t.o, d, bekannt));
    }
    treffer.sort((a, b) => a.$2.compareTo(b.$2));
    final zonen = installationszonen(s.laenge, hoehe, [for (final o in oeff) (o.x1, o.x2)]);
    final inZone = zonen.any((r) => r.contains(p));
    final inOeffnung = oeff.any((o) => p.dx >= o.x1 && p.dx <= o.x2 && p.dy >= o.z1 && p.dy <= o.z2);
    final nah = treffer.where((t) => t.$2 < 100).isNotEmpty;
    final farbe = nah ? const Color(0xFFB91C1C) : (inZone || treffer.isNotEmpty ? const Color(0xFFB45309) : massGemessen);
    final urteil = nah
        ? 'Nicht bohren – Leitung/Gerät näher als 10 cm'
        : inZone
            ? 'Vorsicht – Installationszone (hier dürfen Leitungen liegen)'
            : treffer.isNotEmpty
                ? 'Vorsicht – geplante Leitung/Gerät bis 30 cm'
                : 'Laut Plan frei, außerhalb der Installationszonen';
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(padding: const EdgeInsets.all(16), shrinkWrap: true, children: [
        Row(children: [
          Icon(nah ? Icons.dangerous_outlined : (farbe == massGemessen ? Icons.check_circle_outline : Icons.warning_amber), color: farbe, size: 30),
          const SizedBox(width: 10),
          Expanded(child: Text(urteil, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: farbe))),
        ]),
        const SizedBox(height: 10),
        Text('Anzeichnen: ${mmCm(p.dx)} ab linker Ecke, ${mmCm(p.dy)} über Fertigfußboden', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('(von rechts: ${mmCm(s.laenge - p.dx)}, unter Decke: ${mmCm(hoehe - p.dy)})', style: const TextStyle(color: BsFarben.textLeise)),
        if (inOeffnung) const Text('Die Stelle liegt in einer Öffnung.', style: TextStyle(color: Color(0xFFB45309))),
        const SizedBox(height: 8),
        for (final (o, d, bekannt) in treffer)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(d < 100 ? Icons.dangerous_outlined : Icons.warning_amber, color: d < 100 ? const Color(0xFFB91C1C) : const Color(0xFFB45309)),
            title: Text('${o['kennung']} · ${o['name']}'),
            subtitle: Text('${mmCm(d)} entfernt${bekannt ? '' : ' (Höhe nicht geplant – nur seitlicher Abstand)'}${o['kabel'] == null ? '' : ' · ${o['kabel']}'}'),
          ),
        const SizedBox(height: 6),
        const Text('Installationszonen nach DIN 18015-3: 15–45 cm unter der Decke und über dem Boden, 100–130 cm, 10–30 cm neben Ecken, Türen und Fenstern. '
            'Ohne Gewähr – vor dem Bohren mit Leitungssucher prüfen.', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
      ]),
    );
  }
}

class _WandPainter extends CustomPainter {
  _WandPainter({
    required this.laenge,
    required this.hoehe,
    required this.m,
    required this.zuBild,
    required this.oeffnungen,
    required this.teile,
    required this.gewerke,
    required this.zonen,
    required this.laengeText,
    required this.laengeFarbe,
    required this.hoeheText,
    required this.oeffnungText,
    this.bohrpunkt,
    this.brandschutz,
    this.profil = const [],
  });
  final List<double> profil;
  final double laenge, hoehe, m;
  final Offset Function(double x, double z) zuBild;
  final List<({Map<String, dynamic> o, double x1, double x2, double z1, double z2})> oeffnungen;
  final List<_Teil> teile;
  final Map<String, ({String name, Color farbe})> gewerke;
  final bool zonen;
  final String laengeText;
  final Color laengeFarbe;
  final ({String text, Color farbe}) hoeheText;
  final ({String text, Color farbe}) Function(Map<String, dynamic> o, String feld) oeffnungText;
  final Offset? bohrpunkt;
  final String? brandschutz;

  void _text(Canvas c, String t, Offset p, {double groesse = 10, Color farbe = BsFarben.textLeise, bool fett = false, double winkel = 0}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontFamily: 'Roboto', fontSize: groesse, color: farbe, fontWeight: fett ? FontWeight.w700 : FontWeight.w400, backgroundColor: const Color(0xDDFFFFFF))),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(winkel);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  void _masslinie(Canvas c, Offset a, Offset b, String t, Color farbe, {bool fett = false}) {
    final p = Paint()
      ..color = farbe
      ..strokeWidth = 1;
    c.drawLine(a, b, p);
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / math.max(1, d.distance) * 4;
    c.drawLine(a - n, a + n, p);
    c.drawLine(b - n, b + n, p);
    _text(c, t, (a + b) / 2, farbe: farbe, fett: fett, groesse: 10, winkel: math.atan2(d.dy, d.dx).abs() > 1 ? -math.pi / 2 : 0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final wand = Rect.fromPoints(zuBild(0, hoehe), zuBild(laenge, 0));
    canvas.drawRect(wand, Paint()..color = const Color(0xFFF8F9FA));
    if (zonen) {
      final z = Paint()..color = const Color(0x33FAB005);
      for (final r in installationszonen(laenge, hoehe, [for (final o in oeffnungen) (o.x1, o.x2)])) {
        final rr = Rect.fromPoints(zuBild(math.max(0, r.left), math.min(hoehe, r.bottom)), zuBild(math.min(laenge, r.right), math.max(0, r.top)));
        canvas.drawRect(rr, z);
      }
    }
    canvas.drawRect(wand, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = brandschutz == null ? const Color(0xFF495057) : const Color(0xFFC92A2A));
    if (brandschutz != null) _text(canvas, 'Brandschutz $brandschutz', wand.topRight + const Offset(-60, 10), farbe: const Color(0xFFC92A2A), groesse: 9);
    // Öffnungen
    for (final o in oeffnungen) {
      final r = Rect.fromPoints(zuBild(o.x1, o.z2), zuBild(o.x2, o.z1));
      canvas.drawRect(r, Paint()..color = o.o['art'] == 'fenster' ? const Color(0xFFD0EBFF) : const Color(0xFFFFFFFF));
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF868E96));
      final b = oeffnungText(o.o, 'breite'), h = oeffnungText(o.o, 'hoehe');
      _text(canvas, '${b.text} × ${h.text}', r.center, groesse: 9, farbe: b.farbe == massGrob ? h.farbe : b.farbe, fett: true);
      if (o.o['art'] == 'fenster') {
        final br = oeffnungText(o.o, 'bruestung');
        _masslinie(canvas, Offset(r.center.dx, zuBild(0, 0).dy), Offset(r.center.dx, r.bottom), br.text, br.farbe);
      }
    }
    // Leitungen und Geräte
    final punkte = <(double, double, Color)>[];
    for (final t in teile) {
      final farbe = gewerke[t.o['gewerk']]?.farbe ?? const Color(0xFF888888);
      if (t.istLinie) {
        final p = Paint()
          ..color = farbe
          ..strokeWidth = 2.5;
        if (t.z != null && t.z2 != null) {
          canvas.drawLine(zuBild(t.x, t.z!), zuBild(t.x2!, t.z2!), p);
        } else {
          // Höhe unbekannt: als senkrechtes Band andeuten
          final x1 = math.min(t.x, t.x2!), x2 = math.max(t.x, t.x2!);
          canvas.drawRect(Rect.fromPoints(zuBild(x1, hoehe), zuBild(math.max(x2, x1 + 20 / m), 0)), Paint()..color = farbe.withValues(alpha: 0.12));
        }
      } else {
        final z = t.z;
        final c = zuBild(t.x, z ?? 0);
        if (z == null) {
          canvas.drawLine(zuBild(t.x, 0), zuBild(t.x, hoehe), Paint()
            ..color = farbe.withValues(alpha: 0.35)
            ..strokeWidth = 1);
        }
        canvas.drawCircle(c, 7, Paint()..color = farbe);
        _text(canvas, '${t.o['typ']}', c, groesse: 7, farbe: Colors.white, fett: true);
        _text(canvas, '${t.o['kennung']}${z == null ? '' : ' · ${mmCm(z)}'}', Offset((c.dx).clamp(70.0, math.max(70.0, size.width - 70)), c.dy - 14), groesse: 8, farbe: const Color(0xFF343A40));
        punkte.add((t.x, z ?? -1, farbe));
        // Anschlüsse aus der Bibliothek
        final g = t.o['geraet'];
        if (g is Map && z != null) {
          final d = Map<String, dynamic>.from(g['daten'] as Map? ?? const {});
          double zahl(String k) => (d[k] is num ? d[k] as num : num.tryParse('${d[k]}') ?? 0).toDouble();
          final b = zahl('breite'), h = zahl('hoehe');
          if (b > 0 && h > 0) {
            canvas.drawRect(Rect.fromPoints(zuBild(t.x - b / 2, z + h / 2), zuBild(t.x + b / 2, z - h / 2)), Paint()
              ..style = PaintingStyle.stroke
              ..color = farbe);
          }
          for (final a in (d['anschluesse'] as List? ?? const [])) {
            if (a is! Map) continue;
            final p = zuBild(t.x + ((a['x'] as num?) ?? 0) - b / 2, z + ((a['y'] as num?) ?? 0) - h / 2);
            canvas.drawCircle(p, 3, Paint()..color = const Color(0xFF212529));
          }
        }
      }
    }
    // Dachschrägen: alles oberhalb der Oberkante weg, Schräge orange mit Höhen
    if (profil.length > 1 && profil.any((z) => z < hoehe - 1)) {
      final n = profil.length - 1;
      final weg = Path()..moveTo(zuBild(0, hoehe + 300).dx, zuBild(0, hoehe + 300).dy);
      for (var i = 0; i <= n; i++) {
        final q = zuBild(laenge * i / n, profil[i]);
        weg.lineTo(q.dx, q.dy);
      }
      weg.lineTo(zuBild(laenge, hoehe + 300).dx, zuBild(laenge, hoehe + 300).dy);
      weg.close();
      canvas.drawPath(weg, Paint()..color = Colors.white);
      final linie = Path()..moveTo(zuBild(0, profil[0]).dx, zuBild(0, profil[0]).dy);
      for (var i = 1; i <= n; i++) {
        final q = zuBild(laenge * i / n, profil[i]);
        linie.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(linie, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = BsFarben.akzent);
      _text(canvas, 'Oberkante ${mmCm(profil.first)} … ${mmCm(profil.last)}', zuBild(laenge / 2, profil[n ~/ 2]) + const Offset(0, 10), farbe: BsFarben.akzent, groesse: 9);
    }
    // Maßketten: Länge oben, Raumhöhe links, Abstände ab linker Ecke unten
    final oben = zuBild(0, hoehe).dy - 18;
    _masslinie(canvas, Offset(zuBild(0, 0).dx, oben), Offset(zuBild(laenge, 0).dx, oben), laengeText, laengeFarbe, fett: true);
    final links = zuBild(0, 0).dx - 22;
    _masslinie(canvas, Offset(links, zuBild(0, 0).dy), Offset(links, zuBild(0, hoehe).dy), hoeheText.text, hoeheText.farbe, fett: true);
    final xs = <double>{0, laenge, for (final o in oeffnungen) ...[o.x1, o.x2], for (final p in punkte) if (p.$1 >= 0 && p.$1 <= laenge) p.$1}.toList()..sort();
    final unten = zuBild(0, 0).dy + 16;
    var zuletzt = -1e9;
    for (final x in xs) {
      final p = zuBild(x, 0);
      canvas.drawLine(Offset(p.dx, p.dy), Offset(p.dx, unten + 4), Paint()..color = const Color(0xFFADB5BD));
      if (x > 0 && (p.dx - zuletzt) > 26) {
        _text(canvas, mmCm(x), Offset(p.dx, unten + 14), groesse: 8, farbe: const Color(0xFF495057), winkel: -math.pi / 4);
        zuletzt = p.dx;
      }
    }
    canvas.drawLine(Offset(zuBild(0, 0).dx, unten), Offset(zuBild(laenge, 0).dx, unten), Paint()..color = const Color(0xFFADB5BD));
    _text(canvas, 'FFB', zuBild(0, 0) + const Offset(-12, 8), groesse: 8);
    final bp = bohrpunkt;
    if (bp != null) {
      final c = zuBild(bp.dx, bp.dy);
      canvas.drawCircle(c, 300 * m, Paint()..color = const Color(0x18E03131));
      canvas.drawCircle(c, 100 * m, Paint()..color = const Color(0x30E03131));
      final kreuz = Paint()
        ..color = const Color(0xFFE03131)
        ..strokeWidth = 2;
      canvas.drawLine(c - const Offset(8, 0), c + const Offset(8, 0), kreuz);
      canvas.drawLine(c - const Offset(0, 8), c + const Offset(0, 8), kreuz);
      final hilfs = Paint()
        ..color = const Color(0x99E03131)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(zuBild(0, 0).dx, c.dy), c, hilfs);
      canvas.drawLine(Offset(c.dx, zuBild(0, 0).dy), c, hilfs);
    }
  }

  @override
  bool shouldRepaint(covariant _WandPainter old) => true;
}
