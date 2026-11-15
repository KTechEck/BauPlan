import '../app/symbole.dart';
import 'fotos/fotos_page.dart';
import 'kosten/kosten_page.dart';
import 'einkauf/einkauf_page.dart';
import 'export/export_page.dart';
import 'installation/installation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ipad/ipad_projekt.dart' show projektZumPc;
import '../core/ipad_austausch.dart' show Ausleihe;

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
import 'suche.dart';
import 'hilfe_panel.dart';
import 'widgets.dart';
import '../data/tagebuch_models.dart';
import '../app/version.dart';

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
    Modul.einkauf: Icons.shopping_cart_outlined,
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
        Modul.einkauf => EinkaufPage(state: state),
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
    hilfePanelLaden(state);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => sucheOeffnen(context, state),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => sucheOeffnen(context, state),
      },
      child: Scaffold(
      body: Column(
        children: [
          Kopfleiste(
            titel: [store.name, if (geschoss != null) geschoss.name].join(' · '),
            rechts: [
              IconButton(
                tooltip: 'Suchen (Strg+F)',
                onPressed: () => sucheOeffnen(context, state),
                icon: const Icon(Icons.search, color: Color(0xFFC9CDD1)),
              ),
              HinweisGlocke(state: state),
              ValueListenableBuilder<bool>(
                valueListenable: hilfePanelOffen,
                builder: (_, offen, __) => IconButton(
                  tooltip: offen ? 'Hilfe ausblenden' : 'Hilfe: Begriffe und Werte erklärt (rechts)',
                  onPressed: () => hilfePanelUmschalten(state),
                  icon: Icon(offen ? Icons.help : Icons.help_outline, color: const Color(0xFFC9CDD1)),
                ),
              ),
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
              if (state.touch)
                TextButton.icon(
                  onPressed: () => projektZumPc(context, state),
                  icon: const Icon(Icons.upload_outlined, color: Color(0xFFC9CDD1), size: 18),
                  label: const Text('An PC zurückgeben', style: TextStyle(color: Color(0xFFC9CDD1))),
                ),
              TextButton.icon(
                onPressed: state.projektSchliessen,
                icon: const Icon(Icons.logout, color: Color(0xFFFDBA74), size: 18),
                label: const Text('Projekt schließen', style: TextStyle(color: Color(0xFFFDBA74))),
              ),
            ],
          ),
          if (store.nurLesen)
            Builder(builder: (context) {
              final a = Ausleihe.lesen(store.ordner);
              return Material(
                color: const Color(0xFFFEF3C7),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.lock_outline, color: Color(0xFFB45309)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a?.text ?? 'Projekt ist nur lesbar.', style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w600))),
                    if (a?.amPc ?? false)
                      TextButton(
                        onPressed: () async {
                          final ok = await frage(context,
                              titel: 'Ausleihe aufheben?',
                              text: 'Nur wenn das iPad das Projekt nicht mehr zurückgeben kann (verloren, kaputt, Stand verworfen). '
                                  'Alles, was auf dem iPad seit der Ausleihe geändert wurde, geht dann verloren.',
                              ja: 'Aufheben');
                          if (ok) state.ausleiheAufheben();
                        },
                        child: const Text('Ausleihe aufheben …'),
                      ),
                  ]),
                ),
              );
            }),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Modulleiste(state: state, icons: _icons),
                Expanded(child: _inhalt()),
                ValueListenableBuilder<bool>(
                  valueListenable: hilfePanelOffen,
                  builder: (_, offen, __) => offen ? HilfePanel(state: state) : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          if (!state.touch)
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: BsFarben.rand)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _Statusleiste(state: state),
          ),
        ],
      ),
    ));
  }
}

/// Statusleiste: Projektordner, Geschoss, Mengen, offene Aufgaben/Mängel,
/// Maßeinheit, Benutzer, PC-Dienst, Build, Speichern.
class _Statusleiste extends StatelessWidget {
  const _Statusleiste({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final store = state.store!;
    const stil = TextStyle(fontSize: 12, color: BsFarben.textLeise);
    final g = state.geschossId == null ? null : store.geschoss(state.geschossId!);
    final aufgaben = store.aufgaben().where((a) => a.status != AufgabenStatus.erledigt).toList();
    final maengel = aufgaben.where((a) => a.art == 'mangel').length;
    final raeume = g == null ? 0 : store.raeume(g.id).length;
    final objekte = g == null ? 0 : store.objekte(g.id).length;
    Widget teil(IconData i, String t, {String? tip}) => Tooltip(
          message: tip ?? t,
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 13, color: BsFarben.textLeise), const SizedBox(width: 4), Text(t, style: stil)]),
          ),
        );
    return Row(children: [
      Expanded(child: Tooltip(message: store.ordner, child: Text(store.ordner, overflow: TextOverflow.ellipsis, style: stil))),
      if (g != null) teil(Icons.layers_outlined, '${g.kuerzel} · $raeume Räume · $objekte Objekte', tip: 'aktuelles Geschoss'),
      teil(Icons.checklist, '${aufgaben.length} offen${maengel > 0 ? ', $maengel Mängel' : ''}', tip: 'offene Aufgaben und Mängel (Tagebuch)'),
      teil(Icons.straighten, MassEinheit.aktuell, tip: 'Maßeinheit (Einstellungen › Darstellung)'),
      teil(Icons.person_outline, store.benutzer, tip: 'Benutzer'),
      if (store.nurLesen) teil(Icons.lock_outline, 'nur lesen', tip: 'Projekt ausgeliehen oder schreibgeschützt'),
      teil(Icons.verified_outlined, bauspurBuild),
      teil(Icons.save_outlined, 'gespeichert', tip: 'Änderungen werden sofort gespeichert'),
    ]);
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
    ('Ausführen', [Modul.kosten, Modul.einkauf, Modul.tagebuch, Modul.fotos]),
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
