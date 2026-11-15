import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../kontext.dart';
import '../planstand.dart';

String _z(num v, [int s = 2]) => v.toStringAsFixed(s).replaceAll('.', ',');

/// Hydraulischer Abgleich am Verteiler: Soll-Durchfluss und Voreinstellung je
/// Abgang nachschlagen, eingestellten Wert eintragen (geht an den PC).
class AbgleichSeite extends StatefulWidget {
  const AbgleichSeite({super.key, required this.k});
  final MobilKontext k;

  @override
  State<AbgleichSeite> createState() => _AbgleichSeiteState();
}

class _AbgleichSeiteState extends State<AbgleichSeite> {
  final _eingetragen = <String, String>{}; // Kreis-ID → Text des eingetragenen Werts

  MobilKontext get k => widget.k;

  /// Alle Verteiler mit Abgleich aus allen Geschossen.
  List<(Map<String, dynamic> verteiler, Map<String, dynamic> geschoss)> get _verteiler => [
        for (final g in k.plan.geschosse)
          for (final o in Planstand.liste(g['objekte']))
            if (o['abgleich'] is List && o['durchgehend'] != true) (o, g),
      ];

  Future<void> _eintragen(Map<String, dynamic> zeile, Map<String, dynamic> g) async {
    final lmin = TextEditingController(text: zeile['ist_l_min'] == null ? '' : _z(zeile['ist_l_min'] as num));
    final stufe = TextEditingController(text: '${zeile['ist_stufe'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Abgang ${zeile['abgang']} · ${zeile['kennung']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Soll: ${_z(zeile['soll_l_min'] as num)} l/min${zeile['stufe'] == null ? '' : ' · Stufe ${zeile['stufe']}'}'),
          TextField(controller: lmin, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Eingestellt (l/min)')),
          TextField(controller: stufe, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Voreinstellung (Stufe)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Senden')),
        ],
      ),
    );
    if (ok != true) return;
    final l = double.tryParse(lmin.text.trim().replaceAll(',', '.'));
    final s = int.tryParse(stufe.text.trim());
    if (l == null && s == null) return;
    await k.erfasst({
      'art': 'abgleich',
      'zeit': DateTime.now().toIso8601String(),
      'geschoss': g['id'],
      'objekt': zeile['kreis'],
      if (l != null) 'ist_l_min': l,
      if (s != null) 'ist_stufe': s,
    });
    setState(() => _eingetragen['${zeile['kreis']}'] = [if (l != null) '${_z(l)} l/min', if (s != null) 'Stufe $s'].join(' · '));
  }

  @override
  Widget build(BuildContext context) {
    final liste = _verteiler;
    return Scaffold(
      appBar: AppBar(title: const Text('Hydraulischer Abgleich')),
      body: liste.isEmpty
          ? const Padding(padding: EdgeInsets.all(16), child: Text('Am PC ist noch kein Verteiler mit belegten Abgängen geplant.'))
          : ListView(padding: const EdgeInsets.all(12), children: [
              const Text('Soll-Wert am Durchflussmesser einstellen, eingestellten Wert antippen und eintragen.',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              for (final (v, g) in liste) ...[
                const SizedBox(height: 10),
                Text('${v['kennung']} · ${k.plan.raumName(v['raum'] as String?)} (${g['name'] ?? g['kuerzel']})', style: Theme.of(context).textTheme.titleMedium),
                for (final z in Planstand.liste(v['abgleich']))
                  Builder(builder: (_) {
                    final ist = z['ist_l_min'] as num?;
                    final soll = z['soll_l_min'] as num;
                    final abw = ist == null || soll <= 0 ? null : (ist - soll) / soll * 100;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(radius: 14, child: Text('${z['abgang']}', style: const TextStyle(fontSize: 12))),
                      title: Text('${_z(soll)} l/min${z['stufe'] == null ? '' : ' · Stufe ${z['stufe']}'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        '${z['kennung']} · ${z['raum']}',
                        if (_eingetragen[z['kreis']] case final t?) 'gesendet: $t'
                        else if (ist != null) 'eingestellt ${_z(ist)} l/min (${abw! >= 0 ? '+' : ''}${_z(abw, 0)} %)',
                      ].join('\n')),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _eintragen(z, g),
                    );
                  }),
              ],
            ]),
    );
  }
}
