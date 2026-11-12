import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'bibliothek.dart';
import 'sensoren_page.dart';
import 'assistent/ki_einstellungen.dart';
import 'bauphysik/bauphysik_page.dart' show heizlastParameter, systemTemperaturen;
import 'widgets.dart';
import 'speicher_einstellungen.dart';
import 'package:flutter/services.dart';

enum _Bereich { allgemein, darstellung, ki, speicher, klima, gewerke, materialien, wandtypen, sensoren }

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
              _eintrag('Zeichnen'),
              const SizedBox(height: 12),
              const _Ueberschrift('PROJEKT'),
              _eintrag('Projekt und Geschosse'),
              _eintrag('Standort und Klima', _Bereich.klima),
              _eintrag('Gewerke und Farben', _Bereich.gewerke),
              _eintrag('Objekttypen und Symbole'),
              _eintrag('Kennungen'),
              _eintrag('Benutzer und Rollen'),
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
