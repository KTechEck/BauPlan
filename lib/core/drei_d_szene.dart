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
}) {
  final aus = <Flaeche3d>[];
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
              final ecken = seite > 0 ? [_w(p1, za), _w(p0, za), _w(p0, zb), _w(p1, zb)] : [_w(p0, za), _w(p1, za), _w(p1, zb), _w(p0, zb)];
              final uv = seite > 0 ? [(-s1, za), (-s0, za), (-s0, zb), (-s1, zb)] : [(s0, za), (s1, za), (s1, zb), (s0, zb)];
              aus.add(Flaeche3d(ecken, uv, mat, normale: normale, id: w.id));
            }
          }
        }
        // Oberseite (Schnitt) und Unterseite (Sturz)
        final quer = [links(t0), links(t1), rechts(t1), rechts(t0)];
        aus.add(Flaeche3d([for (final p in quer.reversed) _w(p, z1)], [for (final p in quer.reversed) (p.x, -p.y)], 'schnitt',
            normale: const V3(0, 0, 1), art: 'schnitt', farbe: z1 >= hoch - 1 ? w.zustandFarbe : null, id: w.id));
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
