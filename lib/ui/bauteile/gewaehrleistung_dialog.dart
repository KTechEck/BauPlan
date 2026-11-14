import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/ids.dart';
import '../../data/project_store.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import 'einkauf_dialog.dart' show einkaeufeLesen;

/// Gewährleistung je Produkt (Projekteinstellung `gewaehrleistung`):
/// Produkt, Hersteller, Händler, Kaufdatum, Jahre. Vorschläge aus den Einkäufen.
typedef Gewaehr = ({String id, String produkt, String hersteller, String haendler, DateTime kauf, int jahre, String notiz});

List<Gewaehr> gewaehrleistungLesen(ProjectStore store) => [
      for (final m in (store.einstellung<List>('gewaehrleistung') ?? const []))
        if (m is Map)
          (
            id: '${m['id']}',
            produkt: '${m['produkt'] ?? ''}',
            hersteller: '${m['hersteller'] ?? ''}',
            haendler: '${m['haendler'] ?? ''}',
            kauf: DateTime.tryParse('${m['kauf']}') ?? DateTime.now(),
            jahre: (m['jahre'] as num?)?.toInt() ?? 2,
            notiz: '${m['notiz'] ?? ''}',
          ),
    ];

void _speichern(ProjectStore store, List<Gewaehr> l) => store.einstellungSetzen('gewaehrleistung', [
      for (final g in l)
        {'id': g.id, 'produkt': g.produkt, 'hersteller': g.hersteller, 'haendler': g.haendler, 'kauf': g.kauf.toIso8601String().substring(0, 10), 'jahre': g.jahre, 'notiz': g.notiz},
    ]);

/// Läuft in den nächsten [tage] Tagen ab (für dezente Hinweise).
List<Gewaehr> gewaehrleistungBaldAus(ProjectStore store, {int tage = 60, DateTime? heute}) {
  final h = heute ?? DateTime.now();
  return [
    for (final g in gewaehrleistungLesen(store))
      if (DateTime(g.kauf.year + g.jahre, g.kauf.month, g.kauf.day).difference(h).inDays case final d when d >= 0 && d <= tage) g,
  ];
}

Future<void> gewaehrleistungDialog(BuildContext context, AppState s) async {
  final store = s.store!;
  String d(DateTime t) => '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      final l = gewaehrleistungLesen(store)..sort((a, b) => DateTime(a.kauf.year + a.jahre, a.kauf.month, a.kauf.day).compareTo(DateTime(b.kauf.year + b.jahre, b.kauf.month, b.kauf.day)));
      final heute = DateTime.now();
      void aendern(Gewaehr alt, Gewaehr neu) {
        _speichern(store, [for (final x in l) x.id == alt.id ? neu : x]);
        setD(() {});
      }

      final vorschlaege = [
        for (final e in einkaeufeLesen(store))
          for (final p in e.positionen)
            if ((p.preisCent ?? 0) >= 5000 && !l.any((g) => g.produkt == p.text)) (e, p),
      ];
      return AlertDialog(
        title: const Text('Gewährleistung'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: ListView(children: [
            const Text('Gesetzliche Gewährleistung meist 2 Jahre (Händler), Herstellergarantie oft länger. Die Liste erscheint auch in der Hausakte.',
                style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            for (final g in l)
              () {
                final ende = DateTime(g.kauf.year + g.jahre, g.kauf.month, g.kauf.day);
                final rest = ende.difference(heute).inDays;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [
                      Expanded(
                        flex: 3,
                        child: SpeicherFeld(
                          key: ValueKey('gw-p-${g.id}-${g.produkt}'),
                          initialValue: g.produkt,
                          decoration: const InputDecoration(labelText: 'Produkt', isDense: true),
                          onFieldSubmitted: (t) => aendern(g, (id: g.id, produkt: t.trim(), hersteller: g.hersteller, haendler: g.haendler, kauf: g.kauf, jahre: g.jahre, notiz: g.notiz)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: SpeicherFeld(
                          key: ValueKey('gw-h-${g.id}-${g.hersteller}'),
                          initialValue: g.hersteller,
                          decoration: const InputDecoration(labelText: 'Hersteller', isDense: true),
                          onFieldSubmitted: (t) => aendern(g, (id: g.id, produkt: g.produkt, hersteller: t.trim(), haendler: g.haendler, kauf: g.kauf, jahre: g.jahre, notiz: g.notiz)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: SpeicherFeld(
                          key: ValueKey('gw-ha-${g.id}-${g.haendler}'),
                          initialValue: g.haendler,
                          decoration: const InputDecoration(labelText: 'Händler', isDense: true),
                          onFieldSubmitted: (t) => aendern(g, (id: g.id, produkt: g.produkt, hersteller: g.hersteller, haendler: t.trim(), kauf: g.kauf, jahre: g.jahre, notiz: g.notiz)),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final t = await showDatePicker(context: c, initialDate: g.kauf, firstDate: DateTime(2000), lastDate: DateTime(2100));
                          if (t != null) aendern(g, (id: g.id, produkt: g.produkt, hersteller: g.hersteller, haendler: g.haendler, kauf: t, jahre: g.jahre, notiz: g.notiz));
                        },
                        child: Text(d(g.kauf)),
                      ),
                      SizedBox(
                        width: 60,
                        child: SpeicherFeld(
                          key: ValueKey('gw-j-${g.id}-${g.jahre}'),
                          initialValue: '${g.jahre}',
                          decoration: const InputDecoration(labelText: 'Jahre', isDense: true),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onFieldSubmitted: (t) => aendern(g, (id: g.id, produkt: g.produkt, hersteller: g.hersteller, haendler: g.haendler, kauf: g.kauf, jahre: int.tryParse(t) ?? g.jahre, notiz: g.notiz)),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(rest < 0 ? 'abgelaufen' : 'bis ${d(ende)}',
                            textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: rest < 0 ? BsFarben.textLeise : (rest <= 60 ? const Color(0xFFB45309) : null))),
                      ),
                      IconButton(
                        onPressed: () {
                          _speichern(store, [for (final x in l) if (x.id != g.id) x]);
                          setD(() {});
                        },
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ]),
                  ),
                );
              }(),
            TextButton.icon(
              onPressed: () {
                _speichern(store, [...l, (id: neueId(), produkt: '', hersteller: '', haendler: '', kauf: DateTime.now(), jahre: 2, notiz: '')]);
                setD(() {});
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Eintrag'),
            ),
            if (vorschlaege.isNotEmpty) ...[
              const Divider(),
              const Text('Aus den Einkäufen (ab 50 €):', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final (e, p) in vorschlaege.take(20))
                ListTile(
                  dense: true,
                  title: Text(p.text),
                  subtitle: Text('${e.haendler} · ${d(e.datum)}'),
                  trailing: TextButton(
                    onPressed: () {
                      _speichern(store, [...l, (id: neueId(), produkt: p.text, hersteller: '', haendler: e.haendler, kauf: e.datum, jahre: 2, notiz: '')]);
                      setD(() {});
                    },
                    child: const Text('übernehmen'),
                  ),
                ),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
      );
    }),
  );
}
