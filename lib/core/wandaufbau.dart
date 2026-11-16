/// Wandmodell „Kern + Aufbau je Seite“: Die gezeichnete Wand ist der
/// tragende Kern (Dicke = `dicke`, Achse = Kernmitte); Ecken verbinden sich
/// nur über den Kern. Jede Seite trägt ihren Aufbau (Putz, Fliese, WDVS …)
/// in Bereichen – entlang der Wand (von/bis ab Wandanfang) und in der Höhe
/// (z von/bis über FFB). Im Plan laufen die Schichten jeder Seite als
/// zusammenhängende Kontur um Ecken, Versprünge und Teilstücke.
///
/// Gespeichert in `wand.eigenschaften`: `kern` {m: Baustoff, d: mm},
/// `aufbau_l` / `aufbau_r`: [{von?, bis?, z_von?, z_bis?, s: [{m, d}]}]
/// (Schichten vom Kern nach außen).
library;

import 'dart:math' as math;

import '../data/models.dart';
import 'raumerkennung.dart';
import 'wandmasse.dart';

typedef AufbauSchicht = ({String? material, int dicke});

class Aufbaubereich {
  const Aufbaubereich({this.von, this.bis, this.zVon, this.zBis, this.schichten = const []});
  final double? von, bis;
  final int? zVon, zBis;
  final List<AufbauSchicht> schichten;

  int get dicke => schichten.fold(0, (s, x) => s + x.dicke);

  bool enthaelt(double t, {double z = 1000}) => (von == null || t >= von! - 0.5) && (bis == null || t <= bis! + 0.5) && (zVon == null || z >= zVon!) && (zBis == null || z <= zBis!);

  Map<String, dynamic> toJson() => {
        if (von != null) 'von': von!.round(),
        if (bis != null) 'bis': bis!.round(),
        if (zVon != null) 'z_von': zVon,
        if (zBis != null) 'z_bis': zBis,
        's': [for (final s in schichten) {'m': s.material, 'd': s.dicke}],
      };

  static Aufbaubereich ausJson(Map m) => Aufbaubereich(
        von: (m['von'] as num?)?.toDouble(),
        bis: (m['bis'] as num?)?.toDouble(),
        zVon: (m['z_von'] as num?)?.toInt(),
        zBis: (m['z_bis'] as num?)?.toInt(),
        schichten: [
          for (final s in (m['s'] as List? ?? const []))
            if (s is Map) (material: s['m'] as String?, dicke: (s['d'] as num?)?.toInt() ?? 0),
        ],
      );
}

/// Hat die Wand das neue Modell (Kern + Seiten)?
bool hatKern(Wand w) => w.eigenschaften['kern'] is Map;

String? kernMaterial(Wand w) => (w.eigenschaften['kern'] as Map?)?['m'] as String?;

/// Aufbaubereiche einer Seite ([links] = links der Zeichenrichtung).
List<Aufbaubereich> aufbau(Wand w, bool links) => [
      for (final b in (w.eigenschaften[links ? 'aufbau_l' : 'aufbau_r'] as List? ?? const []))
        if (b is Map) Aufbaubereich.ausJson(b),
    ];

/// Schichten an Stelle [t] (mm ab Wandanfang) und Höhe [z].
List<AufbauSchicht> schichtenBei(Wand w, bool links, double t, {double z = 1000}) {
  for (final b in aufbau(w, links).reversed) {
    if (b.enthaelt(t, z: z)) return b.schichten;
  }
  return const [];
}

/// Aus einem Wandtyp (Schichten von Seite A nach B) Kern und Seitenaufbau
/// machen: Kern = dickste Schicht. Liefert die Eigenschaften und den Versatz
/// der Kernmitte gegenüber der Wandmitte (positiv = Richtung Seite A/links).
({Map<String, Object?> eigenschaften, int kern, double versatz}) ausWandtyp(List<Schicht> schichten) {
  if (schichten.isEmpty) return (eigenschaften: {'kern': {'d': 0}}, kern: 0, versatz: 0);
  var k = 0;
  for (var i = 1; i < schichten.length; i++) {
    if (schichten[i].dicke > schichten[k].dicke) k = i;
  }
  final links = [for (var i = k - 1; i >= 0; i--) (material: schichten[i].materialId, dicke: schichten[i].dicke)];
  final rechts = [for (var i = k + 1; i < schichten.length; i++) (material: schichten[i].materialId, dicke: schichten[i].dicke)];
  final summe = schichten.fold<int>(0, (s, x) => s + x.dicke);
  final vonLinks = links.fold<int>(0, (s, x) => s + x.dicke) + schichten[k].dicke / 2;
  return (
    eigenschaften: {
      'kern': {'m': schichten[k].materialId, 'd': schichten[k].dicke},
      'aufbau_l': links.isEmpty ? null : [Aufbaubereich(schichten: links).toJson()],
      'aufbau_r': rechts.isEmpty ? null : [Aufbaubereich(schichten: rechts).toJson()],
    },
    kern: schichten[k].dicke,
    versatz: summe / 2 - vonLinks,
  );
}

/// Ein Band des Aufbaus im Grundriss: Polygon (mm) und Material.
typedef Aufbauband = ({List<Punkt> polygon, String? material, String wandId, List<(double, double)>? hoehen, bool aussen, bool imPlan});

class _Seg {
  _Seg(this.p, this.q, this.nx, this.ny, this.schichten, this.wandId, {this.hoehen});
  /// Höhenbereiche mit Material (Öffnung: unter Brüstung / über Sturz), null = ganze Höhe.
  final List<(double, double)>? hoehen;
  final Punkt p, q;
  final double nx, ny; // Normale weg vom Kern
  final List<AufbauSchicht> schichten;
  final String wandId;
  double tiefe(int k) {
    var s = 0;
    for (var i = 0; i < k && i < schichten.length; i++) {
      s += schichten[i].dicke;
    }
    return s.toDouble();
  }
}

Punkt? _schnitt(Punkt a, Punkt da, Punkt b, Punkt db) {
  final n = da.kreuz(db);
  if (n.abs() < 1e-6) return null;
  final t = (b - a).kreuz(db) / n;
  return a + da * t;
}

/// Bänder aller Seitenaufbauten im Grundriss (Schnitthöhe [hoehe]). Die
/// Flächen der Kerne werden zu Ketten verbunden; jede Schicht läuft als
/// Kontur um Ecken (Gehrung über die Nachbarschicht gleicher Lage), an
/// Wechseln entlang einer Wand mit Absatz.
List<Aufbauband> aufbauBaender(List<Wand> waende, {bool verbindenStandard = true, double hoehe = 1000, List<Oeffnung> oeffnungen = const [], double raumhoehe = 2600}) {
  final kerne = [for (final w in waende) if (hatKern(w) && !w.istKante && w.laenge > 1) w];
  if (kerne.isEmpty) return const [];
  final alle = [for (final w in waende) if (!w.istKante && !w.teilhoch) w];
  // dieselben Achsen-Objekte verwenden (wandUmriss erkennt die eigene Wand an der Identität)
  final achse = {for (final w in alle) w.id: w.achse};
  final nachbarn = [for (final w in alle) if (w.verbinden ?? verbindenStandard) achse[w.id]!];
  // Seitenflächen, an Bereichsgrenzen geteilt
  final segs = <_Seg>[];
  for (final w in alle) {
    if (w.laenge < 1) continue;
    final u = wandUmriss(achse[w.id]!, (w.verbinden ?? verbindenStandard) ? nachbarn : [achse[w.id]!]);
    final l = w.laenge;
    final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
    for (final links in [true, false]) {
      final (a, b) = links ? (u[0], u[1]) : (u[3], u[2]);
      final nx = links ? uy : -uy, ny = links ? -ux : ux;
      double t(Punkt p) => (p.x - w.x1) * ux + (p.y - w.y1) * uy;
      final ta = t(a), tb = t(b);
      if (tb - ta < 1) continue;
      final grenzen = <double>{ta, tb};
      for (final bb in aufbau(w, links)) {
        for (final g in [bb.von, bb.bis]) {
          if (g != null && g > ta + 1 && g < tb - 1) grenzen.add(g);
        }
      }
      final hier = [for (final o in oeffnungen) if (o.wandId == w.id && o.art != OeffnungsArt.nische) o];
      for (final o in hier) {
        for (final g in [o.abstand.toDouble(), (o.abstand + o.breite).toDouble()]) {
          if (g > ta + 1 && g < tb - 1) grenzen.add(g);
        }
      }
      final gs = grenzen.toList()..sort();
      for (var i = 0; i + 1 < gs.length; i++) {
        final p = a + Punkt(ux, uy) * (gs[i] - ta), q = a + Punkt(ux, uy) * (gs[i + 1] - ta);
        final mitte = (gs[i] + gs[i + 1]) / 2;
        final o = hier.where((o) => mitte > o.abstand && mitte < o.abstand + o.breite).firstOrNull;
        List<(double, double)>? hoehen;
        if (o != null) {
          final unten = o.art == OeffnungsArt.fenster ? o.bruestung.toDouble() : 0.0;
          final oben = (o.art == OeffnungsArt.fenster ? o.bruestung + o.hoehe : o.hoehe).toDouble();
          hoehen = [if (unten > 1) (0.0, unten), if (oben < raumhoehe - 1) (oben, raumhoehe)];
          if (hoehe >= unten && hoehe <= oben) hoehen = [...hoehen, (-1, -1)]; // im Plan geschnitten: Lücke
        }
        segs.add(_Seg(p, q, nx, ny, hatKern(w) ? schichtenBei(w, links, mitte, z: hoehe) : const [], w.id, hoehen: hoehen));
      }
    }
  }
  // Nachbarn je Endpunkt (gleiche Punkte, 3 mm)
  String key(Punkt p) => '${(p.x / 3).round()}|${(p.y / 3).round()}';
  final anPunkt = <String, List<int>>{};
  for (final (i, s) in segs.indexed) {
    for (final p in [s.p, s.q]) {
      (anPunkt[key(p)] ??= []).add(i);
    }
  }
  int? nachbar(int i, Punkt p) {
    for (final j in anPunkt[key(p)] ?? const <int>[]) {
      if (j != i) return j;
    }
    return null;
  }

  final aus = <Aufbauband>[];
  for (final (i, s) in segs.indexed) {
    if (s.schichten.isEmpty) continue;
    final dir = s.q - s.p;
    final n = Punkt(s.nx, s.ny);
    final na = nachbar(i, s.p), nb = nachbar(i, s.q);
    // Eckpunkt in Tiefe [d] am Ende [p] mit Nachbar [j] (gleiche Schichtlage k)
    Punkt ecke(Punkt p, int? j, double d, int k) {
      final eigen = p + n * d;
      if (j == null) return eigen;
      final o = segs[j];
      final od = o.tiefe(k);
      final odir = o.q - o.p;
      final x = _schnitt(s.p + n * d, dir, o.p + Punkt(o.nx, o.ny) * od, odir);
      if (x == null || (x - eigen).laenge > 3 * math.max(d, od) + 50) return eigen; // gleichlaufend oder spitz: Absatz
      return x;
    }

    final luecke = s.hoehen != null && s.hoehen!.contains((-1.0, -1.0));
    for (var k = 0; k < s.schichten.length; k++) {
      final d0 = s.tiefe(k), d1 = s.tiefe(k + 1);
      if (d1 - d0 < 0.5) continue;
      aus.add((
        polygon: [ecke(s.p, na, d0, k), ecke(s.q, nb, d0, k), ecke(s.q, nb, d1, k + 1), ecke(s.p, na, d1, k + 1)],
        material: s.schichten[k].material,
        wandId: s.wandId,
        hoehen: s.hoehen == null ? null : [for (final h in s.hoehen!) if (h.$1 >= 0) h],
        aussen: k == s.schichten.length - 1,
        imPlan: !luecke,
      ));
    }
  }
  return aus;
}

/// Gesamtschichten einer Wand an Stelle [t] von Seite A nach B (für U-Wert,
/// Wärmebrücke, Mengen): Aufbau links (außen → Kern), Kern, Aufbau rechts.
List<AufbauSchicht> schichtenQuer(Wand w, double t, {double z = 1000}) => [
      ...schichtenBei(w, true, t, z: z).reversed,
      (material: kernMaterial(w), dicke: w.dicke),
      ...schichtenBei(w, false, t, z: z),
    ];
