import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/ki.dart';
import '../../core/ki_einrichtung.dart' show Hardware;
import '../../state/app_state.dart';
import '../widgets.dart';
import 'ki_einrichtung_karte.dart';

/// Einstellungen des KI-Assistenten (Einrichtung, Sprachmodell, Cloud) und
/// die Prüfregeln des Projekts – liegen unter Einstellungen.
class KiEinstellungenAnsicht extends StatefulWidget {
  const KiEinstellungenAnsicht({super.key, required this.state, this.anbieter, this.hardware, this.modelle});
  final AppState state;
  final KiAnbieter? anbieter;
  final Future<Hardware> Function()? hardware;
  final Future<List<String>?> Function(String adresse)? modelle;

  @override
  State<KiEinstellungenAnsicht> createState() => _KiEinstellungenAnsichtState();
}

class _KiEinstellungenAnsichtState extends State<KiEinstellungenAnsicht> {
  bool _laeuft = false;
  AppState get _s => widget.state;
  KiEinstellung get _einstellung => KiEinstellung.ausJson(_s.settings.ki);
  KiAnbieter get _anbieter => widget.anbieter ?? OllamaAnbieter(_einstellung);
  Regelwerte get _regeln => Regelwerte.ausJson(_s.store!.einstellung<Map>('regeln')?.cast<String, dynamic>());

  @override
  Widget build(BuildContext context) => _einstellungen();

  Widget _einstellungen() {
    final e = _einstellung;
    final r = _regeln;
    void ki(KiEinstellung neu) {
      _s.settings.ki = {...?_s.settings.ki, ...neu.toJson()};
      _s.settings.speichern();
      setState(() {});
    }

    void regel(Regelwerte neu) {
      _s.store!.einstellungSetzen('regeln', neu.toJson());
      _s.geaendert();
    }

    Widget zahl(String label, int wert, String einheit, void Function(int) setzen) => SizedBox(
          width: 260,
          child: SpeicherFeld(
            key: ValueKey('$label-$wert'),
            initialValue: '$wert',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, suffixText: einheit),
            onFieldSubmitted: (v) => setzen(int.tryParse(v) ?? wert),
          ),
        );

    return ListView(padding: const EdgeInsets.all(20), children: [
      KiEinrichtungKarte(state: _s, hardware: widget.hardware, modelle: widget.modelle),
      const SizedBox(height: 20),
      Text('Sprachmodell (dieser PC)', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text(
          'Standard ist ein lokales Modell im Heimnetz mit Ollama-kompatibler Schnittstelle, z. B. auf einem PC mit Grafikkarte. '
          'Auf der Synology wäre es zu langsam.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      SizedBox(
        width: 420,
        child: SpeicherFeld(
          key: ValueKey('adr-${e.adresse}'),
          initialValue: e.adresse,
          decoration: InputDecoration(
            labelText: 'Adresse',
            helperText: e.lokal ? 'im Heimnetz' : 'außerhalb des Heimnetzes – nur mit eingeschaltetem Cloud-Dienst',
          ),
          onFieldSubmitted: (v) => ki(KiEinstellung(adresse: v.trim(), modell: e.modell, cloudErlaubt: e.cloudErlaubt)),
        ),
      ),
      SizedBox(
        width: 420,
        child: SpeicherFeld(
          key: ValueKey('mod-${e.modell}'),
          initialValue: e.modell,
          decoration: const InputDecoration(labelText: 'Modell', helperText: 'z. B. llama3.1:8b, qwen2.5:14b; für Bilder ein Modell mit Bildverstehen'),
          onFieldSubmitted: (v) => ki(KiEinstellung(adresse: e.adresse, modell: v.trim(), cloudErlaubt: e.cloudErlaubt)),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Cloud-Dienst erlauben'),
        subtitle: const Text('Aus = nur Heimnetz. An = vor jedem Senden wird gezeigt, was das Heimnetz verlässt.'),
        value: e.cloudErlaubt,
        onChanged: (v) => ki(KiEinstellung(adresse: e.adresse, modell: e.modell, cloudErlaubt: v)),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _laeuft
              ? null
              : () async {
                  setState(() {
                    _laeuft = true;

                  });
                  try {
                    final a = await _anbieter.fragen(kiSystem, 'Antworte nur mit: bereit');
                    if (mounted) zeigeHinweis(context, 'Verbindung steht: $a');
                  } catch (x) {
                    if (mounted) zeigeFehler(context, 'Keine Verbindung: $x');
                  } finally {
                    if (mounted) setState(() => _laeuft = false);
                  }
                },
          icon: const Icon(Icons.wifi_tethering, size: 18),
          label: const Text('Verbindung testen'),
        ),
      ),
      const Divider(height: 40),
      Text('Eigene Regeln (Projekt)', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 16, runSpacing: 8, children: [
        zahl('Höchste Heizkreislänge', r.maxKreislaengeM, 'm',
            (v) => regel(Regelwerte(maxKreislaengeM: v, minReserveSchrank: r.minReserveSchrank, minAbstandWasserElektro: r.minAbstandWasserElektro, lichtAnteilZiel: r.lichtAnteilZiel))),
        zahl('Mindestreserve im Verteiler', r.minReserveSchrank, '%',
            (v) => regel(Regelwerte(maxKreislaengeM: r.maxKreislaengeM, minReserveSchrank: v, minAbstandWasserElektro: r.minAbstandWasserElektro, lichtAnteilZiel: r.lichtAnteilZiel))),
        zahl('Abstand Elektro unter Wasser', r.minAbstandWasserElektro, 'mm',
            (v) => regel(Regelwerte(maxKreislaengeM: r.maxKreislaengeM, minReserveSchrank: r.minReserveSchrank, minAbstandWasserElektro: v, lichtAnteilZiel: r.lichtAnteilZiel))),
        zahl('Licht: Hinweis unter … des Zielwerts', r.lichtAnteilZiel, '%',
            (v) => regel(Regelwerte(maxKreislaengeM: r.maxKreislaengeM, minReserveSchrank: r.minReserveSchrank, minAbstandWasserElektro: r.minAbstandWasserElektro, lichtAnteilZiel: v))),
      ]),
      const SizedBox(height: 12),
      const Text(
          'Normtexte (DIN, VDE) werden nicht mitgeliefert. Wer sie besitzt, kann daraus eigene Grenzwerte ableiten. '
          'Elektro-, Gas- und Kältetechnik bleiben in der Verantwortung der jeweiligen Fachkraft.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
    ]);
  }
}
