import 'package:flutter/material.dart';

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import 'auswertung_page.dart';

/// Modul Kosten: Kostenliste (manuell und „aus Plan“) und Produktkatalog.
class KostenPage extends StatefulWidget {
  const KostenPage({super.key, required this.state});
  final AppState state;

  @override
  State<KostenPage> createState() => _KostenPageState();
}

class _KostenPageState extends State<KostenPage> {
  int _ansicht = 0; // 0 Kostenliste, 1 Produkte, 2 Plan/Ist, 3 Einkaufsliste
  KostenStatus? _filterStatus;
  String? _filterGewerk;
  bool _nachgefuehrt = false;

  AppState get _s => widget.state;

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    if (!_nachgefuehrt) {
      // Mengen aus dem Plan beim Öffnen aktualisieren
      _nachgefuehrt = true;
      store.planMengenNachfuehren();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.receipt_long_outlined, size: 18), label: Text('Kostenliste')),
              ButtonSegment(value: 1, icon: Icon(Icons.inventory_2_outlined, size: 18), label: Text('Produkte')),
              ButtonSegment(value: 2, icon: Icon(Icons.stacked_bar_chart, size: 18), label: Text('Plan/Ist')),
              ButtonSegment(value: 3, icon: Icon(Icons.shopping_cart_outlined, size: 18), label: Text('Einkaufsliste')),
            ],
            selected: {_ansicht},
            onSelectionChanged: (s) => setState(() => _ansicht = s.first),
          ),
          if (_ansicht == 0) ...[
            FilledButton.icon(onPressed: _positionNeu, icon: const Icon(Sym.hinzufuegen), label: const Text('Position')),
            OutlinedButton.icon(
              onPressed: () {
                final n = store.planMengenNachfuehren();
                _s.geaendert();
                zeigeHinweis(context, '$n Positionen aus dem Plan aktualisiert.');
              },
              icon: const Icon(Sym.aktualisieren, size: 18),
              label: const Text('Mengen aus Plan'),
            ),
          ] else if (_ansicht == 1)
            FilledButton.icon(onPressed: _produktNeu, icon: const Icon(Sym.hinzufuegen), label: const Text('Produkt')),
        ]),
      ),
      Expanded(
        child: switch (_ansicht) {
          0 => _liste(),
          1 => _produkte(),
          2 => PlanIstAnsicht(state: _s),
          _ => EinkaufAnsicht(state: _s),
        },
      ),
    ]);
  }

  // ------------------------------------------------------- Kostenliste

  Widget _liste() {
    final store = _s.store!;
    final gewerke = {for (final g in store.gewerke()) g.id: g};
    final alle = store.kostenpositionen();
    final pos = alle
        .where((p) => (_filterStatus == null || p.status == _filterStatus) && (_filterGewerk == null || p.gewerkId == _filterGewerk))
        .toList();
    final netto = pos.fold<int>(0, (s, p) => s + p.nettoCent);
    final steuer = pos.fold<int>(0, (s, p) => s + p.steuerCent);
    final jeGewerk = <String?, int>{};
    for (final p in pos) {
      jeGewerk[p.gewerkId] = (jeGewerk[p.gewerkId] ?? 0) + p.bruttoCent;
    }
    final bezahlt = alle.where((p) => p.status == KostenStatus.bezahlt).fold<int>(0, (s, p) => s + p.bruttoCent);

    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 12, children: [
            DropdownButton<KostenStatus?>(
              value: _filterStatus,
              hint: const Text('alle Status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('alle Status')),
                for (final s in KostenStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _filterStatus = v),
            ),
            DropdownButton<String?>(
              value: _filterGewerk,
              hint: const Text('alle Gewerke'),
              items: [
                const DropdownMenuItem(value: null, child: Text('alle Gewerke')),
                for (final g in gewerke.values) DropdownMenuItem(value: g.id, child: Text(g.name)),
              ],
              onChanged: (v) => setState(() => _filterGewerk = v),
            ),
          ]),
          const SizedBox(height: 8),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columnSpacing: 18,
                columns: const [
                  DataColumn(label: Text('Position')),
                  DataColumn(label: Text('Gewerk')),
                  DataColumn(label: Text('Menge'), numeric: true),
                  DataColumn(label: Text('EP netto'), numeric: true),
                  DataColumn(label: Text('MwSt.'), numeric: true),
                  DataColumn(label: Text('Gesamt brutto'), numeric: true),
                  DataColumn(label: Text('Status')),
                ],
                rows: [
                  for (final p in pos)
                    DataRow(
                      onSelectChanged: (_) => _positionBearbeiten(p),
                      cells: [
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          if (p.ausPlan)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Tooltip(message: 'Menge aus dem Plan', child: Icon(Icons.auto_graph, size: 16, color: BsFarben.akzent)),
                            ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Text(p.text, overflow: TextOverflow.ellipsis),
                          ),
                        ])),
                        DataCell(Text(gewerke[p.gewerkId]?.kuerzel ?? '–')),
                        DataCell(Text('${mengeText(p.mengeMilli)} ${p.einheit}')),
                        DataCell(Text(euroText(p.einzelCent))),
                        DataCell(Text('${(p.steuer / 100).toStringAsFixed(0)} %')),
                        DataCell(Text(euroText(p.bruttoCent), style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(p.status.label)),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (pos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Noch keine Positionen. Objekte im Modul Installation erscheinen hier automatisch mit ihrer Menge; '
                  'Preise kommen aus dem Produkt oder werden per Klick auf die Zeile eingetragen.'),
            ),
        ]),
      ),
      Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: BsFarben.rand))),
        child: ListView(children: [
          Text('Summe', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _zeile('netto', euroText(netto)),
          _zeile('MwSt.', euroText(steuer)),
          _zeile('brutto', euroText(netto + steuer), fett: true),
          const Divider(height: 24),
          _zeile('davon bezahlt', euroText(bezahlt)),
          const Divider(height: 24),
          Text('je Gewerk (brutto)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final e in jeGewerk.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            _zeile(gewerke[e.key]?.name ?? 'ohne Gewerk', euroText(e.value),
                farbe: e.key == null ? null : Color(gewerke[e.key]?.farbe ?? 0xFF888888)),
        ]),
      ),
    ]);
  }

  Widget _zeile(String a, String b, {bool fett = false, Color? farbe}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          if (farbe != null) Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8), color: farbe),
          Expanded(child: Text(a, style: const TextStyle(color: BsFarben.textLeise))),
          Text(b, style: TextStyle(fontWeight: fett ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );

  Future<void> _positionNeu() async {
    final id = _s.store!.kostenpositionAnlegen(text: 'Neue Position');
    _s.geaendert();
    final p = _s.store!.kostenpositionen().firstWhere((e) => e.id == id);
    await _positionBearbeiten(p);
  }

  Future<void> _positionBearbeiten(Kostenposition p) async {
    final store = _s.store!;
    final text = TextEditingController(text: p.text);
    final menge = TextEditingController(text: mengeText(p.mengeMilli));
    final einheit = TextEditingController(text: p.einheit);
    final preis = TextEditingController(text: (p.einzelCent / 100).toStringAsFixed(2).replaceAll('.', ','));
    var steuer = p.steuer;
    var status = p.status;
    var art = p.kostenart;
    var gewerk = p.gewerkId;
    final gewerke = store.gewerke();
    final ergebnis = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(p.ausPlan ? 'Position aus dem Plan' : 'Kostenposition'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: text, decoration: const InputDecoration(labelText: 'Text'), enabled: !p.ausPlan),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: menge,
                    enabled: !p.ausPlan,
                    decoration: InputDecoration(labelText: 'Menge', helperText: p.ausPlan ? 'kommt aus dem Plan' : null),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 90, child: TextField(controller: einheit, enabled: !p.ausPlan, decoration: const InputDecoration(labelText: 'Einheit'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: preis, decoration: const InputDecoration(labelText: 'Einzelpreis netto', suffixText: '€'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: const [1900, 700, 0].contains(steuer) ? steuer : 1900,
                    decoration: const InputDecoration(labelText: 'MwSt.'),
                    items: const [
                      DropdownMenuItem(value: 1900, child: Text('19 %')),
                      DropdownMenuItem(value: 700, child: Text('7 %')),
                      DropdownMenuItem(value: 0, child: Text('0 %')),
                    ],
                    onChanged: (v) => setD(() => steuer = v ?? steuer),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<KostenStatus>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [for (final s in KostenStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                    onChanged: (v) => setD(() => status = v ?? status),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: kostenarten.contains(art) ? art : kostenarten.first,
                    decoration: const InputDecoration(labelText: 'Kostenart'),
                    items: [for (final a in kostenarten) DropdownMenuItem(value: a, child: Text(a))],
                    onChanged: (v) => setD(() => art = v ?? art),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: gewerk,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Gewerk'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('–')),
                      for (final g in gewerke) DropdownMenuItem(value: g.id, child: Text(g.name)),
                    ],
                    onChanged: p.ausPlan ? null : (v) => setD(() => gewerk = v),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            if (!p.ausPlan) TextButton(onPressed: () => Navigator.pop(c, 'loeschen'), child: const Text('Löschen')),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, 'ok'), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (ergebnis == 'loeschen') {
      store.kostenpositionLoeschen(p.id);
    } else if (ergebnis == 'ok') {
      store.kostenpositionAendern(p.id, {
        'text': text.text.trim().isEmpty ? p.text : text.text.trim(),
        if (!p.ausPlan) 'menge_milli': dezimalLesen(menge.text, 1000) ?? p.mengeMilli,
        'einheit': einheit.text.trim().isEmpty ? p.einheit : einheit.text.trim(),
        'einzel_cent': dezimalLesen(preis.text, 100) ?? p.einzelCent,
        'steuer': steuer,
        'status': status.name,
        'kostenart': art,
        'gewerk_id': gewerk,
      });
    } else {
      return;
    }
    _s.geaendert();
  }

  // ------------------------------------------------------------ Produkte

  Widget _produkte() {
    final store = _s.store!;
    final liste = store.produkte();
    if (liste.isEmpty) {
      return const Center(
        child: Text('Noch keine Produkte. „Produkt“ legt einen Katalogeintrag an; im Modul Installation '
            'wählst du ihn am Objekt, dann kommt der Preis automatisch in die Kostenliste.'),
      );
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final p in liste)
        Card(
          child: ExpansionTile(
            title: Text(p.name + (p.platzhalter ? '  (Platzhalter)' : '')),
            subtitle: Text([
              if (p.hersteller != null) p.hersteller!,
              if (p.artikelnummer != null) 'Art.-Nr. ${p.artikelnummer}',
              p.bestesAngebot == null ? 'kein Preis' : 'ab ${euroText(p.bestesAngebot!.preisCent)} netto / ${p.einheit}',
            ].join(' · ')),
            children: [
              for (final a in p.angebote)
                ListTile(
                  dense: true,
                  title: Text('${a.haendler} · ${euroText(a.preisCent)} netto (${a.steuer ~/ 100} %)'),
                  subtitle: Text([if (a.datum != null) 'Stand ${a.datum}', if (a.link != null) a.link!].join(' · ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () {
                      store.angebotLoeschen(a.id);
                      _s.geaendert();
                    },
                  ),
                ),
              OverflowBar(alignment: MainAxisAlignment.end, children: [
                TextButton.icon(onPressed: () => _angebotNeu(p), icon: const Icon(Icons.add, size: 18), label: const Text('Händlerpreis')),
                TextButton(onPressed: () => _produktBearbeiten(p), child: const Text('Bearbeiten')),
                TextButton(
                  onPressed: () {
                    store.produktLoeschen(p.id);
                    _s.geaendert();
                  },
                  child: const Text('Löschen'),
                ),
              ]),
            ],
          ),
        ),
    ]);
  }

  Future<void> _produktNeu() async {
    final name = await texteingabe(context, titel: 'Neues Produkt', feld: 'Name', vorschlag: 'Steckdose Gira E2 reinweiß');
    if (name == null || name.trim().isEmpty) return;
    _s.store!.produktAnlegen(name: name.trim());
    _s.geaendert();
  }

  Future<void> _produktBearbeiten(Produkt p) async {
    final felder = {
      'name': TextEditingController(text: p.name),
      'hersteller': TextEditingController(text: p.hersteller ?? ''),
      'artikelnummer': TextEditingController(text: p.artikelnummer ?? ''),
      'ean': TextEditingController(text: p.ean ?? ''),
      'einheit': TextEditingController(text: p.einheit),
    };
    var platzhalter = p.platzhalter;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Produkt'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final e in felder.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(controller: e.value, decoration: InputDecoration(labelText: switch (e.key) {
                    'name' => 'Name',
                    'hersteller' => 'Hersteller',
                    'artikelnummer' => 'Artikelnummer',
                    'ean' => 'EAN',
                    _ => 'Einheit',
                  })),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: platzhalter,
                title: const Text('Platzhalter (Produkt noch nicht entschieden)'),
                onChanged: (v) => setD(() => platzhalter = v ?? false),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    _s.store!.produktAendern(p.id, {
      for (final e in felder.entries) e.key: e.value.text.trim().isEmpty ? (e.key == 'name' ? p.name : (e.key == 'einheit' ? 'Stk' : null)) : e.value.text.trim(),
      'platzhalter': platzhalter ? 1 : 0,
    });
    _s.geaendert();
  }

  Future<void> _angebotNeu(Produkt p) async {
    final haendler = TextEditingController();
    final preis = TextEditingController();
    final link = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Händlerpreis · ${p.name}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: haendler, autofocus: true, decoration: const InputDecoration(labelText: 'Händler')),
            const SizedBox(height: 10),
            TextField(controller: preis, decoration: InputDecoration(labelText: 'Preis netto je ${p.einheit}', suffixText: '€')),
            const SizedBox(height: 10),
            TextField(controller: link, decoration: const InputDecoration(labelText: 'Link (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
        ],
      ),
    );
    final cent = dezimalLesen(preis.text, 100);
    if (ok != true || haendler.text.trim().isEmpty || cent == null) return;
    _s.store!.angebotAnlegen(
        produktId: p.id, haendler: haendler.text.trim(), preisCent: cent, link: link.text.trim().isEmpty ? null : link.text.trim());
    _s.geaendert();
  }
}
