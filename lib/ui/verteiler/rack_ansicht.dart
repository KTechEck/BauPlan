import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/ids.dart';
import '../../core/rack.dart';
import '../../data/schrank_models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Netzwerkschrank als 19″-Rack: Geräte je HE, Prüfung, daneben die
/// Patchfeldbelegung (Dose ↔ Port).
class RackAnsicht extends StatefulWidget {
  const RackAnsicht({super.key, required this.state, required this.schrank, required this.patchfeld});
  final AppState state;
  final Schrank schrank;
  final List<Widget> patchfeld;

  @override
  State<RackAnsicht> createState() => _RackAnsichtState();
}

class _RackAnsichtState extends State<RackAnsicht> {
  String? _auswahl;
  AppState get _s => widget.state;

  void _speichern(List<RackGeraet> g, {int? he}) {
    final store = _s.store!;
    final s = store.schraenke().firstWhere((x) => x.id == widget.schrank.id);
    store.schrankAendern(s.id, {
      'eigenschaften': jsonEncode({...s.eigenschaften, 'rack': [for (final x in g) x.toJson()], if (he != null) 'rack_he': he})
    });
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _s.store!.schraenke().firstWhere((x) => x.id == widget.schrank.id);
    final geraete = rackLesen(s);
    final h = rackHoehe(s);
    final pruef = rackPruefen(s);
    final gew = geraete.where((g) => g.id == _auswahl).firstOrNull;
    int freieHe(int hoehe) {
      for (var u = 1; u + hoehe - 1 <= h; u++) {
        if (!geraete.any((g) => u <= g.oben && u + hoehe - 1 >= g.he)) return u;
      }
      return h + 1;
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 380,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('19″-Rack ${s.kennzeichen}', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              DropdownButton<int>(
                value: h,
                items: [for (final n in {6, 9, 12, 15, 18, 22, 27, 42, h}) DropdownMenuItem(value: n, child: Text('$n HE'))],
                onChanged: (v) => _speichern(geraete, he: v),
              ),
            ]),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: const Color(0xFF1F2328), borderRadius: BorderRadius.circular(4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: [
                for (var u = h; u >= 1; u--)
                  () {
                    final g = geraete.where((x) => x.oben == u).firstOrNull;
                    final drin = geraete.any((x) => u < x.oben && u >= x.he);
                    if (drin) return const SizedBox.shrink();
                    final hoehe = g?.hoehe ?? 1;
                    return GestureDetector(
                      onTap: g == null ? null : () => setState(() => _auswahl = g.id),
                      child: Container(
                        height: 22.0 * hoehe,
                        margin: const EdgeInsets.symmetric(vertical: 0.5),
                        decoration: BoxDecoration(
                          color: g == null ? const Color(0xFF2D333B) : _farbe(g.art),
                          border: Border.all(color: g != null && g.id == _auswahl ? BsFarben.akzent : Colors.black26, width: g != null && g.id == _auswahl ? 2 : 0.5),
                        ),
                        child: Row(children: [
                          SizedBox(width: 26, child: Text('$u', style: const TextStyle(fontSize: 10, color: Colors.white54))),
                          Expanded(
                            child: Text(g == null ? '' : '${g.name.isEmpty ? g.art : g.name}${g.ports > 0 ? ' · ${g.ports} Ports' : ''}',
                                style: const TextStyle(fontSize: 11, color: Colors.white), overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ),
                    );
                  }(),
              ]),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in rackArten)
                ActionChip(
                  label: Text(a),
                  onPressed: () {
                    final hoehe = a == 'NAS / Server' || a == 'USV' ? 2 : 1;
                    final g = RackGeraet(id: neueId(), art: a, he: freieHe(hoehe), hoehe: hoehe, ports: a == 'Patchfeld' || a == 'Switch' ? 24 : 0);
                    _speichern([...geraete, g]);
                    setState(() => _auswahl = g.id);
                  },
                ),
            ]),
            for (final p in pruef)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• $p', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
              ),
            if (gew != null) ...[
              const Divider(height: 24),
              Text(gew.art, style: Theme.of(context).textTheme.titleSmall),
              SpeicherFeld(
                key: ValueKey('rn-${gew.id}-${gew.name}'),
                initialValue: gew.name,
                decoration: const InputDecoration(labelText: 'Bezeichnung', isDense: true),
                onFieldSubmitted: (t) => _speichern([for (final x in geraete) x.id == gew.id ? x.mit(name: t.trim()) : x]),
              ),
              Row(children: [
                for (final (k, l, v) in [('he', 'ab HE', gew.he), ('hoehe', 'Höhe HE', gew.hoehe), ('ports', 'Ports', gew.ports), ('watt', 'Watt', gew.watt)])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SpeicherFeld(
                        key: ValueKey('r$k-${gew.id}-$v'),
                        initialValue: '$v',
                        decoration: InputDecoration(labelText: l, isDense: true),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onFieldSubmitted: (t) {
                          final n = int.tryParse(t) ?? v;
                          _speichern([
                            for (final x in geraete)
                              x.id == gew.id ? x.mit(he: k == 'he' ? n : null, hoehe: k == 'hoehe' ? n : null, ports: k == 'ports' ? n : null, watt: k == 'watt' ? n : null) : x
                          ]);
                        },
                      ),
                    ),
                  ),
              ]),
              TextButton.icon(
                onPressed: () {
                  _speichern([for (final x in geraete) if (x.id != gew.id) x]);
                  setState(() => _auswahl = null);
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Entfernen'),
              ),
            ],
          ]),
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Patchfeldbelegung: Port ↔ Netzwerkdose. Die Dose zeigt ihren Port in der Installation an.',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          ...widget.patchfeld,
        ]),
      ),
    ]);
  }

  Color _farbe(String art) => switch (art) {
        'Patchfeld' => const Color(0xFF475569),
        'Switch' => const Color(0xFF2563EB),
        'Router / Firewall' => const Color(0xFF7C3AED),
        'NAS / Server' => const Color(0xFF0F766E),
        'USV' => const Color(0xFFB45309),
        'Fachboden' => const Color(0xFF6B7280),
        _ => const Color(0xFF52525B),
      };
}
