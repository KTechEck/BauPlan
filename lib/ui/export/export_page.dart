import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/raumerkennung.dart';
import '../../core/wandmasse.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';
import '../../state/app_state.dart';
import '../floorplan/floorplan_painter.dart';
import '../installation/installation_page.dart' show ObjektPainter, wandStrecke;
import '../widgets.dart';
import 'hausdoku.dart';

/// Modul Export: Pläne (Grundriss, Installation je Gewerk) und Kostenliste als PDF.
class ExportPage extends StatefulWidget {
  const ExportPage({super.key, required this.state});
  final AppState state;

  @override
  State<ExportPage> createState() => _ExportPageState();
}

enum Papier { a4, a3 }

class _ExportPageState extends State<ExportPage> {
  final Set<String> _geschosse = {};
  final Set<String> _gewerke = {};
  bool _grundriss = true;
  bool _installation = true;
  bool _kosten = true;
  Papier _papier = Papier.a3;
  int _massstab = 0; // 0 = passend
  bool _laeuft = false;
  String? _letzteDatei;
  bool _init = false;

  AppState get _s => widget.state;

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final gebaeude = store.gebaeude();
    final geschosse = [for (final g in gebaeude) ...store.geschosse(g.id)];
    final gewerke = store.gewerke();
    if (!_init) {
      _init = true;
      if (_s.geschossId != null) _geschosse.add(_s.geschossId!);
      _gewerke.addAll(gewerke.where((g) => g.sichtbar).map((g) => g.id));
    }
    final exporte = Directory(p.join(store.ordner, 'exporte'));
    final dateien = exporte.existsSync()
        ? (exporte.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.pdf')).toList()
          ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync())))
        : <File>[];

    return Material(
      color: BsFarben.flaeche,
      child: ListView(padding: const EdgeInsets.all(28), children: [
        Text('Export', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('Pläne mit Plankopf und Maßstab sowie die Kostenliste als PDF in den Ordner „exporte“ des Projekts.'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 40, runSpacing: 16, children: [
              _spalte('Geschosse', [
                for (final g in geschosse)
                  _haken('${g.kuerzel} · ${g.name}', _geschosse.contains(g.id), (v) => setState(() => v ? _geschosse.add(g.id) : _geschosse.remove(g.id))),
              ]),
              _spalte('Inhalt', [
                _haken('Grundriss (Wände, Räume, Maße)', _grundriss, (v) => setState(() => _grundriss = v)),
                _haken('Installationsplan', _installation, (v) => setState(() => _installation = v)),
                _haken('Kostenliste', _kosten, (v) => setState(() => _kosten = v)),
              ]),
              _spalte('Gewerke im Installationsplan', [
                for (final g in gewerke)
                  _haken(g.name, _gewerke.contains(g.id), (v) => setState(() => v ? _gewerke.add(g.id) : _gewerke.remove(g.id)),
                      farbe: Color(g.farbe)),
              ]),
              _spalte('Papier und Maßstab', [
                DropdownButton<Papier>(
                  value: _papier,
                  items: const [
                    DropdownMenuItem(value: Papier.a3, child: Text('A3 quer')),
                    DropdownMenuItem(value: Papier.a4, child: Text('A4 quer')),
                  ],
                  onChanged: (v) => setState(() => _papier = v ?? _papier),
                ),
                DropdownButton<int>(
                  value: _massstab,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Maßstab passend')),
                    DropdownMenuItem(value: 50, child: Text('1 : 50')),
                    DropdownMenuItem(value: 100, child: Text('1 : 100')),
                    DropdownMenuItem(value: 200, child: Text('1 : 200')),
                  ],
                  onChanged: (v) => setState(() => _massstab = v ?? _massstab),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          FilledButton.icon(
            onPressed: _laeuft || (_geschosse.isEmpty && !_kosten) ? null : _erstellen,
            icon: _laeuft
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Sym.pdf),
            label: const Text('PDF erstellen'),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: _laeuft ? null : _hausdoku,
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Hausdokumentation (komplett)'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _laeuft ? null : _zip,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Projekt als ZIP'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => Process.run('explorer', [exporte.path]),
            icon: const Icon(Sym.ordner),
            label: const Text('Ordner öffnen'),
          ),
          if (_letzteDatei != null) ...[
            const SizedBox(width: 12),
            Flexible(child: Text('Erstellt: ${p.basename(_letzteDatei!)}', overflow: TextOverflow.ellipsis)),
          ],
        ]),
        const SizedBox(height: 24),
        if (dateien.isNotEmpty) ...[
          Text('Bisherige Exporte', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final f in dateien.take(15))
                ListTile(
                  dense: true,
                  leading: const Icon(Sym.pdf),
                  title: Text(p.basename(f.path)),
                  subtitle: Text('${(f.lengthSync() / 1024).round()} KB'),
                  onTap: () => Process.run('explorer', [f.path]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _spalte(String titel, List<Widget> kinder) => SizedBox(
        width: 260,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titel, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...kinder,
        ]),
      );

  Widget _haken(String text, bool wert, void Function(bool) setzen, {Color? farbe}) => InkWell(
        onTap: () => setzen(!wert),
        child: Row(children: [
          Checkbox(value: wert, onChanged: (v) => setzen(v ?? false)),
          if (farbe != null) Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 6), color: farbe),
          Flexible(child: Text(text)),
        ]),
      );


  Future<void> _hausdoku() async {
    setState(() => _laeuft = true);
    try {
      final datei = await HausDokumentation(store: _s.store!, papier: _papier).erstellen();
      if (mounted) {
        setState(() => _letzteDatei = datei);
        zeigeHinweis(context, 'Hausdokumentation gespeichert: ${p.basename(datei)}',
            aktion: SnackBarAction(label: 'Öffnen', onPressed: () => Process.run('explorer', [datei])));
      }
    } catch (e) {
      if (mounted) zeigeFehler(context, 'Hausdokumentation fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  Future<void> _zip() async {
    setState(() => _laeuft = true);
    try {
      final datei = await projektAlsZip(_s.store!);
      if (mounted) zeigeHinweis(context, 'ZIP gespeichert: $datei', aktion: SnackBarAction(label: 'Ordner', onPressed: () => Process.run('explorer', [p.dirname(datei)])));
    } catch (e) {
      if (mounted) zeigeFehler(context, 'ZIP fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }
  Future<void> _erstellen() async {
    setState(() => _laeuft = true);
    try {
      final datei = await PlanExport(
        store: _s.store!,
        geschossIds: _geschosse.toList(),
        gewerkIds: _gewerke,
        grundriss: _grundriss,
        installation: _installation,
        kosten: _kosten,
        papier: _papier,
        massstab: _massstab,
      ).erstellen();
      if (mounted) {
        setState(() => _letzteDatei = datei);
        zeigeHinweis(context, 'PDF gespeichert: ${p.basename(datei)}',
            aktion: SnackBarAction(label: 'Öffnen', onPressed: () => Process.run('explorer', [datei])));
      }
    } catch (e) {
      if (mounted) zeigeFehler(context, 'Export fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }
}

/// Erzeugt das PDF. Pläne werden mit den Zeichenroutinen des Programms
/// gerendert (damit sie genau wie am Bildschirm aussehen) und maßstäblich
/// auf die Seite gesetzt.
class PlanExport {
  PlanExport({
    required this.store,
    required this.geschossIds,
    required this.gewerkIds,
    required this.grundriss,
    required this.installation,
    required this.kosten,
    required this.papier,
    required this.massstab,
  });

  final ProjectStore store;
  final List<String> geschossIds;
  final Set<String> gewerkIds;
  final bool grundriss, installation, kosten;
  final Papier papier;
  final int massstab;

  static const _rand = 10.0; // mm
  static const _plankopf = 22.0; // mm
  static const _logischProMm = 3.78; // Bildpunkte je Papier-mm für Schriftgrößen wie am Bildschirm
  static const _aufloesung = 2.2; // Faktor für die Rasterung (~210 dpi)

  /// PDF-Standardschrift kennt kein typografisches Minus.
  static String _t(String s) => s.replaceAll('−', '-').replaceAll('²', '2').replaceAll('·', '-');

  Future<String> erstellen() async {
    final doc = pw.Document(title: store.name, author: store.benutzer);
    final format = papier == Papier.a3 ? PdfPageFormat.a3.landscape : PdfPageFormat.a4.landscape;
    final breiteMm = format.width / PdfPageFormat.mm, hoeheMm = format.height / PdfPageFormat.mm;
    final zeichnungMm = Size(breiteMm - 2 * _rand, hoeheMm - 2 * _rand - _plankopf);

    for (final gid in geschossIds) {
      final g = store.geschoss(gid);
      if (g == null) continue;
      for (final (art, aktiv) in [('Grundriss', grundriss), ('Installationsplan', installation)]) {
        if (!aktiv) continue;
        final (png, n) = await _plan(gid, art == 'Installationsplan', zeichnungMm);
        if (png == null) continue;
        doc.addPage(pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(_rand * PdfPageFormat.mm),
          build: (c) => pw.Column(children: [
            pw.Expanded(child: pw.Center(child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain))),
            pw.SizedBox(height: 2 * PdfPageFormat.mm),
            _kopf('$art ${g.kuerzel} - ${g.name}', '1 : $n'),
          ]),
        ));
      }
    }
    if (kosten) _kostenSeiten(doc, format);

    final ordner = Directory(p.join(store.ordner, 'exporte'))..createSync(recursive: true);
    final stempel = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '');
    final name = '${store.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}_$stempel.pdf';
    final datei = File(p.join(ordner.path, name));
    await datei.writeAsBytes(await doc.save());
    return datei.path;
  }

  pw.Widget _kopf(String inhalt, String massstabText) {
    const stil = pw.TextStyle(fontSize: 8);
    const fett = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);
    final heute = DateTime.now();
    return pw.Container(
      height: (_plankopf - 2) * PdfPageFormat.mm,
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
      child: pw.Row(children: [
        pw.Expanded(
          flex: 3,
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.center, children: [
              pw.Text(_t(store.name), style: fett),
              pw.Text(_t(inhalt), style: stil),
            ]),
          ),
        ),
        for (final (k, v) in [
          ('Maßstab', massstabText),
          ('Datum', '${heute.day}.${heute.month}.${heute.year}'),
          ('Bearbeiter', store.benutzer),
          ('Programm', 'BauSpur'),
        ])
          pw.Container(
            width: 34 * PdfPageFormat.mm,
            decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: 0.5))),
            padding: const pw.EdgeInsets.all(5),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.center, children: [
              pw.Text(_t(k), style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
              pw.Text(_t(v), style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
      ]),
    );
  }

  /// Plan als PNG für andere Ausgaben (z. B. Hausdokumentation).
  Future<(Uint8List?, int)> planBild(String gid, bool mitObjekten, Size flaecheMm) => _plan(gid, mitObjekten, flaecheMm);

  /// Rendert einen Plan als PNG passend zur Zeichenfläche; liefert Bild und Maßstabszahl.
  Future<(Uint8List?, int)> _plan(String gid, bool mitObjekten, Size flaecheMm) async {
    final waende = store.waende(gid);
    final objekte = mitObjekten
        ? store.objekte(gid)
        : <Objekt>[];
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final sichtbareObjekte = [for (final o in objekte) if (gewerkIds.contains(typen[o.typId]?.gewerkId)) o];
    final punkte = [
      for (final w in waende) ...[Offset(w.x1.toDouble(), w.y1.toDouble()), Offset(w.x2.toDouble(), w.y2.toDouble())],
      for (final o in sichtbareObjekte)
        for (final q in o.punkte) Offset(q.x, q.y),
    ];
    if (punkte.isEmpty) return (null, 0);
    var r = punkte.skip(1).fold(Rect.fromPoints(punkte.first, punkte.first), (Rect a, q) => a.expandToInclude(Rect.fromPoints(q, q)));
    r = r.inflate(800); // Platz für Maße
    // Maßstab: fest oder passend aus einer üblichen Reihe
    var n = massstab;
    final passend = math.max(r.width / flaecheMm.width, r.height / flaecheMm.height);
    if (n == 0 || n < passend) {
      n = const [20, 25, 50, 75, 100, 150, 200, 250, 500, 1000].firstWhere((s) => s >= passend, orElse: () => passend.ceil());
    }
    final logisch = Size(flaecheMm.width * _logischProMm, flaecheMm.height * _logischProMm);
    final pxProWeltMm = _logischProMm / n;
    final mitte = r.center;
    final verschiebung = Offset(logisch.width / 2, logisch.height / 2) - mitte * pxProWeltMm;

    final global = store.einstellung<bool>('ecken_verbinden') ?? true;
    final achsen = [for (final w in waende) w.achse];
    final verb = [for (final w in waende) w.verbinden ?? global];
    final nachbarn = [
      for (var i = 0; i < waende.length; i++)
        if (verb[i]) achsen[i]
    ];
    final raeume = store.raeume(gid);
    final mv = store.einstellung<String>('mass_anzeige');
    final grundrissPainter = FloorplanPainter(
      waende: waende,
      raeume: [
        for (final rm in raeume)
          if (rm.umriss != null)
            RaumBild(
              umriss: [for (final q in rm.umriss!) Offset(q.x, q.y)],
              beschriftung: rm.name,
              unterzeile: mitObjekten ? null : flaecheText(rm.flaeche!),
              innenpunkt: Offset(punktImInneren(rm.umriss!).x, punktImInneren(rm.umriss!).y),
            ),
      ],
      umrisse: {
        for (var i = 0; i < waende.length; i++)
          waende[i].id: [for (final q in wandUmriss(achsen[i], verb[i] ? nachbarn : [achsen[i]])) Offset(q.x, q.y)],
      },
      flanken: {
        for (var i = 0; i < waende.length; i++) waende[i].id: flankenLaengen(achsen[i], verb[i] ? nachbarn : [achsen[i]]),
      },
      schichten: mitObjekten
          ? const {}
          : {
              for (final t in store.wandtypen())
                t.id: [
                  for (final s in t.schichten)
                    (s.dicke, Color(store.materialien().where((m) => m.id == s.materialId).firstOrNull?.farbe ?? 0xFFDDDDDD))
                ],
            },
      massstab: pxProWeltMm,
      verschiebung: verschiebung,
      auswahl: const {},
      kettenStart: null,
      maus: null,
      vorschauDicke: 0,
      weissHintergrund: true,
      massVoreinstellung:
          mitObjekten ? MassAnzeige.keine : (MassAnzeige.values.where((m) => m.name == mv).firstOrNull ?? MassAnzeige.innenAussen),
      bemassungen: mitObjekten ? const [] : store.bemassungen(gid),
      oeffnungen: store.oeffnungen(gid),
    );
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(_aufloesung);
    canvas.clipRect(Offset.zero & logisch);
    grundrissPainter.paint(canvas, logisch);
    if (mitObjekten) {
      ObjektPainter(
        objekte: sichtbareObjekte,
        typen: typen,
        gewerke: {for (final x in store.gewerke()) x.id: x},
        massstab: pxProWeltMm,
        verschiebung: verschiebung,
        auswahl: null,
        entwurf: const [],
        entwurfFarbe: null,
        entwurfFlaeche: false,
        maus: null,
        waende: [for (final w in store.waende(gid)) wandStrecke(w)],
      ).paint(canvas, logisch);
    }
    final bild = await rec.endRecording().toImage(
          (logisch.width * _aufloesung).round(),
          (logisch.height * _aufloesung).round(),
        );
    final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
    return (daten?.buffer.asUint8List(), n);
  }

  void _kostenSeiten(pw.Document doc, PdfPageFormat format) {
    final pos = store.kostenpositionen();
    if (pos.isEmpty) return;
    final gewerke = {for (final g in store.gewerke()) g.id: g};
    final netto = pos.fold<int>(0, (s, p) => s + p.nettoCent);
    final steuer = pos.fold<int>(0, (s, p) => s + p.steuerCent);
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(_rand * PdfPageFormat.mm),
      build: (c) => [
        pw.Text(_t('Kostenliste - ${store.name}'), style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headerStyle: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
          headers: ['Position', 'Gewerk', 'Menge', 'EP netto', 'MwSt.', 'Gesamt brutto', 'Status'],
          data: [
            for (final p in pos)
              [
                _t(p.text),
                _t(gewerke[p.gewerkId]?.kuerzel ?? '-'),
                _t('${mengeText(p.mengeMilli)} ${p.einheit}'),
                _t(euroText(p.einzelCent)),
                '${p.steuer ~/ 100} %',
                _t(euroText(p.bruttoCent)),
                _t(p.status.label),
              ],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            _t('netto ${euroText(netto)}   MwSt. ${euroText(steuer)}   brutto ${euroText(netto + steuer)}'),
            style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ));
  }
}
