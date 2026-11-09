import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/ki.dart';
import '../state/app_state.dart';
import 'assistent/projektpruefung.dart';

/// Hinweise, Warnungen und erkannte Probleme gesammelt in der Kopfleiste
/// (Glocke mit Zahl). Ein Klick öffnet sie als Fenster am rechten Rand –
/// die Arbeitsfläche bleibt frei.
class HinweisGlocke extends StatelessWidget {
  const HinweisGlocke({super.key, required this.state});
  final AppState state;

  List<PruefHinweis> _offene() {
    final store = state.store;
    if (store == null) return const [];
    final status = Map<String, String>.from(store.einstellung<Map>('pruefung_status') ?? const {});
    try {
      final r = Regelwerte.ausJson(store.einstellung<Map>('regeln')?.cast<String, dynamic>());
      return [for (final h in projektPruefen(store, r)) if ((status[h.schluessel] ?? 'offen') == 'offen') h];
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final offen = _offene();
    return IconButton(
      tooltip: offen.isEmpty ? 'Keine offenen Hinweise' : '${offen.length} offene Hinweise und Warnungen',
      onPressed: () => _zeigen(context, offen),
      icon: Badge(
        isLabelVisible: offen.isNotEmpty,
        label: Text('${offen.length}'),
        backgroundColor: const Color(0xFFE67700),
        child: const Icon(Icons.notifications_none, color: Color(0xFFC9CDD1)),
      ),
    );
  }

  Future<void> _zeigen(BuildContext context, List<PruefHinweis> offen) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Hinweise schließen',
      barrierColor: Colors.black12,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (c, _, __) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 60, right: 12),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
            child: SizedBox(
              width: 420,
              height: 560,
              child: StatefulBuilder(builder: (c, neu) {
                final liste = _offene();
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 6, 4),
                    child: Row(children: [
                      Expanded(child: Text('Hinweise und Warnungen (${liste.length})', style: Theme.of(c).textTheme.titleMedium)),
                      IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
                    ]),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Aus der Planprüfung (feste Regeln). Erledigte oder bewusst so geplante Punkte verschwinden aus der Liste.',
                        style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                  ),
                  const Divider(),
                  Expanded(
                    child: liste.isEmpty
                        ? const Center(child: Text('Keine offenen Hinweise. ✓'))
                        : ListView(children: [
                            for (final h in liste)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.warning_amber, color: Color(0xFFE67700)),
                                title: Text(h.text),
                                subtitle: Text(h.bereich),
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Status setzen',
                                  onSelected: (s) {
                                    final store = state.store!;
                                    final m = Map<String, dynamic>.from(store.einstellung<Map>('pruefung_status') ?? const {})..[h.schluessel] = s;
                                    store.einstellungSetzen('pruefung_status', m);
                                    state.geaendert();
                                    neu(() {});
                                  },
                                  itemBuilder: (_) => [
                                    for (final e in pruefStatus.entries)
                                      if (e.key != 'offen') PopupMenuItem(value: e.key, child: Text(e.value)),
                                  ],
                                ),
                                onTap: h.objektId == null
                                    ? null
                                    : () {
                                        Navigator.pop(c);
                                        state.objektAuswahl = h.objektId;
                                        state.markiert = {h.objektId!};
                                        state.modulWaehlen(Modul.installation);
                                      },
                              ),
                          ]),
                  ),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }
}
