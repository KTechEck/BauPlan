import '../app/symbole.dart';
import 'fotos/fotos_page.dart';
import 'kosten/kosten_page.dart';
import 'export/export_page.dart';
import 'installation/installation_page.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../state/app_state.dart';
import 'assistent/assistent_page.dart';
import 'hinweise.dart';
import 'bauphysik/bauphysik_page.dart';
import 'bauteile/bauteile_page.dart';
import 'floorplan/floorplan_page.dart';
import 'haustechnik/haustechnik_page.dart';
import 'project_page.dart';
import 'settings_page.dart';
import 'tagebuch/tagebuch_page.dart';
import 'verteiler/schrank_page.dart';
import 'widgets.dart';

/// Hauptfenster: Kopfleiste, Modulleiste links, Inhalt, Statusleiste.
class Shell extends StatelessWidget {
  const Shell({super.key, required this.state});

  final AppState state;

  static const _icons = <Modul, IconData>{
    Modul.projekt: Sym.projekt,
    Modul.grundriss: Sym.grundriss,
    Modul.installation: Sym.installation,
    Modul.haustechnik: Sym.haustechnik,
    Modul.verteiler: Sym.verteiler,
    Modul.bauteile: Sym.bauteile,
    Modul.bauphysik: Sym.bauphysik,
    Modul.assistent: Sym.assistent,
    Modul.fotos: Sym.fotos,
    Modul.kosten: Sym.kosten,
    Modul.tagebuch: Sym.tagebuch,
    Modul.export: Sym.export,
    Modul.einstellungen: Sym.einstellungen,
  };

  Widget _inhalt() => switch (state.modul) {
        Modul.grundriss => FloorplanPage(state: state),
        Modul.projekt => ProjectPage(state: state),
        Modul.einstellungen => SettingsPage(state: state),
        Modul.installation => InstallationPage(state: state),
        Modul.fotos => FotosPage(state: state),
        Modul.kosten => KostenPage(state: state),
        Modul.export => ExportPage(state: state),
        Modul.haustechnik => HaustechnikPage(state: state),
        Modul.verteiler => SchrankPage(state: state),
        Modul.assistent => AssistentPage(state: state),
        Modul.tagebuch => TagebuchPage(state: state),
        Modul.bauteile => BauteilePage(state: state),
        Modul.bauphysik => BauphysikPage(state: state),
      };

  @override
  Widget build(BuildContext context) {
    final store = state.store!;
    final geschoss = state.geschossId == null ? null : store.geschoss(state.geschossId!);
    return Scaffold(
      body: Column(
        children: [
          Kopfleiste(
            titel: [store.name, if (geschoss != null) geschoss.name].join(' · '),
            rechts: [
              HinweisGlocke(state: state),
              PopupMenuButton<String>(
                tooltip: 'Editoren und Bibliotheken',
                icon: const Icon(Icons.apps, color: Color(0xFFC9CDD1)),
                onSelected: (z) {
                  switch (z) {
                    case 'wandtypen' || 'materialien' || 'sensoren':
                      state.einstellungenZiel = z;
                      state.modulWaehlen(Modul.bauteile);
                    case 'bauteile':
                      state.modulWaehlen(Modul.bauteile);
                    case 'bauphysik':
                      state.modulWaehlen(Modul.bauphysik);
                    default:
                      state.einstellungenZiel = z;
                      state.modulWaehlen(Modul.einstellungen);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(enabled: false, height: 28, child: Text('BAUTEILE UND AUFBAUTEN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                  PopupMenuItem(value: 'wandtypen', child: ListTile(dense: true, leading: Icon(Icons.layers_outlined), title: Text('Wandaufbauten'))),
                  PopupMenuItem(value: 'bauphysik', child: ListTile(dense: true, leading: Icon(Icons.thermostat_outlined), title: Text('Boden-/Deckenaufbauten, Heizlast'))),
                  PopupMenuItem(value: 'bauteile', child: ListTile(dense: true, leading: Icon(Icons.window_outlined), title: Text('Bibliothek: Bauelemente und Material'))),
                  PopupMenuItem(value: 'materialien', child: ListTile(dense: true, leading: Icon(Icons.palette_outlined), title: Text('Baustoffe und Farben'))),
                  PopupMenuItem(value: 'sensoren', child: ListTile(dense: true, leading: Icon(Icons.sensors), title: Text('Eigene Sensoren'))),
                  PopupMenuDivider(),
                  PopupMenuItem(enabled: false, height: 28, child: Text('EINSTELLUNGEN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                  PopupMenuItem(value: 'darstellung', child: ListTile(dense: true, leading: Icon(Icons.tune), title: Text('Darstellung im Plan'))),
                  PopupMenuItem(value: 'klima', child: ListTile(dense: true, leading: Icon(Icons.wb_sunny_outlined), title: Text('Standort und Klima'))),
                  PopupMenuItem(value: 'ki', child: ListTile(dense: true, leading: Icon(Icons.auto_awesome_outlined), title: Text('KI-Assistent'))),
                  PopupMenuItem(value: 'gewerke', child: ListTile(dense: true, leading: Icon(Icons.category_outlined), title: Text('Gewerke und Farben'))),
                ],
              ),
              TextButton.icon(
                onPressed: state.projektSchliessen,
                icon: const Icon(Icons.logout, color: Color(0xFFFDBA74), size: 18),
                label: const Text('Projekt schließen', style: TextStyle(color: Color(0xFFFDBA74))),
              ),
            ],
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Modulleiste(state: state, icons: _icons),
                Expanded(child: _inhalt()),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: BsFarben.rand)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(store.ordner,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                ),
                const Text('Änderungen werden sofort gespeichert',
                    style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Modulleiste extends StatelessWidget {
  const _Modulleiste({required this.state, required this.icons});

  final AppState state;
  final Map<Modul, IconData> icons;

  Widget _knopf(Modul m) {
    final aktiv = state.modul == m;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: aktiv ? BsFarben.akzent : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => state.modulWaehlen(m),
          child: SizedBox(
            height: 50,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icons[m], size: 20, color: aktiv ? BsFarben.leiste : BsFarben.leisteText),
                const SizedBox(height: 2),
                Text(
                  m.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: aktiv ? FontWeight.w600 : FontWeight.w400,
                    color: aktiv ? BsFarben.leiste : BsFarben.leisteText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Gruppen der Modulleiste (Überschrift, Module).
  static const gruppen = <(String, List<Modul>)>[
    ('', [Modul.projekt]),
    ('Planen', [Modul.grundriss, Modul.installation, Modul.haustechnik, Modul.verteiler]),
    ('Bibliothek', [Modul.bauteile, Modul.bauphysik]),
    ('Ausführen', [Modul.kosten, Modul.tagebuch, Modul.fotos]),
    ('Ausgeben', [Modul.export, Modul.assistent]),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      color: BsFarben.leisteHell,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: ListView(children: [
              for (final (titel, module) in gruppen) ...[
                if (titel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2, left: 2),
                    child: Text(titel.toUpperCase(),
                        style: const TextStyle(fontSize: 9.5, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: Color(0xFF8A9096))),
                  ),
                for (final m in module) _knopf(m),
              ],
            ]),
          ),
          const Divider(color: BsFarben.leisteRand, height: 12),
          _knopf(Modul.einstellungen),
        ],
      ),
    );
  }
}
