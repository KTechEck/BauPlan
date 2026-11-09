import 'dart:math' as math;

import '../data/schrank_models.dart';

/// Stromlaufplan in aufgelöster Darstellung (Normstufe B): Sammelschienen
/// oben, je Schutzorgan ein senkrechter Strompfad, Betriebsmittelkennzeichen
/// nach DIN EN 81346, Schaltzeichen angelehnt an DIN EN 60617, Blätter A3 quer
/// mit Spalteneinteilung und Schriftfeld. Alle Maße in mm auf dem Blatt; die
/// Zeichnung wird einmal erzeugt und von Bildschirm und PDF gleich gezeichnet.

// ------------------------------------------------------------ Zeichenelemente

sealed class Zeichen {
  const Zeichen();
}

class ZLinie extends Zeichen {
  const ZLinie(this.x1, this.y1, this.x2, this.y2, {this.dicke = 0.25, this.strich = false, this.strichpunkt = false});
  final double x1, y1, x2, y2, dicke;
  final bool strich, strichpunkt;
}

class ZKreis extends Zeichen {
  const ZKreis(this.x, this.y, this.r, {this.gefuellt = false, this.dicke = 0.25});
  final double x, y, r, dicke;
  final bool gefuellt;
}

class ZEllipse extends Zeichen {
  const ZEllipse(this.x, this.y, this.rx, this.ry, {this.dicke = 0.25});
  final double x, y, rx, ry, dicke;
}

class ZRechteck extends Zeichen {
  const ZRechteck(this.x, this.y, this.b, this.h, {this.dicke = 0.25, this.strich = false});
  final double x, y, b, h, dicke;
  final bool strich;
}

class ZPolylinie extends Zeichen {
  const ZPolylinie(this.punkte, {this.dicke = 0.25});
  final List<(double, double)> punkte;
  final double dicke;
}

enum Ausrichtung { links, mitte, rechts }

/// Text; [y] ist die Grundlinie, [groesse] die Schrifthöhe in mm.
class ZText extends Zeichen {
  const ZText(this.x, this.y, this.text, {this.groesse = 2.0, this.ausrichtung = Ausrichtung.links, this.fett = false});
  final double x, y, groesse;
  final String text;
  final Ausrichtung ausrichtung;
  final bool fett;
}

class SlpBlatt {
  SlpBlatt(this.nr, this.titel);
  final int nr;
  final String titel;
  final List<Zeichen> zeichen = [];
}

/// Verbraucher eines Stromkreises (aus den Objekten der Installation).
typedef SlpVerbraucher = ({String kennung, String kuerzel, String typ, String raum, String? knxKanal});

class Stromlaufplan {
  Stromlaufplan(this.blaetter, this.orte, this.hinweise);
  final List<SlpBlatt> blaetter;

  /// Darstellungsort je Gerät (id) als „Blatt.Spalte“, für Querverweise.
  final Map<String, List<String>> orte;
  final List<String> hinweise;
}

const blattBreite = 420.0, blattHoehe = 297.0;
const slpSpalten = 14;
const _xs = 26.0, _cw = 27.0;
const _rechts = _xs + slpSpalten * _cw; // 404
const _yBus = {'L1': 24.0, 'L2': 29.0, 'L3': 34.0, 'N': 39.0, 'PE': 44.0};
const _ySub = {'L1': 80.0, 'L2': 84.0, 'L3': 88.0, 'N': 92.0};
const _ySchalter = 100.0, _yKontakt = 118.0, _yGrenze = 136.0, _yKlemme = 140.0, _yLast = 178.0;

double spalteX(int spalte) => _xs + spalte * _cw;

/// Zeilenumbruch nach Wörtern auf höchstens [breite] Zeichen.
List<String> umbrechen(String text, int breite, {int maxZeilen = 3}) {
  final zeilen = <String>[];
  var z = '';
  for (final w in text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
    if (z.isEmpty) {
      z = w;
    } else if (z.length + 1 + w.length <= breite) {
      z = '$z $w';
    } else {
      zeilen.add(z);
      z = w;
    }
  }
  if (z.isNotEmpty) zeilen.add(z);
  if (zeilen.length > maxZeilen) {
    final rest = zeilen.sublist(0, maxZeilen);
    rest[maxZeilen - 1] = '${rest[maxZeilen - 1].substring(0, math.min(rest[maxZeilen - 1].length, breite - 3))}...';
    return rest;
  }
  return [for (final z in zeilen) z.length > breite ? '${z.substring(0, breite - 3)}...' : z];
}

/// Stromlaufplan eines Schranks erzeugen.
Stromlaufplan stromlaufplanErzeugen({
  required Schrank schrank,
  required List<SchrankGeraet> geraete,
  required List<Stromkreis> kreise,
  Map<String, List<SlpVerbraucher>> verbraucher = const {},
  String projekt = '',
  DateTime? datum,
}) =>
    _Bauer(schrank, geraete, kreise, verbraucher, projekt, datum ?? DateTime.now()).bauen();

class _Bauer {
  _Bauer(this.s, this.geraete, this.kreise, this.verbraucher, this.projekt, this.datum);
  final Schrank s;
  final List<SchrankGeraet> geraete;
  final List<Stromkreis> kreise;
  final Map<String, List<SlpVerbraucher>> verbraucher;
  final String projekt;
  final DateTime datum;

  final blaetter = <SlpBlatt>[];
  final orte = <String, List<String>>{};
  final hinweise = <String>[];
  late SlpBlatt blatt;
  int spalte = 0;
  late final nachId = {for (final g in geraete) g.id: g};

  List<Zeichen> get z => blatt.zeichen;

  void ort(String id, [String? zusatz]) => orte.putIfAbsent(id, () => []).add('${blatt.nr}.${spalte + 1}${zusatz ?? ''}');

  void neuesBlatt(String titel, {bool schienen = true}) {
    blatt = SlpBlatt(blaetter.length + 1, titel);
    blaetter.add(blatt);
    spalte = 0;
    if (schienen) _sammelschienen();
  }

  int _sortierung(SchrankGeraet a, SchrankGeraet b) => a.reihe != b.reihe ? a.reihe.compareTo(b.reihe) : a.position.compareTo(b.position);

  Stromlaufplan bauen() {
    final sortiert = [...geraete]..sort(_sortierung);
    neuesBlatt('Einspeisung und Stromkreise');
    _einspeisung(sortiert.where((g) => g.art == GeraeteArt.hauptschalter).firstOrNull);
    for (final g in sortiert.where((g) => g.art == GeraeteArt.spd)) {
      _platz(1);
      _spd(g);
    }
    final rcds = sortiert.where((g) => g.art == GeraeteArt.rcd).toList();
    final inGruppe = <String>{};
    for (final r in rcds) {
      final kinder = [for (final g in sortiert) if (g.vorgeschaltetId == r.id && (g.art == GeraeteArt.ls || g.art == GeraeteArt.fils)) g];
      inGruppe.addAll(kinder.map((k) => k.id));
      _gruppe(r, kinder);
    }
    for (final g in sortiert) {
      if ((g.art == GeraeteArt.ls || g.art == GeraeteArt.fils) && !inGruppe.contains(g.id)) {
        _platz(1);
        _abgang(g, null);
        spalte++;
      }
    }
    for (final k in kreise) {
      if (nachId[k.schutzId] == null) hinweise.add('Stromkreis ${k.nummer} ${k.bezeichnung}: kein Schutzorgan – nicht im Plan.');
    }
    _betriebsmittelliste(sortiert);
    for (final b in blaetter) {
      _rahmen(b);
    }
    return Stromlaufplan(blaetter, orte, hinweise);
  }

  void _platz(int n) {
    if (spalte + n > slpSpalten) neuesBlatt('Stromkreise');
  }

  // ------------------------------------------------------------ Grundgerüst

  void _sammelschienen() {
    for (final e in _yBus.entries) {
      z.add(ZText(_xs - 5, e.value + 0.8, e.key, groesse: 2.2, fett: true));
      z.add(ZLinie(_xs - 1, e.value, _rechts, e.value, dicke: 0.35));
    }
    // Schrankgrenze zwischen Verteiler und Abgängen
    z.add(const ZLinie(_xs - 1, _yGrenze, _rechts, _yGrenze, dicke: 0.25, strichpunkt: true));
    z.add(ZText(_xs - 5, _yGrenze - 1.2, '=${s.kennzeichen}', groesse: 1.8));
    z.add(const ZText(_xs - 5, _yGrenze + 3, 'Abgang', groesse: 1.8));
  }

  void _rahmen(SlpBlatt b) {
    final zz = b.zeichen;
    zz.add(const ZRechteck(20, 10, 390, 277, dicke: 0.5));
    // Spaltenkopf
    zz.add(const ZRechteck(_xs, 10, slpSpalten * _cw, 6, dicke: 0.25));
    for (var i = 0; i < slpSpalten; i++) {
      if (i > 0) zz.add(ZLinie(spalteX(i), 10, spalteX(i), 16));
      zz.add(ZText(spalteX(i) + _cw / 2, 14.2, '${i + 1}', groesse: 2.5, ausrichtung: Ausrichtung.mitte));
    }
    // Fortsetzung der Sammelschienen
    if (b.titel != 'Betriebsmittelliste') {
      final naechstes = blaetter.where((x) => x.nr == b.nr + 1 && x.titel != 'Betriebsmittelliste').firstOrNull;
      if (naechstes != null) {
        for (final y in _yBus.values) {
          zz.add(ZText(_rechts + 0.8, y + 0.7, '/${naechstes.nr}.1', groesse: 1.6));
        }
      }
    }
    // Schriftfeld
    const y0 = 262.0, h = 25.0;
    zz.add(const ZRechteck(20, y0, 390, h, dicke: 0.5));
    void feld(double x, double b2, String titel, String wert, {double groesse = 3.2}) {
      zz.add(ZLinie(x, y0, x, y0 + h, dicke: 0.35));
      zz.add(ZText(x + 1.5, y0 + 3.5, titel, groesse: 1.8));
      final zeilen = umbrechen(wert, ((b2 - 3) / (groesse * 0.75)).floor(), maxZeilen: 2);
      for (var i = 0; i < zeilen.length; i++) {
        zz.add(ZText(x + 1.5, y0 + 10 + i * (groesse + 1.5), zeilen[i], groesse: groesse, fett: i == 0));
      }
    }

    feld(20, 100, 'Projekt', projekt.isEmpty ? '-' : projekt);
    feld(120, 100, 'Anlage', '=${s.kennzeichen}  ${s.name}');
    feld(220, 110, 'Inhalt', b.titel);
    final d = '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year}';
    feld(330, 45, 'Datum / Norm', d, groesse: 3);
    zz.add(const ZText(331.5, y0 + 20, 'DIN EN 81346 / 60617', groesse: 1.8));
    zz.add(const ZText(331.5, y0 + 23, 'erstellt mit BauSpur', groesse: 1.6));
    feld(375, 35, 'Blatt', '${b.nr} von ${blaetter.length}', groesse: 3.5);
  }

  // ------------------------------------------------------------ Schaltzeichen

  void _punkt(double x, double y) => z.add(ZKreis(x, y, 0.55, gefuellt: true));

  /// Schalter/Kontakt senkrecht von [y] bis [y]+10 (offen gezeichnet).
  /// [kreuz]: Leistungs-/Leitungsschutzschalter; [kreis]: Lasttrennschalter.
  void _schalter(double x, double y, {bool kreuz = false, bool kreis = false}) {
    z.add(ZLinie(x, y, x, y + 2));
    z.add(ZLinie(x, y + 10, x - 3.2, y + 2.6, dicke: 0.3));
    if (kreuz) {
      z.add(ZLinie(x - 0.9, y + 1.1, x + 0.9, y + 2.9));
      z.add(ZLinie(x - 0.9, y + 2.9, x + 0.9, y + 1.1));
    }
    if (kreis) z.add(ZKreis(x, y + 2, 0.7));
  }

  /// Wirkverbindung (mechanisch) zwischen Schaltern, gestrichelt.
  void _wirklinie(double x1, double x2, double y) => z.add(ZLinie(x1 - 1.6, y, x2, y, strich: true));

  /// Leiterpositionen in einer Spalte.
  Map<String, double> _leiterX(double x0, List<String> phasen, {bool pe = true}) {
    if (phasen.length >= 3) return {'L1': x0 + 3, 'L2': x0 + 6, 'L3': x0 + 9, 'N': x0 + 12, if (pe) 'PE': x0 + 15};
    return {phasen.first: x0 + 4, 'N': x0 + 8, if (pe) 'PE': x0 + 12};
  }

  List<String> _phasen(SchrankGeraet g) =>
      (g.phase == '3P' || g.pole >= 3 || g.art == GeraeteArt.hauptschalter) ? const ['L1', 'L2', 'L3'] : [g.phase ?? 'L1'];

  // ------------------------------------------------------------ Strompfade

  void _einspeisung(SchrankGeraet? haupt) {
    final x0 = spalteX(spalte);
    final lx = _leiterX(x0, const ['L1', 'L2', 'L3']);
    const yUnten = 172.0;
    for (final e in lx.entries) {
      _punkt(e.value, _yBus[e.key]!);
      final schaltet = haupt != null && e.key.startsWith('L');
      if (schaltet) {
        z.add(ZLinie(e.value, _yBus[e.key]!, e.value, _ySchalter));
        _schalter(e.value, _ySchalter, kreis: true);
        z.add(ZLinie(e.value, _ySchalter + 10, e.value, yUnten));
      } else {
        z.add(ZLinie(e.value, _yBus[e.key]!, e.value, yUnten));
      }
    }
    for (final e in lx.entries) {
      z.add(ZText(e.value, yUnten + 3, e.key, groesse: 1.6, ausrichtung: Ausrichtung.mitte));
    }
    if (haupt != null) {
      _wirklinie(lx['L1']!, lx['L3']!, _ySchalter + 6);
      ort(haupt.id);
      final xt = lx['PE']! + 2;
      z.add(ZText(xt, _ySchalter + 3, haupt.kennzeichen, groesse: 2.2, fett: true));
      z.add(ZText(xt, _ySchalter + 6.5, haupt.kurz, groesse: 1.8));
    }
    z.add(ZText(x0 + 1, yUnten + 8, 'Einspeisung', groesse: 2.2, fett: true));
    z.add(ZText(x0 + 1, yUnten + 11.5, 'vom Zähler / HAK', groesse: 1.8));
    if (s.eigenschaften['einspeisung'] is String) z.add(ZText(x0 + 1, yUnten + 14.5, s.eigenschaften['einspeisung'] as String, groesse: 1.8));
    spalte++;
  }

  void _spd(SchrankGeraet g) {
    final x0 = spalteX(spalte);
    final lx = _leiterX(x0, const ['L1', 'L2', 'L3']);
    for (final l in const ['L1', 'L2', 'L3', 'N']) {
      _punkt(lx[l]!, _yBus[l]!);
      z.add(ZLinie(lx[l]!, _yBus[l]!, lx[l]!, _ySchalter));
    }
    z.add(ZRechteck(x0 + 1.5, _ySchalter, 12, 10));
    z.add(ZText(x0 + 7.5, _ySchalter + 6, 'SPD', groesse: 2.2, ausrichtung: Ausrichtung.mitte, fett: true));
    // Erdung auf PE
    final xp = lx['PE']!;
    z.add(ZPolylinie([(x0 + 7.5, _ySchalter + 10), (x0 + 7.5, _ySchalter + 14), (xp, _ySchalter + 14), (xp, _yBus['PE']!)]));
    _punkt(xp, _yBus['PE']!);
    z.add(ZText(xp + 2, _ySchalter + 3, g.kennzeichen, groesse: 2.2, fett: true));
    for (final (i, t) in umbrechen(g.bezeichnung, 9, maxZeilen: 3).indexed) {
      z.add(ZText(xp + 2, _ySchalter + 6.5 + i * 2.6, t, groesse: 1.7));
    }
    ort(g.id);
    spalte++;
  }

  void _gruppe(SchrankGeraet rcd, List<SchrankGeraet> kinder) {
    if (spalte > slpSpalten - 2) neuesBlatt('Stromkreise');
    final phasen = (rcd.pole >= 3 || rcd.phase == '3P') ? const ['L1', 'L2', 'L3'] : [rcd.phase ?? 'L1'];
    final x0 = spalteX(spalte);
    final lx = _leiterX(x0, phasen, pe: false);
    const yS = 50.0;
    for (final e in lx.entries) {
      _punkt(e.value, _yBus[e.key]!);
      z.add(ZLinie(e.value, _yBus[e.key]!, e.value, yS));
      _schalter(e.value, yS);
      z.add(ZLinie(e.value, yS + 10, e.value, _ySub[e.key]!));
      _punkt(e.value, _ySub[e.key]!);
    }
    final xa = lx.values.reduce(math.min), xb = lx.values.reduce(math.max);
    _wirklinie(xa, xb + 3, yS + 6);
    z.add(ZEllipse((xa + xb) / 2, yS + 15, (xb - xa) / 2 + 2, 1.8));
    // Auslöser
    z.add(ZRechteck(xb + 3, yS + 4, 5, 4));
    z.add(ZText(xb + 5.5, yS + 7, 'I', groesse: 2, ausrichtung: Ausrichtung.mitte));
    z.add(ZLinie(xb + 5.5, yS + 8, xb + 5.5, yS + 13.2, strich: true));
    z.add(ZLinie(xb + 5.5, yS + 13.2, (xa + xb) / 2 + (xb - xa) / 2 + 2, yS + 15, strich: true));
    ort(rcd.id);
    z.add(ZText(x0 + 1, _ySchalter + 2, rcd.kennzeichen, groesse: 2.4, fett: true));
    z.add(ZText(x0 + 1, _ySchalter + 5.5, 'FI ${rcd.nennstrom ?? 40} A', groesse: 1.8));
    z.add(ZText(x0 + 1, _ySchalter + 8.5, '${rcd.fehlerstrom ?? 30} mA', groesse: 1.8));
    if (rcd.eigenschaften['typ'] is String) z.add(ZText(x0 + 1, _ySchalter + 11.5, 'Typ ${rcd.eigenschaften['typ']}', groesse: 1.8));
    if (kinder.isEmpty) z.add(ZText(x0 + 1, _ySchalter + 15, '(keine Abgänge)', groesse: 1.6));
    final start = {for (final e in lx.entries) e.key: e.value};
    spalte++;
    final bisX = <String, double>{};
    var ersterTeil = true;
    void schienenZiehen({bool weiter = false}) {
      for (final e in start.entries) {
        final bis = weiter ? _rechts : (bisX[e.key] ?? e.value);
        if (bis > e.value) z.add(ZLinie(e.value, _ySub[e.key]!, bis, _ySub[e.key]!, dicke: 0.3));
        if (weiter) z.add(ZText(_rechts + 0.8, _ySub[e.key]! + 0.7, '/${blatt.nr + 1}.1', groesse: 1.6));
      }
      // Kennung der Unterverteilung an der Schiene
      if (ersterTeil) z.add(ZText(start.values.reduce(math.max) + 2.5, _ySub['N']! - 1, '${rcd.kennzeichen}:2', groesse: 1.6));
    }

    for (final k in kinder) {
      if (spalte >= slpSpalten) {
        schienenZiehen(weiter: true);
        final vorher = blatt.nr;
        neuesBlatt('Stromkreise');
        ersterTeil = false;
        for (final l in start.keys) {
          z.add(ZText(_xs - 5, _ySub[l]! + 0.7, l, groesse: 1.8));
          start[l] = _xs - 1;
        }
        z.add(ZText(_xs, start.keys.map((l) => _ySub[l]!).reduce(math.min) - 2, 'von /$vorher (${rcd.kennzeichen})', groesse: 1.6));
        bisX.clear();
      }
      for (final e in _abgang(k, phasen).entries) {
        if (_ySub.containsKey(e.key)) bisX[e.key] = math.max(bisX[e.key] ?? 0, e.value);
      }
      spalte++;
    }
    schienenZiehen();
  }

  /// Abgang mit Schutzorgan [g]; [gruppe] = Phasen der FI-Unterschiene
  /// (null: direkt von den Sammelschienen). Gibt die Leiter-x zurück.
  Map<String, double> _abgang(SchrankGeraet g, List<String>? gruppe) {
    final x0 = spalteX(spalte);
    var phasen = _phasen(g);
    if (gruppe != null && phasen.any((p) => !gruppe.contains(p))) {
      hinweise.add('${g.kennzeichen}: Phase ${phasen.join('/')} liegt nicht am vorgeschalteten FI – an ${gruppe.first} gezeichnet.');
      phasen = phasen.length >= 3 ? gruppe : [gruppe.first];
    }
    final lx = _leiterX(x0, phasen);
    final quelle = gruppe == null ? _yBus : _ySub;
    final fils = g.art == GeraeteArt.fils;
    ort(g.id);
    // Zuleitungen
    for (final p in phasen) {
      _punkt(lx[p]!, quelle[p]!);
      z.add(ZLinie(lx[p]!, quelle[p]!, lx[p]!, _ySchalter));
      _schalter(lx[p]!, _ySchalter, kreuz: true);
    }
    final xn = lx['N']!, xpe = lx['PE']!;
    _punkt(xn, quelle['N']!);
    if (fils) {
      z.add(ZLinie(xn, quelle['N']!, xn, _ySchalter));
      _schalter(xn, _ySchalter);
      z.add(ZEllipse((lx[phasen.first]! + xn) / 2, _ySchalter + 14, (xn - lx[phasen.first]!) / 2 + 2, 1.6));
      z.add(ZLinie(xn, _ySchalter + 10, xn, _yLast));
    } else {
      z.add(ZLinie(xn, quelle['N']!, xn, _yLast));
    }
    if (phasen.length > 1 || fils) _wirklinie(lx[phasen.first]!, fils ? xn : lx[phasen.last]!, _ySchalter + 6);
    _punkt(xpe, _yBus['PE']!);
    z.add(ZLinie(xpe, _yBus['PE']!, xpe, _yLast));
    final xt = xpe + 2;
    z.add(ZText(xt, _ySchalter + 3, g.kennzeichen, groesse: 2.4, fett: true));
    z.add(ZText(xt, _ySchalter + 6.5, '${g.charakteristik ?? 'B'}${g.nennstrom ?? 16}', groesse: 1.9));
    if (fils) z.add(ZText(xt, _ySchalter + 9.5, '${g.fehlerstrom ?? 30} mA', groesse: 1.8));

    // Stromkreis(e) und Verbraucher
    final ks = [for (final k in kreise) if (k.schutzId == g.id) k];
    final k = ks.firstOrNull;
    final vb = [for (final x in ks) ...?verbraucher[x.id]];
    // KNX-Aktorkontakt
    final kanaele = <String>{for (final v in vb) if (v.knxKanal != null && v.knxKanal!.contains(':')) v.knxKanal!}.toList()..sort();
    final xl = lx[phasen.first]!;
    for (final p in phasen) {
      final mitKontakt = p == phasen.first && kanaele.isNotEmpty;
      if (mitKontakt) {
        z.add(ZLinie(xl, _ySchalter + 10, xl, _yKontakt));
        _schalter(xl, _yKontakt);
        z.add(ZLinie(xl, _yKontakt + 10, xl, _yLast));
      } else {
        z.add(ZLinie(lx[p]!, _ySchalter + 10, lx[p]!, _yLast));
      }
    }
    if (kanaele.isNotEmpty) {
      final teile = kanaele.first.split(':');
      final aktor = nachId[teile.first];
      z.add(ZText(xt, _yKontakt + 3, aktor?.kennzeichen ?? '-K?', groesse: 2.2, fett: true));
      z.add(ZText(xt, _yKontakt + 6.5, 'Kanal ${teile.last}', groesse: 1.8));
      if (kanaele.length > 1) z.add(ZText(xt, _yKontakt + 9.5, '+${kanaele.length - 1} Kanäle', groesse: 1.6));
      if (aktor != null) ort(aktor.id, ':${teile.last}');
    }
    // Klemmen
    final klemme = k == null ? null : geraete.where((x) => x.art == GeraeteArt.klemme && x.eigenschaften['stromkreis'] == k.id).firstOrNull;
    if (klemme != null) {
      for (final x in lx.values) {
        z.add(ZKreis(x, _yKlemme, 0.9));
      }
      z.add(ZText(xt, _yKlemme + 0.8, klemme.kennzeichen, groesse: 2, fett: true));
      ort(klemme.id);
    }
    // Leitung
    if (k != null) {
      z.add(ZText(xt, _yKlemme + 9, '-W${k.nummer}', groesse: 2, fett: true));
      for (final (i, t) in umbrechen(k.leitung, 9, maxZeilen: 3).indexed) {
        z.add(ZText(xt, _yKlemme + 12.5 + i * 2.6, t, groesse: 1.7));
      }
    }
    // Verbraucher
    final xa = lx.values.reduce(math.min) - 2, xb = xpe + 2;
    final kuerzel = vb.isEmpty ? '' : (vb.map((v) => v.kuerzel).toSet().length == 1 ? vb.first.kuerzel : 'gemischt');
    _last(xa, xb, kuerzel, k == null);
    var y = _yLast + 18;
    void zeile(String t, {bool fett = false, double groesse = 1.8}) {
      z.add(ZText(x0 + 1, y, t, groesse: groesse, fett: fett));
      y += groesse + 1.0;
    }

    if (k == null) {
      zeile('Reserve', fett: true, groesse: 2.2);
    } else {
      zeile('SK ${k.nummer}', fett: true, groesse: 2.4);
      for (final t in umbrechen(k.bezeichnung.isEmpty ? '-' : k.bezeichnung, 18, maxZeilen: 2)) {
        zeile(t, groesse: 2);
      }
      if (ks.length > 1) zeile('+ ${ks.skip(1).map((e) => 'SK ${e.nummer}').join(', ')}');
      if (vb.isNotEmpty) {
        final anzahl = <String, int>{};
        for (final v in vb) {
          anzahl[v.kuerzel] = (anzahl[v.kuerzel] ?? 0) + 1;
        }
        zeile([for (final e in anzahl.entries) '${e.value}x ${e.key}'].join(', '));
        final raeume = {for (final v in vb) if (v.raum.isNotEmpty) v.raum}.toList();
        for (final t in umbrechen(raeume.join(', '), 20, maxZeilen: 3)) {
          zeile(t);
        }
      } else {
        zeile('(keine Objekte zugeordnet)', groesse: 1.6);
      }
      if (k.leistung > 0) zeile('${k.leistung} W');
    }
    return lx;
  }

  /// Verbraucher als Kasten mit Kurzsymbol.
  void _last(double xa, double xb, String kuerzel, bool reserve) {
    final m = (xa + xb) / 2;
    const y = _yLast, h = 12.0;
    if (reserve) {
      z.add(ZRechteck(xa, y, xb - xa, h, strich: true));
      return;
    }
    z.add(ZRechteck(xa, y, xb - xa, h));
    const cy = y + h / 2;
    switch (kuerzel) {
      case 'LE' || 'LB' || 'LS':
        z.add(ZKreis(m, cy, 3.2));
        z.add(ZLinie(m - 2.26, cy - 2.26, m + 2.26, cy + 2.26));
        z.add(ZLinie(m - 2.26, cy + 2.26, m + 2.26, cy - 2.26));
      case 'SD':
        final bogen = [for (var i = 0; i <= 12; i++) (m + 3.4 * math.cos(math.pi * i / 12), cy - 1 + 3.4 * math.sin(math.pi * i / 12))];
        z.add(ZPolylinie(bogen));
        z.add(ZLinie(m - 3.4, cy - 1, m + 3.4, cy - 1));
        z.add(ZLinie(m, cy - 1, m, cy - 3.6));
      case 'MO' || 'PU' || 'WP' || 'LU':
        z.add(ZKreis(m, cy, 3.4));
        z.add(ZText(m, cy + 1.1, 'M', groesse: 3, ausrichtung: Ausrichtung.mitte, fett: true));
      default:
        z.add(ZText(m, cy + 1, kuerzel, groesse: 2.6, ausrichtung: Ausrichtung.mitte, fett: true));
    }
  }

  // ------------------------------------------------------------ Liste

  void _betriebsmittelliste(List<SchrankGeraet> sortiert) {
    const spaltenX = [24.0, 50.0, 100.0, 170.0, 215.0, 260.0];
    const kopf = ['BMK', 'Art', 'Daten', 'Platz', 'Darstellung', 'Stromkreise / Bemerkung'];
    var y = 0.0;
    void kopfZeichnen() {
      neuesBlatt('Betriebsmittelliste', schienen: false);
      y = 28;
      for (var i = 0; i < kopf.length; i++) {
        z.add(ZText(spaltenX[i], y, kopf[i], groesse: 2.4, fett: true));
      }
      z.add(ZLinie(24, y + 1.8, _rechts, y + 1.8, dicke: 0.35));
      y += 7;
    }

    kopfZeichnen();
    final kreisZu = <String, List<Stromkreis>>{};
    for (final k in kreise) {
      if (k.schutzId != null) kreisZu.putIfAbsent(k.schutzId!, () => []).add(k);
      for (final g in geraete.where((g) => g.eigenschaften['stromkreis'] == k.id)) {
        kreisZu.putIfAbsent(g.id, () => []).add(k);
      }
    }
    for (final g in sortiert) {
      if (y > 252) kopfZeichnen();
      final daten = switch (g.art) {
        GeraeteArt.ls || GeraeteArt.fils || GeraeteArt.rcd || GeraeteArt.hauptschalter => '${g.kurz}, ${g.pole}-polig${g.phase == null ? '' : ', ${g.phase}'}',
        GeraeteArt.knx => '${g.eigenschaften['aktortyp'] ?? ''} ${g.eigenschaften['kanaele'] ?? ''} Kanäle${g.eigenschaften['pa'] is String ? ', PA ${g.eigenschaften['pa']}' : ''}'.trim(),
        _ => g.bezeichnung,
      };
      final ks = kreisZu[g.id] ?? const [];
      final werte = [
        '=${s.kennzeichen}${g.kennzeichen}',
        g.art.label,
        daten,
        'Reihe ${g.reihe + 1}, TE ${g.position + 1}-${g.ende}',
        (orte[g.id] ?? const ['nur Liste']).take(6).map((o) => o == 'nur Liste' ? o : '/$o').join(' '),
        [for (final k in ks) '${k.nummer} ${k.bezeichnung}'.trim()].join(', '),
      ];
      final breiten = [26, 50, 70, 45, 45, 144];
      for (var i = 0; i < werte.length; i++) {
        final t = umbrechen(werte[i], (breiten[i] / 1.5).floor(), maxZeilen: 1).firstOrNull ?? '';
        z.add(ZText(spaltenX[i], y, t, groesse: 2.0, fett: i == 0));
      }
      z.add(ZLinie(24, y + 1.8, _rechts, y + 1.8, dicke: 0.1));
      y += 5.5;
    }
    if (hinweise.isNotEmpty) {
      if (y > 240) kopfZeichnen();
      y += 4;
      z.add(ZText(24, y, 'Hinweise', groesse: 2.4, fett: true));
      y += 4.5;
      for (final h in hinweise) {
        if (y > 255) break;
        z.add(ZText(24, y, h, groesse: 2.0));
        y += 4;
      }
    }
  }
}
