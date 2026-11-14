import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/tagebuch_models.dart';
import '../state/app_state.dart';

/// Ein Suchtreffer mit Sprungziel.
typedef SuchTreffer = ({String gruppe, String titel, String zeile, IconData symbol, void Function() oeffnen});

/// Globale Suche über Räume, Objekte (Kennung, Typ, Typenschild), Aufgaben,
/// Tagebuch, Stromkreise, Bibliothek, Fotos und Module (Strg+F).
List<SuchTreffer> suchen(AppState s, String text) {
  final q = text.trim().toLowerCase();
  if (q.length < 2) return const [];
  final store = s.store!;
  final aus = <SuchTreffer>[];
  bool passt(String t) => t.toLowerCase().contains(q);
  for (final m in Modul.values) {
    if (passt(m.label)) aus.add((gruppe: 'Module', titel: m.label, zeile: 'Modul öffnen', symbol: Icons.apps, oeffnen: () => s.modulWaehlen(m)));
  }
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final raumName = <String, String>{};
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      for (final r in store.raeume(g.id)) {
        raumName[r.id] = '${g.kuerzel} ${r.name}';
        if (passt(r.name) || passt(r.kuerzel)) {
          aus.add((gruppe: 'Räume', titel: r.name, zeile: '${g.kuerzel} · ${r.kuerzel}', symbol: Icons.meeting_room_outlined, oeffnen: () {
            s.geschossId = g.id;
            s.modulWaehlen(Modul.grundriss);
          }));
        }
      }
    }
  }
  for (final o in store.alleObjekte()) {
    final t = typen[o.typId];
    final ts = o.eigenschaften['typenschild'] is Map ? (o.eigenschaften['typenschild'] as Map).values.join(' ') : '';
    final text = '${o.kennung} ${t?.name ?? ''} ${o.eigenschaften['geraet'] ?? ''} $ts ${o.eigenschaften['bezeichnung'] ?? ''}';
    if (!passt(text)) continue;
    aus.add((gruppe: 'Objekte', titel: '${o.kennung} · ${t?.name ?? ''}', zeile: raumName[o.raumId] ?? '', symbol: Icons.place_outlined, oeffnen: () {
      s.markiert = {o.id};
      s.geschossId = o.geschossId;
      s.modulWaehlen(Modul.installation);
    }));
    if (aus.length > 200) break;
  }
  for (final a in store.aufgaben()) {
    if (!passt('${a.titel} ${a.beschreibung}')) continue;
    aus.add((
      gruppe: 'Aufgaben und Mängel',
      titel: a.titel,
      zeile: '${aufgabenArten[a.art] ?? 'Aufgabe'} · ${a.status.label}${a.raumId == null ? '' : ' · ${raumName[a.raumId] ?? ''}'}',
      symbol: a.art == 'mangel' ? Icons.report_problem_outlined : Icons.checklist,
      oeffnen: () => s.modulWaehlen(Modul.tagebuch),
    ));
  }
  for (final t in store.tagebuch()) {
    if (!passt(t.text)) continue;
    aus.add((gruppe: 'Tagebuch', titel: t.text.length > 80 ? '${t.text.substring(0, 80)} …' : t.text, zeile: '${t.datum.day}.${t.datum.month}.${t.datum.year}', symbol: Icons.menu_book_outlined, oeffnen: () => s.modulWaehlen(Modul.tagebuch)));
  }
  for (final sch in store.schraenke()) {
    if (passt('${sch.name} ${sch.kennzeichen}')) {
      aus.add((gruppe: 'Verteiler', titel: '${sch.kennzeichen} ${sch.name}', zeile: sch.art.label, symbol: Icons.electrical_services, oeffnen: () => s.modulWaehlen(Modul.verteiler)));
    }
    for (final k in store.stromkreise(sch.id)) {
      if (passt('${k.nummer} ${k.bezeichnung} ${k.leitung}')) {
        aus.add((gruppe: 'Stromkreise', titel: '${sch.kennzeichen} · ${k.nummer} ${k.bezeichnung}', zeile: k.leitung, symbol: Icons.bolt, oeffnen: () => s.modulWaehlen(Modul.verteiler)));
      }
    }
  }
  for (final e in s.bibliothek.alle) {
    if (!passt('${e.name} ${e.hersteller} ${e.artikelnummer}')) continue;
    aus.add((gruppe: 'Bibliothek', titel: e.anzeige, zeile: e.kategorie.label, symbol: Icons.inventory_2_outlined, oeffnen: () => s.modulWaehlen(Modul.bauteile)));
    if (aus.length > 300) break;
  }
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      for (final f in store.fotos(g.id)) {
        if ((f.notiz ?? '').isEmpty || !passt(f.notiz!)) continue;
        aus.add((gruppe: 'Fotos', titel: f.notiz!, zeile: raumName[f.raumId] ?? g.kuerzel, symbol: Icons.photo_outlined, oeffnen: () {
          s.geschossId = g.id;
          s.modulWaehlen(Modul.fotos);
        }));
      }
    }
  }
  return aus;
}

Future<void> sucheOeffnen(BuildContext context, AppState s) => showDialog<void>(context: context, builder: (_) => _Suche(state: s));

class _Suche extends StatefulWidget {
  const _Suche({required this.state});
  final AppState state;
  @override
  State<_Suche> createState() => _SucheState();
}

class _SucheState extends State<_Suche> {
  String _text = '';

  @override
  Widget build(BuildContext context) {
    final treffer = suchen(widget.state, _text);
    final gruppen = <String, List<SuchTreffer>>{};
    for (final t in treffer) {
      (gruppen[t.gruppe] ??= []).add(t);
    }
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 60, left: 40, right: 40),
      child: SizedBox(
        width: 680,
        height: 520,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Suchen: Raum, Kennung, Gerät, Aufgabe, Stromkreis, Artikel …'),
              onChanged: (t) => setState(() => _text = t),
              onSubmitted: (_) {
                if (treffer.isEmpty) return;
                Navigator.pop(context);
                treffer.first.oeffnen();
              },
            ),
          ),
          Expanded(
            child: _text.trim().length < 2
                ? const Center(child: Text('Mindestens zwei Zeichen eingeben. Enter öffnet den ersten Treffer.', style: TextStyle(color: BsFarben.textLeise)))
                : treffer.isEmpty
                    ? const Center(child: Text('Nichts gefunden.'))
                    : ListView(children: [
                        for (final e in gruppen.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                            child: Text('${e.key.toUpperCase()} (${e.value.length})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BsFarben.textLeise, letterSpacing: 0.6)),
                          ),
                          for (final t in e.value.take(25))
                            ListTile(
                              dense: true,
                              leading: Icon(t.symbol, size: 20),
                              title: Text(t.titel, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: t.zeile.isEmpty ? null : Text(t.zeile, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                Navigator.pop(context);
                                t.oeffnen();
                              },
                            ),
                        ],
                      ]),
          ),
        ]),
      ),
    );
  }
}
