import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/ki.dart';
import '../../core/ki_einrichtung.dart';
import '../../state/app_state.dart';

/// Geführte Einrichtung des Sprachmodells: Ort wählen (dieser PC oder Server
/// im Heimnetz), Fähigkeiten wählen, „Alles einrichten“ – Installation,
/// Start und Download laufen automatisch.
class KiEinrichtungKarte extends StatefulWidget {
  const KiEinrichtungKarte({super.key, required this.state, this.hardware, this.modelle});
  final AppState state;

  /// Für Tests: feste Hardware bzw. Abfrage der Modelle.
  final Future<Hardware> Function()? hardware;
  final Future<List<String>?> Function(String adresse)? modelle;

  @override
  State<KiEinrichtungKarte> createState() => _KiEinrichtungKarteState();
}

class _KiEinrichtungKarteState extends State<KiEinrichtungKarte> {
  Hardware? _hw;
  List<String>? _vorhanden; // null = nicht erreichbar
  bool _geprueft = false, _arbeitet = false, _sucht = false;
  bool _server = false; // false = dieser PC
  final _serverAdresse = TextEditingController();
  final _ssh = TextEditingController();
  List<String> _gefunden = [];
  Set<String> _gewaehlt = {};
  ServerArt _serverArt = ServerArt.linux;
  double? _fortschritt;
  String _meldung = '';

  KiEinstellung get _e => KiEinstellung.ausJson(widget.state.settings.ki);
  String get _zielAdresse => _server ? _normAdresse(_serverAdresse.text) : 'http://localhost:11434';

  String _normAdresse(String t) {
    var a = t.trim();
    if (a.isEmpty) return '';
    if (!a.startsWith('http')) a = 'http://$a';
    if (!RegExp(r':\d+$').hasMatch(Uri.tryParse(a)?.authority ?? '')) a = '$a:11434';
    return a;
  }

  @override
  void initState() {
    super.initState();
    final e = _e;
    _server = !(Uri.tryParse(e.adresse)?.host == 'localhost' || Uri.tryParse(e.adresse)?.host == '127.0.0.1');
    if (_server) _serverAdresse.text = e.adresse;
    _pruefen();
  }

  @override
  void dispose() {
    _serverAdresse.dispose();
    _ssh.dispose();
    super.dispose();
  }

  Future<void> _pruefen() async {
    setState(() => _arbeitet = true);
    final hw = await (widget.hardware ?? hardwareLesen)();
    final adr = _zielAdresse;
    final m = adr.isEmpty ? null : await (widget.modelle ?? ollamaModelle)(adr);
    if (!mounted) return;
    setState(() {
      _hw = hw;
      _vorhanden = m;
      _geprueft = true;
      _arbeitet = false;
      if (_gewaehlt.isEmpty) {
        final da = {for (final k in modellKatalog) if ((m ?? const []).any((x) => x == k.id || x.startsWith('${k.id}:'))) k.id};
        _gewaehlt = da.isNotEmpty ? da : modelleVorschlagen(_server ? null : hw).toSet();
      }
    });
  }

  Future<void> _suchen() async {
    setState(() {
      _sucht = true;
      _meldung = 'Suche im Heimnetz nach KI-Servern …';
    });
    final l = await heimnetzSuchen();
    if (!mounted) return;
    setState(() {
      _sucht = false;
      _gefunden = l;
      _meldung = l.isEmpty ? 'Kein KI-Server gefunden. Unten den Server einrichten oder die Adresse eintragen.' : '${l.length} Server gefunden.';
      if (l.length == 1) _serverAdresse.text = l.first;
    });
    if (l.length == 1) await _pruefen();
  }

  bool _hat(String id) => (_vorhanden ?? const []).any((x) => x == id || x.startsWith('$id:'));

  /// Alles in einem Schritt: installieren, starten, Modelle laden, einstellen.
  Future<void> _einrichten() async {
    final adr = _zielAdresse;
    if (adr.isEmpty) {
      setState(() => _meldung = 'Bitte die Adresse des Servers eintragen oder suchen.');
      return;
    }
    setState(() {
      _arbeitet = true;
      _fortschritt = null;
    });
    void melde(String t) => mounted ? setState(() => _meldung = t) : null;
    try {
      if (!_server) {
        if (!await ollamaInstalliert()) {
          melde('Installiere Ollama (kostenloses Programm für lokale KI) … Windows fragt eventuell nach Zustimmung.');
          final (ok, ausgabe) = await ollamaInstallieren();
          if (!ok) {
            melde('Die automatische Installation hat nicht geklappt. Download-Seite wird geöffnet – danach erneut „Alles einrichten“.\n${ausgabe.split('\n').take(2).join('\n')}');
            await webseiteOeffnen(ollamaDownload);
            return;
          }
        }
        melde('Starte Ollama …');
        if (!await ollamaStarten(adr)) {
          melde('Ollama startet nicht. Bitte den PC neu starten und es noch einmal versuchen.');
          return;
        }
      } else if (await (widget.modelle ?? ollamaModelle)(adr) == null) {
        melde('Der Server $adr antwortet nicht. Erst unten „Server einrichten“, dann erneut versuchen.');
        return;
      }
      for (final id in _gewaehlt) {
        if (_hat(id)) continue;
        await for (final (anteil, status) in ollamaLaden(adr, id)) {
          if (!mounted) return;
          setState(() {
            _fortschritt = anteil;
            _meldung = 'Lade $id: $status${anteil > 0 ? ' ${(anteil * 100).round()} %' : ''}';
          });
        }
      }
      final text = modellKatalog.where((m) => _gewaehlt.contains(m.id) && !m.bilder).lastOrNull ?? modellKatalog.where((m) => _gewaehlt.contains(m.id)).firstOrNull;
      final bild = modellKatalog.where((m) => _gewaehlt.contains(m.id) && m.bilder).lastOrNull;
      final e = _e;
      widget.state.settings.ki = {
        ...KiEinstellung(adresse: adr, modell: text?.id ?? e.modell, cloudErlaubt: e.cloudErlaubt).toJson(),
        if (bild != null) 'bildmodell': bild.id,
      };
      widget.state.settings.speichern();
      melde('Fertig: ${text?.id ?? e.modell}${bild == null ? '' : ' und ${bild.id}'} ${_server ? 'auf $adr' : 'auf diesem PC'} eingerichtet.');
      await _pruefen();
    } catch (e) {
      melde('Fehler: $e');
    } finally {
      if (mounted) {
        setState(() {
          _arbeitet = false;
          _fortschritt = null;
        });
      }
    }
  }

  Future<void> _sshEinrichten() async {
    final ziel = _ssh.text.trim();
    if (ziel.isEmpty) return;
    setState(() {
      _arbeitet = true;
      _meldung = 'Richte $ziel per SSH ein (kann einige Minuten dauern) …';
    });
    final (ok, ausgabe) = await perSshEinrichten(ziel);
    if (!mounted) return;
    setState(() {
      _arbeitet = false;
      _meldung = ok
          ? 'Server eingerichtet.'
          : 'SSH ohne Passwortabfrage war nicht möglich. Befehl kopieren und auf dem Server einfügen.\n${ausgabe.split('\n').take(2).join('\n')}';
      if (ok && _serverAdresse.text.isEmpty) _serverAdresse.text = _normAdresse(ziel.split('@').last);
    });
    if (ok) await _pruefen();
  }

  @override
  Widget build(BuildContext context) {
    final hw = _hw;
    final laeuft = _vorhanden != null;
    final eingestellt = _e.modell;
    Widget kopf(int n, String titel, {bool fertig = false}) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: fertig ? const Color(0xFF2F9E44) : BsFarben.akzent,
              child: fertig ? const Icon(Icons.check, size: 14, color: Colors.white) : Text('$n', style: const TextStyle(fontSize: 12, color: Colors.white)),
            ),
            const SizedBox(width: 10),
            Text(titel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('KI einrichten', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (_arbeitet && _fortschritt == null) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            IconButton(tooltip: 'Erneut prüfen', onPressed: _arbeitet ? null : _pruefen, icon: const Icon(Icons.refresh)),
          ]),
          Text(
            laeuft && _hat(eingestellt)
                ? 'Bereit: $eingestellt ${_server ? 'auf ${_zielAdresse.replaceFirst('http://', '')}' : 'auf diesem PC'}.'
                : 'Drei Schritte – du wählst nur aus, den Rest erledigt BauSpur. Alles bleibt im Heimnetz.',
            style: const TextStyle(color: BsFarben.textLeise),
          ),
          kopf(1, 'Wo soll die KI laufen?', fertig: laeuft),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.computer, size: 18), label: Text('Auf diesem PC')),
              ButtonSegment(value: true, icon: Icon(Icons.dns_outlined, size: 18), label: Text('Auf einem Server im Heimnetz')),
            ],
            selected: {_server},
            onSelectionChanged: (v) {
              setState(() {
                _server = v.first;
                _gewaehlt = {};
              });
              _pruefen();
            },
          ),
          const SizedBox(height: 6),
          if (!_server)
            Text(
              hw == null || hw.ramGb == 0
                  ? 'Hardware wird gelesen …'
                  : 'Dieser PC: ${hw.ramGb.round()} GB Arbeitsspeicher, ${hw.grafik}${hw.vramGb > 0 ? ' mit ${hw.vramGb.round()} GB' : ''}.'
                      '${hw.vramGb < 6 ? ' Ohne starke Grafikkarte sind nur kleine Modelle flüssig – ein Server im Heimnetz ist dann besser.' : ''}',
              style: const TextStyle(fontSize: 12, color: BsFarben.textLeise),
            )
          else ...[
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _serverAdresse,
                  decoration: const InputDecoration(isDense: true, labelText: 'Adresse des Servers', hintText: '192.168.1.20'),
                  onSubmitted: (_) => _pruefen(),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _sucht ? null : _suchen,
                icon: _sucht ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar, size: 18),
                label: const Text('Im Heimnetz suchen'),
              ),
              for (final g in _gefunden)
                ActionChip(
                  label: Text(g.replaceFirst('http://', '')),
                  onPressed: () {
                    _serverAdresse.text = g;
                    _pruefen();
                  },
                ),
            ]),
            const SizedBox(height: 4),
            Text(laeuft ? 'Server erreichbar, ${_vorhanden!.length} Modell(e) vorhanden.' : 'Server noch nicht erreichbar.',
                style: TextStyle(fontSize: 12, color: laeuft ? const Color(0xFF2F9E44) : BsFarben.textLeise)),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: !laeuft,
              title: const Text('Server von hier aus einrichten'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<ServerArt>(
                    segments: [for (final a in ServerArt.values) ButtonSegment(value: a, label: Text(a.label))],
                    selected: {_serverArt},
                    onSelectionChanged: (v) => setState(() => _serverArt = v.first),
                  ),
                ),
                const SizedBox(height: 8),
                if (_serverArt == ServerArt.linux)
                  Row(children: [
                    SizedBox(
                      width: 260,
                      child: TextField(controller: _ssh, decoration: const InputDecoration(isDense: true, labelText: 'SSH-Zugang', hintText: 'benutzer@192.168.1.20')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(onPressed: _arbeitet ? null : _sshEinrichten, child: const Text('Automatisch per SSH einrichten')),
                  ]),
                const SizedBox(height: 6),
                Text(
                  switch (_serverArt) {
                    ServerArt.linux => 'Oder diesen Befehl auf dem Server im Terminal einfügen (installiert Ollama und gibt es im Heimnetz frei):',
                    ServerArt.synology => 'In DSM „Container Manager“ installieren, dann per SSH (Systemsteuerung → Terminal) diesen Befehl ausführen:',
                    ServerArt.windows => 'Auf dem Windows-PC PowerShell als Administrator öffnen und einfügen, danach den PC neu anmelden:',
                  },
                  style: const TextStyle(fontSize: 12),
                ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(8),
                  color: const Color(0xFFF1F3F5),
                  child: SelectableText(serverBefehl(_serverArt), style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: serverBefehl(_serverArt))),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Befehl kopieren'),
                  ),
                ),
                if (_serverArt == ServerArt.synology)
                  const Text('Hinweis: Ohne Grafikkarte rechnet die Synology sehr langsam – dort eher das kleine Modell wählen.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFE67700))),
              ],
            ),
          ],
          kopf(2, 'Was soll die KI können?', fertig: _gewaehlt.isNotEmpty && _gewaehlt.every(_hat)),
          for (final m in modellKatalog)
            () {
              final eig = eignung(m, _server ? null : hw);
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _gewaehlt.contains(m.id),
                onChanged: (v) => setState(() => v == true ? _gewaehlt.add(m.id) : _gewaehlt.remove(m.id)),
                title: Row(children: [
                  Text(m.titel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  if (_hat(m.id))
                    const Chip(label: Text('vorhanden'), visualDensity: VisualDensity.compact)
                  else
                    Text('${m.groesseGb.toString().replaceAll('.', ',')} GB Download', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                  const SizedBox(width: 8),
                  if (!_server)
                    Text(
                      switch (eig) {
                        Eignung.passt => 'passt',
                        Eignung.langsam => 'läuft, aber langsam',
                        Eignung.zuGross => 'zu groß für diesen PC',
                      },
                      style: TextStyle(
                          fontSize: 12,
                          color: switch (eig) {
                            Eignung.passt => const Color(0xFF2F9E44),
                            Eignung.langsam => const Color(0xFFE67700),
                            Eignung.zuGross => const Color(0xFFB91C1C),
                          }),
                    ),
                ]),
                subtitle: Text(m.beschreibung),
              );
            }(),
          kopf(3, 'Einrichten', fertig: laeuft && _hat(eingestellt)),
          FilledButton.icon(
            onPressed: _arbeitet || _gewaehlt.isEmpty ? null : _einrichten,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: Text(_server ? 'Alles einrichten (Modelle auf den Server laden)' : 'Alles einrichten (installieren, starten, Modelle laden)'),
          ),
          if (_fortschritt != null) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: _fortschritt! > 0 ? _fortschritt : null)),
          if (_meldung.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_meldung, style: const TextStyle(fontSize: 12))),
          if (!_geprueft) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Prüfe …')),
        ]),
      ),
    );
  }
}
