import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/knx.dart';
import '../../core/schrank.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';
import '../../data/schrank_models.dart';
import 'export_page.dart';

/// Hausdokumentation komplett: Deckblatt, Inhaltsverzeichnis, Grundrisse und
/// Installationspläne je Geschoss, Räume, Verteiler mit Belegung und
/// Stromkreisliste, KNX-Gruppenadressen, Prüfprotokolle, Bautagebuch, Fotos je
/// Raum und Kostenübersicht – als ein PDF.
class HausDokumentation {
  HausDokumentation({required this.store, this.papier = Papier.a3, this.fotosJeRaum = 6});
  final ProjectStore store;
  final Papier papier;
  final int fotosJeRaum;

  static String _t(String s) => s.replaceAll('−', '-').replaceAll('²', '2').replaceAll('·', '-').replaceAll('→', '->').replaceAll('Ω', 'Ohm').replaceAll('Δ', 'd');

  static const _h1 = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
  static const _klein = pw.TextStyle(fontSize: 8);
  static const _kopfStil = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

  final Map<String, int> _gefunden = {};
  int _seite(pw.Document d) => d.document.pdfPageList.pages.length + 1;
  Map<String, int> _seiten = {};
  final Map<String, (Uint8List?, int)> _planCache = {};
  final Map<String, Uint8List?> _fotoCache = {};

  pw.Widget _titel(pw.Context? c, String text, {int ebene = 0}) {
    return pw.Header(
        level: ebene,
        text: _t(text),
        textStyle: ebene == 0 ? _h1 : const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        decoration: const pw.BoxDecoration(),
        padding: const pw.EdgeInsets.only(bottom: 4),
        margin: const pw.EdgeInsets.only(bottom: 6),
      );
  }

  pw.Widget _tabelle(List<String> kopf, List<List<String>> zeilen) => pw.TableHelper.fromTextArray(
        headerStyle: _kopfStil,
        cellStyle: _klein,
        headers: [for (final k in kopf) _t(k)],
        data: [
          for (final z in zeilen) [for (final c in z) _t(c)],
        ],
      );

  /// Foto verkleinert als PNG (große Originale würden das PDF aufblähen).
  Future<Uint8List?> _vorschau(String datei) async {
    try {
      final f = File(p.join(store.ordner, datei));
      if (!f.existsSync()) return null;
      final codec = await ui.instantiateImageCodec(await f.readAsBytes(), targetWidth: 640);
      final bild = (await codec.getNextFrame()).image;
      final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
      return daten?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Inhaltsverzeichnis aus dem ersten Durchlauf (Abschnitt → Seite).
  pw.Widget _inhalt() {
    final eintraege = _seiten.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    if (eintraege.isEmpty) return pw.Text('…');
    return pw.Column(children: [
      for (final e in eintraege)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [pw.Expanded(child: pw.Text(_t(e.key), style: const pw.TextStyle(fontSize: 10))), pw.Text('${e.value}', style: const pw.TextStyle(fontSize: 10))]),
        ),
    ]);
  }

  /// Zwei Durchläufe: der erste ermittelt die Seitenzahlen fürs Inhaltsverzeichnis.
  Future<String> erstellen() async {
    await (await _bauen()).save();
    _seiten = Map.of(_gefunden);
    final doc = await _bauen();
    final heute = DateTime.now();
    final ordner = Directory(p.join(store.ordner, 'exporte'))..createSync(recursive: true);
    final stempel = heute.toIso8601String().substring(0, 10);
    final datei = File(p.join(ordner.path, 'Hausdokumentation_${store.name.replaceAll(RegExp(r'[<>:"/\|?*]'), '_')}_$stempel.pdf'));
    await datei.writeAsBytes(await doc.save());
    return datei.path;
  }

  Future<pw.Document> _bauen() async {
    _gefunden.clear();
    final doc = pw.Document(title: 'Hausdokumentation ${store.name}', author: store.benutzer);
    final format = papier == Papier.a3 ? PdfPageFormat.a3.landscape : PdfPageFormat.a4.landscape;
    const rand = pw.EdgeInsets.all(10 * PdfPageFormat.mm);
    final heute = DateTime.now();
    final geschosse = [for (final geb in store.gebaeude()) ...store.geschosse(geb.id)];

    // Deckblatt und Inhaltsverzeichnis
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: rand,
      build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.center, children: [
        pw.Text('Hausdokumentation', style: const pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text(_t(store.name), style: const pw.TextStyle(fontSize: 22)),
        pw.SizedBox(height: 24),
        pw.Text(_t('Stand ${heute.day}.${heute.month}.${heute.year} - erstellt von ${store.benutzer} mit BauSpur'), style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 6),
        pw.Text(_t('Geschosse: ${geschosse.map((g) => '${g.kuerzel} ${g.name}').join(', ')}'), style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 30),
        pw.Text(
            _t('Diese Dokumentation zeigt die geplanten und ausgeführten Installationen mit Lage, Höhen und Fotos. '
                'Prüfungen der Elektro-, Gas- und Kältetechnik sind Aufgabe der jeweiligen Fachkraft.'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ]),
    ));
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: rand,
      build: (c) => [pw.Text('Inhalt', style: _h1), pw.SizedBox(height: 10), _inhalt()],
    ));

    // Pläne je Geschoss (gleiche Zeichnung wie am Bildschirm)
    final plaene = PlanExport(
      store: store,
      geschossIds: [for (final g in geschosse) g.id],
      gewerkIds: {for (final g in store.gewerke()) g.id},
      grundriss: true,
      installation: true,
      kosten: false,
      papier: papier,
      massstab: 0,
    );
    final breiteMm = format.width / PdfPageFormat.mm, hoeheMm = format.height / PdfPageFormat.mm;
    final zeichnung = ui.Size(breiteMm - 20, hoeheMm - 20 - 30);
    for (final g in geschosse) {
      for (final (art, objekte) in [('Grundriss', false), ('Installationsplan', true)]) {
        final (png, n) = _planCache['${g.id}|$objekte'] ??= await plaene.planBild(g.id, objekte, zeichnung);
        if (png == null) continue;
        if (art == 'Grundriss') _gefunden['Pläne ${g.kuerzel} - ${g.name}'] = _seite(doc);
        doc.addPage(pw.Page(
          pageFormat: format,
          margin: rand,
          build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _titel(c, '$art ${g.kuerzel} - ${g.name} (1 : $n)', ebene: art == 'Grundriss' ? 0 : 1),
            pw.Expanded(child: pw.Center(child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain))),
          ]),
        ));
      }
    }

    // Räume
    final raumZeilen = <List<String>>[];
    final raumNamen = <String, String>{};
    for (final g in geschosse) {
      final objekte = store.objekte(g.id);
      for (final r in store.raeume(g.id)) {
        raumNamen[r.id] = '${g.kuerzel} ${r.name}';
        final h = r.hoehen(g);
        raumZeilen.add([
          g.kuerzel,
          r.name,
          r.art.label,
          r.flaeche == null ? '-' : '${(r.flaeche! / 1e6).toStringAsFixed(2).replaceAll('.', ',')} m²',
          '${((r.ukDecke ?? h.rohdecke) - h.ffb)} mm',
          '${objekte.where((o) => o.raumId == r.id).length}',
        ]);
      }
    }
    if (raumZeilen.isNotEmpty) {
      _gefunden['Räume'] = _seite(doc);
      doc.addPage(pw.MultiPage(
        pageFormat: format,
        margin: rand,
        build: (c) => [_titel(c, 'Räume'), _tabelle(['Geschoss', 'Raum', 'Art', 'Fläche', 'lichte Höhe', 'Objekte'], raumZeilen)],
      ));
    }

    // Verteiler
    final schraenke = store.schraenke();
    final alleObjekte = store.alleObjekte();
    for (final s in schraenke) {
      final geraete = store.schrankGeraete(s.id);
      final kreise = store.stromkreise(s.id);
      final nach = {for (final g in geraete) g.id: g};
      final b = belegung(s, geraete);
      _gefunden['Verteiler ${s.name} (=${s.kennzeichen})'] = _seite(doc);
      doc.addPage(pw.MultiPage(
        pageFormat: format,
        margin: rand,
        build: (c) => [
          _titel(c, 'Verteiler ${s.name} (=${s.kennzeichen})'),
          pw.Text(_t('${s.art.label}, ${s.reihen} Reihen à ${s.teJeReihe} TE - ${b.belegt} TE belegt, Reserve ${(b.reserve * 100).round()} %'), style: _klein),
          pw.SizedBox(height: 6),
          _tabelle(['Reihe', 'TE', 'Kennzeichen', 'Gerät', 'Daten', 'Phase', 'vorgeschaltet'], [
            for (final g in geraete)
              [
                '${g.reihe + 1}',
                '${g.position + 1}-${g.ende}',
                betriebsmittel(s, g),
                g.art.label,
                g.kurz,
                g.phase ?? '-',
                nach[g.vorgeschaltetId]?.kennzeichen ?? '-',
              ],
          ]),
          pw.SizedBox(height: 10),
          _titel(c, 'Stromkreisliste =${s.kennzeichen}', ebene: 1),
          _tabelle(['Nr.', 'Bezeichnung', 'Schutzorgan', 'FI/RCD', 'Querschnitt', 'Leitung', 'Räume'], [
            for (final k in kreise)
              () {
                final sch = nach[k.schutzId];
                final rcd = sch?.art == GeraeteArt.fils ? sch : nach[sch?.vorgeschaltetId];
                final rs = {for (final o in alleObjekte) if (o.eigenschaften['stromkreis'] == k.id && raumNamen[o.raumId] != null) raumNamen[o.raumId]!};
                return [
                  k.nummer,
                  k.bezeichnung,
                  sch == null ? '-' : '${sch.kennzeichen} ${sch.kurz}',
                  rcd == null ? '-' : '${rcd.kennzeichen} ${rcd.fehlerstrom ?? 30} mA',
                  k.querschnittText,
                  k.leitung,
                  rs.join(', '),
                ];
              }(),
          ]),
        ],
      ));
    }

    // KNX
    final gas = [for (final m in (store.einstellung<List>('knx_gruppenadressen') ?? const [])) Gruppenadresse.ausJson(Map<String, dynamic>.from(m as Map))];
    if (gas.isNotEmpty) {
      _gefunden['KNX-Gruppenadressen'] = _seite(doc);
      doc.addPage(pw.MultiPage(
        pageFormat: format,
        margin: rand,
        build: (c) => [
          _titel(c, 'KNX-Gruppenadressen'),
          _tabelle(['Adresse', 'Name', 'Funktion', 'DPT', 'Objekte'], [
            for (final g in gas)
              [g.adresse, g.name, gaFunktionen[g.funktion]?.$1 ?? g.funktion, g.dpt, g.objekte.map((o) => alleObjekte.where((x) => x.id == o).firstOrNull?.kennung ?? '?').join(', ')],
          ]),
        ],
      ));
    }

    // Prüfprotokolle und Bautagebuch
    final pruef = store.pruefprotokolle();
    final tagebuch = store.tagebuch();
    if (pruef.isNotEmpty || tagebuch.isNotEmpty) {
      String d(DateTime x) => '${x.day}.${x.month}.${x.year}';
      _gefunden['Prüfprotokolle und Bautagebuch'] = _seite(doc);
      doc.addPage(pw.MultiPage(
        pageFormat: format,
        margin: rand,
        build: (c) => [
          if (pruef.isNotEmpty) ...[
            _titel(c, 'Prüfprotokolle'),
            _tabelle(['Datum', 'Art', 'Raum', 'Messwerte', 'Ergebnis', 'geprüft von'], [
              for (final x in pruef)
                [d(x.datum), x.art, raumNamen[x.raumId] ?? '-', x.messwerte.entries.map((e) => '${e.key}: ${e.value}').join('; '), x.ergebnis, x.pruefer],
            ]),
            pw.SizedBox(height: 12),
          ],
          if (tagebuch.isNotEmpty) ...[
            _titel(c, 'Bautagebuch'),
            _tabelle(['Datum', 'Text', 'Räume', 'Stunden', 'Wer'], [
              for (final e in tagebuch.reversed)
                [d(e.datum), e.text, e.raeume.map((r) => raumNamen[r] ?? '').join(', '), e.stunden.toStringAsFixed(1).replaceAll('.', ','), e.personen],
            ]),
          ],
        ],
      ));
    }

    // Fotos je Raum
    final fotoSeiten = <pw.Widget>[];
    for (final g in geschosse) {
      final fotos = store.fotos(g.id);
      final nachRaum = <String?, List<Foto>>{};
      for (final f in fotos) {
        nachRaum.putIfAbsent(f.raumId, () => []).add(f);
      }
      for (final e in nachRaum.entries) {
        final bilder = <(Uint8List, Foto)>[];
        for (final f in e.value.take(fotosJeRaum)) {
          final b = _fotoCache.containsKey(f.datei) ? _fotoCache[f.datei] : (_fotoCache[f.datei] = await _vorschau(f.datei));
          if (b != null) bilder.add((b, f));
        }
        if (bilder.isEmpty) continue;
        fotoSeiten
          ..add(_titel(null, 'Fotos ${raumNamen[e.key] ?? '${g.kuerzel} ohne Raum'}', ebene: 1))
          ..add(pw.Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (b, f) in bilder)
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Image(pw.MemoryImage(b), width: 120 * PdfPageFormat.mm / 2, fit: pw.BoxFit.contain),
                pw.Text(_t('${f.aufnahme.day}.${f.aufnahme.month}.${f.aufnahme.year}${f.notiz == null ? '' : ' - ${f.notiz}'}'), style: const pw.TextStyle(fontSize: 7)),
              ]),
          ]))
          ..add(pw.SizedBox(height: 10));
      }
    }
    if (fotoSeiten.isNotEmpty) {
      _gefunden['Fotos je Raum'] = _seite(doc);
      doc.addPage(pw.MultiPage(pageFormat: format, margin: rand, build: (c) => [_titel(c, 'Fotos je Raum'), ...fotoSeiten]));
    }

    // Kosten
    final pos = store.kostenpositionen();
    if (pos.isNotEmpty) {
      final gewerke = {for (final g in store.gewerke()) g.id: g};
      final jeGewerk = <String, int>{};
      for (final x in pos) {
        final k = gewerke[x.gewerkId]?.name ?? 'ohne Gewerk';
        jeGewerk[k] = (jeGewerk[k] ?? 0) + x.bruttoCent;
      }
      final summe = pos.fold<int>(0, (a, x) => a + x.bruttoCent);
      _gefunden['Kostenübersicht'] = _seite(doc);
      doc.addPage(pw.MultiPage(
        pageFormat: format,
        margin: rand,
        build: (c) => [
          _titel(c, 'Kostenübersicht'),
          _tabelle(['Gewerk', 'Summe brutto'], [
            for (final e in jeGewerk.entries) [e.key, euroText(e.value)],
            ['Gesamt', euroText(summe)],
          ]),
          pw.SizedBox(height: 10),
          _tabelle(['Position', 'Menge', 'Gesamt brutto', 'Status'], [
            for (final x in pos) [x.text, '${mengeText(x.mengeMilli)} ${x.einheit}', euroText(x.bruttoCent), x.status.label],
          ]),
        ],
      ));
    }

    return doc;
  }
}

/// Projektordner als ZIP (mit dem in Windows eingebauten tar).
Future<String> projektAlsZip(ProjectStore store) async {
  final ziel = Directory(p.join(p.dirname(store.ordner), 'BauSpur-Sicherungen'))..createSync(recursive: true);
  final stempel = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '');
  final datei = p.join(ziel.path, '${p.basename(store.ordner)}_$stempel.zip');
  final r = await Process.run('tar', ['-a', '-c', '-f', datei, '--exclude=projekt.lock', '-C', store.ordner, '.']);
  if (r.exitCode != 0) throw ProcessException('tar', const [], '${r.stderr}', r.exitCode);
  return datei;
}
