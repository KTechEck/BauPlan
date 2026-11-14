import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/gebaeude.dart';
import '../../core/leitung_wand.dart' show geschossStapel;
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../export/export_page.dart' show PlanExport, Papier;
import '../widgets.dart';

/// Wände eines anderen Geschosses als gestrichelte Unterlage (oder als rote
/// Warnung für tragende Wände ohne Wand darunter).
class UnterlagePainter extends CustomPainter {
  UnterlagePainter({required this.waende, required this.massstab, required this.verschiebung, this.warnung = false});
  final List<Wand> waende;
  final double massstab;
  final Offset verschiebung;
  final bool warnung;

  @override
  void paint(Canvas canvas, Size size) {
    final farbe = warnung ? const Color(0xFFDC2626) : const Color(0xFF3B82F6);
    final strich = Paint()
      ..color = farbe.withValues(alpha: warnung ? 0.9 : 0.6)
      ..strokeWidth = warnung ? 2.5 : 1.2;
    Offset s(double x, double y) => Offset(x, y) * massstab + verschiebung;
    for (final w in waende) {
      final l = w.laenge;
      if (l < 1) continue;
      final ux = (w.x2 - w.x1) / l, uy = (w.y2 - w.y1) / l;
      final h = w.dicke / 2;
      for (final q in [h, -h]) {
        final a = s(w.x1 - uy * q, w.y1 + ux * q), b = s(w.x2 - uy * q, w.y2 + ux * q);
        final d = b - a;
        final lp = d.distance;
        if (lp < 1) continue;
        final u = d / lp;
        for (var t = 0.0; t < lp; t += 8) {
          canvas.drawLine(a + u * t, a + u * (t + 4 > lp ? lp : t + 4), strich);
        }
      }
    }
  }

  @override
  bool shouldRepaint(UnterlagePainter old) => old.waende != waende || old.massstab != massstab || old.verschiebung != verschiebung;
}

String _mm(num v) => '${(v / 1000).toStringAsFixed(2).replaceAll('.', ',')} m';

/// Mappe für den Statiker: je Geschoss Grundriss, tragende Wände, Öffnungen
/// und Durchbrüche darin mit Sturz-Richtwerten und die Lastabtragung
/// (steht auf Wand darunter?). Nur Zusammenstellung, keine Berechnung.
Future<void> statikerMappeErstellen(BuildContext context, AppState s) async {
  final store = s.store!;
  final doc = pw.Document(title: 'Mappe für den Statiker', author: store.benutzer);
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final geloest = {for (final e in (store.einstellung<List>('geschoss_verknuepfung_geloest') ?? const [])) '$e'};
  final format = PdfPageFormat.a3.landscape;
  final plaene = PlanExport(store: store, geschossIds: const [], gewerkIds: const {}, grundriss: true, installation: false, kosten: false, papier: Papier.a3, massstab: 0);
  var tragendGesamt = 0;
  for (final geb in store.gebaeude()) {
    final stapel = geschossStapel(store.geschosse(geb.id));
    for (var i = 0; i < stapel.length; i++) {
      final g = stapel[i];
      final waende = store.waende(g.id);
      final tragend = [for (final w in waende) if (w.eigenschaften['tragend'] == true) w];
      final oeff = store.oeffnungen(g.id);
      final wd = [for (final o in store.objekte(g.id)) if (typen[o.typId]?.kuerzel == 'WD' && o.punkte.isNotEmpty) o];
      final unten = i > 0 ? stapel[i - 1] : null;
      WandAchse2 achse(Wand w) => (id: w.id, a: Punkt(w.x1.toDouble(), w.y1.toDouble()), b: Punkt(w.x2.toDouble(), w.y2.toDouble()), dicke: w.dicke);
      final verkn = unten == null ? const <String, String>{} : wandVerknuepfungen([for (final w in waende) achse(w)], [for (final w in store.waende(unten.id)) achse(w)], geloest: geloest);
      if (tragend.isEmpty && wd.isEmpty) continue;
      tragendGesamt += tragend.length;
      final (png, n) = await plaene.planBild(g.id, false, const ui.Size(400, 230));
      final zeilen = <List<String>>[];
      for (final w in tragend) {
        final typ = w.wandtypId == null ? null : store.wandtyp(w.wandtypId!);
        final drin = [for (final o in oeff) if (o.wandId == w.id && o.art != OeffnungsArt.nische) o];
        final durch = [
          for (final o in wd)
            if (_abstand(o.punkte.first, w) <= w.dicke / 2 + 100) o
        ];
        zeilen.add([
          '${typ?.name ?? 'Wand'} · ${w.dicke} mm · ${_mm(w.laenge)}',
          unten == null ? '–' : (verkn.containsKey(w.id) ? 'steht auf Wand (${unten.kuerzel})' : 'KEINE Wand darunter (${unten.kuerzel})'),
          [
            for (final o in drin)
              () {
                final r = sturzRichtwert(o.breite.toDouble(), wanddicke: w.dicke.toDouble());
                return '${o.art.label} ${o.breite}×${o.hoehe}: Sturz ≥ ${r.laenge.round()} mm, ${r.art}';
              }(),
            for (final o in durch) 'Durchbruch ${o.kennung}${o.eigenschaften['durchmesser'] != null ? ' Ø ${o.eigenschaften['durchmesser']} mm' : ''}',
          ].join('\n'),
        ]);
      }
      doc.addPage(pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        build: (c) => [
          pw.Text('Mappe für den Statiker · ${g.kuerzel} ${g.name}', style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('${store.name} · Stand ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year} · Zusammenstellung aus BauSpur, keine statische Berechnung. '
              'Sturzlängen und Ausführungen sind Richtwerte zur Abstimmung.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          if (png != null) pw.Image(pw.MemoryImage(png), height: 360, fit: pw.BoxFit.contain),
          if (png != null) pw.Text('Grundriss ca. 1:$n', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 10),
          if (zeilen.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: ['Tragende Wand', 'Lastabtragung', 'Öffnungen / Durchbrüche (Richtwerte)'],
              data: zeilen,
              headerStyle: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1.4), 2: const pw.FlexColumnWidth(3)},
            )
          else
            pw.Text('Keine Wand als tragend markiert – Durchbrüche: ${wd.map((o) => o.kennung).join(', ')}', style: const pw.TextStyle(fontSize: 10)),
        ],
      ));
    }
  }
  if (tragendGesamt == 0 && doc.document.pdfPageList.pages.isEmpty) {
    if (context.mounted) zeigeHinweis(context, 'Noch keine tragende Wand markiert (Wand wählen › „tragende Wand“).');
    return;
  }
  final datei = File(p.join(store.ordner, 'exporte', 'Mappe Statiker.pdf'));
  await datei.parent.create(recursive: true);
  await datei.writeAsBytes(await doc.save());
  if (context.mounted) zeigeHinweis(context, 'Gespeichert unter ${datei.path}');
}

double _abstand(Punkt q, Wand w) {
  final ax = w.x1.toDouble(), ay = w.y1.toDouble(), dx = w.x2 - ax, dy = w.y2 - ay;
  final l2 = dx * dx + dy * dy;
  if (l2 == 0) return (q - Punkt(ax, ay)).laenge;
  final t = (((q.x - ax) * dx + (q.y - ay) * dy) / l2).clamp(0.0, 1.0);
  return (q - Punkt(ax + dx * t, ay + dy * t)).laenge;
}
