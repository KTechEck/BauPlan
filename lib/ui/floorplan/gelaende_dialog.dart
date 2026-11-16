import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/gelaende.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// Geländeeditor: Höhenpunkte rund ums Haus setzen (Klick), Hang als Vorlage,
/// farbige Höhen, Höhenlinien, Gefällepfeile, Hinweise zur Entwässerung.
Future<void> gelaendeDialog(BuildContext context, AppState s) => showDialog<void>(context: context, builder: (_) => _Gelaende(state: s));

class _Gelaende extends StatefulWidget {
  const _Gelaende({required this.state});
  final AppState state;
  @override
  State<_Gelaende> createState() => _GelaendeState();
}

class _GelaendeState extends State<_Gelaende> {
  AppState get _s => widget.state;
  List<Hoehenpunkt> get _punkte => gelaendeLesen(_s.store!.einstellung<Object>('gelaende'));
  void _speichern(List<Hoehenpunkt> p) {
    _s.store!.einstellungSetzen('gelaende', gelaendeJson(p));
    _s.geaendert();
    setState(() {});
  }

  /// Wände des untersten Geschosses (Erdgeschoss) als Bezug.
  List<Wand> get _waende {
    final store = _s.store!;
    for (final geb in store.gebaeude()) {
      final gs = store.geschosse(geb.id);
      final eg = gs.where((g) => g.kuerzel.toUpperCase().contains('EG')).firstOrNull ?? gs.firstOrNull;
      if (eg != null) return store.waende(eg.id);
    }
    return const [];
  }

  Rect _haus(List<Wand> w) {
    if (w.isEmpty) return const Rect.fromLTWH(0, 0, 10000, 8000);
    var r = Rect.fromPoints(Offset(w.first.x1.toDouble(), w.first.y1.toDouble()), Offset(w.first.x2.toDouble(), w.first.y2.toDouble()));
    for (final x in w) {
      r = r.expandToInclude(Rect.fromPoints(Offset(x.x1.toDouble(), x.y1.toDouble()), Offset(x.x2.toDouble(), x.y2.toDouble())));
    }
    return r;
  }

  Future<Hoehenpunkt?> _punktDialog(Offset p, {Hoehenpunkt? alt}) async {
    final z = TextEditingController(text: alt == null ? '-300' : '${alt.z.round()}');
    final name = TextEditingController(text: alt?.name ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(alt == null ? 'Höhenpunkt setzen' : 'Höhenpunkt ändern'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: z,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: const InputDecoration(labelText: 'Höhe relativ zu ±0 (FFB Erdgeschoss)', suffixText: 'mm', helperText: 'z. B. −300 = 30 cm unter Fußboden'),
          ),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Bezeichnung (optional)', hintText: 'z. B. Gehweg, Grenze, Böschungsfuß')),
        ]),
        actions: [
          if (alt != null) TextButton(onPressed: () => Navigator.pop(c, 'weg'), child: const Text('Löschen')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, 'ok'), child: const Text('OK')),
        ],
      ),
    );
    if (r == 'weg') return const Hoehenpunkt(double.nan, 0, 0);
    if (r != 'ok') return null;
    final v = double.tryParse(z.text.replaceAll(',', '.').replaceAll('−', '-'));
    if (v == null) return null;
    return Hoehenpunkt(p.dx, p.dy, v, name: name.text.trim());
  }

  Future<void> _hang() async {
    final haus = _haus(_waende);
    var richtung = 'S';
    final fall = TextEditingController(text: '5'), anHaus = TextEditingController(text: '-300');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Hang als Vorlage'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Legt Höhenpunkte 8 m ums Haus an. Danach einzeln anpassen.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            DropdownButtonFormField<String>(
              initialValue: richtung,
              decoration: const InputDecoration(labelText: 'Hang fällt nach'),
              items: const [
                DropdownMenuItem(value: 'N', child: Text('oben (Nord)')),
                DropdownMenuItem(value: 'S', child: Text('unten (Süd)')),
                DropdownMenuItem(value: 'W', child: Text('links (West)')),
                DropdownMenuItem(value: 'O', child: Text('rechts (Ost)')),
                DropdownMenuItem(value: '-', child: Text('eben (rundum vom Haus weg)')),
              ],
              onChanged: (v) => setD(() => richtung = v ?? 'S'),
            ),
            TextField(controller: fall, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Gefälle', suffixText: '%')),
            TextField(controller: anHaus, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: const InputDecoration(labelText: 'Gelände am Haus (Mitte)', suffixText: 'mm')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Anlegen')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final f = (double.tryParse(fall.text.replaceAll(',', '.')) ?? 5) / 100;
    final z0 = double.tryParse(anHaus.text.replaceAll('−', '-')) ?? -300;
    final m = haus.center;
    final (rx, ry) = switch (richtung) { 'N' => (0.0, -1.0), 'S' => (0.0, 1.0), 'W' => (-1.0, 0.0), 'O' => (1.0, 0.0), _ => (0.0, 0.0) };
    final r = haus.inflate(8000);
    final pts = <Hoehenpunkt>[];
    for (final x in [r.left, haus.left - 500, m.dx, haus.right + 500, r.right]) {
      for (final y in [r.top, haus.top - 500, m.dy, haus.bottom + 500, r.bottom]) {
        if (x > haus.left - 501 && x < haus.right + 501 && y > haus.top - 501 && y < haus.bottom + 501 && !(x == haus.left - 500 || x == haus.right + 500 || y == haus.top - 500 || y == haus.bottom + 500)) continue;
        final z = richtung == '-'
            ? z0 - f * math.max(0, math.max((x - m.dx).abs() - haus.width / 2, (y - m.dy).abs() - haus.height / 2))
            : z0 - f * ((x - m.dx) * rx + (y - m.dy) * ry);
        pts.add(Hoehenpunkt(x, y, z));
      }
    }
    _speichern(pts);
  }

  @override
  Widget build(BuildContext context) {
    final waende = _waende;
    final haus = _haus(waende);
    final punkte = _punkte;
    final hinweise = gelaendeHinweise(punkte, haus.left, haus.top, haus.right, haus.bottom);
    return AlertDialog(
      title: const Text('Gelände'),
      content: SizedBox(
        width: 1100,
        height: 640,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final welt = haus.inflate(9000);
              final m = math.min(c.maxWidth / welt.width, c.maxHeight / welt.height);
              Offset zuBild(Offset w) => (w - welt.topLeft) * m;
              Offset zuWelt(Offset b) => b / m + welt.topLeft;
              return GestureDetector(
                onTapUp: (e) async {
                  final w = zuWelt(e.localPosition);
                  final alt = punkte.where((q) => (Offset(q.x, q.y) - w).distance < 12 / m).firstOrNull;
                  final neu = await _punktDialog(alt == null ? Offset(w.dx.roundToDouble(), w.dy.roundToDouble()) : Offset(alt.x, alt.y), alt: alt);
                  if (neu == null) return;
                  final l = [for (final q in punkte) if (q != alt) q];
                  if (!neu.x.isNaN) l.add(neu);
                  _speichern(l);
                },
                child: ClipRect(
                  child: CustomPaint(
                    size: Size(c.maxWidth, c.maxHeight),
                    painter: _GelaendePainter(punkte, waende, welt, m, zuBild),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 300,
            child: ListView(children: [
              const Text('Klick in den Plan setzt einen Höhenpunkt (Höhe zu ±0 = Fußboden EG). Klick auf einen Punkt ändert oder löscht ihn.',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                OutlinedButton.icon(onPressed: _hang, icon: const Icon(Icons.landscape_outlined, size: 18), label: const Text('Hang als Vorlage …')),
                if (punkte.isNotEmpty) TextButton(onPressed: () => _speichern(const []), child: const Text('Alle löschen')),
              ]),
              const Divider(),
              Text('Entwässerung und Sockel', style: Theme.of(context).textTheme.titleSmall),
              if (punkte.isEmpty) const Text('Noch keine Höhenpunkte.', style: TextStyle(fontSize: 12)),
              if (punkte.isNotEmpty && hinweise.isEmpty) const Text('Gelände fällt rundum vom Haus weg ✓', style: TextStyle(color: Color(0xFF2F9E44))),
              for (final h in hinweise) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $h', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)))),
              const Divider(),
              Text('Höhenpunkte (${punkte.length})', style: Theme.of(context).textTheme.titleSmall),
              for (final q in punkte)
                Text('${q.name.isEmpty ? '' : '${q.name}: '}${q.z >= 0 ? '+' : ''}${q.z.round()} mm  (${(q.x / 1000).toStringAsFixed(1)} | ${(q.y / 1000).toStringAsFixed(1)} m)',
                    style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              const Text('In der 3D-Ansicht des Erdgeschosses erscheint das Gelände als Fläche.', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
    );
  }
}

class _GelaendePainter extends CustomPainter {
  _GelaendePainter(this.punkte, this.waende, this.welt, this.m, this.zuBild);
  final List<Hoehenpunkt> punkte;
  final List<Wand> waende;
  final Rect welt;
  final double m;
  final Offset Function(Offset) zuBild;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF4F6EF));
    if (punkte.isNotEmpty) {
      // Höhen farbig (tief blau-grün … hoch braun)
      final zs = [for (final q in punkte) q.z];
      final lo = zs.reduce(math.min), hi = zs.reduce(math.max);
      const zelle = 600.0;
      for (var y = welt.top; y < welt.bottom; y += zelle) {
        for (var x = welt.left; x < welt.right; x += zelle) {
          final z = gelaendeHoehe(punkte, x + zelle / 2, y + zelle / 2)!;
          final t = hi - lo < 1 ? 0.5 : ((z - lo) / (hi - lo)).clamp(0.0, 1.0);
          final f = Color.lerp(const Color(0xFFB8DDBF), const Color(0xFFD9BE8C), t)!;
          canvas.drawRect(Rect.fromPoints(zuBild(Offset(x, y)), zuBild(Offset(x + zelle, y + zelle))), Paint()..color = f);
        }
      }
      // Höhenlinien alle 250 mm, kräftiger je Meter
      for (final (h, a, b) in hoehenlinien(punkte, welt.left, welt.top, welt.right, welt.bottom, raster: 400)) {
        final meter = (h / 1000).roundToDouble() * 1000 == h;
        canvas.drawLine(zuBild(Offset(a.$1, a.$2)), zuBild(Offset(b.$1, b.$2)), Paint()
          ..color = const Color(0xFF6B5B3E).withValues(alpha: meter ? 0.8 : 0.4)
          ..strokeWidth = meter ? 1.4 : 0.7);
      }
      // Gefällepfeile
      for (var y = welt.top + 1500; y < welt.bottom; y += 3000) {
        for (var x = welt.left + 1500; x < welt.right; x += 3000) {
          final g = gefaelle(punkte, x, y);
          if (g.prozent < 0.3) continue;
          final p = zuBild(Offset(x, y)), q = p + Offset(g.dx, g.dy) * 16;
          final stift = Paint()
            ..color = const Color(0xFF1C7ED6)
            ..strokeWidth = 1.4;
          canvas.drawLine(p, q, stift);
          canvas.drawCircle(q, 2.2, Paint()..color = const Color(0xFF1C7ED6));
          final tp = TextPainter(text: TextSpan(text: '${g.prozent.toStringAsFixed(1).replaceAll('.', ',')} %', style: const TextStyle(fontSize: 9, color: Color(0xFF1C7ED6))), textDirection: TextDirection.ltr)
            ..layout();
          tp.paint(canvas, p + const Offset(4, 2));
        }
      }
    }
    for (final w in waende) {
      canvas.drawLine(zuBild(Offset(w.x1.toDouble(), w.y1.toDouble())), zuBild(Offset(w.x2.toDouble(), w.y2.toDouble())), Paint()
        ..color = BsFarben.wandBestand
        ..strokeWidth = math.max(1.5, w.dicke * m));
    }
    for (final q in punkte) {
      final c = zuBild(Offset(q.x, q.y));
      canvas.drawCircle(c, 5, Paint()..color = Colors.white);
      canvas.drawCircle(c, 5, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF2B8A3E));
      final tp = TextPainter(
        text: TextSpan(text: '${q.z >= 0 ? '+' : ''}${(q.z / 1000).toStringAsFixed(2).replaceAll('.', ',')}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF212529), backgroundColor: Color(0xCCFFFFFF))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + const Offset(7, -6));
    }
  }

  @override
  bool shouldRepaint(covariant _GelaendePainter old) => true;
}
