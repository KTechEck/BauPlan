import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/rollen.dart';
import '../data/austausch.dart';
import '../state/app_state.dart';

/// Benutzer und Rollen (Lastenheft: Eigentümer / Mitarbeit / Gast). Jeder
/// Benutzer bekommt einen eigenen Kopplungscode für die App; der PC erkennt
/// daran Rolle und freigegebene Räume. Darunter: Einträge, die auf Prüfung warten.
class BenutzerRollenKarte extends StatefulWidget {
  const BenutzerRollenKarte({super.key, required this.state});
  final AppState state;

  @override
  State<BenutzerRollenKarte> createState() => _BenutzerRollenKarteState();
}

class _BenutzerRollenKarteState extends State<BenutzerRollenKarte> {
  AppState get _s => widget.state;

  List<Benutzer> get _liste => benutzerAus(_s.store?.einstellung<List>('benutzer'));

  void _speichern(List<Benutzer> l) {
    _s.store!.einstellungSetzen('benutzer', [for (final b in l) b.toJson()]);
    _s.geaendert();
    setState(() {});
  }

  Future<void> _bearbeiten(Benutzer? alt) async {
    final store = _s.store!;
    final raeume = [
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) (r.id, '${g.kuerzel} ${r.name}'),
    ];
    final name = TextEditingController(text: alt?.name ?? '');
    var rolle = alt?.rolle ?? Rolle.mitarbeit;
    var pruef = alt?.pruefpflicht ?? true;
    final frei = {...?alt?.raeume};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(alt == null ? 'Benutzer anlegen' : 'Benutzer bearbeiten'),
          content: SizedBox(
            width: 460,
            child: ListView(shrinkWrap: true, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name (z. B. Elektriker Müller, Familie)')),
              const SizedBox(height: 12),
              SegmentedButton<Rolle>(
                segments: [for (final r in Rolle.values.where((r) => r != Rolle.eigentuemer)) ButtonSegment(value: r, label: Text(r.label))],
                selected: {rolle},
                onSelectionChanged: (v) => setD(() => rolle = v.first),
              ),
              Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: Text(rolle.darf, style: const TextStyle(fontSize: 11))),
              if (rolle == Rolle.mitarbeit)
                SwitchListTile(
                  dense: true,
                  value: pruef,
                  title: const Text('Einträge erst nach Prüfung übernehmen'),
                  onChanged: (v) => setD(() => pruef = v),
                ),
              const SizedBox(height: 8),
              Text('Freigegebene Räume (keiner gewählt = alle)', style: Theme.of(c).textTheme.titleSmall),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final (id, text) in raeume)
                  FilterChip(
                    label: Text(text, style: const TextStyle(fontSize: 12)),
                    selected: frei.contains(id),
                    onSelected: (v) => setD(() => v ? frei.add(id) : frei.remove(id)),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final l = _liste;
    final neu = (alt ?? Benutzer(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), name: '', rolle: rolle, code: _freierCode(l)))
        .mit(name: name.text.trim(), rolle: rolle, raeume: frei.toList(), pruefpflicht: pruef);
    _speichern([for (final b in l) if (b.id != neu.id) b, neu]);
  }

  String _freierCode(List<Benutzer> l) {
    while (true) {
      final c = benutzerCode();
      if (c != _s.speicher.code && !l.any((b) => b.code == c)) return c;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store;
    const leise = TextStyle(fontSize: 12, color: BsFarben.textLeise);
    if (store == null) return const SizedBox.shrink();
    final liste = _liste;
    final pruefen = pruefListe(store);
    final raumName = {
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) r.id: r.name,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Benutzer und Rollen', style: Theme.of(context).textTheme.titleMedium)),
            OutlinedButton.icon(onPressed: () => _bearbeiten(null), icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Benutzer anlegen')),
          ]),
          const SizedBox(height: 4),
          const Text('Du bist Eigentümer (Kopplungscode oben). Weitere Personen bekommen einen eigenen Code für die App: '
              'Mitarbeit sieht und erfasst nur in freigegebenen Räumen, Gast liest nur.', style: leise),
          for (final b in liste)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(b.rolle == Rolle.gast ? Icons.visibility_outlined : Icons.engineering_outlined),
              title: Text('${b.name} · ${b.rolle.label}'),
              subtitle: Text([
                'Code ${b.code}',
                b.raeume.isEmpty ? 'alle Räume' : b.raeume.map((r) => raumName[r] ?? '?').join(', '),
                if (b.rolle == Rolle.mitarbeit) b.pruefpflicht ? 'mit Prüfung' : 'ohne Prüfung',
              ].join(' · ')),
              trailing: Wrap(children: [
                IconButton(tooltip: 'Bearbeiten', onPressed: () => _bearbeiten(b), icon: const Icon(Icons.edit_outlined)),
                IconButton(
                  tooltip: 'Neuer Code (altes Gerät wird getrennt)',
                  onPressed: () => _speichern([for (final x in liste) x.id == b.id ? x.mit(code: _freierCode(liste)) : x]),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(tooltip: 'Entfernen', onPressed: () => _speichern([for (final x in liste) if (x.id != b.id) x]), icon: const Icon(Icons.delete_outline)),
              ]),
            ),
          if (pruefen.isNotEmpty) ...[
            const Divider(),
            Text('Zur Prüfung (${pruefen.length})', style: Theme.of(context).textTheme.titleSmall),
            for (final (datei, e) in pruefen)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(e['datei'] != null ? Icons.photo_outlined : Icons.edit_note),
                title: Text(eintragText(e)),
                subtitle: Text('${e['autor'] ?? '?'} · ${'${e['zeit'] ?? ''}'.replaceFirst('T', ' ').split('.').first}${e['raum'] != null ? ' · ${raumName[e['raum']] ?? ''}' : ''}'),
                trailing: Wrap(children: [
                  TextButton(
                    onPressed: () {
                      pruefEintragErledigen(store, datei, uebernehmen: true);
                      _s.geaendert();
                      setState(() {});
                    },
                    child: const Text('Übernehmen'),
                  ),
                  TextButton(
                    onPressed: () {
                      pruefEintragErledigen(store, datei, uebernehmen: false);
                      setState(() {});
                    },
                    child: const Text('Verwerfen'),
                  ),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}
