import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app/theme.dart';
import 'ordner.dart';
import 'planstand.dart';

/// BauSpur auf iPhone und iPad (Lastenheft Abschnitt 14): kein zweites
/// Planungsprogramm, sondern das schnelle Werkzeug für die Baustelle.
/// Erfassen in höchstens drei Schritten (Raum wählen, aufnehmen, zuordnen),
/// Nachschlagen im Planstand. Die App schreibt nie in die Projektdatenbank,
/// sondern jede Erfassung als eigene Datei nach `eingang/`.
class MobilApp extends StatelessWidget {
  const MobilApp({super.key, required this.ordner, required this.einstellungen, required this.puffer, this.kamera});
  final ProjektOrdner ordner;
  final MobilEinstellungen einstellungen;
  final Puffer puffer;

  /// Fotoquelle (in Tests ersetzbar).
  final Future<List<int>?> Function(int qualitaet)? kamera;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BauSpur',
        debugShowCheckedModeBanner: false,
        theme: bauSpurTheme(),
        home: MobilStart(ordner: ordner, einstellungen: einstellungen, puffer: puffer, kamera: kamera),
      );
}

class MobilStart extends StatefulWidget {
  const MobilStart({super.key, required this.ordner, required this.einstellungen, required this.puffer, this.kamera});
  final ProjektOrdner ordner;
  final MobilEinstellungen einstellungen;
  final Puffer puffer;
  final Future<List<int>?> Function(int qualitaet)? kamera;

  @override
  State<MobilStart> createState() => _MobilStartState();
}

class _MobilStartState extends State<MobilStart> with WidgetsBindingObserver {
  String? _ordnerName;
  Planstand? _plan;
  bool _laedt = true;
  int _seite = 0;
  int _wartend = 0;
  String? _meldung;
  Timer? _timer;

  MobilEinstellungen get _e => widget.einstellungen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _laden();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _abgleichen());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _abgleichen();
  }

  Future<void> _laden() async {
    setState(() => _laedt = true);
    String? name;
    try {
      name = await widget.ordner.name();
    } catch (_) {}
    Planstand? plan;
    if (name != null) {
      try {
        plan = Planstand.lesen(await widget.ordner.lesen('planstand/planstand.json'));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _ordnerName = name;
      _plan = plan ?? _plan;
      _laedt = false;
      _wartend = widget.puffer.wartend.length;
    });
    _abgleichen();
  }

  /// Wartende Erfassungen übertragen und Planstand neu lesen.
  Future<void> _abgleichen() async {
    if (_ordnerName == null) return;
    var n = 0;
    try {
      n = await widget.puffer.uebertragen(widget.ordner);
    } catch (_) {}
    Planstand? plan;
    try {
      plan = Planstand.lesen(await widget.ordner.lesen('planstand/planstand.json'));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (plan != null) _plan = plan;
      _wartend = widget.puffer.wartend.length;
      if (n > 0) _meldung = '$n Erfassung(en) übertragen';
    });
  }

  Future<void> _ordnerWaehlen() async {
    try {
      await widget.ordner.waehlen();
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ordner konnte nicht gewählt werden: ${e.message}')));
    }
    await _laden();
  }

  /// Erfassung ablegen (Puffer) und sofort zu übertragen versuchen.
  Future<void> _erfasst(Map<String, dynamic> eintrag, {List<int>? foto}) async {
    widget.puffer.ablegen({...eintrag, 'autor': _e.benutzer.isEmpty ? 'App' : _e.benutzer}, foto: foto);
    setState(() => _wartend = widget.puffer.wartend.length);
    await _abgleichen();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_wartend > 0 ? 'Gespeichert – wird übertragen, sobald der Ordner erreichbar ist.' : 'Gespeichert und übertragen.'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_laedt && _plan == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_ordnerName == null || _plan == null) return _einrichten();
    final plan = _plan!;
    final seiten = [
      ErfassenSeite(plan: plan, einstellungen: _e, erfasst: _erfasst, kamera: widget.kamera),
      GrundrissSeite(plan: plan, einstellungen: _e),
      EinkaufSeite(plan: plan, erfasst: _erfasst),
      _mehr(plan),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(plan.projekt),
        actions: [
          if (_wartend > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(avatar: const Icon(Icons.cloud_upload_outlined, size: 16), label: Text('$_wartend wartend')),
            ),
          IconButton(tooltip: 'Abgleichen', onPressed: _abgleichen, icon: const Icon(Icons.sync)),
        ],
      ),
      body: Column(children: [
        if (_meldung != null)
          MaterialBanner(
            content: Text(_meldung!),
            actions: [TextButton(onPressed: () => setState(() => _meldung = null), child: const Text('OK'))],
          ),
        Expanded(child: seiten[_seite]),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _seite,
        onDestinationSelected: (i) => setState(() => _seite = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add_a_photo_outlined), label: 'Erfassen'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Grundriss'),
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), label: 'Einkauf'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Mehr'),
        ],
      ),
    );
  }

  Widget _einrichten() => Scaffold(
        appBar: AppBar(title: const Text('BauSpur')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Icon(Icons.folder_open_outlined, size: 64, color: BsFarben.akzent),
          const SizedBox(height: 16),
          Text(_ordnerName == null ? 'Projektordner wählen' : 'Noch kein Planstand im Ordner „$_ordnerName“',
              style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            _ordnerName == null
                ? 'Wähle in iCloud Drive den Austauschordner des Projekts (z. B. „BauSpur › Wohnhaus“). '
                    'Am PC stellst du ihn unter Einstellungen › Allgemein ein. Ordner in OneDrive lässt das iPhone hier nicht zu. '
                    'Die App liest daraus nur den Planstand und legt Erfassungen im Unterordner „eingang“ ab.'
                : 'Öffne das Projekt einmal in BauSpur am PC – dann liegt der Planstand im Ordner und erscheint hier. '
                    'iCloud braucht für das Übertragen manchmal einen Moment.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _ordnerWaehlen, icon: const Icon(Icons.folder_outlined), label: Text(_ordnerName == null ? 'Ordner wählen' : 'Anderen Ordner wählen')),
          if (_ordnerName != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _laden, icon: const Icon(Icons.refresh), label: const Text('Erneut versuchen')),
            const SizedBox(height: 24),
            Text('Was die App im Ordner sieht', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            FutureBuilder<String>(
              future: widget.ordner.info().catchError((Object e) => 'Fehler: $e'),
              builder: (_, s) => SelectableText(s.data ?? '…', style: const TextStyle(fontSize: 12, fontFamily: 'Courier')),
            ),
            const SizedBox(height: 8),
            const Text(
              'Erwartet wird „planstand: planstand.json“. Steht dort „.planstand.json.icloud“, lädt iCloud die Datei gerade – kurz warten und erneut versuchen. '
              'Fehlt „planstand“ ganz, wurde ein anderer Ordner gewählt als am PC eingestellt.',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise),
            ),
          ],
        ]),
      );

  Widget _mehr(Planstand plan) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Abgleich', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: Text('Projektordner: ${_ordnerName ?? '–'}'),
          subtitle: Text('Planstand vom ${plan.erstellt == null ? '–' : _datum(plan.erstellt!)}'),
          trailing: TextButton(onPressed: _ordnerWaehlen, child: const Text('Ändern')),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_upload_outlined),
          title: Text('$_wartend Erfassung(en) warten auf Übertragung'),
          trailing: TextButton(onPressed: _abgleichen, child: const Text('Jetzt')),
        ),
        const Divider(),
        Text('Einstellungen', style: Theme.of(context).textTheme.titleMedium),
        TextFormField(
          initialValue: _e.benutzer,
          decoration: const InputDecoration(labelText: 'Dein Name (steht an jeder Erfassung)'),
          onChanged: (v) {
            _e.benutzer = v.trim();
            _e.speichern();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: const [50, 80, 95].contains(_e.fotoQualitaet) ? _e.fotoQualitaet : 80,
          decoration: const InputDecoration(labelText: 'Fotoqualität'),
          items: const [
            DropdownMenuItem(value: 50, child: Text('klein (schnell übertragen)')),
            DropdownMenuItem(value: 80, child: Text('normal')),
            DropdownMenuItem(value: 95, child: Text('hoch')),
          ],
          onChanged: (v) {
            _e.fotoQualitaet = v ?? 80;
            _e.speichern();
          },
        ),
      ]);
}

String _datum(DateTime d) => '${d.day}.${d.month}.${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

// ------------------------------------------------------------------ Erfassen

class ErfassenSeite extends StatefulWidget {
  const ErfassenSeite({super.key, required this.plan, required this.einstellungen, required this.erfasst, this.kamera});
  final Planstand plan;
  final MobilEinstellungen einstellungen;
  final Future<void> Function(Map<String, dynamic> eintrag, {List<int>? foto}) erfasst;
  final Future<List<int>?> Function(int qualitaet)? kamera;

  @override
  State<ErfassenSeite> createState() => _ErfassenSeiteState();
}

class _ErfassenSeiteState extends State<ErfassenSeite> {
  MobilEinstellungen get _e => widget.einstellungen;
  Map<String, dynamic>? get _geschoss => widget.plan.geschoss(_e.geschoss);
  List<Map<String, dynamic>> get _raeume => Planstand.liste(_geschoss?['raeume']);
  Map<String, dynamic>? get _raum => _raeume.where((r) => r['id'] == _e.raum).firstOrNull;

  List<Map<String, dynamic>> _objekteImRaum() {
    final g = _geschoss;
    if (g == null) return const [];
    final r = _raum;
    final umriss = r == null ? const <Offset>[] : punkte(r['umriss']);
    return [
      for (final o in Planstand.liste(g['objekte']))
        if (o['geometrie'] != 'flaeche' &&
            (_e.gewerk == null || o['gewerk'] == _e.gewerk) &&
            (r == null || o['raum'] == r['id'] || (umriss.length >= 3 && punkte(o['punkte']).any((q) => imPolygon(q, umriss)))))
          o
    ];
  }

  Map<String, dynamic> _basis() => {
        'geschoss': _geschoss?['id'],
        if (_raum != null) 'raum': _raum!['id'],
        if (_e.gewerk != null) 'gewerk': _e.gewerk,
      };

  Future<List<int>?> _foto() async {
    if (widget.kamera != null) return widget.kamera!(_e.fotoQualitaet);
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: _e.fotoQualitaet, maxWidth: 2400);
      return x == null ? null : await x.readAsBytes();
    } catch (_) {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: _e.fotoQualitaet, maxWidth: 2400);
      return x == null ? null : await x.readAsBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _geschoss;
    final gewerke = widget.plan.gewerke;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Schritt 1: Raum (bleibt voreingestellt)
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('g-${g?['id']}'),
            initialValue: g?['id'] as String?,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Geschoss'),
            items: [for (final x in widget.plan.geschosse) DropdownMenuItem(value: x['id'] as String, child: Text('${x['name']}'))],
            onChanged: (v) => setState(() {
              _e.geschoss = v;
              _e.raum = null;
              _e.speichern();
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey('gw-${_e.gewerk}'),
            initialValue: gewerke.containsKey(_e.gewerk) ? _e.gewerk : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Gewerk'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('alle')),
              for (final e in gewerke.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _e.gewerk = v;
              _e.speichern();
            }),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Text('Raum', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final r in _raeume)
          ChoiceChip(
            label: Text('${r['name']}'),
            selected: r['id'] == _e.raum,
            onSelected: (v) => setState(() {
              _e.raum = v ? r['id'] as String : null;
              _e.speichern();
            }),
          ),
        if (_raeume.isEmpty) const Text('Keine Räume im Planstand.', style: TextStyle(color: BsFarben.textLeise)),
      ]),
      const SizedBox(height: 20),
      // Schritt 2: aufnehmen
      GridView.count(
        crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 5 : 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          _kachel(Icons.photo_camera_outlined, 'Foto', _fotoErfassen),
          _kachel(Icons.edit_note, 'Notiz', () => _formular('notiz')),
          _kachel(Icons.straighten, 'Messwert', () => _formular('messwert')),
          _kachel(Icons.inventory_2_outlined, 'Material', () => _formular('material')),
          _kachel(Icons.task_alt, 'Status', _statusErfassen),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        _raum == null ? 'Tipp: erst den Raum wählen – dann ist alles gleich richtig zugeordnet.' : 'Erfassungen gehen an: ${_raum!['name']}${_e.gewerk == null ? '' : ' · ${gewerke[_e.gewerk]?.name ?? _e.gewerk}'}',
        style: const TextStyle(color: BsFarben.textLeise),
      ),
    ]);
  }

  Widget _kachel(IconData icon, String text, VoidCallback tippen) => Material(
        color: BsFarben.akzentHell,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: tippen,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 34, color: BsFarben.akzentDunkel),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Future<void> _fotoErfassen() async {
    final bytes = await _foto();
    if (bytes == null || !mounted) return;
    // Schritt 3: zuordnen (Objekt, Position, Notiz – alles optional)
    final ergebnis = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => ZuordnenSeite(titel: 'Foto zuordnen', plan: widget.plan, geschoss: _geschoss!, objekte: _objekteImRaum(), foto: bytes),
    ));
    if (ergebnis == null) return;
    await widget.erfasst({..._basis(), 'art': 'foto', ...ergebnis}, foto: bytes);
  }

  Future<void> _formular(String art) async {
    final ergebnis = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => ZuordnenSeite(
        titel: switch (art) { 'messwert' => 'Messwert', 'material' => 'Material', _ => 'Notiz' },
        plan: widget.plan,
        geschoss: _geschoss!,
        objekte: _objekteImRaum(),
        art: art,
      ),
    ));
    if (ergebnis == null) return;
    await widget.erfasst({..._basis(), 'art': art, ...ergebnis});
  }

  Future<void> _statusErfassen() async {
    final objekte = _objekteImRaum();
    if (objekte.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('In diesem Raum gibt es keine Objekte.')));
      return;
    }
    final ergebnis = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => StatusSeite(plan: widget.plan, objekte: objekte),
    ));
    if (ergebnis == null || !mounted) return;
    List<int>? bytes;
    // „verdeckt“ braucht einen Fotonachweis (Lastenheft)
    if (ergebnis['status'] == 'verdeckt') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Foto vor dem Verdecken'),
          content: const Text('Bevor „verdeckt“ gesetzt wird, braucht es ein Foto als Nachweis, wie es unter Putz bzw. Estrich aussieht.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Foto aufnehmen')),
          ],
        ),
      );
      if (ok != true) return;
      bytes = await _foto();
      if (bytes == null) return;
    }
    await widget.erfasst({..._basis(), 'art': 'status', ...ergebnis}, foto: bytes);
  }
}

/// Zuordnen: Objekt (optional), Position im Grundriss (optional), Text bzw. Wert.
class ZuordnenSeite extends StatefulWidget {
  const ZuordnenSeite({super.key, required this.titel, required this.plan, required this.geschoss, required this.objekte, this.foto, this.art = 'foto'});
  final String titel;
  final Planstand plan;
  final Map<String, dynamic> geschoss;
  final List<Map<String, dynamic>> objekte;
  final List<int>? foto;
  final String art;

  @override
  State<ZuordnenSeite> createState() => _ZuordnenSeiteState();
}

class _ZuordnenSeiteState extends State<ZuordnenSeite> {
  String? _objekt;
  Offset? _position;
  final _text = TextEditingController(), _wert = TextEditingController();
  String _einheit = 'mm';

  static const _einheitenMess = ['mm', 'cm', 'm', 'm²', '°C', 'bar', 'V', 'Ω', '%'];
  static const _einheitenMaterial = ['Stk', 'm', 'm²', 'kg', 'l', 'Pkg', 'Rolle'];

  @override
  void initState() {
    super.initState();
    if (widget.art == 'material') _einheit = 'Stk';
  }

  @override
  Widget build(BuildContext context) {
    final mitWert = widget.art == 'messwert' || widget.art == 'material';
    return Scaffold(
      appBar: AppBar(title: Text(widget.titel), actions: [
        TextButton(
          onPressed: () {
            final wert = num.tryParse(_wert.text.replaceAll(',', '.'));
            if (mitWert && wert == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte einen Wert eingeben.')));
              return;
            }
            if (widget.art == 'notiz' && _text.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte eine Notiz eingeben.')));
              return;
            }
            Navigator.pop(context, {
              if (_objekt != null) 'objekt': _objekt,
              if (_position != null) 'x': _position!.dx.round(),
              if (_position != null) 'y': _position!.dy.round(),
              if (_text.text.trim().isNotEmpty) 'text': _text.text.trim(),
              if (mitWert) 'wert': wert,
              if (mitWert) 'einheit': _einheit,
            });
          },
          child: const Text('Speichern'),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.foto != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(Uint8List.fromList(widget.foto!), height: 220, fit: BoxFit.cover),
          ),
        if (mitWert) ...[
          Row(children: [
            Expanded(
              child: TextField(
                controller: _wert,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: widget.art == 'material' ? 'Menge' : 'Wert'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                initialValue: _einheit,
                decoration: const InputDecoration(labelText: 'Einheit'),
                items: [for (final x in widget.art == 'material' ? _einheitenMaterial : _einheitenMess) DropdownMenuItem(value: x, child: Text(x))],
                onChanged: (v) => _einheit = v ?? _einheit,
              ),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: widget.art == 'notiz',
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: switch (widget.art) { 'material' => 'Was (z. B. NYM-J 3×1,5)', 'messwert' => 'Was wurde gemessen?', _ => 'Notiz' },
            helperText: 'Diktieren: Mikrofon auf der Tastatur',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _objekt,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Zu Objekt (optional)'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('– kein bestimmtes –')),
            for (final o in widget.objekte) DropdownMenuItem<String?>(value: o['id'] as String, child: Text('${o['kennung']} · ${o['name']}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _objekt = v),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final q = await Navigator.of(context).push<Offset>(MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Position antippen')),
                body: GrundrissAnsicht(plan: widget.plan, geschoss: widget.geschoss, waehlen: (p) => Navigator.pop(context, p)),
              ),
            ));
            if (q != null) setState(() => _position = q);
          },
          icon: const Icon(Icons.place_outlined),
          label: Text(_position == null ? 'Position im Grundriss setzen (optional)' : 'Position gesetzt ✓ – ändern'),
        ),
      ]),
    );
  }
}

class StatusSeite extends StatefulWidget {
  const StatusSeite({super.key, required this.plan, required this.objekte});
  final Planstand plan;
  final List<Map<String, dynamic>> objekte;

  @override
  State<StatusSeite> createState() => _StatusSeiteState();
}

class _StatusSeiteState extends State<StatusSeite> {
  String? _objekt;

  @override
  Widget build(BuildContext context) {
    final o = widget.objekte.where((x) => x['id'] == _objekt).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Status ändern')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('1. Objekt', style: Theme.of(context).textTheme.titleSmall),
        for (final x in widget.objekte)
          ListTile(
            selected: _objekt == x['id'],
            leading: Icon(_objekt == x['id'] ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            onTap: () => setState(() => _objekt = x['id'] as String),
            title: Text('${x['kennung']} · ${x['name']}'),
            subtitle: Text('jetzt: ${widget.plan.status.where((s) => s.name == x['status']).firstOrNull?.label ?? x['status']}'),
          ),
        if (o != null) ...[
          const Divider(),
          Text('2. Neuer Status', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in widget.plan.status)
              FilledButton.tonal(
                onPressed: s.name == o['status'] ? null : () => Navigator.pop(context, {'objekt': o['id'], 'status': s.name}),
                child: Text(s.label),
              ),
          ]),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------------ Grundriss

class GrundrissSeite extends StatefulWidget {
  const GrundrissSeite({super.key, required this.plan, required this.einstellungen});
  final Planstand plan;
  final MobilEinstellungen einstellungen;

  @override
  State<GrundrissSeite> createState() => _GrundrissSeiteState();
}

class _GrundrissSeiteState extends State<GrundrissSeite> {
  String? _geschoss;
  final Set<String> _aus = {};

  @override
  Widget build(BuildContext context) {
    final g = widget.plan.geschoss(_geschoss ?? widget.einstellungen.geschoss);
    if (g == null) return const Center(child: Text('Kein Geschoss im Planstand.'));
    final gewerke = widget.plan.gewerke;
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), children: [
          for (final x in widget.plan.geschosse)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text('${x['kuerzel']}'), selected: x['id'] == g['id'], onSelected: (_) => setState(() => _geschoss = x['id'] as String)),
            ),
          const VerticalDivider(),
          for (final e in gewerke.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                avatar: CircleAvatar(backgroundColor: e.value.farbe, radius: 6),
                label: Text(e.value.name),
                selected: !_aus.contains(e.key),
                onSelected: (v) => setState(() => v ? _aus.remove(e.key) : _aus.add(e.key)),
              ),
            ),
        ]),
      ),
      Expanded(child: GrundrissAnsicht(plan: widget.plan, geschoss: g, aus: _aus, bohrCheck: true)),
    ]);
  }
}

/// Grundriss zum Ansehen (Zoomen/Verschieben), Bohr-Check per Antippen oder
/// Position wählen ([waehlen]).
class GrundrissAnsicht extends StatefulWidget {
  const GrundrissAnsicht({super.key, required this.plan, required this.geschoss, this.aus = const {}, this.waehlen, this.bohrCheck = false});
  final Planstand plan;
  final Map<String, dynamic> geschoss;
  final Set<String> aus;
  final ValueChanged<Offset>? waehlen;
  final bool bohrCheck;

  @override
  State<GrundrissAnsicht> createState() => _GrundrissAnsichtState();
}

class _GrundrissAnsichtState extends State<GrundrissAnsicht> {
  final _tc = TransformationController();
  Offset? _markiert;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final g = widget.geschoss;
      final alle = [
        for (final w in Planstand.liste(g['waende'])) ...[punkt(w['a']), punkt(w['b'])],
        for (final r in Planstand.liste(g['raeume'])) ...punkte(r['umriss']),
      ];
      if (alle.isEmpty) return const Center(child: Text('Keine Wände in diesem Geschoss.'));
      var x0 = alle.first.dx, y0 = alle.first.dy, x1 = x0, y1 = y0;
      for (final q in alle) {
        x0 = math.min(x0, q.dx);
        y0 = math.min(y0, q.dy);
        x1 = math.max(x1, q.dx);
        y1 = math.max(y1, q.dy);
      }
      const rand = 40.0;
      final m = math.min((c.maxWidth - 2 * rand) / math.max(1, x1 - x0), (c.maxHeight - 2 * rand) / math.max(1, y1 - y0));
      Offset zuBild(Offset w) => Offset(rand + (w.dx - x0) * m, rand + (w.dy - y0) * m);
      Offset zuWelt(Offset b) => Offset((b.dx - rand) / m + x0, (b.dy - rand) / m + y0);
      return GestureDetector(
        onTapUp: (d) {
          final welt = zuWelt(_tc.toScene(d.localPosition));
          if (widget.waehlen != null) {
            widget.waehlen!(welt);
            return;
          }
          if (!widget.bohrCheck) return;
          setState(() => _markiert = welt);
          final treffer = bohrCheck(g, welt);
          showModalBottomSheet<void>(
            context: context,
            builder: (_) => ListView(padding: const EdgeInsets.all(16), shrinkWrap: true, children: [
              Text(treffer.isEmpty ? 'Bohr-Check: frei ✓' : 'Bohr-Check: ${treffer.length} Leitung(en)/Gerät(e) in 30 cm',
                  style: TextStyle(fontWeight: FontWeight.w600, color: treffer.isEmpty ? const Color(0xFF2F9E44) : const Color(0xFFB91C1C))),
              const SizedBox(height: 8),
              for (final (o, d) in treffer)
                ListTile(
                  dense: true,
                  leading: Icon(d < 100 ? Icons.dangerous_outlined : Icons.warning_amber, color: d < 100 ? const Color(0xFFB91C1C) : const Color(0xFFB45309)),
                  title: Text('${o['kennung']} · ${o['name']}'),
                  subtitle: Text('${(d / 10).round()} cm entfernt${o['lage'] == null ? '' : ' · ${o['lage']}'}${o['z'] == null ? '' : ' · Höhe ${o['z']} mm'}'),
                ),
              const Text('Ohne Gewähr – vor dem Bohren mit Leitungssucher prüfen.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            ]),
          );
        },
        child: InteractiveViewer(
          transformationController: _tc,
          minScale: 0.5,
          maxScale: 12,
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _PlanPainter(plan: widget.plan, g: g, aus: widget.aus, zuBild: zuBild, m: m, markiert: _markiert),
          ),
        ),
      );
    });
  }
}

class _PlanPainter extends CustomPainter {
  _PlanPainter({required this.plan, required this.g, required this.aus, required this.zuBild, required this.m, this.markiert});
  final Planstand plan;
  final Map<String, dynamic> g;
  final Set<String> aus;
  final Offset Function(Offset) zuBild;
  final double m;
  final Offset? markiert;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final r in Planstand.liste(g['raeume'])) {
      final u = punkte(r['umriss']);
      if (u.length < 3) continue;
      canvas.drawPath(Path()..addPolygon([for (final q in u) zuBild(q)], true), Paint()..color = const Color(0xFFF1F3F5));
      var cx = 0.0, cy = 0.0;
      for (final q in u) {
        cx += q.dx;
        cy += q.dy;
      }
      final tp = TextPainter(text: TextSpan(text: '${r['name']}', style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, zuBild(Offset(cx / u.length, cy / u.length)) - Offset(tp.width / 2, tp.height / 2));
    }
    for (final w in Planstand.liste(g['waende'])) {
      canvas.drawLine(zuBild(punkt(w['a'])), zuBild(punkt(w['b'])), Paint()
        ..color = BsFarben.wandBestand
        ..strokeWidth = math.max(1.5, ((w['d'] as num?)?.toDouble() ?? 175) * m)
        ..strokeCap = StrokeCap.square);
    }
    final gewerke = plan.gewerke;
    for (final o in Planstand.liste(g['objekte'])) {
      if (aus.contains(o['gewerk'])) continue;
      final farbe = gewerke[o['gewerk']]?.farbe ?? const Color(0xFF888888);
      final pts = [for (final q in punkte(o['punkte'])) zuBild(q)];
      if (pts.isEmpty) continue;
      switch (o['geometrie']) {
        case 'linie':
          canvas.drawPath(Path()..addPolygon(pts, false), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = farbe);
        case 'flaeche':
          canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = farbe.withValues(alpha: 0.12));
        default:
          canvas.drawCircle(pts.first, 6, Paint()..color = farbe);
          final tp = TextPainter(text: TextSpan(text: '${o['typ']}', style: const TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, pts.first - Offset(tp.width / 2, tp.height / 2));
      }
    }
    final mk = markiert;
    if (mk != null) {
      final c = zuBild(mk);
      canvas.drawCircle(c, 300 * m, Paint()..color = const Color(0x22E03131));
      canvas.drawCircle(c, 4, Paint()..color = const Color(0xFFE03131));
    }
  }

  @override
  bool shouldRepaint(_PlanPainter old) => true;
}

// ------------------------------------------------------------------ Einkauf

class EinkaufSeite extends StatefulWidget {
  const EinkaufSeite({super.key, required this.plan, required this.erfasst});
  final Planstand plan;
  final Future<void> Function(Map<String, dynamic> eintrag, {List<int>? foto}) erfasst;

  @override
  State<EinkaufSeite> createState() => _EinkaufSeiteState();
}

class _EinkaufSeiteState extends State<EinkaufSeite> {
  final Set<String> _erledigt = {};

  @override
  Widget build(BuildContext context) {
    final liste = widget.plan.einkauf;
    if (liste.isEmpty) return const Center(child: Text('Die Einkaufsliste ist leer.'));
    final nachHaendler = <String, List<Map<String, dynamic>>>{};
    for (final e in liste) {
      nachHaendler.putIfAbsent('${e['haendler']}', () => []).add(e);
    }
    return ListView(children: [
      for (final h in nachHaendler.entries) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(h.key, style: Theme.of(context).textTheme.titleSmall)),
        for (final e in h.value)
          CheckboxListTile(
            value: _erledigt.contains(e['id']) || e['status'] == 'geliefert',
            onChanged: (v) async {
              setState(() => v == true ? _erledigt.add(e['id'] as String) : _erledigt.remove(e['id']));
              await widget.erfasst({'art': 'einkauf', 'position': e['id'], 'erledigt': v == true});
            },
            title: Text('${e['text']}'),
            subtitle: Text([
              '${_menge(e['menge'])} ${e['einheit']}',
              if (e['link'] != null) '${e['link']}',
            ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
      ],
    ]);
  }

  String _menge(Object? m) {
    final x = (m as num?)?.toDouble() ?? 0;
    return x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(1).replaceAll('.', ',');
  }
}
