import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'bibliothek.dart';
import 'sensoren_page.dart';
import 'assistent/ki_einstellungen.dart';
import 'bauphysik/bauphysik_page.dart' show heizlastParameter, systemTemperaturen;
import 'tastenkuerzel.dart';
import '../core/updater.dart';
import '../app/version.dart';
import 'widgets.dart';
import 'speicher_einstellungen.dart';
import 'einstellungen_mehr.dart';
import 'package:flutter/services.dart';

enum _Bereich { allgemein, darstellung, zeichnen, ki, speicher, projekt, vorgaben, klima, gewerke, objekttypen, kennungen, benutzer, materialien, wandtypen, sensoren }

/// Einstellungen: Gewerke und Farben, Materialien, Wandtypen (Projekteinstellung).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _Bereich _bereich = _Bereich.allgemein;

  @override
  void initState() {
    super.initState();
    final ziel = state.einstellungenZiel;
    state.einstellungenZiel = null;
    _bereich = _Bereich.values.where((b) => b.name == ziel).firstOrNull ?? _Bereich.allgemein;
  }

  AppState get state => widget.state;

  Future<void> _farbeWaehlen(BuildContext context, Gewerk g) async {
    final farbe = await farbeWaehlen(context, titel: 'Farbe für ${g.name}', aktuell: g.farbe);
    if (farbe != null) {
      state.store!.gewerkAendern(g.id, farbe: farbe);
      state.geaendert();
    }
  }

  Widget _eintrag(String text, [_Bereich? b]) => _Eintrag(
        text,
        aktiv: b != null && b == _bereich,
        verfuegbar: b != null,
        onTap: b == null ? null : () => setState(() => _bereich = b),
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 260,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: BsFarben.rand)),
          ),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const _Ueberschrift('PROGRAMM · DIESER PC'),
              _eintrag('Allgemein', _Bereich.allgemein),
              _eintrag('Darstellung im Plan', _Bereich.darstellung),
              _eintrag('KI-Assistent', _Bereich.ki),
              _eintrag('Speicher und Abgleich', _Bereich.speicher),
              _eintrag('Zeichnen', _Bereich.zeichnen),
              const SizedBox(height: 12),
              const _Ueberschrift('PROJEKT'),
              _eintrag('Projekt und Geschosse', _Bereich.projekt),
              _eintrag('Planung und Vorgaben', _Bereich.vorgaben),
              _eintrag('Standort und Klima', _Bereich.klima),
              _eintrag('Gewerke und Farben', _Bereich.gewerke),
              _eintrag('Objekttypen und Symbole', _Bereich.objekttypen),
              _eintrag('Kennungen', _Bereich.kennungen),
              _eintrag('Benutzer und Rollen', _Bereich.benutzer),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('Baustoffe, Wandaufbauten und eigene Sensoren findest du jetzt in der Bibliothek.',
                    style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_bereich) {
            _Bereich.allgemein => _allgemein(context),
            _Bereich.ki => KiEinstellungenAnsicht(state: state),
            _Bereich.speicher => SpeicherEinstellungenAnsicht(state: state),
            _Bereich.darstellung => _darstellung(context),
            _Bereich.zeichnen => ZeichnenAnsicht(state: state),
            _Bereich.projekt => ProjektGeschosseAnsicht(state: state),
            _Bereich.vorgaben => VorgabenAnsicht(state: state),
            _Bereich.objekttypen => ObjekttypenAnsicht(state: state),
            _Bereich.kennungen => KennungenAnsicht(state: state),
            _Bereich.benutzer => BenutzerAnsicht(state: state),
            _Bereich.klima => _klima(context),
            _Bereich.gewerke => _gewerke(context),
            _Bereich.materialien => MaterialienAnsicht(state: state),
            _Bereich.wandtypen => WandtypenAnsicht(state: state),
            _Bereich.sensoren => SensorenAnsicht(state: state),
          },
        ),
      ],
    );
  }

  Widget _allgemein(BuildContext context) {
    final s = state.settings;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text('Programmeinstellung · gilt nur auf diesem PC',
            style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text('Allgemein', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Fenster beim Start', style: TextStyle(fontWeight: FontWeight.w600)),
              RadioGroup<String>(
                groupValue: s.fensterStart,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => s.fensterStart = v);
                  s.speichern();
                },
                child: const Column(children: [
                  RadioListTile<String>(value: 'maximiert', title: Text('immer maximiert')),
                  RadioListTile<String>(value: 'zuletzt', title: Text('so, wie es zuletzt geschlossen wurde')),
                ]),
              ),
            ]),
          ),
        ),
      ],
    );
  }


  Widget _darstellung(BuildContext context) {
    final s = state.settings;
    final d = s.darstellung;
    void setzen(String k, Object v) {
      setState(() => s.darstellung = {...d, k: v});
      s.speichern();
      state.geaendert();
    }

    double z(String k, double v) => (d[k] as num?)?.toDouble() ?? v;
    return ListView(padding: const EdgeInsets.all(28), children: [
      const Text('Programmeinstellung · gilt nur auf diesem PC', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Text('Darstellung im Plan', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Wie Geräte, Leitungen und Flächen in der Installation gezeichnet werden.'),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Maßeinheit in Plänen und Anzeigen (Eingaben bleiben in mm)')),
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
              title: const Text('Hinweis „Foto vor dem Verdecken“'),
              value: d['pflichtfoto_hinweis'] != false,
              onChanged: (v) => setzen('pflichtfoto_hinweis', v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bauablauf-Hinweise (dezent, in der Projektprüfung)'),
              value: state.store?.einstellung<bool>('bauablauf_aus') != true,
              onChanged: state.store == null
                  ? null
                  : (v) {
                      state.store!.einstellungSetzen('bauablauf_aus', !v);
                      state.geaendert();
                      setState(() {});
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Eigenleistung / Lohnanteil in den Kosten zeigen'),
              value: d['eigenleistung_aus'] != true,
              onChanged: (v) => setzen('eigenleistung_aus', !v),
            ),
            TextButton.icon(
              onPressed: () => tastenkuerzelZeigen(context, einstellungen: s),
              icon: const Icon(Icons.keyboard_outlined, size: 18),
              label: const Text('Tastenkürzel anpassen …'),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Programm-Update ($bauspurBuild)', style: TextStyle(fontWeight: FontWeight.w600)),
            const Text('Neue Versionen aus einem Ordner (OneDrive, NAS, USB). Jede Datei wird per SHA-256 geprüft, das Programm vorher gesichert.',
                style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            Row(children: [
              Expanded(child: Text(d['update_quelle'] == null ? 'Keine Update-Quelle gewählt' : 'Quelle: ${d['update_quelle']}', style: const TextStyle(fontSize: 13))),
              TextButton(
                onPressed: () async {
                  final o = await getDirectoryPath(confirmButtonText: 'Update-Quelle');
                  if (o != null) setzen('update_quelle', o);
                },
                child: const Text('Ordner …'),
              ),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: d['update_quelle'] == null
                    ? null
                    : () async {
                        final u = updateSuchen('${d['update_quelle']}', bauspurBuild);
                        if (u == null) {
                          zeigeHinweis(context, 'Keine neuere Version in der Quelle.');
                          return;
                        }
                        final fehler = await updatePruefen(u);
                        if (!context.mounted) return;
                        if (fehler.isNotEmpty) {
                          zeigeFehler(context, 'Update nicht vollständig: ${fehler.take(3).join(', ')}');
                          return;
                        }
                        final ok = await frage(context,
                            titel: '${u.build} installieren?',
                            text: 'Alle ${u.dateien.length} Dateien sind geprüft. BauSpur wird gesichert, beendet, aktualisiert und neu gestartet.',
                            ja: 'Aktualisieren');
                        if (!ok) return;
                        final v = await updateVorbereiten(u, aktuell: bauspurBuild);
                        await updateStarten(v.skript);
                        exit(0);
                      },
                icon: const Icon(Icons.system_update_alt, size: 18),
                label: const Text('Nach Update suchen'),
              ),
              OutlinedButton.icon(
                onPressed: d['update_quelle'] == null
                    ? null
                    : () async {
                        final quelle = '${d['update_quelle']}';
                        final ziel = File(Platform.resolvedExecutable).parent.path;
                        if (p.equals(quelle, ziel)) {
                          await updateManifestSchreiben(quelle, bauspurBuild);
                        } else {
                          for (final f in Directory(ziel).listSync(recursive: true).whereType<File>()) {
                            final n = File(p.join(quelle, p.relative(f.path, from: ziel)));
                            n.parent.createSync(recursive: true);
                            f.copySync(n.path);
                          }
                          await updateManifestSchreiben(quelle, bauspurBuild);
                        }
                        if (context.mounted) zeigeHinweis(context, '$bauspurBuild als Update in der Quelle bereitgestellt.');
                      },
                icon: const Icon(Icons.publish_outlined, size: 18),
                label: const Text('Diese Version bereitstellen'),
              ),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Symbolgröße ${(z('groesse', 1) * 100).round()} %'),
            Slider(value: z('groesse', 1).clamp(0.6, 2.0), min: 0.6, max: 2.0, divisions: 14, onChanged: (v) => setzen('groesse', v)),
            Text('Deckkraft der Symbole ${(z('deckkraft', 1) * 100).round()} %'),
            Slider(value: z('deckkraft', 1).clamp(0.2, 1.0), min: 0.2, max: 1, divisions: 8, onChanged: (v) => setzen('deckkraft', v)),
            Text('Deckkraft der Flächen (Heizkreise, Zonen) ${(z('flaeche', 0.15) * 100).round()} %'),
            Slider(value: z('flaeche', 0.15).clamp(0.0, 0.6), min: 0, max: 0.6, divisions: 12, onChanged: (v) => setzen('flaeche', v)),
            const SizedBox(height: 8),
            Wrap(spacing: 24, runSpacing: 12, children: [
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String>(
                  initialValue: d['text'] as String? ?? 'kennung',
                  decoration: const InputDecoration(labelText: 'Beschriftung'),
                  items: const [
                    DropdownMenuItem(value: 'kennung', child: Text('Kürzel im Symbol + Kennung')),
                    DropdownMenuItem(value: 'kennung_hoehe', child: Text('Kürzel + Kennung + Höhe')),
                    DropdownMenuItem(value: 'kuerzel', child: Text('nur Kürzel im Symbol')),
                    DropdownMenuItem(value: 'keiner', child: Text('keine Beschriftung')),
                  ],
                  onChanged: (v) => setzen('text', v ?? 'kennung'),
                ),
              ),
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String>(
                  initialValue: d['form'] as String? ?? 'kreis',
                  decoration: const InputDecoration(labelText: 'Symbolform'),
                  items: const [
                    DropdownMenuItem(value: 'kreis', child: Text('Kreis')),
                    DropdownMenuItem(value: 'quadrat', child: Text('Quadrat')),
                  ],
                  onChanged: (v) => setzen('form', v ?? 'kreis'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _klima(BuildContext context) {
    final store = state.store!;
    final p = heizlastParameter(store);
    final (vl, rl) = systemTemperaturen(store);
    void setzen(String k, String v) {
      final z = num.tryParse(v.replaceAll(',', '.'));
      final m = Map<String, dynamic>.from(store.einstellung<Map>('heizlast') ?? const {});
      if (z == null) {
        m.remove(k);
      } else {
        m[k] = z;
      }
      store.einstellungSetzen('heizlast', m);
      state.geaendert();
      setState(() {});
    }

    Widget zahl(String label, String k, num wert, String einheit, {String? hilfe}) => SizedBox(
          width: 300,
          child: SpeicherFeld(
            key: ValueKey('klima-$k-$wert'),
            initialValue: '$wert'.replaceAll('.', ','),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]'))],
            decoration: InputDecoration(labelText: label, suffixText: einheit, helperText: hilfe),
            onFieldSubmitted: (v) => setzen(k, v),
          ),
        );
    return ListView(padding: const EdgeInsets.all(28), children: [
      const Text('Projekteinstellung', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Text('Standort und Klima', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Werte für Heizlast und Heizflächen. Die Norm-Außentemperatur steht für jeden Ort in DIN/TS 12831-1 (Postleitzahl-Tabelle).'),
      const SizedBox(height: 16),
      Wrap(spacing: 20, runSpacing: 14, children: [
        zahl('Norm-Außentemperatur θe', 'theta_e', p.normAussen, '°C', hilfe: 'z. B. −12 °C (Mitteldeutschland), −16 °C (Bayern)'),
        zahl('Jahresmitteltemperatur', 'theta_m', p.jahresmittel, '°C', hilfe: 'für Bauteile gegen Erdreich'),
        zahl('Temperatur unbeheizter Räume', 'unbeheizt', p.unbeheizt, '°C', hilfe: 'Keller, Dachboden, Garage'),
        zahl('Wärmebrückenzuschlag ΔU_WB', 'delta_uwb', p.deltaUwb, 'W/(m²K)', hilfe: '0,05 bei Detailnachweis, 0,10 pauschal'),
        zahl('Vorlauftemperatur', 'vorlauf', vl, '°C', hilfe: 'Auslegung Heizkörper'),
        zahl('Rücklauftemperatur', 'ruecklauf', rl, '°C'),
        zahl('Luftdichtheit n50', 'n50', p.n50, '1/h', hilfe: '0 = nur Mindestluftwechsel; Bestand 4–6, saniert 1,5–3, Neubau ≤ 1,5'),
        zahl('Lüftungsanlage: Wärmerückgewinnung', 'wrg', (p.wrg * 100).round(), '%', hilfe: '0 = keine Anlage, sonst z. B. 80'),
        zahl('Aufheizzuschlag', 'aufheiz', p.aufheiz, 'W/m²', hilfe: '0 = ohne; 8–12 nach Nachtabsenkung'),
      ]),
    ]);
  }
  Widget _gewerke(BuildContext context) {
    final store = state.store!;
    final gewerke = store.gewerke();
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text('Projekteinstellung · gilt für alle Geräte und Nutzer',
            style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Text('Gewerke und Farben', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Die Farbe eines Gewerks gilt überall: Ebenen im Grundriss, Wandansicht, Kosten und Fotos.'),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              for (final g in gewerke)
                ListTile(
                  leading: Farbfeld(g.farbe, groesse: 28, onTap: () => _farbeWaehlen(context, g)),
                  title: Text(g.name),
                  subtitle: Text('${g.kuerzel} · ${store.anzahlObjekttypen(g.id)} Objekttypen'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('beim Start sichtbar', style: TextStyle(fontSize: 12)),
                      Switch(
                        value: g.sichtbar,
                        onChanged: (v) {
                          store.gewerkAendern(g.id, sichtbar: v);
                          state.geaendert();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Ueberschrift extends StatelessWidget {
  const _Ueberschrift(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
        child: Text(text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: BsFarben.textLeise)),
      );
}

class _Eintrag extends StatelessWidget {
  const _Eintrag(this.text, {required this.aktiv, required this.verfuegbar, this.onTap});
  final String text;
  final bool aktiv;
  final bool verfuegbar;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: aktiv ? BsFarben.akzentHell : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Text(text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: aktiv ? FontWeight.w600 : FontWeight.w400,
                    color: aktiv ? BsFarben.akzentDunkel : (verfuegbar ? null : const Color(0xFF9AA0A6)),
                  )),
            ),
          ),
        ),
      );
}
