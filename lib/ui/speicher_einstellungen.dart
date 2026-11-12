import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/theme.dart';
import '../core/speicher.dart';
import '../data/austausch.dart';
import '../state/app_state.dart';

/// Einstellungen › Speicher und Abgleich: wo die Daten für die Mobil-App
/// liegen (nur dieser PC, Heimnetz, Cloud) und wie sich die App verbindet.
class SpeicherEinstellungenAnsicht extends StatefulWidget {
  const SpeicherEinstellungenAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<SpeicherEinstellungenAnsicht> createState() => _SpeicherEinstellungenState();
}

class _SpeicherEinstellungenState extends State<SpeicherEinstellungenAnsicht> {
  AppState get state => widget.state;
  late final _pfad = TextEditingController(text: state.speicher.netzPfad);
  late final _url = TextEditingController(text: state.speicher.url);
  late final _benutzer = TextEditingController(text: state.speicher.benutzer);
  late final _passwort = TextEditingController(text: state.speicher.passwort);
  late final _port = TextEditingController(text: '${state.speicher.port}');
  List<String> _adressen = [];
  String? _ergebnis;
  bool _ergebnisGut = false, _prueft = false;

  @override
  void initState() {
    super.initState();
    eigeneAdressen().then((a) {
      if (mounted) setState(() => _adressen = a);
    });
  }

  @override
  void dispose() {
    for (final c in [_pfad, _url, _benutzer, _passwort, _port]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _setzen(Map<String, dynamic> neu) async {
    state.settings.speicher = {...state.settings.speicher, ...neu};
    state.settings.speichern();
    setState(() {});
    await state.speicherAnwenden();
    if (mounted) setState(() {});
  }

  /// Eingaben übernehmen und den gewählten Speicher wirklich ansprechen.
  Future<void> _pruefen() async {
    setState(() {
      _prueft = true;
      _ergebnis = null;
    });
    await _setzen({'netz_pfad': _pfad.text.trim(), 'url': _url.text.trim(), 'benutzer': _benutzer.text.trim(), 'passwort': _passwort.text});
    final s = state.speicher;
    String text;
    var gut = false;
    try {
      if (s.art == 'netz') {
        if (s.netzPfad.isEmpty) {
          text = 'Bitte einen Netzwerkordner angeben.';
        } else {
          final probe = File(p.join(s.netzPfad, '.bauspur_probe'));
          await probe.writeAsString('ok').timeout(const Duration(seconds: 6));
          await probe.delete();
          gut = true;
          text = 'Netzwerkordner erreichbar und beschreibbar.';
        }
      } else if (s.art == 'cloud') {
        if (s.url.isEmpty) {
          text = 'Bitte die WebDAV-Adresse angeben.';
        } else {
          final dav = WebDavSpeicher(s.url, benutzer: s.benutzer, passwort: s.passwort, unsicher: s.unsicher);
          gut = await dav.schreiben('.bauspur_probe', 'ok'.codeUnits);
          if (gut) await dav.loeschen('.bauspur_probe');
          text = gut ? 'Cloud-Speicher erreichbar und beschreibbar.' : 'Der Speicher antwortet, nimmt aber keine Datei an (Adresse, Benutzer oder Passwort prüfen).';
        }
      } else {
        gut = state.dienst.laeuft;
        text = gut ? 'BauSpur ist im Heimnetz erreichbar.' : 'Der Dienst läuft nicht: ${state.dienst.fehler ?? 'ausgeschaltet'}';
      }
    } catch (e) {
      text = 'Nicht erreichbar: $e';
    }
    if (!mounted) return;
    setState(() {
      _prueft = false;
      _ergebnis = text;
      _ergebnisGut = gut;
    });
  }

  Widget _art(String wert, IconData symbol, String titel, String text) => RadioListTile<String>(
        value: wert,
        secondary: Icon(symbol, color: BsFarben.akzent),
        title: Text(titel, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(text),
      );

  @override
  Widget build(BuildContext context) {
    final s = state.speicher;
    final store = state.store;
    const leise = TextStyle(fontSize: 12, color: BsFarben.textLeise);
    final adresse = _adressen.isEmpty ? 'dieser PC' : _adressen.map((a) => s.port == bauspurPort ? a : '$a:${s.port}').join(' oder ');
    return ListView(padding: const EdgeInsets.all(28), children: [
      const Text('Programmeinstellung · gilt nur auf diesem PC', style: leise),
      Text('Speicher und Abgleich', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Hier legst du fest, wo der Planstand für die Mobil-App liegt und wohin die App ihre Erfassungen schickt. '
          'Das Projekt selbst bleibt immer vollständig auf diesem PC.'),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: RadioGroup<String>(
            groupValue: s.art,
            onChanged: (v) {
              if (v != null) {
                _ergebnis = null;
                _setzen({'art': v});
              }
            },
            child: Column(children: [
              _art('pc', Icons.computer_outlined, 'Nur dieser PC',
                  'Nichts verlässt den PC. Die App gleicht im WLAN direkt mit BauSpur ab, solange das Programm läuft. Keine Einrichtung nötig.'),
              _art('netz', Icons.dns_outlined, 'Heimnetz: NAS oder Netzwerkrechner',
                  'Planstand und Erfassungen liegen in einem Netzwerkordner. Die App kann auch abgleichen, wenn dieser PC aus ist.'),
              _art('cloud', Icons.cloud_outlined, 'Cloud',
                  'Abgleich über einen Online-Speicher mit WebDAV (z. B. Nextcloud, MagentaCLOUD, HiDrive, pCloud, Koofr) – auch unterwegs.'),
            ]),
          ),
        ),
      ),
      if (s.art == 'netz') ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Netzwerkordner', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _pfad,
                    decoration: const InputDecoration(labelText: 'Ordner', hintText: r'\\NAS\BauSpur  oder  Z:\BauSpur'),
                    onSubmitted: (_) => _pruefen(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await getDirectoryPath(confirmButtonText: 'Diesen Ordner verwenden');
                    if (d != null) {
                      _pfad.text = d;
                      _pruefen();
                    }
                  },
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Wählen …'),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                'BauSpur legt darin je Projekt einen Unterordner an${store == null ? '' : ' (hier: ${p.basename(store.ordner)})'}. '
                'Ist der Ordner einmal nicht erreichbar, bleibt alles im Projektordner und wird später nachgetragen. '
                'Damit die App das NAS ohne den PC erreicht, dort WebDAV einschalten und in der App unter „Erweitert“ die Adresse dieses Ordners eintragen.',
                style: leise,
              ),
            ]),
          ),
        ),
      ],
      if (s.art == 'cloud') ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cloud-Speicher (WebDAV)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _url,
                decoration: const InputDecoration(labelText: 'WebDAV-Adresse des Ordners', hintText: 'https://…/BauSpur'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _benutzer, decoration: const InputDecoration(labelText: 'Benutzer'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _passwort, obscureText: true, decoration: const InputDecoration(labelText: 'Passwort oder App-Passwort'))),
              ]),
              const SizedBox(height: 6),
              const Text(
                'In der App dieselbe Adresse und dieselben Zugangsdaten eintragen. Die Zugangsdaten bleiben in den Einstellungen dieses PCs. '
                'OneDrive und iCloud bieten kein WebDAV und gehen auf diesem Weg nicht.',
                style: leise,
              ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        FilledButton.icon(
          onPressed: _prueft ? null : _pruefen,
          icon: _prueft ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline, size: 18),
          label: Text(s.art == 'pc' ? 'Prüfen' : 'Übernehmen und prüfen'),
        ),
        const SizedBox(width: 12),
        if (_ergebnis != null)
          Expanded(
            child: Row(children: [
              Icon(_ergebnisGut ? Icons.check_circle : Icons.error_outline, size: 18, color: _ergebnisGut ? const Color(0xFF15803D) : const Color(0xFFB45309)),
              const SizedBox(width: 6),
              Expanded(child: Text(_ergebnis!, style: const TextStyle(fontSize: 13))),
            ]),
          ),
      ]),
      if (state.speicherMeldung != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(state.speicherMeldung!, style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
        ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Mobil-App verbinden', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: BsFarben.akzent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Column(children: [
                  const Text('Kopplungscode', style: leise),
                  SelectableText(s.code.isEmpty ? '––––––' : '${s.code.substring(0, 3)} ${s.code.substring(3)}',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 2)),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  state.dienst.laeuft
                      ? 'Handy ins selbe WLAN, BauSpur-App öffnen: sie findet diesen PC von selbst und fragt einmal nach dem Code.\n'
                          'Falls nicht: in der App unter „Erweitert“ die Adresse $adresse eintragen.'
                      : s.dienst
                          ? 'Der Dienst für die App konnte nicht starten: ${state.dienst.fehler ?? ''}'
                          : 'Der direkte Abgleich im WLAN ist ausgeschaltet (siehe Erweitert).',
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Fragt Windows beim ersten Mal, ob BauSpur im Netzwerk kommunizieren darf, bitte für private Netzwerke zulassen – sonst findet die App den PC nicht.',
              style: leise,
            ),
            if (store != null) ...[
              const SizedBox(height: 4),
              Text('Austauschordner dieses Projekts: ${austauschOrdner(store)}', style: leise),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ExpansionTile(
          title: const Text('Erweitert'),
          shape: const Border(),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.dienst,
              onChanged: (v) => _setzen({'dienst': v}),
              title: const Text('Direkter Abgleich im WLAN'),
              subtitle: const Text('BauSpur beantwortet Anfragen der App im Heimnetz. Lässt sich bei NAS oder Cloud abschalten.'),
            ),
            Row(children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                  onSubmitted: (v) {
                    final n = int.tryParse(v.trim());
                    if (n != null && n > 1023 && n < 65536) _setzen({'port': n});
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _setzen({'code': neuerCode()}),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Neuer Kopplungscode'),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('Vorgabe ist Port $bauspurPort – nur dann sucht die App von selbst. Ein neuer Code trennt alle verbundenen Geräte.', style: leise),
            if (s.art == 'cloud')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.unsicher,
                onChanged: (v) => _setzen({'unsicher': v}),
                title: const Text('Selbst signiertes Zertifikat zulassen'),
                subtitle: const Text('Nur für eigene Server, deren Zertifikat der PC nicht kennt.'),
              ),
          ],
        ),
      ),
    ]);
  }
}
