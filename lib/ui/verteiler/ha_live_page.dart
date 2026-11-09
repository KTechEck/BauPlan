import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/ha_live.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Rolle einer Zuordnung, die aus dem KNX-Vorschlag stammt (nicht beim Objekt gespeichert).
const haRolleVorschlag = 'KNX-Vorschlag';

/// Home Assistant live: nur lesende Verbindung, Zustände der zugeordneten
/// Entitäten, fehlende und nicht zugeordnete Entitäten.
class HaLivePage extends StatefulWidget {
  const HaLivePage({super.key, required this.state, required this.zuordnungen, this.verbindung});
  final AppState state;
  final List<HaZuordnung> zuordnungen;

  /// Für Tests: vorgegebene Verbindung.
  final HaVerbindung? verbindung;

  @override
  State<HaLivePage> createState() => _HaLivePageState();
}

class _HaLivePageState extends State<HaLivePage> {
  late HaEinstellung _e = HaEinstellung.ausJson(widget.state.settings.ha);
  late final _adresse = TextEditingController(text: _e.adresse);
  late final _token = TextEditingController(text: _e.token);
  late List<HaZuordnung> _zuordnungen = widget.zuordnungen;
  List<HaEntitaet>? _ha;
  String? _info, _fehler;
  bool _laedt = false, _automatisch = true;
  DateTime? _stand;
  Timer? _timer;
  HaVerbindung? _v;

  @override
  void initState() {
    super.initState();
    if (widget.verbindung != null || _e.sperre == null) _laden();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.verbindung == null) _v?.schliessen();
    _adresse.dispose();
    _token.dispose();
    super.dispose();
  }

  void _einstellungSpeichern({bool? fremd}) {
    _e = HaEinstellung(adresse: _adresse.text.trim(), token: _token.text.trim(), fremdzugriff: fremd ?? _e.fremdzugriff);
    widget.state.settings
      ..ha = _e.toJson()
      ..speichern();
    if (widget.verbindung == null) {
      _v?.schliessen();
      _v = null;
    }
  }

  Future<void> _laden({bool neu = false}) async {
    if (neu) _einstellungSpeichern();
    final v = widget.verbindung ?? (_v ??= HaVerbindung(_e));
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    try {
      if (_info == null || neu) _info = await v.pruefen();
      final ha = await v.zustaende();
      if (!mounted) return;
      setState(() {
        _ha = ha;
        _stand = DateTime.now();
      });
      _timer?.cancel();
      if (_automatisch) _timer = Timer(const Duration(seconds: 10), () => mounted ? _laden() : null);
    } catch (e) {
      if (mounted) setState(() => _fehler = '$e'.replaceFirst(RegExp(r'^(Bad state|HttpException|SocketException): '), ''));
    } finally {
      if (mounted) setState(() => _laedt = false);
    }
  }

  void _zuordnen(HaZuordnung z, String entity) {
    final store = widget.state.store!;
    final o = store.alleObjekte().where((x) => x.id == z.objektId).firstOrNull;
    if (o == null) return;
    final eig = {...o.eigenschaften};
    if (z.rolle == 'Objekt' || z.rolle == haRolleVorschlag) {
      eig['ha_entity'] = entity;
    } else {
      eig['ha_entities'] = {...Map<String, dynamic>.from(eig['ha_entities'] as Map? ?? const {}), z.rolle: entity};
    }
    store.objektAendern(o.id, {'eigenschaften': jsonEncode(eig)});
    widget.state.geaendert();
    setState(() {
      _zuordnungen = [
        for (final x in _zuordnungen)
          if (identical(x, z)) (entity: entity, objektId: z.objektId, objekt: z.objekt, rolle: z.rolle == haRolleVorschlag ? 'Objekt' : z.rolle) else x,
      ];
    });
    zeigeHinweis(context, '${z.objekt}: $entity eingetragen.');
  }

  @override
  Widget build(BuildContext context) {
    final sperre = HaEinstellung(adresse: _adresse.text, token: _token.text, fremdzugriff: _e.fremdzugriff).sperre;
    return Scaffold(
      appBar: AppBar(title: const Text('Home Assistant live')),
      backgroundColor: BsFarben.flaeche,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _adresse,
                    decoration: const InputDecoration(labelText: 'Adresse', hintText: 'http://homeassistant.local:8123'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _token,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Langlebiger Zugangs-Token'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                FilterChip(
                  label: const Text('Fremdzugriff (https)'),
                  tooltip: 'Verbindung auch über das Internet erlauben, z. B. Nabu Casa oder eigene Domain. Nur verschlüsselt.',
                  selected: _e.fremdzugriff,
                  onSelected: (v) => setState(() => _einstellungSpeichern(fremd: v)),
                ),
                FilledButton.icon(
                  onPressed: sperre != null || _laedt ? null : () => _laden(neu: true),
                  icon: _laedt ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 18),
                  label: const Text('Verbinden'),
                ),
                FilterChip(
                  label: const Text('alle 10 s aktualisieren'),
                  selected: _automatisch,
                  onSelected: (v) {
                    setState(() => _automatisch = v);
                    if (!v) _timer?.cancel();
                    if (v && _ha != null) _laden();
                  },
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                sperre ??
                    'Nur lesend: BauSpur schaltet nichts. Der Token bleibt in den Einstellungen dieses PCs und wird nicht ins Projekt geschrieben.'
                        '${_e.lokal ? '' : ' Verbindung läuft über das Internet.'}',
                style: TextStyle(fontSize: 12, color: sperre != null ? const Color(0xFFB91C1C) : BsFarben.textLeise),
              ),
              if (_info != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Verbunden mit $_info${_stand == null ? '' : ', Stand ${_uhr(_stand!)}'}')),
              if (_fehler != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_fehler!, style: const TextStyle(color: Color(0xFFB91C1C)))),
            ]),
          ),
        ),
        if (_ha != null) ..._ergebnis(_ha!),
        if (_ha == null && _zuordnungen.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('In BauSpur eingetragen (${_zuordnungen.length})', style: Theme.of(context).textTheme.titleMedium),
          for (final z in _zuordnungen) Text('${z.objekt}: ${z.entity}${z.rolle == 'Objekt' ? '' : ' (${z.rolle})'}'),
        ],
      ]),
    );
  }

  String _uhr(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  Color _zustandFarbe(HaEntitaet e) => !e.erreichbar
      ? const Color(0xFFB91C1C)
      : e.zustand == 'on' || e.zustand == 'open'
          ? const Color(0xFFE67700)
          : BsFarben.textLeise;

  List<Widget> _ergebnis(List<HaEntitaet> ha) {
    final a = haAbgleichen(_zuordnungen, ha);
    Widget titel(String t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(t, style: Theme.of(context).textTheme.titleMedium));
    return [
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        Chip(label: Text('${a.gefunden.length} zugeordnet und erreichbar')),
        Chip(label: Text('${a.nichtErreichbar.length} nicht erreichbar')),
        Chip(label: Text('${a.fehlt.length} fehlen in Home Assistant')),
        Chip(label: Text('${a.unzugeordnet.length} ohne Objekt in BauSpur')),
      ]),
      if (a.fehlt.isNotEmpty) ...[
        titel('Fehlen in Home Assistant'),
        Card(
          child: Column(children: [
            for (final z in a.fehlt)
              () {
                final vorschlag = haVorschlag(z.entity, a.unzugeordnet);
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
                  title: Text('${z.objekt}: ${z.entity}'),
                  subtitle: Text(z.rolle == haRolleVorschlag
                      ? 'aus den Gruppenadressen vorgeschlagen – in HA anders benannt?'
                      : (z.rolle == 'Objekt' ? 'beim Objekt eingetragen' : 'Rolle ${z.rolle}')),
                  trailing: vorschlag == null
                      ? null
                      : TextButton(onPressed: () => _zuordnen(z, vorschlag.id), child: Text('${vorschlag.id} übernehmen')),
                );
              }(),
          ]),
        ),
      ],
      if (a.gefunden.isNotEmpty || a.nichtErreichbar.isNotEmpty) ...[
        titel('Zugeordnete Entitäten'),
        Card(
          child: DataTable(columnSpacing: 20, columns: const [
            DataColumn(label: Text('Objekt')),
            DataColumn(label: Text('Entität')),
            DataColumn(label: Text('Name in HA')),
            DataColumn(label: Text('Zustand')),
          ], rows: [
            for (final (z, e) in [...a.nichtErreichbar, ...a.gefunden])
              DataRow(cells: [
                DataCell(Text(z.objekt)),
                DataCell(Text(e.id)),
                DataCell(Text(e.name)),
                DataCell(Text(e.zustandText, style: TextStyle(color: _zustandFarbe(e), fontWeight: FontWeight.w600))),
              ]),
          ]),
        ),
      ],
      if (a.unzugeordnet.isNotEmpty) ...[
        titel('In Home Assistant, aber keinem Objekt zugeordnet'),
        const Text('Eintragen in der Installation beim Objekt (Feld „Home-Assistant-Entität“).', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        const SizedBox(height: 4),
        Card(
          child: Column(children: [
            for (final e in a.unzugeordnet.take(300))
              ListTile(
                dense: true,
                title: Text(e.id),
                subtitle: e.name.isEmpty ? null : Text(e.name),
                trailing: Text(e.zustandText, style: TextStyle(color: _zustandFarbe(e))),
              ),
            if (a.unzugeordnet.length > 300) Padding(padding: const EdgeInsets.all(8), child: Text('… und ${a.unzugeordnet.length - 300} weitere')),
          ]),
        ),
      ],
    ];
  }
}
