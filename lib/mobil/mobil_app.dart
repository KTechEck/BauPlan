import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import 'kontext.dart';
import 'ordner.dart';
import 'planstand.dart';
import 'seiten/einkauf.dart';
import 'seiten/erfassen.dart';
import 'seiten/mehr.dart';
import 'seiten/plan.dart';
import 'verbindung.dart';

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
        content: Text(_wartend > 0 ? 'Gespeichert – wird übertragen, sobald die Verbindung steht.' : 'Gespeichert und übertragen.'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  MobilKontext _kontext(Planstand plan) => MobilKontext(
        plan: plan,
        einstellungen: _e,
        erfasst: _erfasst,
        abgleichen: _abgleichen,
        verbindungAendern: _verbindungAendern,
        wartend: _wartend,
        ordnerName: _ordnerName,
        kamera: widget.kamera,
      );

  @override
  Widget build(BuildContext context) {
    if (_laedt && _plan == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_ordnerName == null || _plan == null) return _einrichten();
    final k = _kontext(_plan!);
    final seiten = <({IconData icon, String label, Widget seite})>[
      (icon: Icons.add_a_photo_outlined, label: 'Erfassen', seite: ErfassenSeite(k: k)),
      (icon: Icons.architecture, label: 'Plan', seite: PlanSeite(k: k)),
      (icon: Icons.meeting_room_outlined, label: 'Räume', seite: RaeumeListe(k: k)),
      (icon: Icons.shopping_cart_outlined, label: 'Einkauf', seite: EinkaufSeite(k: k)),
      (icon: Icons.more_horiz, label: 'Mehr', seite: MehrSeite(k: k, neuZeichnen: () => setState(() {}))),
    ];
    final tablet = mobilGeraet(context) == MobilGeraet.tablet;
    final kopf = AppBar(
      title: Text(_plan!.projekt),
      actions: [
        if (_wartend > 0)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Chip(avatar: const Icon(Icons.cloud_upload_outlined, size: 16), label: Text('$_wartend wartend')),
          ),
        IconButton(tooltip: 'Abgleichen', onPressed: _abgleichen, icon: const Icon(Icons.sync)),
      ],
    );
    final inhalt = Column(children: [
      if (_meldung != null)
        MaterialBanner(
          content: Text(_meldung!),
          actions: [TextButton(onPressed: () => setState(() => _meldung = null), child: const Text('OK'))],
        ),
      Expanded(
        // iPad: Plan groß mit Räumen daneben; die eigene iPad-Oberfläche folgt
        child: tablet && _seite == 1
            ? Row(children: [
                Expanded(child: seiten[1].seite),
                const VerticalDivider(width: 1),
                SizedBox(width: 340, child: RaeumeListe(k: k)),
              ])
            : seiten[_seite].seite,
      ),
    ]);
    if (tablet) {
      return Scaffold(
        appBar: kopf,
        body: Row(children: [
          NavigationRail(
            selectedIndex: _seite,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _seite = i),
            destinations: [for (final s in seiten) NavigationRailDestination(icon: Icon(s.icon), label: Text(s.label))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: inhalt),
        ]),
      );
    }
    return Scaffold(
      appBar: kopf,
      body: inhalt,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _seite,
        onDestinationSelected: (i) => setState(() => _seite = i),
        destinations: [for (final s in seiten) NavigationDestination(icon: Icon(s.icon), label: s.label)],
      ),
    );
  }

  Widget _einrichten() {
    final o = widget.ordner;
    if (o is FernOrdner) return VerbindungSeite(ordner: o, fertig: _laden);
    return _einrichtenOrdner();
  }

  Future<void> _verbindungAendern() async {
    final o = widget.ordner;
    if (o is! FernOrdner) return _ordnerWaehlen();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (c) => VerbindungSeite(ordner: o, zurueck: true, fertig: () async => Navigator.of(c).pop())));
    await _laden();
  }

  Widget _einrichtenOrdner() => Scaffold(
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
}

