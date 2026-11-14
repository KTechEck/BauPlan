import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../core/geraeteanschluesse.dart';

/// Bohrloch / Befestigungspunkt am Gerät (Vorderansicht, mm ab linker
/// Unterkante), Durchmesser in mm. Gespeichert in `daten['bohrungen']`.
class Bohrung {
  const Bohrung({required this.x, required this.y, this.d = 8});
  final int x, y, d;
  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'd': d};
  static Bohrung ausJson(Map m) => Bohrung(x: (m['x'] as num?)?.round() ?? 0, y: (m['y'] as num?)?.round() ?? 0, d: (m['d'] as num?)?.round() ?? 8);
}

List<Bohrung> bohrungenVon(Map<String, dynamic> daten) => [for (final m in (daten['bohrungen'] as List? ?? const [])) if (m is Map) Bohrung.ausJson(m)];

/// Gewählter Punkt im Schaubild: Anschluss oder Bohrung.
typedef _Wahl = ({bool bohrung, int index});

/// Geräte-Schaubild: Vorderansicht mit Maßen, Anschlüssen, Bohrlöchern und
/// Freiräumen. Punkte lassen sich ziehen (5-mm-Raster, rasten an den Kanten
/// ein und übernehmen dann die Seite), Maße antippen ändert Breite/Höhe,
/// gewählte Punkte zeigen ihre Maßkette. Darunter die Liste zum Feinjustieren.
class AnschlussEditor extends StatefulWidget {
  const AnschlussEditor({super.key, required this.element, required this.setzen});
  final Bauelement element;
  final ValueChanged<Map<String, dynamic>> setzen;

  @override
  State<AnschlussEditor> createState() => _AnschlussEditorState();
}

class _AnschlussEditorState extends State<AnschlussEditor> {
  _Wahl? _wahl;
  Offset? _zieh; // laufende Lage beim Ziehen (mm)

  Map<String, dynamic> get _d => widget.element.daten;
  List<GeraeteAnschluss> get _liste => geraeteAnschluesse(_d);
  List<Bohrung> get _bohrungen => bohrungenVon(_d);

  int _mass(String k, int vorgabe) {
    final v = _d[k];
    final z = v is num ? v.round() : int.tryParse('$v');
    return z == null || z <= 0 ? vorgabe : z;
  }

  String get _breiteSchluessel => _d.containsKey('baulaenge') && !_d.containsKey('breite') ? 'baulaenge' : 'breite';
  String get _hoeheSchluessel => _d.containsKey('bauhoehe') && !_d.containsKey('hoehe') ? 'bauhoehe' : 'hoehe';

  void _speichern({List<GeraeteAnschluss>? anschluesse, List<Bohrung>? bohrungen, Map<String, dynamic>? extra}) {
    var d = {..._d, ...?extra};
    if (anschluesse != null) d = mitAnschluessen(d, anschluesse);
    if (bohrungen != null) {
      if (bohrungen.isEmpty) {
        d.remove('bohrungen');
      } else {
        d['bohrungen'] = [for (final b in bohrungen) b.toJson()];
      }
    }
    widget.setzen(d);
  }

  /// Seite aus der Lage an der Kante (sonst bleibt sie).
  String _seiteAn(int x, int y, int b, int h, String alt) {
    if (y <= 0) return 'unten';
    if (y >= h) return 'oben';
    if (x <= 0) return 'links';
    if (x >= b) return 'rechts';
    return alt == 'unten' || alt == 'oben' || alt == 'links' || alt == 'rechts' ? 'hinten' : alt;
  }

  void _bewegen(_Wahl w, Offset mm, int b, int h, {required bool fertig}) {
    // 5-mm-Raster, Kanten fangen (bis 3 % der Größe)
    var x = (mm.dx / 5).round() * 5, y = (mm.dy / 5).round() * 5;
    final fx = math.max(5, b * 0.03), fy = math.max(5, h * 0.03);
    if (x.abs() < fx) x = 0;
    if ((x - b).abs() < fx) x = b;
    if (y.abs() < fy) y = 0;
    if ((y - h).abs() < fy) y = h;
    x = x.clamp(0, b);
    y = y.clamp(0, h);
    if (!fertig) {
      setState(() => _zieh = Offset(x.toDouble(), y.toDouble()));
      return;
    }
    _zieh = null;
    if (w.bohrung) {
      final l = [..._bohrungen];
      l[w.index] = Bohrung(x: x, y: y, d: l[w.index].d);
      _speichern(bohrungen: l);
    } else {
      final l = [..._liste];
      l[w.index] = l[w.index].mit(x: x, y: y, seite: _seiteAn(x, y, b, h, l[w.index].seite));
      _speichern(anschluesse: l);
    }
  }

  Future<void> _massEingeben(String schluessel, String titel, int aktuell) async {
    final c = TextEditingController(text: '$aktuell');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titel),
        content: TextField(
          controller: c,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'mm'),
          onSubmitted: (t) => Navigator.pop(ctx, int.tryParse(t)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)), child: const Text('Übernehmen')),
        ],
      ),
    );
    if (v != null && v > 0) _speichern(extra: {schluessel: v});
  }

  @override
  Widget build(BuildContext context) {
    final l = _liste, bo = _bohrungen;
    final b = _mass(_breiteSchluessel, 200), h = _mass(_hoeheSchluessel, 200);
    if (_wahl != null && (_wahl!.bohrung ? _wahl!.index >= bo.length : _wahl!.index >= l.length)) _wahl = null;
    int frei(String k) => _mass(k, 0);
    final freiraum = (seite: frei('freiraum_seite'), oben: frei('freiraum_oben'), unten: frei('freiraum_unten'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Schaubild: Anschlüsse und Befestigung', style: Theme.of(context).textTheme.titleMedium),
        OutlinedButton.icon(
          onPressed: () {
            final neu = [...l, GeraeteAnschluss(art: l.isEmpty ? '230 V' : l.last.art, x: b ~/ 2, y: h ~/ 2)];
            _speichern(anschluesse: neu);
            setState(() => _wahl = (bohrung: false, index: neu.length - 1));
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Anschluss'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            final neu = [...bo, Bohrung(x: (b * 0.15).round(), y: (h * 0.85).round())];
            _speichern(bohrungen: neu);
            setState(() => _wahl = (bohrung: true, index: neu.length - 1));
          },
          icon: const Icon(Icons.add_circle_outline, size: 18),
          label: const Text('Bohrloch'),
        ),
        if (bo.isEmpty)
          TextButton(
            onPressed: () {
              // vier Befestigungslöcher 10 % von den Ecken
              final dx = (b * 0.1).round(), dy = (h * 0.1).round();
              _speichern(bohrungen: [Bohrung(x: dx, y: dy), Bohrung(x: b - dx, y: dy), Bohrung(x: dx, y: h - dy), Bohrung(x: b - dx, y: h - dy)]);
            },
            child: const Text('4 Bohrlöcher an den Ecken'),
          ),
        if (l.isEmpty)
          TextButton(
            onPressed: () => _speichern(anschluesse: anschlussVorschlag(widget.element.kategorie, _d)),
            child: const Text('Typische Anschlüsse vorschlagen'),
          ),
      ]),
      const Text(
        'Punkte mit der Maus ziehen (5-mm-Raster, an den Kanten rasten sie ein und bekommen die Seite). Maße unten und links antippen ändert Breite und Höhe. '
        'Gestrichelt: Freiräume aus den Gerätedaten. x ab linker Kante, y ab Unterkante. Wandansicht und Bohr-Check nutzen Anschlüsse und Bohrlöcher.',
        style: TextStyle(fontSize: 12, color: BsFarben.textLeise),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 460,
        child: LayoutBuilder(builder: (context, c) {
          const rand = 56.0;
          final gesamtB = b + 2 * freiraum.seite, gesamtH = h + freiraum.oben + freiraum.unten;
          final m = math.min((c.maxWidth - 2 * rand) / gesamtB, (c.maxHeight - 2 * rand) / gesamtH);
          final ursprung = Offset((c.maxWidth - b * m) / 2, c.maxHeight / 2 + (h * m) / 2 + (freiraum.oben - freiraum.unten) * m / 2);
          Offset mm(Offset p) => Offset((p.dx - ursprung.dx) / m, (ursprung.dy - p.dy) / m);
          Offset bild(num x, num y) => Offset(ursprung.dx + x * m, ursprung.dy - y * m);
          _Wahl? treffer(Offset p) {
            _Wahl? best;
            var bd = 14.0;
            for (var i = 0; i < l.length; i++) {
              final d = (bild(l[i].x, l[i].y) - p).distance;
              if (d < bd) {
                bd = d;
                best = (bohrung: false, index: i);
              }
            }
            for (var i = 0; i < bo.length; i++) {
              final d = (bild(bo[i].x, bo[i].y) - p).distance;
              if (d < bd) {
                bd = d;
                best = (bohrung: true, index: i);
              }
            }
            return best;
          }

          return GestureDetector(
            onTapDown: (d) {
              final p = d.localPosition;
              // Maße antippen
              if (p.dy > ursprung.dy + 4 && p.dy < ursprung.dy + 30 && p.dx > ursprung.dx && p.dx < ursprung.dx + b * m) {
                _massEingeben(_breiteSchluessel, 'Breite des Geräts', b);
                return;
              }
              if (p.dx < ursprung.dx - 4 && p.dx > ursprung.dx - 34 && p.dy < ursprung.dy && p.dy > ursprung.dy - h * m) {
                _massEingeben(_hoeheSchluessel, 'Höhe des Geräts', h);
                return;
              }
              final t = treffer(p);
              if (t != null) {
                setState(() => _wahl = t);
              } else if (_wahl != null) {
                _bewegen(_wahl!, mm(p), b, h, fertig: true);
              }
            },
            onPanStart: (d) {
              final t = treffer(d.localPosition);
              if (t != null) setState(() => _wahl = t);
            },
            onPanUpdate: (d) {
              if (_wahl != null) _bewegen(_wahl!, mm(d.localPosition), b, h, fertig: false);
            },
            onPanEnd: (_) {
              final z = _zieh;
              if (_wahl != null && z != null) _bewegen(_wahl!, z, b, h, fertig: true);
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.precise,
              child: CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _GeraetPainter(
                  l: l,
                  bohrungen: bo,
                  b: b,
                  h: h,
                  m: m,
                  ursprung: ursprung,
                  wahl: _wahl,
                  zieh: _zieh,
                  freiSeite: freiraum.seite,
                  freiOben: freiraum.oben,
                  freiUnten: freiraum.unten,
                  einbauhoehe: _mass('einbauhoehe', 0),
                ),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < l.length; i++) _zeile(l, i),
      for (var i = 0; i < bo.length; i++) _bohrZeile(bo, i, b, h),
      if (l.isEmpty && bo.isEmpty) const Text('Noch keine Anschlüsse oder Bohrlöcher festgelegt.', style: TextStyle(color: BsFarben.textLeise)),
    ]);
  }

  Widget _zahl(String schluessel, String label, int wert, void Function(int) setzen, {String suffix = 'mm', double breite = 112}) => SizedBox(
        width: breite,
        child: TextFormField(
          key: ValueKey('${widget.element.id}-$schluessel-$wert'),
          initialValue: '$wert',
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
          onFieldSubmitted: (v) => setzen(int.tryParse(v) ?? wert),
        ),
      );

  Widget _zeilenRahmen(_Wahl w, List<Widget> kinder) => Material(
        color: _wahl == w ? BsFarben.akzentHell : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _wahl = w),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: kinder),
          ),
        ),
      );

  Widget _zeile(List<GeraeteAnschluss> l, int i) {
    final a = l[i];
    void aendern(GeraeteAnschluss neu) {
      final n = [...l];
      n[i] = neu;
      _speichern(anschluesse: n);
    }

    return _zeilenRahmen((bohrung: false, index: i), [
      CircleAvatar(radius: 7, backgroundColor: Color(anschlussFarbe(a.art))),
      SizedBox(
        width: 170,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: anschlussArten.containsKey(a.art) ? a.art : 'Sonstiges',
          decoration: const InputDecoration(labelText: 'Art', isDense: true),
          items: [for (final k in anschlussArten.keys) DropdownMenuItem(value: k, child: Text(k, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => aendern(a.mit(art: v)),
        ),
      ),
      SizedBox(
        width: 110,
        child: TextFormField(
          key: ValueKey('${widget.element.id}-a$i-name-${a.name}'),
          initialValue: a.name,
          decoration: const InputDecoration(labelText: 'Bezeichnung', isDense: true),
          onFieldSubmitted: (v) => aendern(a.mit(name: v.trim())),
        ),
      ),
      SizedBox(
        width: 96,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: anschlussSeiten.contains(a.seite) ? a.seite : 'hinten',
          decoration: const InputDecoration(labelText: 'Seite', isDense: true),
          items: [for (final k in anschlussSeiten) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (v) => aendern(a.mit(seite: v)),
        ),
      ),
      _zahl('a$i-x', 'x', a.x, (v) => aendern(a.mit(x: v))),
      _zahl('a$i-y', 'y', a.y, (v) => aendern(a.mit(y: v))),
      SizedBox(
        width: 90,
        child: TextFormField(
          key: ValueKey('${widget.element.id}-a$i-gr-${a.groesse}'),
          initialValue: a.groesse,
          decoration: const InputDecoration(labelText: 'Größe', hintText: '½", 3×1,5', isDense: true),
          onFieldSubmitted: (v) => aendern(a.mit(groesse: v.trim())),
        ),
      ),
      IconButton(
        tooltip: 'Anschluss entfernen',
        onPressed: () {
          _speichern(anschluesse: [...l]..removeAt(i));
          setState(() => _wahl = null);
        },
        icon: const Icon(Icons.close, size: 18),
      ),
    ]);
  }

  Widget _bohrZeile(List<Bohrung> l, int i, int b, int h) {
    final a = l[i];
    void aendern(Bohrung neu) {
      final n = [...l];
      n[i] = neu;
      _speichern(bohrungen: n);
    }

    return _zeilenRahmen((bohrung: true, index: i), [
      const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF495057)),
      SizedBox(width: 90, child: Text('Bohrloch ${i + 1}', style: const TextStyle(fontSize: 13))),
      _zahl('b$i-x', 'x', a.x, (v) => aendern(Bohrung(x: v, y: a.y, d: a.d))),
      _zahl('b$i-y', 'y', a.y, (v) => aendern(Bohrung(x: a.x, y: v, d: a.d))),
      _zahl('b$i-d', 'Ø', a.d, (v) => aendern(Bohrung(x: a.x, y: a.y, d: v)), breite: 80),
      Text('von rechts ${b - a.x} · von oben ${h - a.y} mm', style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
      IconButton(
        tooltip: 'Bohrloch entfernen',
        onPressed: () {
          _speichern(bohrungen: [...l]..removeAt(i));
          setState(() => _wahl = null);
        },
        icon: const Icon(Icons.close, size: 18),
      ),
    ]);
  }
}

class _GeraetPainter extends CustomPainter {
  _GeraetPainter({
    required this.l,
    required this.bohrungen,
    required this.b,
    required this.h,
    required this.m,
    required this.ursprung,
    required this.wahl,
    required this.zieh,
    required this.freiSeite,
    required this.freiOben,
    required this.freiUnten,
    required this.einbauhoehe,
  });
  final List<GeraeteAnschluss> l;
  final List<Bohrung> bohrungen;
  final int b, h, freiSeite, freiOben, freiUnten, einbauhoehe;
  final double m;
  final Offset ursprung;
  final _Wahl? wahl;
  final Offset? zieh;

  Offset _p(num x, num y) => Offset(ursprung.dx + x * m, ursprung.dy - y * m);

  void _text(Canvas canvas, String t, Offset p, {Color farbe = const Color(0xFF495057), double groesse = 10, bool fett = false, bool hinterlegt = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(fontFamily: 'Roboto', fontSize: groesse, color: farbe, fontWeight: fett ? FontWeight.w700 : FontWeight.w400, backgroundColor: hinterlegt ? Colors.white : null),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  void _gestrichelt(Canvas canvas, Rect r, Paint p) {
    for (final (a, e) in [(r.topLeft, r.topRight), (r.topRight, r.bottomRight), (r.bottomRight, r.bottomLeft), (r.bottomLeft, r.topLeft)]) {
      final len = (e - a).distance;
      if (len < 1) continue;
      final u = (e - a) / len;
      for (var t = 0.0; t < len; t += 8) {
        canvas.drawLine(a + u * t, a + u * math.min(t + 4, len), p);
      }
    }
  }

  void _massLinie(Canvas canvas, Offset a, Offset e, String text, {Color farbe = const Color(0xFF1C7ED6)}) {
    final p = Paint()
      ..color = farbe
      ..strokeWidth = 1;
    canvas.drawLine(a, e, p);
    final u = e - a;
    final n = Offset(-u.dy, u.dx) / math.max(1, u.distance) * 4;
    canvas.drawLine(a - n, a + n, p);
    canvas.drawLine(e - n, e + n, p);
    _text(canvas, text, (a + e) / 2, farbe: farbe, groesse: 10, fett: true, hinterlegt: true);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromPoints(_p(0, h), _p(b, 0));
    // Freiräume
    if (freiSeite > 0 || freiOben > 0 || freiUnten > 0) {
      final fr = Rect.fromPoints(_p(-freiSeite, h + freiOben), _p(b + freiSeite, -freiUnten));
      canvas.drawRect(fr, Paint()..color = const Color(0x1440C057));
      _gestrichelt(canvas, fr, Paint()
        ..color = const Color(0xFF2F9E44)
        ..strokeWidth = 1);
      _text(canvas, 'Freiraum', Offset(fr.center.dx, fr.top + 8), farbe: const Color(0xFF2F9E44), groesse: 9);
    }
    canvas.drawRect(r, Paint()..color = const Color(0xFFF1F3F5));
    canvas.drawRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF495057)
      ..strokeWidth = 1.5);
    // Maße außen (antippbar)
    _massLinie(canvas, Offset(r.left, r.bottom + 16), Offset(r.right, r.bottom + 16), '$b mm', farbe: const Color(0xFF495057));
    canvas.save();
    canvas.translate(r.left - 18, r.center.dy);
    canvas.rotate(-math.pi / 2);
    _massLinie(canvas, Offset(-r.height / 2, 0), Offset(r.height / 2, 0), '$h mm', farbe: const Color(0xFF495057));
    canvas.restore();
    if (einbauhoehe > 0) _text(canvas, 'Einbau: Mitte $einbauhoehe mm über FFB', Offset(r.center.dx, r.bottom + 38 + freiUnten * m), groesse: 10);
    // Bohrlöcher
    for (var i = 0; i < bohrungen.length; i++) {
      final w = wahl != null && wahl!.bohrung && wahl!.index == i;
      final q = w && zieh != null ? zieh! : Offset(bohrungen[i].x.toDouble(), bohrungen[i].y.toDouble());
      final p = _p(q.dx, q.dy);
      final rad = math.max(3.0, bohrungen[i].d * m / 2);
      final stift = Paint()
        ..style = PaintingStyle.stroke
        ..color = w ? BsFarben.akzentDunkel : const Color(0xFF343A40)
        ..strokeWidth = w ? 2 : 1.2;
      canvas.drawCircle(p, rad, stift);
      canvas.drawLine(p - Offset(rad + 4, 0), p + Offset(rad + 4, 0), stift);
      canvas.drawLine(p - Offset(0, rad + 4), p + Offset(0, rad + 4), stift);
      if (w) _masse(canvas, q);
    }
    // Anschlüsse
    for (var i = 0; i < l.length; i++) {
      final a = l[i];
      final w = wahl != null && !wahl!.bohrung && wahl!.index == i;
      final q = w && zieh != null ? zieh! : Offset(a.x.toDouble(), a.y.toDouble());
      final p = _p(q.dx, q.dy);
      final farbe = Color(anschlussFarbe(a.art));
      if (w) canvas.drawCircle(p, 11, Paint()..color = farbe.withValues(alpha: 0.25));
      canvas.drawCircle(p, 6, Paint()..color = farbe);
      // Pfeil zur Seite, aus der der Anschluss herauskommt
      final dir = switch (a.seite) { 'oben' => const Offset(0, -1), 'unten' => const Offset(0, 1), 'links' => const Offset(-1, 0), 'rechts' => const Offset(1, 0), _ => Offset.zero };
      if (dir != Offset.zero) {
        canvas.drawLine(p, p + dir * 16, Paint()
          ..color = farbe
          ..strokeWidth = 2);
      }
      _text(canvas, '${a.anzeige}${a.groesse.isEmpty ? '' : ' ${a.groesse}'}', p + const Offset(0, -15), farbe: farbe, groesse: 9, fett: w);
      if (w) _masse(canvas, q);
    }
  }

  /// Maßkette des gewählten Punkts: ab linker Kante und ab Unterkante.
  void _masse(Canvas canvas, Offset q) {
    final p = _p(q.dx, q.dy);
    if (q.dx > 0) _massLinie(canvas, Offset(_p(0, 0).dx, p.dy), p, '${q.dx.round()}');
    if (q.dy > 0) _massLinie(canvas, Offset(p.dx, _p(0, 0).dy), p, '${q.dy.round()}');
  }

  @override
  bool shouldRepaint(covariant _GeraetPainter old) => true;
}
