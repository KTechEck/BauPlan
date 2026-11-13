import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../core/fbh.dart';
import '../../core/verdrahtungskette.dart';
import '../../core/geschossuebergreifend.dart';
import '../../core/height.dart';
import '../../core/leitungsnetz.dart';
import '../../core/raumerkennung.dart';
import '../../core/verteiler.dart';
import '../../core/sensoren.dart';
import '../../core/knx.dart' show haSlug;
import '../../core/wandmasse.dart';
import '../../data/bauelement_bibliothek.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../floorplan/floorplan_painter.dart';
import '../project_tree.dart';
import '../wandansicht/wandansicht_page.dart';
import '../decke/decke_page.dart';
import '../sensoren_page.dart' show sensorVorlagen;
import '../verteiler/verteiler_editor.dart';
import '../tastenkuerzel.dart';
import '../bauteile/bauelement_wahl.dart';
import 'heizkreise_dialog.dart';
import '../floorplan/geschoss_3d.dart';
import '../symbole_plan.dart';
import '../widgets.dart';

/// Modul Installation: Leitungswege und Geräte aller Gewerke auf dem
/// Grundriss. Jedes Gewerk ist eine Ebene, die sich ein- und ausblenden lässt.
class InstallationPage extends StatefulWidget {
  const InstallationPage({super.key, required this.state});
  final AppState state;

  @override
  State<InstallationPage> createState() => _InstallationPageState();
}

class _Daten {
  _Daten({
    required this.waende,
    required this.umrisse,
    required this.raeume,
    required this.raumBilder,
    required this.oeffnungen,
    required this.objekte,
    required this.typen,
    required this.gewerke,
    required this.geschoss,
  });
  final List<Wand> waende;
  final Map<String, List<Offset>> umrisse;
  final List<Raum> raeume;
  final List<RaumBild> raumBilder;
  final List<Oeffnung> oeffnungen;
  final List<Objekt> objekte;
  final Map<String, Objekttyp> typen;
  final Map<String, Gewerk> gewerke;
  final Geschoss? geschoss;
}

/// Standardhöhe und Lage beim Setzen, je Objekttyp.
(int?, Hoehenbezug?, String?) objektVorgabe(Objekttyp t) {
  const anDecke = {'LE', 'PM', 'BM', 'LV', 'AP'};
  return switch (t.geometrie) {
    Geometrieart.punkt when anDecke.contains(t.kuerzel) => (0, Hoehenbezug.rohdecke, 'an Decke'),
    Geometrieart.punkt when t.kuerzel == 'TA' || t.kuerzel == 'KX' => (1050, Hoehenbezug.ffb, 'in Wand'),
    Geometrieart.punkt when t.kuerzel == 'WD' => (300, Hoehenbezug.ffb, 'durch Wand'),
    Geometrieart.linie when t.kuerzel == 'LB' => (0, Hoehenbezug.rohdecke, 'an Decke'),
    Geometrieart.punkt => (300, Hoehenbezug.ffb, 'in Wand'),
    Geometrieart.linie => (0, Hoehenbezug.rfb, 'auf RFB'),
    Geometrieart.flaeche => (null, null, 'im Estrich'),
  };
}

class _InstallationPageState extends State<InstallationPage> {
  final _eigFenster = EigenschaftenFenster();
  final _doppel = Doppelklick();
  final _fokus = FocusNode();
  bool _ansichtZiehen = false; // Leertaste + Ziehen
  double _massstab = 0.08;
  Offset _verschiebung = const Offset(120, 120);
  bool _setzen = true;
  bool _ganzerRaum = false; // Fläche = ganzer Raum per Klick
  String? _zugangFuer; // Heizkreis, dessen Zugang mit dem nächsten Klick gesetzt wird
  String? _sperrFuer; // Heizkreis, für den eine Sperrfläche (zwei Ecken) gezeichnet wird
  Offset? _sperrStart;
  final Set<String> _mehr = {}; // Mehrfachauswahl (Umschalt/Strg-Klick, Rahmen)
  List<Objekt> _ablage = const []; // Strg+C
  double _einfuegeVersatz = 0;
  Offset? _rahmenA, _rahmenB; // Auswahlrahmen in Weltkoordinaten
  bool _amOrtWaehlen = false; // Setzen: Auswahlmenü direkt an der Klickstelle
  final Set<String> _ebenenAus = {}; // ausgeblendete Verlegeebenen (Objekt.lage)
  String? _ebeneNeu; // Verlegeebene für neue Objekte (null = Vorgabe des Typs)
  Offset _klickGlobal = Offset.zero;
  String? _typId;
  String? _gewerkId; // beim Setzen zuerst das Gewerk, dann das Gerät
  ObjektStatus _status = ObjektStatus.geplant;
  final List<Offset> _entwurf = [];
  Offset? _maus;
  String? _auswahl;
  Offset? _ziehStart; // Welt beim Drücken auf das gewählte Objekt
  Offset _ziehVersatz = Offset.zero;
  Set<String>? _sichtbar; // Gewerk-IDs
  _Daten? _daten;
  (int, String?)? _stand;
  bool _eingepasst = false;
  Size _flaeche = Size.zero;
  final List<VoidCallback> _rueckgaengig = [];
  String? _geschossBeiLetztemBuild;

  AppState get _s => widget.state;

  @override
  void dispose() {
    _fokus.dispose();
    super.dispose();
  }

  _Daten _laden() {
    final stand = (_s.revision, _s.geschossId);
    if (_daten != null && _stand == stand) return _daten!;
    final store = _s.store!;
    final g = _s.geschossId;
    final waende = g == null ? <Wand>[] : store.waende(g);
    final global = store.einstellung<bool>('ecken_verbinden') ?? true;
    final achsen = [for (final w in waende) w.achse];
    final verb = [for (final w in waende) w.verbinden ?? global];
    final nachbarn = [
      for (var i = 0; i < waende.length; i++)
        if (verb[i]) achsen[i]
    ];
    final raeume = g == null ? <Raum>[] : store.raeume(g);
    final gewerke = {for (final x in store.gewerke()) x.id: x};
    _sichtbar ??= {for (final x in gewerke.values) if (x.sichtbar) x.id};
    final d = _Daten(
      waende: waende,
      umrisse: {
        for (var i = 0; i < waende.length; i++)
          waende[i].id: [
            for (final p in wandUmriss(achsen[i], verb[i] ? nachbarn : [achsen[i]])) Offset(p.x, p.y)
          ],
      },
      raeume: raeume,
      raumBilder: [
        for (final r in raeume)
          if (r.umriss != null)
            RaumBild(
              umriss: [for (final p in r.umriss!) Offset(p.x, p.y)],
              beschriftung: r.name,
              innenpunkt: Offset(punktImInneren(r.umriss!).x, punktImInneren(r.umriss!).y),
              ausgewaehlt: r.id == _s.raumId,
            ),
      ],
      oeffnungen: g == null ? const [] : store.oeffnungen(g),
      objekte: g == null ? const [] : [...store.objekte(g), ...durchgehendeObjekte(store, g)],
      typen: {for (final t in store.objekttypen()) t.id: t},
      gewerke: gewerke,
      geschoss: g == null ? null : store.geschoss(g),
    );
    _daten = d;
    _stand = stand;
    return d;
  }

  Objekttyp? get _typ => _daten?.typen[_typId];
  Offset _zuWelt(Offset b) => (b - _verschiebung) / _massstab;

  // ------------------------------------------------------------- Fangen

  Offset _fangen(Offset welt, _Daten d) {
    final radius = 10 / _massstab;
    // Punkte vorhandener Objekte (Leitungen an Dosen anschließen)
    Offset? bester;
    var abstand = radius;
    // Anschlusspunkte von Heizkreisverteilern (je Abgang Vor- und Rücklauf)
    final strecken = [for (final w in d.waende) wandStrecke(w)];
    for (final o in d.objekte) {
      if (!_istSichtbar(o, d) || d.typen[o.typId]?.kuerzel != 'HV' || o.punkte.isEmpty) continue;
      for (final (_, q) in verteilerAnschlussPunkte(o.punkte.first, VerteilerDaten.ausJson(o.eigenschaften), strecken)) {
        final a = (Offset(q.x, q.y) - welt).distance;
        if (a < abstand) {
          abstand = a;
          bester = Offset(q.x.roundToDouble(), q.y.roundToDouble());
        }
      }
    }
    // Zugänge der Heizkreise (Anbindeleitung anschließen)
    for (final o in d.objekte) {
      if (!_istSichtbar(o, d) || d.typen[o.typId]?.kuerzel != 'HK' || o.punkte.length < 3) continue;
      final z = heizkreisAnschluesse(o.punkte, o.eigenschaften);
      if (z == null) continue;
      for (final q in [z.vl, z.rl]) {
        final a = (Offset(q.x, q.y) - welt).distance;
        if (a < abstand) {
          abstand = a;
          bester = Offset(q.x.roundToDouble(), q.y.roundToDouble());
        }
      }
    }
    // freie Plätze in Mehrfachrahmen (Gerät direkt in den Rahmen setzen)
    for (final (_, q) in _freiePlaetze(d)) {
      final a = (q - welt).distance;
      if (a < abstand) {
        abstand = a;
        bester = q;
      }
    }
    // Startpunkt der gerade gezeichneten Fläche: schließt sie
    if (_entwurf.length >= 2 && (_entwurf.first - welt).distance < radius * 1.5) return _entwurf.first;
    for (final o in d.objekte) {
      if (!_istSichtbar(o, d)) continue;
      for (final p in o.punkte) {
        final q = Offset(p.x, p.y);
        final a = (q - welt).distance;
        if (a < abstand) {
          abstand = a;
          bester = q;
        }
      }
    }
    // Ecken der Räume (lichter Umriss) für Flächen und Leitungen
    if (_typ?.geometrie != Geometrieart.punkt) {
      for (final r in d.raeume) {
        for (final p in r.umriss ?? const <Punkt>[]) {
          final q = Offset(p.x.roundToDouble(), p.y.roundToDouble());
          final a = (q - welt).distance;
          if (a < abstand) {
            abstand = a;
            bester = q;
          }
        }
      }
    }
    if (bester != null) return bester;
    // Wanddurchbruch: auf die Wandachse
    if (_typ?.kuerzel == 'WD') {
      for (final w in d.waende) {
        final a = Offset(w.x1.toDouble(), w.y1.toDouble()), b = Offset(w.x2.toDouble(), w.y2.toDouble());
        if (abstandZuStrecke(welt, a, b) > w.dicke / 2 + radius) continue;
        final l = (b - a).distance;
        if (l < 1) continue;
        final u = (b - a) / l;
        final t = (((welt - a).dx * u.dx + (welt - a).dy * u.dy) / 10).round() * 10.0;
        final f = a + u * t.clamp(0.0, l);
        return Offset(f.dx.roundToDouble(), f.dy.roundToDouble());
      }
    }
    // Geräte, Flächen und Leitungen an die Wandoberfläche
    final f = _wandflaecheFang(welt, d);
    if (f != null) return f;
    var x = (welt.dx / 50).round() * 50.0, y = (welt.dy / 50).round() * 50.0;
    if (_entwurf.isNotEmpty && HardwareKeyboard.instance.isShiftPressed) {
      final s = _entwurf.last;
      if ((x - s.dx).abs() >= (y - s.dy).abs()) {
        y = s.dy;
      } else {
        x = s.dx;
      }
    }
    return Offset(x, y);
  }


  /// Nächster Punkt auf einer Wandoberfläche (verschnittener Umriss) im Fangradius.
  Offset? _wandflaecheFang(Offset welt, _Daten d) {
    final radius = 10 / _massstab;
    Offset? bester;
    var abstand = radius;
    for (final u in d.umrisse.values) {
      if (u.length < 4) continue;
      for (final (a, b) in [(u[0], u[1]), (u[3], u[2])]) {
        final l = (b - a).distance;
        if (l < 1) continue;
        final r = (b - a) / l;
        final t = ((welt - a).dx * r.dx + (welt - a).dy * r.dy).clamp(0.0, l);
        final f = a + r * t;
        if ((f - welt).distance < abstand) {
          abstand = (f - welt).distance;
          bester = Offset(f.dx.roundToDouble(), f.dy.roundToDouble());
        }
      }
    }
    return bester;
  }

  /// Richtung (Einheit) der Wandoberfläche, die [p] am nächsten liegt.
  Offset? _wandRichtung(Offset p, _Daten d) {
    Offset? best;
    var abstand = 60.0;
    for (final u in d.umrisse.values) {
      if (u.length < 4) continue;
      for (final (a, b) in [(u[0], u[1]), (u[3], u[2])]) {
        final l = (b - a).distance;
        if (l < 1) continue;
        final r = (b - a) / l;
        final t = ((p - a).dx * r.dx + (p - a).dy * r.dy).clamp(0.0, l);
        final f = (a + r * t - p).distance;
        if (f < abstand) {
          abstand = f;
          best = r;
        }
      }
    }
    return best;
  }

  /// Punktgeräte zu einem Mehrfachrahmen verbinden: im 71-mm-Raster entlang der
  /// Wand ausrichten, gemeinsame Kennung im Plan, Rahmen in der Wandansicht.
  void _rahmenVerbinden(List<Objekt> geraete, _Daten d) {
    if (geraete.length < 2) return;
    final store = _s.store!;
    final p0 = Offset(geraete.first.punkte.first.x, geraete.first.punkte.first.y);
    final r = _wandRichtung(p0, d) ?? const Offset(1, 0);
    double t(Objekt o) => (o.punkte.first.x - p0.dx) * r.dx + (o.punkte.first.y - p0.dy) * r.dy;
    final sortiert = [...geraete]..sort((a, b) => t(a).compareTo(t(b)));
    final start = Offset(sortiert.first.punkte.first.x, sortiert.first.punkte.first.y);
    final gid = sortiert.first.id;
    // Rahmengröße beibehalten, wenn schon größer gewählt (freie Plätze)
    var fach = sortiert.length;
    for (final o in sortiert) {
      final r0 = o.eigenschaften['rahmen'];
      if (r0 is Map && (r0['fach'] as num? ?? 0) > fach) fach = (r0['fach'] as num).toInt();
    }
    final alte = <(String, Map<String, Object?>)>[];
    for (final (i, o) in sortiert.indexed) {
      final q = start + r * (71.0 * i);
      final eig = {...o.eigenschaften, 'rahmen_gruppe': gid, 'rahmen_pos': i}..remove('rahmen');
      if (i == 0) {
        eig['rahmen'] = {'fach': fach, 'richtung': 'w', 'inhalt': [for (final x in sortiert) d.typen[x.typId]?.kuerzel ?? '?']};
      }
      alte.add((o.id, store.objektAendern(o.id, {
        'geometrie': Objekt.geometrieText([Punkt(q.dx.roundToDouble(), q.dy.roundToDouble())]),
        'eigenschaften': jsonEncode(eig),
      })));
    }
    _rueckgaengig.add(() {
      for (final (i, alt) in alte) {
        store.objektAendern(i, alt);
      }
    });
    _s.geaendert();
    setState(() {});
  }

  /// Freie Plätze aller Mehrfachrahmen: (Gruppe, Weltpunkt) im 71-mm-Raster.
  List<(String, Offset)> _freiePlaetze(_Daten d) {
    final aus = <(String, Offset)>[];
    for (final o in d.objekte) {
      final r0 = o.eigenschaften['rahmen'];
      if (r0 is! Map || o.punkte.isEmpty) continue;
      final fach = (r0['fach'] as num?)?.toInt() ?? 1;
      if (fach < 2) continue;
      final gid = o.eigenschaften['rahmen_gruppe'] as String? ?? o.id;
      final mitglieder = [for (final x in d.objekte) if (x.id == o.id || x.eigenschaften['rahmen_gruppe'] == gid) x];
      final belegt = {for (final x in mitglieder) (x.eigenschaften['rahmen_pos'] as num?)?.toInt() ?? 0};
      final p0 = Offset(o.punkte.first.x, o.punkte.first.y);
      final r = _wandRichtung(p0, d) ?? const Offset(1, 0);
      for (var i = 0; i < fach; i++) {
        if (!belegt.contains(i)) aus.add((gid, p0 + r * (71.0 * i)));
      }
    }
    return aus;
  }

  /// Mehrfachrahmen auflösen (Geräte bleiben, wo sie sind).
  void _rahmenLoesen(String gid, _Daten d) {
    final store = _s.store!;
    for (final o in d.objekte.where((o) => o.eigenschaften['rahmen_gruppe'] == gid)) {
      store.objektAendern(o.id, {
        'eigenschaften': jsonEncode({...o.eigenschaften}
          ..remove('rahmen_gruppe')
          ..remove('rahmen_pos')
          ..remove('rahmen')),
      });
    }
    _s.geaendert();
    setState(() {});
  }

  /// Objekt mit um [d] verschobenen Punkten (Vorschau beim Ziehen).
  static Objekt verschobenesObjekt(Objekt o, Offset d) => Objekt(
        id: o.id,
        typId: o.typId,
        geschossId: o.geschossId,
        raumId: o.raumId,
        kennung: o.kennung,
        punkte: [for (final p in o.punkte) Punkt(p.x + d.dx, p.y + d.dy)],
        z: o.z,
        zBezug: o.zBezug,
        lage: o.lage,
        status: o.status,
        normkennzeichen: o.normkennzeichen,
        produktId: o.produktId,
        eigenschaften: o.eigenschaften,
      );

  /// Verschiebung beim Ziehen: Geräte rasten an Wandoberflächen ein, sonst 10-mm-Raster.
  Offset _ziehVersatzBerechnen(Offset welt, _Daten d) {
    final s = _ziehStart!;
    final o = d.objekte.where((e) => e.id == _auswahl).firstOrNull;
    if (o == null || o.punkte.isEmpty) return Offset.zero;
    var delta = welt - s;
    if (d.typen[o.typId]?.geometrie == Geometrieart.punkt) {
      final p0 = Offset(o.punkte.first.x, o.punkte.first.y);
      final f = _wandflaecheFang(p0 + delta, d);
      if (f != null) return f - p0;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      delta = delta.dx.abs() >= delta.dy.abs() ? Offset(delta.dx, 0) : Offset(0, delta.dy);
    }
    return Offset((delta.dx / 10).round() * 10.0, (delta.dy / 10).round() * 10.0);
  }

  void _ziehenBeenden() {
    final id = _auswahl, v = _ziehVersatz;
    setState(() {
      _ziehStart = null;
      _ziehVersatz = Offset.zero;
    });
    if (id == null || v.distance < 1) return;
    final ids = _mehr.contains(id) ? {..._mehr} : {id};
    final store = _s.store!;
    final alte = <(String, Map<String, Object?>)>[];
    for (final o in _laden().objekte.where((e) => ids.contains(e.id))) {
      alte.add((o.id, store.objektAendern(o.id, {'geometrie': Objekt.geometrieText(verschobenesObjekt(o, v).punkte)})));
    }
    _rueckgaengig.add(() {
      for (final (i, alt) in alte) {
        store.objektAendern(i, alt);
      }
    });
    _s.geaendert();
  }

  /// Kopierte Objekte (Strg+C) versetzt einfügen (Strg+V), mit allen Eigenschaften.
  void _einfuegen() {
    if (_ablage.isEmpty || _s.geschossId == null) return;
    final d = _laden();
    final store = _s.store!;
    _einfuegeVersatz += 300;
    final neu = <String>[];
    for (final o in _ablage) {
      final t = d.typen[o.typId];
      if (t == null) continue;
      final id = store.objektAnlegen(
        geschossId: _s.geschossId!,
        typ: t,
        punkte: [for (final p in o.punkte) Punkt(p.x + _einfuegeVersatz, p.y + _einfuegeVersatz)],
        raumId: o.raumId,
        z: o.z,
        zBezug: o.zBezug,
        lage: o.lage,
        status: o.status,
      );
      final eig = {...o.eigenschaften}
        ..remove('rahmen_gruppe')
        ..remove('rahmen_pos')
        ..remove('gespeist_von')
        ..remove('anbindung')
        ..remove('anfang')
        ..remove('ende');
      store.objektAendern(id, {'eigenschaften': jsonEncode(eig), if (o.produktId != null) 'produkt_id': o.produktId});
      neu.add(id);
    }
    _rueckgaengig.add(() {
      for (final id in neu) {
        store.objektLoeschen(id);
      }
    });
    setState(() {
      _mehr
        ..clear()
        ..addAll(neu);
      _auswahl = neu.firstOrNull;
    });
    _s.geaendert();
  }

  /// Auswahlrahmen: alle sichtbaren Objekte, die ganz im Rahmen liegen.
  void _rahmenBeenden(_Daten d) {
    final a = _rahmenA!, b = _rahmenB ?? a;
    setState(() {
      _rahmenA = null;
      _rahmenB = null;
    });
    if ((a - b).distance * _massstab < 5) return;
    final r = Rect.fromPoints(a, b);
    final neu = [
      for (final o in d.objekte)
        if (_istSichtbar(o, d) && o.punkte.isNotEmpty && o.punkte.every((q) => r.contains(Offset(q.x, q.y)))) o.id
    ];
    setState(() {
      _mehr.addAll(neu);
      if (_auswahl == null && neu.isNotEmpty) _auswahl = neu.first;
    });
  }
  bool _istSichtbar(Objekt o, _Daten d) =>
      _sichtbar!.contains(d.typen[o.typId]?.gewerkId) && !_ebenenAus.contains(o.lage ?? '');

  // ----------------------------------------------------------- Aktionen

  String? _raumBei(Offset p, _Daten d) {
    final q = Punkt(p.dx, p.dy);
    for (final r in d.raeume) {
      if (r.umriss != null && punktInPolygon(q, r.umriss!)) return r.id;
    }
    return null;
  }


  /// Bezug eines Leitungsendes: Ende einer anderen Leitung (mit deren Übergang
  /// an dieser Stelle) oder Anschluss eines Heizkreisverteilers.
  (Map<String, dynamic>?, String?) _endBezug(Offset p, _Daten d) {
    for (final o in d.objekte) {
      final t = d.typen[o.typId];
      if (t?.geometrie != Geometrieart.linie || o.punkte.length < 2) continue;
      for (final (i, ende) in [(0, 'uebergang_anfang'), (o.punkte.length - 1, 'uebergang_ende')]) {
        if ((Offset(o.punkte[i].x, o.punkte[i].y) - p).distance <= 2) {
          final u = o.eigenschaften[ende];
          return ({'leitung': o.id}, u is String && _lagen.contains(u) ? u : null);
        }
      }
    }
    final strecken = [for (final w in d.waende) wandStrecke(w)];
    for (final o in d.objekte) {
      if (d.typen[o.typId]?.kuerzel != 'HV' || o.punkte.isEmpty) continue;
      for (final (name, q) in verteilerAnschlussPunkte(o.punkte.first, VerteilerDaten.ausJson(o.eigenschaften), strecken)) {
        if ((Offset(q.x, q.y) - p).distance <= 2) return ({'objekt': o.id, 'anschluss': name}, 'im Estrich');
      }
    }
    for (final o in d.objekte) {
      if (d.typen[o.typId]?.kuerzel != 'HK' || o.punkte.length < 3) continue;
      final z = heizkreisAnschluesse(o.punkte, o.eigenschaften);
      if (z == null) continue;
      for (final (name, q) in [('VL', z.vl), ('RL', z.rl)]) {
        if ((Offset(q.x, q.y) - p).distance <= 2) return ({'objekt': o.id, 'anschluss': name}, 'im Estrich');
      }
    }
    return (null, null);
  }
  void _objektAnlegen(List<Offset> punkte) {
    final t = _typ;
    final d = _daten;
    if (t == null || d == null || _s.geschossId == null) return;
    final (z, bezug, vorgabeLage) = objektVorgabe(t);
    var lage = _ebeneNeu ?? vorgabeLage;
    // Gerät auf der Wandoberfläche gefangen: sitzt in der Wand
    if (_ebeneNeu == null && t.geometrie == Geometrieart.punkt && punkte.isNotEmpty) {
      final f = _wandflaecheFang(punkte.first, d);
      if (f != null && (f - punkte.first).distance < 3) lage = 'in Wand';
    }
    final store = _s.store!;
    // Punktgerät auf ein vorhandenes gesetzt: daneben in den Mehrfachrahmen (71-mm-Raster)
    List<Objekt>? rahmenMit;
    String? platzGruppe;
    if (t.geometrie == Geometrieart.punkt && punkte.isNotEmpty) {
      for (final (gid, q) in _freiePlaetze(d)) {
        if ((q - punkte.first).distance < 5) platzGruppe = gid;
      }
    }
    if (platzGruppe != null) {
      rahmenMit = [for (final o in d.objekte) if (o.id == platzGruppe || o.eigenschaften['rahmen_gruppe'] == platzGruppe) o];
    } else if (t.geometrie == Geometrieart.punkt && punkte.isNotEmpty) {
      final besetzt = d.objekte
          .where((o) => d.typen[o.typId]?.geometrie == Geometrieart.punkt && o.punkte.isNotEmpty && (Offset(o.punkte.first.x, o.punkte.first.y) - punkte.first).distance < 5)
          .firstOrNull;
      final r = besetzt == null ? null : _wandRichtung(punkte.first, d);
      if (besetzt != null && r != null) {
        final gid = besetzt.eigenschaften['rahmen_gruppe'];
        rahmenMit = gid is String ? [for (final o in d.objekte) if (o.eigenschaften['rahmen_gruppe'] == gid) o] : [besetzt];
        final letzter = rahmenMit.fold<Objekt>(rahmenMit.first,
            (a, b) => ((b.eigenschaften['rahmen_pos'] as num?) ?? 0) > ((a.eigenschaften['rahmen_pos'] as num?) ?? 0) ? b : a);
        final q = Offset(letzter.punkte.first.x, letzter.punkte.first.y) + r * 71.0;
        punkte = [Offset(q.dx.roundToDouble(), q.dy.roundToDouble())];
      }
    }
    // Leitungen: Anfang/Ende an andere Leitungen oder Geräteanschlüsse knüpfen
    final bezuege = <String, Map<String, dynamic>>{};
    if (t.geometrie == Geometrieart.linie && punkte.length >= 2) {
      for (final (ende, p) in [('anfang', punkte.first), ('ende', punkte.last)]) {
        final (b, uebergang) = _endBezug(p, d);
        if (b != null) bezuege[ende] = b;
        if (uebergang != null && ende == 'anfang') lage = uebergang;
      }
    }
    final id = store.objektAnlegen(
      geschossId: _s.geschossId!,
      typ: t,
      punkte: [for (final p in punkte) Punkt(p.dx, p.dy)],
      raumId: _raumBei(punkte.first, d),
      z: z,
      zBezug: bezug,
      lage: lage,
      status: _status,
    );
    if (bezuege.isNotEmpty) store.objektAendern(id, {'eigenschaften': jsonEncode(bezuege)});
    if (rahmenMit != null) {
      final neu = store.objekte(_s.geschossId!).where((o) => o.id == id).firstOrNull;
      if (neu != null) _rahmenVerbinden([...rahmenMit, neu], d);
    }
    // Anbindeleitung an einem Heizkreis: Länge als Zuleitung übernehmen
    for (final b in bezuege.values) {
      final hk = d.objekte.where((o) => o.id == b['objekt'] && d.typen[o.typId]?.kuerzel == 'HK').firstOrNull;
      if (hk == null || hk.eigenschaften['zuleitung_manuell'] == true) continue;
      var l = 0.0;
      for (var i = 0; i + 1 < punkte.length; i++) {
        l += (punkte[i + 1] - punkte[i]).distance;
      }
      store.objektAendern(hk.id, {'eigenschaften': jsonEncode({...hk.eigenschaften, 'zuleitung_mm': l.round(), 'anbindung': id})});
    }
    _rueckgaengig.add(() => store.objektLoeschen(id));
    _s.geaendert();
  }

  void _entwurfAbschliessen() {
    final t = _typ;
    if (t == null) return;
    final noetig = t.geometrie == Geometrieart.flaeche ? 3 : 2;
    if (_entwurf.length >= noetig) _objektAnlegen(List.of(_entwurf));
    setState(_entwurf.clear);
  }

  String? _treffer(Offset welt, _Daten d) {
    final tol = 8 / _massstab;
    String? id;
    var bester = tol;
    for (final o in d.objekte.reversed) {
      if (!_istSichtbar(o, d)) continue;
      final pts = [for (final p in o.punkte) Offset(p.x, p.y)];
      final typ = d.typen[o.typId];
      double a;
      if (pts.length == 1) {
        a = (pts.first - welt).distance;
      } else {
        a = double.infinity;
        final n = typ?.geometrie == Geometrieart.flaeche ? pts.length : pts.length - 1;
        for (var i = 0; i < n; i++) {
          a = math.min(a, abstandZuStrecke(welt, pts[i], pts[(i + 1) % pts.length]));
        }
        if (typ?.geometrie == Geometrieart.flaeche && punktInPolygon(Punkt(welt.dx, welt.dy), o.punkte)) {
          a = math.min(a, tol * 0.9);
        }
      }
      if (a < bester) {
        bester = a;
        id = o.id;
      }
    }
    return id;
  }

  void _klick(Offset bildschirm) {
    _fokus.requestFocus();
    if (_s.geschossId == null) return;
    final d = _laden();
    final welt = _zuWelt(bildschirm);
    if (_sperrFuer != null) {
      final p = Offset((welt.dx / 10).round() * 10.0, (welt.dy / 10).round() * 10.0);
      if (_sperrStart == null) {
        setState(() => _sperrStart = p);
        return;
      }
      final hk = d.objekte.where((o) => o.id == _sperrFuer).firstOrNull;
      final a = _sperrStart!;
      setState(() {
        _sperrFuer = null;
        _sperrStart = null;
      });
      if (hk != null && (a - p).distance > 50) {
        final neu = [
          ...FbhEinstellung.ausJson(hk.eigenschaften).sperren,
          [Punkt(a.dx, a.dy), Punkt(p.dx, a.dy), Punkt(p.dx, p.dy), Punkt(a.dx, p.dy)],
        ];
        final alt = _s.store!.objektAendern(hk.id, {'eigenschaften': jsonEncode({...hk.eigenschaften, 'sperren': sperrenJson(neu)})});
        _rueckgaengig.add(() => _s.store!.objektAendern(hk.id, alt));
        _s.geaendert();
      }
      return;
    }
    if (_zugangFuer != null) {
      final hk = d.objekte.where((o) => o.id == _zugangFuer).firstOrNull;
      setState(() {
        _zugangFuer = null;
        _maus = null;
      });
      if (hk != null && hk.punkte.length >= 3) {
        final anteil = double.parse(zugangAnteil(hk.punkte, Punkt(welt.dx, welt.dy)).toStringAsFixed(3));
        final alt = _s.store!.objektAendern(hk.id, {'eigenschaften': jsonEncode({...hk.eigenschaften, 'zugang': anteil})});
        _rueckgaengig.add(() => _s.store!.objektAendern(hk.id, alt));
        setState(() {});
      }
      return;
    }
    if (!_setzen || _typ == null) {
      final t = _treffer(welt, d);
      final zusatz = HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isControlPressed;
      setState(() {
        if (t == null) {
          _s.markiert = {};
          if (!zusatz) _mehr.clear();
          _rahmenA = welt;
          _rahmenB = welt;
        } else if (zusatz) {
          if (_auswahl != null) _mehr.add(_auswahl!);
          if (!_mehr.remove(t)) _mehr.add(t);
        } else if (!_mehr.contains(t)) {
          _mehr.clear();
        }
        _auswahl = t ?? (zusatz ? _auswahl : null);
        _ziehStart = t == null ? null : welt;
        _ziehVersatz = Offset.zero;
      });
      if (t == null && !zusatz) _wandDoppelklick(welt, d);
      return;
    }
    // Auswahl am Ort: erst klicken, dann wählen, was hier hin soll
    if (_amOrtWaehlen && _entwurf.isEmpty) {
      _amOrtSetzen(welt, d);
      return;
    }
    final t = _typ!;
    // Fläche über den ganzen Raum (z. B. Heizkreis nach Raum)
    if (t.geometrie == Geometrieart.flaeche && _ganzerRaum && _entwurf.isEmpty) {
      final r = d.raeume.where((r) => r.umriss != null && r.umriss!.length >= 3 && punktInPolygon(Punkt(welt.dx, welt.dy), r.umriss!)).firstOrNull;
      if (r != null) {
        _objektAnlegen([for (final q in r.umriss!) Offset(q.x.roundToDouble(), q.y.roundToDouble())]);
        return;
      }
    }
    final p = _fangen(welt, d);
    if (t.geometrie == Geometrieart.punkt) {
      _objektAnlegen([p]);
      return;
    }
    setState(() {
      if (_entwurf.isNotEmpty && (p - _entwurf.last).distance < 1) {
        _entwurfAbschliessen(); // gleicher Punkt = fertig
      } else if (t.geometrie == Geometrieart.flaeche && _entwurf.length >= 3 && (p - _entwurf.first).distance < 1) {
        _entwurfAbschliessen(); // Startpunkt erneut = Fläche geschlossen
      } else {
        _entwurf.add(p);
      }
    });
  }

  /// Menü an der Klickstelle: Gewerke als Überschriften, darunter die Geräte.
  /// Punktobjekte werden sofort gesetzt; bei Leitungen/Flächen beginnt hier der Zug.
  Future<void> _amOrtSetzen(Offset welt, _Daten d) async {
    final sichtbare = [for (final g in d.gewerke.values) if (_sichtbar!.contains(g.id) && d.typen.values.any((t) => t.gewerkId == g.id)) g];
    final pos = _klickGlobal;
    final wahl = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      constraints: const BoxConstraints(maxHeight: 520, minWidth: 260),
      items: [
        for (final g in sichtbare) ...[
          PopupMenuItem<String>(
            enabled: false,
            height: 28,
            child: Text(g.name.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(g.farbe))),
          ),
          for (final t in d.typen.values.where((t) => t.gewerkId == g.id))
            PopupMenuItem<String>(
              value: t.id,
              height: 34,
              child: Row(children: [
                Container(width: 10, height: 10, color: Color(g.farbe)),
                const SizedBox(width: 8),
                Expanded(child: Text('${t.name} (${t.kuerzel})', overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
      ],
    );
    if (wahl == null || !mounted) return;
    setState(() {
      _typId = wahl;
      _gewerkId = d.typen[wahl]?.gewerkId ?? _gewerkId;
    });
    final t = d.typen[wahl]!;
    final p = _fangen(welt, d);
    if (t.geometrie == Geometrieart.punkt) {
      _objektAnlegen([p]);
    } else {
      setState(() => _entwurf.add(p));
    }
  }

  (String, DateTime)? _letzterWandKlick;

  /// Doppelklick auf eine Wand öffnet die Wandansicht der angeklickten Seite.
  void _wandDoppelklick(Offset welt, _Daten d) {
    Wand? wand;
    var bester = double.infinity;
    for (final w in d.waende) {
      final a = Offset(w.x1.toDouble(), w.y1.toDouble()), b = Offset(w.x2.toDouble(), w.y2.toDouble());
      final abst = abstandZuStrecke(welt, a, b);
      if (abst < w.dicke / 2 + 8 / _massstab && abst < bester) {
        bester = abst;
        wand = w;
      }
    }
    if (wand == null) return;
    final jetzt = DateTime.now();
    final letzter = _letzterWandKlick;
    if (letzter != null && letzter.$1 == wand.id && jetzt.difference(letzter.$2).inMilliseconds < 450) {
      _letzterWandKlick = null;
      final a = Offset(wand.x1.toDouble(), wand.y1.toDouble());
      final u = (Offset(wand.x2.toDouble(), wand.y2.toDouble()) - a) / math.max(1.0, wand.laenge);
      final links = (welt - a).dx * u.dy - (welt - a).dy * u.dx > 0;
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => WandansichtPage(state: _s, wandId: wand!.id, links: links)));
    } else {
      _letzterWandKlick = (wand.id, jetzt);
    }
  }

  void _loeschen() {
    final ids = {..._mehr, if (_auswahl != null) _auswahl!};
    if (ids.isEmpty) return;
    final store = _s.store!;
    for (final id in ids) {
      store.objektLoeschen(id);
    }
    _rueckgaengig.add(() {
      for (final id in ids) {
        store.objektWiederherstellen(id);
      }
    });
    setState(() {
      _auswahl = null;
      _mehr.clear();
    });
    _s.geaendert();
  }

  KeyEventResult _taste(FocusNode n, KeyEvent e) {
    if (e is KeyUpEvent && e.logicalKey == LogicalKeyboardKey.space) {
      _ansichtZiehen = false;
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.f1:
        tastenkuerzelZeigen(context);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _ansichtZiehen = true;
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        setState(() => _verschiebung += const Offset(80, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        setState(() => _verschiebung -= const Offset(80, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() => _verschiebung += const Offset(0, 80));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        setState(() => _verschiebung -= const Offset(0, 80));
        return KeyEventResult.handled;
      default:
    }
    final k = e.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed && k == LogicalKeyboardKey.keyZ) {
      if (_rueckgaengig.isNotEmpty) {
        _rueckgaengig.removeLast()();
        setState(() => _auswahl = null);
        _s.geaendert();
      }
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed && k == LogicalKeyboardKey.keyC) {
      final d = _laden();
      final ids = {..._mehr, if (_auswahl != null) _auswahl!};
      _ablage = [for (final o in d.objekte) if (ids.contains(o.id)) o];
      if (_ablage.isNotEmpty) zeigeHinweis(context, '${_ablage.length} Objekt(e) kopiert – Strg+V fügt sie versetzt ein.');
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed && k == LogicalKeyboardKey.keyV) {
      _einfuegen();
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed && k == LogicalKeyboardKey.keyD) {
      final d = _laden();
      final ids = {..._mehr, if (_auswahl != null) _auswahl!};
      _ablage = [for (final o in d.objekte) if (ids.contains(o.id)) o];
      _einfuegen();
      return KeyEventResult.handled;
    }
    if (!HardwareKeyboard.instance.isControlPressed && (k == LogicalKeyboardKey.keyV || k == LogicalKeyboardKey.keyP)) {
      setState(() {
        _setzen = k == LogicalKeyboardKey.keyP;
        _entwurf.clear();
      });
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _entwurfAbschliessen();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      setState(() {
        _entwurf.clear();
        _zugangFuer = null;
        _sperrFuer = null;
        _sperrStart = null;
        _mehr.clear();
        _auswahl = null;
      });
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      _loeschen();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace && _entwurf.isNotEmpty) {
      setState(_entwurf.removeLast);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _einpassen(_Daten d) {
    final pts = [
      for (final w in d.waende) ...[Offset(w.x1.toDouble(), w.y1.toDouble()), Offset(w.x2.toDouble(), w.y2.toDouble())],
      for (final o in d.objekte)
        for (final p in o.punkte) Offset(p.x, p.y),
    ];
    if (pts.isEmpty || _flaeche.isEmpty) return;
    final r = pts.skip(1).fold(Rect.fromPoints(pts.first, pts.first), (Rect a, p) => a.expandToInclude(Rect.fromPoints(p, p)));
    final b = math.max(1000.0, r.width), h = math.max(1000.0, r.height);
    final m = math.min((_flaeche.width - 120) / b, (_flaeche.height - 120) / h).clamp(0.005, 2.0).toDouble();
    setState(() {
      _massstab = m;
      _verschiebung = Offset((_flaeche.width - b * m) / 2 - r.left * m, (_flaeche.height - h * m) / 2 - r.top * m);
    });
  }

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (_geschossBeiLetztemBuild != _s.geschossId) {
      _geschossBeiLetztemBuild = _s.geschossId;
      _entwurf.clear();
      _auswahl = null;
      _eingepasst = false;
      _rueckgaengig.clear();
    }
    final d = _laden();
    _typId ??= d.typen.values.firstOrNull?.id;
    if (_s.objektAuswahl != null) {
      _auswahl = _s.objektAuswahl;
      _setzen = false;
      _s.objektAuswahl = null;
    }
    final gewaehlt = d.objekte.where((o) => o.id == _auswahl).firstOrNull;
    _eigFenster.setzen(auswahl: gewaehlt != null, bauen: () => gewaehlt == null ? const SizedBox() : _eigenschaften(gewaehlt, d));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProjectTree(state: _s),
        Expanded(
          child: Column(children: [
            _werkzeugleiste(d),
            Expanded(
              child: _s.geschossId == null
                  ? const Center(child: Text('Links ein Geschoss wählen.'))
                  : ClipRect(child: _zeichenflaeche(d)),
            ),
            _statuszeile(d),
          ]),
        ),
        Container(
          width: 300,
          decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: BsFarben.rand))),
          padding: const EdgeInsets.all(16),
          child: gewaehlt == null ? _ebenen(d) : _eigFenster.seitenleiste(() => _eigenschaften(gewaehlt, d)),
        ),
      ],
    );
  }

  Widget _werkzeugleiste(_Daten d) {
    final gewerke = [for (final g in d.gewerke.values) if (_sichtbar!.contains(g.id) && d.typen.values.any((t) => t.gewerkId == g.id)) g];
    if (_gewerkId == null || !gewerke.any((g) => g.id == _gewerkId)) {
      _gewerkId = d.typen[_typId]?.gewerkId ?? gewerke.firstOrNull?.id;
      if (!gewerke.any((g) => g.id == _gewerkId)) _gewerkId = gewerke.firstOrNull?.id;
    }
    final typen = d.typen.values.where((t) => t.gewerkId == _gewerkId).toList();
    if (!typen.any((t) => t.id == _typId)) _typId = typen.firstOrNull?.id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
      child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        WerkzeugGruppe(kinder: [
          WerkzeugKnopf(symbol: Sym.auswahl, text: 'Auswahl', tooltip: 'Auswahl (V)', aktiv: !_setzen, onTap: () => setState(() {
                _setzen = false;
                _entwurf.clear();
              })),
          WerkzeugKnopf(symbol: Sym.setzen, text: 'Setzen', tooltip: 'Objekt setzen (P)', aktiv: _setzen, onTap: () => setState(() {
                _setzen = true;
                _entwurf.clear();
              })),
        ]),
        Tooltip(
          message: 'Wie gesetzt wird: Gerät vorher aus der Liste wählen – oder erst in den Plan klicken und dann im Menü neben dem Cursor wählen',
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.list, size: 18), label: Text('aus Liste')),
              ButtonSegment(value: true, icon: Icon(Icons.ads_click, size: 18), label: Text('am Cursor')),
            ],
            selected: {_amOrtWaehlen},
            onSelectionChanged: (v) => setState(() {
              _amOrtWaehlen = v.first;
              _setzen = true;
              _entwurf.clear();
            }),
          ),
        ),
        if (!_amOrtWaehlen)
        GruppenAuswahl<String>(
          hinweis: 'Gerät / Objekt wählen',
          breite: 300,
          wert: _typId,
          gruppen: [
            for (final g in gewerke)
              (g.name, [for (final t in d.typen.values) if (t.gewerkId == g.id) (t.id, '${t.name} (${t.kuerzel})', Color(g.farbe))]),
          ],
          onChanged: (v) => setState(() {
            _typId = v;
            _gewerkId = d.typen[v]?.gewerkId ?? _gewerkId;
            _setzen = true;
            _entwurf.clear();
          }),
        ),
        Tooltip(
          message: 'Verlegeebene für neue Objekte und Leitungen',
          child: DropdownButton<String?>(
            value: _ebeneNeu,
            isDense: true,
            underline: const SizedBox.shrink(),
            hint: const Text('Ebene: Vorgabe'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Ebene: Vorgabe')),
              for (final l in _lagen) DropdownMenuItem<String?>(value: l, child: Text('Ebene: $l')),
            ],
            onChanged: (v) => setState(() => _ebeneNeu = v),
          ),
        ),
        if (_typ?.geometrie == Geometrieart.flaeche)
          FilterChip(
            label: const Text('Ganzer Raum'),
            tooltip: 'Klick in einen Raum legt die Fläche über den ganzen Raum (z. B. Heizkreis nach Raum)',
            selected: _ganzerRaum,
            onSelected: (v) => setState(() => _ganzerRaum = v),
          ),
        if (_typ?.kuerzel == 'HK')
          FilledButton.tonalIcon(
            onPressed: () async {
              final d = _laden();
              final hv = d.objekte.where((o) => d.typen[o.typId]?.kuerzel == 'HV' && o.punkte.isNotEmpty).firstOrNull;
              final n = await heizkreiseNachRaeumen(
                context,
                store: _s.store!,
                geschossId: _s.geschossId!,
                raeume: d.raeume,
                vorhandene: d.objekte,
                hkTyp: _typ!,
                verteiler: hv?.punkte.first,
                status: _status,
              );
              if (n > 0 && mounted) {
                setState(() {});
                zeigeHinweis(context, '$n Heizkreise angelegt');
              }
            },
            icon: const Icon(Icons.grid_view, size: 18),
            label: const Text('Nach Räumen …'),
          ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Status ', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          DropdownButton<ObjektStatus>(
            value: _status,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [for (final s in ObjektStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
        ]),
        PopupMenuButton<String>(
          tooltip: 'Deckenansicht eines Raums öffnen',
          enabled: d.raeume.any((r) => r.umriss != null),
          onSelected: (id) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => DeckePage(state: _s, raumId: id))),
          itemBuilder: (_) => [
            for (final r in d.raeume)
              if (r.umriss != null) PopupMenuItem(value: r.id, child: Text(r.name)),
          ],
          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Sym.decke)),
        ),
        IconButton(tooltip: 'Alles zeigen', onPressed: () => _einpassen(d), icon: const Icon(Sym.allesZeigen)),
        IconButton(tooltip: '3D-Ansicht des Geschosses', onPressed: () => geschoss3dZeigen(context, _s), icon: const Icon(Icons.view_in_ar)),
        IconButton(
          tooltip: 'Rückgängig (Strg+Z)',
          onPressed: _rueckgaengig.isEmpty
              ? null
              : () {
                  _rueckgaengig.removeLast()();
                  setState(() => _auswahl = null);
                  _s.geaendert();
                },
          icon: const Icon(Sym.rueckgaengig),
        ),
      ]),
    );
  }

  Widget _zeichenflaeche(_Daten d) {
    return LayoutBuilder(builder: (context, c) {
      _flaeche = Size(c.maxWidth, c.maxHeight);
      if (!_eingepasst) {
        _eingepasst = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _einpassen(d);
        });
      }
      final typ = _typ;
      return Focus(
        focusNode: _fokus,
        autofocus: true,
        onKeyEvent: _taste,
        child: MouseRegion(
          cursor: _setzen ? SystemMouseCursors.precise : SystemMouseCursors.basic,
          onHover: (e) => setState(() {
            final w = _zuWelt(e.localPosition);
            final hk = _zugangFuer == null ? null : d.objekte.where((o) => o.id == _zugangFuer).firstOrNull;
            if (hk != null && hk.punkte.length >= 3) {
              final m = heizkreisZugang(hk.punkte, zugangAnteil(hk.punkte, Punkt(w.dx, w.dy)), abstand: 0).mitte;
              _maus = Offset(m.x, m.y);
            } else {
              _maus = _setzen ? _fangen(w, d) : null;
            }
          }),
          onExit: (_) => setState(() => _maus = null),
          child: Listener(
            onPointerDown: (e) {
              if (e.buttons == kPrimaryButton && _doppel.erkannt(e.localPosition)) _eigFenster.nachKlickOeffnen(context);
              if (e.buttons == kPrimaryMouseButton && !_ansichtZiehen) {
                _klickGlobal = e.position;
                _klick(e.localPosition);
              }
            },
            onPointerUp: (_) {
              if (_ziehStart != null) _ziehenBeenden();
              if (_rahmenA != null) _rahmenBeenden(d);
            },
            onPointerMove: (e) {
              if (_rahmenA != null && (e.buttons & kPrimaryMouseButton) != 0 && !_ansichtZiehen) {
                setState(() => _rahmenB = _zuWelt(e.localPosition));
                return;
              }
              if (_ziehStart != null && (e.buttons & kPrimaryMouseButton) != 0 && !_ansichtZiehen) {
                setState(() => _ziehVersatz = _ziehVersatzBerechnen(_zuWelt(e.localPosition), d));
                return;
              }
              if ((e.buttons & (kMiddleMouseButton | kSecondaryMouseButton)) != 0 ||
                  (_ansichtZiehen && (e.buttons & kPrimaryMouseButton) != 0)) {
                setState(() => _verschiebung += e.delta);
              }
            },
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                if (HardwareKeyboard.instance.isShiftPressed) {
                  setState(() => _verschiebung -= Offset(e.scrollDelta.dy, e.scrollDelta.dx));
                  return;
                }
                final f = e.scrollDelta.dy > 0 ? 0.88 : 1 / 0.88;
                final neu = (_massstab * f).clamp(0.005, 2.0).toDouble();
                final w = _zuWelt(e.localPosition);
                setState(() {
                  _massstab = neu;
                  _verschiebung = e.localPosition - w * neu;
                });
              }
            },
            onPointerPanZoomUpdate: (e) => setState(() => _verschiebung += e.panDelta),
            child: ClipRect(
              child: Stack(children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: FloorplanPainter(
                      waende: d.waende,
                      raeume: d.raumBilder,
                      umrisse: d.umrisse,
                      schichten: const {},
                      massstab: _massstab,
                      verschiebung: _verschiebung,
                      auswahl: const {},
                      kettenStart: null,
                      maus: null,
                      vorschauDicke: 0,
                      massVoreinstellung: MassAnzeige.keine,
                      oeffnungen: d.oeffnungen,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: ObjektPainter(
                      darstellung: _s.settings.darstellung,
                      abmasse: _abmasse(d),
                      objekte: [
                        for (final o in d.objekte)
                          if (_istSichtbar(o, d))
                            (o.id == _auswahl || (_mehr.contains(_auswahl) && _mehr.contains(o.id))) && _ziehVersatz != Offset.zero
                                ? verschobenesObjekt(o, _ziehVersatz)
                                : o
                      ],
                      typen: d.typen,
                      gewerke: d.gewerke,
                      massstab: _massstab,
                      verschiebung: _verschiebung,
                      auswahl: _auswahl,
                      entwurf: List.of(_entwurf),
                      entwurfFarbe: typ == null ? null : Color(d.gewerke[typ.gewerkId]?.farbe ?? 0xFF888888),
                      entwurfFlaeche: typ?.geometrie == Geometrieart.flaeche,
                      maus: _maus,
                      waende: [for (final w in d.waende) wandStrecke(w)],
                      zug: _auswahl == null ? const {} : leitungsZug(_auswahl!, d.objekte),
                      markiert: {..._s.markiert, ..._mehr},
                      freiePlaetze: [for (final (_, q) in _freiePlaetze(d)) q],
                    ),
                  ),
                ),
                if (_rahmenA != null && _rahmenB != null)
                  Positioned.fromRect(
                    rect: Rect.fromPoints(_rahmenA! * _massstab + _verschiebung, _rahmenB! * _massstab + _verschiebung),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: BsFarben.akzent.withValues(alpha: 0.08),
                          border: Border.all(color: BsFarben.akzent),
                        ),
                      ),
                    ),
                  ),
                if (_mehr.length > 1)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Chip(
                        avatar: const Icon(Icons.select_all, size: 16),
                        label: Text('${_mehr.length} gewählt · ziehen verschiebt alle · Entf löscht alle'),
                      ),
                      const SizedBox(width: 8),
                      if (_mehr.length <= 5 &&
                          d.objekte.where((o) => _mehr.contains(o.id)).every((o) => d.typen[o.typId]?.geometrie == Geometrieart.punkt))
                        ActionChip(
                          avatar: const Icon(Icons.view_week_outlined, size: 16),
                          label: const Text('Zu Mehrfachrahmen verbinden'),
                          onPressed: () => _rahmenVerbinden([for (final o in d.objekte) if (_mehr.contains(o.id)) o], d),
                        ),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
      );
    });
  }

  Widget _statuszeile(_Daten d) {
    final t = _typ;
    final hinweis = !_setzen || t == null
        ? 'Objekt anklicken · Umschalt/Strg-Klick oder Rahmen: mehrere · Doppelklick auf eine Wand öffnet die Wandansicht · Entf löscht · Strg+Z rückgängig'
        : switch (t.geometrie) {
            Geometrieart.punkt => '${t.name}: klicken setzt (fängt Wandoberfläche und vorhandene Punkte)',
            Geometrieart.linie => '${t.name}: Punkte klicken · Enter oder gleicher Punkt beendet · Rücktaste nimmt den letzten zurück · Umschalt: rechtwinklig',
            Geometrieart.flaeche => '${t.name}: Eckpunkte klicken · Enter schließt die Fläche',
          };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: Colors.white,
      child: Text('$hinweis   ·   Mittlere/rechte Maustaste: verschieben · Mausrad: zoomen',
          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
    );
  }

  Widget _ebenen(_Daten d) {
    final anzahl = _s.geschossId == null ? <String, int>{} : _s.store!.objekteJeGewerk(_s.geschossId!);
    return Material(color: Colors.white, child: ListView(children: [
      Text('Ebenen', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text('Jedes Gewerk ist eine Ebene. Ausgeblendete Gewerke lassen sich weder sehen noch fangen.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      for (final g in d.gewerke.values)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _sichtbar!.contains(g.id),
          onChanged: (v) => setState(() {
            v == true ? _sichtbar!.add(g.id) : _sichtbar!.remove(g.id);
            _entwurf.clear();
          }),
          secondary: Container(width: 14, height: 14, color: Color(g.farbe)),
          title: Text(g.name),
          subtitle: Text('${anzahl[g.id] ?? 0} Objekte'),
        ),
      const SizedBox(height: 16),
      Text('Verlegeebenen', style: Theme.of(context).textTheme.titleMedium),
      const Text('Wo Leitungen und Objekte liegen. Neue Objekte bekommen die oben gewählte Ebene.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      for (final l in _lagen)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: !_ebenenAus.contains(l),
          onChanged: (v) => setState(() => v == true ? _ebenenAus.remove(l) : _ebenenAus.add(l)),
          secondary: _eigeneEbenen.where((e) => e['name'] == l).map((e) => Container(width: 14, height: 14, color: Color((e['farbe'] as num?)?.toInt() ?? 0xFF868E96))).firstOrNull,
          title: Text(l),
          subtitle: Text([
            '${d.objekte.where((o) => o.lage == l).length} Objekte',
            for (final e in _eigeneEbenen.where((e) => e['name'] == l)) _ebeneBeschreibung(e),
          ].join(' · ')),
        ),
      TextButton.icon(onPressed: _ebeneAnlegen, icon: const Icon(Icons.add, size: 18), label: const Text('Eigene Verlegeebene …')),
    ]));
  }

  /// Eigene Verlegeebenen des Projekts (z. B. Dämmlage unter dem Estrich mit Leerrohren).
  List<Map<String, dynamic>> get _eigeneEbenen =>
      [for (final e in (_s.store?.einstellung<List>('verlegeebenen') ?? const [])) Map<String, dynamic>.from(e as Map)];

  List<String> get _lagen => [...objektLagen, for (final e in _eigeneEbenen) if (!objektLagen.contains(e['name'])) '${e['name']}'];

  String _ebeneBeschreibung(Map<String, dynamic> e) => [
        if (e['von_mm'] != null || e['bis_mm'] != null) '${e['von_mm'] ?? '?'}–${e['bis_mm'] ?? '?'} mm ${e['bezug'] ?? 'über Rohdecke'}',
        if ((e['schicht'] as String? ?? '').isNotEmpty) 'in ${e['schicht']}',
      ].join(', ');

  Future<void> _ebeneAnlegen() async {
    final name = TextEditingController(), von = TextEditingController(), bis = TextEditingController(), schicht = TextEditingController();
    var bezug = 'über Rohdecke';
    var farbe = 0xFF1098AD;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Eigene Verlegeebene'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name', hintText: 'z. B. Leerrohre in der Dämmlage')),
              Row(children: [
                Expanded(child: TextField(controller: von, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Höhe von', suffixText: 'mm'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: bis, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'bis', suffixText: 'mm'))),
              ]),
              DropdownButtonFormField<String>(
                initialValue: bezug,
                decoration: const InputDecoration(labelText: 'gemessen'),
                items: const [
                  DropdownMenuItem(value: 'über Rohdecke', child: Text('über Rohdecke')),
                  DropdownMenuItem(value: 'unter FFB', child: Text('unter Fertigfußboden')),
                  DropdownMenuItem(value: 'unter Decke', child: Text('unter Rohdecke (oben)')),
                  DropdownMenuItem(value: 'ab Wandoberfläche', child: Text('ab Wandoberfläche (Tiefe)')),
                ],
                onChanged: (v) => bezug = v ?? bezug,
              ),
              TextField(controller: schicht, decoration: const InputDecoration(labelText: 'Schicht im Aufbau (optional)', hintText: 'z. B. Trittschalldämmung, Ausgleichsdämmung')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final f in const [0xFF1098AD, 0xFF7048E8, 0xFFE8590C, 0xFF2F9E44, 0xFFC2255C, 0xFF495057])
                  InkWell(
                    onTap: () => setD(() => farbe = f),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(color: Color(f), border: Border.all(width: farbe == f ? 3 : 0, color: Colors.black54)),
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Anlegen')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    final liste = [
      ..._eigeneEbenen.where((e) => e['name'] != name.text.trim()),
      {
        'name': name.text.trim(),
        if (int.tryParse(von.text) != null) 'von_mm': int.parse(von.text),
        if (int.tryParse(bis.text) != null) 'bis_mm': int.parse(bis.text),
        'bezug': bezug,
        if (schicht.text.trim().isNotEmpty) 'schicht': schicht.text.trim(),
        'farbe': farbe,
      },
    ];
    _s.store!.einstellungSetzen('verlegeebenen', liste);
    setState(() => _ebeneNeu = name.text.trim());
  }

  /// Fußbodenheizung: Verlegeabstand, Muster, Randabstand, Zuleitung, Rohrlänge.
  /// Einbau und Material: Dose, Zuleitung (Rohr + Kabel), Mehrfachrahmen bei
  /// Geräten; Rohr und Kabel bei Leitungen. Abmaße werden mitgespeichert, damit
  /// Plan und Wandansicht die realen Größen zeichnen.
  List<Widget> _einbauFelder(Objekt o, Objekttyp? typ, void Function(Map<String, Object?>) aendern) {
    if (typ == null) return const [];
    final eig = o.eigenschaften;
    void setzen(Map<String, Object?> neu) => aendern({'eigenschaften': jsonEncode({...eig, ...neu}..removeWhere((_, v) => v == null))});
    final elektro = const {'SD', 'SC', 'TA', 'ND', 'AP', 'HD', 'DS', 'RT', 'LE', 'PM', 'BM', 'RM'}.contains(typ.kuerzel);
    if (typ.geometrie == Geometrieart.linie) {
      final kabel = [for (final k in (eig['kabel_liste'] as List? ?? const [])) '$k'];
      double breite(String? rohr, List<String> kabel) {
        final store = _s.store!;
        final r = _s.bibliothek.fuerProjekt(store, rohr)?.zahl('aussendurchmesser')?.toDouble() ?? 0;
        final k = kabel.map((id) => _s.bibliothek.fuerProjekt(store, id)?.zahl('aussendurchmesser')?.toDouble() ?? 0).fold<double>(0, (a, b) => a + b);
        return math.max(r, k);
      }

      return [
        const SizedBox(height: 10),
        Text('Material der Leitung', style: Theme.of(context).textTheme.titleSmall),
        BauelementWahl(
          state: _s,
          label: 'Rohr / Leerrohr',
          wert: eig['rohr'] as String?,
          kategorien: const [BauelementKategorie.rohr],
          nurKategorien: true,
          onChanged: (e) => setzen({'rohr': e?.id, 'breite_mm': breite(e?.id, kabel)}),
        ),
        for (final (i, k) in kabel.indexed)
          Row(children: [
            Expanded(
              child: BauelementWahl(
                state: _s,
                label: 'Kabel ${i + 1}${eig['rohr'] != null ? ' (im Rohr)' : ''}',
                wert: k,
                kategorien: const [BauelementKategorie.kabel],
                nurKategorien: true,
                onChanged: (e) {
                  final neu = [...kabel];
                  if (e == null) {
                    neu.removeAt(i);
                  } else {
                    neu[i] = e.id;
                  }
                  setzen({'kabel_liste': neu, 'breite_mm': breite(eig['rohr'] as String?, neu)});
                },
              ),
            ),
          ]),
        TextButton.icon(
          onPressed: () {
            final erstes = _s.bibliothek.auswahl(_s.store, BauelementKategorie.kabel).firstOrNull;
            if (erstes == null) return;
            BauelementBibliothek.insProjekt(_s.store!, erstes);
            final neu = [...kabel, erstes.id];
            setzen({'kabel_liste': neu, 'breite_mm': breite(eig['rohr'] as String?, neu)});
          },
          icon: const Icon(Sym.hinzufuegen, size: 18),
          label: const Text('Kabel hinzufügen'),
        ),
        if ((eig['breite_mm'] as num? ?? 0) > 0)
          Text('Breite ${(eig['breite_mm'] as num).toStringAsFixed(1).replaceAll('.', ',')} mm – so breit zeichnet der Plan die Leitung.',
              style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      ];
    }
    if (typ.geometrie != Geometrieart.punkt || !elektro) return const [];
    final rahmen = Map<String, dynamic>.from(eig['rahmen'] as Map? ?? const {});
    final fach = (rahmen['fach'] as num?)?.toInt() ?? 1;
    return [
      const SizedBox(height: 10),
      Text('Einbau', style: Theme.of(context).textTheme.titleSmall),
      BauelementWahl(
        state: _s,
        label: 'Dose',
        wert: eig['dose'] as String?,
        kategorien: const [BauelementKategorie.dose],
        nurKategorien: true,
        onChanged: (e) => setzen({'dose': e?.id, 'dose_d': e?.zahl('durchmesser'), 'dose_t': e?.zahl('tiefe')}),
      ),
      BauelementWahl(
        state: _s,
        label: 'Zuleitung: Rohr',
        wert: eig['zuleitung_rohr'] as String?,
        kategorien: const [BauelementKategorie.rohr],
        nurKategorien: true,
        onChanged: (e) => setzen({'zuleitung_rohr': e?.id}),
      ),
      BauelementWahl(
        state: _s,
        label: 'Zuleitung: Kabel',
        wert: eig['zuleitung_kabel'] as String?,
        kategorien: const [BauelementKategorie.kabel],
        nurKategorien: true,
        onChanged: (e) => setzen({'zuleitung_kabel': e?.id}),
      ),
      const SizedBox(height: 8),
      if (eig['rahmen_gruppe'] is String)
        Row(children: [
          const Icon(Icons.view_week_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Im Mehrfachrahmen mit ${[for (final x in _laden().objekte) if (x.eigenschaften['rahmen_gruppe'] == eig['rahmen_gruppe'] && x.id != o.id) x.kennung].join(', ')}',
                style: const TextStyle(fontSize: 12)),
          ),
          TextButton(onPressed: () => _rahmenLoesen(eig['rahmen_gruppe'] as String, _laden()), child: const Text('Auflösen')),
        ]),
      if (eig['rahmen_gruppe'] is String)
        Builder(builder: (_) {
          final dd = _laden();
          final gid = eig['rahmen_gruppe'] as String;
          final leiter = dd.objekte.where((x) => x.id == gid).firstOrNull;
          final anzahl = dd.objekte.where((x) => x.eigenschaften['rahmen_gruppe'] == gid).length;
          final f0 = ((leiter?.eigenschaften['rahmen'] as Map?)?['fach'] as num?)?.toInt() ?? anzahl;
          return DropdownButtonFormField<int>(
            key: ValueKey('rgf-$gid-$f0'),
            initialValue: f0.clamp(anzahl, 5),
            decoration: InputDecoration(labelText: 'Rahmengröße', helperText: f0 > anzahl ? '${f0 - anzahl} freie Plätze – Gerät dort hinein setzen (Fang)' : null),
            items: [for (var n = anzahl; n <= 5; n++) DropdownMenuItem(value: n, child: Text('$n-fach'))],
            onChanged: (n) {
              if (leiter == null || n == null) return;
              final r0 = Map<String, dynamic>.from(leiter.eigenschaften['rahmen'] as Map? ?? const {});
              _s.store!.objektAendern(leiter.id, {'eigenschaften': jsonEncode({...leiter.eigenschaften, 'rahmen': {...r0, 'fach': n}})});
              _s.geaendert();
              setState(() {});
            },
          );
        })
      else
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('rahmen-${o.id}-$fach'),
            initialValue: fach,
            decoration: const InputDecoration(labelText: 'Abdeckrahmen'),
            items: [for (var n = 1; n <= 5; n++) DropdownMenuItem(value: n, child: Text(n == 1 ? 'einzeln' : '$n-fach'))],
            onChanged: (v) => setzen({'rahmen': v == null || v == 1 ? null : {...rahmen, 'fach': v}}),
          ),
        ),
        const SizedBox(width: 8),
        if (fach > 1)
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('rahmenr-${o.id}-${rahmen['richtung']}'),
              initialValue: rahmen['richtung'] == 's' ? 's' : 'w',
              decoration: const InputDecoration(labelText: 'Richtung'),
              items: const [DropdownMenuItem(value: 'w', child: Text('waagerecht')), DropdownMenuItem(value: 's', child: Text('senkrecht'))],
              onChanged: (v) => setzen({'rahmen': {...rahmen, 'fach': fach, 'richtung': v}}),
            ),
          ),
      ]),
      if (fach > 1)
        SpeicherFeld(
          key: ValueKey('rahmeni-${o.id}'),
          initialValue: [for (final x in (rahmen['inhalt'] as List? ?? const [])) '$x'].join(', '),
          decoration: const InputDecoration(labelText: 'Belegung des Rahmens', helperText: 'z. B. TA, SD, SD – von links bzw. oben'),
          onFieldSubmitted: (v) => setzen({
            'rahmen': {...rahmen, 'fach': fach, 'inhalt': v.split(',').map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty).toList()},
          }),
        ),
    ];
  }

  List<Widget> _fbhFelder(Objekt o, _Daten d, void Function(Map<String, Object?>) aendern) {
    final e = FbhEinstellung.ausJson(o.eigenschaften);
    final laenge = rohrlaenge(o.punkte, e);
    void setzen(String k, Object v) => aendern({'eigenschaften': jsonEncode({...o.eigenschaften, k: v})});
    final verteiler = [
      for (final v in d.objekte)
        if (d.typen[v.typId]?.kuerzel == 'HV' && v.punkte.isNotEmpty) v
    ];
    return [
      const SizedBox(height: 12),
      Text('Fußbodenheizung', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('va-${o.id}-${e.abstand}'),
            initialValue: const [75, 100, 125, 150, 200, 250, 300].contains(e.abstand) ? e.abstand : 150,
            decoration: const InputDecoration(labelText: 'Verlegeabstand'),
            items: [for (final v in const [75, 100, 125, 150, 200, 250, 300]) DropdownMenuItem(value: v, child: Text('$v mm'))],
            onChanged: (v) => setzen('va_mm', v ?? 150),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('muster-${o.id}-${e.muster.name}'),
            initialValue: e.muster.name,
            decoration: const InputDecoration(labelText: 'Muster'),
            items: [for (final m in Verlegemuster.values) DropdownMenuItem(value: m.name, child: Text(m.label))],
            onChanged: (v) => setzen('muster', v ?? 'schnecke'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('rand-${o.id}-${e.rand}'),
            initialValue: '${e.rand}',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Randabstand', suffixText: 'mm'),
            onFieldSubmitted: (v) => setzen('rand_mm', int.tryParse(v) ?? 100),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('zul-${o.id}-${e.zuleitung}'),
            initialValue: '${e.zuleitung}',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Zuleitung (einfach)', suffixText: 'mm'),
            onFieldSubmitted: (v) => aendern({
              'eigenschaften': jsonEncode({...o.eigenschaften, 'zuleitung_mm': int.tryParse(v) ?? 0, 'zuleitung_manuell': true}),
            }),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('rz-${o.id}-${e.randzone}'),
            initialValue: '${e.randzone}',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Randzone (0 = keine)', suffixText: 'mm', helperText: 'z. B. 1000 vor Fensterfronten'),
            onFieldSubmitted: (v) => setzen('randzone_mm', int.tryParse(v) ?? 0),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('varz-${o.id}-${e.abstandRand}'),
            initialValue: const [50, 75, 100, 125, 150].contains(e.abstandRand) ? e.abstandRand : 100,
            decoration: const InputDecoration(labelText: 'Abstand in Randzone'),
            items: [for (final v in const [50, 75, 100, 125, 150]) DropdownMenuItem(value: v, child: Text('$v mm'))],
            onChanged: (v) => setzen('va_rand_mm', v ?? 100),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Text('Sperrflächen (${e.sperren.length})', style: Theme.of(context).textTheme.titleSmall),
      const Text('Darunter wird kein Rohr verlegt (Küchenzeile, Dusche, Wanne, Gerät). Das Rohr läuft um sie herum.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Wrap(spacing: 6, runSpacing: 4, children: [
        _sperrFuer == o.id
            ? OutlinedButton.icon(
                onPressed: () => setState(() {
                  _sperrFuer = null;
                  _sperrStart = null;
                }),
                icon: const Icon(Icons.close, size: 18),
                label: Text(_sperrStart == null ? 'Erste Ecke klicken … (abbrechen)' : 'Gegenüberliegende Ecke klicken …'),
              )
            : OutlinedButton.icon(
                onPressed: () => setState(() {
                  _sperrFuer = o.id;
                  _sperrStart = null;
                }),
                icon: const Icon(Icons.crop_square, size: 18),
                label: const Text('Sperrfläche zeichnen'),
              ),
        OutlinedButton.icon(
          onPressed: () {
            // Geräte mit Aufstellfläche im Kreis übernehmen
            final neu = [
              for (final x in d.objekte)
                if (x.id != o.id && x.punkte.length == 1 && x.eigenschaften['masse'] is List && x.eigenschaften['montage'] != 'Wand' &&
                    punktInPolygon(x.punkte.first, o.punkte))
                  aufstellflaeche(x.punkte.first, ((x.eigenschaften['masse'] as List)[0] as num).toDouble(),
                      ((x.eigenschaften['masse'] as List)[1] as num).toDouble(), (x.eigenschaften['drehung'] as num?) ?? 0),
            ];
            if (neu.isEmpty) {
              zeigeHinweis(context, 'Keine Geräte mit Aufstellfläche in diesem Heizkreis.');
              return;
            }
            setzen('sperren', sperrenJson([...e.sperren, ...neu]));
          },
          icon: const Icon(Icons.kitchen_outlined, size: 18),
          label: const Text('Aus Geräten übernehmen'),
        ),
        if (e.sperren.isNotEmpty)
          TextButton.icon(
            onPressed: () => setzen('sperren', <Object>[]),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Alle entfernen'),
          ),
      ]),
      if (verlegeplanKreuzungen(verlegeplan(o.punkte, e)) > 0)
        const Text('Achtung: Das Rohr kreuzt sich – Zugang an eine andere Stelle legen.', style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
      if (e.sperren.isNotEmpty && e.muster != Verlegemuster.schnecke)
        const Text('Mit Sperrflächen wird schneckenförmig verlegt.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 12),
      Text('Rohr und System (läuft in die Besorgungsliste)', style: Theme.of(context).textTheme.titleSmall),
      for (final (k, m, einheit) in fbhBedarf(o.punkte, o.eigenschaften))
        BauelementWahl(
          state: _s,
          label: '${fbhMaterialFelder.firstWhere((f) => f.$1 == k).$2} · ${m.toStringAsFixed(einheit == 'Stk' ? 0 : 1).replaceAll('.', ',')} $einheit',
          wert: o.eigenschaften[k] as String?,
          kategorien: switch (k) {
            'heizrohr' => const [BauelementKategorie.rohr],
            'systemplatte' || 'randstreifen' => const [BauelementKategorie.daemmstoff, BauelementKategorie.baustoff],
            'verschraubung' => const [BauelementKategorie.verbinder],
            _ => const [BauelementKategorie.kleinmaterial, BauelementKategorie.verbinder],
          },
          nurKategorien: true,
          onChanged: (b) => setzen(k, b?.id ?? ''),
        ),
      const SizedBox(height: 8),
      Text('Zugang in die Fläche (Vorlauf rot, Rücklauf blau)', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      _zugangFuer == o.id
          ? OutlinedButton.icon(
              onPressed: () => setState(() => _zugangFuer = null),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Jetzt auf den Rand klicken … (abbrechen)'),
            )
          : FilledButton.tonalIcon(
              onPressed: () => setState(() => _zugangFuer = o.id),
              icon: const Icon(Icons.ads_click, size: 18),
              label: const Text('Zugang im Plan anklicken'),
            ),
      if (verteiler.isNotEmpty)
        TextButton.icon(
          onPressed: () {
            // Zugang an die dem Verteiler nächste Stelle des Umrisses legen
            final v = verteiler.reduce((a, b) {
              double ab(Objekt x) => o.punkte.map((q) => (q - x.punkte.first).laenge).reduce(math.min);
              return ab(a) <= ab(b) ? a : b;
            });
            setzen('zugang', double.parse(zugangAnteil(o.punkte, v.punkte.first).toStringAsFixed(3)));
          },
          icon: const Icon(Icons.my_location, size: 18),
          label: const Text('Zugang zum Verteiler hin legen'),
        ),
      if (o.eigenschaften['anbindung'] is String)
        Text('Anbindeleitung verbunden – Zuleitung aus ihrer Länge${o.eigenschaften['zuleitung_manuell'] == true ? ' (von Hand überschrieben)' : ''}.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF2F9E44))),
      if (verteiler.isNotEmpty)
        TextButton.icon(
          onPressed: () {
            // kürzester Weg vom Verteiler zur nächsten Ecke des Kreises, rechtwinklig gelegt
            var best = double.infinity;
            for (final v in verteiler) {
              final p = v.punkte.first;
              for (final q in o.punkte) {
                best = math.min(best, (p.x - q.x).abs() + (p.y - q.y).abs());
              }
            }
            setzen('zuleitung_mm', best.round());
          },
          icon: const Icon(Icons.call_split, size: 18),
          label: const Text('Zuleitung vom Heizkreisverteiler'),
        ),
      if (verteiler.isNotEmpty)
        TextButton.icon(
          onPressed: () => _anbindungZeichnen(o, d, verteiler),
          icon: const Icon(Icons.alt_route, size: 18),
          label: const Text('Anbindeleitungen VL/RL zum Verteiler zeichnen'),
        ),
      const SizedBox(height: 6),
      Text('Rohrlänge ${meterText(laenge)} (inkl. Vor- und Rücklauf)',
          style: TextStyle(fontWeight: FontWeight.w600, color: laenge > maxKreislaenge ? const Color(0xFFB91C1C) : null)),
      if (laenge > maxKreislaenge)
        const Text('Über 120 m: Kreis teilen oder Verlegeabstand vergrößern.',
            style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
    ];
  }

  /// Vor- und Rücklauf als Anbindeleitungen (HR) vom Zugang des Kreises zum
  /// nächsten Heizkreisverteiler, rechtwinklig und durch die Tür des Raums.
  void _anbindungZeichnen(Objekt hk, _Daten d, List<Objekt> verteiler) {
    final store = _s.store!;
    final hr = d.typen.values.where((t) => t.kuerzel == 'HR').firstOrNull;
    final z = verlegeplan(hk.punkte, FbhEinstellung.ausJson(hk.eigenschaften));
    if (hr == null || z.anschlussVl == null || z.anschlussRl == null) return;
    final v = verteiler.reduce((a, b) => (a.punkte.first - z.anschlussVl!).laenge <= (b.punkte.first - z.anschlussVl!).laenge ? a : b);
    final raum = d.raeume.where((r) => r.id == hk.raumId).firstOrNull?.umriss ??
        d.raeume.where((r) => r.umriss != null && r.umriss!.length >= 3 && punktInPolygon(hk.punkte.first, r.umriss!)).firstOrNull?.umriss;
    final waende = {for (final w in d.waende) w.id: w};
    final tueren = <Durchgang>[
      for (final oe in d.oeffnungen)
        if (oe.art == OeffnungsArt.tuer && waende[oe.wandId] != null)
          () {
            final w = waende[oe.wandId]!;
            final a = Punkt(w.x1.toDouble(), w.y1.toDouble()), b = Punkt(w.x2.toDouble(), w.y2.toDouble());
            final r = (b - a) * (1 / math.max(1, (b - a).laenge));
            return (mitte: a + r * (oe.abstand + oe.breite / 2), richtung: r, dicke: w.dicke.toDouble());
          }(),
    ];
    final va = FbhEinstellung.ausJson(hk.eigenschaften).abstand.toDouble();
    final hv = v.punkte.first;
    final ids = <String>[];
    var summe = 0.0;
    for (final (ende, art, sv) in [(z.anschlussVl!, 'VL', -1.0), (z.anschlussRl!, 'RL', 1.0)]) {
      final weg = anbindeweg(ende, hv + Punkt(sv * 40, 0), raum: raum, tueren: tueren, versatz: sv * va / 2);
      if (weg.length < 2) continue;
      final id = store.objektAnlegen(geschossId: _s.geschossId!, typ: hr, punkte: weg, raumId: hk.raumId, lage: 'im Estrich', status: _status);
      store.objektAendern(id, {'eigenschaften': jsonEncode({'leitung': art, 'heizkreis': hk.id, 'verteiler': v.id})});
      ids.add(id);
      for (var i = 0; i + 1 < weg.length; i++) {
        summe += (weg[i + 1] - weg[i]).laenge;
      }
    }
    if (ids.isEmpty) return;
    final alt = store.objektAendern(hk.id, {
      'eigenschaften': jsonEncode({...hk.eigenschaften, 'zuleitung_mm': (summe / ids.length).round(), 'anbindung': ids.first, 'verteiler': v.id}),
    });
    _rueckgaengig.add(() {
      store.objektAendern(hk.id, alt);
      for (final id in ids) {
        store.objektLoeschen(id);
      }
    });
    setState(() {});
    zeigeHinweis(context, 'Anbindeleitungen gezeichnet (${meterText(summe)} gesamt)');
  }

  /// Heizkreisverteiler: Montageart direkt hier, alles Weitere im Editor.
  List<Widget> _verteilerFelder(Objekt o, _Daten d, void Function(Map<String, Object?>) aendern) {
    final v = VerteilerDaten.ausJson(o.eigenschaften);
    final belegt = v.kreise.where((k) => k != null).length;
    return [
      const SizedBox(height: 12),
      Text('Heizkreisverteiler', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      DropdownButtonFormField<Montage>(
        key: ValueKey('montage-${o.id}-${v.montage.name}'),
        initialValue: v.montage,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Montageart'),
        items: [for (final m in Montage.values) DropdownMenuItem(value: m, child: Text(m.label))],
        onChanged: (m) => aendern({
          'eigenschaften': jsonEncode({...o.eigenschaften, ...(v..montage = m ?? v.montage).toJson()}),
        }),
      ),
      const SizedBox(height: 6),
      Text('${v.abgaenge} Abgänge, $belegt belegt · Schrank ca. ${v.schrankBreite} × ${v.schrankHoehe} × ${v.montage.tiefe} mm',
          style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => VerteilerEditor(state: _s, objektId: o.id))),
        icon: const Icon(Sym.heizkreisverteiler, size: 18),
        label: const Text('Verteiler bearbeiten …'),
      ),
    ];
  }

  /// Wand und Seite, an der ein Gerät sitzt: (Wand, links, x ab linker Kante).
  (Wand, bool, double, Raum?)? wandLage(Objekt o, _Daten d) {
    if (o.punkte.length != 1) return null;
    final p = Offset(o.punkte.first.x, o.punkte.first.y);
    final verbinden = _s.store!.einstellung<bool>('ecken_verbinden') ?? true;
    (Wand, bool, double, Raum?)? beste;
    var bester = 40.0;
    for (final w in d.waende) {
      for (final links in [true, false]) {
        final s = WandSeite.berechnen(w, d.waende, d.raeume, verbinden, links);
        final x = s.x(p), vor = s.vor(p);
        if (x < -1 || x > s.laenge + 1) continue;
        // auf der Oberfläche oder (Durchbruch) in der Wand
        final abst = vor >= 0 ? vor : (vor.abs() <= w.dicke + 1 ? 0.5 : double.infinity);
        if (abst < bester) {
          bester = abst;
          beste = (w, links, x, s.raum);
        }
      }
    }
    return beste;
  }

  List<Widget> _wandInfo(Objekt o, _Daten d) {
    if (d.typen[o.typId]?.geometrie != Geometrieart.punkt) return const [];
    final lage = wandLage(o, d);
    if (lage == null) {
      return [
        const SizedBox(height: 6),
        const Text('Sitzt an keiner Wand. Zum Einrasten nahe an eine Wandoberfläche setzen oder ziehen.',
            style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
      ];
    }
    final (w, links, x, raum) = lage;
    return [
      const SizedBox(height: 8),
      Text(
          'An der Wand, Seite ${raum?.name ?? 'außen'} · ${mmText(x)} mm von der linken Wandkante'
          '${o.lage == 'durch Wand' ? ' · durch die ganze Wand (${mmText(w.dicke)} mm)' : ''}',
          style: const TextStyle(fontSize: 12)),
      TextButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => WandansichtPage(state: _s, wandId: w.id, links: links))),
        icon: const Icon(Icons.view_agenda_outlined, size: 18),
        label: const Text('in der Wandansicht zeigen'),
      ),
    ];
  }

  /// Wanddurchbruch: Durchmesser bzw. Größe.
  List<Widget> _durchbruchFelder(Objekt o, _Daten d, void Function(Map<String, Object?>) aendern) {
    final dm = (o.eigenschaften['durchmesser_mm'] as num?)?.toInt() ?? 50;
    return [
      const SizedBox(height: 8),
      SpeicherFeld(
        key: ValueKey('dm-${o.id}-$dm'),
        initialValue: '$dm',
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Durchmesser / Kernbohrung', suffixText: 'mm'),
        onFieldSubmitted: (v) => aendern({
          'eigenschaften': jsonEncode({...o.eigenschaften, 'durchmesser_mm': int.tryParse(v) ?? 50}),
        }),
      ),
      const SizedBox(height: 4),
      const Text('Erscheint in der Wandansicht beider Seiten. Leitungen auf beiden Seiten am Durchbruch anschließen.',
          style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
    ];
  }

  /// Zuordnung zu einem Stromkreis aus der Schrankplanung (Modul Verteiler).
  List<Widget> _stromkreisFeld(Objekt o, void Function(Map<String, Object?>) aendern) {
    final store = _s.store!;
    final kreise = [
      for (final s in store.schraenke())
        for (final k in store.stromkreise(s.id)) (s, k),
    ];
    final aktuell = o.eigenschaften['stromkreis'];
    return [
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(
        key: ValueKey('sk-${o.id}-$aktuell'),
        initialValue: kreise.any((e) => e.$2.id == aktuell) ? aktuell as String : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Stromkreis',
          helperText: kreise.isEmpty ? 'Stromkreise legst du im Modul Verteiler an' : null,
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('– keiner –')),
          for (final (s, k) in kreise)
            DropdownMenuItem(value: k.id, child: Text('=${s.kennzeichen} · ${k.nummer} ${k.bezeichnung}')),
        ],
        onChanged: (v) {
          final neu = {...o.eigenschaften};
          if (v == null) {
            neu.remove('stromkreis');
          } else {
            neu['stromkreis'] = v;
          }
          aendern({'eigenschaften': jsonEncode(neu)});
        },
      ),
      ..._ketteFelder(o, aendern),
      ..._smartHomeFelder(o, aendern),
    ];
  }

  /// Verdrahtungskette: gespeist von (Stromkreis oder anderem Gerät), Schaltung, Hinweise.
  List<Widget> _ketteFelder(Objekt o, void Function(Map<String, Object?>) aendern) {
    final d = _laden();
    final typ = d.typen[o.typId];
    if (typ?.geometrie != Geometrieart.punkt) return const [];
    final eig = o.eigenschaften;
    void setzen(String k, Object? v) {
      final neu = {...eig};
      if (v == null) {
        neu.remove(k);
      } else {
        neu[k] = v;
      }
      aendern({'eigenschaften': jsonEncode(neu)});
    }

    Kettenglied glied(Objekt x) {
      final kabel = _s.bibliothek.fuerProjekt(_s.store!, x.eigenschaften['zuleitung_kabel'] as String?);
      return (
        id: x.id,
        kennung: x.kennung,
        kuerzel: d.typen[x.typId]?.kuerzel ?? '?',
        gespeistVon: x.eigenschaften['gespeist_von'] as String?,
        adern: kabel?.zahl('adern')?.toInt(),
        querschnitt: kabel?.zahl('querschnitt')?.toDouble(),
        leistung: (x.eigenschaften['leistung_w'] as num?)?.toInt() ?? (d.typen[x.typId]?.kuerzel == 'SD' ? 200 : 0),
      );
    }

    final kandidaten = [
      for (final x in d.objekte)
        if (x.id != o.id && d.typen[x.typId]?.geometrie == Geometrieart.punkt && d.typen[x.typId]?.gewerkId == typ?.gewerkId) x
    ];
    final alle = [for (final x in d.objekte) if (d.typen[x.typId]?.geometrie == Geometrieart.punkt) glied(x)];
    final gid = eig['rahmen_gruppe'];
    final imRahmen = gid is String
        ? [for (final x in d.objekte) if (x.eigenschaften['rahmen_gruppe'] == gid) d.typen[x.typId]?.kuerzel ?? '?']
        : [typ?.kuerzel ?? '?'];
    final schaltung = Schaltung.values.where((x) => x.name == eig['schaltung']).firstOrNull ?? Schaltung.aus;
    final abHier = eig['leuchte_ab_hier'] != false;
    final hinweise = kettenHinweise(geraet: glied(o), imRahmen: imRahmen, alle: alle, schaltung: schaltung, leuchteAbHier: abHier);
    final von = eig['gespeist_von'] as String?;
    return [
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(
        key: ValueKey('gv-${o.id}-$von'),
        initialValue: kandidaten.any((x) => x.id == von) ? von : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Gespeist von', helperText: 'Dose zu Dose weiterschleifen – oder direkt vom Stromkreis'),
        items: [
          const DropdownMenuItem(value: null, child: Text('– direkt vom Stromkreis / Verteiler –')),
          for (final x in kandidaten) DropdownMenuItem(value: x.id, child: Text('${x.kennung} · ${d.typen[x.typId]?.name ?? ''}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setzen('gespeist_von', v),
      ),
      if (typ?.kuerzel == 'TA') ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('sch-${o.id}-${schaltung.name}'),
          initialValue: schaltung.name,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Schaltung'),
          items: [for (final x in Schaltung.values) DropdownMenuItem(value: x.name, child: Text(x.label))],
          onChanged: (v) => setzen('schaltung', v),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Leitung zur Leuchte geht von dieser Dose ab'),
          value: abHier,
          onChanged: (v) => setzen('leuchte_ab_hier', v == true ? null : false),
        ),
      ],
      for (final h in hinweise)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 14, color: Color(0xFFB45309)),
            const SizedBox(width: 4),
            Expanded(child: Text(h, style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)))),
          ]),
        ),
    ];
  }

  /// KNX-Kanal, Gruppenadressen, physikalische Adresse und Home-Assistant-Entität.
  List<Widget> _smartHomeFelder(Objekt o, void Function(Map<String, Object?>) aendern) {
    final store = _s.store!;
    final kanal = o.eigenschaften['knx_kanal'] as String?;
    String? aktorText;
    if (kanal != null && kanal.contains(':')) {
      final id = kanal.substring(0, kanal.lastIndexOf(':'));
      for (final s in store.schraenke()) {
        final g = store.schrankGeraete(s.id).where((x) => x.id == id).firstOrNull;
        if (g != null) aktorText = '=${s.kennzeichen}${g.kennzeichen} Kanal ${kanal.substring(kanal.lastIndexOf(':') + 1)}';
      }
    }
    final gas = [
      for (final m in (store.einstellung<List>('knx_gruppenadressen') ?? const []))
        if (((m as Map)['objekte'] as List? ?? const []).contains(o.id)) '${m['h']}/${m['m']}/${m['u']} ${m['name']}',
    ];
    void eig(String k, String v) {
      final neu = {...o.eigenschaften};
      if (v.trim().isEmpty) {
        neu.remove(k);
      } else {
        neu[k] = v.trim();
      }
      aendern({'eigenschaften': jsonEncode(neu)});
    }

    return [
      if (aktorText != null) Text('KNX: $aktorText', style: const TextStyle(fontSize: 12)),
      for (final g in gas) Text('GA $g', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      SpeicherFeld(
        key: ValueKey('ha-${o.id}-${o.eigenschaften['ha_entity']}'),
        initialValue: o.eigenschaften['ha_entity'] as String? ?? '',
        decoration: const InputDecoration(labelText: 'Home-Assistant-Entität', hintText: 'light.bad_decke'),
        onFieldSubmitted: (v) => eig('ha_entity', v),
      ),
      if (_s.store!.objekttypen().where((t) => t.id == o.typId).firstOrNull?.kuerzel case 'KX' || 'PM' || 'BM' || 'ES')
        SpeicherFeld(
          key: ValueKey('pa-${o.id}-${o.eigenschaften['knx_pa']}'),
          initialValue: o.eigenschaften['knx_pa'] as String? ?? '',
          decoration: const InputDecoration(labelText: 'Physikalische Adresse (KNX)', hintText: '1.1.20'),
          onFieldSubmitted: (v) => eig('knx_pa', v),
        ),
    ];
  }

  /// Eigener Sensor: Vorlage aus der Bibliothek, Anschlüsse, Entitäten der Instanz.
  List<Widget> _sensorFelder(Objekt o, _Daten d, void Function(Map<String, Object?>) aendern) {
    final vorlagen = sensorVorlagen(_s);
    final v = vorlagen.where((x) => x.id == o.eigenschaften['sensor']).firstOrNull;
    final raum = d.raeume.where((r) => r.id == o.raumId).firstOrNull;
    final entitaeten = Map<String, dynamic>.from(o.eigenschaften['ha_entities'] as Map? ?? const {});
    return [
      const SizedBox(height: 12),
      Text('Eigener Sensor', style: Theme.of(context).textTheme.titleSmall),
      DropdownButtonFormField<String?>(
        key: ValueKey('sv-${o.id}-${v?.id}'),
        initialValue: v?.id,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Vorlage',
          helperText: vorlagen.isEmpty ? 'Vorlagen legst du unter Einstellungen → Eigene Sensoren an' : null,
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('–')),
          for (final x in vorlagen) DropdownMenuItem(value: x.id, child: Text('${x.name} (${x.protokoll})')),
        ],
        onChanged: (id) {
          final x = vorlagen.where((e) => e.id == id).firstOrNull;
          final neu = {...o.eigenschaften}..remove('sensor');
          if (x != null) {
            neu['sensor'] = x.id;
            neu['anschluesse'] = [for (final a in x.anschluesse) {'name': a.name, 'farbe': a.farbe}];
            neu['ha_entities'] = instanzEntitaeten(x, haSlug('${raum?.name ?? ''} ${x.name} ${o.kennung}'));
          }
          aendern({'eigenschaften': jsonEncode(neu)});
        },
      ),
      if (v != null) ...[
        const SizedBox(height: 6),
        Text('${v.kategorie} · ${v.montage} · ${v.versorgung}${v.breite > 0 ? ' · ${v.breite}×${v.hoehe}×${v.tiefe} mm' : ''}',
            style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text('Anschlüsse: ${[for (final a in v.anschluesse) '${a.name} (${a.farbe})'].join(', ')}', style: const TextStyle(fontSize: 12)),
        for (final e in entitaeten.entries)
          SpeicherFeld(
            key: ValueKey('he-${o.id}-${e.key}-${e.value}'),
            initialValue: e.value as String,
            decoration: InputDecoration(labelText: 'Entität ${e.key}'),
            onFieldSubmitted: (x) => aendern({
              'eigenschaften': jsonEncode({
                ...o.eigenschaften,
                'ha_entities': {...entitaeten, e.key: x.trim()},
              }),
            }),
          ),
      ],
    ];
  }

  /// Signal-, Bus- und Netzwerkleitungen: Kabeltyp, Aderbelegung, Topologie.
  List<Widget> _kabelFelder(Objekt o, _Daten d, void Function(Map<String, Object?>) aendern) {
    final kabel = o.eigenschaften['kabel'] as String?;
    final adern = kabelTypen[kabel] ?? const <String>[];
    // Protokoll eines angeschlossenen Sensors (am Anfang oder Ende der Leitung)
    String? protokoll;
    final vorlagen = sensorVorlagen(_s);
    for (final p in [o.punkte.first, o.punkte.last]) {
      for (final s in d.objekte) {
        if (s.punkte.length == 1 && (Offset(s.punkte.first.x, s.punkte.first.y) - Offset(p.x, p.y)).distance < 3) {
          protokoll ??= vorlagen.where((v) => v.id == s.eigenschaften['sensor']).firstOrNull?.protokoll;
        }
      }
    }
    final belegung = Map<String, dynamic>.from(o.eigenschaften['adern'] as Map? ?? (protokoll == null ? const {} : standardBelegung(protokoll)));
    final gleicheArt = [
      for (final x in d.objekte)
        if (x.typId == o.typId && x.punkte.length >= 2) [for (final q in x.punkte) (q.x, q.y)],
    ];
    final topo = topologie(gleicheArt);
    void eig(Map<String, Object?> neu) => aendern({'eigenschaften': jsonEncode({...o.eigenschaften, ...neu})});
    return [
      const SizedBox(height: 12),
      Text('Kabel', style: Theme.of(context).textTheme.titleSmall),
      DropdownButtonFormField<String?>(
        key: ValueKey('kt-${o.id}-$kabel'),
        initialValue: kabelTypen.containsKey(kabel) ? kabel : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Kabeltyp'),
        items: [
          const DropdownMenuItem(value: null, child: Text('–')),
          for (final k in kabelTypen.keys) DropdownMenuItem(value: k, child: Text(k)),
        ],
        onChanged: (v) => eig({'kabel': v}),
      ),
      if (adern.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('Aderbelegung${protokoll == null ? '' : ' (Vorschlag für $protokoll)'}', style: const TextStyle(fontSize: 12)),
        for (final a in adern)
          Row(children: [
            SizedBox(width: 90, child: Text(a, style: const TextStyle(fontSize: 12))),
            Expanded(
              child: SpeicherFeld(
                key: ValueKey('ad-${o.id}-$a-${belegung[a]}'),
                initialValue: belegung[a] as String? ?? '',
                decoration: const InputDecoration(isDense: true, hintText: 'frei'),
                onFieldSubmitted: (v) => eig({'adern': {...belegung, a: v.trim()}..removeWhere((_, x) => x == null || (x as String).isEmpty)}),
              ),
            ),
          ]),
      ],
      if (topo != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Topologie dieser Leitungsart im Geschoss: $topo (${gleicheArt.length} Leitungen)',
              style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        ),
    ];
  }

  /// Grundfläche der Geräte aus ihrem Produkt (Breite × Tiefe bzw. Baulänge × Bautiefe).
  Map<String, (double, double)> _abmasse(_Daten d) {
    final store = _s.store!;
    final m = <String, (double, double)>{};
    for (final o in d.objekte) {
      if (o.punkte.length != 1) continue;
      final be = _s.bibliothek.fuerProjekt(store, o.eigenschaften['bauelement'] as String?);
      if (be == null) continue;
      final b = be.zahl('breite') ?? be.zahl('baulaenge');
      final t = be.zahl('tiefe') ?? be.zahl('bautiefe');
      if (b != null && t != null && b > 0 && t > 0) m[o.id] = (b.toDouble(), t.toDouble());
    }
    return m;
  }

  /// Eigenschaften mit Reitern (Lastenheft): Allgemein, Produkt & Kosten,
  /// Fotos, Verlauf.
  /// Über Geschosse (Steigleitung, Kamin, Treppe) und Treppenwerte.
  List<Widget> _geschossuebergreifend(Objekt o, _Daten d, void Function(Map<String, Object?>) aendern) {
    final store = _s.store!;
    final kuerzel = d.typen[o.typId]?.kuerzel ?? '';
    void setzen(String k, Object? v) {
      final e = {...o.eigenschaften};
      v == null || (v is String && v.isEmpty) ? e.remove(k) : e[k] = v;
      aendern({'eigenschaften': jsonEncode(e)});
    }

    final geschosse = [for (final geb in store.gebaeude()) ...store.geschosse(geb.id)];
    final fremd = o.geschossId != _s.geschossId;
    final widgets = <Widget>[
      const SizedBox(height: 12),
      if (fremd)
        _hinweisBox('Dieses Objekt gehört zum Geschoss „${geschosse.where((g) => g.id == o.geschossId).firstOrNull?.name ?? '?'}“ und läuft bis hierher durch.'),
      DropdownButtonFormField<String?>(
        key: ValueKey('bis-${o.id}-${o.eigenschaften['bis_geschoss']}'),
        initialValue: geschosse.any((g) => g.id == o.eigenschaften['bis_geschoss']) ? o.eigenschaften['bis_geschoss'] as String : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: kuerzel == 'TR' ? 'Treppe führt nach' : 'Läuft über Geschosse bis', isDense: true),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('– nur dieses Geschoss –')),
          for (final g in geschosse)
            if (g.id != o.geschossId) DropdownMenuItem<String?>(value: g.id, child: Text(g.name)),
        ],
        onChanged: (v) => setzen('bis_geschoss', v),
      ),
    ];
    if (kuerzel == 'TR') {
      final t = treppeBerechnen(o);
      Widget feld(String k, String label, int vorgabe) => SizedBox(
            width: 150,
            child: TextFormField(
              key: ValueKey('tr-${o.id}-$k-${o.eigenschaften[k]}'),
              initialValue: '${o.eigenschaften[k] ?? vorgabe}',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: label, isDense: true),
              onFieldSubmitted: (v) => setzen(k, int.tryParse(v.trim())),
            ),
          );
      widgets.addAll([
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          feld('hoehe', 'Höhe FFB → FFB (mm)', 2800),
          feld('breite', 'Laufbreite (mm)', 1000),
          feld('steigungen', 'Steigungen', t.steigungen),
          feld('podest_nach', 'Podest nach Stufe (0 = keins)', 0),
          feld('podest_tiefe', 'Podesttiefe (mm)', 1000),
        ]),
        const SizedBox(height: 6),
        Text('${t.steigungen} Steigungen à ${t.steigung.toStringAsFixed(1).replaceAll('.', ',')} mm, Auftritt ${t.auftritt.round()} mm – ${t.bewertung}. '
            'Zwischenpodest als Fläche: Typ „Treppenpodest“.',
            style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      ]);
    }
    return widgets;
  }

  Widget _hinweisBox(String t) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: BsFarben.akzentHell, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: const TextStyle(fontSize: 12)),
      );

  Widget _eigenschaften(Objekt o, _Daten d) {
    final store = _s.store!;
    final be = _s.bibliothek.fuerProjekt(store, o.eigenschaften['bauelement'] as String?);
    final fotos = [for (final f in store.fotos(o.geschossId)) if (f.objektIds.contains(o.id)) f];
    final verlauf = store.verlauf('objekt', o.id);
    final hk = d.typen[o.typId]?.kuerzel == 'HK';
    return DefaultTabController(
      key: ValueKey('reiter-${o.id}'),
      length: 4,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          tabs: [
            const Tab(icon: Icon(Icons.tune, size: 18), text: 'Allgemein', iconMargin: EdgeInsets.zero),
            Tab(icon: const Icon(Icons.inventory_2_outlined, size: 18), text: hk ? 'Material' : 'Produkt', iconMargin: EdgeInsets.zero),
            const Tab(icon: Icon(Icons.photo_camera_outlined, size: 18), text: 'Fotos', iconMargin: EdgeInsets.zero),
            const Tab(icon: Icon(Icons.history, size: 18), text: 'Verlauf', iconMargin: EdgeInsets.zero),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(children: [
            _eigenschaftenAllgemein(o, d),
            if (hk)
              ListView(children: [
                const Text('Bedarf dieses Heizkreises', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                for (final (k, m, einheit) in fbhBedarf(o.punkte, o.eigenschaften))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(fbhMaterialFelder.firstWhere((f) => f.$1 == k).$2),
                    subtitle: Text(_s.bibliothek.fuerProjekt(store, o.eigenschaften[k] as String?)?.anzeige ?? 'noch nicht gewählt (unter „Allgemein“)'),
                    trailing: Text('${m.toStringAsFixed(einheit == 'Stk' ? 0 : 1).replaceAll('.', ',')} $einheit'),
                  ),
              ])
            else
            ListView(children: [
              if (be == null)
                const Text('Kein Produkt zugeordnet – unter „Allgemein“ ein Produkt aus der Bibliothek wählen.', style: TextStyle(color: BsFarben.textLeise))
              else ...[
                Text(be.anzeige, style: Theme.of(context).textTheme.titleMedium),
                Text(be.kategorie.label, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                const SizedBox(height: 8),
                if (be.artikelnummer.isNotEmpty) Text('Artikelnummer ${be.artikelnummer}'),
                if (be.preisCent != null) Text('Preis netto ${(be.preisCent! / 100).toStringAsFixed(2).replaceAll('.', ',')} €'),
                const SizedBox(height: 8),
                for (final f in be.kategorie.felder)
                  if (be.daten[f.schluessel] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text(f.label, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise))),
                        Text('${be.daten[f.schluessel]}'.replaceAll('.', ',') + (f.einheit.isEmpty ? '' : ' ${f.einheit}'), style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                const SizedBox(height: 10),
                if (_s.bibliothek.datenblattDatei(be)?.existsSync() == true)
                  OutlinedButton.icon(
                    onPressed: () => Process.run('explorer', [_s.bibliothek.datenblattDatei(be)!.path]),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Datenblatt öffnen'),
                  ),
                TextButton.icon(
                  onPressed: () => _s.modulWaehlen(Modul.bauteile),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('In der Bibliothek bearbeiten'),
                ),
              ],
            ]),
            fotos.isEmpty
                ? const Center(child: Text('Noch keine Fotos mit diesem Objekt verknüpft (Modul Fotos).', textAlign: TextAlign.center))
                : GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (final f in fotos)
                        Image.file(File(p.join(store.ordner, f.datei)), fit: BoxFit.cover, cacheWidth: 300, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                    ],
                  ),
            ListView(children: [
              for (final v in verlauf)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.aktion),
                  subtitle: Text(v.daten.length > 120 ? '${v.daten.substring(0, 120)}…' : v.daten, style: const TextStyle(fontSize: 11)),
                  trailing: Text(v.zeit.length >= 16 ? v.zeit.substring(0, 16).replaceFirst('T', ' ') : v.zeit, style: const TextStyle(fontSize: 11)),
                ),
              if (verlauf.isEmpty) const Text('Kein Verlauf.'),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _eigenschaftenAllgemein(Objekt o, _Daten d) {
    final store = _s.store!;
    final typ = d.typen[o.typId];
    final gewerk = d.gewerke[typ?.gewerkId];
    final raum = d.raeume.where((r) => r.id == o.raumId).firstOrNull;
    final g = d.geschoss;
    final h = g == null ? null : (raum?.hoehen(g) ?? g.hoehen);

    void aendern(Map<String, Object?> felder) {
      final alt = store.objektAendern(o.id, felder);
      if (alt.isEmpty) return;
      _rueckgaengig.add(() => store.objektAendern(o.id, alt));
      _s.geaendert();
    }

    return Material(color: Colors.white, child: ListView(children: [
      Row(children: [
        Container(width: 12, height: 12, color: Color(gewerk?.farbe ?? 0xFF888888)),
        const SizedBox(width: 6),
        Text('${gewerk?.name ?? ''} · ${typ?.name ?? ''}', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      ]),
      const SizedBox(height: 4),
      SpeicherFeld(
        key: ValueKey('kennung-${o.id}-${o.kennung}'),
        initialValue: o.kennung,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        decoration: const InputDecoration(border: InputBorder.none, helperText: 'Kennung (bleibt beim Verschieben)'),
        onFieldSubmitted: (v) {
          if (v.trim().isNotEmpty) aendern({'kennung': v.trim().toUpperCase()});
        },
      ),
      BauelementWahl(
        state: _s,
        wert: o.eigenschaften['bauelement'] as String?,
        kategorien: kategorienFuerKuerzel(typ?.kuerzel ?? ''),
        onChanged: (e) => aendern({
          'eigenschaften': jsonEncode({...o.eigenschaften, 'bauelement': e?.id}..removeWhere((_, v) => v == null)),
        }),
      ),
      ..._einbauFelder(o, typ, aendern),
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(
        key: ValueKey('raum-${o.id}-${o.raumId}'),
        initialValue: d.raeume.any((r) => r.id == o.raumId) ? o.raumId : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'gehört zu Raum',
          helperText: 'darf ein anderer Raum sein als der, durch den die Leitung läuft',
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('– kein Raum –')),
          for (final r in d.raeume) DropdownMenuItem(value: r.id, child: Text(r.name)),
        ],
        onChanged: (v) => aendern({'raum_id': v}),
      ),
      if (gewerk?.kuerzel == 'EL' || gewerk?.kuerzel == 'KX') ..._stromkreisFeld(o, aendern),
      ..._wandInfo(o, d),
      if (typ?.kuerzel == 'WD') ..._durchbruchFelder(o, d, aendern),
      if (typ?.geometrie == Geometrieart.linie) Text('Länge ${meterText(o.laenge)}'),
      if (typ?.geometrie == Geometrieart.linie && leitungsZug(o.id, d.objekte).length > 1) ...[
        Text(
            'Leitungszug: ${[for (final x in d.objekte) if (leitungsZug(o.id, d.objekte).contains(x.id)) '${x.kennung} (${x.lage ?? '–'})'].join(' → ')}',
            style: const TextStyle(fontSize: 12)),
        Text(
            'gesamt ${meterText([for (final x in d.objekte) if (leitungsZug(o.id, d.objekte).contains(x.id)) x.laenge].fold(0.0, (a, b) => a + b))}',
            style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      ],
      if (typ?.geometrie == Geometrieart.flaeche) Text('Fläche ${flaecheText(polygonFlaeche(o.punkte).abs())}'),
      if (typ?.kuerzel == 'HK') ..._fbhFelder(o, d, aendern),
      if (typ?.kuerzel == 'HV') ..._verteilerFelder(o, d, aendern),
      if (typ?.kuerzel == 'ES') ..._sensorFelder(o, d, aendern),
      if (typ?.kuerzel == 'SL' || typ?.kuerzel == 'BL' || typ?.kuerzel == 'NK') ..._kabelFelder(o, d, aendern),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('z-${o.id}-${o.z}'),
            initialValue: o.z?.toString() ?? '',
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
            decoration: const InputDecoration(labelText: 'Höhe', suffixText: 'mm'),
            onFieldSubmitted: (v) => aendern({'z_mm': int.tryParse(v.trim())}),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<Hoehenbezug?>(
            key: ValueKey('bezug-${o.id}-${o.zBezug}'),
            initialValue: o.zBezug,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Bezug'),
            items: [
              const DropdownMenuItem(value: null, child: Text('–')),
              for (final b in Hoehenbezug.values) DropdownMenuItem(value: b, child: Text(b.label)),
            ],
            onChanged: (b) {
              // Bezug wechseln, Höhe in den neuen Bezug umrechnen (Lage bleibt gleich)
              final z = o.z, alt = o.zBezug;
              if (z != null && alt != null && b != null && h != null) {
                aendern({'z_bezug': b.name, 'z_mm': umrechnen(z, alt, b, h)});
              } else {
                aendern({'z_bezug': b?.name});
              }
            },
          ),
        ),
      ]),
      if (o.z != null && o.zBezug != null && h != null) ...[
        const SizedBox(height: 6),
        Text(
          [
            for (final b in Hoehenbezug.values)
              if (b != o.zBezug) '${mmText(umrechnen(o.z!, o.zBezug!, b, h))} ${b.label}'
          ].join(' · '),
          style: const TextStyle(fontSize: 11, color: BsFarben.textLeise),
        ),
      ],
      const SizedBox(height: 12),
      DropdownButtonFormField<String?>(
        key: ValueKey('lage-${o.id}-${o.lage}'),
        initialValue: _lagen.contains(o.lage) ? o.lage : null,
        decoration: const InputDecoration(labelText: 'Lage'),
        items: [
          const DropdownMenuItem(value: null, child: Text('–')),
          for (final l in _lagen) DropdownMenuItem(value: l, child: Text(l)),
        ],
        onChanged: (v) => aendern({'lage': v}),
      ),
      ..._geschossuebergreifend(o, d, aendern),
      const SizedBox(height: 12),
      DropdownButtonFormField<ObjektStatus>(
        key: ValueKey('status-${o.id}-${o.status.name}'),
        initialValue: o.status,
        decoration: const InputDecoration(labelText: 'Status'),
        items: [for (final s in ObjektStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
        onChanged: (s) {
          if (s != null) aendern({'status': s.name});
        },
      ),
      const SizedBox(height: 12),
      SpeicherFeld(
        key: ValueKey('norm-${o.id}-${o.normkennzeichen}'),
        initialValue: o.normkennzeichen ?? '',
        decoration: const InputDecoration(labelText: 'Normkennzeichen (DIN EN 81346)', hintText: 'z. B. =EG+BAD-XD3'),
        onFieldSubmitted: (v) => aendern({'normkennzeichen': v.trim().isEmpty ? null : v.trim()}),
      ),
      const SizedBox(height: 12),
      if (d.typen[o.typId]?.kuerzel != 'HK')
      DropdownButtonFormField<String?>(
        key: ValueKey('produkt-${o.id}-${o.produktId}'),
        initialValue: o.produktId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Produkt', helperText: 'Preis und Menge laufen in die Kostenliste'),
        items: [
          const DropdownMenuItem(value: null, child: Text('– noch offen –')),
          for (final p in store.produkte())
            DropdownMenuItem(
              value: p.id,
              child: Text(
                '${p.name}${p.bestesAngebot == null ? '' : ' · ${euroText(p.bestesAngebot!.preisCent)}'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) => aendern({'produkt_id': v}),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(onPressed: _loeschen, icon: const Icon(Sym.loeschen), label: const Text('Löschen (Entf)')),
    ]));
  }
}

/// Zeichnet Objekte der Gewerke: Punkte mit Kürzel, Leitungen, Flächen.
class ObjektPainter extends CustomPainter {
  ObjektPainter({
    required this.objekte,
    required this.typen,
    required this.gewerke,
    required this.massstab,
    required this.verschiebung,
    required this.auswahl,
    required this.entwurf,
    required this.entwurfFarbe,
    required this.entwurfFlaeche,
    required this.maus,
    this.waende = const [],
    this.zug = const {},
    this.markiert = const {},
    this.freiePlaetze = const [],
    this.darstellung = const {},
    this.abmasse = const {},
  });

  /// Reale Abmaße (Breite, Tiefe in mm) je Objekt aus dem zugeordneten Produkt.
  final Map<String, (double, double)> abmasse;

  /// Darstellung aus den Einstellungen (Größe, Beschriftung, Deckkraft, Form).
  final Map<String, dynamic> darstellung;
  double get _groesse => (darstellung['groesse'] as num?)?.toDouble() ?? 1.0;
  double get _deckkraft => (darstellung['deckkraft'] as num?)?.toDouble() ?? 1.0;
  double get _flaechenDeckkraft => (darstellung['flaeche'] as num?)?.toDouble() ?? 0.15;
  String get _beschriftung => darstellung['text'] as String? ?? 'kennung';
  bool get _quadrat => darstellung['form'] == 'quadrat';

  final List<Objekt> objekte;
  final Map<String, Objekttyp> typen;
  final Map<String, Gewerk> gewerke;
  final double massstab;
  final Offset verschiebung;
  final String? auswahl;
  final List<Offset> entwurf;
  final Color? entwurfFarbe;
  final bool entwurfFlaeche;
  final Offset? maus;

  /// Wände für die Lage von Verteilerschränken (leer = Schrank waagerecht).
  final List<WandStrecke> waende;

  /// Leitungen, die mit der gewählten über Fortsetzungen zusammenhängen.
  final Set<String> zug;

  /// Hervorgehobene Objekte (z. B. Verbraucher eines Stromkreises).
  final Set<String> markiert;

  /// Freie Plätze in Mehrfachrahmen (Welt).
  final List<Offset> freiePlaetze;

  Offset _s(Offset w) => w * massstab + verschiebung;

  /// Nächste Wand zu einem Punkt (bis halbe Dicke + 40 mm): Strecke, Richtung, Normale.
  (WandStrecke, Offset, Offset)? _naechsteWand(Punkt p) {
    (WandStrecke, Offset, Offset)? beste;
    var bester = double.infinity;
    for (final w in waende) {
      final a = Offset(w.a.x, w.a.y), b = Offset(w.b.x, w.b.y);
      final l = (b - a).distance;
      if (l < 1) continue;
      final d = abstandZuStrecke(Offset(p.x, p.y), a, b);
      if (d <= w.dicke / 2 + 40 && d < bester) {
        bester = d;
        final u = (b - a) / l;
        beste = (w, u, Offset(-u.dy, u.dx));
      }
    }
    return beste;
  }

  void _strichlinie(Canvas c, List<Offset> p, Paint paint, bool gestrichelt) {
    for (var i = 0; i + 1 < p.length; i++) {
      final a = p[i], b = p[i + 1];
      if (!gestrichelt) {
        c.drawLine(a, b, paint);
        continue;
      }
      final l = (b - a).distance;
      if (l < 1) continue;
      final r = (b - a) / l;
      for (var t = 0.0; t < l; t += 12) {
        c.drawLine(a + r * t, a + r * math.min(t + 7, l), paint);
      }
    }
  }

  void _text(Canvas c, String t, Offset p, Color farbe, {double groesse = 10, bool fett = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          fontSize: groesse,
          color: farbe,
          fontWeight: fett ? FontWeight.w700 : FontWeight.w500,
          backgroundColor: Colors.white.withValues(alpha: 0.8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final linien = [for (final o in objekte) if (typen[o.typId]?.geometrie == Geometrieart.linie) o];
    final versatz = buendelVersatz([for (final o in linien) [for (final p in o.punkte) Offset(p.x, p.y)]]);
    // Mehrfachrahmen: Geräte einer Gruppe nebeneinander, eine gemeinsame Beschriftung
    final gruppen = <String, List<Objekt>>{};
    for (final o in objekte) {
      final g = o.eigenschaften['rahmen_gruppe'];
      if (g is String) gruppen.putIfAbsent(g, () => []).add(o);
    }
    for (final l in gruppen.values) {
      l.sort((a, b) => ((a.eigenschaften['rahmen_pos'] as num?) ?? 0).compareTo((b.eigenschaften['rahmen_pos'] as num?) ?? 0));
    }
    for (final o in objekte) {
      final typ = typen[o.typId];
      final g = gewerke[typ?.gewerkId];
      final farbe = Color(g?.farbe ?? 0xFF888888);
      final gewaehlt = o.id == auswahl;
      final pts = [for (final p in o.punkte) _s(Offset(p.x, p.y))];
      if (pts.isEmpty) continue;
      final status = o.status;
      // Verdrahtungskette: Linie vom speisenden Gerät
      final gv = o.eigenschaften['gespeist_von'];
      if (gv is String && massstab > 0.02) {
        final f = objekte.where((x) => x.id == gv).firstOrNull;
        if (f != null && f.punkte.isNotEmpty) {
          canvas.drawLine(_s(Offset(f.punkte.first.x, f.punkte.first.y)), pts.first, Paint()
            ..color = farbe.withValues(alpha: 0.45)
            ..strokeWidth = 1.2);
        }
      }
      if (markiert.contains(o.id)) {
        for (final q in pts) {
          canvas.drawCircle(q, 14, Paint()..color = BsFarben.akzent.withValues(alpha: 0.35));
        }
      }
      switch (typ?.geometrie) {
        case Geometrieart.flaeche:
          final path = Path()..addPolygon(pts, true);
          canvas.drawPath(path, Paint()..color = farbe.withValues(alpha: gewaehlt ? math.min(1, _flaechenDeckkraft * 2) : _flaechenDeckkraft));
          canvas.drawPath(path, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = gewaehlt ? 2.5 : 1.5
            ..color = farbe);
          if (typ?.kuerzel == 'HK' && massstab > 0.02) {
            // Vorlauf rot, Rücklauf blau – Anschlusspunkte am Rohranfang
            final fe = FbhEinstellung.ausJson(o.eigenschaften);
            for (final sp in fe.sperren) {
              final pfad = Path()..addPolygon([for (final q in sp) _s(Offset(q.x, q.y))], true);
              canvas.drawPath(pfad, Paint()..color = const Color(0x55868E96));
              canvas.drawPath(pfad, Paint()
                ..style = PaintingStyle.stroke
                ..color = const Color(0xFF495057));
              final r = pfad.getBounds();
              canvas.drawLine(r.topLeft, r.bottomRight, Paint()..color = const Color(0x88495057));
              canvas.drawLine(r.topRight, r.bottomLeft, Paint()..color = const Color(0x88495057));
            }
            final plan = verlegeplan(o.punkte, fe);
            for (final (zug, f) in [(plan.vl, const Color(0xFFE03131)), (plan.rl, const Color(0xFF1C7ED6))]) {
              if (zug.length < 2) continue;
              canvas.drawPath(
                  Path()..addPolygon([for (final q in zug) _s(Offset(q.x, q.y))], false),
                  Paint()
                    ..color = f.withValues(alpha: 0.7)
                    ..strokeWidth = math.max(1.0, 16 * massstab)
                    ..style = PaintingStyle.stroke);
            }
            for (final (q, f) in [(plan.anschlussVl, const Color(0xFFE03131)), (plan.anschlussRl, const Color(0xFF1C7ED6))]) {
              if (q != null) canvas.drawCircle(_s(Offset(q.x, q.y)), 4.5, Paint()..color = f);
            }
          }
          final c = punktImInneren(o.punkte);
          _text(canvas, o.kennung, _s(Offset(c.x, c.y)), farbe, fett: true);
        case Geometrieart.linie:
          final bild = versetzterZug(pts, linien.indexOf(o), versatz, 4);
          if (zug.contains(o.id) && zug.length > 1) {
            canvas.drawPath(
                Path()..addPolygon(bild, false),
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 9
                  ..strokeJoin = StrokeJoin.round
                  ..color = BsFarben.akzent.withValues(alpha: 0.35));
          }
          final p = Paint()
            ..color = farbe
            ..strokeWidth = math.max(gewaehlt ? 4.0 : 2.2, ((o.eigenschaften['breite_mm'] as num?)?.toDouble() ?? 0) * massstab)
            ..strokeCap = StrokeCap.round;
          _strichlinie(canvas, bild, p, g?.linie == 'dashed');
          for (final (ende, q) in [('uebergang_anfang', bild.first), ('uebergang_ende', bild.last)]) {
            final lage = o.eigenschaften[ende];
            if (lage is! String) continue;
            canvas.drawCircle(q, 6, Paint()..color = Colors.white);
            canvas.drawCircle(q, 6, Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = farbe);
            _text(canvas, uebergangsPfeil(lage), q - const Offset(3.5, 7), farbe, groesse: 9, fett: true);
            if (massstab > 0.04 || gewaehlt) _text(canvas, '${o.kennung} ab hier ', q + const Offset(8, 4), farbe, groesse: 9);
          }
          final m = pts.length >= 2 ? (pts[0] + pts[1]) / 2 : pts.first;
          _text(canvas, '${o.kennung} · ${meterText(o.laenge)}', m + const Offset(4, 2), farbe);
        default:
          var c = pts.first;
          final grp = gruppen[o.eigenschaften['rahmen_gruppe']];
          final idx = grp?.indexOf(o) ?? 0;
          if (grp != null && idx > 0 && grp.first.punkte.isNotEmpty) {
            // im Plan mindestens so weit auseinander, dass sich die Symbole nicht überdecken
            final l = _s(Offset(grp.first.punkte.first.x, grp.first.punkte.first.y));
            final d = c - l;
            final schritt = math.max(d.distance / idx, 14 * _groesse + 3);
            if (d.distance > 0.01) c = l + d / d.distance * schritt * idx.toDouble();
          }
          if (typ?.kuerzel == 'HV') {
            final d = VerteilerDaten.ausJson(o.eigenschaften);
            final umriss = [for (final q in verteilerUmriss(o.punkte.first, d, waende)) _s(Offset(q.x, q.y))];
            final schrank = Path()..addPolygon(umriss, true);
            canvas.drawPath(schrank, Paint()..color = farbe.withValues(alpha: gewaehlt ? 0.35 : 0.2));
            canvas.drawPath(schrank, Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = gewaehlt ? 2 : 1.2
              ..color = farbe);
            if (massstab > 0.05 || gewaehlt) {
              for (final (name, q) in verteilerAnschlussPunkte(o.punkte.first, d, waende)) {
                final s = _s(Offset(q.x, q.y));
                final rot = name.endsWith('VL');
                canvas.drawCircle(s, 2.5, Paint()..color = rot ? const Color(0xFFE03131) : const Color(0xFF1C7ED6));
              }
            }
          }
          // An oder in der Wand: Strich auf der Wandoberfläche; Durchbruch quer durch die Wand
          final ws = _naechsteWand(o.punkte.first);
          if (ws != null && (typ?.kuerzel == 'WD' || o.lage == 'in Wand' || o.lage == 'auf Wand' || o.lage == 'durch Wand')) {
            final (w, u, n) = ws;
            final p0 = Offset(o.punkte.first.x, o.punkte.first.y);
            if (typ?.kuerzel == 'WD') {
              final dm = ((o.eigenschaften['durchmesser_mm'] as num?)?.toDouble() ?? 50) / 2;
              final a0 = Offset(w.a.x, w.a.y);
              final t = (p0 - a0).dx * u.dx + (p0 - a0).dy * u.dy;
              final m = a0 + u * t;
              final h = w.dicke / 2 + 20;
              final ecken = [m + u * dm + n * h, m - u * dm + n * h, m - u * dm - n * h, m + u * dm - n * h];
              final pfad = Path()..addPolygon([for (final e in ecken) _s(e)], true);
              canvas.drawPath(pfad, Paint()..color = Colors.white);
              canvas.drawPath(pfad, Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = farbe);
            } else {
              final halb = math.max(40.0, 5 / massstab);
              canvas.drawLine(_s(p0 - u * halb), _s(p0 + u * halb), Paint()
                ..color = farbe
                ..strokeWidth = 3.5
                ..strokeCap = StrokeCap.butt);
            }
          }
          final rad = (gewaehlt ? 9 : 7) * _groesse;
          // An der Wand: Symbol sitzt im Raum direkt an der Wandoberfläche und zeigt zur Wand
          var mitte = c;
          var richtung = const Offset(0, -1);
          if (ws != null && typ?.kuerzel != 'WD') {
            final (w, _, n) = ws;
            final p0 = Offset(o.punkte.first.x, o.punkte.first.y);
            final a0 = Offset(w.a.x, w.a.y);
            final seite = ((p0 - a0).dx * n.dx + (p0 - a0).dy * n.dy) >= 0 ? 1.0 : -1.0;
            final abstandAchse = ((p0 - a0).dx * n.dx + (p0 - a0).dy * n.dy).abs();
            if ((abstandAchse - w.dicke / 2).abs() < 30) {
              richtung = n * seite;
              mitte = c + Offset(richtung.dx, richtung.dy) * rad;
              canvas.drawLine(c, mitte, Paint()
                ..color = farbe
                ..strokeWidth = 1.5);
            }
          }
          // Reale Grundfläche des Produkts (z. B. WC, Waschtisch, Heizkörper), an der Wand ausgerichtet
          final am = abmasse[o.id];
          if (am != null && am.$1 * massstab > 6) {
            final quer = Offset(-richtung.dy, richtung.dx);
            final m0 = c + richtung * (am.$2 / 2 * massstab);
            final pts4 = [
              m0 + quer * (am.$1 / 2 * massstab) - richtung * (am.$2 / 2 * massstab),
              m0 - quer * (am.$1 / 2 * massstab) - richtung * (am.$2 / 2 * massstab),
              m0 - quer * (am.$1 / 2 * massstab) + richtung * (am.$2 / 2 * massstab),
              m0 + quer * (am.$1 / 2 * massstab) + richtung * (am.$2 / 2 * massstab),
            ];
            final pfad = Path()..addPolygon(pts4, true);
            canvas.drawPath(pfad, Paint()..color = farbe.withValues(alpha: 0.12));
            canvas.drawPath(pfad, Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = farbe);
            mitte = m0;
          }
          geraetSymbol(canvas, mitte, rad, _beschriftung == 'keiner' ? '' : (typ?.kuerzel ?? '?'), farbe,
              richtung: richtung, deckkraft: _deckkraft, quadrat: _quadrat);
          if (gewaehlt) {
            canvas.drawCircle(mitte, rad + 4, Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = BsFarben.akzent);
          }
          if ((massstab > 0.04 || gewaehlt) && (_beschriftung == 'kennung' || _beschriftung == 'kennung_hoehe') && idx == 0) {
            final hoehe = _beschriftung == 'kennung_hoehe' && o.z != null ? '\n${o.z} ${o.zBezug?.kurz ?? ''}' : '';
            final name = grp == null ? o.kennung : '${grp.map((x) => x.kennung).join('/')} (${grp.length}-fach)';
            _text(canvas, '$name$hoehe', mitte + Offset(rad + 3, -6), farbe);
          }
      }
      // Status: verdeckte Objekte gepunktet umrandet, geprüfte mit Häkchen
      if (status == ObjektStatus.geprueft || status == ObjektStatus.verdeckt) {
        final c = pts.first;
        _text(canvas, status == ObjektStatus.geprueft ? '✓' : '▣', c + const Offset(-14, -14), farbe, groesse: 10, fett: true);
      }
    }
    // Entwurf
    final f = entwurfFarbe ?? BsFarben.akzent;
    final e = [for (final p in entwurf) _s(p), if (maus != null && entwurf.isNotEmpty) _s(maus!)];
    if (e.length >= 2) {
      final p = Paint()
        ..color = f.withValues(alpha: 0.7)
        ..strokeWidth = 2;
      _strichlinie(canvas, e, p, false);
      if (entwurfFlaeche && e.length >= 3) {
        canvas.drawPath(Path()..addPolygon(e, true), Paint()..color = f.withValues(alpha: 0.12));
      }
      var l = 0.0;
      for (var i = 0; i + 1 < entwurf.length; i++) {
        l += (entwurf[i + 1] - entwurf[i]).distance;
      }
      if (maus != null) l += (maus! - entwurf.last).distance;
      _text(canvas, meterText(l), e.last + const Offset(10, 8), f, fett: true);
    }
    final m = maus;
    if (m != null) {
      final c = _s(m);
      final p = Paint()
        ..color = BsFarben.akzentDunkel
        ..strokeWidth = 1.2;
      canvas.drawLine(c.translate(-8, 0), c.translate(8, 0), p);
      canvas.drawLine(c.translate(0, -8), c.translate(0, 8), p);
    }
    // freie Plätze in Mehrfachrahmen: gestrichelte Kreise
    if (massstab > 0.03) {
      for (final q in freiePlaetze) {
        final c = _s(q);
        final r = 7 * _groesse;
        for (var w = 0.0; w < 6.28; w += 0.7) {
          canvas.drawArc(Rect.fromCircle(center: c, radius: r), w, 0.35, false, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = BsFarben.textLeise);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ObjektPainter old) => true;
}

/// Wand als Strecke für die Lage von Verteilerschränken.
WandStrecke wandStrecke(Wand w) =>
    (a: Punkt(w.x1.toDouble(), w.y1.toDouble()), b: Punkt(w.x2.toDouble(), w.y2.toDouble()), dicke: w.dicke.toDouble());
