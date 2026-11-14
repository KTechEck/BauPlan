import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/hydraulik_schema.dart';
import '../../core/ids.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Hydraulikschema-Editor: Symbole aus der Bibliothek setzen und ziehen,
/// mit Leitungen (Vorlauf, Rücklauf, Warmwasser …) verbinden und mit Geräten
/// im Grundriss verknüpfen. Ausgabe als SVG (auch als C.M.I.-Hintergrund).
class HydraulikSchemaAnsicht extends StatefulWidget {
  const HydraulikSchemaAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<HydraulikSchemaAnsicht> createState() => _HydraulikSchemaAnsichtState();
}

class _HydraulikSchemaAnsichtState extends State<HydraulikSchemaAnsicht> {
  String? _setzen; // Symbolart zum Setzen
  String _linienArt = 'vl';
  String? _verbindenVon;
  String? _auswahl;
  String? _ziehen;
  Offset _ver = const Offset(40, 40);

  AppState get _s => widget.state;
  HydraulikSchema get _schema => HydraulikSchema.ausJson(_s.store!.einstellung<Map>('hydraulikschema'));

  void _speichern(HydraulikSchema s) {
    _s.store!.einstellungSetzen('hydraulikschema', s.toJson());
    setState(() {});
  }

  SchemaSymbol? _treffer(HydraulikSchema s, Offset w) {
    for (final sy in s.symbole.reversed) {
      final (b, h) = sy.groesse;
      if ((w.dx - sy.x).abs() <= b / 2 + 4 && (w.dy - sy.y).abs() <= h / 2 + 4) return sy;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = _schema;
    final store = _s.store!;
    final gew = s.symbole.where((x) => x.id == _auswahl).firstOrNull;
    final objekte = [for (final o in store.alleObjekte()) if (o.punkte.length == 1) o];
    final typen = {for (final t in store.objekttypen()) t.id: t};
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 220,
        child: Material(
          color: Colors.white,
          child: ListView(padding: const EdgeInsets.all(10), children: [
            const Text('Symbole', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text('Wählen, dann ins Schema klicken.', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
            for (final e in schemaSymbole.entries)
              ListTile(
                dense: true,
                selected: _setzen == e.key,
                title: Text(e.value.$1),
                onTap: () => setState(() {
                  _setzen = _setzen == e.key ? null : e.key;
                  _verbindenVon = null;
                }),
              ),
            const Divider(),
            const Text('Leitung', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text('Art wählen, dann zwei Symbole nacheinander anklicken.', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in schemaLeitungen.entries)
                ChoiceChip(
                  label: Text(e.value.$1, style: TextStyle(color: Color(e.value.$2))),
                  selected: _linienArt == e.key,
                  onSelected: (_) => setState(() {
                    _linienArt = e.key;
                    _setzen = null;
                  }),
                ),
            ]),
          ]),
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(_setzen != null
                  ? 'Klicken setzt: ${schemaSymbole[_setzen]!.$1}'
                  : _verbindenVon != null
                      ? 'Zweites Symbol für die Leitung anklicken (Esc/Rechtsklick bricht ab)'
                      : 'Ziehen verschiebt · Klick wählt · Symbol anklicken und dann ein zweites verbindet'),
              OutlinedButton.icon(
                onPressed: s.symbole.isEmpty
                    ? null
                    : () async {
                        final f = File(p.join(store.ordner, 'exporte', 'Hydraulikschema.svg'));
                        await f.parent.create(recursive: true);
                        await f.writeAsString(schemaSvg(s, titel: 'Hydraulikschema ${store.name}'));
                        if (context.mounted) zeigeHinweis(context, 'Gespeichert unter ${f.path}');
                      },
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Als SVG'),
              ),
            ]),
          ),
          Expanded(
            child: GestureDetector(
              onSecondaryTap: () => setState(() {
                _verbindenVon = null;
                _setzen = null;
              }),
              onTapUp: (d) {
                final w = d.localPosition - _ver;
                final hit = _treffer(s, w);
                if (_setzen != null) {
                  _speichern(HydraulikSchema([...s.symbole, SchemaSymbol(id: neueId(), art: _setzen!, x: (w.dx / 10).round() * 10, y: (w.dy / 10).round() * 10)], s.linien));
                  return;
                }
                if (hit == null) {
                  setState(() {
                    _auswahl = null;
                    _verbindenVon = null;
                  });
                  return;
                }
                if (_verbindenVon != null && _verbindenVon != hit.id) {
                  _speichern(HydraulikSchema(s.symbole, [...s.linien, SchemaLinie(id: neueId(), von: _verbindenVon!, bis: hit.id, art: _linienArt)]));
                  setState(() => _verbindenVon = null);
                  return;
                }
                setState(() {
                  _auswahl = hit.id;
                  _verbindenVon = hit.id;
                });
              },
              onPanStart: (d) {
                final hit = _treffer(s, d.localPosition - _ver);
                _ziehen = hit?.id;
              },
              onPanUpdate: (d) {
                if (_ziehen == null) {
                  setState(() => _ver += d.delta);
                  return;
                }
                final sy = s.symbole.firstWhere((x) => x.id == _ziehen);
                final neu = [for (final x in s.symbole) x.id == _ziehen ? sy.mit(x: sy.x + d.delta.dx, y: sy.y + d.delta.dy) : x];
                _speichern(HydraulikSchema(neu, s.linien));
              },
              onPanEnd: (_) {
                if (_ziehen == null) return;
                final neu = [for (final x in s.symbole) x.id == _ziehen ? x.mit(x: (x.x / 10).round() * 10, y: (x.y / 10).round() * 10) : x];
                _ziehen = null;
                _speichern(HydraulikSchema(neu, s.linien));
              },
              child: ClipRect(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _SchemaPainter(s, _ver, _auswahl, _verbindenVon),
                ),
              ),
            ),
          ),
        ]),
      ),
      if (gew != null)
        SizedBox(
          width: 280,
          child: Material(
            color: Colors.white,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Text(schemaSymbole[gew.art]?.$1 ?? gew.art, style: Theme.of(context).textTheme.titleMedium),
              SpeicherFeld(
                key: ValueKey('hs-name-${gew.id}-${gew.name}'),
                initialValue: gew.name,
                decoration: const InputDecoration(labelText: 'Bezeichnung (z. B. HK1, Pumpe P2)'),
                onFieldSubmitted: (t) => _speichern(HydraulikSchema([for (final x in s.symbole) x.id == gew.id ? x.mit(name: t.trim()) : x], s.linien)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: objekte.any((o) => o.id == gew.objekt) ? gew.objekt : null,
                decoration: const InputDecoration(labelText: 'Verknüpft mit Gerät im Grundriss'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('–')),
                  for (final o in objekte) DropdownMenuItem(value: o.id, child: Text('${o.kennung} · ${typen[o.typId]?.name ?? ''}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => _speichern(HydraulikSchema([for (final x in s.symbole) x.id == gew.id ? x.mit(objekt: v) : x], s.linien)),
              ),
              if (gew.objekt != null)
                TextButton.icon(
                  onPressed: () {
                    final o = objekte.where((o) => o.id == gew.objekt).firstOrNull;
                    if (o == null) return;
                    _s.markiert = {o.id};
                    _s.geschossId = o.geschossId;
                    _s.modulWaehlen(Modul.installation);
                  },
                  icon: const Icon(Icons.place_outlined, size: 18),
                  label: const Text('Im Grundriss zeigen'),
                ),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => _speichern(HydraulikSchema([for (final x in s.symbole) x.id == gew.id ? x.mit(drehung: (x.drehung + 90) % 360) : x], s.linien)),
                  icon: const Icon(Icons.rotate_right, size: 18),
                  label: const Text('Drehen'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    _speichern(HydraulikSchema([for (final x in s.symbole) if (x.id != gew.id) x], [for (final l in s.linien) if (l.von != gew.id && l.bis != gew.id) l]));
                    setState(() => _auswahl = null);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Löschen'),
                ),
              ]),
              const Divider(),
              const Text('Leitungen dieses Symbols', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final l in s.linien.where((l) => l.von == gew.id || l.bis == gew.id))
                ListTile(
                  dense: true,
                  title: Text('${schemaLeitungen[l.art]?.$1 ?? l.art} → ${s.symbole.where((x) => x.id == (l.von == gew.id ? l.bis : l.von)).firstOrNull?.name ?? ''}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => _speichern(HydraulikSchema(s.symbole, [for (final x in s.linien) if (x.id != l.id) x])),
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }
}

class _SchemaPainter extends CustomPainter {
  _SchemaPainter(this.s, this.ver, this.auswahl, this.von);
  final HydraulikSchema s;
  final Offset ver;
  final String? auswahl, von;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = BsFarben.zeichenflaeche);
    final raster = Paint()..color = BsFarben.raster;
    for (var x = ver.dx % 20; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), raster);
    }
    for (var y = ver.dy % 20; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), raster);
    }
    canvas.save();
    canvas.translate(ver.dx, ver.dy);
    final nach = {for (final sy in s.symbole) sy.id: sy};
    for (final l in s.linien) {
      final a = nach[l.von], b = nach[l.bis];
      if (a == null || b == null) continue;
      final (_, farbe, strich) = schemaLeitungen[l.art] ?? ('', 0xFF000000, false);
      final p = Paint()
        ..color = Color(farbe)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      final w = schemaWeg(a, b);
      for (var i = 0; i + 1 < w.length; i++) {
        final p0 = Offset(w[i].$1, w[i].$2), p1 = Offset(w[i + 1].$1, w[i + 1].$2);
        if (!strich) {
          canvas.drawLine(p0, p1, p);
        } else {
          final d = p1 - p0;
          final len = d.distance;
          if (len < 1) continue;
          final u = d / len;
          for (var t = 0.0; t < len; t += 9) {
            canvas.drawLine(p0 + u * t, p0 + u * (t + 5 > len ? len : t + 5), p);
          }
        }
      }
    }
    for (final sy in s.symbole) {
      final (b, h) = sy.groesse;
      final r = Rect.fromCenter(center: Offset(sy.x, sy.y), width: b, height: h);
      final rahmen = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sy.id == auswahl ? 2.5 : 1.5
        ..color = sy.id == auswahl ? BsFarben.akzent : (sy.id == von ? BsFarben.akzentDunkel : Colors.black87);
      final fuell = Paint()..color = Colors.white;
      switch (sy.art) {
        case 'pumpe':
          canvas.drawCircle(r.center, b / 2, fuell);
          canvas.drawCircle(r.center, b / 2, rahmen);
          final path = Path()
            ..moveTo(r.center.dx - b / 4, r.center.dy - h / 3)
            ..lineTo(r.center.dx + b / 3, r.center.dy)
            ..lineTo(r.center.dx - b / 4, r.center.dy + h / 3)
            ..close();
          canvas.drawPath(path, rahmen);
        case 'fuehler':
          canvas.drawCircle(r.center, b / 2, fuell);
          canvas.drawCircle(r.center, b / 2, rahmen);
          _text(canvas, 'T', r.center, 9);
        case 'mischer' || 'umschalt' || 'ventil' || 'rueckschlag':
          final path = Path()
            ..moveTo(r.left, r.top)
            ..lineTo(r.right, r.bottom)
            ..lineTo(r.right, r.top)
            ..lineTo(r.left, r.bottom)
            ..close();
          canvas.drawPath(path, fuell);
          canvas.drawPath(path, rahmen);
          if (sy.art == 'mischer' || sy.art == 'umschalt') {
            canvas.drawLine(r.center, Offset(r.center.dx, r.bottom + 6), rahmen);
          }
        case 'ag':
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(b / 2)), fuell);
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(b / 2)), rahmen);
        case 'text':
          _text(canvas, sy.name.isEmpty ? 'Text' : sy.name, r.center, 11);
          continue;
        default:
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), fuell);
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), rahmen);
          if (sy.art == 'puffer' || sy.art == 'tww') {
            for (var i = 1; i < 4; i++) {
              canvas.drawLine(Offset(r.left + 4, r.top + h * i / 4), Offset(r.right - 4, r.top + h * i / 4), Paint()..color = Colors.black12);
            }
          }
      }
      _text(canvas, sy.name.isEmpty ? (schemaSymbole[sy.art]?.$1 ?? sy.art) : sy.name, Offset(r.center.dx, r.bottom + 9), 10);
      if (sy.objekt != null) canvas.drawCircle(Offset(r.right, r.top), 3.5, Paint()..color = const Color(0xFF2F9E44));
    }
    canvas.restore();
  }

  void _text(Canvas c, String t, Offset mitte, double groesse) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: groesse, color: Colors.black87, fontFamily: 'Roboto')),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 160);
    tp.paint(c, mitte - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_SchemaPainter o) => true;
}
