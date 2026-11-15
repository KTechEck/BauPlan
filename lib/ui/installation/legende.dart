import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/height.dart';
import '../../data/models.dart';
import '../symbole_plan.dart';

/// Eine Zeile der automatischen Legende.
typedef LegendenZeile = ({String kuerzel, String name, Color farbe, bool linie, int anzahl, double meter, List<String> hoehen});

/// Legende aus den Objekten im Plan: jedes verwendete Symbol einmal, mit
/// Anzahl, Leitungslänge und Montagehöhen. Sortiert nach Gewerk und Name.
List<LegendenZeile> legendeBauen(Iterable<Objekt> objekte, Map<String, Objekttyp> typen, Map<String, Gewerk> gewerke) {
  final je = <String, ({Objekttyp t, int n, double m, Set<String> h})>{};
  for (final o in objekte) {
    final t = typen[o.typId];
    if (t == null || t.geometrie == Geometrieart.flaeche) continue;
    final alt = je[t.id];
    final hoehe = o.z == null || o.zBezug == null ? null : '${(o.z! / 10).round()} cm ${o.zBezug!.kurz}';
    je[t.id] = (
      t: t,
      n: (alt?.n ?? 0) + 1,
      m: (alt?.m ?? 0) + (o.punkte.length >= 2 ? o.laenge / 1000 : 0),
      h: {...?alt?.h, if (hoehe != null) hoehe},
    );
  }
  final l = [
    for (final e in je.values)
      (
        kuerzel: e.t.kuerzel,
        name: e.t.name,
        farbe: Color(gewerke[e.t.gewerkId]?.farbe ?? 0xFF868E96),
        linie: e.t.geometrie == Geometrieart.linie,
        anzahl: e.n,
        meter: e.m,
        hoehen: (e.h.toList()..sort()).take(3).toList(),
      ),
  ];
  l.sort((a, b) => a.farbe.toARGB32() != b.farbe.toARGB32() ? a.farbe.toARGB32().compareTo(b.farbe.toARGB32()) : a.name.compareTo(b.name));
  return l;
}

/// Legende auf eine Zeichenfläche zeichnen (für Bildschirm und PDF-Export).
/// [ecke] ist die rechte untere Ecke. Liefert die belegte Fläche.
Rect legendeZeichnen(Canvas canvas, Offset ecke, List<LegendenZeile> zeilen, {double skala = 1, String titel = 'Legende'}) {
  if (zeilen.isEmpty) return Rect.zero;
  const zeile = 18.0, rand = 8.0;
  TextPainter tp(String t, double g, {bool fett = false, Color farbe = const Color(0xFF212529)}) =>
      TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: g * skala, color: farbe, fontWeight: fett ? FontWeight.w700 : FontWeight.w400)), textDirection: TextDirection.ltr)..layout();
  final texte = [
    for (final z in zeilen)
      (
        tp(z.name, 10),
        tp([
          z.linie ? '${z.meter.toStringAsFixed(1).replaceAll('.', ',')} m' : '${z.anzahl}×',
          if (z.hoehen.isNotEmpty) 'h ${z.hoehen.join(' / ')}',
        ].join(' · '), 9, farbe: const Color(0xFF6C757D)),
      ),
  ];
  final kopf = tp(titel, 11, fett: true);
  final sym = 26 * skala;
  final breite = rand * 2 * skala + sym + texte.map((t) => math.max(t.$1.width, t.$2.width)).fold(kopf.width, math.max) + 6 * skala;
  final hoehe = rand * 2 * skala + kopf.height + 4 * skala + zeilen.length * zeile * 1.45 * skala;
  final r = Rect.fromLTWH(ecke.dx - breite, ecke.dy - hoehe, breite, hoehe);
  canvas.drawRect(r, Paint()..color = const Color(0xF2FFFFFF));
  canvas.drawRect(r, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0xFF495057));
  kopf.paint(canvas, r.topLeft + Offset(rand * skala, rand * skala));
  var y = r.top + rand * skala + kopf.height + 4 * skala;
  for (final (i, z) in zeilen.indexed) {
    final h = zeile * 1.45 * skala;
    final c = Offset(r.left + rand * skala + sym / 2, y + h / 2);
    if (z.linie) {
      canvas.drawLine(c - Offset(sym / 2 - 2, 0), c + Offset(sym / 2 - 2, 0), Paint()
        ..color = z.farbe
        ..strokeWidth = 2.5 * skala);
    } else {
      geraetSymbol(canvas, c, 8 * skala, z.kuerzel, z.farbe);
    }
    final (a, b) = texte[i];
    a.paint(canvas, Offset(r.left + rand * skala + sym + 6 * skala, y + 1 * skala));
    b.paint(canvas, Offset(r.left + rand * skala + sym + 6 * skala, y + 1 * skala + a.height));
    y += h;
  }
  return r;
}

/// Legende als eigenes Widget (Overlay im Installationsplan).
class LegendenPainter extends CustomPainter {
  LegendenPainter(this.zeilen);
  final List<LegendenZeile> zeilen;
  @override
  void paint(Canvas canvas, Size size) => legendeZeichnen(canvas, Offset(size.width, size.height), zeilen);
  @override
  bool shouldRepaint(covariant LegendenPainter old) => old.zeilen != zeilen;
}
