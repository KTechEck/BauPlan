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
import '../data/project_store.dart';
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
({Map<String, Object?> eigenschaften, int kern, double versatz}) ausWandtyp(List<Schicht> schichten, {int? kern}) {
  if (schichten.isEmpty) return (eigenschaften: {'kern': {'d': 0}}, kern: 0, versatz: 0);
  var k = 0;
  for (var i = 1; i < schichten.length; i++) {
    if (schichten[i].dicke > schichten[k].dicke) k = i;
  }
  if (kern != null && kern >= 0 && kern < schichten.length) k = kern;
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
List<Aufbauband> aufbauBaender(List<Wand> waende,
    {bool verbindenStandard = true, double hoehe = 1000, List<Oeffnung> oeffnungen = const [], double raumhoehe = 2600, String? Function(String? id)? baustoffName}) {
  final kerne = [for (final w in waende) if (hatKern(w) && !w.istKante && w.laenge > 1) w];
  if (kerne.isEmpty) return const [];
  final alle = [for (final w in waende) if (!w.istKante && !w.teilhoch) w];
  // dieselben Achsen-Objekte verwenden (wandUmriss erkennt die eigene Wand an der Identität)
  final achse = {for (final w in alle) w.id: w.achse};
  final nachbarn = [for (final w in alle) if (w.verbinden ?? verbindenStandard) achse[w.id]!];
  // Seitenflächen, an Bereichsgrenzen geteilt
  final segs = <_Seg>[];
  final umrisse = wandUmrisse(waende, verbindenStandard: verbindenStandard, baustoffName: baustoffName);
  for (final w in alle) {
    if (w.laenge < 1) continue;
    final u = umrisse[w.id] ?? wandUmriss(achse[w.id]!, (w.verbinden ?? verbindenStandard) ? nachbarn : [achse[w.id]!]);
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

// ------------------------------------------------------------ Wandanschluss

/// Anschluss einer Wand an einem Ende: Gehrung, stumpf (stößt an die andere
/// Wand), durch (läuft durch, die andere stößt an), eingebunden (stößt an und
/// greift [tiefe] mm in die andere Wand). `auto` = nach Baustoff (Leichtbau
/// stößt stumpf an Massivwand, sonst Gehrung).
enum AnschlussArt { auto, gehrung, stumpf, durch, eingebunden }

typedef Anschluss = ({AnschlussArt art, int tiefe, bool schichtenDurch});

Anschluss anschlussVon(Wand w, bool amAnfang) {
  final m = w.eigenschaften[amAnfang ? 'anschluss_a' : 'anschluss_b'];
  if (m is! Map) return (art: AnschlussArt.auto, tiefe: 0, schichtenDurch: false);
  return (
    art: AnschlussArt.values.where((a) => a.name == m['art']).firstOrNull ?? AnschlussArt.auto,
    tiefe: (m['tiefe'] as num?)?.toInt() ?? 0,
    schichtenDurch: m['schichten'] == true,
  );
}

Map<String, Object?> anschlussJson(Anschluss a) => {'art': a.art.name, if (a.tiefe > 0) 'tiefe': a.tiefe, if (a.schichtenDurch) 'schichten': true};

/// Leichtbau (Ständerwand, GK, Holz) erkennen.
bool istLeichtbau(String? name) {
  final t = (name ?? '').toLowerCase();
  return ['ständer', 'staender', 'gipskarton', 'gk', 'trockenbau', 'holz', 'metallständer', 'cw-', 'uw-', 'osb', 'fermacell', 'gipsfaser'].any(t.contains);
}

/// Nachbarwand, die an einem Ende einer Wand anschließt (Ende an Ende, nicht parallel).
Wand? anschlussNachbar(Wand w, bool amAnfang, List<Wand> alle) {
  final x = amAnfang ? w.x1 : w.x2, y = amAnfang ? w.y1 : w.y2;
  for (final o in alle) {
    if (o.id == w.id || o.istKante || o.teilhoch || o.laenge < 1) continue;
    final trifft = ((o.x1 - x).abs() <= 3 && (o.y1 - y).abs() <= 3) || ((o.x2 - x).abs() <= 3 && (o.y2 - y).abs() <= 3);
    if (!trifft) continue;
    final kreuz = ((w.x2 - w.x1) * (o.y2 - o.y1) - (w.y2 - w.y1) * (o.x2 - o.x1)).abs() / (w.laenge * o.laenge);
    if (kreuz < 0.05) continue; // gleichlaufend
    return o;
  }
  return null;
}

/// Wirksame Anschlussart an einem Ende (eigene Einstellung, sonst aus der
/// Einstellung der Nachbarwand abgeleitet, sonst nach Baustoff).
({AnschlussArt art, int tiefe}) anschlussWirksam(Wand w, bool amAnfang, Wand o, {String? Function(String? id)? baustoffName}) {
  final eigen = anschlussVon(w, amAnfang);
  if (eigen.art != AnschlussArt.auto) return (art: eigen.art, tiefe: eigen.tiefe);
  final oAnfang = (o.x1 - (amAnfang ? w.x1 : w.x2)).abs() <= 3 && (o.y1 - (amAnfang ? w.y1 : w.y2)).abs() <= 3;
  final fremd = anschlussVon(o, oAnfang).art;
  switch (fremd) {
    case AnschlussArt.stumpf || AnschlussArt.eingebunden:
      return (art: AnschlussArt.durch, tiefe: 0);
    case AnschlussArt.durch:
      return (art: AnschlussArt.stumpf, tiefe: 0);
    case AnschlussArt.gehrung:
      return (art: AnschlussArt.gehrung, tiefe: 0);
    case AnschlussArt.auto:
      final l1 = istLeichtbau(baustoffName?.call(kernMaterial(w))), l2 = istLeichtbau(baustoffName?.call(kernMaterial(o)));
      if (l1 && !l2) return (art: AnschlussArt.stumpf, tiefe: 0);
      if (l2 && !l1) return (art: AnschlussArt.durch, tiefe: 0);
      return (art: AnschlussArt.gehrung, tiefe: 0);
  }
}

/// Umrisse aller Wände mit verschnittenen Ecken und den eingestellten
/// Anschlüssen (stumpf/durch/eingebunden statt Gehrung). Offene Kanten und
/// teilhohe Wände zählen nicht als Nachbarn.
Map<String, List<Punkt>> wandUmrisse(List<Wand> waende, {bool verbindenStandard = true, String? Function(String? id)? baustoffName}) {
  final achse = {for (final w in waende) w.id: w.achse};
  final verb = {for (final w in waende) w.id: w.verbinden ?? verbindenStandard};
  final nachbarn = [for (final w in waende) if (verb[w.id]! && !w.istKante) achse[w.id]!];
  final aus = <String, List<Punkt>>{};
  for (final w in waende) {
    final u = [...wandUmriss(achse[w.id]!, verb[w.id]! ? nachbarn : [achse[w.id]!])];
    if (verb[w.id]! && !w.istKante && !w.teilhoch && w.laenge > 1) {
      final l = w.laenge;
      final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
      for (final amAnfang in [true, false]) {
        final o = anschlussNachbar(w, amAnfang, waende);
        if (o == null || !verb[o.id]!) continue;
        final a = anschlussWirksam(w, amAnfang, o, baustoffName: baustoffName);
        if (a.art == AnschlussArt.gehrung) continue;
        // gerades Ende ohne diesen Nachbarn, dann um die halbe Dicke der anderen Wand verschieben
        final gerade = wandUmriss(achse[w.id]!, [for (final n in nachbarn) if (!identical(n, achse[o.id])) n]);
        final sin = (((w.x2 - w.x1) * (o.y2 - o.y1) - (w.y2 - w.y1) * (o.x2 - o.x1)) / (l * o.laenge)).abs().clamp(0.2, 1.0);
        final halb = o.dicke / 2 / sin;
        final d = switch (a.art) {
          AnschlussArt.stumpf => -halb,
          AnschlussArt.durch => halb,
          AnschlussArt.eingebunden => -halb + a.tiefe,
          _ => 0.0,
        };
        final s = amAnfang ? -d : d;
        final (i, j) = amAnfang ? (0, 3) : (1, 2);
        u[i] = gerade[i] + Punkt(ux, uy) * s;
        u[j] = gerade[j] + Punkt(ux, uy) * s;
      }
    }
    aus[w.id] = u;
  }
  return aus;
}


// ------------------------------------------------------------ Aufbau-Vorlagen

typedef AufbauVorlage = ({String name, List<AufbauSchicht> schichten});

/// Aufbau-Vorlagen des Projekts (Einstellung `aufbau_vorlagen`).
List<AufbauVorlage> aufbauVorlagen(ProjectStore store) => [
      for (final v in (store.einstellung<List>('aufbau_vorlagen') ?? const []))
        if (v is Map)
          (
            name: '${v['name'] ?? 'Vorlage'}',
            schichten: [
              for (final s in (v['s'] as List? ?? const []))
                if (s is Map) (material: s['m'] as String?, dicke: (s['d'] as num?)?.toInt() ?? 0),
            ],
          ),
    ];

void aufbauVorlagenSetzen(ProjectStore store, List<AufbauVorlage> l) => store.einstellungSetzen('aufbau_vorlagen', [
      for (final v in l) {'name': v.name, 's': [for (final s in v.schichten) {'m': s.material, 'd': s.dicke}]},
    ]);
