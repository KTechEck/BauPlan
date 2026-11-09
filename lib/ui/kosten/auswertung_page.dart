import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/auswertung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

String _menge(double m) => m == m.roundToDouble() ? m.round().toString() : m.toStringAsFixed(2).replaceAll('.', ',');

/// Plan/Ist: Fortschritt der Installation (geplant → verlegt → geprüft →
/// verdeckt) je Objektart und Kosten Plan/Ist je Gewerk.
class PlanIstAnsicht extends StatefulWidget {
  const PlanIstAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<PlanIstAnsicht> createState() => _PlanIstAnsichtState();
}

class _PlanIstAnsichtState extends State<PlanIstAnsicht> {
  String? _raumId;
  String? _gewerkId;

  @override
  Widget build(BuildContext context) {
    final store = widget.state.store!;
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final gewerke = {for (final g in store.gewerke()) g.id: g};
    final raeume = [
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) (r, g),
    ];
    final zeilen = fortschritt(store.alleObjekte(), typen, raumId: _raumId, gewerkId: _gewerkId);
    final kosten = kostenVergleich(store.kostenpositionen().where((k) => _gewerkId == null || k.gewerkId == _gewerkId));
    final summe = KostenVergleich(null);
    for (final k in kosten) {
      summe
        ..plan += k.plan
        ..beauftragt += k.beauftragt
        ..bezahlt += k.bezahlt
        ..offen += k.offen;
    }
    final gesamtAnzahl = zeilen.fold<int>(0, (s, z) => s + z.anzahl);

    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<String?>(
          value: _raumId,
          hint: const Text('alle Räume'),
          items: [
            const DropdownMenuItem(value: null, child: Text('alle Räume')),
            for (final (r, g) in raeume) DropdownMenuItem(value: r.id, child: Text('${g.kuerzel} · ${r.name}')),
          ],
          onChanged: (v) => setState(() => _raumId = v),
        ),
        DropdownButton<String?>(
          value: _gewerkId,
          hint: const Text('alle Gewerke'),
          items: [
            const DropdownMenuItem(value: null, child: Text('alle Gewerke')),
            for (final g in gewerke.values) DropdownMenuItem(value: g.id, child: Text(g.name)),
          ],
          onChanged: (v) => setState(() => _gewerkId = v),
        ),
        Text('$gesamtAnzahl Objekte', style: const TextStyle(color: BsFarben.textLeise)),
      ]),
      const SizedBox(height: 12),
      Text('Installation: Plan und Ist', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text('Ist = Status „verlegt“, „geprüft“ oder „verdeckt“ (in der Installation je Objekt gesetzt).',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      Card(
        child: zeilen.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Text('Noch keine Objekte geplant.'))
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('Objektart')),
                    DataColumn(label: Text('Gewerk')),
                    DataColumn(label: Text('Plan'), numeric: true),
                    DataColumn(label: Text('verlegt'), numeric: true),
                    DataColumn(label: Text('geprüft'), numeric: true),
                    DataColumn(label: Text('verdeckt'), numeric: true),
                    DataColumn(label: Text('offen'), numeric: true),
                    DataColumn(label: Text('Fortschritt')),
                  ],
                  rows: [
                    for (final z in zeilen)
                      DataRow(cells: [
                        DataCell(Text(z.typ.name)),
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 10, height: 10, color: Color(gewerke[z.typ.gewerkId]?.farbe ?? 0xFF888888)),
                          const SizedBox(width: 6),
                          Text(gewerke[z.typ.gewerkId]?.name ?? ''),
                        ])),
                        DataCell(Text('${_menge(z.gesamt)} ${z.einheit}')),
                        DataCell(Text(_menge(z.verlegt))),
                        DataCell(Text(_menge(z.geprueft))),
                        DataCell(Text(_menge(z.verdeckt))),
                        DataCell(Text(_menge(z.offen), style: TextStyle(fontWeight: z.offen > 0 ? FontWeight.w600 : null))),
                        DataCell(SizedBox(
                          width: 140,
                          child: Row(children: [
                            Expanded(child: LinearProgressIndicator(value: z.anteil, minHeight: 6)),
                            const SizedBox(width: 6),
                            Text('${(z.anteil * 100).round()} %', style: const TextStyle(fontSize: 12)),
                          ]),
                        )),
                      ]),
                  ],
                ),
              ),
      ),
      const SizedBox(height: 20),
      Text('Kosten: Plan und Ist', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text('Plan = alle Positionen · beauftragt = bestellt/geliefert · offen = geplant/angefragt (alles brutto).',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('Gewerk')),
              DataColumn(label: Text('Plan'), numeric: true),
              DataColumn(label: Text('offen'), numeric: true),
              DataColumn(label: Text('beauftragt'), numeric: true),
              DataColumn(label: Text('bezahlt'), numeric: true),
              DataColumn(label: Text('bezahlt %'), numeric: true),
            ],
            rows: [
              for (final k in [...kosten, summe])
                DataRow(cells: [
                  DataCell(Text(identical(k, summe) ? 'Summe' : (gewerke[k.gewerkId]?.name ?? 'ohne Gewerk'),
                      style: TextStyle(fontWeight: identical(k, summe) ? FontWeight.w700 : null))),
                  DataCell(Text(euroText(k.plan))),
                  DataCell(Text(euroText(k.offen))),
                  DataCell(Text(euroText(k.beauftragt))),
                  DataCell(Text(euroText(k.bezahlt))),
                  DataCell(Text('${(k.anteilBezahlt * 100).round()} %')),
                ]),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// Einkaufsliste: offene Material-Positionen nach Händler, abhaken = bestellt.
class EinkaufAnsicht extends StatefulWidget {
  const EinkaufAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<EinkaufAnsicht> createState() => _EinkaufAnsichtState();
}

class _EinkaufAnsichtState extends State<EinkaufAnsicht> {
  bool _unterwegs = true;

  AppState get _s => widget.state;

  double get _zuschlag => (_s.store!.einstellung<num>('einkauf_zuschlag') ?? 10).toDouble();

  Map<String, List<EinkaufsPosition>> _liste({bool? unterwegs}) => einkaufsliste(
        _s.store!.kostenpositionen(),
        _s.store!.produkte(),
        zuschlagProzent: _zuschlag,
        auchUnterwegs: unterwegs ?? _unterwegs,
      );

  Future<void> _speichern(String endung) async {
    final store = _s.store!;
    final liste = _liste(unterwegs: false);
    if (liste.isEmpty) {
      zeigeHinweis(context, 'Nichts offen – alle Material-Positionen sind bestellt.');
      return;
    }
    final jetzt = DateTime.now();
    final stamp = '${jetzt.year}-${jetzt.month.toString().padLeft(2, '0')}-${jetzt.day.toString().padLeft(2, '0')}';
    final datei = File(p.join(store.ordner, 'exporte', 'Einkaufsliste_$stamp.$endung'));
    await datei.parent.create(recursive: true);
    final name = p.basename(store.ordner);
    if (endung == 'csv') {
      // mit BOM, damit Excel die Umlaute erkennt
      await datei.writeAsString('﻿${einkaufCsv(liste)}');
    } else {
      await datei.writeAsString(einkaufHtml(name, liste, jetzt));
    }
    if (!mounted) return;
    zeigeHinweis(context, 'Gespeichert: ${datei.path}',
        aktion: SnackBarAction(label: 'Pfad kopieren', onPressed: () => Clipboard.setData(ClipboardData(text: datei.path))));
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final liste = _liste();
    final gesamt = liste.values.expand((e) => e).where((e) => e.position.status != KostenStatus.bestellt).fold<int>(0, (s, e) => s + e.bruttoCent);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Verschnitt-Zuschlag (m, m²) '),
          DropdownButton<int>(
            value: _zuschlag.round(),
            items: [for (final z in const [0, 5, 10, 15, 20]) DropdownMenuItem(value: z, child: Text('$z %'))],
            onChanged: (v) {
              store.einstellungSetzen('einkauf_zuschlag', v ?? 10);
              setState(() {});
            },
          ),
        ]),
        FilterChip(
          label: const Text('bestellte zeigen'),
          selected: _unterwegs,
          onSelected: (v) => setState(() => _unterwegs = v),
        ),
        OutlinedButton.icon(
          onPressed: () => _speichern('html'),
          icon: const Icon(Icons.phone_iphone, size: 18),
          label: const Text('Abhakliste fürs Handy'),
        ),
        OutlinedButton.icon(
          onPressed: () => _speichern('csv'),
          icon: const Icon(Icons.table_view_outlined, size: 18),
          label: const Text('CSV für Excel'),
        ),
        Text('noch zu kaufen: ${euroText(gesamt)}', style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 6),
      const Text(
          'Haken = gekauft/bestellt (Status der Kostenposition wird „bestellt“). Mengen aus dem Plan, Meter und m² mit Zuschlag aufgerundet; '
          'Preis vom günstigsten Händlerangebot des Produkts. Die Abhakliste landet im Projektordner unter exporte/ und lässt sich auf dem Handy öffnen.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      if (liste.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nichts zu kaufen – keine offenen Material-Positionen.'))),
      for (final e in liste.entries) ...[
        const SizedBox(height: 8),
        Row(children: [
          Text(e.key, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text(euroText(e.value.fold<int>(0, (s, x) => s + x.bruttoCent)), style: const TextStyle(color: BsFarben.textLeise)),
        ]),
        Card(
          child: Column(children: [
            for (final x in e.value)
              CheckboxListTile(
                dense: true,
                value: x.position.status == KostenStatus.bestellt,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(x.position.text,
                    style: TextStyle(
                        decoration: x.position.status == KostenStatus.bestellt ? TextDecoration.lineThrough : null)),
                subtitle: Text([
                  if (x.produkt?.artikelnummer != null) 'Art.-Nr. ${x.produkt!.artikelnummer}',
                  'Plan ${_menge(x.position.mengeMilli / 1000)} ${x.position.einheit}',
                  if (x.angebot?.link != null && x.angebot!.link!.isNotEmpty) x.angebot!.link!,
                ].join(' · ')),
                secondary: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${_menge(x.menge)} ${x.position.einheit}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(euroText(x.bruttoCent), style: const TextStyle(fontSize: 12)),
                ]),
                onChanged: (v) {
                  store.kostenpositionAendern(x.position.id, {'status': (v == true ? KostenStatus.bestellt : KostenStatus.geplant).name});
                  _s.geaendert();
                  setState(() {});
                },
              ),
          ]),
        ),
      ],
    ]);
  }
}
