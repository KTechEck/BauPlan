import 'dart:math' as math;

import 'raumerkennung.dart';

/// Einfacher DXF-Leser (ASCII-DXF, wie ihn AutoCAD, DraftSight, LibreCAD,
/// ArchiCAD usw. schreiben). Gelesen werden LINE, LWPOLYLINE, POLYLINE/VERTEX,
/// ARC, CIRCLE, TEXT, MTEXT und INSERT (Blöcke werden aufgelöst). Koordinaten
/// bleiben in Zeichnungseinheiten und mit y nach oben – die Umrechnung in
/// BauSpur-Weltkoordinaten (mm, y nach unten) macht [DxfZeichnung.zuWelt].

/// Linienzug auf einem Layer (Bögen und Kreise sind in Strecken zerlegt).
class DxfZug {
  DxfZug(this.layer, this.punkte, {this.geschlossen = false, this.bogen = false});
  final String layer;
  final List<Punkt> punkte;
  final bool geschlossen;
  final bool bogen; // aus ARC/CIRCLE – kommt nicht als Wand infrage
}

class DxfText {
  DxfText(this.layer, this.ort, this.text, this.hoehe);
  final String layer;
  final Punkt ort;
  final String text;
  final double hoehe;
}

class DxfZeichnung {
  DxfZeichnung({required this.zuege, required this.texte, required this.einheit});
  final List<DxfZug> zuege;
  final List<DxfText> texte;

  /// Wert von $INSUNITS (0 = ohne, 1 = Zoll, 2 = Fuß, 4 = mm, 5 = cm, 6 = m).
  final int einheit;

  /// Millimeter je Zeichnungseinheit laut Kopf; ohne Angabe Millimeter.
  double get mmProEinheit => switch (einheit) {
        1 => 25.4,
        2 => 304.8,
        5 => 10,
        6 => 1000,
        _ => 1,
      };

  Set<String> get layer => {for (final z in zuege) z.layer, for (final t in texte) t.layer};

  Map<String, int> get anzahlJeLayer {
    final m = <String, int>{};
    for (final z in zuege) {
      m[z.layer] = (m[z.layer] ?? 0) + 1;
    }
    return m;
  }

  /// Umgebendes Rechteck in Zeichnungseinheiten (minX, minY, maxX, maxY).
  (double, double, double, double)? get grenzen {
    double? a, b, c, d;
    for (final z in zuege) {
      for (final p in z.punkte) {
        a = a == null ? p.x : math.min(a, p.x);
        b = b == null ? p.y : math.min(b, p.y);
        c = c == null ? p.x : math.max(c, p.x);
        d = d == null ? p.y : math.max(d, p.y);
      }
    }
    return a == null ? null : (a, b!, c!, d!);
  }

  /// Zeichnungspunkt → Welt (mm, y nach unten) mit Ursprung und Maßstab.
  static Punkt zuWelt(Punkt p, {required double ursprungX, required double ursprungY, required double mmProEinheit}) =>
      Punkt(ursprungX + p.x * mmProEinheit, ursprungY - p.y * mmProEinheit);
}

/// Liest eine DXF-Datei (Text). Unbekannte Objekte werden übersprungen.
DxfZeichnung dxfLesen(String inhalt) {
  final zeilen = inhalt.split(RegExp(r'\r?\n'));
  final paare = <(int, String)>[];
  for (var i = 0; i + 1 < zeilen.length; i += 2) {
    final code = int.tryParse(zeilen[i].trim());
    if (code == null) {
      i--; // aus dem Tritt: eine Zeile weiter versuchen
      continue;
    }
    paare.add((code, zeilen[i + 1].trim()));
  }

  var einheit = 0;
  final bloecke = <String, List<List<(int, String)>>>{};
  final entities = <List<(int, String)>>[];

  // In Abschnitte zerlegen
  var i = 0;
  String? abschnitt;
  String? block;
  List<(int, String)>? aktuell;
  void abschliessen() {
    final a = aktuell;
    if (a == null) return;
    if (abschnitt == 'ENTITIES') {
      entities.add(a);
    } else if (abschnitt == 'BLOCKS' && block != null) {
      bloecke[block]!.add(a);
    }
    aktuell = null;
  }

  while (i < paare.length) {
    final (code, wert) = paare[i];
    if (code == 0) {
      abschliessen();
      if (wert == 'SECTION') {
        abschnitt = i + 1 < paare.length && paare[i + 1].$1 == 2 ? paare[i + 1].$2 : null;
        i += 2;
        continue;
      }
      if (wert == 'ENDSEC') {
        abschnitt = null;
        i++;
        continue;
      }
      if (abschnitt == 'BLOCKS' && wert == 'BLOCK') {
        // Name steht in Code 2
        var j = i + 1;
        String? name;
        while (j < paare.length && paare[j].$1 != 0) {
          if (paare[j].$1 == 2) name = paare[j].$2;
          j++;
        }
        block = name;
        if (name != null) bloecke[name] = [];
        i = j;
        continue;
      }
      if (abschnitt == 'BLOCKS' && wert == 'ENDBLK') {
        block = null;
        i++;
        while (i < paare.length && paare[i].$1 != 0) {
          i++;
        }
        continue;
      }
      if (abschnitt == 'ENTITIES' || (abschnitt == 'BLOCKS' && block != null)) aktuell = [(0, wert)];
      i++;
      continue;
    }
    if (abschnitt == 'HEADER' && code == 9 && wert == r'$INSUNITS' && i + 1 < paare.length) {
      einheit = int.tryParse(paare[i + 1].$2) ?? 0;
    }
    aktuell?.add((code, wert));
    i++;
  }
  abschliessen();

  final zuege = <DxfZug>[];
  final texte = <DxfText>[];
  _auswerten(entities, bloecke, zuege, texte, _Trafo.eins, 0);
  return DxfZeichnung(zuege: zuege, texte: texte, einheit: einheit);
}

/// Verschiebung, Maßstab und Drehung eines eingefügten Blocks; [_KettenTrafo] verkettet (erst innen, dann außen).
class _Trafo {
  const _Trafo(this.dx, this.dy, this.sx, this.sy, this.winkel, this.bx, this.by);
  final double dx, dy, sx, sy, winkel, bx, by; // bx/by: Basispunkt des Blocks
  static const eins = _Trafo(0, 0, 1, 1, 0, 0, 0);

  Punkt an(Punkt p) {
    final x = (p.x - bx) * sx, y = (p.y - by) * sy;
    final c = math.cos(winkel), s = math.sin(winkel);
    return Punkt(dx + x * c - y * s, dy + x * s + y * c);
  }
}

class _KettenTrafo extends _Trafo {
  _KettenTrafo(this.aussen, this.innen) : super(0, 0, 1, 1, 0, 0, 0);
  final _Trafo aussen, innen;
  @override
  Punkt an(Punkt p) => aussen.an(innen.an(p));
}

void _auswerten(List<List<(int, String)>> liste, Map<String, List<List<(int, String)>>> bloecke, List<DxfZug> zuege,
    List<DxfText> texte, _Trafo t, int tiefe) {
  var i = 0;
  while (i < liste.length) {
    final e = liste[i];
    final typ = e.first.$2;
    String layer = '0';
    double? zahl(int code) {
      for (final (c, w) in e) {
        if (c == code) return double.tryParse(w);
      }
      return null;
    }

    String? text(int code) {
      for (final (c, w) in e) {
        if (c == code) return w;
      }
      return null;
    }

    layer = text(8) ?? '0';
    switch (typ) {
      case 'LINE':
        zuege.add(DxfZug(layer, [
          t.an(Punkt(zahl(10) ?? 0, zahl(20) ?? 0)),
          t.an(Punkt(zahl(11) ?? 0, zahl(21) ?? 0)),
        ]));
      case 'LWPOLYLINE':
        final pts = <Punkt>[];
        double? x;
        for (final (c, w) in e) {
          if (c == 10) x = double.tryParse(w);
          if (c == 20 && x != null) {
            pts.add(t.an(Punkt(x, double.tryParse(w) ?? 0)));
            x = null;
          }
        }
        final flags = (zahl(70) ?? 0).toInt();
        if (pts.length >= 2) zuege.add(DxfZug(layer, pts, geschlossen: flags & 1 == 1));
      case 'POLYLINE':
        final flags = (zahl(70) ?? 0).toInt();
        final pts = <Punkt>[];
        var j = i + 1;
        while (j < liste.length && liste[j].first.$2 == 'VERTEX') {
          double? vx, vy;
          for (final (c, w) in liste[j]) {
            if (c == 10) vx = double.tryParse(w);
            if (c == 20) vy = double.tryParse(w);
          }
          if (vx != null && vy != null) pts.add(t.an(Punkt(vx, vy)));
          j++;
        }
        if (j < liste.length && liste[j].first.$2 == 'SEQEND') j++;
        if (pts.length >= 2) zuege.add(DxfZug(layer, pts, geschlossen: flags & 1 == 1));
        i = j;
        continue;
      case 'ARC' || 'CIRCLE':
        final cx = zahl(10) ?? 0, cy = zahl(20) ?? 0, r = zahl(40) ?? 0;
        if (r > 0) {
          final a0 = (typ == 'ARC' ? zahl(50) ?? 0 : 0) * math.pi / 180;
          var a1 = (typ == 'ARC' ? zahl(51) ?? 360 : 360) * math.pi / 180;
          if (a1 <= a0) a1 += 2 * math.pi;
          final n = math.max(4, ((a1 - a0) / (math.pi / 18)).ceil()); // alle 10°
          final pts = [
            for (var k = 0; k <= n; k++) t.an(Punkt(cx + r * math.cos(a0 + (a1 - a0) * k / n), cy + r * math.sin(a0 + (a1 - a0) * k / n))),
          ];
          zuege.add(DxfZug(layer, pts, geschlossen: typ == 'CIRCLE', bogen: true));
        }
      case 'TEXT' || 'MTEXT':
        final s = text(1);
        if (s != null && s.trim().isNotEmpty) {
          final sauber = s.replaceAll(RegExp(r'\\[A-Za-z][^;]*;'), '').replaceAll(RegExp(r'[{}]'), '').replaceAll(r'\P', ' ');
          texte.add(DxfText(layer, t.an(Punkt(zahl(10) ?? 0, zahl(20) ?? 0)), sauber, zahl(40) ?? 0));
        }
      case 'INSERT':
        final name = text(2);
        final inhalt = name == null ? null : bloecke[name];
        if (inhalt != null && tiefe < 8) {
          final innen = _Trafo(zahl(10) ?? 0, zahl(20) ?? 0, zahl(41) ?? 1, zahl(42) ?? 1, (zahl(50) ?? 0) * math.pi / 180, 0, 0);
          final unter = <DxfZug>[];
          _auswerten(inhalt, bloecke, unter, texte, _KettenTrafo(t, innen), tiefe + 1);
          // Objekte auf Layer „0“ erben den Layer des Blocks
          for (final z in unter) {
            zuege.add(z.layer == '0' ? DxfZug(layer, z.punkte, geschlossen: z.geschlossen, bogen: z.bogen) : z);
          }
        }
    }
    i++;
  }
}

/// Wandvorschlag aus einer DXF-Zeichnung (Weltkoordinaten, mm).
typedef WandVorschlag = ({Punkt a, Punkt b, double dicke});

/// Erzeugt Wände aus geraden Strecken. Zwei parallele, überlappende Strecken
/// im Abstand [minDicke] … [maxDicke] gelten als die beiden Seiten einer Wand:
/// daraus wird eine Achse in der Mitte mit dieser Dicke. Übrige Strecken
/// werden mit [standardDicke] zu Wänden, wenn [einzelLinien] gesetzt ist.
List<WandVorschlag> waendeErkennen(
  List<(Punkt, Punkt)> strecken, {
  double minDicke = 50,
  double maxDicke = 600,
  double standardDicke = 240,
  bool einzelLinien = true,
  double minLaenge = 100,
}) {
  final s = [for (final (a, b) in strecken) if ((b - a).laenge >= minLaenge) (a, b)];
  final benutzt = List<bool>.filled(s.length, false);
  final ergebnis = <WandVorschlag>[];
  for (var i = 0; i < s.length; i++) {
    if (benutzt[i]) continue;
    final (a, b) = s[i];
    final l = (b - a).laenge;
    final u = Punkt((b.x - a.x) / l, (b.y - a.y) / l);
    int? partner;
    double partnerAbstand = double.infinity;
    for (var j = 0; j < s.length; j++) {
      if (j == i || benutzt[j]) continue;
      final (c, d) = s[j];
      final e = d - c;
      final el = e.laenge;
      if (((u.x * e.y - u.y * e.x) / el).abs() > 0.01) continue; // nicht parallel
      final quer = ((c - a).x * u.y - (c - a).y * u.x).abs();
      if (quer < minDicke || quer > maxDicke) continue;
      // Überlappung entlang der Achse
      double t(Punkt p) => (p - a).x * u.x + (p - a).y * u.y;
      final t0 = math.min(t(c), t(d)), t1 = math.max(t(c), t(d));
      final ueber = math.min(t1, l) - math.max(t0, 0);
      if (ueber < math.min(l, el) * 0.5) continue;
      if (quer < partnerAbstand) {
        partnerAbstand = quer;
        partner = j;
      }
    }
    if (partner != null) {
      final (c, d) = s[partner];
      benutzt[i] = benutzt[partner] = true;
      double t(Punkt p) => (p - a).x * u.x + (p - a).y * u.y;
      // gemeinsamer Bereich beider Seiten, Achse mittig
      final t0 = math.max(0.0, math.min(t(c), t(d))), t1 = math.min(l, math.max(t(c), t(d)));
      final n = Punkt(-u.y, u.x);
      final seite = (c - a).x * n.x + (c - a).y * n.y;
      final mitte = Punkt(n.x * seite / 2, n.y * seite / 2);
      ergebnis.add((
        a: Punkt(a.x + u.x * t0 + mitte.x, a.y + u.y * t0 + mitte.y),
        b: Punkt(a.x + u.x * t1 + mitte.x, a.y + u.y * t1 + mitte.y),
        dicke: partnerAbstand,
      ));
    }
  }
  if (einzelLinien) {
    for (var i = 0; i < s.length; i++) {
      if (!benutzt[i]) ergebnis.add((a: s[i].$1, b: s[i].$2, dicke: standardDicke));
    }
  }
  return ergebnis;
}

/// Schließt Ecken: Wandenden, die nahe an der Achse einer anderen Wand enden,
/// werden bis zum Schnittpunkt der Achsen verlängert bzw. gekürzt – so
/// entstehen geschlossene Wandzüge, aus denen die Raumerkennung Räume macht.
List<WandVorschlag> waendeVerbinden(List<WandVorschlag> waende, {double zuschlag = 50}) {
  final w = [for (final x in waende) (a: x.a, b: x.b, dicke: x.dicke)];
  Punkt? schnitt(Punkt p, Punkt r, Punkt q, Punkt s) {
    final kreuz = r.x * s.y - r.y * s.x;
    if (kreuz.abs() < 1e-9) return null;
    final t = ((q.x - p.x) * s.y - (q.y - p.y) * s.x) / kreuz;
    return Punkt(p.x + r.x * t, p.y + r.y * t);
  }

  for (var i = 0; i < w.length; i++) {
    for (final amB in [false, true]) {
      final ende = amB ? w[i].b : w[i].a;
      final r = w[i].b - w[i].a;
      Punkt? bester;
      var abstand = double.infinity;
      for (var j = 0; j < w.length; j++) {
        if (j == i) continue;
        final s = w[j].b - w[j].a;
        final x = schnitt(w[i].a, r, w[j].a, s);
        if (x == null) continue;
        final tol = math.max(w[i].dicke, w[j].dicke) * 0.75 + zuschlag;
        final d = (x - ende).laenge;
        if (d > tol || d >= abstand) continue;
        // Schnittpunkt muss auf (oder knapp neben) der anderen Wand liegen
        final sl = s.laenge;
        final t = ((x - w[j].a).x * s.x + (x - w[j].a).y * s.y) / sl;
        if (t < -tol || t > sl + tol) continue;
        abstand = d;
        bester = x;
      }
      if (bester != null) {
        w[i] = amB ? (a: w[i].a, b: bester, dicke: w[i].dicke) : (a: bester, b: w[i].b, dicke: w[i].dicke);
      }
    }
  }
  return [for (final x in w) if ((x.b - x.a).laenge >= 1) x];
}
