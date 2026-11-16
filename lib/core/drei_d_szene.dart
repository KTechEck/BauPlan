/// Szene für die 3D-Ansicht eines Geschosses: Wände mit echten Öffnungen
/// (Fenster mit Brüstung und Sturz, Türen), Böden je Raum, Oberflächen je
/// Material. Alles in kleine ebene Flächen zerlegt, damit das Zeichnen von
/// hinten nach vorne sauber funktioniert.
///
/// Koordinaten: rechtshändig in mm, x wie im Grundriss, y = −y des
/// Grundrisses (sonst wäre die Ansicht spiegelverkehrt), z nach oben ab FFB.
library;

import 'dart:math' as math;

import 'drei_d.dart';
import 'raumerkennung.dart';


/// Oberfläche, wie sie in 3D erscheint: Art der Textur und Grundfarbe.
class Oberflaeche3d {
  const Oberflaeche3d(this.key, this.label, this.art, this.farbe, {this.kachelB = 0, this.kachelH = 0});
  final String key, label;

  /// Texturart: farbe, putz, beton, ziegel, klinker, ks, porenbeton,
  /// gipskarton, holz, fliesen, parkett, dielen, teppich, stein, estrich,
  /// pflaster, daemmung, glas, vinyl.
  final String art;

  /// ARGB, mit der die Textur eingefärbt wird.
  final int farbe;

  /// Fliesengröße in mm (nur bei Fliesen).
  final int kachelB, kachelH;
}

const oberflaechen3d = <Oberflaeche3d>[
  Oberflaeche3d('weiss', 'Wand weiß gestrichen', 'farbe', 0xFFF5F3EE),
  Oberflaeche3d('grau', 'Wand hellgrau gestrichen', 'farbe', 0xFFD4D4D0),
  Oberflaeche3d('salbei', 'Wand salbeigrün', 'farbe', 0xFFBCC8AC),
  Oberflaeche3d('sand', 'Wand sandfarben', 'farbe', 0xFFE6D6B8),
  Oberflaeche3d('blau', 'Wand taubenblau', 'farbe', 0xFFB4C3CF),
  Oberflaeche3d('putz', 'Putz (roh)', 'putz', 0xFFEDE8DE),
  Oberflaeche3d('aussenputz', 'Außenputz', 'putz', 0xFFE9E2D2),
  Oberflaeche3d('beton', 'Beton', 'beton', 0xFFB9B7B1),
  Oberflaeche3d('ziegel', 'Ziegel / Mauerwerk', 'ziegel', 0xFFFFFFFF),
  Oberflaeche3d('klinker', 'Klinker', 'klinker', 0xFFFFFFFF),
  Oberflaeche3d('ks', 'Kalksandstein', 'ks', 0xFFFFFFFF),
  Oberflaeche3d('porenbeton', 'Porenbeton', 'porenbeton', 0xFFFFFFFF),
  Oberflaeche3d('gipskarton', 'Gipskarton', 'gipskarton', 0xFFFFFFFF),
  Oberflaeche3d('holzwand', 'Holzverkleidung', 'holz', 0xFFFFFFFF),
  Oberflaeche3d('daemmung', 'Dämmung (WDVS roh)', 'daemmung', 0xFFFFFFFF),
  Oberflaeche3d('fliesen_weiss', 'Fliesen weiß 30×60', 'fliesen', 0xFFF8F8F6, kachelB: 300, kachelH: 600),
  Oberflaeche3d('fliesen_grau', 'Fliesen grau 60×60', 'fliesen', 0xFFA9A9A5, kachelB: 600, kachelH: 600),
  Oberflaeche3d('fliesen_gross', 'Fliesen Großformat 60×120', 'fliesen', 0xFFD8D2C8, kachelB: 600, kachelH: 1200),
  Oberflaeche3d('fliesen_anthrazit', 'Fliesen anthrazit 30×60', 'fliesen', 0xFF5E5E5C, kachelB: 300, kachelH: 600),
  Oberflaeche3d('mosaik', 'Mosaik 5×5', 'fliesen', 0xFFB9CDD3, kachelB: 50, kachelH: 50),
  Oberflaeche3d('parkett', 'Parkett Eiche', 'parkett', 0xFFFFFFFF),
  Oberflaeche3d('parkett_dunkel', 'Parkett Nuss dunkel', 'parkett', 0xFF9C7A60),
  Oberflaeche3d('dielen', 'Holzdielen', 'dielen', 0xFFFFFFFF),
  Oberflaeche3d('laminat_grau', 'Laminat/Vinyl grau', 'dielen', 0xFFB0ADA6),
  Oberflaeche3d('vinyl', 'Vinyl/Designbelag', 'vinyl', 0xFFFFFFFF),
  Oberflaeche3d('teppich', 'Teppich', 'teppich', 0xFFFFFFFF),
  Oberflaeche3d('stein', 'Naturstein', 'stein', 0xFFFFFFFF),
  Oberflaeche3d('estrich', 'Estrich (roh)', 'estrich', 0xFFC7C3BA),
  Oberflaeche3d('pflaster', 'Pflaster / Platten außen', 'pflaster', 0xFFFFFFFF),
  Oberflaeche3d('wpc', 'WPC-/Holzdielen außen', 'dielen', 0xFF8A8580),
  Oberflaeche3d('dachziegel', 'Dachziegel rot', 'dachziegel', 0xFFFFFFFF),
  Oberflaeche3d('rasen', 'Rasen / Gelände', 'rasen', 0xFFFFFFFF),
  Oberflaeche3d('dachziegel_anthrazit', 'Dachziegel anthrazit', 'dachziegel', 0xFF6A6A6A),
];

final _nachKey = {for (final o in oberflaechen3d) o.key: o};
Oberflaeche3d oberflaeche3d(String? key) => _nachKey[key] ?? _nachKey['putz']!;

/// Oberfläche aus einem Text (Material, Beschichtung, Raumname) erraten.
String? oberflaecheAusText(String text) {
  final t = text.toLowerCase();
  bool hat(List<String> w) => w.any(t.contains);
  if (hat(['mosaik'])) return 'mosaik';
  if (hat(['fliese', 'feinstein', 'keramik', 'kachel'])) return t.contains('grau') || t.contains('60') ? 'fliesen_grau' : 'fliesen_weiss';
  if (hat(['parkett'])) return 'parkett';
  if (hat(['laminat', 'vinyl', 'designbelag', 'pvc', 'linoleum'])) return 'vinyl';
  if (hat(['diele', 'holzboden'])) return 'dielen';
  if (hat(['teppich'])) return 'teppich';
  if (hat(['naturstein', 'marmor', 'granit', 'schiefer', 'travertin'])) return 'stein';
  if (hat(['pflaster', 'terrassenplatte', 'betonplatte'])) return 'pflaster';
  if (hat(['wpc'])) return 'wpc';
  if (hat(['estrich'])) return 'estrich';
  if (hat(['klinker', 'verblend'])) return 'klinker';
  if (hat(['kalksand', 'ks-', 'ks '])) return 'ks';
  if (hat(['porenbeton', 'gasbeton', 'ytong'])) return 'porenbeton';
  if (hat(['ziegel', 'mauerwerk', 'poroton', 'hlz', 'vollziegel', 'backstein'])) return 'ziegel';
  if (hat(['beton', 'stahlbeton'])) return 'beton';
  if (hat(['gipskarton', 'gk-', 'gkb', 'gipsfaser', 'fermacell', 'trockenbau', 'rigips'])) return 'gipskarton';
  if (hat(['holz', 'osb', 'schalung', 'verkleidung'])) return 'holzwand';
  if (hat(['eps', 'xps', 'mineralwolle', 'dämm', 'daemm', 'wdvs', 'holzfaser'])) return 'daemmung';
  if (hat(['außenputz', 'aussenputz', 'oberputz', 'edelputz', 'kratzputz'])) return 'aussenputz';
  if (hat(['farbe', 'anstrich', 'dispersion', 'silikat', 'latex', 'tapete', 'vlies'])) return 'weiss';
  if (hat(['putz', 'spachtel'])) return 'putz';
  return null;
}

/// Bodenbelag aus dem Raumnamen, wenn nichts eingetragen ist.
String bodenAusRaumname(String name, {bool aussen = false}) {
  final t = name.toLowerCase();
  if (aussen || ['balkon', 'terrasse', 'loggia'].any(t.contains)) return 'wpc';
  if (['bad', 'wc', 'dusche', 'sanit'].any(t.contains)) return 'fliesen_grau';
  if (['küche', 'kueche', 'flur', 'diele', 'eingang', 'windfang', 'hwr', 'technik', 'haus­wirtschaft'].any(t.contains)) return 'fliesen_gross';
  if (['keller', 'lager', 'heiz', 'garage', 'abstell'].any(t.contains)) return 'estrich';
  return 'parkett';
}

/// Wandoberfläche im Raum aus dem Raumnamen (Bad/WC: Fliesen).
String wandAusRaumname(String name) {
  final t = name.toLowerCase();
  if (['bad', 'dusche'].any(t.contains)) return 'fliesen_weiss';
  if (['keller', 'heiz', 'garage', 'lager'].any(t.contains)) return 'putz';
  return 'weiss';
}

/// Ebene Fläche der Szene (3 oder 4 Ecken, konvex) mit Texturkoordinaten in mm.
class Flaeche3d {
  Flaeche3d(this.ecken, this.uv, this.material, {this.normale, this.deckkraft = 1, this.beidseitig = false, this.art = 'wand', this.farbe, this.id = ''});
  final List<V3> ecken;
  final List<(double, double)> uv;
  final String material; // Key aus [oberflaechen3d] oder 'schnitt'
  final V3? normale; // nach außen, sonst aus den Ecken
  final double deckkraft;
  final bool beidseitig;
  final String art; // boden, wand, schnitt, glas, geraet
  final int? farbe; // feste Farbe (Schnittfläche, Gerät)
  final String id;

  late final V3 n = normale ?? _normaleAus(ecken);
  late final V3 mitte = ecken.fold(const V3(0, 0, 0), (a, b) => a + b) * (1 / ecken.length);
}

V3 kreuz(V3 a, V3 b) => V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
V3 normiert(V3 v) {
  final l = v.laenge;
  return l < 1e-12 ? const V3(0, 0, 1) : v * (1 / l);
}

V3 _normaleAus(List<V3> e) => normiert(kreuz(e[1] - e[0], e[2] - e[0]));

/// Wand für die Szene (Grundrisskoordinaten, mm).
class Wand3d {
  const Wand3d({
    required this.id,
    required this.a,
    required this.b,
    required this.dicke,
    required this.umriss,
    required this.hoehe,
    this.zustandFarbe = 0xFF495057,
    this.materialLinks,
    this.materialRechts,
  });
  final String id;
  final Punkt a, b;
  final int dicke;

  /// Verschnittener Umriss: links-Anfang, links-Ende, rechts-Ende, rechts-Anfang.
  final List<Punkt> umriss;
  final double hoehe;
  final int zustandFarbe;

  /// Oberfläche der Wandseite ohne Raum davor (z. B. außen), aus dem Wandtyp.
  final String? materialLinks, materialRechts;
}

/// Öffnung für die Szene: Lage entlang der Wandachse ab Wandanfang.
typedef Oeffnung3d = ({String wandId, double von, double bis, double unten, double oben, bool fenster});

/// Raum für die Szene: lichter Umriss (Grundriss), Boden- und Wandoberfläche.
typedef Raum3d = ({String id, String name, List<Punkt> umriss, String boden, String waende, bool aussen});

V3 _w(Punkt p, double z) => V3(p.x, -p.y, z);

/// Baut die Flächen eines Geschosses. [schnitt] begrenzt die Wandhöhe
/// (Puppenhaus-Ansicht); [raster] ist die größte Kantenlänge der Teilflächen.
List<Flaeche3d> geschossSzene({
  required List<Wand3d> waende,
  required List<Oeffnung3d> oeffnungen,
  required List<Raum3d> raeume,
  double schnitt = double.infinity,
  double raster = 900,
  double Function(Punkt p)? oben,
}) {
  final aus = <Flaeche3d>[];
  // Wandoberkante unter einer Dachschräge (Giebel, Kniestock)
  double top(Punkt p, double z) => oben == null ? z : math.min(z, math.max(0, oben(p)));
  // ----------------------------------------------------------- Böden
  for (final r in raeume) {
    if (r.umriss.length < 3) continue;
    for (final (i, j, k) in dreieckeZerlegen(r.umriss)) {
      for (final d in _teilen([r.umriss[i], r.umriss[j], r.umriss[k]], raster)) {
        aus.add(Flaeche3d([for (final p in d) _w(p, 0)], [for (final p in d) (p.x, -p.y)], r.boden, normale: const V3(0, 0, 1), art: 'boden', id: r.id));
      }
    }
  }
  String? raumAn(Punkt p) {
    for (final r in raeume) {
      if (r.umriss.length >= 3 && punktInPolygon(p, r.umriss)) return r.waende;
    }
    return null;
  }

  // Freie Wandenden (ohne Nachbarwand) bekommen eine Stirnfläche.
  bool frei(Wand3d w, Punkt p) {
    for (final o in waende) {
      if (o.id == w.id) continue;
      if (_abstandStrecke(p, o.a, o.b) <= o.dicke / 2 + w.dicke / 2 + 2) return false;
    }
    return true;
  }

  final jeWand = <String, List<Oeffnung3d>>{};
  for (final o in oeffnungen) {
    (jeWand[o.wandId] ??= []).add(o);
  }
  // ----------------------------------------------------------- Wände
  for (final w in waende) {
    final d = w.b - w.a;
    final l = d.laenge;
    if (l < 1 || w.umriss.length != 4) continue;
    final u = d * (1 / l);
    final nl = Punkt(u.y, -u.x); // links der Zeichenrichtung (Grundriss)
    final h = w.dicke / 2;
    double t(Punkt p) => (p - w.a).skalar(u);
    final tla = t(w.umriss[0]), tlb = t(w.umriss[1]), trb = t(w.umriss[2]), tra = t(w.umriss[3]);
    final tMin = math.min(tla, tra), tMax = math.max(tlb, trb);
    final hoch = math.min(w.hoehe, schnitt);
    double klemm(double v, double lo, double hi) => lo <= hi ? v.clamp(lo, hi) : (lo + hi) / 2;
    Punkt links(double s) => w.a + nl * h + u * klemm(s, tla, tlb);
    Punkt rechts(double s) => w.a - nl * h + u * klemm(s, tra, trb);

    // Abschnitte entlang der Achse mit ihren festen Höhenbereichen
    final oe = [...?jeWand[w.id]]..sort((x, y) => x.von.compareTo(y.von));
    final abschnitte = <(double, double, List<(double, double)>, Oeffnung3d?)>[];
    var s = tMin;
    for (final o in oe) {
      final von = klemm(o.von, tMin, tMax), bis = klemm(o.bis, tMin, tMax);
      if (bis - von < 1 || von < s - 1) continue;
      if (von > s) abschnitte.add((s, von, [(0, hoch)], null));
      abschnitte.add((von, bis, [if (o.unten > 0) (0, math.min(o.unten, hoch)), if (o.oben < hoch) (o.oben, hoch)], o));
      s = bis;
    }
    if (tMax > s) abschnitte.add((s, tMax, [(0, hoch)], null));

    for (final (t0, t1, bereiche, o) in abschnitte) {
      for (final (z0, z1) in bereiche) {
        if (z1 - z0 < 1) continue;
        // Seitenflächen in Kacheln (Material je Raum davor)
        for (final seite in [1.0, -1.0]) {
          final fuss = seite > 0 ? links : rechts;
          final a0 = seite > 0 ? math.max(t0, tla) : math.max(t0, tra);
          final a1 = seite > 0 ? math.min(t1, tlb) : math.min(t1, trb);
          if (a1 - a0 < 1) continue;
          final n = math.max(1, ((a1 - a0) / raster).ceil());
          final m = math.max(1, ((z1 - z0) / raster).ceil());
          final normale = V3(nl.x * seite, -nl.y * seite, 0);
          for (var i = 0; i < n; i++) {
            final s0 = a0 + (a1 - a0) * i / n, s1 = a0 + (a1 - a0) * (i + 1) / n;
            final p0 = fuss(s0), p1 = fuss(s1);
            final probe = (p0 + p1) * 0.5 + nl * (seite * 60);
            final mat = raumAn(probe) ?? (seite > 0 ? w.materialLinks : w.materialRechts) ?? 'aussenputz';
            for (var k = 0; k < m; k++) {
              final za = z0 + (z1 - z0) * k / m, zb = z0 + (z1 - z0) * (k + 1) / m;
              // Ecken gegen den Uhrzeigersinn von außen gesehen
              final a0z = top(p0, za), b0z = top(p0, zb), a1z = top(p1, za), b1z = top(p1, zb);
              if (b0z - a0z < 1 && b1z - a1z < 1) continue; // ganz über der Dachschräge
              final ecken = seite > 0 ? [_w(p1, a1z), _w(p0, a0z), _w(p0, b0z), _w(p1, b1z)] : [_w(p0, a0z), _w(p1, a1z), _w(p1, b1z), _w(p0, b0z)];
              final uv = seite > 0 ? [(-s1, a1z), (-s0, a0z), (-s0, b0z), (-s1, b1z)] : [(s0, a0z), (s1, a1z), (s1, b1z), (s0, b0z)];
              aus.add(Flaeche3d(ecken, uv, mat, normale: normale, id: w.id));
            }
          }
        }
        // Oberseite (Schnitt) und Unterseite (Sturz)
        final quer = [links(t0), links(t1), rechts(t1), rechts(t0)];
        if (oben == null) {
          aus.add(Flaeche3d([for (final p in quer.reversed) _w(p, z1)], [for (final p in quer.reversed) (p.x, -p.y)], 'schnitt',
              normale: const V3(0, 0, 1), art: 'schnitt', farbe: z1 >= hoch - 1 ? w.zustandFarbe : null, id: w.id));
        } else {
          // Oberseite unter der Dachschräge in Stücken (folgt dem Giebel)
          final n = math.max(1, ((t1 - t0) / raster).ceil());
          for (var i = 0; i < n; i++) {
            final s0 = t0 + (t1 - t0) * i / n, s1 = t0 + (t1 - t0) * (i + 1) / n;
            final q = [links(s0), links(s1), rechts(s1), rechts(s0)];
            aus.add(Flaeche3d([for (final p in q.reversed) _w(p, top(p, z1))], [for (final p in q.reversed) (p.x, -p.y)], 'schnitt',
                normale: const V3(0, 0, 1), art: 'schnitt', farbe: w.zustandFarbe, id: w.id));
          }
        }
        if (z0 > 1) {
          aus.add(Flaeche3d([for (final p in quer) _w(p, z0)], [for (final p in quer) (p.x, -p.y)], 'putz', normale: const V3(0, 0, -1), id: w.id));
        }
      }
      // Laibungen der Öffnung
      if (o != null) {
        final zu = klemm(o.unten, 0, hoch), zo = klemm(o.oben, 0, hoch);
        if (zo - zu >= 1) {
          for (final (tt, richtung) in [(t0, 1.0), (t1, -1.0)]) {
            final p = links(tt), q = rechts(tt);
            final nn = V3(u.x * richtung, -u.y * richtung, 0);
            final ecken = [_w(p, zu), _w(q, zu), _w(q, zo), _w(p, zo)];
            final f = Flaeche3d(ecken, [(0, zu), (w.dicke.toDouble(), zu), (w.dicke.toDouble(), zo), (0, zo)], 'putz', normale: nn, id: w.id);
            // Ecken so ordnen, dass die Normale zur Öffnung zeigt
            aus.add(_normaleSetzen(f, nn));
          }
          if (o.fenster) {
            final m0 = w.a + u * t0, m1 = w.a + u * t1;
            aus.add(Flaeche3d([_w(m0, zu), _w(m1, zu), _w(m1, zo), _w(m0, zo)], [(0, 0), (1, 0), (1, 1), (0, 1)], 'glas',
                normale: V3(nl.x, -nl.y, 0), deckkraft: 0.28, beidseitig: true, art: 'glas', farbe: 0xFF8EC5E8, id: w.id));
            // Fensterrahmen als Schnittkante unten/oben
          }
        }
      }
    }
    // Stirnflächen an freien Enden
    for (final (ende, tt, richtung) in [(w.a, tMin, -1.0), (w.b, tMax, 1.0)]) {
      if (!frei(w, ende)) continue;
      final p = links(tt), q = rechts(tt);
      final nn = V3(u.x * richtung, -u.y * richtung, 0);
      aus.add(_normaleSetzen(
          Flaeche3d([_w(p, 0), _w(q, 0), _w(q, hoch), _w(p, hoch)], [(0, 0), (w.dicke.toDouble(), 0), (w.dicke.toDouble(), hoch), (0, hoch)], 'putz', normale: nn, id: w.id),
          nn));
    }
  }
  return aus;
}

Flaeche3d _normaleSetzen(Flaeche3d f, V3 n) {
  final roh = _normaleAus(f.ecken);
  if (roh.skalar(n) >= 0) return f;
  return Flaeche3d(f.ecken.reversed.toList(), f.uv.reversed.toList(), f.material,
      normale: n, deckkraft: f.deckkraft, beidseitig: f.beidseitig, art: f.art, farbe: f.farbe, id: f.id);
}

double _abstandStrecke(Punkt p, Punkt a, Punkt b) {
  final ab = b - a;
  final l2 = ab.skalar(ab);
  if (l2 == 0) return (p - a).laenge;
  final t = ((p - a).skalar(ab) / l2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).laenge;
}

/// Dreieck so lange an der längsten Kante teilen, bis alle Kanten ≤ [max] sind.
List<List<Punkt>> _teilen(List<Punkt> d, double max, [int tiefe = 0]) {
  final l = [(d[1] - d[0]).laenge, (d[2] - d[1]).laenge, (d[0] - d[2]).laenge];
  final i = l[0] >= l[1] && l[0] >= l[2] ? 0 : (l[1] >= l[2] ? 1 : 2);
  if (l[i] <= max || tiefe > 9) return [d];
  final a = d[i], b = d[(i + 1) % 3], c = d[(i + 2) % 3];
  final m = (a + b) * 0.5;
  return [..._teilen([a, m, c], max, tiefe + 1), ..._teilen([m, b, c], max, tiefe + 1)];
}

/// Einfaches Polygon in Dreiecke zerlegen (Ohrenschneiden). Liefert Indizes.
List<(int, int, int)> dreieckeZerlegen(List<Punkt> p) {
  final n = p.length;
  if (n < 3) return const [];
  final idx = List<int>.generate(n, (i) => i);
  if (polygonFlaeche(p) < 0) idx.setAll(0, idx.reversed.toList());
  final aus = <(int, int, int)>[];
  var schutz = 0;
  while (idx.length > 3 && schutz++ < 10 * n) {
    var gefunden = false;
    for (var k = 0; k < idx.length; k++) {
      final i0 = idx[(k - 1 + idx.length) % idx.length], i1 = idx[k], i2 = idx[(k + 1) % idx.length];
      final a = p[i0], b = p[i1], c = p[i2];
      if ((b - a).kreuz(c - b) <= 1e-9) continue; // nicht konvex
      var leer = true;
      for (final j in idx) {
        if (j == i0 || j == i1 || j == i2) continue;
        if (_imDreieck(p[j], a, b, c)) {
          leer = false;
          break;
        }
      }
      if (!leer) continue;
      aus.add((i0, i1, i2));
      idx.removeAt(k);
      gefunden = true;
      break;
    }
    if (!gefunden) break;
  }
  if (idx.length == 3) aus.add((idx[0], idx[1], idx[2]));
  return aus;
}

bool _imDreieck(Punkt q, Punkt a, Punkt b, Punkt c) {
  final d1 = (b - a).kreuz(q - a), d2 = (c - b).kreuz(q - b), d3 = (a - c).kreuz(q - c);
  return d1 >= 0 && d2 >= 0 && d3 >= 0;
}

/// Orbit-Kamera (rechtshändig, z oben). [azimut] um die Hochachse,
/// [neigung] über dem Horizont, [abstand] zum [ziel].
class Orbit {
  const Orbit({this.azimut = -2.2, this.neigung = 0.7, this.abstand = 9000, this.ziel = const V3(0, 0, 0)});
  final double azimut, neigung, abstand;
  final V3 ziel;

  V3 get auge => ziel + V3(math.cos(neigung) * math.cos(azimut), math.cos(neigung) * math.sin(azimut), math.sin(neigung)) * abstand;

  /// Kamerabasis: rechts, oben, vorwärts.
  (V3, V3, V3) get basis {
    final f = normiert(V3(-math.cos(neigung) * math.cos(azimut), -math.cos(neigung) * math.sin(azimut), -math.sin(neigung)));
    var r = kreuz(f, const V3(0, 0, 1));
    r = r.laenge < 1e-6 ? V3(-math.sin(azimut), math.cos(azimut), 0) : normiert(r);
    return (r, kreuz(r, f), f);
  }

  Orbit mit({double? azimut, double? neigung, double? abstand, V3? ziel}) => Orbit(
        azimut: azimut ?? this.azimut,
        neigung: (neigung ?? this.neigung).clamp(-0.45, 1.5607),
        abstand: (abstand ?? this.abstand).clamp(1, 120000),
        ziel: ziel ?? this.ziel,
      );
}

/// Gerät/Installationsobjekt für die 3D-Ansicht (Grundrisskoordinaten).
typedef Geraet3d = ({String id, String kuerzel, Punkt p, double? z, List<double>? masse, int farbe, int drehung});

const _weiss = 0xFFF3F3F0, _dunkel = 0xFF3A3D40, _grau = 0xFFB9BCBF;

/// An die Decke gehören diese Kürzel (Unterseite der Decke), sonst an die Wand.
const _decke = {'LE', 'RW', 'WR', 'CM', 'PM', 'BM', 'AP', 'LV'};
const _wandplatte = {'SD', 'TA', 'ND', 'DO', 'FA', 'TO', 'KX', 'ES', 'AS', 'MP'};

/// Übliche Montagehöhe über FFB (mm), wenn das Objekt keine eigene hat.
double standardHoehe(String k) => switch (k) {
      'SD' || 'ND' || 'AS' => 300,
      'TA' || 'TO' || 'KX' || 'ES' => 1050,
      'DO' => 2200,
      'FA' => 600,
      'VT' => 1100,
      'HV' => 400,
      'EN' => 850,
      'FL' => 800,
      _ => 300,
    };

/// Geräte als erkennbare Körper: Steckdosen/Schalter/Datendosen als Platte mit
/// Einsatz bündig auf der nächsten Wand, Melder/Leuchten als flache Scheibe an
/// der Decke, Verteiler/Geräte als Kasten (mit echten Maßen, wenn vorhanden).
List<Flaeche3d> geraeteFlaechen(List<Geraet3d> geraete, List<Wand3d> waende, double raumhoehe) {
  final aus = <Flaeche3d>[];
  for (final g in geraete) {
    // nächste Wandoberfläche
    Punkt? fuss;
    var u = const Punkt(1, 0), n = const Punkt(0, 1);
    var best = 450.0;
    for (final w in waende) {
      final d = w.b - w.a;
      final l = d.laenge;
      if (l < 1) continue;
      final ux = d * (1 / l);
      final t = (g.p - w.a).skalar(ux).clamp(0.0, l);
      final q = w.a + ux * t;
      final ab = (g.p - q).laenge;
      if (ab - w.dicke / 2 < best) {
        best = ab - w.dicke / 2;
        var nn = Punkt(ux.y, -ux.x);
        if ((g.p - q).skalar(nn) < 0) nn = nn * -1;
        u = ux;
        n = nn;
        fuss = q + nn * (w.dicke / 2);
      }
    }
    final k = g.kuerzel;
    final m = g.masse;
    if (_decke.contains(k) && g.z == null) {
      final (r, h, farbe) = switch (k) {
        'LE' => (110.0, 60.0, _weiss),
        'AP' => (100.0, 35.0, _weiss),
        'LV' => (65.0, 25.0, _grau),
        _ => (55.0, 45.0, _weiss),
      };
      aus.addAll(_scheibe(g.id, g.p, raumhoehe - h, h, r, farbe));
      if (k == 'LE') aus.addAll(_scheibe(g.id, g.p, raumhoehe - h - 2, 2, r * 0.7, 0xFFFFF4C2)); // Lichtfläche
      continue;
    }
    final z = g.z ?? standardHoehe(k);
    if (_wandplatte.contains(k) && fuss != null) {
      final (b, h) = m != null && m.length >= 3 ? (m[0], m[2]) : (k == 'FA' || k == 'DO' ? (90.0, 90.0) : (80.0, 80.0));
      final mitte = fuss + n * 5;
      aus.addAll(_kasten(g.id, mitte, u, n, z - h / 2, b, 10, h, k == 'MP' ? 0xFFE03131 : _weiss));
      // Einsatz vorne
      final vorne = fuss + n * 10.5;
      switch (k) {
        case 'SD' || 'AS':
          aus.addAll(_kasten(g.id, vorne, u, n, z - 25, 50, 1, 50, 0xFFE6E6E2));
          for (final s in [-1.0, 1.0]) {
            aus.addAll(_kasten(g.id, vorne + u * (s * 10) + n * 1, u, n, z - 4, 8, 1, 8, _dunkel));
          }
        case 'TA':
          aus.addAll(_kasten(g.id, vorne, u, n, z - 28, 56, 2, 56, 0xFFE9E9E5));
          aus.addAll(_kasten(g.id, vorne + n * 2, u, n, z - 2, 40, 1, 2, _grau));
        case 'ND':
          for (final s in [-1.0, 1.0]) {
            aus.addAll(_kasten(g.id, vorne + u * (s * 14), u, n, z - 7, 16, 1, 14, _dunkel));
          }
        default:
          aus.addAll(_kasten(g.id, vorne, u, n, z - 10, 20, 1, 20, g.farbe));
      }
      continue;
    }
    // Kästen: Verteiler, Heizkreisverteiler, Geräte mit Maßen
    final (b, t, h, farbe) = m != null && m.length >= 3
        ? (m[0], m[1], m[2], _hell(g.farbe))
        : switch (k) {
            'VT' => (550.0, 160.0, 1100.0, 0xFFE9EAEC),
            'HV' => (500.0, 110.0, 700.0, 0xFFF1F1EE),
            'EN' => (60.0, 60.0, 200.0, 0xFFC9CED3),
            'FL' => (160.0, 160.0, 550.0, 0xFFD62828),
            'SR' => (120.0, 120.0, raumhoehe, _grau),
            _ => (90.0, 70.0, 90.0, _hell(g.farbe)),
          };
    if (fuss != null && best < 200 && k != 'SR') {
      aus.addAll(_kasten(g.id, fuss + n * (t / 2), u, n, k == 'VT' || k == 'HV' ? z - h / 2 : z, b, t, h, farbe));
    } else {
      final w = g.drehung * math.pi / 180;
      aus.addAll(_kasten(g.id, g.p, Punkt(math.cos(w), math.sin(w)), Punkt(-math.sin(w), math.cos(w)), k == 'SR' ? 0 : z, b, t, h, farbe));
    }
  }
  return aus;
}

int _hell(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  int h(int c) => (c + (255 - c) * 0.35).round();
  return 0xFF000000 | (h(r) << 16) | (h(g) << 8) | h(b);
}

/// Quader: Mitte der Rückseite… vereinfacht: Mitte der Grundfläche [m], Breite
/// entlang [u], Tiefe entlang [n], Unterkante [z0].
List<Flaeche3d> _kasten(String id, Punkt m, Punkt u, Punkt n, double z0, double b, double t, double h, int farbe) {
  Punkt q(double a, double c) => m + u * a + n * c;
  final ecken = [q(-b / 2, -t / 2), q(b / 2, -t / 2), q(b / 2, t / 2), q(-b / 2, t / 2)];
  final z1 = z0 + h;
  final f = <Flaeche3d>[];
  void fl(List<V3> e, V3 nn) => f.add(Flaeche3d(e, const [(0, 0), (1, 0), (1, 1), (0, 1)], 'geraet', normale: nn, art: 'geraet', farbe: farbe, id: id));
  fl([for (final e in ecken) _w(e, z1)], const V3(0, 0, 1));
  fl([for (final e in ecken.reversed) _w(e, z0)], const V3(0, 0, -1));
  for (var i = 0; i < 4; i++) {
    final a = ecken[i], c = ecken[(i + 1) % 4];
    final mid = (a + c) * 0.5 - m;
    final nn = normiert(V3(mid.x, -mid.y, 0));
    fl([_w(a, z0), _w(c, z0), _w(c, z1), _w(a, z1)], nn);
  }
  return f;
}

/// Flache runde Scheibe (Achteck) mit Unterkante [z0].
List<Flaeche3d> _scheibe(String id, Punkt m, double z0, double h, double r, int farbe) {
  final f = <Flaeche3d>[];
  final pts = [for (var i = 0; i < 12; i++) m + Punkt(math.cos(i * math.pi / 6), math.sin(i * math.pi / 6)) * r];
  for (var i = 0; i < 12; i++) {
    final a = pts[i], c = pts[(i + 1) % 12];
    f.add(Flaeche3d([_w(m, z0), _w(c, z0), _w(a, z0)], const [(0, 0), (1, 0), (0, 1)], 'geraet', normale: const V3(0, 0, -1), art: 'geraet', farbe: farbe, id: id));
    final mid = (a + c) * 0.5 - m;
    f.add(Flaeche3d([_w(a, z0), _w(c, z0), _w(c, z0 + h), _w(a, z0 + h)], const [(0, 0), (1, 0), (1, 1), (0, 1)], 'geraet',
        normale: normiert(V3(mid.x, -mid.y, 0)), art: 'geraet', farbe: farbe, id: id));
  }
  return f;
}

/// Dachfläche als Raster von Dreiecken über dem Gebäuderahmen (mit Überstand);
/// Höhe je Punkt aus [hoehe] (über FFB, Oberkante Dachhaut).
List<Flaeche3d> dachFlaechen({required double x0, required double y0, required double x1, required double y1, required double Function(double x, double y) hoehe, double raster = 300}) {
  final aus = <Flaeche3d>[];
  final nx = math.max(1, ((x1 - x0) / raster).ceil()), ny = math.max(1, ((y1 - y0) / raster).ceil());
  final dx = (x1 - x0) / nx, dy = (y1 - y0) / ny;
  V3 p(int i, int j) {
    final x = x0 + i * dx, y = y0 + j * dy;
    return V3(x, -y, hoehe(x, y));
  }

  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      final a = p(i, j), b = p(i + 1, j), c = p(i + 1, j + 1), d = p(i, j + 1);
      for (final t in [
        [a, c, b],
        [a, d, c],
      ]) {
        var n = normiert(kreuz(t[1] - t[0], t[2] - t[0]));
        if (n.z < 0) n = n * -1;
        aus.add(Flaeche3d(t, [for (final q in t) (q.x, -q.y * 1.0)], 'dachziegel', normale: n, beidseitig: true, art: 'dach'));
      }
    }
  }
  return aus;
}

/// Holzbalken als Quader entlang einer Strecke (Grundriss x/y, z), Breite b, Höhe h.
List<Flaeche3d> balkenFlaechen(String id, double x1, double y1, double z1, double x2, double y2, double z2, int b, int h, {int farbe = 0xFFC08A55}) {
  final a = V3(x1, -y1, z1), e = V3(x2, -y2, z2);
  final dir = e - a;
  if (dir.laenge < 1) return const [];
  final d = normiert(dir);
  var s = kreuz(d, const V3(0, 0, 1));
  s = s.laenge < 1e-6 ? const V3(1, 0, 0) : normiert(s);
  final u = normiert(kreuz(s, d));
  final sb = s * (b / 2), uh = u * (h / 2);
  // Oberkante liegt auf der Strecke: Mitte eine halbe Höhe darunter
  final a0 = a - uh, e0 = e - uh;
  final aus = <Flaeche3d>[];
  for (final (o1, o2, n) in [(sb + uh, sb - uh, s), (sb * -1 - uh, sb * -1 + uh, s * -1), (sb * -1 + uh, sb + uh, u), (sb - uh, sb * -1 - uh, u * -1)]) {
    aus.add(Flaeche3d([a0 + o1, e0 + o1, e0 + o2, a0 + o2], const [(0, 0), (1, 0), (1, 1), (0, 1)], 'holz', normale: n, art: 'holz', farbe: farbe, id: id));
  }
  return aus;
}


/// Geländefläche als Dreiecksraster (ohne die Zellen unter dem Haus [haus]).
List<Flaeche3d> gelaendeFlaechen({required double x0, required double y0, required double x1, required double y1, required double Function(double x, double y) hoehe, required (double, double, double, double) haus, double raster = 600}) {
  final aus = <Flaeche3d>[];
  final nx = math.max(1, ((x1 - x0) / raster).ceil()), ny = math.max(1, ((y1 - y0) / raster).ceil());
  final dx = (x1 - x0) / nx, dy = (y1 - y0) / ny;
  V3 p(int i, int j) {
    final x = x0 + i * dx, y = y0 + j * dy;
    return V3(x, -y, hoehe(x, y));
  }

  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      final cx = x0 + (i + 0.5) * dx, cy = y0 + (j + 0.5) * dy;
      if (cx > haus.$1 && cx < haus.$3 && cy > haus.$2 && cy < haus.$4) continue;
      final a = p(i, j), b = p(i + 1, j), c = p(i + 1, j + 1), d = p(i, j + 1);
      for (final t in [
        [a, c, b],
        [a, d, c],
      ]) {
        var n = normiert(kreuz(t[1] - t[0], t[2] - t[0]));
        if (n.z < 0) n = n * -1;
        aus.add(Flaeche3d(t, [for (final q in t) (q.x, -q.y * 1.0)], 'rasen', normale: n, art: 'gelaende'));
      }
    }
  }
  return aus;
}
