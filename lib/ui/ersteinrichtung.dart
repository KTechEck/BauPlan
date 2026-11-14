import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/theme.dart';
import '../data/app_settings.dart';
import '../data/project_store.dart';
import '../state/app_state.dart';
import 'tastenkuerzel.dart';
import 'widgets.dart';

/// Projekteinstellungen, die als Vorlage taugen (allgemeine Vorgaben, keine
/// Projektdaten wie Bestand, Einkäufe, Aufmaß oder Schemata).
const vorlagenSchluessel = [
  'auslegung', 'wdvs', 'kennung', 'objekt_vorgaben', 'verlegeebenen', 'regeln', 'revision_reichweite', 'bohr_radius', 'bohr_sicherheit',
  'verschnitt_prozent', 'abgleich', 'heizlast', 'aufbauten', 'ecken_verbinden', 'mass_anzeige', 'dicke_fest', 'werkzeug', 'eigene_symbole',
  'symbol_zuordnung', 'plankopf', 'ausstattungswert', 'norden_grad', 'klima', 'licht_ziel', 'lichtszenen', 'sensoren', 'deckendicke', 'bauablauf_aus',
];

Directory vorlagenOrdner(AppSettings s) => Directory(p.join(s.ordner.path, 'vorlagen'));

/// Aktuelle Projekteinstellungen als Vorlage speichern.
Future<String> einstellungenAlsVorlage(AppState s, String name) async {
  final store = s.store!;
  final daten = <String, Object?>{
    for (final k in vorlagenSchluessel)
      if (store.einstellung<Object>(k) != null) k: store.einstellung<Object>(k),
  };
  final pk = Map<String, dynamic>.from(daten['plankopf'] as Map? ?? const {})..remove('adresse');
  if (pk.isNotEmpty) daten['plankopf'] = pk;
  final ordner = vorlagenOrdner(s.settings);
  await ordner.create(recursive: true);
  final f = File(p.join(ordner.path, '${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.json'));
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert({'format': 'bauspur-vorlage', 'name': name, 'einstellungen': daten}));
  return f.path;
}

/// Vorlage auf ein (neues) Projekt anwenden.
void vorlageAnwenden(ProjectStore store, String datei) {
  final j = jsonDecode(File(datei).readAsStringSync()) as Map<String, dynamic>;
  for (final e in (j['einstellungen'] as Map? ?? const {}).entries) {
    if (vorlagenSchluessel.contains(e.key)) store.einstellungSetzen('${e.key}', e.value);
  }
}

List<File> vorlagenListe(AppSettings s) {
  final o = vorlagenOrdner(s);
  if (!o.existsSync()) return const [];
  return [for (final f in o.listSync().whereType<File>()) if (f.path.endsWith('.json')) f]..sort((a, b) => a.path.compareTo(b.path));
}

/// Ersteinrichtung beim ersten Start (jederzeit wieder aufrufbar): Maßeinheit,
/// Hinweise, Fensterstart, Ordner für Inhaltspakete, Tastenkürzel.
Future<void> ersteinrichtung(BuildContext context, AppState s) async {
  final st = s.settings;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      final d = st.darstellung;
      void setzen(String k, Object? v) {
        v == null ? d.remove(k) : d[k] = v;
        st.speichern();
        setD(() {});
      }

      return AlertDialog(
        title: const Text('Willkommen bei BauSpur'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ein paar Grundeinstellungen – alles lässt sich später unter Einstellungen ändern.', style: TextStyle(color: BsFarben.textLeise)),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(child: Text('Maßeinheit in Plänen')),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'mm', label: Text('mm')), ButtonSegment(value: 'cm', label: Text('cm')), ButtonSegment(value: 'm', label: Text('m'))],
                  selected: {d['einheit'] as String? ?? 'mm'},
                  onSelectionChanged: (v) {
                    MassEinheit.setzen(v.first);
                    setzen('einheit', v.first);
                  },
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hilfetexte anzeigen'),
                value: st.hilfeAnzeigen,
                onChanged: (v) {
                  st.hilfeAnzeigen = v;
                  st.speichern();
                  setD(() {});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hinweis „Foto vor dem Verdecken“'),
                value: d['pflichtfoto_hinweis'] != false,
                onChanged: (v) => setzen('pflichtfoto_hinweis', v),
              ),
              Row(children: [
                const Expanded(child: Text('Fenster beim Start')),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'maximiert', label: Text('maximiert')), ButtonSegment(value: 'zuletzt', label: Text('wie zuletzt'))],
                  selected: {st.fensterStart == 'zuletzt' ? 'zuletzt' : 'maximiert'},
                  onSelectionChanged: (v) {
                    st.fensterStart = v.first;
                    st.speichern();
                    setD(() {});
                  },
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(d['pakete_ordner'] == null
                      ? 'Inhaltspakete automatisch laden: aus (Ordner wählen, z. B. auf dem NAS oder in OneDrive)'
                      : 'Inhaltspakete automatisch aus: ${d['pakete_ordner']}'),
                ),
                TextButton(
                  onPressed: () async {
                    final o = await getDirectoryPath(confirmButtonText: 'Ordner wählen');
                    if (o != null) setzen('pakete_ordner', o);
                  },
                  child: const Text('Ordner …'),
                ),
                if (d['pakete_ordner'] != null) TextButton(onPressed: () => setzen('pakete_ordner', null), child: const Text('aus')),
              ]),
              TextButton.icon(
                onPressed: () => tastenkuerzelZeigen(c, einstellungen: st),
                icon: const Icon(Icons.keyboard_outlined, size: 18),
                label: const Text('Tastenkürzel ansehen / anpassen'),
              ),
              const SizedBox(height: 6),
              const Text('KI-Assistent (lokal, Ollama), Speicherort und Home Assistant richtest du unter Einstellungen ein.',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            ]),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              d['ersteinrichtung'] = true;
              st.speichern();
              Navigator.pop(c);
            },
            child: const Text('Los geht’s'),
          ),
        ],
      );
    }),
  );
  s.geaendert();
}
