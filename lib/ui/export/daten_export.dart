import 'dart:io';

import 'package:flutter/painting.dart' show Size;
import 'package:path/path.dart' as p;

import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';
import '../../data/tagebuch_models.dart';
import 'export_page.dart' show PlanExport;

String _stamp(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
String _f(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
String _z(num v, [int n = 2]) => v.toStringAsFixed(n).replaceAll('.', ',');
String _sicher(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

/// Weitere Datenausgaben: CSV-Listen, DXF, SVG, PNG, Fotos sortiert, Home Assistant.
/// Liefert den Zielordner.
Future<String> datenAusgeben(ProjectStore store, String art, {PlanExport? plaene}) async {
  final ziel = Directory(p.join(store.ordner, 'exporte', switch (art) {
    'csv' => 'Listen_${_stamp(DateTime.now())}',
    'dxf' => 'DXF_${_stamp(DateTime.now())}',
    'svg' => 'SVG_${_stamp(DateTime.now())}',
    'png' => 'Plaene_PNG_${_stamp(DateTime.now())}',
    'fotos' => 'Fotos_${_stamp(DateTime.now())}',
    _ => 'home_assistant',
  }));
  await ziel.create(recursive: true);
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final gewerke = {for (final g in store.gewerke()) g.id: g};
  final geschosse = [for (final geb in store.gebaeude()) ...store.geschosse(geb.id)];
  final raumName = {
    for (final g in geschosse)
      for (final r in store.raeume(g.id)) r.id: r.name,
  };
  Future<void> schreiben(String name, String text) => File(p.join(ziel.path, name)).writeAsString('\uFEFF$text');
  switch (art) {
    case 'csv':
      final r = StringBuffer('Geschoss;Raum;Kürzel;Art;Fläche m²;Umfang m;FFB mm;lichte Höhe mm\n');
      final o = StringBuffer('Kennung;Typ;Gewerk;Geschoss;Raum;x mm;y mm;Höhe;Bezug;Status;Stromkreis;Länge m;Reserve;Hersteller;Typ (Schild);Seriennummer\n');
      final oe = StringBuffer('Geschoss;Art;Breite;Höhe;Brüstung;Türart\n');
      final kreise = <String, String>{};
      final k = StringBuffer('Verteiler;Nr.;Bezeichnung;Leitung;Querschnitt;Last W\n');
      for (final s in store.schraenke()) {
        for (final x in store.stromkreise(s.id)) {
          kreise[x.id] = '${s.kennzeichen}.${x.nummer}';
          k.writeln([_f(s.kennzeichen), _f(x.nummer), _f(x.bezeichnung), _f(x.leitung), _f(x.querschnittText), x.leistung].join(';'));
        }
      }
      for (final g in geschosse) {
        for (final x in store.raeume(g.id)) {
          final h = x.hoehen(g);
          r.writeln([_f(g.kuerzel), _f(x.name), _f(x.kuerzel), _f(x.art.name), _z((x.flaeche ?? 0) / 1e6), _z((x.umfang ?? 0) / 1000), h.ffb, (x.ukDecke ?? h.rohdecke) - h.ffb].join(';'));
        }
        for (final x in store.objekte(g.id)) {
          final t = typen[x.typId];
          final ts = x.eigenschaften['typenschild'] as Map? ?? const {};
          o.writeln([
            _f(x.kennung),
            _f(t?.name),
            _f(gewerke[t?.gewerkId]?.name),
            _f(g.kuerzel),
            _f(raumName[x.raumId]),
            x.punkte.isEmpty ? '' : x.punkte.first.x.round(),
            x.punkte.isEmpty ? '' : x.punkte.first.y.round(),
            x.z ?? '',
            _f(x.zBezug?.name),
            _f(x.status.label),
            _f(kreise[x.eigenschaften['stromkreis']]),
            x.punkte.length >= 2 ? _z(x.laenge / 1000) : '',
            x.eigenschaften['reserve'] == true ? 'ja' : '',
            _f(ts['hersteller']),
            _f(ts['typ']),
            _f(ts['seriennummer']),
          ].join(';'));
        }
        for (final x in store.oeffnungen(g.id)) {
          oe.writeln([_f(g.kuerzel), _f(x.art.label), x.breite, x.hoehe, x.bruestung, _f(x.eigenschaften['tuerart'])].join(';'));
        }
      }
      final a = StringBuffer('Art;Titel;Status;Raum;Fällig;Erledigt;Beschreibung\n');
      for (final x in store.aufgaben()) {
        a.writeln([_f(aufgabenArten[x.art]), _f(x.titel), _f(x.status.label), _f(raumName[x.raumId]), _f(x.faellig?.toIso8601String().substring(0, 10)), _f(x.erledigtAm?.toIso8601String().substring(0, 10)), _f(x.beschreibung)].join(';'));
      }
      await schreiben('Raeume.csv', r.toString());
      await schreiben('Objekte.csv', o.toString());
      await schreiben('Stromkreise.csv', k.toString());
      await schreiben('Oeffnungen.csv', oe.toString());
      await schreiben('Aufgaben.csv', a.toString());
    case 'dxf':
      for (final g in geschosse) {
        await File(p.join(ziel.path, '${_sicher(g.kuerzel)}_${_sicher(g.name)}.dxf')).writeAsString(grundrissDxf(store, g, typen));
      }
    case 'svg':
      for (final g in geschosse) {
        await File(p.join(ziel.path, '${_sicher(g.kuerzel)}_${_sicher(g.name)}.svg')).writeAsString(grundrissSvg(store, g));
      }
    case 'png':
      if (plaene != null) {
        for (final g in geschosse) {
          for (final (name, obj) in [('Grundriss', false), ('Installation', true)]) {
            final (png, _) = await plaene.planBild(g.id, obj, const Size(400, 280));
            if (png != null) await File(p.join(ziel.path, '${_sicher(g.kuerzel)}_$name.png')).writeAsBytes(png);
          }
        }
      }
    case 'fotos':
      final objekte = {for (final o in store.alleObjekte()) o.id: o};
      for (final g in geschosse) {
        final rn = {for (final r in store.raeume(g.id)) r.id: r.name};
        for (final f in store.fotos(g.id)) {
          final q = File(p.join(store.ordner, f.datei));
          if (!q.existsSync()) continue;
          final raumOrdner = Directory(p.join(ziel.path, 'nach Raum', _sicher(g.kuerzel), _sicher(rn[f.raumId] ?? 'ohne Raum')));
          await raumOrdner.create(recursive: true);
          q.copySync(p.join(raumOrdner.path, p.basename(f.datei)));
          final gw = {for (final id in f.objektIds) gewerke[typen[objekte[id]?.typId]?.gewerkId]?.name}.whereType<String>();
          for (final w in gw.isEmpty ? ['ohne Gewerk'] : gw) {
            final o = Directory(p.join(ziel.path, 'nach Gewerk', _sicher(w)));
            await o.create(recursive: true);
            q.copySync(p.join(o.path, p.basename(f.datei)));
          }
        }
      }
    default:
      final b = StringBuffer('# BauSpur: Bereiche (Räume) mit ihren Entitäten – als Vorlage für Home Assistant\n# Bereiche in HA anlegen und Entitäten zuweisen; customize.yaml setzt Anzeigenamen.\n');
      final c = StringBuffer('# BauSpur: Anzeigenamen (in configuration.yaml: homeassistant: customize: !include customize.yaml)\n');
      for (final g in geschosse) {
        for (final r in store.raeume(g.id)) {
          final ent = <String>[];
          for (final o in store.objekte(g.id)) {
            if (o.raumId != r.id) continue;
            final e = <String>[
              if (o.eigenschaften['ha_entity'] is String) o.eigenschaften['ha_entity'] as String,
              for (final x in (o.eigenschaften['ha_entities'] as List? ?? const [])) '$x',
            ];
            for (final x in e) {
              ent.add(x);
              c.writeln('$x:\n  friendly_name: "${r.name} ${typen[o.typId]?.name ?? ''} ${o.kennung}"');
            }
          }
          if (ent.isEmpty) continue;
          b.writeln('- bereich: "${g.kuerzel} ${r.name}"\n  entitaeten:');
          for (final x in ent) {
            b.writeln('    - $x');
          }
        }
      }
      await File(p.join(ziel.path, 'bereiche.yaml')).writeAsString(b.toString());
      await File(p.join(ziel.path, 'customize.yaml')).writeAsString(c.toString());
  }
  return ziel.path;
}

/// Wandumriss als vier Ecken (Achse ± halbe Dicke).
List<Punkt> _wandEcken(Wand w) {
  final l = w.laenge;
  if (l < 1) return const [];
  final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l, h = w.dicke / 2;
  return [
    Punkt(w.x1 - uy * h, w.y1 + ux * h),
    Punkt(w.x2 - uy * h, w.y2 + ux * h),
    Punkt(w.x2 + uy * h, w.y2 - ux * h),
    Punkt(w.x1 + uy * h, w.y1 - ux * h),
  ];
}

/// Grundriss eines Geschosses als DXF (R12, ASCII, mm; y nach oben):
/// Ebenen Wände je Zustand, Öffnungen, Räume, Texte, Objekte.
String grundrissDxf(ProjectStore store, Geschoss g, Map<String, Objekttyp> typen) {
  final b = StringBuffer();
  void gc(int code, Object v) => b
    ..writeln(code)
    ..writeln(v);
  String y(double v) => (-v).toStringAsFixed(1);
  void linie(String layer, Punkt a, Punkt c) {
    gc(0, 'LINE');
    gc(8, layer);
    gc(10, a.x.toStringAsFixed(1));
    gc(20, y(a.y));
    gc(11, c.x.toStringAsFixed(1));
    gc(21, y(c.y));
  }

  void text(String layer, Punkt a, String t, double hoehe) {
    gc(0, 'TEXT');
    gc(8, layer);
    gc(10, a.x.toStringAsFixed(1));
    gc(20, y(a.y));
    gc(40, hoehe);
    gc(1, t.replaceAll(RegExp(r'[^\x20-\x7E\xC0-\xFF]'), '?'));
  }

  const layers = ['WAENDE_BESTAND', 'WAENDE_NEU', 'WAENDE_ABBRUCH', 'OEFFNUNGEN', 'RAEUME', 'TEXT', 'OBJEKTE'];
  gc(0, 'SECTION');
  gc(2, 'HEADER');
  gc(9, r'$INSUNITS');
  gc(70, 4);
  gc(0, 'ENDSEC');
  gc(0, 'SECTION');
  gc(2, 'TABLES');
  gc(0, 'TABLE');
  gc(2, 'LAYER');
  gc(70, layers.length);
  for (final (i, l) in layers.indexed) {
    gc(0, 'LAYER');
    gc(2, l);
    gc(70, 0);
    gc(62, const [7, 1, 2, 5, 3, 7, 4][i]);
    gc(6, 'CONTINUOUS');
  }
  gc(0, 'ENDTAB');
  gc(0, 'ENDSEC');
  gc(0, 'SECTION');
  gc(2, 'ENTITIES');
  for (final w in store.waende(g.id)) {
    final e = _wandEcken(w);
    if (e.isEmpty) continue;
    final layer = switch (w.zustand) { WandZustand.neu => 'WAENDE_NEU', WandZustand.abbruch => 'WAENDE_ABBRUCH', _ => 'WAENDE_BESTAND' };
    for (var i = 0; i < 4; i++) {
      linie(layer, e[i], e[(i + 1) % 4]);
    }
  }
  final waende = {for (final w in store.waende(g.id)) w.id: w};
  for (final o in store.oeffnungen(g.id)) {
    final w = waende[o.wandId];
    if (w == null || w.laenge < 1) continue;
    final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge;
    final a = Punkt(w.x1 + ux * o.abstand, w.y1 + uy * o.abstand), c = Punkt(w.x1 + ux * (o.abstand + o.breite), w.y1 + uy * (o.abstand + o.breite));
    linie('OEFFNUNGEN', a, c);
    text('OEFFNUNGEN', Punkt((a.x + c.x) / 2, (a.y + c.y) / 2), '${o.art.label} ${o.breite}x${o.hoehe}', 80);
  }
  for (final r in store.raeume(g.id)) {
    final u = r.umriss;
    if (u == null || u.length < 3) continue;
    for (var i = 0; i < u.length; i++) {
      linie('RAEUME', u[i], u[(i + 1) % u.length]);
    }
    final m = punktImInneren(u);
    text('TEXT', m, r.name, 150);
    text('TEXT', Punkt(m.x, m.y + 220), '${_z(polygonFlaeche(u).abs() / 1e6)} m2', 100);
  }
  for (final o in store.objekte(g.id)) {
    if (o.punkte.isEmpty) continue;
    if (o.punkte.length == 1) {
      gc(0, 'POINT');
      gc(8, 'OBJEKTE');
      gc(10, o.punkte.first.x.toStringAsFixed(1));
      gc(20, y(o.punkte.first.y));
      text('OBJEKTE', Punkt(o.punkte.first.x + 60, o.punkte.first.y), '${o.kennung} ${typen[o.typId]?.kuerzel ?? ''}', 60);
    } else {
      for (var i = 0; i + 1 < o.punkte.length; i++) {
        linie('OBJEKTE', o.punkte[i], o.punkte[i + 1]);
      }
    }
  }
  gc(0, 'ENDSEC');
  gc(0, 'EOF');
  return b.toString();
}

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Grundriss eines Geschosses als SVG (Wände, Öffnungen, Räume mit Namen und Fläche).
String grundrissSvg(ProjectStore store, Geschoss g) {
  final waende = store.waende(g.id);
  final pts = [for (final w in waende) ..._wandEcken(w)];
  if (pts.isEmpty) return '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"></svg>';
  var x0 = pts.first.x, y0 = pts.first.y, x1 = x0, y1 = y0;
  for (final q in pts) {
    if (q.x < x0) x0 = q.x;
    if (q.y < y0) y0 = q.y;
    if (q.x > x1) x1 = q.x;
    if (q.y > y1) y1 = q.y;
  }
  const rand = 500.0;
  final b = StringBuffer('<svg xmlns="http://www.w3.org/2000/svg" viewBox="${(x0 - rand).round()} ${(y0 - rand).round()} ${(x1 - x0 + 2 * rand).round()} ${(y1 - y0 + 2 * rand).round()}" font-family="Arial">')
    ..write('<rect x="${(x0 - rand).round()}" y="${(y0 - rand).round()}" width="100%" height="100%" fill="white"/>');
  for (final r in store.raeume(g.id)) {
    final u = r.umriss;
    if (u == null || u.length < 3) continue;
    b.write('<polygon points="${u.map((q) => '${q.x.round()},${q.y.round()}').join(' ')}" fill="#FFF7ED" stroke="none"/>');
  }
  for (final w in waende) {
    final e = _wandEcken(w);
    if (e.isEmpty) continue;
    final farbe = switch (w.zustand) { WandZustand.neu => '#C92A2A', WandZustand.abbruch => '#E6A700', _ => '#2B2F33' };
    b.write('<polygon points="${e.map((q) => '${q.x.round()},${q.y.round()}').join(' ')}" fill="$farbe" fill-opacity="${w.teilhoch ? 0.45 : 1}"/>');
  }
  final wn = {for (final w in waende) w.id: w};
  for (final o in store.oeffnungen(g.id)) {
    final w = wn[o.wandId];
    if (w == null || w.laenge < 1) continue;
    final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge, h = w.dicke / 2 + 2;
    final t0 = o.abstand.toDouble(), t1 = (o.abstand + o.breite).toDouble();
    final ecken = [
      Punkt(w.x1 + ux * t0 - uy * h, w.y1 + uy * t0 + ux * h),
      Punkt(w.x1 + ux * t1 - uy * h, w.y1 + uy * t1 + ux * h),
      Punkt(w.x1 + ux * t1 + uy * h, w.y1 + uy * t1 - ux * h),
      Punkt(w.x1 + ux * t0 + uy * h, w.y1 + uy * t0 - ux * h),
    ];
    b.write('<polygon points="${ecken.map((q) => '${q.x.round()},${q.y.round()}').join(' ')}" fill="white" stroke="#2B2F33" stroke-width="15"/>');
  }
  for (final r in store.raeume(g.id)) {
    final u = r.umriss;
    if (u == null || u.length < 3) continue;
    final m = punktImInneren(u);
    b.write('<text x="${m.x.round()}" y="${m.y.round()}" font-size="220" text-anchor="middle">${_x(r.name)}</text>');
    b.write('<text x="${m.x.round()}" y="${(m.y + 260).round()}" font-size="160" text-anchor="middle" fill="#555">${_z(polygonFlaeche(u).abs() / 1e6)} m²</text>');
  }
  b.write('</svg>');
  return b.toString();
}
