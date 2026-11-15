import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// Treffer der Kabelsuche: Objekt, Geschoss, Anzeigetext.
typedef KabelTreffer = ({Objekt objekt, String geschossId, String geschoss, String titel, String zeile, double laengeM});

/// Leitungen, Kabel, Rohre (und Geräte mit Zuleitung) nach Text suchen:
/// Kennung, Typ, Kabelbezeichnung (auch aus der Bibliothek), Stromkreis.
List<KabelTreffer> kabelSuchen(AppState s, String text) {
  final q = text.trim().toLowerCase();
  if (q.length < 2) return const [];
  final store = s.store!;
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final geschossName = <String, String>{};
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      geschossName[g.id] = g.name;
    }
  }
  String? name(Object? id) => id is String && id.isNotEmpty ? (s.bibliothek.fuerProjekt(store, id)?.anzeige ?? id) : null;
  final aus = <KabelTreffer>[];
  for (final o in store.alleObjekte()) {
    final t = typen[o.typId];
    if (t == null) continue;
    final e = o.eigenschaften;
    final kabel = [
      if (e['kabel'] is String) e['kabel'] as String,
      for (final k in (e['kabel_liste'] as List? ?? const [])) name(k),
      name(e['rohr']),
      name(e['zuleitung_kabel']),
    ].whereType<String>().toList();
    final teile = [o.kennung, t.name, t.kuerzel, ...kabel, '${e['stromkreis'] ?? ''}', '${e['bezeichnung'] ?? ''}', '${e['dimension'] ?? ''}'];
    if (!teile.join(' ').toLowerCase().contains(q)) continue;
    if (t.geometrie != Geometrieart.linie && kabel.isEmpty && !'${e['stromkreis'] ?? ''}'.toLowerCase().contains(q)) continue;
    aus.add((
      objekt: o,
      geschossId: o.geschossId,
      geschoss: geschossName[o.geschossId] ?? '',
      titel: '${o.kennung} · ${t.name}',
      zeile: [if (kabel.isNotEmpty) kabel.join(', '), if (e['stromkreis'] != null) 'Stromkreis ${e['stromkreis']}'].join(' · '),
      laengeM: o.punkte.length >= 2 ? o.laenge / 1000 : 0,
    ));
  }
  aus.sort((a, b) => a.geschoss.compareTo(b.geschoss));
  return aus;
}

/// Suchfeld für die Werkzeugleiste: markiert alle Treffer im Plan (alle
/// Geschosse), Liste mit Sprung zum Treffer.
class KabelSuchfeld extends StatefulWidget {
  const KabelSuchfeld({super.key, required this.state, required this.springen});
  final AppState state;

  /// Zum Treffer springen (Geschoss wechseln, einpassen).
  final void Function(KabelTreffer t) springen;

  @override
  State<KabelSuchfeld> createState() => _KabelSuchfeldState();
}

class _KabelSuchfeldState extends State<KabelSuchfeld> {
  final _c = TextEditingController();
  List<KabelTreffer> _treffer = const [];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _suchen(String t) {
    final l = kabelSuchen(widget.state, t);
    setState(() => _treffer = l);
    widget.state.markiert = {for (final x in l) x.objekt.id};
    widget.state.geaendertOhneSpeichern();
  }

  @override
  Widget build(BuildContext context) {
    final hier = _treffer.where((t) => t.geschossId == widget.state.geschossId).length;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 210,
        child: TextField(
          controller: _c,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.cable, size: 18),
            hintText: 'Kabel / Leitung suchen',
            suffixIcon: _c.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Suche leeren',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      _c.clear();
                      _suchen('');
                    },
                  ),
          ),
          onChanged: _suchen,
          onSubmitted: (_) {
            if (_treffer.isNotEmpty) widget.springen(_treffer.first);
          },
        ),
      ),
      if (_c.text.trim().length >= 2)
        PopupMenuButton<KabelTreffer>(
          tooltip: 'Treffer anzeigen',
          onSelected: widget.springen,
          itemBuilder: (_) => _treffer.isEmpty
              ? [const PopupMenuItem(enabled: false, child: Text('Nichts gefunden'))]
              : [
                  for (final t in _treffer.take(60))
                    PopupMenuItem(
                      value: t,
                      child: ListTile(
                        dense: true,
                        title: Text(t.titel),
                        subtitle: Text([t.geschoss, if (t.zeile.isNotEmpty) t.zeile, if (t.laengeM > 0) '${t.laengeM.toStringAsFixed(1).replaceAll('.', ',')} m'].join(' · ')),
                      ),
                    ),
                ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: _treffer.isEmpty ? null : BsFarben.akzentHell,
              label: Text('${_treffer.length} Treffer${_treffer.isEmpty ? '' : ', $hier hier'} ▾', style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
    ]);
  }
}
