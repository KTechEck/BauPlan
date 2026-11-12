import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/speicher.dart';
import 'ordner.dart';
import 'qr_scannen.dart';

/// Verbindung der App zum Projekt: sucht BauSpur am PC von selbst im WLAN
/// (einmal Kopplungscode eingeben, fertig). Unter „Erweitert“ lassen sich die
/// Adresse von Hand oder ein NAS/Cloud-Speicher (WebDAV) eintragen.
class VerbindungSeite extends StatefulWidget {
  const VerbindungSeite({super.key, required this.ordner, required this.fertig, this.zurueck = false});
  final FernOrdner ordner;
  final Future<void> Function() fertig;

  /// Als eigene Seite geöffnet (mit Zurück-Pfeil).
  final bool zurueck;

  @override
  State<VerbindungSeite> createState() => _VerbindungSeiteState();
}

class _VerbindungSeiteState extends State<VerbindungSeite> {
  FernOrdner get _o => widget.ordner;
  Map<String, dynamic> get _v => _o.einstellungen.verbindung;
  List<GefundenerPc>? _gefunden;
  bool _sucht = false, _arbeitet = false;
  String? _meldung;
  late String _art = _o.istPc ? 'pc' : 'webdav';
  late final _adresse = TextEditingController(text: '${_v['adresse'] ?? ''}');
  late final _code = TextEditingController(text: '${_v['code'] ?? ''}');
  late final _url = TextEditingController(text: '${_v['url'] ?? ''}');
  late final _benutzer = TextEditingController(text: '${_v['benutzer'] ?? ''}');
  late final _passwort = TextEditingController(text: '${_v['passwort'] ?? ''}');
  late final _projekt = TextEditingController(text: '${_v['projekt'] ?? ''}');
  late bool _auto = _v['auto'] != false;
  late bool _unsicher = _v['unsicher'] == true;

  @override
  void initState() {
    super.initState();
    if (!_o.eingerichtet) _suchen();
  }

  @override
  void dispose() {
    for (final c in [_adresse, _code, _url, _benutzer, _passwort, _projekt]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _suchen() async {
    setState(() {
      _sucht = true;
      _meldung = null;
    });
    List<GefundenerPc> g = [];
    try {
      g = await _o.suche();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _sucht = false;
      _gefunden = g;
    });
  }

  void _speichern(Map<String, dynamic> v) {
    _o.einstellungen.verbindung = v;
    _o.einstellungen.speichern();
  }

  /// Adresse und Code am PC prüfen und bei Erfolg übernehmen.
  /// QR-Code vom PC scannen und nacheinander dessen Adressen versuchen.
  Future<void> _qrKoppeln() async {
    final k = await Navigator.of(context).push<({List<String> adressen, String code, String name})>(
        MaterialPageRoute(builder: (_) => const QrScannenSeite()));
    if (k == null || !mounted) return;
    for (final a in k.adressen) {
      _adresse.text = a;
      _code.text = k.code;
      if (await _pcVerbinden(a, k.code, name: k.name.isEmpty ? null : k.name)) return;
      if (!mounted) return;
    }
  }

  Future<bool> _pcVerbinden(String adresse, String code, {String? name}) async {
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    String? fehler;
    try {
      final a = await PcSpeicher(adresse.trim(), code: code.replaceAll(RegExp(r'\s'), '')).pruefen();
      _speichern({'art': 'pc', 'adresse': adresse.trim(), 'code': code.replaceAll(RegExp(r'\s'), ''), 'pc_name': '${a['name'] ?? name ?? adresse}', 'auto': _auto});
    } on CodeFalsch {
      fehler = 'Der Code stimmt nicht. Er steht am PC unter Einstellungen › Speicher und Abgleich.';
    } catch (_) {
      fehler = 'Unter $adresse antwortet BauSpur nicht. Ist das Handy im selben WLAN und BauSpur am PC geöffnet?';
    }
    if (!mounted) return false;
    setState(() {
      _arbeitet = false;
      _meldung = fehler;
    });
    if (fehler == null) await widget.fertig();
    return fehler == null;
  }

  Future<void> _codeFragen(GefundenerPc pc) async {
    final feld = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Kopplungscode von „${pc.name}“'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Der sechsstellige Code steht am PC unter Einstellungen › Speicher und Abgleich. Er wird nur einmal gebraucht.'),
          const SizedBox(height: 12),
          TextField(
            controller: feld,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 7,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 4),
            onSubmitted: (v) => Navigator.of(c).pop(v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(c).pop(feld.text), child: const Text('Verbinden')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    _adresse.text = pc.adresse;
    _code.text = code.trim();
    await _pcVerbinden(pc.adresse, code, name: pc.name);
  }

  /// WebDAV prüfen; liegt der Planstand in einem Unterordner (je Projekt einer), diesen selbst finden.
  Future<void> _webdavVerbinden() async {
    setState(() {
      _arbeitet = true;
      _meldung = null;
    });
    String? fehler;
    var projekt = _projekt.text.trim();
    try {
      final dav = WebDavSpeicher(_url.text, benutzer: _benutzer.text.trim(), passwort: _passwort.text, unsicher: _unsicher);
      Future<bool> hatPlan(String ordner) async => await (ordner.isEmpty ? dav : UnterSpeicher(dav, ordner)).lesen(planstandPfad) != null;
      if (!await hatPlan(projekt)) {
        final treffer = <String>[];
        for (final n in await dav.liste('')) {
          if (n.endsWith('/') && await hatPlan(n.substring(0, n.length - 1))) treffer.add(n.substring(0, n.length - 1));
        }
        if (treffer.isEmpty) {
          fehler = 'Verbindung steht, aber unter dieser Adresse liegt noch kein BauSpur-Planstand. Am PC die Speicherart einstellen und das Projekt öffnen.';
        } else if (treffer.length == 1 || !mounted) {
          projekt = treffer.first;
        } else {
          final wahl = await showDialog<String>(
            context: context,
            builder: (c) => SimpleDialog(title: const Text('Projekt wählen'), children: [
              for (final t in treffer) SimpleDialogOption(onPressed: () => Navigator.of(c).pop(t), child: Text(t)),
            ]),
          );
          if (wahl == null) {
            fehler = 'Kein Projekt gewählt.';
          } else {
            projekt = wahl;
          }
        }
      }
      if (fehler == null) {
        _projekt.text = projekt;
        _speichern({'art': 'webdav', 'url': _url.text.trim(), 'benutzer': _benutzer.text.trim(), 'passwort': _passwort.text, 'unsicher': _unsicher, 'projekt': projekt});
      }
    } catch (e) {
      fehler = 'Speicher nicht erreichbar: Adresse, Benutzer und Passwort prüfen. ($e)';
    }
    if (!mounted) return;
    setState(() {
      _arbeitet = false;
      _meldung = fehler;
    });
    if (fehler == null) await widget.fertig();
  }

  @override
  Widget build(BuildContext context) {
    const leise = TextStyle(fontSize: 12, color: BsFarben.textLeise);
    final verbunden = _o.eingerichtet;
    return Scaffold(
      appBar: AppBar(title: const Text('Verbindung'), automaticallyImplyLeading: widget.zurueck),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.wifi_find_outlined, size: 56, color: BsFarben.akzent),
        const SizedBox(height: 12),
        Text(verbunden ? 'Verbindung zum Projekt' : 'Mit BauSpur verbinden', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        if (verbunden)
          FutureBuilder<String>(
            future: _o.info().catchError((Object e) => '$e'),
            builder: (_, s) => Text(s.data ?? '…', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          )
        else
          const Text('Die App sucht im WLAN nach dem PC, auf dem BauSpur läuft.', textAlign: TextAlign.center),
        if (verbunden && _o.fehler == null) ...[
          const SizedBox(height: 8),
          const Text('Steht die Verbindung, aber es erscheint kein Plan: das Projekt am PC einmal öffnen.', textAlign: TextAlign.center, style: leise),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _arbeitet ? null : _qrKoppeln,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Mit QR-Code koppeln'),
        ),
        const SizedBox(height: 4),
        const Text('QR-Code steht am PC unter Einstellungen › Speicher und Abgleich.', textAlign: TextAlign.center, style: leise),
        const SizedBox(height: 12),
        if (_meldung != null)
          Card(
            color: const Color(0xFFFFF7ED),
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_meldung!, style: const TextStyle(color: Color(0xFF9A3412)))),
          ),
        if (_sucht)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else ...[
          for (final pc in _gefunden ?? const <GefundenerPc>[])
            Card(
              child: ListTile(
                leading: const Icon(Icons.computer_outlined, color: BsFarben.akzent),
                title: Text(pc.name),
                subtitle: Text(pc.projekt.isEmpty ? 'kein Projekt geöffnet' : 'Projekt: ${pc.projekt}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _arbeitet ? null : () => _codeFragen(pc),
              ),
            ),
          if (_gefunden != null && _gefunden!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Kein PC gefunden. Bitte prüfen: Handy im selben WLAN wie der PC, BauSpur am PC geöffnet, '
                'und Windows darf BauSpur im privaten Netzwerk kommunizieren lassen (Firewall-Frage beim ersten Start).',
                textAlign: TextAlign.center,
              ),
            ),
          FilledButton.icon(onPressed: _arbeitet ? null : _suchen, icon: const Icon(Icons.search), label: Text(_gefunden == null ? 'PC im WLAN suchen' : 'Erneut suchen')),
        ],
        if (verbunden) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _arbeitet ? null : () => widget.fertig(), icon: const Icon(Icons.refresh), label: const Text('Erneut versuchen')),
        ],
        const SizedBox(height: 16),
        Card(
          child: ExpansionTile(
            title: const Text('Erweitert'),
            subtitle: const Text('Adresse von Hand, NAS oder Cloud'),
            shape: const Border(),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pc', label: Text('BauSpur-PC'), icon: Icon(Icons.computer_outlined)),
                  ButtonSegment(value: 'webdav', label: Text('NAS / Cloud'), icon: Icon(Icons.cloud_outlined)),
                ],
                selected: {_art},
                onSelectionChanged: (s) => setState(() => _art = s.first),
              ),
              const SizedBox(height: 12),
              if (_art == 'pc') ...[
                TextField(controller: _adresse, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(labelText: 'Adresse des PCs', hintText: '192.168.178.20')),
                const SizedBox(height: 8),
                TextField(controller: _code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kopplungscode')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _auto,
                  onChanged: (v) => setState(() => _auto = v),
                  title: const Text('PC selbst wiederfinden'),
                  subtitle: const Text('Sucht neu, wenn der PC im WLAN eine andere Adresse bekommen hat.'),
                ),
                FilledButton(onPressed: _arbeitet || _adresse.text.trim().isEmpty && _code.text.isEmpty ? null : () => _pcVerbinden(_adresse.text, _code.text), child: const Text('Verbinden')),
              ] else ...[
                TextField(controller: _url, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(labelText: 'WebDAV-Adresse', hintText: 'https://…/BauSpur')),
                const SizedBox(height: 8),
                TextField(controller: _benutzer, autocorrect: false, decoration: const InputDecoration(labelText: 'Benutzer')),
                const SizedBox(height: 8),
                TextField(controller: _passwort, obscureText: true, decoration: const InputDecoration(labelText: 'Passwort oder App-Passwort')),
                const SizedBox(height: 8),
                TextField(controller: _projekt, decoration: const InputDecoration(labelText: 'Projektordner (leer = selbst finden)')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _unsicher,
                  onChanged: (v) => setState(() => _unsicher = v),
                  title: const Text('Selbst signiertes Zertifikat zulassen'),
                  subtitle: const Text('Für das eigene NAS im Heimnetz.'),
                ),
                const Text('Dieselbe Adresse und Zugangsdaten wie am PC (Cloud) bzw. die WebDAV-Adresse des Netzwerkordners auf dem NAS.', style: leise),
                const SizedBox(height: 8),
                FilledButton(onPressed: _arbeitet ? null : _webdavVerbinden, child: const Text('Verbinden')),
              ],
              if (verbunden)
                TextButton(
                  onPressed: () {
                    _o.trennen();
                    setState(() => _gefunden = null);
                    widget.fertig();
                  },
                  child: const Text('Verbindung trennen'),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
