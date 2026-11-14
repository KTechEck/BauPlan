import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/auslegung.dart';
import '../../core/auslegung_projekt.dart';
import '../../core/elektro.dart' show plankopf;
import '../../core/height.dart';
import '../../core/hydraulik_schema.dart';
import '../../core/raumerkennung.dart';
import '../../core/stromlaufplan.dart';
import '../../core/ta_regler.dart';
import '../../core/wasser.dart' show wassermelderYaml;
import '../../core/zip_schreiben.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';
import '../../data/tagebuch_models.dart';
import '../bauteile/gewaehrleistung_dialog.dart' show gewaehrleistungLesen;
import '../verteiler/stromlaufplan_ansicht.dart' show stromlaufplanPdf;
import '../verteiler/auslegung_page.dart' show leitungslisteCsv, leitungslisteHtml;
import 'hausdoku.dart';

String _d(DateTime t) => '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
String _stamp(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
String _t(String s) => s.replaceAll('→', '>').replaceAll('Ø', 'D').replaceAll('≥', '>=').replaceAll('≤', '<=').replaceAll('–', '-').replaceAll('·', '-').replaceAll('×', 'x');

Uint8List? _bild(String pfad) {
  try {
    final f = File(pfad);
    if (!f.existsSync() || f.lengthSync() > 12 * 1024 * 1024) return null;
    final e = p.extension(pfad).toLowerCase();
    if (e != '.jpg' && e != '.jpeg' && e != '.png') return null;
    return f.readAsBytesSync();
  } catch (_) {
    return null;
  }
}

/// Raumbuch als PDF: je Raum Maße, Oberflächen, Öffnungen, Installation, Aufgaben/Mängel, Fotos.
Future<String> raumbuchPdf(ProjectStore store, {String? ziel}) async {
  final doc = pw.Document(title: 'Raumbuch ${store.name}', author: store.benutzer);
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final aufgaben = store.aufgaben();
  const h1 = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
  const klein = pw.TextStyle(fontSize: 8.5);
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final fotos = store.fotos(g.id);
      final oeff = store.oeffnungen(g.id);
      final waende = {for (final w in store.waende(g.id)) w.id: w};
      final objekte = store.objekte(g.id);
      for (final r in store.raeume(g.id)) {
        if (r.umriss == null) continue;
        final flaeche = polygonFlaeche(r.umriss!).abs() / 1e6;
        final umfang = (r.umfang ?? 0) / 1000;
        final h = r.hoehen(g);
        final drin = [for (final o in objekte) if (o.raumId == r.id || (o.punkte.isNotEmpty && punktInPolygon(o.punkte.first, r.umriss!))) o];
        final raumOeff = <Oeffnung>[];
        for (final o in oeff) {
          final w = waende[o.wandId];
          if (w == null || w.laenge < 1) continue;
          final t = (o.abstand + o.breite / 2) / w.laenge;
          final m = Punkt(w.x1 + (w.x2 - w.x1) * t, w.y1 + (w.y2 - w.y1) * t);
          final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge, dd = w.dicke / 2 + 60;
          if (punktInPolygon(Punkt(m.x - uy * dd, m.y + ux * dd), r.umriss!) || punktInPolygon(Punkt(m.x + uy * dd, m.y - ux * dd), r.umriss!)) raumOeff.add(o);
        }
        final rf = [for (final f in fotos) if (f.raumId == r.id) f].take(4).toList();
        final ra = [for (final a in aufgaben) if (a.raumId == r.id) a];
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (c) => [
            pw.Text(_t('${g.kuerzel} ${r.name} (${r.kuerzel})'), style: h1),
            pw.Text(_t('Raumbuch ${store.name} - Stand ${_d(DateTime.now())}'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(cellStyle: klein, headerStyle: const pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold), data: [
              ['Fläche', '${flaeche.toStringAsFixed(2).replaceAll('.', ',')} m²', 'Umfang', '${umfang.toStringAsFixed(2).replaceAll('.', ',')} m'],
              ['lichte Höhe', '${((r.ukDecke ?? h.rohdecke) - h.ffb)} mm', 'FFB / RFB', '${h.ffb} / ${h.rfb} mm'],
              ['Nassraum', r.eigenschaften['nassraum'] == true ? 'ja' : '-', 'Heizlast', r.eigenschaften['heizlast_w'] == null ? '-' : '${r.eigenschaften['heizlast_w']} W'],
            ]),
            if (raumOeff.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Fenster und Türen', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.TableHelper.fromTextArray(
                cellStyle: klein,
                headers: ['Art', 'Breite', 'Höhe', 'Brüstung'],
                data: [for (final o in raumOeff) [_t(o.art.label), '${o.breite}', '${o.hoehe}', '${o.bruestung}']],
              ),
            ],
            if (drin.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Installation (${drin.length})', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.TableHelper.fromTextArray(
                cellStyle: klein,
                headers: ['Kennung', 'Art', 'Höhe', 'Status', 'Hinweis'],
                data: [
                  for (final o in drin)
                    [
                      o.kennung,
                      _t(typen[o.typId]?.name ?? ''),
                      o.z == null ? '-' : '${o.z} ${o.zBezug?.kurz ?? ''}',
                      _t(o.status.label),
                      _t([if (o.eigenschaften['reserve'] == true) 'Reserve', if (o.eigenschaften['typenschild'] is Map) '${(o.eigenschaften['typenschild'] as Map)['typ'] ?? ''}'].join(' ')),
                    ],
                ],
              ),
            ],
            if (ra.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Aufgaben, Mängel, Restarbeiten', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              for (final a in ra) pw.Text(_t('${a.status == AufgabenStatus.erledigt ? '[x]' : '[ ]'} ${aufgabenArten[a.art] ?? 'Aufgabe'}: ${a.titel}'), style: klein),
            ],
            if (rf.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in rf)
                  if (_bild(p.join(store.ordner, f.datei)) case final b?)
                    pw.Column(children: [pw.Image(pw.MemoryImage(b), width: 120, height: 90, fit: pw.BoxFit.cover), pw.Text(_d(f.aufnahme.toLocal()), style: const pw.TextStyle(fontSize: 7))]),
              ]),
            ],
          ],
        ));
      }
    }
  }
  if (doc.document.pdfPageList.pages.isEmpty) doc.addPage(pw.Page(build: (c) => pw.Text('Keine verorteten Räume.')));
  final datei = File(ziel ?? p.join(store.ordner, 'exporte', 'Raumbuch_${_stamp(DateTime.now())}.pdf'));
  await datei.parent.create(recursive: true);
  await datei.writeAsBytes(await doc.save());
  return datei.path;
}

/// Fotobericht: alle Fotos nach Geschoss/Raum und Datum, je Seite 6 mit Notiz.
Future<String> fotoberichtPdf(ProjectStore store, {String? ziel}) async {
  final doc = pw.Document(title: 'Fotobericht ${store.name}', author: store.benutzer);
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final raeume = {for (final r in store.raeume(g.id)) r.id: r.name};
      final fotos = store.fotos(g.id)..sort((a, b) => a.raumId == b.raumId ? a.aufnahme.compareTo(b.aufnahme) : '${raeume[a.raumId]}'.compareTo('${raeume[b.raumId]}'));
      if (fotos.isEmpty) continue;
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (c) => [
          pw.Text(_t('Fotobericht ${store.name} - ${g.kuerzel} ${g.name}'), style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Wrap(spacing: 10, runSpacing: 10, children: [
            for (final f in fotos)
              if (_bild(p.join(store.ordner, f.datei)) case final b?)
                pw.SizedBox(
                  width: 260,
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Image(pw.MemoryImage(b), width: 260, height: 180, fit: pw.BoxFit.cover),
                    pw.Text(_t('${raeume[f.raumId] ?? 'ohne Raum'} - ${_d(f.aufnahme.toLocal())} - ${f.autor}'), style: const pw.TextStyle(fontSize: 8)),
                    if ((f.notiz ?? '').isNotEmpty) pw.Text(_t(f.notiz!), style: const pw.TextStyle(fontSize: 8)),
                  ]),
                ),
          ]),
        ],
      ));
    }
  }
  if (doc.document.pdfPageList.pages.isEmpty) doc.addPage(pw.Page(build: (c) => pw.Text('Noch keine Fotos.')));
  final datei = File(ziel ?? p.join(store.ordner, 'exporte', 'Fotobericht_${_stamp(DateTime.now())}.pdf'));
  await datei.parent.create(recursive: true);
  await datei.writeAsBytes(await doc.save());
  return datei.path;
}

// --------------------------------------------------------------- Etiketten

/// Ein Etikett: zwei Zeilen.
typedef Etikett = ({String art, String zeile1, String zeile2});

/// Etiketten aus dem Plan: Leitungen/Kabel, Netzwerkdosen (mit Port),
/// Sicherungen (Kennzeichen + Stromkreis), Fühler (Regelung).
List<Etikett> etikettenSammeln(ProjectStore store, Set<String> arten) {
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final raeume = {
    for (final geb in store.gebaeude())
      for (final g in store.geschosse(geb.id))
        for (final r in store.raeume(g.id)) r.id: r.name,
  };
  final aus = <Etikett>[];
  if (arten.contains('kabel')) {
    for (final o in store.alleObjekte()) {
      final k = typen[o.typId]?.kuerzel;
      if (typen[o.typId]?.geometrie != Geometrieart.linie || !const {'LT', 'BL', 'NK', 'SL', 'LR'}.contains(k)) continue;
      aus.add((art: 'Kabel', zeile1: o.kennung, zeile2: '${o.eigenschaften['kabel'] ?? typen[o.typId]?.name ?? ''} ${raeume[o.raumId] ?? ''}'.trim()));
    }
  }
  if (arten.contains('dosen')) {
    final ports = <String, String>{};
    for (final s in store.schraenke()) {
      for (final e in (s.eigenschaften['patch'] as Map? ?? const {}).entries) {
        ports['${e.value}'] = '${s.kennzeichen}-${e.key}';
      }
    }
    for (final o in store.alleObjekte()) {
      if (typen[o.typId]?.kuerzel != 'ND' && typen[o.typId]?.kuerzel != 'AP') continue;
      aus.add((art: 'Netzwerkdose', zeile1: ports[o.id] ?? o.kennung, zeile2: '${raeume[o.raumId] ?? ''} ${o.kennung}'.trim()));
    }
  }
  if (arten.contains('sicherungen')) {
    for (final s in store.schraenke()) {
      final geraete = {for (final g in store.schrankGeraete(s.id)) g.id: g};
      for (final k in store.stromkreise(s.id)) {
        final g = geraete[k.schutzId];
        aus.add((art: 'Sicherung', zeile1: '=${s.kennzeichen}${g?.kennzeichen ?? ''}  ${g == null ? '' : '${g.charakteristik ?? ''}${g.nennstrom ?? ''}'}'.trim(), zeile2: '${k.nummer} ${k.bezeichnung}'.trim()));
      }
    }
  }
  if (arten.contains('fuehler')) {
    final ta = TaBelegung.ausJson(store.einstellung<Map>('ta_regelung'));
    for (final k in ta.kanaele.where((k) => k.eingang)) {
      final g = ta.geraete.where((x) => x.id == k.regler).firstOrNull;
      aus.add((art: 'Fühler', zeile1: '${g?.name.isNotEmpty == true ? g!.name : g?.typ ?? ''} ${k.kurz}', zeile2: '${k.name} ${k.typ}'.trim()));
    }
  }
  return aus;
}

/// Etikettenformate: A4-Bogen (Spalten × Zeilen, mm) oder Bandetikett (Höhe × Länge mm).
const etikettenFormate = <String, ({bool bogen, double b, double h, int spalten, int zeilen})>{
  'A4 3×8 (70×37 mm)': (bogen: true, b: 70, h: 37, spalten: 3, zeilen: 8),
  'A4 4×12 (48,5×25,4 mm)': (bogen: true, b: 48.5, h: 25.4, spalten: 4, zeilen: 12),
  'Band 12 mm (z. B. P-touch)': (bogen: false, b: 50, h: 12, spalten: 1, zeilen: 1),
  'Band 24 mm (z. B. P-touch)': (bogen: false, b: 60, h: 24, spalten: 1, zeilen: 1),
  'Kabelfahne 40×20 mm': (bogen: false, b: 40, h: 20, spalten: 1, zeilen: 1),
};

/// Etiketten als PDF (Bogen oder ein Etikett je Seite für Banddrucker) und CSV.
Future<(String, String)> etikettenSpeichern(ProjectStore store, List<Etikett> l, String format) async {
  final f = etikettenFormate[format]!;
  const mm = PdfPageFormat.mm;
  final doc = pw.Document(title: 'Etiketten');
  pw.Widget etikett(Etikett e, double b, double h) => pw.Container(
        width: b * mm,
        height: h * mm,
        padding: pw.EdgeInsets.all(h < 15 ? 0.6 * mm : 1.5 * mm),
        decoration: f.bogen ? pw.BoxDecoration(border: pw.Border.all(width: 0.2, color: PdfColors.grey400)) : null,
        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(_t(e.zeile1), style: pw.TextStyle(fontSize: h < 15 ? 7 : 11, fontWeight: pw.FontWeight.bold), maxLines: 1),
          pw.Text(_t(e.zeile2), style: pw.TextStyle(fontSize: h < 15 ? 5.5 : 8), maxLines: h < 15 ? 1 : 2),
        ]),
      );
  if (f.bogen) {
    final jeSeite = f.spalten * f.zeilen;
    for (var i = 0; i < l.length; i += jeSeite) {
      final teil = l.skip(i).take(jeSeite).toList();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.symmetric(horizontal: (210 - f.spalten * f.b) / 2 * mm, vertical: (297 - f.zeilen * f.h) / 2 * mm),
        build: (c) => pw.Wrap(children: [for (final e in teil) etikett(e, f.b, f.h)]),
      ));
    }
  } else {
    for (final e in l) {
      doc.addPage(pw.Page(pageFormat: PdfPageFormat(f.b * mm, f.h * mm, marginAll: 0), build: (c) => etikett(e, f.b, f.h)));
    }
  }
  if (l.isEmpty) doc.addPage(pw.Page(build: (c) => pw.Text('Keine Etiketten.')));
  final ordner = Directory(p.join(store.ordner, 'exporte', 'etiketten'));
  await ordner.create(recursive: true);
  final name = format.split(' ').take(2).join('_').replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  final pdf = File(p.join(ordner.path, 'Etiketten_$name.pdf'));
  await pdf.writeAsBytes(await doc.save());
  // CSV für Etiketten-Software (z. B. P-touch Editor: Datenbank verknüpfen)
  final csv = StringBuffer('Art;Zeile1;Zeile2\n');
  for (final e in l) {
    csv.writeln('${e.art};"${e.zeile1.replaceAll('"', '""')}";"${e.zeile2.replaceAll('"', '""')}"');
  }
  final c = File(p.join(ordner.path, 'Etiketten.csv'));
  await c.writeAsString('﻿$csv');
  return (pdf.path, c.path);
}

// ----------------------------------------------------------------- Hausakte

/// Hausakte als Ordner mit Kategorien (und ZIP): Pläne/Dokumentation,
/// Elektro, Heizung/Sanitär, Fotos nach Geschoss/Raum, Protokolle, Raumbuch,
/// Einkauf/Gewährleistung, Home Assistant – mit index.html zum Blättern (offline).
Future<String> hausakteErstellen(ProjectStore store, {bool zip = true, bool hausdoku = true}) async {
  final jetzt = DateTime.now();
  final wurzel = Directory(p.join(store.ordner, 'exporte', 'Hausakte_${_stamp(jetzt)}'));
  if (wurzel.existsSync()) wurzel.deleteSync(recursive: true);
  final eintraege = <String, List<String>>{};
  Future<void> ablegen(String kat, String name, List<int> daten) async {
    final f = File(p.join(wurzel.path, kat, name));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(daten);
    (eintraege[kat] ??= []).add(p.join(kat, name).replaceAll(r'\', '/'));
  }

  Future<void> kopieren(String kat, String quelle, String name) async {
    final q = File(quelle);
    if (!q.existsSync()) return;
    await ablegen(kat, name, q.readAsBytesSync());
  }

  // 01 Pläne und Dokumentation
  if (hausdoku) {
    try {
      final hd = await HausDokumentation(store: store).erstellen();
      await kopieren('01_Plaene_Dokumentation', hd, 'Hausdokumentation.pdf');
    } catch (_) {}
  }
  await kopieren('01_Plaene_Dokumentation', await raumbuchPdf(store, ziel: p.join(Directory.systemTemp.path, 'bauspur_raumbuch.pdf')), 'Raumbuch.pdf');
  // 02 Elektro
  for (final s in store.schraenke()) {
    try {
      final plan = stromlaufplanErzeugen(schrank: s, geraete: store.schrankGeraete(s.id), kreise: store.stromkreise(s.id), projekt: store.name);
      await ablegen('02_Elektro', 'Stromlaufplan_${s.kennzeichen}.pdf', await stromlaufplanPdf(plan, titel: 'Stromlaufplan ${s.name}'));
    } catch (_) {}
    final patch = s.eigenschaften['patch'] as Map? ?? const {};
    if (patch.isNotEmpty) {
      final b = StringBuffer('Port;Objekt\n');
      for (final e in patch.entries) {
        b.writeln('${e.key};${store.alleObjekte().where((o) => o.id == e.value).firstOrNull?.kennung ?? ''}');
      }
      await ablegen('02_Elektro', 'Patchfeld_${s.kennzeichen}.csv', _utf8('﻿$b'));
    }
  }
  final et = etikettenSammeln(store, {'kabel', 'dosen', 'sicherungen', 'fuehler'});
  if (et.isNotEmpty) {
    final (pdf, csv) = await etikettenSpeichern(store, et, 'A4 3×8 (70×37 mm)');
    await kopieren('02_Elektro', pdf, 'Etiketten_A4.pdf');
    await kopieren('02_Elektro', csv, 'Etiketten.csv');
  }
  // 03 Heizung, Sanitär, Lüftung
  final schema = HydraulikSchema.ausJson(store.einstellung<Map>('hydraulikschema'));
  if (schema.symbole.isNotEmpty) await ablegen('03_Heizung_Sanitaer', 'Hydraulikschema.svg', _utf8(schemaSvg(schema, titel: store.name)));
  final ta = TaBelegung.ausJson(store.einstellung<Map>('ta_regelung'));
  if (ta.geraete.isNotEmpty) await ablegen('03_Heizung_Sanitaer', 'TAPPS2-Vorlage.txt', _utf8(tapps2Vorlage(ta, projekt: store.name)));
  // 04 Fotos nach Geschoss/Raum
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final raeume = {for (final r in store.raeume(g.id)) r.id: r.name};
      for (final f in store.fotos(g.id)) {
        final raum = (raeume[f.raumId] ?? 'ohne Raum').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        await kopieren('04_Fotos/${g.kuerzel}/$raum', p.join(store.ordner, f.datei), p.basename(f.datei));
      }
    }
  }
  // 05 Protokolle
  final prot = store.pruefprotokolle();
  if (prot.isNotEmpty) {
    final b = StringBuffer('Datum;Art;Ergebnis;Prüfer;Messwerte;Notiz\n');
    for (final x in prot) {
      b.writeln('${_d(x.datum)};${x.art};${x.ergebnis};${x.pruefer};"${x.messwerte.entries.map((e) => '${e.key}: ${e.value}').join(', ')}";"${x.notiz}"');
    }
    await ablegen('05_Protokolle', 'Pruefprotokolle.csv', _utf8('﻿$b'));
  }
  // 06 Einkauf, Leitungen, Gewährleistung
  final v = auslegungVorgaben(store);
  final summen = leitungsliste(leitungsStuecke(store));
  if (summen.isNotEmpty) {
    await ablegen('06_Einkauf_Gewaehrleistung', 'Kabel- und Rohrliste.csv', _utf8('﻿${leitungslisteCsv(summen, v.zuschlag)}'));
    await ablegen('06_Einkauf_Gewaehrleistung', 'Kabel- und Rohrliste.html', _utf8(leitungslisteHtml(store.name, summen, v.zuschlag, jetzt)));
  }
  final gw = gewaehrleistungLesen(store);
  if (gw.isNotEmpty) {
    final b = StringBuffer('Produkt;Hersteller;Händler;Kaufdatum;Jahre;bis\n');
    for (final g in gw) {
      b.writeln('${g.produkt};${g.hersteller};${g.haendler};${_d(g.kauf)};${g.jahre};${_d(DateTime(g.kauf.year + g.jahre, g.kauf.month, g.kauf.day))}');
    }
    await ablegen('06_Einkauf_Gewaehrleistung', 'Gewaehrleistung.csv', _utf8('﻿$b'));
  }
  final belege = Directory(p.join(store.ordner, 'belege'));
  if (belege.existsSync()) {
    for (final f in belege.listSync().whereType<File>()) {
      await kopieren('06_Einkauf_Gewaehrleistung/Belege', f.path, p.basename(f.path));
    }
  }
  // 07 Home Assistant
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final wm = [for (final o in store.alleObjekte()) if (typen[o.typId]?.kuerzel == 'WM') '${o.eigenschaften['ha_entity'] ?? 'binary_sensor.wassermelder_${o.kennung.toLowerCase()}'}'];
  if (wm.isNotEmpty) await ablegen('07_Home_Assistant', 'wassermelder.yaml', _utf8(wassermelderYaml(store.name, wm, 'valve.hauptwasser')));
  final ha = Directory(p.join(store.ordner, 'exporte', 'home_assistant'));
  if (ha.existsSync()) {
    for (final f in ha.listSync().whereType<File>()) {
      await kopieren('07_Home_Assistant', f.path, p.basename(f.path));
    }
  }
  // index.html
  final kopf = plankopf(store);
  final html = StringBuffer()
    ..writeln('<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>Hausakte ${_h(store.name)}</title><style>body{font-family:system-ui,sans-serif;max-width:900px;margin:24px auto;padding:0 16px;color:#222}'
        'h1{margin-bottom:0}h2{border-bottom:2px solid #F97316;padding-bottom:4px;margin-top:28px}a{color:#9A3412}li{margin:3px 0}.l{color:#666;font-size:13px}'
        '.fotos{display:flex;flex-wrap:wrap;gap:6px}.fotos img{width:150px;height:110px;object-fit:cover;border-radius:4px}</style></head><body>')
    ..writeln('<h1>Hausakte ${_h(store.name)}</h1><div class="l">Stand ${_d(jetzt)}${(kopf['adresse'] ?? '').isEmpty ? '' : ' · ${_h(kopf['adresse']!)}'} · erstellt mit BauSpur</div>');
  for (final kat in eintraege.keys.toList()..sort()) {
    final titel = kat.replaceAll('_', ' ').replaceFirst(RegExp(r'^\d+ '), '');
    if (kat.startsWith('04_Fotos')) continue;
    html.writeln('<h2>${_h(titel)}</h2><ul>');
    for (final f in eintraege[kat]!) {
      html.writeln('<li><a href="${Uri.encodeFull(f)}">${_h(p.basename(f))}</a></li>');
    }
    html.writeln('</ul>');
  }
  final fotoKats = eintraege.keys.where((k) => k.startsWith('04_Fotos')).toList()..sort();
  if (fotoKats.isNotEmpty) {
    html.writeln('<h2>Fotos</h2>');
    for (final k in fotoKats) {
      html.writeln('<h3>${_h(k.split('/').skip(1).join(' · '))}</h3><div class="fotos">');
      for (final f in eintraege[k]!) {
        html.writeln('<a href="${Uri.encodeFull(f)}"><img src="${Uri.encodeFull(f)}" loading="lazy" alt=""></a>');
      }
      html.writeln('</div>');
    }
  }
  html.writeln('</body></html>');
  await File(p.join(wurzel.path, 'index.html')).writeAsString(html.toString());
  if (zip) {
    final daten = ordnerPacken(wurzel.path);
    await File('${wurzel.path}.zip').writeAsBytes(daten);
  }
  return wurzel.path;
}

List<int> _utf8(String s) => utf8.encode(s);
String _h(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
