import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../kontext.dart';

/// Einkaufsliste nach Lastenheft: alle offenen Positionen, gruppiert nach
/// Händler (oder nach Herkunft, Kategorie, Raum), abhakbar, mit Produktinfo
/// und Händler-Link. Abgehakt = gekauft (Bestand am PC steigt bzw. Position
/// gilt als geliefert).
class EinkaufSeite extends StatefulWidget {
  const EinkaufSeite({super.key, required this.k});
  final MobilKontext k;

  @override
  State<EinkaufSeite> createState() => _EinkaufSeiteState();
}

const _ansichten = {'haendler': 'Händler', 'herkunft': 'Gewerk / Bereich', 'kategorie': 'Kategorie', 'raum': 'Raum'};

class _EinkaufSeiteState extends State<EinkaufSeite> {
  String _suche = '';
  bool _erledigteZeigen = false, _kompakt = false;

  MobilKontext get k => widget.k;

  bool _erledigt(Map<String, dynamic> e) => k.einstellungen.abgehakt.contains(e['id']) || e['status'] == 'geliefert' || e['status'] == 'bezahlt';

  String _gruppe(Map<String, dynamic> e) => switch (k.einstellungen.einkaufAnsicht) {
        'herkunft' => '${e['herkunft'] ?? e['gewerk'] ?? 'Kosten / ohne Zuordnung'}'.split(',').first.trim(),
        'kategorie' => '${e['kategorie'] ?? 'ohne Kategorie'}',
        'raum' => '${e['raum'] ?? 'ohne Raum'}',
        _ => '${e['haendler'] ?? 'ohne Händler'}',
      };

  @override
  Widget build(BuildContext context) {
    final alle = k.plan.einkauf;
    final liste = [
      for (final e in alle)
        if ((_erledigteZeigen || !_erledigt(e)) && (_suche.isEmpty || '${e['text']} ${(e['produkt'] as Map?)?['artikel'] ?? ''}'.toLowerCase().contains(_suche))) e
    ];
    final gruppen = <String, List<Map<String, dynamic>>>{};
    for (final e in liste) {
      gruppen.putIfAbsent(_gruppe(e), () => []).add(e);
    }
    final namen = gruppen.keys.toList()..sort((a, b) => a.startsWith('ohne') ? 1 : b.startsWith('ohne') ? -1 : a.compareTo(b));
    final offen = alle.where((e) => !_erledigt(e)).length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Artikel suchen', isDense: true),
          onChanged: (v) => setState(() => _suche = v.trim().toLowerCase()),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), children: [
          for (final a in _ansichten.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(a.value),
                selected: k.einstellungen.einkaufAnsicht == a.key,
                onSelected: (_) => setState(() {
                  k.einstellungen.einkaufAnsicht = a.key;
                  k.einstellungen.speichern();
                }),
              ),
            ),
          FilterChip(label: const Text('kompakt'), selected: _kompakt, onSelected: (v) => setState(() => _kompakt = v)),
          const SizedBox(width: 6),
          FilterChip(label: const Text('erledigte'), selected: _erledigteZeigen, onSelected: (v) => setState(() => _erledigteZeigen = v)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text('$offen offen von ${alle.length}', style: const TextStyle(color: BsFarben.textLeise)),
          const Spacer(),
          Text(_euro(liste.where((e) => !_erledigt(e)).fold<int>(0, (s, e) => s + _summe(e))), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
      Expanded(
        child: liste.isEmpty
            ? const Center(
                child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nichts offen. Am PC füllt sich die Liste aus den Kostenpositionen und der Besorgungsliste (Produkte aus der Bibliothek im Plan).',
                    textAlign: TextAlign.center, style: TextStyle(color: BsFarben.textLeise)),
              ))
            : ListView(children: [
                for (final g in namen) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                    child: Row(children: [
                      Expanded(child: Text(g, style: Theme.of(context).textTheme.titleSmall)),
                      Text('${gruppen[g]!.length} · ${_euro(gruppen[g]!.fold<int>(0, (s, e) => s + _summe(e)))}', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                    ]),
                  ),
                  for (final e in gruppen[g]!)
                    CheckboxListTile(
                      dense: _kompakt,
                      value: _erledigt(e),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => _abhaken(e, v == true),
                      title: Text('${e['text']}', style: TextStyle(decoration: _erledigt(e) ? TextDecoration.lineThrough : null)),
                      subtitle: _kompakt
                          ? null
                          : Text([
                              '${_menge(e['menge'])} ${e['einheit'] ?? ''}',
                              if (e['preis_cent'] != null) '${_euro(e['preis_cent'] as int)} je ${e['einheit'] ?? 'Stk'}',
                              if ((e['produkt'] as Map?)?['artikel'] != null) 'Art.-Nr. ${(e['produkt'] as Map)['artikel']}',
                              if (k.einstellungen.einkaufAnsicht != 'haendler') '${e['haendler']}',
                            ].join(' · ')),
                      secondary: IconButton(icon: const Icon(Icons.info_outline), tooltip: 'Produktinfo', onPressed: () => _info(context, e)),
                    ),
                ],
              ]),
      ),
    ]);
  }

  int _summe(Map<String, dynamic> e) => (((e['preis_cent'] as num?) ?? 0) * ((e['menge'] as num?) ?? 0)).round();

  Future<void> _abhaken(Map<String, dynamic> e, bool erledigt) async {
    setState(() => erledigt ? k.einstellungen.abgehakt.add('${e['id']}') : k.einstellungen.abgehakt.remove('${e['id']}'));
    k.einstellungen.speichern();
    await k.erfasst({
      'art': 'einkauf',
      if (e['quelle'] != 'bedarf') 'position': e['id'],
      if (e['element'] != null) 'element': e['element'],
      'menge': e['menge'],
      'text': e['text'],
      'erledigt': erledigt,
    });
  }

  void _info(BuildContext context, Map<String, dynamic> e) {
    final p = Map<String, dynamic>.from(e['produkt'] as Map? ?? const {});
    final angebote = [for (final a in (p['angebote'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)];
    final guenstig = angebote.isEmpty ? null : angebote.reduce((a, b) => ((a['preis_cent'] as num?) ?? 1 << 30) <= ((b['preis_cent'] as num?) ?? 1 << 30) ? a : b);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
          Text('${e['text']}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final (l, v) in [
            ('Hersteller', p['hersteller']),
            ('Artikelnummer', p['artikel']),
            ('EAN', p['ean']),
            ('Menge', '${_menge(e['menge'])} ${e['einheit'] ?? ''}'),
            ('Bedarf laut Plan', p['bedarf'] == null ? null : '${_menge(p['bedarf'])} ${e['einheit'] ?? ''}'),
            ('Bestand', p['bestand'] == null ? null : _menge(p['bestand'])),
            ('Preis', e['preis_cent'] == null ? null : _euro(e['preis_cent'] as int)),
            ('Händler', e['haendler']),
            ('für', e['herkunft'] ?? e['gewerk']),
            ('Raum', e['raum']),
            ('Notiz', p['notiz']),
          ])
            if (v != null && '$v'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 130, child: Text(l, style: const TextStyle(color: BsFarben.textLeise))),
                  Expanded(child: Text('$v')),
                ]),
              ),
          if (angebote.isNotEmpty) ...[
            const Divider(),
            const Text('Angebote', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final a in angebote)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(identical(a, guenstig) ? Icons.star : Icons.storefront_outlined, color: identical(a, guenstig) ? BsFarben.akzent : null),
                title: Text('${a['haendler']}'),
                subtitle: Text([if (a['preis_cent'] != null) _euro(a['preis_cent'] as int), if (a['datum'] != null) 'Stand ${a['datum']}'].join(' · ')),
                trailing: a['link'] == null ? null : const Icon(Icons.open_in_new),
                onTap: a['link'] == null ? null : () => _oeffnen('${a['link']}'),
              ),
          ],
          const SizedBox(height: 8),
          if (e['link'] != null)
            FilledButton.icon(onPressed: () => _oeffnen('${e['link']}'), icon: const Icon(Icons.open_in_new), label: Text('Beim Händler öffnen (${e['haendler']})')),
        ]),
      ),
    );
  }

  Future<void> _oeffnen(String link) async {
    final u = Uri.tryParse(link.startsWith('http') ? link : 'https://$link');
    if (u == null) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Link lässt sich nicht öffnen: $link')));
    }
  }
}

String _menge(Object? m) {
  final x = (m as num?)?.toDouble() ?? 0;
  return x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(1).replaceAll('.', ',');
}

String _euro(int cent) => '${(cent / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
