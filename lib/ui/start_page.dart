import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../app/theme.dart';
import '../data/project_store.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Startseite: zuletzt geöffnete Projekte, neues Projekt, Projekt öffnen.
class StartPage extends StatelessWidget {
  const StartPage({super.key, required this.state});

  final AppState state;

  Future<void> _oeffnen(BuildContext context, String ordner) async {
    if (!ProjectStore.istProjektordner(ordner)) {
      zeigeFehler(context, '„$ordner“ ist kein BauSpur-Projekt oder nicht erreichbar.');
      return;
    }
    final sperre = Sperre.lesen(ordner);
    if (sperre != null && !sperre.istDieserRechner) {
      final weiter = await frage(
        context,
        titel: 'Projekt ist schon geöffnet',
        text: 'Das Projekt ist auf „${sperre.rechner}“ (${sperre.benutzer}) geöffnet, '
            'seit ${sperre.seit}.\n\nWenn dort noch gearbeitet wird, können Änderungen verloren gehen. '
            'Trotzdem öffnen?',
        ja: 'Trotzdem öffnen',
      );
      if (!weiter) return;
    }
    try {
      state.projektOeffnen(ProjectStore.oeffnen(ordner));
    } catch (e) {
      if (context.mounted) zeigeFehler(context, 'Öffnen fehlgeschlagen: $e');
    }
  }

  /// Auf iPhone/iPad gibt es keine freie Ordnerwahl: Projekte liegen im
  /// Dokumente-Ordner der App (über die Dateien-App erreichbar).
  static bool get _mobil => Platform.isIOS || Platform.isAndroid;

  Future<String?> _ordner(String knopf) async {
    if (_mobil) return (await getApplicationDocumentsDirectory()).path;
    return getDirectoryPath(confirmButtonText: knopf);
  }

  Future<void> _ordnerWaehlen(BuildContext context) async {
    if (_mobil) {
      final basis = Directory((await getApplicationDocumentsDirectory()).path);
      final projekte = [for (final d in basis.listSync().whereType<Directory>()) if (ProjectStore.istProjektordner(d.path)) d.path];
      if (!context.mounted) return;
      final wahl = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Projekt öffnen'),
          children: [
            if (projekte.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Noch keine Projekte auf diesem Gerät.')),
            for (final p in projekte) SimpleDialogOption(onPressed: () => Navigator.pop(c, p), child: Text(p.split(Platform.pathSeparator).last)),
          ],
        ),
      );
      if (wahl == null || !context.mounted) return;
      await _oeffnen(context, wahl);
      return;
    }
    final ordner = await getDirectoryPath(confirmButtonText: 'Projekt öffnen');
    if (ordner == null || !context.mounted) return;
    await _oeffnen(context, ordner);
  }

  Future<void> _neu(BuildContext context) async {
    final name = await texteingabe(context, titel: 'Neues Projekt', feld: 'Projektname', vorschlag: 'Wohnhaus');
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final eltern = await _ordner('Hier anlegen');
    if (eltern == null || !context.mounted) return;
    try {
      state.projektOeffnen(ProjectStore.anlegen(elternOrdner: eltern, projektName: name));
    } catch (e) {
      if (context.mounted) zeigeFehler(context, 'Anlegen fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final zuletzt = state.settings.zuletztGeoeffnet;
    return Scaffold(
      body: Column(
        children: [
          const Kopfleiste(titel: ''),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(32),
                  children: [
                    Text('Projekte', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 16),
                    if (zuletzt.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text('Noch kein Projekt geöffnet. Lege ein neues an, '
                            'z. B. auf der Synology unter \\\\NAS\\BauSpur.'),
                      ),
                    for (final ordner in zuletzt)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.home_work_outlined, color: BsFarben.akzentDunkel),
                          title: Text(p.basename(ordner)),
                          subtitle: Text(ordner),
                          trailing: IconButton(
                            tooltip: 'Aus Liste entfernen',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              state.settings.vergissProjekt(ordner);
                              state.geaendert();
                            },
                          ),
                          enabled: Directory(ordner).existsSync(),
                          onTap: () => _oeffnen(context, ordner),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _neu(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Neues Projekt'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _ordnerWaehlen(context),
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Projektordner öffnen …'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
