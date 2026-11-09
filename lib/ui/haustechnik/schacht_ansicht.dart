import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/technik.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Farbe je Zone im Querschnitt.
Color zonenFarbe(String zone) => switch (zone) {
      'Abwasser' => const Color(0xFF868E96),
      'Wasser' => const Color(0xFF1C7ED6),
      'Heizung' => const Color(0xFFE03131),
      'Lüftung' => const Color(0xFF0C8599),
      'Elektro' => const Color(0xFFE6A700),
      'Daten' => const Color(0xFF7048E8),
      _ => const Color(0xFF495057),
    };

/// Schacht- und Trassenplaner: Belegung, Querschnitt, Füllgrad, Steigschema.
class SchachtAnsicht extends StatefulWidget {
  const SchachtAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<SchachtAnsicht> createState() => _SchachtAnsichtState();
}

class _SchachtAnsichtState extends State<SchachtAnsicht> {
  String? _auswahl;
  final List<VoidCallback> _rueckgaengig = [];
  AppState get _s => widget.state;

  List<Schacht> _schaechte() => [
        for (final m in (_s.store!.einstellung<List>('schaechte') ?? const [])) Schacht.ausJson(Map<String, dynamic>.from(m as Map)),
      ];

  void _speichern(List<Schacht> neu) {
    final store = _s.store!;
    final alt = store.einstellung<List>('schaechte');
    store.einstellungSetzen('schaechte', [for (final s in neu) s.toJson()]);
    _rueckgaengig.add(() => store.einstellungSetzen('schaechte', alt));
    _s.geaendert();
  }

  void _aendern(Schacht s) => _speichern([for (final x in _schaechte()) x.id == s.id ? s : x]);

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final liste = _schaechte();
    final s = liste.where((x) => x.id == _auswahl).firstOrNull ?? liste.firstOrNull;
    final geschosse = [for (final geb in store.gebaeude()) ...store.geschosse(geb.id)];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (_rueckgaengig.isEmpty) return;
          _rueckgaengig.removeLast()();
          _s.geaendert();
        },
      },
      child: Focus(
        autofocus: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 240,
            child: Material(
              color: Colors.white,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                Text('Schächte und Trassen', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final x in liste)
                  ListTile(
                    dense: true,
                    selected: x.id == s?.id,
                    title: Text(x.name),
                    subtitle: Text('${x.art} · ${(fuellgrad(x) * 100).round()} %'),
                    onTap: () => setState(() => _auswahl = x.id),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    final neu = Schacht(
                      id: '${DateTime.now().microsecondsSinceEpoch}',
                      name: 'Schacht ${liste.length + 1}',
                      geschosse: [for (final g in geschosse) g.id],
                    );
                    _speichern([...liste, neu]);
                    setState(() => _auswahl = neu.id);
                  },
                  icon: const Icon(Sym.hinzufuegen),
                  label: const Text('Schacht / Trasse'),
                ),
              ]),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: s == null ? const Center(child: Text('Noch kein Schacht und keine Trasse angelegt.')) : _editor(s, liste, geschosse)),
        ]),
      ),
    );
  }

  Widget _editor(Schacht s, List<Schacht> liste, List<Geschoss> geschosse) {
    final store = _s.store!;
    final f = fuellgrad(s);
    final hinweise = schachtHinweise(s);
    final hoehen = {for (final g in geschosse) g.id: g.hoehen.rohdecke - g.hoehen.rfb + 250};
    final schachtGeschosse = [for (final g in geschosse) if (s.geschosse.contains(g.id)) g.id];
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final leitungen = [for (final o in store.alleObjekte()) if (typen[o.typId]?.geometrie == Geometrieart.linie) o];
    final gewerkKuerzel = {for (final g in store.gewerke()) g.id: g.kuerzel};
    String zoneFuer(Objekt o) => switch (gewerkKuerzel[typen[o.typId]?.gewerkId]) {
          'SA' => typen[o.typId]?.kuerzel == 'AW' ? 'Abwasser' : 'Wasser',
          'HZ' || 'FH' => 'Heizung',
          'LU' || 'KL' => 'Lüftung',
          'NW' || 'KX' => 'Daten',
          _ => 'Elektro',
        };
    void leitungAendern(SchachtLeitung l, SchachtLeitung neu) => _aendern(s.mit(leitungen: [for (final x in s.leitungen) x.id == l.id ? neu : x]));

    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 220,
          child: SpeicherFeld(
            key: ValueKey('sn-${s.id}-${s.name}'),
            initialValue: s.name,
            style: Theme.of(context).textTheme.titleLarge,
            onFieldSubmitted: (v) => _aendern(s.mit(name: v.trim())),
          ),
        ),
        DropdownButton<String>(
          value: s.art,
          items: [for (final a in schachtArten) DropdownMenuItem(value: a, child: Text(a))],
          onChanged: (v) => _aendern(s.mit(art: v)),
        ),
        for (final (label, wert, setzen) in [
          ('Breite innen', s.breite, (int v) => s.mit(breite: v)),
          ('Tiefe innen', s.tiefe, (int v) => s.mit(tiefe: v)),
        ])
          SizedBox(
            width: 120,
            child: SpeicherFeld(
              key: ValueKey('$label-${s.id}-$wert'),
              initialValue: '$wert',
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: label, suffixText: 'mm'),
              onFieldSubmitted: (v) => _aendern(setzen(int.tryParse(v) ?? wert)),
            ),
          ),
        FilterChip(label: const Text('Trennsteg Strom/Daten'), selected: s.trennsteg, onSelected: (v) => _aendern(s.mit(trennsteg: v))),
        TextButton.icon(
          onPressed: () {
            _speichern([for (final x in liste) if (x.id != s.id) x]);
            setState(() => _auswahl = null);
          },
          icon: const Icon(Sym.loeschen, size: 18),
          label: const Text('löschen'),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        const Text('Geschosse: '),
        for (final g in geschosse)
          FilterChip(
            label: Text(g.kuerzel),
            selected: s.geschosse.contains(g.id),
            onSelected: (v) => _aendern(s.mit(geschosse: v ? [...s.geschosse, g.id] : [for (final x in s.geschosse) if (x != g.id) x])),
          ),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Querschnitt
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Querschnitt', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(border: Border.all(color: BsFarben.rand)),
            child: CustomPaint(size: const Size(360, 280), painter: _QuerschnittPainter(s)),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 360,
            child: LinearProgressIndicator(
              value: f.clamp(0, 1),
              minHeight: 8,
              color: f > s.maxFuellgrad ? const Color(0xFFB91C1C) : null,
            ),
          ),
          Text('Füllgrad ${(f * 100).round()} % (zulässig ${(s.maxFuellgrad * 100).round()} %) · Reserve ${(math.max(0, s.maxFuellgrad - f) * 100).round()} %'),
        ]),
        const SizedBox(width: 24),
        // Hinweise und Steigschema
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hinweise', style: Theme.of(context).textTheme.titleSmall),
            if (hinweise.isEmpty) const Text('Keine Auffälligkeiten.', style: TextStyle(color: BsFarben.textLeise)),
            for (final h in hinweise) Text('• $h', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
            const SizedBox(height: 16),
            Text('Steigschema', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            if (schachtGeschosse.isEmpty || s.leitungen.isEmpty)
              const Text('Geschosse wählen und Leitungen eintragen.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 30,
                  dataRowMinHeight: 26,
                  dataRowMaxHeight: 30,
                  columnSpacing: 14,
                  columns: [
                    const DataColumn(label: Text('Geschoss')),
                    for (final l in s.leitungen) DataColumn(label: Text(l.bezeichnung, style: TextStyle(fontSize: 11, color: zonenFarbe(l.zone)))),
                  ],
                  rows: [
                    for (final gid in schachtGeschosse.reversed)
                      DataRow(cells: [
                        DataCell(Text(geschosse.firstWhere((g) => g.id == gid).kuerzel)),
                        for (final l in s.leitungen)
                          DataCell(Text(() {
                            final i = schachtGeschosse.indexOf(gid);
                            final a = l.vonGeschoss == null ? 0 : schachtGeschosse.indexOf(l.vonGeschoss!);
                            final b = l.bisGeschoss == null ? schachtGeschosse.length - 1 : schachtGeschosse.indexOf(l.bisGeschoss!);
                            final (lo, hi) = a <= b ? (a, b) : (b, a);
                            if (i == lo && i == hi) return '●';
                            if (i == lo) return '↑ ein';
                            if (i == hi) return '→ aus';
                            if (i > lo && i < hi) return '│';
                            return '';
                          }(), style: TextStyle(color: zonenFarbe(l.zone)))),
                      ]),
                  ],
                ),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Text('Belegung', style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: 'Leitung aus Vorlage',
          onSelected: (k) {
            final (zone, d, dae) = leitungsVorlagen[k]!;
            _aendern(s.mit(leitungen: [
              ...s.leitungen,
              SchachtLeitung(id: '${DateTime.now().microsecondsSinceEpoch}', bezeichnung: k, zone: zone, durchmesser: d, daemmung: dae),
            ]));
          },
          itemBuilder: (_) => [for (final k in leitungsVorlagen.keys) PopupMenuItem(value: k, child: Text(k))],
          child: const Padding(padding: EdgeInsets.all(8), child: Text('+ aus Vorlage')),
        ),
        PopupMenuButton<String>(
          tooltip: 'Leitung aus dem Grundriss',
          enabled: leitungen.isNotEmpty,
          onSelected: (id) {
            final o = leitungen.firstWhere((x) => x.id == id);
            _aendern(s.mit(leitungen: [
              ...s.leitungen,
              SchachtLeitung(
                id: '${DateTime.now().microsecondsSinceEpoch}',
                bezeichnung: '${o.kennung} ${typen[o.typId]?.name ?? ''}'.trim(),
                zone: zoneFuer(o),
                durchmesser: 16,
                objektId: o.id,
              ),
            ]));
          },
          itemBuilder: (_) => [for (final o in leitungen) PopupMenuItem(value: o.id, child: Text('${o.kennung} · ${typen[o.typId]?.name ?? ''}'))],
          child: const Padding(padding: EdgeInsets.all(8), child: Text('+ aus Grundriss')),
        ),
      ]),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columnSpacing: 14, columns: const [
            DataColumn(label: Text('Leitung')),
            DataColumn(label: Text('Zone')),
            DataColumn(label: Text('Ø außen'), numeric: true),
            DataColumn(label: Text('Dämmung'), numeric: true),
            DataColumn(label: Text('ein')),
            DataColumn(label: Text('aus')),
            DataColumn(label: Text('Länge'), numeric: true),
            DataColumn(label: Text('')),
          ], rows: [
            for (final l in s.leitungen)
              DataRow(cells: [
                DataCell(SizedBox(
                  width: 180,
                  child: SpeicherFeld(
                    key: ValueKey('lb-${l.id}-${l.bezeichnung}'),
                    initialValue: l.bezeichnung,
                    onFieldSubmitted: (v) => leitungAendern(
                        l,
                        SchachtLeitung(
                            id: l.id, bezeichnung: v.trim(), zone: l.zone, durchmesser: l.durchmesser, daemmung: l.daemmung, vonGeschoss: l.vonGeschoss, bisGeschoss: l.bisGeschoss, objektId: l.objektId)),
                  ),
                )),
                DataCell(DropdownButton<String>(
                  value: l.zone,
                  underline: const SizedBox.shrink(),
                  items: [for (final z in schachtZonen) DropdownMenuItem(value: z, child: Text(z, style: TextStyle(color: zonenFarbe(z))))],
                  onChanged: (v) => leitungAendern(
                      l,
                      SchachtLeitung(
                          id: l.id, bezeichnung: l.bezeichnung, zone: v ?? l.zone, durchmesser: l.durchmesser, daemmung: l.daemmung, vonGeschoss: l.vonGeschoss, bisGeschoss: l.bisGeschoss, objektId: l.objektId)),
                )),
                for (final (wert, istD) in [(l.durchmesser, true), (l.daemmung, false)])
                  DataCell(SizedBox(
                    width: 56,
                    child: SpeicherFeld(
                      key: ValueKey('ld-${l.id}-$istD-$wert'),
                      initialValue: wert == wert.roundToDouble() ? '${wert.round()}' : '$wert',
                      textAlign: TextAlign.right,
                      onFieldSubmitted: (v) {
                        final x = double.tryParse(v.replaceAll(',', '.')) ?? wert;
                        leitungAendern(
                            l,
                            SchachtLeitung(
                                id: l.id,
                                bezeichnung: l.bezeichnung,
                                zone: l.zone,
                                durchmesser: istD ? x : l.durchmesser,
                                daemmung: istD ? l.daemmung : x,
                                vonGeschoss: l.vonGeschoss,
                                bisGeschoss: l.bisGeschoss,
                                objektId: l.objektId));
                      },
                    ),
                  )),
                for (final istVon in [true, false])
                  DataCell(DropdownButton<String?>(
                    value: schachtGeschosse.contains(istVon ? l.vonGeschoss : l.bisGeschoss) ? (istVon ? l.vonGeschoss : l.bisGeschoss) : null,
                    underline: const SizedBox.shrink(),
                    hint: Text(istVon ? 'unten' : 'oben'),
                    items: [
                      DropdownMenuItem(value: null, child: Text(istVon ? 'unten' : 'oben')),
                      for (final gid in schachtGeschosse) DropdownMenuItem(value: gid, child: Text(geschosse.firstWhere((g) => g.id == gid).kuerzel)),
                    ],
                    onChanged: (v) => leitungAendern(
                        l,
                        SchachtLeitung(
                            id: l.id,
                            bezeichnung: l.bezeichnung,
                            zone: l.zone,
                            durchmesser: l.durchmesser,
                            daemmung: l.daemmung,
                            vonGeschoss: istVon ? v : l.vonGeschoss,
                            bisGeschoss: istVon ? l.bisGeschoss : v,
                            objektId: l.objektId)),
                  )),
                DataCell(Text(meterText(laengeImSchacht(l, schachtGeschosse, hoehen)))),
                DataCell(IconButton(
                  icon: const Icon(Sym.loeschen, size: 18),
                  onPressed: () => _aendern(s.mit(leitungen: [for (final x in s.leitungen) if (x.id != l.id) x])),
                )),
              ]),
          ]),
        ),
      ),
      if (s.leitungen.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              final ids = [
                for (final l in s.leitungen)
                  if (laengeImSchacht(l, schachtGeschosse, hoehen) > 0)
                    store.kostenpositionAnlegen(
                      text: '${l.bezeichnung} im ${s.name}',
                      mengeMilli: laengeImSchacht(l, schachtGeschosse, hoehen).round(),
                      einheit: 'm',
                    ),
              ];
              _rueckgaengig.add(() {
                for (final id in ids) {
                  store.kostenpositionLoeschen(id);
                }
              });
              _s.geaendert();
              zeigeHinweis(context, '${ids.length} Positionen (Länge im Schacht) in die Kostenliste übernommen.');
            },
            icon: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Längen im Schacht in die Kostenliste'),
          ),
        ),
    ]);
  }
}

class _QuerschnittPainter extends CustomPainter {
  _QuerschnittPainter(this.s);
  final Schacht s;

  @override
  void paint(Canvas canvas, Size size) {
    final m = math.min((size.width - 20) / math.max(1, s.breite), (size.height - 20) / math.max(1, s.tiefe));
    final o = Offset((size.width - s.breite * m) / 2, (size.height + s.tiefe * m) / 2); // linke untere Innenecke
    final innen = Rect.fromLTWH(o.dx, o.dy - s.tiefe * m, s.breite * m, s.tiefe * m);
    canvas.drawRect(innen, Paint()..color = const Color(0xFFF8F9FA));
    canvas.drawRect(innen.inflate(4), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = const Color(0xFFCED4DA));
    final q = querschnitt(s);
    for (final (l, x, y) in q.lagen) {
      final c = Offset(o.dx + x * m, o.dy - y * m);
      final farbe = zonenFarbe(l.zone);
      if (l.daemmung > 0) canvas.drawCircle(c, l.aussen / 2 * m, Paint()..color = farbe.withValues(alpha: 0.18));
      canvas.drawCircle(c, l.durchmesser / 2 * m, Paint()..color = farbe.withValues(alpha: 0.75));
    }
    if (s.trennsteg) {
      // Trennsteg zwischen Elektro und Daten (Höhe der ersten Datenleitung)
      final daten = q.lagen.where((e) => e.$1.zone == 'Daten').toList();
      if (daten.isNotEmpty) {
        final y = daten.map((e) => e.$3 - e.$1.aussen / 2).reduce(math.min);
        canvas.drawLine(Offset(innen.left, o.dy - y * m), Offset(innen.right, o.dy - y * m), Paint()
          ..color = Colors.black54
          ..strokeWidth = 2);
      }
    }
    final tp = TextPainter(
      text: TextSpan(text: '${s.breite} × ${s.tiefe} mm', style: const TextStyle(fontSize: 10, color: BsFarben.textLeise)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(innen.left, innen.top - 16));
  }

  @override
  bool shouldRepaint(covariant _QuerschnittPainter old) => true;
}
