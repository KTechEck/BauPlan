import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/dach.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';
import '../widgets.dart';

String dachSchluessel(String geschossId) => 'dach_$geschossId';

DachEinstellung dachLesen(ProjectStore store, String geschossId) =>
    DachEinstellung.ausJson((store.einstellung<Map>(dachSchluessel(geschossId)))?.cast<String, dynamic>());

/// Außenkanten des Geschosses aus den Wänden.
Gebaeuderahmen? gebaeuderahmen(List<Wand> waende) {
  if (waende.isEmpty) return null;
  var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
  for (final w in waende) {
    final h = w.dicke / 2;
    x0 = math.min(x0, math.min(w.x1, w.x2) - h);
    y0 = math.min(y0, math.min(w.y1, w.y2) - h);
    x1 = math.max(x1, math.max(w.x1, w.x2) + h);
    y1 = math.max(y1, math.max(w.y1, w.y2) + h);
  }
  return (x0: x0, y0: y0, x1: x1, y1: y1);
}

/// Dachgeschoss bearbeiten: Dachform, Neigung, Kniestock, Sparren, Dämmung, Kehlbalken, Dachfenster.
Future<void> dachBearbeiten(BuildContext context, ProjectStore store, String geschossId, VoidCallback geaendert) async {
  await showDialog<void>(context: context, builder: (_) => _DachDialog(store: store, geschossId: geschossId, geaendert: geaendert));
}

class _DachDialog extends StatefulWidget {
  const _DachDialog({required this.store, required this.geschossId, required this.geaendert});
  final ProjectStore store;
  final String geschossId;
  final VoidCallback geaendert;

  @override
  State<_DachDialog> createState() => _DachDialogState();
}

class _DachDialogState extends State<_DachDialog> {
  late Map<String, dynamic> _m = dachLesen(widget.store, widget.geschossId).toJson();

  DachEinstellung get _d => DachEinstellung.ausJson(_m);

  void _setzen(String k, Object? v) {
    setState(() => _m = {..._m, k: v});
    widget.store.einstellungSetzen(dachSchluessel(widget.geschossId), _m);
    widget.geaendert();
  }

  Widget _zahl(String label, String k, num wert, {String einheit = 'mm', bool komma = false, String? hilfe}) => SizedBox(
        width: 150,
        child: SpeicherFeld(
          key: ValueKey('dach-$k-$wert'),
          initialValue: '$wert'.replaceAll('.', ','),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(komma ? r'[0-9,.]' : r'[0-9]'))],
          decoration: InputDecoration(labelText: label, suffixText: einheit, helperText: hilfe, isDense: true),
          onFieldSubmitted: (v) {
            final z = num.tryParse(v.replaceAll(',', '.'));
            if (z != null) _setzen(k, komma ? z.toDouble() : z.toInt());
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final g = gebaeuderahmen(widget.store.waende(widget.geschossId));
    final raeume = [for (final r in widget.store.raeume(widget.geschossId)) if (r.umriss != null && r.art == RaumArt.raum) r];
    String m2(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
    return AlertDialog(
      title: const Text('Dachgeschoss'),
      content: SizedBox(
        width: 940,
        height: 600,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 480,
            child: ListView(children: [
              Wrap(spacing: 10, runSpacing: 10, children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<Dachform>(
                    initialValue: d.form,
                    decoration: const InputDecoration(labelText: 'Dachform', isDense: true),
                    items: [for (final f in Dachform.values) DropdownMenuItem(value: f, child: Text(f.label))],
                    onChanged: (v) => _setzen('form', v?.name),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<bool>(
                    initialValue: d.firstInX,
                    decoration: const InputDecoration(labelText: 'First', isDense: true),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('waagerecht im Plan')),
                      DropdownMenuItem(value: false, child: Text('senkrecht im Plan')),
                    ],
                    onChanged: (v) => _setzen('first_x', v),
                  ),
                ),
                if (d.form == Dachform.pult)
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<bool>(
                      initialValue: d.hochSeiteVorne,
                      decoration: const InputDecoration(labelText: 'Hohe Seite', isDense: true),
                      items: [
                        DropdownMenuItem(value: true, child: Text(d.firstInX ? 'oben im Plan' : 'links im Plan')),
                        DropdownMenuItem(value: false, child: Text(d.firstInX ? 'unten im Plan' : 'rechts im Plan')),
                      ],
                      onChanged: (v) => _setzen('hoch_vorne', v),
                    ),
                  ),
                _zahl('Dachneigung', 'neigung', d.neigung, einheit: '°', komma: true),
                _zahl('Kniestock', 'kniestock', d.kniestock, hilfe: 'Höhe der Schräge an der Außenwand über FFB'),
                _zahl('Kehlbalken UK', 'kehlbalken', d.kehlbalken, hilfe: '0 = offen bis First'),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Text('Kniestock abschnittsweise (${d.abschnitte.length})', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _setzen('abschnitte', [
                    ...[for (final a in d.abschnitte) a.toJson()],
                    KniestockAbschnitt(
                      von: d.abschnitte.isEmpty ? 0 : d.abschnitte.last.bis,
                      bis: (d.abschnitte.isEmpty ? 0 : d.abschnitte.last.bis) + 3000,
                      vorne: d.kniestock,
                      hinten: d.kniestock,
                    ).toJson(),
                  ]),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Abschnitt'),
                ),
              ]),
              const Text('Ab Giebel gemessen, längs zum First. Außerhalb der Abschnitte gilt der Kniestock oben. Vorne = obere bzw. linke Traufe im Plan.',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              for (final (i, ab) in d.abschnitte.indexed)
                Row(children: [
                  for (final (k, label, wert) in [('von', 'von', ab.von.round()), ('bis', 'bis', ab.bis.round()), ('vorne', 'Knie vorne', ab.vorne), ('hinten', 'Knie hinten', ab.hinten)])
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 6),
                      child: SizedBox(
                        width: 100,
                        child: SpeicherFeld(
                          key: ValueKey('ks-$i-$k-$wert'),
                          initialValue: '$wert',
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: label, suffixText: 'mm', isDense: true),
                          onFieldSubmitted: (v) {
                            final l = [for (final x in d.abschnitte) x.toJson()];
                            l[i] = {...l[i], k: int.tryParse(v) ?? wert};
                            _setzen('abschnitte', l);
                          },
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: () => _setzen('abschnitte', [for (final (j, x) in d.abschnitte.indexed) if (j != i) x.toJson()]),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ]),
              const SizedBox(height: 14),
              Text('Sparren', style: Theme.of(context).textTheme.titleSmall),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _zahl('Abstand (Achse)', 'sp_abstand', d.sparrenAbstand),
                _zahl('Breite', 'sp_breite', d.sparrenBreite),
                _zahl('Höhe', 'sp_hoehe', d.sparrenHoehe),
                _zahl('Versatz erster Sparren', 'sp_versatz', d.sparrenVersatz),
              ]),
              const SizedBox(height: 14),
              Text('Dämmung', style: Theme.of(context).textTheme.titleSmall),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _zahl('Zwischensparren', 'zw_dicke', d.zwischenDicke),
                _zahl('λ Zwischensparren', 'zw_lambda', d.zwischenLambda, einheit: 'W/(mK)', komma: true),
                _zahl('Untersparren', 'unter_dicke', d.unterDicke),
                _zahl('λ Untersparren', 'unter_lambda', d.unterLambda, einheit: 'W/(mK)', komma: true),
              ]),
              if (d.zwischenDicke > d.sparrenHoehe)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Zwischensparrendämmung dicker als der Sparren – Sparren aufdoppeln oder Untersparrendämmung ergänzen.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFB45309))),
                ),
              const SizedBox(height: 14),
              Row(children: [
                Text('Dachfenster (${d.dachfenster.length})', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: g == null
                      ? null
                      : () => _setzen('fenster', [
                            ...[for (final f in d.dachfenster) f.toJson()],
                            Dachfenster(x: (g.x0 + g.x1) / 2, y: g.y0 + (g.y1 - g.y0) / 4).toJson(),
                          ]),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Dachfenster'),
                ),
              ]),
              for (final (i, f) in d.dachfenster.indexed)
                Row(children: [
                  for (final (k, label, wert) in [('x', 'Mitte x', f.x.round()), ('y', 'Mitte y', f.y.round()), ('b', 'Breite', f.breite), ('h', 'Länge', f.hoehe)])
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 6),
                      child: SizedBox(
                        width: 100,
                        child: SpeicherFeld(
                          key: ValueKey('df-$i-$k-$wert'),
                          initialValue: '$wert',
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
                          decoration: InputDecoration(labelText: label, suffixText: 'mm', isDense: true),
                          onFieldSubmitted: (v) {
                            final l = [for (final x in d.dachfenster) x.toJson()];
                            l[i] = {...l[i], k: int.tryParse(v) ?? wert};
                            _setzen('fenster', l);
                          },
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: () => _setzen('fenster', [for (final (j, x) in d.dachfenster.indexed) if (j != i) x.toJson()]),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ]),
            ]),
          ),
          const VerticalDivider(width: 24),
          Expanded(
            child: ListView(children: [
              SizedBox(height: 230, child: CustomPaint(painter: _SchnittPainter(d, g))),
              const SizedBox(height: 8),
              if (d.aktiv) ...[
                Text('U-Wert Dach ≈ ${uDach(d).toStringAsFixed(2).replaceAll('.', ',')} W/(m²K)', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Text('Sparren und Gefach parallel gerechnet, belüftet. Für die Heizlast als Deckenaufbau übernehmen.',
                    style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                const SizedBox(height: 10),
                Text('Wohnfläche nach WoFlV', style: Theme.of(context).textTheme.titleSmall),
                if (g != null)
                  Table(
                    columnWidths: const {0: FlexColumnWidth(2)},
                    children: [
                      const TableRow(children: [
                        Text('Raum', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text('Grund', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text('< 1 m', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text('1–2 m', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text('Wohnfl.', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      ]),
                      for (final r in raeume)
                        () {
                          final w = wohnflaeche(r.umriss!, d, g);
                          return TableRow(children: [
                            Text(r.name, style: const TextStyle(fontSize: 12)),
                            Text(m2(w.grund), style: const TextStyle(fontSize: 12)),
                            Text(m2(w.unter1), style: const TextStyle(fontSize: 12)),
                            Text(m2(w.zwischen), style: const TextStyle(fontSize: 12)),
                            Text(m2(w.wohn), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ]);
                        }(),
                    ],
                  ),
              ],
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
    );
  }
}

/// Querschnitt quer zum First: Kniestock, Sparren, Dämmung, Kehlbalken, 1-m-/2-m-Linien.
class _SchnittPainter extends CustomPainter {
  _SchnittPainter(this.d, this.g);
  final DachEinstellung d;
  final Gebaeuderahmen? g;

  @override
  void paint(Canvas canvas, Size size) {
    final rahmen = g;
    if (!d.aktiv || rahmen == null) {
      final tp = TextPainter(text: const TextSpan(text: 'Dachform wählen – hier erscheint der Schnitt.', style: TextStyle(color: BsFarben.textLeise)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(10, size.height / 2));
      return;
    }
    final (a, b) = d.firstInX ? (rahmen.y0, rahmen.y1) : (rahmen.x0, rahmen.x1);
    final breite = b - a;
    var hMax = 0.0;
    for (var t = 0.0; t <= 1; t += 0.01) {
      final p = d.firstInX ? Punkt(rahmen.x0, a + breite * t) : Punkt(a + breite * t, rahmen.y0);
      final h = d.kniestock + math.max(0.0, _quer(p, rahmen)) * math.tan(d.neigung * math.pi / 180);
      hMax = math.max(hMax, h);
    }
    final k = math.min((size.width - 20) / breite, (size.height - 30) / math.max(2500, hMax + 300));
    Offset s(double x, double h) => Offset(10 + (x - a) * k, size.height - 15 - h * k);
    // Fußboden
    canvas.drawLine(s(a, 0), s(b, 0), Paint()..color = Colors.black54..strokeWidth = 2);
    // Dachlinie innen (mit Kehlbalken)
    final pfad = Path()..moveTo(s(a, 0).dx, s(a, 0).dy);
    final dach = Path();
    for (var t = 0.0; t <= 1.0001; t += 0.005) {
      final x = a + breite * t;
      final p = d.firstInX ? Punkt(rahmen.x0, x) : Punkt(x, rahmen.y0);
      final hRoh = d.kniestock + math.max(0.0, _quer(p, rahmen)) * math.tan(d.neigung * math.pi / 180);
      final h = d.kehlbalken > 0 ? math.min(hRoh, d.kehlbalken.toDouble()) : hRoh;
      pfad.lineTo(s(x, h).dx, s(x, h).dy);
      if (t == 0) {
        dach.moveTo(s(x, hRoh).dx, s(x, hRoh).dy);
      } else {
        dach.lineTo(s(x, hRoh).dx, s(x, hRoh).dy);
      }
    }
    pfad.lineTo(s(b, 0).dx, s(b, 0).dy);
    pfad.close();
    canvas.drawPath(pfad, Paint()..color = const Color(0xFFF8F9FA));
    // Sparren + Dämmung als Band über der Innenlinie
    canvas.drawPath(dach, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3, (d.sparrenHoehe + d.unterDicke) * k)
      ..color = const Color(0xFFFFD8A8));
    canvas.drawPath(dach, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF8D6E63));
    canvas.drawPath(pfad, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black54);
    if (d.kehlbalken > 0) {
      canvas.drawLine(s(a, d.kehlbalken.toDouble()), s(b, d.kehlbalken.toDouble()), Paint()
        ..color = const Color(0xFF8D6E63)
        ..strokeWidth = 2);
    }
    for (final (h, farbe, text) in [(1000.0, const Color(0xFFE8590C), '1 m'), (2000.0, const Color(0xFF2F9E44), '2 m')]) {
      canvas.drawLine(s(a, h), s(b, h), Paint()
        ..color = farbe.withValues(alpha: 0.6)
        ..strokeWidth = 1);
      final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(fontSize: 10, color: farbe)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, s(b, h) + const Offset(-24, -14));
    }
    final tp = TextPainter(
        text: TextSpan(text: 'Kniestock ${d.kniestock} mm · ${d.neigung.toStringAsFixed(0)}°', style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, const Offset(10, 0));
  }

  double _quer(Punkt p, Gebaeuderahmen g) {
    final (a, b, v) = d.firstInX ? (g.y0, g.y1, p.y) : (g.x0, g.x1, p.x);
    return switch (d.form) {
      Dachform.sattel => math.min(v - a, b - v),
      Dachform.pult => d.hochSeiteVorne ? b - v : v - a,
      Dachform.keins => 0,
    };
  }

  @override
  bool shouldRepaint(_SchnittPainter old) => true;
}

/// Überlagerung im Grundriss: Sparren, First, Linien 1 m / 2 m, Dachfenster.
class DachPainter extends CustomPainter {
  DachPainter({required this.d, required this.g, required this.massstab, required this.verschiebung});
  final DachEinstellung d;
  final Gebaeuderahmen g;
  final double massstab;
  final Offset verschiebung;

  Offset _s(double x, double y) => Offset(x, y) * massstab + verschiebung;

  @override
  void paint(Canvas canvas, Size size) {
    if (!d.aktiv) return;
    Offset q(double laengs, double quer) => d.firstInX ? _s(laengs, quer) : _s(quer, laengs);
    final (l0, l1) = d.firstInX ? (g.x0, g.x1) : (g.y0, g.y1);
    final (q0, q1) = d.firstInX ? (g.y0, g.y1) : (g.x0, g.x1);
    final sparren = Paint()
      ..color = const Color(0x558D6E63)
      ..strokeWidth = math.max(1, d.sparrenBreite * massstab);
    for (final v in sparrenLagen(d, g)) {
      canvas.drawLine(q(v, q0), q(v, q1), sparren);
    }
    final first = firstLage(d, g);
    if (first != null) {
      canvas.drawLine(q(l0, first), q(l1, first), Paint()
        ..color = const Color(0xFF8D6E63)
        ..strokeWidth = 1.5);
    }
    for (final (h, farbe) in [(1000.0, const Color(0xFFE8590C)), (2000.0, const Color(0xFF2F9E44))]) {
      for (final (la, lb, v) in hoehenLinienAbschnitte(d, g, h)) {
        final p = Paint()
          ..color = farbe
          ..strokeWidth = 1.2;
        // gestrichelt
        final a = q(la, v), b = q(lb, v);
        final len = (b - a).distance;
        if (len < 1) continue;
        final r = (b - a) / len;
        for (var t = 0.0; t < len; t += 12) {
          canvas.drawLine(a + r * t, a + r * math.min(len, t + 6), p);
        }
        final tp = TextPainter(text: TextSpan(text: '${(h / 1000).toStringAsFixed(0)} m', style: TextStyle(fontSize: 10, color: farbe, backgroundColor: Colors.white70)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, a + const Offset(4, -14));
      }
    }
    for (final f in d.dachfenster) {
      final (bx, by) = d.firstInX ? (f.breite.toDouble(), f.hoehe * math.cos(d.neigung * math.pi / 180)) : (f.hoehe * math.cos(d.neigung * math.pi / 180), f.breite.toDouble());
      final r = Rect.fromCenter(center: _s(f.x, f.y), width: bx * massstab, height: by * massstab);
      canvas.drawRect(r, Paint()..color = const Color(0x332F80ED));
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF1C7ED6));
      canvas.drawLine(r.topLeft, r.bottomRight, Paint()..color = const Color(0x881C7ED6));
    }
  }

  @override
  bool shouldRepaint(DachPainter old) => true;
}
