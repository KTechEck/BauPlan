import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../widgets.dart';

/// Ein Raum, wie er im Grundriss erscheint (lichter Umriss in Weltkoordinaten).
class RaumBild {
  const RaumBild({
    required this.umriss,
    required this.beschriftung,
    required this.innenpunkt,
    this.unterzeile,
    this.zugeordnet = true,
    this.ausgewaehlt = false,
    this.warnung = false,
    this.bodenplatte = false,
  });

  final List<Offset> umriss;
  final String beschriftung;
  final String? unterzeile;
  final Offset innenpunkt;
  final bool zugeordnet; // false = erkannte Fläche ohne Raum
  final bool ausgewaehlt;
  final bool warnung; // Wandzug offen oder mehrere Räume in einer Fläche
  final bool bodenplatte; // Balkon, Terrasse … ohne Wände: gestrichelter Rand
}

/// Eine Schicht für die Darstellung: Dicke in mm und Farbe.
typedef SchichtBild = (int dicke, Color farbe);

/// Winkelmaß: Scheitel (Welt), Startwinkel, Überstreichung, Text, gewählt.
typedef WinkelBild = (Offset scheitel, double start, double sweep, String text, bool gewaehlt);

/// Zeichnet Raster, Räume, Wände (mit Schichten), Maße und die Vorschau der
/// gerade gezeichneten Wand. Weltkoordinaten in mm,
/// Bildschirm = welt * massstab + verschiebung.
class FloorplanPainter extends CustomPainter {
  FloorplanPainter({
    required this.waende,
    required this.raeume,
    this.umrisse = const {},
    required this.schichten,
    required this.massstab,
    required this.verschiebung,
    required this.auswahl,
    this.rahmen,
    required this.kettenStart,
    required this.maus,
    required this.vorschauDicke,
    this.flanken = const {},
    this.raumStuecke = const {},
    this.vorschauEnde,
    this.vorschauFlanken,
    this.vorschauWinkel,
    this.massVoreinstellung = MassAnzeige.innenAussen,
    this.fangText,
    this.bemassungen = const [],
    this.winkel = const [],
    this.weissHintergrund = false,
    this.vorlage,
    this.vorlageLinien,
    this.vorschauRechteck,
    this.oeffnungen = const [],
    this.oeffnungAuswahl,
    this.oeffnungVorschau,
    this.massAuswahl,
    this.massVorschau,
    this.bezugPunkt,
  });

  final List<Wand> waende;
  final List<RaumBild> raeume;
  final Map<String, List<Offset>> umrisse; // verschnittener Wandumriss je Wand
  final Map<String, List<SchichtBild>> schichten; // je Wandtyp
  final double massstab;
  final Offset verschiebung;
  final Set<String> auswahl;
  final Rect? rahmen; // Auswahlrahmen in Weltkoordinaten
  final Offset? kettenStart;
  final Offset? maus;
  final int vorschauDicke;
  final Map<String, (double, double)> flanken; // Seitenlängen je Wand

  /// Lichte Messstrecken je Raum an Wänden, die an mehrere Räume grenzen oder
  /// nur teilweise an einen Raum: Wand-ID → (von, bis entlang der Achse, Seite ±1, Raumname).
  final Map<String, List<(double, double, double, String)>> raumStuecke;
  final Offset? vorschauEnde; // Ende der Vorschauwand (sonst Maus)
  final (double, double)? vorschauFlanken;
  final String? vorschauWinkel;
  final MassAnzeige massVoreinstellung;
  final String? fangText; // Fangart am Cursor, z. B. „Mitte“
  final List<Bemassung> bemassungen;
  final List<WinkelBild> winkel;
  final bool weissHintergrund; // für Druck/PDF: weiß, ohne Raster
  final (ui.Image, Rect, double)? vorlage; // Bild, Lage in Welt, Deckkraft
  /// DXF-Vorlage als Linien (Welt, mm) mit Texten und Deckkraft.
  final (List<List<Offset>>, List<(Offset, String, double)>, double)? vorlageLinien;
  final Rect? vorschauRechteck; // Achsrechteck beim Rechteckraum
  final List<Oeffnung> oeffnungen;
  final String? oeffnungAuswahl;
  final (String wandId, int abstand, int breite, OeffnungsArt art)? oeffnungVorschau;
  final String? massAuswahl; // gewählte Bemaßung
  final (Offset, Offset, double)? massVorschau; // Bemaßung im Entstehen: a, b, Abstand
  final Offset? bezugPunkt; // Bezugsende bei der Abstandseingabe

  Offset _s(Offset welt) => welt * massstab + verschiebung;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = weissHintergrund ? Colors.white : BsFarben.zeichenflaeche);
    if (!weissHintergrund) _raster(canvas, size);

    _vorlageZeichnen(canvas);
    for (final r in raeume) {
      _raumFlaeche(canvas, r);
    }
    for (final w in waende) {
      _wand(canvas, w, auswahl.contains(w.id));
      if (w.gesperrt) _schloss(canvas, _s(Offset((w.x1 + w.x2) / 2, (w.y1 + w.y2) / 2)));
    }
    final wandNach = {for (final w in waende) w.id: w};
    for (final o in oeffnungen) {
      final w = wandNach[o.wandId];
      if (w != null) _oeffnung(canvas, w, o.abstand, o.breite, o.art, o.bandRechts, o.aufgehenLinks, o.id == oeffnungAuswahl);
    }
    final ov = oeffnungVorschau;
    if (ov != null && wandNach[ov.$1] != null) {
      _oeffnung(canvas, wandNach[ov.$1]!, ov.$2, ov.$3, ov.$4, false, false, false, vorschau: true);
    }
    for (final w in waende) {
      final st = raumStuecke[w.id];
      if (st != null && st.isNotEmpty && (w.massanzeige ?? massVoreinstellung) != MassAnzeige.keine) {
        _raumMasse(canvas, w, st, flanken[w.id], auswahl.length == 1 && auswahl.contains(w.id));
        continue;
      }
      _mass(canvas, Offset(w.x1.toDouble(), w.y1.toDouble()), Offset(w.x2.toDouble(), w.y2.toDouble()),
          w.dicke,
          hervorheben: auswahl.length == 1 && auswahl.contains(w.id),
          flanken: flanken[w.id],
          anzeige: w.massanzeige ?? massVoreinstellung);
    }
    for (final r in raeume) {
      _raumText(canvas, r);
    }

    for (final b in bemassungen) {
      _bemassung(canvas, Offset(b.x1.toDouble(), b.y1.toDouble()), Offset(b.x2.toDouble(), b.y2.toDouble()),
          b.abstand.toDouble(), b.id == massAuswahl);
    }
    final mv = massVorschau;
    if (mv != null) _bemassung(canvas, mv.$1, mv.$2, mv.$3, true);
    for (final w in winkel) {
      _winkel(canvas, w);
    }

    final rr = rahmen;
    if (rr != null) {
      final r = Rect.fromPoints(_s(rr.topLeft), _s(rr.bottomRight));
      canvas.drawRect(r, Paint()..color = BsFarben.akzent.withValues(alpha: 0.08));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = BsFarben.akzentDunkel,
      );
    }

    final start = kettenStart;
    final m = maus;
    final vr = vorschauRechteck;
    if (vr != null) {
      final p = Paint()
        ..color = BsFarben.akzent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, vorschauDicke * massstab)
        ..strokeJoin = StrokeJoin.miter;
      canvas.drawRect(Rect.fromPoints(_s(vr.topLeft), _s(vr.bottomRight)), p);
      _mass(canvas, vr.topLeft, vr.topRight, vorschauDicke, hervorheben: true);
      _mass(canvas, vr.topRight, vr.bottomRight, vorschauDicke, hervorheben: true);
    }
    final bp = bezugPunkt;
    if (bp != null) {
      final c = _s(bp);
      canvas.drawCircle(c, 7, Paint()..color = BsFarben.akzent.withValues(alpha: 0.35));
      canvas.drawCircle(c, 7, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = BsFarben.akzentDunkel);
    }
    final ende = vorschauEnde ?? m;
    if (start != null && ende != null && start != ende) {
      final p = Paint()
        ..color = BsFarben.akzent.withValues(alpha: 0.55)
        ..strokeWidth = math.max(2.0, vorschauDicke * massstab)
        ..strokeCap = StrokeCap.square;
      canvas.drawLine(_s(start), _s(ende), p);
      _mass(canvas, start, ende, vorschauDicke,
          hervorheben: true, flanken: vorschauFlanken, zusatz: vorschauWinkel,
          anzeige: massVoreinstellung == MassAnzeige.keine ? MassAnzeige.innenAussen : massVoreinstellung);
    }
    if (m != null) {
      final c = _s(m);
      final kreuz = Paint()
        ..color = BsFarben.akzentDunkel
        ..strokeWidth = 1.2;
      canvas.drawLine(c.translate(-8, 0), c.translate(8, 0), kreuz);
      canvas.drawLine(c.translate(0, -8), c.translate(0, 8), kreuz);
      final ft = fangText;
      if (ft != null) {
        canvas.drawCircle(c, 5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = BsFarben.akzent);
        final tp = TextPainter(
          text: TextSpan(
            text: ft,
            style: const TextStyle(fontSize: 11, color: Colors.white, backgroundColor: BsFarben.akzentDunkel),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c + const Offset(12, 10));
      }
    }
  }

  void _raster(Canvas canvas, Size size) {
    // Rasterweite so wählen, dass Linien mindestens ~12 px auseinander liegen.
    const stufen = [50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0];
    final fein = stufen.firstWhere((s) => s * massstab >= 12, orElse: () => 10000.0);
    final grob = fein * 10 > 10000 ? fein * 5 : fein * 10;

    final links = (-verschiebung.dx) / massstab;
    final oben = (-verschiebung.dy) / massstab;
    final rechts = links + size.width / massstab;
    final unten = oben + size.height / massstab;

    final pFein = Paint()
      ..color = BsFarben.raster
      ..strokeWidth = 1;
    final pGrob = Paint()
      ..color = const Color(0xFFCFD3CB)
      ..strokeWidth = 1;

    final jeGrob = (grob / fein).round();
    for (var i = (links / fein).floor(); i * fein <= rechts; i++) {
      final sx = i * fein * massstab + verschiebung.dx;
      final istGrob = i % jeGrob == 0;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), istGrob ? pGrob : pFein);
    }
    for (var i = (oben / fein).floor(); i * fein <= unten; i++) {
      final sy = i * fein * massstab + verschiebung.dy;
      final istGrob = i % jeGrob == 0;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), istGrob ? pGrob : pFein);
    }
    // Nullpunkt
    final o = _s(Offset.zero);
    final pNull = Paint()
      ..color = BsFarben.akzent
      ..strokeWidth = 1.5;
    canvas.drawLine(o.translate(-10, 0), o.translate(10, 0), pNull);
    canvas.drawLine(o.translate(0, -10), o.translate(0, 10), pNull);
  }

  void _raumFlaeche(Canvas canvas, RaumBild r) {
    if (r.umriss.length < 3) return;
    final path = Path()..addPolygon([for (final p in r.umriss) _s(p)], true);
    final farbe = r.ausgewaehlt
        ? BsFarben.akzent.withValues(alpha: 0.22)
        : r.zugeordnet
            ? BsFarben.akzentHell.withValues(alpha: 0.55)
            : const Color(0xFFE9ECE4).withValues(alpha: 0.7);
    canvas.drawPath(path, Paint()..color = farbe);
    if (r.bodenplatte) {
      final rand = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = BsFarben.wandBestand;
      final pts = [for (final p in r.umriss) _s(p)];
      for (var i = 0; i < pts.length; i++) {
        final a = pts[i], b = pts[(i + 1) % pts.length];
        final l = (b - a).distance;
        if (l < 1) continue;
        final u = (b - a) / l;
        for (var t = 0.0; t < l; t += 10) {
          canvas.drawLine(a + u * t, a + u * math.min(t + 6, l), rand);
        }
      }
    }
    if (r.ausgewaehlt || r.warnung) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r.ausgewaehlt ? 2 : 1.2
          ..color = r.warnung ? const Color(0xFFB91C1C) : BsFarben.akzentDunkel,
      );
    }
  }

  void _raumText(Canvas canvas, RaumBild r) {
    final tp = TextPainter(
      textAlign: TextAlign.center,
      text: TextSpan(children: [
        TextSpan(
          text: r.beschriftung,
          style: TextStyle(
            fontSize: 13,
            fontWeight: r.zugeordnet ? FontWeight.w600 : FontWeight.w400,
            fontStyle: r.zugeordnet ? FontStyle.normal : FontStyle.italic,
            color: r.warnung
                ? const Color(0xFFB91C1C)
                : (r.zugeordnet ? BsFarben.leiste : BsFarben.textLeise),
          ),
        ),
        if (r.unterzeile != null)
          TextSpan(
            text: '\n${r.unterzeile}',
            style: const TextStyle(fontSize: 11, color: BsFarben.textLeise),
          ),
      ]),
      textDirection: TextDirection.ltr,
    )..layout();
    final c = _s(r.innenpunkt);
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _wand(Canvas canvas, Wand w, bool ausgewaehlt) {
    final umriss = umrisse[w.id];
    if (umriss == null || umriss.length != 4) {
      _wandAlsLinie(canvas, w, ausgewaehlt);
      return;
    }
    final farbe = switch (w.zustand) {
      WandZustand.bestand => BsFarben.wandBestand,
      WandZustand.neu => BsFarben.wandNeu,
      WandZustand.abbruch => BsFarben.wandAbbruch,
    };
    final p = [for (final e in umriss) _s(e)];
    final path = Path()..addPolygon(p, true);
    if (ausgewaehlt) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.miter
          ..color = BsFarben.akzent,
      );
    }
    final breite = w.dicke * massstab;
    final lagen = w.wandtypId == null ? null : schichten[w.wandtypId];
    final summe = lagen?.fold<int>(0, (s, e) => s + e.$1) ?? 0;
    if (lagen == null || lagen.isEmpty || breite < 7 || summe <= 0) {
      canvas.drawPath(path, Paint()..color = w.zustand == WandZustand.abbruch ? farbe.withValues(alpha: 0.6) : farbe);
    } else {
      // Schichten als Streifen: Ecken linear zwischen linker und rechter Flanke
      // (p[0]/p[1] links, p[3]/p[2] rechts) – so laufen sie in die Gehrung.
      var ab = 0;
      for (final (dicke, f) in lagen) {
        final t0 = ab / summe, t1 = (ab + dicke) / summe;
        final streifen = Path()
          ..addPolygon([
            Offset.lerp(p[0], p[3], t0)!,
            Offset.lerp(p[1], p[2], t0)!,
            Offset.lerp(p[1], p[2], t1)!,
            Offset.lerp(p[0], p[3], t1)!,
          ], true);
        canvas.drawPath(streifen, Paint()..color = w.zustand == WandZustand.abbruch ? f.withValues(alpha: 0.5) : f);
        ab += dicke;
      }
      // Seitenlinien in Zustandsfarbe, damit Bestand/Neu/Abbruch erkennbar bleibt.
      final kante = Paint()
        ..color = farbe
        ..strokeWidth = w.zustand == WandZustand.bestand ? 1.2 : 2.2;
      canvas.drawLine(p[0], p[1], kante);
      canvas.drawLine(p[3], p[2], kante);
    }
  }

  /// Ersatzdarstellung ohne berechneten Umriss (z. B. Vorschau beim Verschieben).
  void _wandAlsLinie(Canvas canvas, Wand w, bool ausgewaehlt) {
    final a = _s(Offset(w.x1.toDouble(), w.y1.toDouble()));
    final b = _s(Offset(w.x2.toDouble(), w.y2.toDouble()));
    final farbe = switch (w.zustand) {
      WandZustand.bestand => BsFarben.wandBestand,
      WandZustand.neu => BsFarben.wandNeu,
      WandZustand.abbruch => BsFarben.wandAbbruch,
    };
    final breite = math.max(2.0, w.dicke * massstab);
    if (ausgewaehlt) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = BsFarben.akzent
          ..strokeWidth = breite + 6
          ..strokeCap = StrokeCap.square,
      );
    }
    final p = Paint()
      ..color = w.zustand == WandZustand.abbruch ? farbe.withValues(alpha: 0.6) : farbe
      ..strokeWidth = breite
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(a, b, p);

    // Schichten des Wandtyps, sobald die Wand breit genug erscheint.
    final lagen = w.wandtypId == null ? null : schichten[w.wandtypId];
    if (lagen == null || lagen.isEmpty || breite < 7 || (b - a).distance < 1) return;
    final summe = lagen.fold<int>(0, (s, e) => s + e.$1);
    if (summe <= 0) return;
    final u = (b - a) / (b - a).distance;
    final links = Offset(u.dy, -u.dx); // Seite 1 = links der Zeichenrichtung (Bildschirm)
    final skala = breite / summe; // Pixel je mm Schichtdicke
    var abLinks = 0.0;
    for (final (dicke, f) in lagen) {
      final mitte = breite / 2 - (abLinks + dicke * skala / 2);
      canvas.drawLine(
        a + links * mitte,
        b + links * mitte,
        Paint()
          ..color = w.zustand == WandZustand.abbruch ? f.withValues(alpha: 0.5) : f
          ..strokeWidth = dicke * skala
          ..strokeCap = StrokeCap.butt,
      );
      abLinks += dicke * skala;
    }
    // Kanten in Zustandsfarbe, damit Bestand/Neu/Abbruch erkennbar bleibt.
    final kante = Paint()
      ..color = farbe
      ..strokeWidth = w.zustand == WandZustand.bestand ? 1.2 : 2.2;
    for (final s in [-1.0, 1.0]) {
      final o = links * (s * breite / 2);
      canvas.drawLine(a + o, b + o, kante);
    }
  }

  /// Planvorlage (Hintergrundbild) mit eingestellter Deckkraft.
  void _vorlageZeichnen(Canvas canvas) {
    final vl = vorlageLinien;
    if (vl != null) {
      final (linien, texte, deckkraft) = vl;
      final stift = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF5C6B7A).withValues(alpha: deckkraft);
      for (final l in linien) {
        if (l.length < 2) continue;
        canvas.drawPath(Path()..addPolygon([for (final q in l) _s(q)], false), stift);
      }
      for (final (ort, text, hoehe) in texte) {
        final px = hoehe * massstab;
        if (px < 6) continue;
        final tp = TextPainter(
          text: TextSpan(text: text, style: TextStyle(fontSize: math.min(px, 40), color: const Color(0xFF5C6B7A).withValues(alpha: deckkraft))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, _s(ort) - Offset(0, tp.height));
      }
    }
    final v = vorlage;
    if (v == null) return;
    final (bild, welt, deckkraft) = v;
    final ziel = Rect.fromPoints(_s(welt.topLeft), _s(welt.bottomRight));
    canvas.drawImageRect(
      bild,
      Rect.fromLTWH(0, 0, bild.width.toDouble(), bild.height.toDouble()),
      ziel,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: deckkraft),
    );
  }

  /// Öffnung in einer Wand: Lücke freistellen, Laibungen, Symbol.
  void _oeffnung(Canvas canvas, Wand w, int abstand, int breite, OeffnungsArt art, bool bandRechts,
      bool aufgehenLinks, bool gewaehlt, {bool vorschau = false}) {
    final l = w.laenge;
    if (l < 1) return;
    final a = Offset(w.x1.toDouble(), w.y1.toDouble());
    final u = (Offset(w.x2.toDouble(), w.y2.toDouble()) - a) / l;
    final nl = Offset(u.dy, -u.dx); // links der Zeichenrichtung (Bildschirm)
    final h = w.dicke / 2;
    final t0 = abstand.toDouble().clamp(0.0, l), t1 = (abstand + breite).toDouble().clamp(0.0, l);
    Offset pt(double t, double quer) => _s(a + u * t + nl * quer);
    final rand = 1 / massstab; // 1 px über die Wandkante, damit nichts stehen bleibt
    final luecke = Path()
      ..addPolygon([pt(t0, h + rand), pt(t1, h + rand), pt(t1, -h - rand), pt(t0, -h - rand)], true);
    canvas.drawPath(luecke, Paint()..color = BsFarben.zeichenflaeche);
    final farbe = gewaehlt || vorschau ? BsFarben.akzentDunkel : BsFarben.wandBestand;
    final linie = Paint()
      ..color = vorschau ? BsFarben.akzent : farbe
      ..strokeWidth = gewaehlt ? 2 : 1.2
      ..style = PaintingStyle.stroke;
    // Laibungen
    canvas.drawLine(pt(t0, h), pt(t0, -h), linie);
    canvas.drawLine(pt(t1, h), pt(t1, -h), linie);
    switch (art) {
      case OeffnungsArt.tuer || OeffnungsArt.balkontuer:
        if (art == OeffnungsArt.balkontuer) {
          // Verglasung wie beim Fenster, dazu der Flügelaufschlag
          final glas = Paint()
            ..color = vorschau ? BsFarben.akzent : farbe
            ..strokeWidth = 1;
          for (final q in [h / 4, -h / 4]) {
            canvas.drawLine(pt(t0, q), pt(t1, q), glas);
          }
        }
        final seite = aufgehenLinks ? 1.0 : -1.0;
        final band = bandRechts ? t1 : t0;
        final frei = bandRechts ? t0 : t1;
        final drehpunkt = a + u * band + nl * (seite * h);
        final blattEnde = drehpunkt + nl * (seite * breite.toDouble());
        canvas.drawLine(_s(drehpunkt), _s(blattEnde), linie..strokeWidth = gewaehlt ? 2.4 : 1.8);
        final r = breite * massstab;
        final start = math.atan2((blattEnde - drehpunkt).dy, (blattEnde - drehpunkt).dx);
        final zum = a + u * frei + nl * (seite * h) - drehpunkt;
        var sweep = math.atan2(zum.dy, zum.dx) - start;
        while (sweep > math.pi) {
          sweep -= 2 * math.pi;
        }
        while (sweep < -math.pi) {
          sweep += 2 * math.pi;
        }
        canvas.drawArc(Rect.fromCircle(center: _s(drehpunkt), radius: r), start, sweep, false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.9
              ..color = farbe.withValues(alpha: 0.7));
      case OeffnungsArt.fenster:
        final glas = Paint()
          ..color = vorschau ? BsFarben.akzent : farbe
          ..strokeWidth = 1;
        for (final q in [h, -h, h / 4, -h / 4]) {
          canvas.drawLine(pt(t0, q), pt(t1, q), glas);
        }
      case OeffnungsArt.durchbruch:
        final d = Paint()
          ..color = farbe.withValues(alpha: 0.6)
          ..strokeWidth = 0.9;
        canvas.drawLine(pt(t0, h), pt(t1, -h), d);
        canvas.drawLine(pt(t0, -h), pt(t1, h), d);
    }
    if (gewaehlt || vorschau) {
      final tp = TextPainter(
        text: TextSpan(
          text: mmText(breite),
          style: TextStyle(
            fontSize: 11,
            color: BsFarben.akzentDunkel,
            fontWeight: FontWeight.w600,
            backgroundColor: BsFarben.zeichenflaeche.withValues(alpha: 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final c = pt((t0 + t1) / 2, 0);
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// Winkelmaß: Bogen am Scheitel mit Gradzahl.
  void _winkel(Canvas canvas, WinkelBild w) {
    final (v, start, sweep, text, gewaehlt) = w;
    final c = _s(v);
    const r = 26.0;
    final farbe = gewaehlt ? BsFarben.akzentDunkel : const Color(0xFF3B5BA9);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = gewaehlt ? 2 : 1.2
        ..color = farbe,
    );
    final mitte = start + sweep / 2;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10,
          color: farbe,
          fontWeight: gewaehlt ? FontWeight.w600 : FontWeight.w500,
          backgroundColor: BsFarben.zeichenflaeche.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final p = c + Offset(math.cos(mitte), math.sin(mitte)) * (r + 11);
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  /// Kleines Schloss an gesperrten Wänden.
  void _schloss(Canvas canvas, Offset c) {
    final farbe = Paint()..color = BsFarben.akzentDunkel;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + const Offset(0, 2), width: 10, height: 8),
        const Radius.circular(1.5)), farbe);
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(0, -2), width: 7, height: 8),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = BsFarben.akzentDunkel,
    );
  }

  /// Bemaßung: Hilfslinien, Maßlinie mit Schrägstrichen, Maßzahl.
  void _bemassung(Canvas canvas, Offset a, Offset b, double abstand, bool hervorheben) {
    final l = (b - a).distance;
    if (l < 1) return;
    final u = (b - a) / l;
    final nl = Offset(u.dy, -u.dx);
    final farbe = hervorheben ? BsFarben.akzentDunkel : const Color(0xFF3B5BA9);
    final linie = Paint()
      ..color = farbe
      ..strokeWidth = hervorheben ? 1.6 : 1;
    final sa = _s(a), sb = _s(b);
    final da = _s(a + nl * abstand), db = _s(b + nl * abstand);
    final seite = abstand >= 0 ? 1.0 : -1.0;
    final su = (sb - sa) / (sb - sa).distance;
    final snl = Offset(su.dy, -su.dx) * seite;
    // Hilfslinien: kleiner Abstand zum Messpunkt, 4 px über die Maßlinie hinaus
    if ((da - sa).distance > 6) {
      canvas.drawLine(sa + snl * 3, da + snl * 4, linie);
      canvas.drawLine(sb + snl * 3, db + snl * 4, linie);
    }
    canvas.drawLine(da - su * 4, db + su * 4, linie);
    // Schrägstriche (Architekturmaß)
    final schraeg = (su + snl) / math.sqrt2 * 5;
    final strich = Paint()
      ..color = farbe
      ..strokeWidth = 2;
    for (final p in [da, db]) {
      canvas.drawLine(p - schraeg, p + schraeg, strich);
    }
    final tp = TextPainter(
      text: TextSpan(
        text: mmText(l),
        style: TextStyle(
          fontSize: 11,
          color: farbe,
          fontWeight: hervorheben ? FontWeight.w600 : FontWeight.w500,
          backgroundColor: BsFarben.zeichenflaeche.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var winkel = math.atan2(su.dy, su.dx);
    if (winkel > math.pi / 2 || winkel < -math.pi / 2) winkel += math.pi;
    final c = (da + db) / 2 + snl * (tp.height / 2 + 2);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(winkel);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  /// Maße einer Wand, an der mehrere Räume liegen: je Raum eine eigene
  /// Messlinie auf seiner Seite, nur über die lichte Strecke (Oberfläche zu
  /// Oberfläche), beschriftet mit Maß und Raum. Seiten ohne Raumstück zeigen
  /// ihre ganze Länge.
  void _raumMasse(Canvas canvas, Wand w, List<(double, double, double, String)> st, (double, double)? f, bool hervorheben) {
    final a = Offset(w.x1.toDouble(), w.y1.toDouble()), b = Offset(w.x2.toDouble(), w.y2.toDouble());
    final l = (b - a).distance;
    if (l * massstab < 40) return;
    final u = (b - a) / l;
    final nl = Offset(u.dy, -u.dx);
    final farbe = hervorheben ? BsFarben.akzentDunkel : const Color(0xFF5C6B7A);
    final stift = Paint()
      ..color = farbe
      ..strokeWidth = hervorheben ? 1.6 : 1;
    var winkel = math.atan2(u.dy, u.dx);
    if (winkel > math.pi / 2 || winkel < -math.pi / 2) winkel += math.pi;
    void beschriften(String t, Offset p) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontSize: 11, color: farbe, fontWeight: hervorheben ? FontWeight.w600 : FontWeight.w400, backgroundColor: BsFarben.zeichenflaeche.withValues(alpha: 0.85))),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(winkel);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    for (final seite in [1.0, -1.0]) {
      final hier = [for (final x in st) if (x.$3 == seite) x];
      final versatz = w.dicke / 2 + 14 / massstab;
      if (hier.isEmpty) {
        final len = f == null ? l : (seite > 0 ? f.$1 : f.$2);
        beschriften(mmText(len), _s((a + b) / 2 + nl * (seite * (w.dicke / 2 + 16 / massstab))));
        continue;
      }
      for (final (t1, t2, _, name) in hier) {
        if ((t2 - t1) * massstab < 30) continue;
        final p1 = _s(a + u * t1 + nl * (seite * versatz)), p2 = _s(a + u * t2 + nl * (seite * versatz));
        canvas.drawLine(p1, p2, stift);
        final q = Offset(-(p2 - p1).dy, (p2 - p1).dx) / math.max(1, (p2 - p1).distance) * 4;
        canvas.drawLine(p1 - q, p1 + q, stift);
        canvas.drawLine(p2 - q, p2 + q, stift);
        beschriften('${mmText(t2 - t1)} $name', _s(a + u * ((t1 + t2) / 2) + nl * (seite * (versatz + 12 / massstab))));
      }
    }
  }

  /// Maß an einer Wand. Mit [flanken] stehen die Längen beider Wandseiten
  /// jeweils auf ihrer Seite (innen/außen), sonst die Achslänge.
  void _mass(Canvas canvas, Offset a, Offset b, int dicke,
      {bool hervorheben = false, (double, double)? flanken, String? zusatz, MassAnzeige anzeige = MassAnzeige.innenAussen}) {
    final laenge = (b - a).distance;
    if (laenge * massstab < 40) return;
    final sa = _s(a), sb = _s(b);
    final mitte = (sa + sb) / 2;
    final u = (sb - sa) / (sb - sa).distance;
    final links = Offset(u.dy, -u.dx);
    var winkel = math.atan2(u.dy, u.dx);
    if (winkel > math.pi / 2 || winkel < -math.pi / 2) winkel += math.pi;

    void text(String t, double seite) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
            fontSize: 11,
            color: hervorheben ? BsFarben.akzentDunkel : BsFarben.textLeise,
            fontWeight: hervorheben ? FontWeight.w600 : FontWeight.w400,
            backgroundColor: BsFarben.zeichenflaeche.withValues(alpha: 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final abstand = dicke * massstab / 2 + 6 + tp.height / 2;
      final c = mitte + links * (seite * abstand);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(winkel);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    final f = flanken;
    final gleich = f == null || (f.$1 - f.$2).abs() < 1;
    final z = zusatz == null ? '' : '  $zusatz';
    if (anzeige == MassAnzeige.keine) {
      if (zusatz != null) text(zusatz, 1);
      return;
    }
    if (gleich) {
      // Beide Seiten gleich lang (freie Wand oder gerade durchlaufend)
      final innenWert = f?.$1 ?? laenge;
      final wert = anzeige == MassAnzeige.achse ? laenge : innenWert;
      text('${mmText(wert)}$z', 1);
      if (anzeige == MassAnzeige.achseInnen && (innenWert - laenge).abs() >= 1) {
        text('${mmText(laenge)} Achse', -1);
      }
      return;
    }
    final linksInnen = f.$1 < f.$2;
    final innenSeite = linksInnen ? 1.0 : -1.0;
    final innen = linksInnen ? f.$1 : f.$2;
    final aussen = linksInnen ? f.$2 : f.$1;
    switch (anzeige) {
      case MassAnzeige.innenAussen:
        text('${mmText(innen)} innen', innenSeite);
        text('${mmText(aussen)} außen$z', -innenSeite);
      case MassAnzeige.achse:
        text('${mmText(laenge)} Achse$z', -innenSeite);
      case MassAnzeige.innen:
        text('${mmText(innen)} innen$z', innenSeite);
      case MassAnzeige.achseInnen:
        text('${mmText(innen)} innen', innenSeite);
        text('${mmText(laenge)} Achse$z', -innenSeite);
      case MassAnzeige.keine:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant FloorplanPainter old) =>
      old.waende != waende ||
      old.raeume != raeume ||
      old.umrisse != umrisse ||
      old.schichten != schichten ||
      old.massstab != massstab ||
      old.verschiebung != verschiebung ||
      !setEquals(old.auswahl, auswahl) ||
      old.rahmen != rahmen ||
      old.kettenStart != kettenStart ||
      old.maus != maus ||
      old.vorschauDicke != vorschauDicke ||
      old.flanken != flanken ||
      old.vorschauEnde != vorschauEnde ||
      old.vorschauFlanken != vorschauFlanken ||
      old.vorschauWinkel != vorschauWinkel ||
      old.massVoreinstellung != massVoreinstellung ||
      old.fangText != fangText ||
      old.bemassungen != bemassungen ||
      old.winkel != winkel ||
      old.vorlage != vorlage ||
      old.vorlageLinien != vorlageLinien ||
      old.vorschauRechteck != vorschauRechteck ||
      old.oeffnungen != oeffnungen ||
      old.oeffnungAuswahl != oeffnungAuswahl ||
      old.oeffnungVorschau != oeffnungVorschau ||
      old.massAuswahl != massAuswahl ||
      old.massVorschau != massVorschau ||
      old.bezugPunkt != bezugPunkt;
}

/// Abstand eines Punkts zu einer Strecke (für die Auswahl).
double abstandZuStrecke(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / l2;
  t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
  return (p - (a + ab * t)).distance;
}
