import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app/theme.dart';
import '../core/abgleich_projekt.dart';
import '../core/geschossuebergreifend.dart' show deckendicke;
import '../core/height.dart';
import '../core/hydraulik.dart';
import '../core/kennung.dart';
import '../core/ki.dart' show Regelwerte;
import '../data/models.dart';
import '../state/app_state.dart';
import 'benutzer_rollen.dart';
import 'dialogs.dart' show geschossDialog;
import 'installation/installation_page.dart' show objektVorgabe;
import 'widgets.dart';

const _leise = TextStyle(fontSize: 12, color: BsFarben.textLeise);

String _geoText(Geometrieart g) => switch (g) { Geometrieart.punkt => 'Punkt (Gerät)', Geometrieart.linie => 'Linie (Leitung)', Geometrieart.flaeche => 'Fläche' };

Widget _kopf(BuildContext context, String art, String titel, String text) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(art, style: _leise),
      Text(titel, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(text),
      const SizedBox(height: 16),
    ]);

Widget _zahlFeld(String schluessel, String label, num wert, ValueChanged<double> setzen, {String suffix = '', double breite = 200, String? hilfe}) => SizedBox(
      width: breite,
      child: SpeicherFeld(
        key: ValueKey('$schluessel-$wert'),
        initialValue: wert == wert.roundToDouble() ? wert.round().toString() : wert.toString().replaceAll('.', ','),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]'))],
        decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: hilfe, helperMaxLines: 2, isDense: true),
        onFieldSubmitted: (v) {
          final z = double.tryParse(v.trim().replaceAll(',', '.'));
          if (z != null) setzen(z);
        },
      ),
    );

// ------------------------------------------------------------- Zeichnen (PC)

/// Einstellungen › Zeichnen: Vorgaben für Grundriss und Plan auf diesem PC.
class ZeichnenAnsicht extends StatefulWidget {
  const ZeichnenAnsicht({super.key, required this.state});
  final AppState state;
  @override
  State<ZeichnenAnsicht> createState() => _ZeichnenAnsichtState();
}

class _ZeichnenAnsichtState extends State<ZeichnenAnsicht> {
  Map<String, dynamic> get _d => widget.state.settings.darstellung;
  void _setzen(String k, Object? v) {
    setState(() {
      if (v == null) {
        _d.remove(k);
      } else {
        _d[k] = v;
      }
    });
    widget.state.settings.speichern();
    widget.state.geaendert();
  }

  double _z(String k, double v) => (_d[k] as num?)?.toDouble() ?? v;

  @override
  Widget build(BuildContext context) {
    final s = widget.state.settings;
    return ListView(padding: const EdgeInsets.all(28), children: [
      _kopf(context, 'Programmeinstellung · gilt nur auf diesem PC', 'Zeichnen', 'Vorgaben für Grundriss, Maße und Fang. Gilt ab dem nächsten Öffnen des Grundrisses.'),
      Wrap(spacing: 24, runSpacing: 16, children: [
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: const [115, 175, 240, 300, 365, 425].contains(_z('wand_dicke', 240).round()) ? _z('wand_dicke', 240).round() : 240,
            decoration: const InputDecoration(labelText: 'Wanddicke für neue Wände'),
            items: [for (final d in const [115, 175, 240, 300, 365, 425]) DropdownMenuItem(value: d, child: Text('$d mm'))],
            onChanged: (v) => _setzen('wand_dicke', v),
          ),
        ),
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: const [10, 50, 100, 250].contains(_z('raster_mm', 50).round()) ? _z('raster_mm', 50).round() : 50,
            decoration: const InputDecoration(labelText: 'Raster beim Zeichnen'),
            items: [for (final d in const [10, 50, 100, 250]) DropdownMenuItem(value: d, child: Text('$d mm'))],
            onChanged: (v) => _setzen('raster_mm', v),
          ),
        ),
      ]),
      const SizedBox(height: 24),
      Text('Maße im Grundriss je Zoom', style: Theme.of(context).textTheme.titleMedium),
      Text('Dichte ${_z('mass_dichte', 1).toStringAsFixed(2).replaceAll('.', ',')} (größer = weniger Maße, kleiner = mehr)'),
      Slider(value: _z('mass_dichte', 1).clamp(0.5, 3.0), min: 0.5, max: 3, divisions: 25, onChanged: (v) => _setzen('mass_dichte', v)),
      Text('Schriftgröße der Maße ${(_z('mass_schrift', 1) * 100).round()} %'),
      Slider(value: _z('mass_schrift', 1).clamp(0.7, 2.0), min: 0.7, max: 2, divisions: 13, onChanged: (v) => _setzen('mass_schrift', v)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () {
            _setzen('mass_dichte', null);
            _setzen('mass_schrift', null);
          },
          child: const Text('Maße zurücksetzen'),
        ),
      ),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: s.hilfeAnzeigen,
        title: const Text('Erklärungen rechts neben dem Plan zeigen'),
        onChanged: (v) {
          s.hilfeAnzeigen = v;
          s.speichern();
          setState(() {});
        },
      ),
    ]);
  }
}

// ------------------------------------------------------------- Projekt und Geschosse

/// Einstellungen › Projekt und Geschosse: Gebäude, Geschosse mit Bezugshöhen
/// und Deckendicke, Sicherungen.
class ProjektGeschosseAnsicht extends StatefulWidget {
  const ProjektGeschosseAnsicht({super.key, required this.state});
  final AppState state;
  @override
  State<ProjektGeschosseAnsicht> createState() => _ProjektGeschosseState();
}

class _ProjektGeschosseState extends State<ProjektGeschosseAnsicht> {
  AppState get _s => widget.state;

  void _neu() {
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store;
    if (store == null) return const Center(child: Text('Kein Projekt geöffnet.'));
    final sicherungen = store.sicherungen();
    return ListView(padding: const EdgeInsets.all(28), children: [
      _kopf(context, 'Projekteinstellung', 'Projekt und Geschosse',
          'Projektordner: ${store.ordner}. Höhen je Geschoss in mm (Nullpunkt = Rohfußboden des Geschosses). Die Deckendicke braucht BauSpur für Leitungen über mehrere Geschosse.'),
      for (final geb in store.gebaeude()) ...[
        SizedBox(
          width: 360,
          child: SpeicherFeld(
            key: ValueKey('geb-${geb.id}-${geb.name}'),
            initialValue: geb.name,
            decoration: const InputDecoration(labelText: 'Gebäude'),
            onFieldSubmitted: (v) {
              if (v.trim().isEmpty) return;
              store.gebaeudeUmbenennen(geb.id, v.trim());
              _neu();
            },
          ),
        ),
        const SizedBox(height: 8),
        for (final g in store.geschosse(geb.id))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 180,
                  child: SpeicherFeld(
                    key: ValueKey('gn-${g.id}-${g.name}'),
                    initialValue: g.name,
                    decoration: const InputDecoration(labelText: 'Geschoss', isDense: true),
                    onFieldSubmitted: (v) {
                      if (v.trim().isEmpty) return;
                      store.geschossAendern(g.id, name: v.trim());
                      _neu();
                    },
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: SpeicherFeld(
                    key: ValueKey('gk-${g.id}-${g.kuerzel}'),
                    initialValue: g.kuerzel,
                    decoration: const InputDecoration(labelText: 'Kürzel', isDense: true),
                    onFieldSubmitted: (v) {
                      if (v.trim().isEmpty) return;
                      store.geschossAendern(g.id, kuerzel: v.trim());
                      _neu();
                    },
                  ),
                ),
                for (final (k, label, wert) in [
                  ('rfb', 'RFB', g.hoehen.rfb),
                  ('ffb', 'FFB', g.hoehen.ffb),
                  ('rohdecke', 'Rohdecke', g.hoehen.rohdecke),
                  ('meterriss', 'Meterriss', g.hoehen.meterriss),
                ])
                  _zahlFeld('$k-${g.id}', label, wert, (v) {
                    final n = v.round();
                    switch (k) {
                      case 'rfb':
                        store.geschossAendern(g.id, rfb: n);
                      case 'ffb':
                        store.geschossAendern(g.id, ffb: n);
                      case 'rohdecke':
                        store.geschossAendern(g.id, rohdecke: n);
                      default:
                        store.geschossAendern(g.id, meterriss: n);
                    }
                    _neu();
                  }, suffix: 'mm', breite: 110),
                _zahlFeld('dd-${g.id}', 'Decke darüber', deckendicke(store, g), (v) {
                  store.einstellungSetzen('deckendicke', {...(store.einstellung<Map>('deckendicke') ?? const {}), g.id: v.round()});
                  _neu();
                }, suffix: 'mm', breite: 130),
                Text('lichte Höhe ${g.hoehen.rohdecke - g.hoehen.ffb} mm', style: _leise),
              ]),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              if (await geschossDialog(context, store, geb.id)) _neu();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Geschoss anlegen'),
          ),
        ),
        const SizedBox(height: 16),
      ],
      const Divider(),
      Text('Sicherungen', style: Theme.of(context).textTheme.titleMedium),
      Text('Beim Öffnen legt BauSpur automatisch eine Sicherung an (die letzten 20 bleiben). ${sicherungen.length} vorhanden'
          '${sicherungen.isEmpty ? '' : ', neueste ${p.basename(sicherungen.first.path).replaceAll('projekt_', '').replaceAll('.bauspur', '')}'}.'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () {
            store.sicherungJetzt();
            zeigeHinweis(context, 'Sicherung angelegt.');
            setState(() {});
          },
          icon: const Icon(Icons.backup_outlined, size: 18),
          label: const Text('Jetzt sichern'),
        ),
        OutlinedButton.icon(
          onPressed: () => Process.run('explorer', [p.join(store.ordner, 'backup')]),
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('Sicherungsordner öffnen'),
        ),
      ]),
    ]);
  }
}

// ------------------------------------------------------------- Objekttypen

/// Einstellungen › Objekttypen und Symbole: alle Typen je Gewerk, eigene Typen,
/// Standardhöhe/Bezug/Lage beim Setzen.
class ObjekttypenAnsicht extends StatefulWidget {
  const ObjekttypenAnsicht({super.key, required this.state});
  final AppState state;
  @override
  State<ObjekttypenAnsicht> createState() => _ObjekttypenState();
}

class _ObjekttypenState extends State<ObjekttypenAnsicht> {
  AppState get _s => widget.state;
  String? _gewerk;

  static const _lagen = objektLagen;

  void _vorgabeSetzen(Objekttyp t, Map<String, Object?> neu) {
    final store = _s.store!;
    final alle = Map<String, dynamic>.from(store.einstellung<Map>('objekt_vorgaben') ?? const {});
    final e = {...Map<String, dynamic>.from(alle[t.kuerzel] as Map? ?? const {}), ...neu}..removeWhere((_, v) => v == null);
    if (e.isEmpty) {
      alle.remove(t.kuerzel);
    } else {
      alle[t.kuerzel] = e;
    }
    store.einstellungSetzen('objekt_vorgaben', alle);
    _s.geaendert();
    setState(() {});
  }

  Future<void> _neuerTyp(Gewerk g) async {
    final name = TextEditingController(), kuerzel = TextEditingController();
    var geo = Geometrieart.punkt;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Eigener Objekttyp in ${g.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name, z. B. Bodensteckdose')),
            TextField(controller: kuerzel, decoration: const InputDecoration(labelText: 'Kürzel (2 Buchstaben, steht in der Kennung)'), maxLength: 3),
            const SizedBox(height: 8),
            SegmentedButton<Geometrieart>(
              segments: [for (final x in Geometrieart.values) ButtonSegment(value: x, label: Text(_geoText(x)))],
              selected: {geo},
              onSelectionChanged: (v) => setD(() => geo = v.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Anlegen')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final vorschlag = kuerzelVorschlag(name.text);
    final k = (kuerzel.text.trim().isEmpty ? vorschlag.substring(0, vorschlag.length.clamp(1, 2)) : kuerzel.text.trim()).toUpperCase();
    _s.store!.objekttypAnlegen(gewerkId: g.id, name: name.text.trim(), kuerzel: k, geometrie: geo);
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store;
    if (store == null) return const Center(child: Text('Kein Projekt geöffnet.'));
    final gewerke = store.gewerke();
    final g = gewerke.where((x) => x.id == _gewerk).firstOrNull ?? gewerke.firstOrNull;
    final vorgaben = store.einstellung<Map>('objekt_vorgaben') ?? const {};
    final typen = [for (final t in store.objekttypen()) if (t.gewerkId == g?.id) t];
    return ListView(padding: const EdgeInsets.all(28), children: [
      _kopf(context, 'Projekteinstellung', 'Objekttypen und Symbole',
          'Welche Objekte es je Gewerk gibt und mit welcher Höhe und Lage sie gesetzt werden. Eigene Typen ergänzen; die Kürzel stehen in den Kennungen.'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in gewerke)
          ChoiceChip(
            avatar: CircleAvatar(backgroundColor: Color(x.farbe), radius: 6),
            label: Text(x.name),
            selected: x.id == g?.id,
            onSelected: (_) => setState(() => _gewerk = x.id),
          ),
      ]),
      const SizedBox(height: 12),
      if (g != null)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: () => _neuerTyp(g), icon: const Icon(Icons.add, size: 18), label: Text('Eigener Typ in ${g.name}')),
        ),
      const SizedBox(height: 8),
      for (final t in typen)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              CircleAvatar(radius: 14, backgroundColor: Color(g?.farbe ?? 0xFF888888), child: Text(t.kuerzel, style: const TextStyle(fontSize: 10, color: Colors.white))),
              SizedBox(
                width: 260,
                child: SpeicherFeld(
                  key: ValueKey('tn-${t.id}-${t.name}'),
                  initialValue: t.name,
                  decoration: InputDecoration(labelText: _geoText(t.geometrie), isDense: true),
                  onFieldSubmitted: (v) {
                    if (v.trim().isEmpty) return;
                    store.objekttypUmbenennen(t.id, v.trim());
                    _s.geaendert();
                    setState(() {});
                  },
                ),
              ),
              if (t.geometrie != Geometrieart.flaeche) ...[
                Builder(builder: (_) {
                  final (z, bezug, _) = objektVorgabe(t, eigene: vorgaben);
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    _zahlFeld('tz-${t.id}', 'Höhe', z ?? 0, (v) => _vorgabeSetzen(t, {'z': v.round()}), suffix: 'mm', breite: 110),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<Hoehenbezug>(
                        key: ValueKey('tb-${t.id}-$bezug'),
                        initialValue: bezug ?? Hoehenbezug.ffb,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Bezug', isDense: true),
                        items: [for (final b in Hoehenbezug.values) DropdownMenuItem(value: b, child: Text(b.label))],
                        onChanged: (b) => _vorgabeSetzen(t, {'bezug': b?.name}),
                      ),
                    ),
                  ]);
                }),
              ],
              Builder(builder: (_) {
                final (_, _, lage) = objektVorgabe(t, eigene: vorgaben);
                return SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('tl-${t.id}-$lage'),
                    initialValue: _lagen.contains(lage) ? lage : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Lage beim Setzen', isDense: true),
                    items: [for (final l in _lagen) DropdownMenuItem(value: l, child: Text(l))],
                    onChanged: (l) => _vorgabeSetzen(t, {'lage': l}),
                  ),
                );
              }),
              if (vorgaben[t.kuerzel] != null)
                TextButton(onPressed: () => _vorgabeSetzen(t, {'z': null, 'bezug': null, 'lage': null}), child: const Text('Standard')),
            ]),
          ),
        ),
    ]);
  }
}

// ------------------------------------------------------------- Kennungen

class KennungenAnsicht extends StatefulWidget {
  const KennungenAnsicht({super.key, required this.state});
  final AppState state;
  @override
  State<KennungenAnsicht> createState() => _KennungenState();
}

class _KennungenState extends State<KennungenAnsicht> {
  AppState get _s => widget.state;

  void _setzen(String k, Object? v) {
    final store = _s.store!;
    store.einstellungSetzen('kennung', {...Map<String, dynamic>.from(store.einstellung<Map>('kennung') ?? const {}), k: v});
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store;
    if (store == null) return const Center(child: Text('Kein Projekt geöffnet.'));
    final m = store.einstellung<Map>('kennung') ?? const {};
    final trenner = m['trenner'] as String? ?? '-';
    final stellen = (m['stellen'] as num?)?.toInt() ?? 2;
    final mitG = m['geschoss'] as bool? ?? true, mitR = m['raum'] as bool? ?? true;
    final praefix = m['praefix'] as String? ?? '';
    final beispiel = naechsteKennung(geschoss: 'EG', raum: 'BAD', typ: 'SD', vorhandene: const [], trenner: trenner, stellen: stellen, mitGeschoss: mitG, mitRaum: mitR, praefix: praefix);
    return ListView(padding: const EdgeInsets.all(28), children: [
      _kopf(context, 'Projekteinstellung', 'Kennungen', 'Wie neue Objekte benannt werden. Vorhandene Kennungen bleiben, wie sie sind (sie stehen schon auf Plänen und Fotos).'),
      Text('Beispiel: $beispiel', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: const ['-', '.', '_', '/'].contains(trenner) ? trenner : '-',
            decoration: const InputDecoration(labelText: 'Trennzeichen'),
            items: [for (final t in const ['-', '.', '_', '/']) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => _setzen('trenner', v),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: stellen.clamp(1, 4),
            decoration: const InputDecoration(labelText: 'Stellen der Nummer'),
            items: [for (final n in const [1, 2, 3, 4]) DropdownMenuItem(value: n, child: Text('$n (${'1'.padLeft(n, '0')})'))],
            onChanged: (v) => _setzen('stellen', v),
          ),
        ),
        SizedBox(
          width: 200,
          child: SpeicherFeld(
            key: ValueKey('pf-$praefix'),
            initialValue: praefix,
            decoration: const InputDecoration(labelText: 'Präfix (z. B. Gebäude HH)'),
            onFieldSubmitted: (v) => _setzen('praefix', v.trim()),
          ),
        ),
      ]),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: mitG, title: const Text('Geschoss in der Kennung'), onChanged: (v) => _setzen('geschoss', v)),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: mitR, title: const Text('Raum in der Kennung'), onChanged: (v) => _setzen('raum', v)),
    ]);
  }
}

// ------------------------------------------------------------- Planung und Vorgaben

/// Einstellungen › Planung und Vorgaben: Werte, mit denen BauSpur rechnet.
class VorgabenAnsicht extends StatefulWidget {
  const VorgabenAnsicht({super.key, required this.state});
  final AppState state;
  @override
  State<VorgabenAnsicht> createState() => _VorgabenState();
}

class _VorgabenState extends State<VorgabenAnsicht> {
  AppState get _s => widget.state;

  void _setzen(String k, Object v) {
    _s.store!.einstellungSetzen(k, v);
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store;
    if (store == null) return const Center(child: Text('Kein Projekt geöffnet.'));
    num z(String k, num v) => store.einstellung<num>(k) ?? v;
    final regeln = Regelwerte.ausJson(store.einstellung<Map>('regeln')?.cast<String, dynamic>());
    final ab = abgleichEinstellung(store);
    Widget gruppe(String titel, List<Widget> felder, [String? text]) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titel, style: Theme.of(context).textTheme.titleMedium),
            if (text != null) Text(text, style: _leise),
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 12, children: felder),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(28), children: [
      _kopf(context, 'Projekteinstellung', 'Planung und Vorgaben', 'Werte, mit denen BauSpur in diesem Projekt rechnet und prüft.'),
      gruppe('Material und Einkauf', [
        _zahlFeld('verschnitt', 'Verschnitt Leitungen, Rohre, Kanäle', z('verschnitt_prozent', 10), (v) => _setzen('verschnitt_prozent', v), suffix: '%'),
        _zahlFeld('zuschlag', 'Zuschlag Einkauf (Plan/Ist)', z('einkauf_zuschlag', 10), (v) => _setzen('einkauf_zuschlag', v), suffix: '%'),
      ]),
      gruppe('Prüfregeln', [
        _zahlFeld('kreis', 'max. Heizkreislänge', regeln.maxKreislaengeM, (v) => _setzen('regeln', Regelwerte(maxKreislaengeM: v.round(), minReserveSchrank: regeln.minReserveSchrank, minAbstandWasserElektro: regeln.minAbstandWasserElektro, lichtAnteilZiel: regeln.lichtAnteilZiel).toJson()), suffix: 'm'),
        _zahlFeld('reserve', 'Reserve im Verteilerschrank', regeln.minReserveSchrank, (v) => _setzen('regeln', Regelwerte(maxKreislaengeM: regeln.maxKreislaengeM, minReserveSchrank: v.round(), minAbstandWasserElektro: regeln.minAbstandWasserElektro, lichtAnteilZiel: regeln.lichtAnteilZiel).toJson()), suffix: '%'),
        _zahlFeld('we', 'Abstand Wasser ↔ Elektro', regeln.minAbstandWasserElektro, (v) => _setzen('regeln', Regelwerte(maxKreislaengeM: regeln.maxKreislaengeM, minReserveSchrank: regeln.minReserveSchrank, minAbstandWasserElektro: v.round(), lichtAnteilZiel: regeln.lichtAnteilZiel).toJson()), suffix: 'mm'),
        _zahlFeld('rev', 'Reichweite Revisionsöffnung', z('revision_reichweite', 400), (v) => _setzen('revision_reichweite', v.round()), suffix: 'mm'),
        _zahlFeld('bohr', 'Bohr-Check: Umkreis', z('bohr_radius', 300), (v) => _setzen('bohr_radius', v.round()), suffix: 'mm'),
      ]),
      gruppe('Hydraulischer Abgleich', [
        _zahlFeld('spr', 'Spreizung', ab.spreizung, (v) => _setzen('abgleich', ab.mit(spreizung: v).toJson()), suffix: 'K'),
        _zahlFeld('wm2', 'Leistung ohne Heizlast', ab.spezLeistung, (v) => _setzen('abgleich', ab.mit(spezLeistung: v).toJson()), suffix: 'W/m²'),
        _zahlFeld('di', 'Heizrohr innen', ab.rohrInnen, (v) => _setzen('abgleich', ab.mit(rohrInnen: v).toJson()), suffix: 'mm'),
        _zahlFeld('kvo', 'kv Ventil voll offen', ab.kvOffen, (v) => _setzen('abgleich', ab.mit(kvOffen: v).toJson()), suffix: 'm³/h'),
      ], 'Gilt für alle Verteiler; die kv-Stufen stellst du im Abgleich selbst ein (Standard: ${AbgleichEinstellung.standardKvStufen.length} Stufen).'),
    ]);
  }
}

/// Einstellungen › Benutzer und Rollen (Projekt).
class BenutzerAnsicht extends StatelessWidget {
  const BenutzerAnsicht({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(28), children: [
        _kopf(context, 'Projekteinstellung', 'Benutzer und Rollen', 'Wer mit der App mitarbeitet oder nur liest. Jeder bekommt einen eigenen Kopplungscode.'),
        BenutzerRollenKarte(state: state),
      ]);
}
