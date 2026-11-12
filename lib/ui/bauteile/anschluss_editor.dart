import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../core/geraeteanschluesse.dart';

/// Anschlüsse eines Geräts festlegen: Vorderansicht mit Lage der Anschlüsse
/// (antippen setzt den gewählten Anschluss), dazu Art, Bezeichnung, Seite und
/// Größe je Anschluss. Die Lage nutzt die Wandansicht (Anschlusspunkte am Gerät).
class AnschlussEditor extends StatefulWidget {
  const AnschlussEditor({super.key, required this.element, required this.setzen});
  final Bauelement element;
  final ValueChanged<Map<String, dynamic>> setzen;

  @override
  State<AnschlussEditor> createState() => _AnschlussEditorState();
}

class _AnschlussEditorState extends State<AnschlussEditor> {
  int? _gewaehlt;

  List<GeraeteAnschluss> get _liste => geraeteAnschluesse(widget.element.daten);

  int _mass(String k, int vorgabe) {
    final v = widget.element.daten[k];
    final z = v is num ? v.round() : int.tryParse('$v');
    return z == null || z <= 0 ? vorgabe : z;
  }

  void _speichern(List<GeraeteAnschluss> l) => widget.setzen(mitAnschluessen(widget.element.daten, l));

  @override
  Widget build(BuildContext context) {
    final l = _liste;
    final b = _mass('breite', _mass('baulaenge', 200)), h = _mass('hoehe', _mass('bauhoehe', 200));
    if (_gewaehlt != null && _gewaehlt! >= l.length) _gewaehlt = null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Anschlüsse', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () {
            final neu = [...l, GeraeteAnschluss(art: l.isEmpty ? '230 V' : l.last.art, x: b ~/ 2, y: h ~/ 2)];
            _speichern(neu);
            setState(() => _gewaehlt = neu.length - 1);
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Anschluss'),
        ),
        if (l.isEmpty) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _speichern(anschlussVorschlag(widget.element.kategorie, widget.element.daten)),
            child: const Text('Typische Anschlüsse vorschlagen'),
          ),
        ],
      ]),
      const Text(
        'Vorderansicht des Geräts (Breite × Höhe aus den Maßen). Anschluss in der Liste wählen und in der Zeichnung an die richtige Stelle tippen. '
        'x ab linker Kante, y ab Unterkante. Die Wandansicht zeigt die Anschlüsse am eingebauten Gerät.',
        style: TextStyle(fontSize: 12, color: BsFarben.textLeise),
      ),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 260,
          height: 220,
          child: LayoutBuilder(builder: (context, c) {
            final m = math.min((c.maxWidth - 40) / b, (c.maxHeight - 40) / h);
            final ursprung = Offset((c.maxWidth - b * m) / 2, (c.maxHeight + h * m) / 2);
            return GestureDetector(
              onTapDown: (d) {
                final i = _gewaehlt;
                if (i == null) return;
                final x = ((d.localPosition.dx - ursprung.dx) / m).round().clamp(0, b);
                final y = ((ursprung.dy - d.localPosition.dy) / m).round().clamp(0, h);
                final neu = [...l];
                neu[i] = neu[i].mit(x: x, y: y);
                _speichern(neu);
              },
              child: CustomPaint(size: Size(c.maxWidth, c.maxHeight), painter: _GeraetPainter(l, b, h, m, ursprung, _gewaehlt)),
            );
          }),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(children: [
            for (var i = 0; i < l.length; i++) _zeile(l, i),
            if (l.isEmpty) const Text('Noch keine Anschlüsse festgelegt.', style: TextStyle(color: BsFarben.textLeise)),
          ]),
        ),
      ]),
    ]);
  }

  Widget _zeile(List<GeraeteAnschluss> l, int i) {
    final a = l[i];
    void aendern(GeraeteAnschluss neu) {
      final n = [...l];
      n[i] = neu;
      _speichern(n);
    }

    Widget zahl(String label, int wert, void Function(int) setzen) => SizedBox(
          width: 100,
          child: TextFormField(
            key: ValueKey('${widget.element.id}-a$i-$label-$wert'),
            initialValue: '$wert',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, suffixText: 'mm', isDense: true),
            onFieldSubmitted: (v) => setzen(int.tryParse(v) ?? wert),
          ),
        );

    return Material(
      color: _gewaehlt == i ? BsFarben.akzentHell : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _gewaehlt = i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
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
            zahl('x', a.x, (v) => aendern(a.mit(x: v))),
            zahl('y', a.y, (v) => aendern(a.mit(y: v))),
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
                _speichern([...l]..removeAt(i));
                setState(() => _gewaehlt = null);
              },
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GeraetPainter extends CustomPainter {
  _GeraetPainter(this.l, this.b, this.h, this.m, this.ursprung, this.gewaehlt);
  final List<GeraeteAnschluss> l;
  final int b, h;
  final double m;
  final Offset ursprung;
  final int? gewaehlt;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(ursprung.dx, ursprung.dy - h * m, b * m, h * m);
    canvas.drawRect(r, Paint()..color = const Color(0xFFF1F3F5));
    canvas.drawRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF495057)
      ..strokeWidth = 1.5);
    void text(String t, Offset p, {Color farbe = const Color(0xFF495057), double groesse = 10}) {
      final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontFamily: 'Roboto', fontSize: groesse, color: farbe)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    text('$b mm', Offset(r.center.dx, r.bottom + 10));
    canvas.save();
    canvas.translate(r.left - 12, r.center.dy);
    canvas.rotate(-math.pi / 2);
    text('$h mm', Offset.zero);
    canvas.restore();
    for (var i = 0; i < l.length; i++) {
      final a = l[i];
      final p = Offset(ursprung.dx + a.x * m, ursprung.dy - a.y * m);
      final farbe = Color(anschlussFarbe(a.art));
      if (i == gewaehlt) canvas.drawCircle(p, 10, Paint()..color = farbe.withValues(alpha: 0.25));
      canvas.drawCircle(p, 5, Paint()..color = farbe);
      text(a.anzeige, p + const Offset(0, -12), farbe: farbe, groesse: 9);
    }
  }

  @override
  bool shouldRepaint(covariant _GeraetPainter old) => true;
}
