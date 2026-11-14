import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../data/models.dart';
import 'raumerkennung.dart';

/// Leitungen im Bauteil: wie breit, wie tief und wie verlegt eine Leitung
/// (Kabel, Leerrohr, Rohrbündel) in der Wand bzw. im Boden liegt.
///
/// Gespeichert in `Objekt.eigenschaften`:
/// - `verlegung`: unterputz | schlitz | aufputz | vorwand | hohlwand | kanal
/// - `breite_mm`: Außenmaß quer (aus Rohr/Kabel oder von Hand, `breite_hand: true`)
/// - `tiefe_mm`: Überdeckung = Abstand von der fertigen Oberfläche bis zur
///   Vorderkante der Leitung (so tief darf man höchstens bohren)
/// - `schlitz_b`, `schlitz_t`: Schlitzmaße, wenn abweichend vom Vorschlag
enum Verlegung {
  unterputz('Unterputz (im Putz)', 10),
  schlitz('Im Wandschlitz', 15),
  aufputz('Aufputz (sichtbar)', 0),
  vorwand('In Vorwand / Installationsebene', 15),
  hohlwand('In Hohlwand (Ständerwand)', 13),
  kanal('Im Kabelkanal / Sockelleiste', 0);

  const Verlegung(this.label, this.ueberdeckung);
  final String label;

  /// Übliche Überdeckung in mm (Putz bzw. Beplankung vor der Leitung).
  final int ueberdeckung;

  /// Schlitz muss gestemmt/gefräst werden.
  bool get mitSchlitz => this == Verlegung.schlitz || this == Verlegung.unterputz;
}

/// Lage einer Leitung im Bauteil (alles in mm).
class LeitungImBauteil {
  const LeitungImBauteil({required this.verlegung, required this.breite, required this.ueberdeckung, this.schlitzBreite, this.schlitzTiefe});

  final Verlegung verlegung;
  final double breite; // Außenmaß der Leitung bzw. des Bündels
  final int ueberdeckung; // Oberfläche → Vorderkante der Leitung
  final int? schlitzBreite, schlitzTiefe; // von Hand gesetzt, sonst Vorschlag

  /// Tiefe der Leitungsachse ab Oberfläche.
  double get achsTiefe => ueberdeckung + breite / 2;

  /// Hinterkante der Leitung ab Oberfläche.
  double get hinterkante => ueberdeckung + breite;

  /// Schlitzbreite: Leitung + 10 mm Luft je Seite zum Einputzen (gerundet auf 5 mm).
  int get schlitzB => schlitzBreite ?? (verlegung.mitSchlitz ? ((breite + 20) / 5).ceil() * 5 : 0);

  /// Schlitztiefe ab Rohbau: Leitung + Überdeckung abzüglich Putzdicke [putz].
  int schlitzT({int putz = 10}) => schlitzTiefe ?? (verlegung.mitSchlitz ? math.max(0, (hinterkante - putz).ceil()) : 0);

  /// Bis zu dieser Tiefe kann laut Plan gebohrt werden, ohne die Leitung zu treffen.
  int get sicherBohren => math.max(0, ueberdeckung - 5);

  String get kurz {
    final b = breite.toStringAsFixed(breite % 1 == 0 ? 0 : 1).replaceAll('.', ',');
    return switch (verlegung) {
      Verlegung.aufputz || Verlegung.kanal => '${verlegung.label}, $b mm breit',
      _ => '${verlegung.label}, $b mm breit, $ueberdeckung mm tief (Vorderkante)',
    };
  }

  static LeitungImBauteil aus(Map<String, dynamic> eig, {String? lage}) {
    final v = Verlegung.values.where((x) => x.name == eig['verlegung']).firstOrNull ?? verlegungAusLage(lage);
    int? zahl(String k) => (eig[k] as num?)?.round();
    return LeitungImBauteil(
      verlegung: v,
      breite: math.max(0, (eig['breite_mm'] as num?)?.toDouble() ?? 0),
      ueberdeckung: zahl('tiefe_mm') ?? v.ueberdeckung,
      schlitzBreite: zahl('schlitz_b'),
      schlitzTiefe: zahl('schlitz_t'),
    );
  }
}

/// Vorgabe aus der Lage eines Objekts.
Verlegung verlegungAusLage(String? lage) => switch (lage) {
      'auf Wand' => Verlegung.aufputz,
      'in Vorwand' => Verlegung.vorwand,
      _ => Verlegung.unterputz,
    };

/// Richtwerte für Schlitze ohne statischen Nachweis in tragendem Mauerwerk
/// nach DIN EN 1996-1-1/NA (Tab. NA.19/NA.20), nachträglich hergestellt.
/// Liefert einen Hinweis oder null, wenn der Schlitz im Rahmen bleibt.
/// [senkrecht]: senkrechter Schlitz; sonst waagerecht/schräg mit [laenge].
String? schlitzPruefen({required int wanddicke, required int tiefe, required int breite, required bool senkrecht, double laenge = 0}) {
  if (tiefe <= 0) return null;
  if (senkrecht) {
    final (maxT, maxB) = switch (wanddicke) {
      < 115 => (0, 0),
      < 150 => (10, 100),
      < 175 => (20, 100),
      < 200 => (30, 100),
      < 240 => (30, 125),
      < 300 => (30, 150),
      _ => (30, 200),
    };
    if (maxT == 0) return 'Wand unter 11,5 cm: Schlitze nur mit Nachweis (oder Vorwand/Aufputz).';
    if (tiefe > maxT || breite > maxB) return 'Senkrechter Schlitz $tiefe × $breite mm über dem Richtwert ($maxT × $maxB mm bei ${wanddicke ~/ 10} cm Wand) – Statik prüfen.';
    return null;
  }
  final kurz = laenge <= 1250;
  final maxT = switch (wanddicke) {
    < 175 => 0,
    < 240 => kurz ? 25 : 0,
    < 300 => kurz ? 25 : 15,
    _ => kurz ? 30 : 20,
  };
  if (maxT == 0) return 'Waagerechter Schlitz in ${wanddicke ~/ 10}-cm-Wand ${kurz ? '' : 'über 1,25 m '}ohne Nachweis nicht zulässig – senkrecht führen oder Statik prüfen.';
  if (tiefe > maxT) return 'Waagerechter Schlitz $tiefe mm tief über dem Richtwert ($maxT mm) – Statik prüfen.';
  return 'Waagerechte Schlitze nur bis 40 cm unter/über der Rohdecke bzw. dem Rohfußboden (Richtwert).';
}

/// Ein Stück Leitung oder ein Gerät in einer Wandansicht (x ab linker
/// Wandkante, z absolut im Geschoss, mm). Linien haben x2/z2.
class WandTeil {
  const WandTeil({required this.id, required this.text, required this.x, this.z, this.x2, this.z2, this.breite = 0, this.ueberdeckung, this.durchgehend = false});
  final String id, text;
  final double x;
  final double? z, x2, z2;
  final double breite;
  final int? ueberdeckung; // null = unbekannt
  final bool durchgehend; // aus einem anderen Geschoss (Steigleitung)
  bool get istLinie => x2 != null;
}

/// Treffer beim Bohr-Check.
class BohrTreffer {
  const BohrTreffer(this.teil, this.abstand, this.hoeheBekannt);
  final WandTeil teil;

  /// Abstand von der Bohrstelle bis zur Außenkante der Leitung (mm, 0 = trifft).
  final double abstand;
  final bool hoeheBekannt;

  /// Wie tief darf hier höchstens gebohrt werden (null = nicht begrenzt / unbekannt).
  int? get maxBohrtiefe => abstand <= 0 && teil.ueberdeckung != null ? math.max(0, teil.ueberdeckung! - 5) : null;
}

double _strecke(Offset p, Offset a, Offset b) {
  final d = b - a;
  final l2 = d.dx * d.dx + d.dy * d.dy;
  if (l2 < 1e-9) return (p - a).distance;
  final t = (((p - a).dx * d.dx + (p - a).dy * d.dy) / l2).clamp(0.0, 1.0);
  return (a + d * t - p).distance;
}

/// Bohr-Check an einer Wandstelle [p] (x, z absolut): alles im Umkreis
/// [radius] mm, Abstand bis zur Leitungskante (halbe Breite abgezogen).
/// Ist die Höhe unbekannt, zählt nur der seitliche Abstand.
List<BohrTreffer> bohrCheck(Offset p, List<WandTeil> teile, {double radius = 300, double bohrer = 0}) {
  final aus = <BohrTreffer>[];
  for (final t in teile) {
    final bekannt = t.z != null && (!t.istLinie || t.z2 != null) && !t.durchgehend;
    double d;
    if (t.durchgehend) {
      d = (t.x - p.dx).abs();
    } else if (!bekannt) {
      d = t.istLinie
          ? (p.dx < math.min(t.x, t.x2!) ? math.min(t.x, t.x2!) - p.dx : (p.dx > math.max(t.x, t.x2!) ? p.dx - math.max(t.x, t.x2!) : 0))
          : (t.x - p.dx).abs();
    } else if (t.istLinie) {
      d = _strecke(p, Offset(t.x, t.z!), Offset(t.x2!, t.z2!));
    } else {
      d = (Offset(t.x, t.z!) - p).distance;
    }
    d = math.max(0, d - t.breite / 2 - bohrer / 2);
    if (d <= radius) aus.add(BohrTreffer(t, d, bekannt || t.durchgehend));
  }
  aus.sort((a, b) => a.abstand.compareTo(b.abstand));
  return aus;
}

/// Urteil zum Bohr-Check: (Stufe 0 frei, 1 Vorsicht, 2 nicht bohren; Text).
(int, String) bohrUrteil(List<BohrTreffer> treffer, {required bool inZone, int? bohrtiefe}) {
  final trifft = treffer.where((t) => t.abstand <= 0).toList();
  if (trifft.isNotEmpty) {
    final tiefen = [for (final t in trifft) t.maxBohrtiefe];
    if (tiefen.every((x) => x != null)) {
      final max = tiefen.cast<int>().reduce(math.min);
      if (bohrtiefe != null && bohrtiefe <= max) return (1, 'Leitung dahinter – mit $bohrtiefe mm Bohrtiefe noch frei (höchstens $max mm)');
      return (2, 'Nicht tiefer als $max mm bohren – dahinter liegt ${trifft.first.teil.text}');
    }
    return (2, 'Nicht bohren – ${trifft.first.teil.text} liegt hier (Tiefe unbekannt)');
  }
  if (treffer.any((t) => t.abstand < 100)) return (2, 'Nicht bohren – Leitung/Gerät näher als 10 cm');
  if (inZone) return (1, 'Vorsicht – Installationszone (hier dürfen Leitungen liegen)');
  if (treffer.isNotEmpty) return (1, 'Vorsicht – geplante Leitung/Gerät bis 30 cm');
  return (0, 'Laut Plan frei, außerhalb der Installationszonen');
}

/// Reihenfolge der Geschosse von unten nach oben: nach Kürzel (KG < EG < OG <
/// 2.OG … < DG < SB), sonst nach der Reihenfolge im Projekt.
List<Geschoss> geschossStapel(List<Geschoss> gs) {
  int rang(Geschoss g, int i) {
    final k = g.kuerzel.toUpperCase().replaceAll(' ', '').replaceAll('.', '');
    final n = int.tryParse(RegExp(r'^(\d+)').firstMatch(k)?.group(1) ?? '');
    if (k.startsWith('UG') || k.startsWith('KG')) return -100 - (n ?? 1);
    if (k.startsWith('EG')) return 0;
    if (k.contains('OG')) return 100 * (n ?? 1);
    if (k.startsWith('DG')) return 10000;
    if (k.startsWith('SB') || k.startsWith('SPB')) return 20000;
    return 50000 + i;
  }

  final mit = [for (final (i, g) in gs.indexed) (g, rang(g, i), i)]..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3));
  return [for (final e in mit) e.$1];
}

/// Höhe des Rohfußbodens jedes Geschosses über dem untersten (mm): Geschoss­
/// höhe RFB→Rohdecke plus Deckendicke ([decke], je Geschoss einstellbar).
Map<String, int> geschossSockel(List<Geschoss> gs, {int Function(Geschoss)? decke}) {
  final aus = <String, int>{};
  var h = 0;
  for (final g in geschossStapel(gs)) {
    aus[g.id] = h - g.hoehen.rfb;
    h += g.hoehen.rohdecke - g.hoehen.rfb + (decke?.call(g) ?? 200);
  }
  return aus;
}

/// Leitungen eines anderen Geschosses, die mit ihren Höhen (z_abs) in dieses
/// Geschoss hineinreichen: Stücke in Höhen dieses Geschosses ([unten]…[oben]).
/// [versatz] = Sockel(anderes) − Sockel(dieses).
List<List<(Punkt, double)>> leitungImGeschoss(Objekt o, int versatz, double unten, double oben) {
  final zs = o.zPunkte;
  if (zs == null || zs.length != o.punkte.length) return const [];
  final pts = [for (var i = 0; i < zs.length; i++) (o.punkte[i], zs[i] + versatz.toDouble())];
  final stuecke = <List<(Punkt, double)>>[];
  List<(Punkt, double)>? akt;
  (Punkt, double) bei((Punkt, double) a, (Punkt, double) b, double t) =>
      (Punkt(a.$1.x + (b.$1.x - a.$1.x) * t, a.$1.y + (b.$1.y - a.$1.y) * t), a.$2 + (b.$2 - a.$2) * t);
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], b = pts[i + 1];
    var t0 = 0.0, t1 = 1.0;
    final dz = b.$2 - a.$2;
    if (dz.abs() < 1e-9) {
      if (a.$2 < unten || a.$2 > oben) t1 = -1;
    } else {
      final ta = (unten - a.$2) / dz, tb = (oben - a.$2) / dz;
      t0 = math.max(t0, math.min(ta, tb));
      t1 = math.min(t1, math.max(ta, tb));
    }
    if (t1 < t0) {
      if (akt != null && akt.length >= 2) stuecke.add(akt);
      akt = null;
      continue;
    }
    final s = bei(a, b, t0), e = bei(a, b, t1);
    if (akt == null || t0 > 1e-9) {
      if (akt != null && akt.length >= 2) stuecke.add(akt);
      akt = [s];
    }
    akt.add(e);
    if (t1 < 1 - 1e-9) {
      if (akt.length >= 2) stuecke.add(akt);
      akt = null;
    }
  }
  if (akt != null && akt.length >= 2) stuecke.add(akt);
  return stuecke;
}
