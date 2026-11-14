import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/auslegung_projekt.dart';
import '../../core/elektro.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../data/schrank_models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

const _gruen = Color(0xFF2F9E44);
const _orange = Color(0xFFE67700);

/// Verteiler › Prüfung: Plankopf, Phasenlast, Prüfpunkte, Checkliste,
/// Verdrahtungsabgleich und Ausstattung nach DIN 18015-2.
class ElektroPruefungAnsicht extends StatefulWidget {
  const ElektroPruefungAnsicht({super.key, required this.state, required this.schrank});
  final AppState state;
  final Schrank schrank;

  @override
  State<ElektroPruefungAnsicht> createState() => _ElektroPruefungAnsichtState();
}

class _ElektroPruefungAnsichtState extends State<ElektroPruefungAnsicht> {
  AppState get _s => widget.state;

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final s = widget.schrank;
    final kreise = store.stromkreise(s.id);
    final geraete = store.schrankGeraete(s.id);
    final last = phasenlast(kreise, geraete, {for (final a in kreiseAuslegen(store, s)) a.kreis.id: a.leistung});
    final maxLast = last.values.fold<double>(1, (a, b) => a > b ? a : b);
    final punkte = elektroPruefen(store, s);
    final abgleich = verdrahtungsabgleich(store);
    final check = Map<String, dynamic>.from(store.einstellung<Map>('elektro_pruefung') ?? const {});
    final kopf = plankopf(store);
    final wert = store.einstellung<int>('ausstattungswert') ?? 2;
    final typen = {for (final t in store.objekttypen()) t.id: t};

    Widget titel(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(t, style: Theme.of(context).textTheme.titleMedium));
    Widget punkt(ElektroPunkt p) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(p.ok ? Icons.info_outline : Icons.warning_amber, size: 16, color: p.ok ? BsFarben.textLeise : _orange),
          const SizedBox(width: 6),
          SizedBox(width: 90, child: Text(p.bereich, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise))),
          Expanded(child: Text(p.text, style: const TextStyle(fontSize: 13))),
        ]);

    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Planungshilfe – ersetzt nicht die Erstprüfung nach DIN VDE 0100-600 durch eine Elektrofachkraft.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      titel('Plankopf (Stromlaufplan, Beschriftung, Ausgaben)'),
      Wrap(spacing: 12, runSpacing: 8, children: [
        for (final (k, l) in const [('ersteller', 'Erstellt von'), ('firma', 'Firma / Elektrofachkraft'), ('revision', 'Änderungsstand'), ('adresse', 'Anschrift Objekt')])
          SizedBox(
            width: 240,
            child: SpeicherFeld(
              key: ValueKey('pk-$k-${kopf[k]}'),
              initialValue: kopf[k] ?? '',
              decoration: InputDecoration(labelText: l, isDense: true),
              onFieldSubmitted: (t) {
                store.einstellungSetzen('plankopf', {...kopf, k: t.trim()}..removeWhere((_, v) => v.isEmpty));
                _s.geaendert();
                setState(() {});
              },
            ),
          ),
      ]),
      titel('Phasenlast ${s.kennzeichen}'),
      for (final e in last.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 30, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(
              child: LinearProgressIndicator(
                value: maxLast <= 0 ? 0 : e.value / maxLast,
                minHeight: 12,
                color: BsFarben.akzent,
                backgroundColor: BsFarben.flaeche,
              ),
            ),
            SizedBox(width: 90, child: Text(' ${(e.value / 1000).toStringAsFixed(2).replaceAll('.', ',')} kW', textAlign: TextAlign.right)),
          ]),
        ),
      const Text('Phase je Stromkreis legst du am Schutzorgan fest (Feld „Phase“); Kreise ohne Phase werden der schwächsten zugerechnet.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      titel('Automatische Prüfpunkte'),
      if (punkte.isEmpty) const Text('Keine Auffälligkeiten.', style: TextStyle(color: _gruen)),
      for (final p in punkte) punkt(p),
      titel('Checkliste Erdung, Potentialausgleich, Blitzschutz, Messungen'),
      for (final e in elektroCheckliste.entries)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: check[e.key] == true,
          title: Text(e.value),
          onChanged: (v) {
            store.einstellungSetzen('elektro_pruefung', {...check, e.key: v == true});
            _s.geaendert();
            setState(() {});
          },
        ),
      titel('Verdrahtungsabgleich Plan ↔ Verteiler'),
      if (abgleich.isEmpty) const Text('Plan und Verteiler passen zusammen.', style: TextStyle(color: _gruen)),
      for (final p in abgleich.take(40)) punkt(p),
      if (abgleich.length > 40) Text('… und ${abgleich.length - 40} weitere', style: const TextStyle(fontSize: 12)),
      Row(children: [
        Expanded(child: titel('Ausstattung nach DIN 18015-2 (Richtwerte)')),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 1, label: Text('Wert 1')),
            ButtonSegment(value: 2, label: Text('Wert 2')),
            ButtonSegment(value: 3, label: Text('Wert 3')),
          ],
          selected: {wert},
          onSelectionChanged: (v) {
            store.einstellungSetzen('ausstattungswert', v.first);
            setState(() {});
          },
        ),
      ]),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: const [
            DataColumn(label: Text('Raum')),
            DataColumn(label: Text('Steckdosen'), numeric: true),
            DataColumn(label: Text('Licht'), numeric: true),
            DataColumn(label: Text('Daten'), numeric: true),
          ], rows: [
            for (final geb in store.gebaeude())
              for (final g in store.geschosse(geb.id))
                for (final r in store.raeume(g.id))
                  if (r.umriss != null && r.art == RaumArt.raum)
                    () {
                      final soll = ausstattungSoll(r.name, polygonFlaeche(r.umriss!).abs() / 1e6, wert);
                      final objekte = [for (final o in store.objekte(g.id)) if (o.raumId == r.id || (o.punkte.isNotEmpty && punktInPolygon(o.punkte.first, r.umriss!))) o];
                      final ist = ausstattungIst(objekte, typen);
                      DataCell zelle(int i, int sl) => DataCell(Text('$i / $sl', style: TextStyle(color: i >= sl ? _gruen : _orange, fontWeight: FontWeight.w600)));
                      return DataRow(cells: [
                        DataCell(Text('${g.kuerzel} ${r.name}')),
                        zelle(ist.sd, soll.sd),
                        zelle(ist.licht, soll.licht),
                        zelle(ist.daten, soll.daten),
                      ]);
                    }(),
          ]),
        ),
      ),
      const Text('Ist / Soll. Mehrfachsteckdosen zählen je Einsatz (Feld „Fach“). Wert 1 = Mindest, 2 = Standard, 3 = Komfort (RAL-RG 678).',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
    ]);
  }
}
