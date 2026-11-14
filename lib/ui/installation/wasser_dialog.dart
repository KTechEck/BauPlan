import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/raumerkennung.dart';
import '../../core/wasser.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

const _rot = Color(0xFFB91C1C);
const _gruen = Color(0xFF2F9E44);
String _z(double v, [int n = 1]) => v.toStringAsFixed(n).replaceAll('.', ',');

/// Wasser: Abwasser (Nennweite, Gefälle), Trinkwasser-Hausanschluss und
/// Wassermelder mit Absperrventil (Home Assistant). Planungshilfe.
Future<void> wasserDialogZeigen(BuildContext context, AppState s) => showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        child: SizedBox(width: 900, height: 640, child: _Wasser(state: s)),
      ),
    );

class _Wasser extends StatefulWidget {
  const _Wasser({required this.state});
  final AppState state;

  @override
  State<_Wasser> createState() => _WasserState();
}

class _WasserState extends State<_Wasser> {
  AppState get _s => widget.state;

  void _eig(Objekt o, Map<String, Object?> w) {
    final neu = {...o.eigenschaften, ...w}..removeWhere((k, v) => v == null);
    _s.store!.objektAendern(o.id, {'eigenschaften': jsonEncode(neu)});
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wasser'),
          automaticallyImplyLeading: false,
          actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))],
          bottom: const TabBar(tabs: [Tab(text: 'Abwasser'), Tab(text: 'Trinkwasser'), Tab(text: 'Wassermelder')]),
        ),
        body: TabBarView(children: [_abwasser(), _trinkwasser(), _wassermelder()]),
      ),
    );
  }

  Map<String, Objekttyp> get _typen => {for (final t in _s.store!.objekttypen()) t.id: t};

  // ---------------------------------------------------------------- Abwasser

  Widget _abwasser() {
    final store = _s.store!;
    final typen = _typen;
    final alle = store.alleObjekte();
    final leitungen = [for (final o in alle) if (typen[o.typId]?.kuerzel == 'AW' && o.punkte.length >= 2) o];
    final gegenstaende = [for (final o in alle) if (abwasserJeKuerzel.containsKey(typen[o.typId]?.kuerzel) && o.punkte.isNotEmpty) o];
    final fallrohre = [for (final o in alle) if (typen[o.typId]?.kuerzel == 'SR' && _gewerk(typen[o.typId]) == 'SA') o];
    if (leitungen.isEmpty) {
      return const Center(child: Text('Noch keine Abwasserleitung (Sanitär › Abwasserleitung) im Plan.'));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
          'Je Abwasserleitung: angeschlossene Gegenstände (Badobjekte in bis 40 cm Nähe eines Leitungspunkts), Schmutzwasserabfluss Qww = 0,5·√ΣDU, '
          'Nennweite, Mindestgefälle (1 % Anschluss, 0,5 % ab DN 90/Grundleitung) und Höhenunterschied. Richtwerte nach DIN 1986-100.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      for (final l in leitungen)
        () {
          final an = [
            for (final g in gegenstaende)
              if (g.geschossId == l.geschossId && l.punkte.any((q) => (q - g.punkte.first).laenge <= 400 || _imUmriss(g, q))) g
          ];
          final du = [for (final g in an) abwasserGegenstaende[abwasserJeKuerzel[typen[g.typId]!.kuerzel]]!.$1];
          final mitWc = an.any((g) => typen[g.typId]?.kuerzel == 'WC');
          final e = l.eigenschaften;
          final r = abwasserPruefen(
            laengeM: l.laenge / 1000,
            du: du,
            dn: (e['dn'] as num?)?.toInt(),
            gefaelleProzent: (e['gefaelle'] as num?)?.toDouble() ?? 1.0,
            grundleitung: e['grundleitung'] == true,
            mitWc: mitWc,
            platzMm: (e['platz_mm'] as num?)?.toDouble(),
          );
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(r.hinweise.isEmpty ? Icons.check_circle : Icons.warning_amber, color: r.hinweise.isEmpty ? _gruen : _rot, size: 18),
                  const SizedBox(width: 6),
                  Text('${l.kennung} · ${_z(l.laenge / 1000, 2)} m', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('ΣDU ${_z(du.fold(0.0, (a, b) => a + b))} · Qww ${_z(r.qww, 2)} l/s · DN ${r.dnSoll} · Δh ${r.hoehenunterschied.round()} mm'),
                ]),
                Text(an.isEmpty ? 'keine Gegenstände erkannt' : an.map((g) => '${g.kennung} (${typen[g.typId]!.name})').join(', '),
                    style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<int?>(
                      initialValue: e['dn'] as int?,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'DN gewählt', isDense: true),
                      items: [const DropdownMenuItem(value: null, child: Text('–')), for (final d in const [40, 50, 70, 90, 100, 125, 150]) DropdownMenuItem(value: d, child: Text('DN $d'))],
                      onChanged: (v) => _eig(l, {'dn': v}),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: SpeicherFeld(
                      key: ValueKey('gef-${l.id}-${e['gefaelle']}'),
                      initialValue: _z(((e['gefaelle'] as num?) ?? 1.0).toDouble()),
                      decoration: const InputDecoration(labelText: 'Gefälle', suffixText: '%', isDense: true),
                      onFieldSubmitted: (t) => _eig(l, {'gefaelle': double.tryParse(t.replaceAll(',', '.'))}),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: SpeicherFeld(
                      key: ValueKey('platz-${l.id}-${e['platz_mm']}'),
                      initialValue: e['platz_mm'] == null ? '' : '${e['platz_mm']}',
                      decoration: const InputDecoration(labelText: 'Platz für Gefälle', suffixText: 'mm', isDense: true, hintText: 'Estrich/Vorwand'),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onFieldSubmitted: (t) => _eig(l, {'platz_mm': int.tryParse(t)}),
                    ),
                  ),
                  FilterChip(label: const Text('Grundleitung'), selected: e['grundleitung'] == true, onSelected: (v) => _eig(l, {'grundleitung': v ? true : null})),
                ]),
                for (final h in r.hinweise) Text('• $h', style: const TextStyle(fontSize: 12, color: _rot)),
              ]),
            ),
          );
        }(),
      if (fallrohre.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Fallleitungen', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final f in fallrohre)
          ListTile(
            dense: true,
            title: Text(f.kennung),
            subtitle: Text('DN ${f.eigenschaften['dn'] ?? 100} · mit Hauptlüftung über Dach · '
                '${(f.eigenschaften['dn'] as num? ?? 100) < 100 && gegenstaende.any((g) => typen[g.typId]?.kuerzel == 'WC') ? 'mit WC mindestens DN 100' : 'ok'}'),
          ),
      ],
    ]);
  }

  bool _imUmriss(Objekt g, Punkt q) => g.punkte.length >= 3 && punktInPolygon(q, g.punkte);

  String? _gewerk(Objekttyp? t) => t == null ? null : _s.store!.gewerke().where((g) => g.id == t.gewerkId).firstOrNull?.kuerzel;

  // ------------------------------------------------------------- Trinkwasser

  Widget _trinkwasser() {
    final store = _s.store!;
    final typen = _typen;
    final alle = store.alleObjekte();
    final kuerzel = [for (final o in alle) if (typen[o.typId] != null) typen[o.typId]!.kuerzel];
    final entn = entnahmenAusObjekten(kuerzel);
    // weitere Entnahmestellen (EN) mit eingetragener Art
    for (final o in alle) {
      final a = o.eigenschaften['entnahme'] as String?;
      if (typen[o.typId]?.kuerzel == 'EN' && a != null) entn[a] = (entn[a] ?? 0) + 1;
    }
    final ha = hausanschluss(entn);
    final hausanschl = [for (final o in alle) if (typen[o.typId]?.kuerzel == 'HA') o];
    final verteiler = [for (final o in alle) if (typen[o.typId]?.kuerzel == 'TV') o];
    final raumName = {
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) r.id: r.name,
    };
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
          'Spitzendurchfluss aus allen Entnahmestellen im Plan (Waschtisch, Dusche, Wanne, WC, Urinal; Entnahmestellen „EN“ mit Art). '
          'Daraus Hausanschluss und Wasserzähler (Richtwerte, Wasserversorger entscheidet). Die Leitungsdimension je Strang steht in der Auslegung (Rohre).',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Summe Berechnungsdurchfluss ${_z(ha.summeVr, 2)} l/s → Spitzendurchfluss ${_z(ha.spitze, 2)} l/s (${_z(ha.spitze * 3.6, 2)} m³/h)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Wasserzähler: ${ha.zaehler} · Hausanschluss: ${ha.anschluss}'),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [for (final e in entn.entries) Chip(label: Text('${e.value}× ${e.key}'))]),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      ListTile(
        leading: Icon(hausanschl.isEmpty ? Icons.info_outline : Icons.check_circle, color: hausanschl.isEmpty ? BsFarben.textLeise : _gruen),
        title: Text(hausanschl.isEmpty ? 'Hausanschluss noch nicht im Plan' : 'Hausanschluss: ${hausanschl.map((o) => '${o.kennung} (${raumName[o.raumId] ?? '–'})').join(', ')}'),
        subtitle: const Text('Reihenfolge: Absperrung – Wasserzähler – Rückflussverhinderer – Filter – Druckminderer (Sanitär › Hausanschluss)'),
      ),
      ListTile(
        leading: Icon(verteiler.isEmpty ? Icons.info_outline : Icons.check_circle, color: verteiler.isEmpty ? BsFarben.textLeise : _gruen),
        title: Text(verteiler.isEmpty ? 'Trinkwasserverteiler noch nicht im Plan' : 'Trinkwasserverteiler: ${verteiler.map((o) => '${o.kennung} (${raumName[o.raumId] ?? '–'})').join(', ')}'),
        subtitle: Text(verteiler.any((o) => !RegExp(r'hwr|technik|keller|hauswirtschaft|heiz').hasMatch((raumName[o.raumId] ?? '').toLowerCase()))
            ? 'Verteiler liegt nicht in HWR/Technikraum – zugänglich lassen'
            : 'Verteiler mit Absperrung je Abgang; Stagnation vermeiden (selten genutzte Stränge kurz halten oder durchschleifen).'),
      ),
    ]);
  }

  // ------------------------------------------------------------ Wassermelder

  Widget _wassermelder() {
    final store = _s.store!;
    final typen = _typen;
    final alle = store.alleObjekte();
    const wasserKuerzel = {'WT', 'DU', 'WA', 'WC', 'UR', 'EN', 'HA', 'TV'};
    final melder = [for (final o in alle) if (typen[o.typId]?.kuerzel == 'WM') o];
    final ventile = [for (final o in alle) if (typen[o.typId]?.kuerzel == 'AV') o];
    final raeume = [
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) r,
    ];
    final ohne = <Raum>[];
    for (final r in raeume) {
      if (r.eigenschaften['kein_wassermelder'] == true) continue;
      final wasser = alle.any((o) => o.raumId == r.id && wasserKuerzel.contains(typen[o.typId]?.kuerzel)) ||
          RegExp(r'küche|hwr|hauswirtschaft|technik|heiz').hasMatch(r.name.toLowerCase());
      if (!wasser) continue;
      if (!melder.any((m) => m.raumId == r.id || (r.umriss != null && m.punkte.isNotEmpty && punktInPolygon(m.punkte.first, r.umriss!)))) ohne.add(r);
    }
    final hauptventil = ventile.where((v) => v.eigenschaften['hauptventil'] == true).firstOrNull;
    final yamlMelder = [for (final m in melder) '${m.eigenschaften['ha_entity'] ?? 'binary_sensor.wassermelder_${m.kennung.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'}'];
    final ventilEntity = '${hauptventil?.eigenschaften['ha_entity'] ?? 'valve.hauptwasser'}';
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
          'Wassermelder (Sanitär › Wassermelder) in Räumen mit Wasseranschluss; bei Alarm schließt ein Motor-Absperrventil (Armatur, als Hauptventil markiert). '
          'Hinweise lassen sich je Raum abschalten.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      for (final r in ohne)
        ListTile(
          dense: true,
          leading: const Icon(Icons.water_drop_outlined, color: Color(0xFFE67700)),
          title: Text('${r.name}: Wasseranschluss ohne Wassermelder'),
          trailing: TextButton(
            onPressed: () {
              store.raumEigenschaftenSetzen(r.id, {...r.eigenschaften, 'kein_wassermelder': true});
              _s.geaendert();
              setState(() {});
            },
            child: const Text('hier nicht nötig'),
          ),
        ),
      if (ohne.isEmpty) const ListTile(leading: Icon(Icons.check_circle, color: _gruen), title: Text('Alle Räume mit Wasseranschluss haben einen Wassermelder.')),
      const Divider(),
      Text('Absperrventil (Hauptventil)', style: Theme.of(context).textTheme.titleSmall),
      if (ventile.isEmpty)
        const Text('Noch keine Armatur/Absperrventil (Sanitär › Armatur) im Plan.', style: TextStyle(fontSize: 12))
      else
        Wrap(spacing: 8, children: [
          for (final v in ventile)
            ChoiceChip(
              label: Text(v.kennung),
              selected: v.eigenschaften['hauptventil'] == true,
              onSelected: (b) {
                for (final x in ventile) {
                  if (x.eigenschaften['hauptventil'] == true && x.id != v.id) _eig(x, {'hauptventil': null});
                }
                _eig(v, {'hauptventil': b ? true : null});
              },
            ),
        ]),
      const SizedBox(height: 12),
      Text('Home-Assistant-Automation', style: Theme.of(context).textTheme.titleSmall),
      const Text('Entitäten aus den Objekten (Feld „Home Assistant“), sonst Platzhalter zum Anpassen.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(10),
        color: const Color(0xFFF4F5F2),
        child: SelectableText(
          melder.isEmpty ? '# noch keine Wassermelder im Plan' : wassermelderYaml(store.name, yamlMelder, ventilEntity),
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: melder.isEmpty
              ? null
              : () async {
                  final text = wassermelderYaml(store.name, yamlMelder, ventilEntity);
                  final f = File(p.join(store.ordner, 'exporte', 'home_assistant', 'wassermelder.yaml'));
                  await f.parent.create(recursive: true);
                  await f.writeAsString(text);
                  await Clipboard.setData(ClipboardData(text: text));
                  if (mounted) zeigeHinweis(context, 'Kopiert und gespeichert unter ${f.path}');
                },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Kopieren und als YAML speichern'),
        ),
      ),
    ]);
  }
}
