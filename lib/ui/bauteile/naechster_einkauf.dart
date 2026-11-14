import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/auslegung.dart';
import '../../core/auslegung_projekt.dart';
import '../../data/project_store.dart';
import '../../data/tagebuch_models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import 'einkauf_dialog.dart';

/// Werkzeugliste (Projekteinstellung `werkzeug`): Name und Gewerke.
List<({String name, List<String> gewerke})> werkzeugLesen(ProjectStore store) => [
      for (final m in (store.einstellung<List>('werkzeug') ?? const []))
        if (m is Map) (name: '${m['name']}', gewerke: [for (final g in (m['gewerke'] as List? ?? const [])) '$g']),
    ];

/// Übliches Werkzeug je Gewerk-Kürzel (Startvorschlag).
const werkzeugVorschlag = <String, List<String>>{
  'EL': ['Spannungsprüfer', 'Abisolierzange', 'Seitenschneider', 'Dosenbohrer 68 mm', 'Schlitzfräse', 'Kabeleinziehband', 'Wago-Klemmen'],
  'SA': ['Pressmaschine + Backen', 'Rohrschneider', 'Entgrater', 'Wasserwaage', 'Kernbohrgerät'],
  'HZ': ['Pressmaschine + Backen', 'Rohrschneider', 'Druckprüfpumpe', 'Spülschlauch'],
  'FH': ['Tackerwerkzeug', 'Abroller für Heizrohr', 'Druckprüfpumpe', 'Randdämmstreifen-Messer'],
  'NW': ['LSA-Auflegewerkzeug', 'Netzwerktester', 'Abmantler'],
  'KX': ['KNX-Programmiergerät', 'Busleitungs-Abmantler'],
  'AL': ['Akkuschrauber', 'Bohrhammer', 'Zollstock', 'Laser / Linienlaser', 'Staubsauger'],
};

/// Nächster Einkauf: was laut Plan fehlt (Bibliothek + Kabel-/Rohrliste),
/// was noch da ist („nicht kaufen“), Werkzeug zum Mitnehmen; Abhaken erhöht
/// den Bestand. Einkaufszettel als HTML fürs Handy.
Future<void> naechsterEinkauf(BuildContext context, AppState s) => showDialog<void>(context: context, builder: (_) => _NaechsterEinkauf(state: s));

class _NaechsterEinkauf extends StatefulWidget {
  const _NaechsterEinkauf({required this.state});
  final AppState state;
  @override
  State<_NaechsterEinkauf> createState() => _NaechsterEinkaufState();
}

class _NaechsterEinkaufState extends State<_NaechsterEinkauf> {
  final _neu = TextEditingController();
  AppState get _s => widget.state;
  String _z(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final liste = besorgungsliste(_s);
    final fehlt = [for (final r in liste) if (r.bedarf > r.bestand) r];
    final uebrig = [for (final r in liste) if (r.bestand > r.bedarf + 1e-9) r];
    final v = auslegungVorgaben(store);
    final gekauft = leitungGekauft(store);
    final leitungen = [
      for (final l in leitungsliste(leitungsStuecke(store, name: (id) => _s.bibliothek.fuerProjekt(store, id)?.anzeige)))
        if (l.einkauf(v.zuschlag) > (gekauft[leitungSchluessel(l)] ?? 0)) l,
    ];
    final plan = {for (final e in (store.einstellung<List>('einkauf_plan') ?? const [])) '$e'};
    void planSetzen(String k, bool an) {
      final n = {...plan};
      an ? n.add(k) : n.remove(k);
      store.einstellungSetzen('einkauf_plan', n.toList());
      setState(() {});
    }

    // Werkzeug passend zu offenen Aufgaben (Gewerke)
    final gewerke = {for (final g in store.gewerke()) g.id: g.kuerzel};
    final offeneGewerke = {
      for (final a in store.aufgaben())
        if (a.status != AufgabenStatus.erledigt && a.gewerkId != null) gewerke[a.gewerkId] ?? '',
    }..add('AL');
    final werkzeug = werkzeugLesen(store);
    final mitnehmen = {for (final e in (store.einstellung<List>('werkzeug_dabei') ?? const [])) '$e'};

    Widget zeile(String k, String text, String menge, String woher, VoidCallback gekauftAktion) => CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: plan.contains(k),
          onChanged: (b) => planSetzen(k, b == true),
          title: Text(text),
          subtitle: Text(woher, style: const TextStyle(fontSize: 11)),
          secondary: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(menge, style: const TextStyle(fontWeight: FontWeight.w600)),
            IconButton(tooltip: 'gekauft – in den Bestand', onPressed: gekauftAktion, icon: const Icon(Icons.shopping_bag_outlined, size: 18)),
          ]),
        );

    return AlertDialog(
      title: const Text('Nächster Einkauf'),
      content: SizedBox(
        width: 760,
        height: 580,
        child: ListView(children: [
          const Text('Anhaken = für den nächsten Einkauf vormerken. Tasche = gekauft (Bestand steigt, Zeile verschwindet).',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          const SizedBox(height: 6),
          Text('Noch zu beschaffen (${fehlt.length + leitungen.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final r in fehlt)
            zeile('e:${r.element.id}', r.element.anzeige, '${_z(r.bedarf - r.bestand)} ${r.einheit}', '${elementHaendler(r.element)} · ${r.herkunft}', () {
              bestandSetzen(store, r.element.id, r.bedarf);
              planSetzen('e:${r.element.id}', false);
              _s.geaendert();
            }),
          for (final l in leitungen)
            zeile('l:${leitungSchluessel(l)}', l.bezeichnung, '${l.einkauf(v.zuschlag).round()} m', '${l.art} · Kabel-/Rohrliste${l.geschaetzt > 0 ? ' (teils geschätzt)' : ''}', () {
              leitungGekauftSetzen(store, leitungSchluessel(l), l.einkauf(v.zuschlag));
              planSetzen('l:${leitungSchluessel(l)}', false);
              _s.geaendert();
            }),
          if (uebrig.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Noch da – nicht kaufen (${uebrig.length})', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2F9E44))),
            for (final r in uebrig)
              ListTile(
                dense: true,
                leading: const Icon(Icons.inventory_2_outlined, size: 18, color: Color(0xFF2F9E44)),
                title: Text(r.element.anzeige),
                trailing: Text('${_z(r.bestand - r.bedarf)} ${r.einheit} übrig'),
              ),
          ],
          const Divider(height: 24),
          Row(children: [
            const Expanded(child: Text('Werkzeug mitnehmen', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton(
              onPressed: () {
                final l = [
                  ...werkzeug.map((w) => {'name': w.name, 'gewerke': w.gewerke}),
                  for (final e in werkzeugVorschlag.entries)
                    for (final n in e.value)
                      if (!werkzeug.any((w) => w.name == n)) {'name': n, 'gewerke': [e.key]},
                ];
                store.einstellungSetzen('werkzeug', l);
                setState(() {});
              },
              child: const Text('Vorschläge ergänzen'),
            ),
          ]),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final w in werkzeug)
              FilterChip(
                label: Text(w.name),
                selected: mitnehmen.contains(w.name),
                avatar: w.gewerke.any(offeneGewerke.contains) ? const Icon(Icons.star, size: 14) : null,
                onSelected: (b) {
                  final n = {...mitnehmen};
                  b ? n.add(w.name) : n.remove(w.name);
                  store.einstellungSetzen('werkzeug_dabei', n.toList());
                  setState(() {});
                },
              ),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: _neu, decoration: const InputDecoration(hintText: 'Werkzeug hinzufügen', isDense: true))),
            IconButton(
              onPressed: () {
                if (_neu.text.trim().isEmpty) return;
                store.einstellungSetzen('werkzeug', [...werkzeug.map((w) => {'name': w.name, 'gewerke': w.gewerke}), {'name': _neu.text.trim(), 'gewerke': <String>[]}]);
                _neu.clear();
                setState(() {});
              },
              icon: const Icon(Icons.add),
            ),
          ]),
          const Text('★ = passt zu offenen Aufgaben.', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
        ]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final b = StringBuffer()
              ..writeln('<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">')
              ..writeln('<title>Einkaufszettel</title><style>body{font-family:system-ui;margin:16px;background:#f7f5f0}label{display:flex;gap:10px;background:#fff;'
                  'border-radius:8px;padding:10px;margin:6px 0}input{width:22px;height:22px}.m{margin-left:auto;font-weight:600}h2{font-size:16px}</style></head><body>')
              ..writeln('<h1>Einkaufszettel</h1><div>${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}</div><h2>Kaufen</h2>');
            var n = 0;
            for (final r in fehlt.where((r) => plan.isEmpty || plan.contains('e:${r.element.id}'))) {
              b.writeln('<label><input type="checkbox" id="e${n++}"><span>${r.element.anzeige}<br><small>${elementHaendler(r.element)}</small></span><span class="m">${_z(r.bedarf - r.bestand)} ${r.einheit}</span></label>');
            }
            for (final l in leitungen.where((l) => plan.isEmpty || plan.contains('l:${leitungSchluessel(l)}'))) {
              b.writeln('<label><input type="checkbox" id="l${n++}"><span>${l.bezeichnung}</span><span class="m">${l.einkauf(v.zuschlag).round()} m</span></label>');
            }
            if (uebrig.isNotEmpty) {
              b.writeln('<h2>Noch da – nicht kaufen</h2>');
              for (final r in uebrig) {
                b.writeln('<div>${r.element.anzeige}: ${_z(r.bestand - r.bedarf)} ${r.einheit}</div>');
              }
            }
            if (mitnehmen.isNotEmpty) {
              b.writeln('<h2>Werkzeug mitnehmen</h2>');
              for (final w in mitnehmen) {
                b.writeln('<label><input type="checkbox"><span>$w</span></label>');
              }
            }
            b.writeln('</body></html>');
            final f = File(p.join(store.ordner, 'exporte', 'Einkaufszettel.html'));
            await f.parent.create(recursive: true);
            await f.writeAsString(b.toString());
            if (context.mounted) zeigeHinweis(context, 'Gespeichert unter ${f.path}');
          },
          icon: const Icon(Icons.checklist, size: 18),
          label: const Text('Einkaufszettel (HTML)'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
      ],
    );
  }
}
