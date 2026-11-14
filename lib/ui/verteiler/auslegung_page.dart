import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/auslegung.dart';
import '../../core/auslegung_projekt.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Kabel- und Rohrauslegung sowie die Kabel-/Rohrliste für den Einkauf.
/// [reiter]: 0 Kabel, 1 Rohre, 2 Kabel- und Rohrliste.
class AuslegungPage extends StatefulWidget {
  const AuslegungPage({super.key, required this.state, this.reiter = 0});
  final AppState state;
  final int reiter;

  static Future<void> oeffnen(BuildContext context, AppState s, {int reiter = 0}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AuslegungPage(state: s, reiter: reiter)));

  @override
  State<AuslegungPage> createState() => _AuslegungPageState();
}

String _z(double v, [int stellen = 1]) => v.toStringAsFixed(stellen).replaceAll('.', ',');
String _q(double a) => '${a.toStringAsFixed(a % 1 == 0 ? 0 : 1).replaceAll('.', ',')} mm²';

const _gruen = Color(0xFF2F9E44);
const _rot = Color(0xFFB91C1C);

class _AuslegungPageState extends State<AuslegungPage> {
  AppState get _s => widget.state;

  void _neu() {
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.reiter,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Auslegung und Kabel-/Rohrliste'),
          actions: [
            TextButton.icon(onPressed: _vorgaben, icon: const Icon(Sym.einstellungen, size: 18), label: const Text('Vorgaben')),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Kabel (Stromkreise)'),
            Tab(text: 'Rohre'),
            Tab(text: 'Kabel- und Rohrliste'),
          ]),
        ),
        body: TabBarView(children: [_kabel(), _rohre(), _liste()]),
      ),
    );
  }

  // ---------------------------------------------------------------- Vorgaben

  Future<void> _vorgaben() async {
    final store = _s.store!;
    var v = auslegungVorgaben(store);
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          Widget zahl(String label, double wert, String einheit, AuslegungVorgaben Function(double) neu) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SpeicherFeld(
                  key: ValueKey('$label-$wert'),
                  initialValue: _z(wert, wert % 1 == 0 ? 0 : 2),
                  decoration: InputDecoration(labelText: label, suffixText: einheit),
                  onFieldSubmitted: (t) {
                    final d = double.tryParse(t.replaceAll(',', '.'));
                    if (d != null) setD(() => v = neu(d));
                  },
                ),
              );
          AuslegungVorgaben mit({Verlegeart? art, double? zVor, double? duMax, double? umgebung, double? zuschlag, double? reserve, String? system, double? spreizung}) =>
              AuslegungVorgaben(
                art: art ?? v.art,
                zVor: zVor ?? v.zVor,
                duMax: duMax ?? v.duMax,
                umgebung: umgebung ?? v.umgebung,
                zuschlag: zuschlag ?? v.zuschlag,
                reserve: reserve ?? v.reserve,
                system: system ?? v.system,
                spreizung: spreizung ?? v.spreizung,
              );
          return AlertDialog(
            title: const Text('Vorgaben der Auslegung'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DropdownButtonFormField<Verlegeart>(
                    isExpanded: true,
                    initialValue: v.art,
                    decoration: const InputDecoration(labelText: 'Verlegeart (Vorgabe für alle Stromkreise)'),
                    items: [for (final a in Verlegeart.values) DropdownMenuItem(value: a, child: Text(a.label, overflow: TextOverflow.ellipsis))],
                    onChanged: (a) => setD(() => v = mit(art: a)),
                  ),
                  const SizedBox(height: 8),
                  zahl('Schleifenimpedanz bis zum Verteiler', v.zVor, 'Ω', (d) => mit(zVor: d)),
                  zahl('Spannungsfall höchstens', v.duMax, '%', (d) => mit(duMax: d)),
                  zahl('Umgebungstemperatur', v.umgebung, '°C', (d) => mit(umgebung: d)),
                  zahl('Reserve je Stromkreis am Verteiler', v.reserve, 'm', (d) => mit(reserve: d)),
                  zahl('Zuschlag Einkaufsliste (Verschnitt)', v.zuschlag, '%', (d) => mit(zuschlag: d)),
                  zahl('Spreizung Heizung', v.spreizung, 'K', (d) => mit(spreizung: d)),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: v.system,
                    decoration: const InputDecoration(labelText: 'Rohrsystem für Vorschläge'),
                    items: [for (final s in rohrSysteme) DropdownMenuItem(value: s, child: Text(s))],
                    onChanged: (s) => setD(() => v = mit(system: s)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                      'Planungshilfe nach DIN VDE 0298-4 (Belastbarkeit Cu/PVC), DIN 18015-1 (Spannungsfall) und DIN 1988-300 (Spitzendurchfluss). '
                      'Ersetzt keine Messung und keine Prüfung durch die Elektrofachkraft.',
                      style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
              FilledButton(
                onPressed: () {
                  store.einstellungSetzen('auslegung', v.toJson());
                  Navigator.pop(c);
                },
                child: const Text('Übernehmen'),
              ),
            ],
          );
        },
      ),
    );
    _neu();
  }

  // ------------------------------------------------------------------ Kabel

  Widget _kabel() {
    final store = _s.store!;
    final schraenke = store.schraenke();
    if (schraenke.isEmpty) {
      return const Center(child: Text('Noch kein Verteiler angelegt. Stromkreise legst du im Modul Verteiler an.'));
    }
    final alle = [for (final s in schraenke) ...kreiseAuslegen(store, s)];
    final fehler = alle.where((a) => !a.ist.ok).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(
          'Je Stromkreis: Betriebsstrom aus der Last (Stromkreis oder Summe der Geräte), Länge aus gezeichneten Leitungen oder geschätzt '
          '(Verteiler → Geräte rechtwinklig, Steigstrecken, Reserve). Geprüft werden Belastbarkeit mit Häufung und Temperatur, '
          'Absicherung, Spannungsfall und Abschaltbedingung. ${fehler == 0 ? 'Alle Stromkreise passen.' : '$fehler Stromkreis${fehler == 1 ? '' : 'e'} mit Hinweis.'}',
          style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      for (final s in schraenke) ...[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text('${s.kennzeichen} · ${s.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 14,
              headingRowHeight: 34,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 64,
              columns: const [
                DataColumn(label: Text('Nr.')),
                DataColumn(label: Text('Bezeichnung')),
                DataColumn(label: Text('Last'), numeric: true),
                DataColumn(label: Text('Ib'), numeric: true),
                DataColumn(label: Text('Länge'), numeric: true),
                DataColumn(label: Text('Verlegung')),
                DataColumn(label: Text('Häufung'), numeric: true),
                DataColumn(label: Text('Ist')),
                DataColumn(label: Text('ΔU'), numeric: true),
                DataColumn(label: Text('Zs / max'), numeric: true),
                DataColumn(label: Text('Vorschlag')),
                DataColumn(label: Text('')),
              ],
              rows: [for (final a in alle.where((a) => a.schrank.id == s.id)) _kreisZeile(a)],
            ),
          ),
        ),
      ],
    ]);
  }

  DataRow _kreisZeile(KreisAuslegung a) {
    final store = _s.store!;
    final ist = a.ist, v = a.vorschlag;
    final gleich = (v.querschnitt - ist.querschnitt).abs() < 0.01 && v.nennstrom == ist.nennstrom;
    return DataRow(cells: [
      DataCell(Text(a.kreis.nummer)),
      DataCell(SizedBox(
        width: 160,
        child: Text(
          [a.kreis.bezeichnung.isEmpty ? '–' : a.kreis.bezeichnung, '${a.objekte.length} Objekt${a.objekte.length == 1 ? '' : 'e'}${a.eingabe.drehstrom ? ' · 400 V' : ''}'].join('\n'),
          style: const TextStyle(fontSize: 12),
        ),
      )),
      DataCell(Text('${a.leistung.round()} W')),
      DataCell(Text('${_z(ist.ib)} A')),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 64,
          child: SpeicherFeld(
            key: ValueKey('l-${a.kreis.id}-${a.laenge}'),
            initialValue: _z(a.laenge),
            textAlign: TextAlign.right,
            decoration: const InputDecoration(isDense: true, suffixText: 'm'),
            onFieldSubmitted: (t) {
              final d = double.tryParse(t.replaceAll(',', '.'));
              kreisAngabenSetzen(store, a.kreis.id, {'laenge_m': d});
              _neu();
            },
          ),
        ),
        Tooltip(
          message: a.laengeGeschaetzt
              ? 'Geschätzt – zeichne die Leitung (Typ Leitung) oder trage die Länge ein'
              : kreisAngaben(store, a.kreis.id)['laenge_m'] != null
                  ? 'Von Hand – leeren für automatisch'
                  : 'Aus gezeichneten Leitungen + Reserve',
          child: Icon(a.laengeGeschaetzt ? Icons.straighten : Icons.check, size: 15, color: BsFarben.textLeise),
        ),
      ])),
      DataCell(DropdownButton<Verlegeart>(
        value: a.eingabe.art,
        underline: const SizedBox.shrink(),
        items: [for (final v in Verlegeart.values) DropdownMenuItem(value: v, child: Tooltip(message: v.label, child: Text(v.kurz)))],
        onChanged: (v) {
          kreisAngabenSetzen(store, a.kreis.id, {'art': v?.name});
          _neu();
        },
      )),
      DataCell(SizedBox(
        width: 44,
        child: SpeicherFeld(
          key: ValueKey('h-${a.kreis.id}-${a.eingabe.haeufung}'),
          initialValue: '${a.eingabe.haeufung}',
          textAlign: TextAlign.right,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(isDense: true),
          onFieldSubmitted: (t) {
            kreisAngabenSetzen(store, a.kreis.id, {'haeufung': int.tryParse(t)});
            _neu();
          },
        ),
      )),
      DataCell(Text('${_q(ist.querschnitt)}\n${a.schutz == null ? 'ohne Schutzorgan' : '${a.eingabe.charakteristik}${ist.nennstrom}'}',
          style: const TextStyle(fontSize: 12))),
      DataCell(Text('${_z(ist.spannungsfall, 2)} %',
          style: TextStyle(color: ist.spannungsfall > a.eingabe.maxSpannungsfall ? _rot : null, fontWeight: FontWeight.w600))),
      DataCell(Text('${_z(ist.zs, 2)} / ${_z(ist.zsMax, 2)} Ω', style: TextStyle(fontSize: 12, color: ist.zs > ist.zsMax ? _rot : null))),
      DataCell(SizedBox(
        width: 240,
        child: Tooltip(
          message: [
            ...ist.hinweise,
            'Größte Länge mit ${_q(ist.querschnitt)}: ${_z(ist.maxLaenge, 0)} m',
            'Belastbarkeit Iz: ${_z(ist.iz)} A',
          ].join('\n'),
          child: Row(children: [
            Icon(ist.ok ? Icons.check_circle : Icons.warning_amber, size: 18, color: ist.ok ? _gruen : _rot),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                ist.ok
                    ? (gleich ? 'passt' : 'passt · kleinstmöglich ${_q(v.querschnitt)}')
                    : '${ist.hinweise.first}\n→ ${_q(v.querschnitt)}, ${a.eingabe.charakteristik}${v.nennstrom}${v.ok ? '' : ' (reicht nicht – Länge/Verlegung prüfen)'}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ]),
        ),
      )),
      DataCell(ist.ok || (v.querschnitt - ist.querschnitt).abs() < 0.01
          ? const SizedBox.shrink()
          : TextButton(
              onPressed: () {
                store.stromkreisAendern(a.kreis.id, {
                  'querschnitt': (v.querschnitt * 100).round(),
                  'leitung': leitungText(v.querschnitt, drehstrom: a.eingabe.drehstrom),
                });
                _neu();
                zeigeHinweis(context, 'Stromkreis ${a.kreis.nummer}: ${leitungText(v.querschnitt, drehstrom: a.eingabe.drehstrom)} übernommen.'
                    '${v.nennstrom != ist.nennstrom ? ' Absicherung ${a.eingabe.charakteristik}${v.nennstrom} bitte im Schrank anpassen.' : ''}');
              },
              child: const Text('Übernehmen'),
            )),
    ]);
  }

  // ------------------------------------------------------------------ Rohre

  Widget _rohre() {
    final store = _s.store!;
    final bib = _s.bibliothek;
    final rohre = rohreAuslegen(
      store,
      innenVon: (id) {
        final e = bib.fuerProjekt(store, id);
        final i = e?.zahl('innendurchmesser')?.toDouble();
        if (i != null) return i;
        final a = e?.zahl('aussendurchmesser')?.toDouble(), w = e?.zahl('wandstaerke')?.toDouble();
        return a != null && w != null ? a - 2 * w : null;
      },
      nameVon: (id) => bib.fuerProjekt(store, id)?.anzeige,
    );
    if (rohre.isEmpty) {
      return const Center(
          child: Text('Keine Rohrleitungen im Plan (Kaltwasser, Warmwasser, Zirkulation, Vorlauf, Rücklauf, Anbindeleitung).'));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
          'Heizung: Volumenstrom aus Leistung und Spreizung, Ziel bis 0,7 m/s und 150 Pa/m. Trinkwasser: Spitzendurchfluss aus den Entnahmestellen '
          '(DIN 1988-300, Wohngebäude), Ziel bis 2 m/s. Leistung bzw. Entnahmestellen trägst du je Leitungsabschnitt ein – '
          'gerechnet wird die Teilstrecke mit allem, was sie versorgt.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 14,
            headingRowHeight: 34,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 60,
            columns: const [
              DataColumn(label: Text('Leitung')),
              DataColumn(label: Text('Länge'), numeric: true),
              DataColumn(label: Text('versorgt')),
              DataColumn(label: Text('Durchfluss'), numeric: true),
              DataColumn(label: Text('Ist')),
              DataColumn(label: Text('v'), numeric: true),
              DataColumn(label: Text('R'), numeric: true),
              DataColumn(label: Text('Vorschlag')),
            ],
            rows: [for (final r in rohre) _rohrZeile(r)],
          ),
        ),
      ),
    ]);
  }

  void _eigenschaft(String objektId, Map<String, Object?> werte) {
    final store = _s.store!;
    final o = store.alleObjekte().where((o) => o.id == objektId).firstOrNull;
    if (o == null) return;
    final neu = {...o.eigenschaften, ...werte}..removeWhere((k, v) => v == null);
    store.objektAendern(objektId, {'eigenschaften': jsonEncode(neu)});
    _neu();
  }

  DataRow _rohrZeile(RohrAuslegung r) {
    final e = r.eingabe;
    final trink = e.medium == Medium.trinkwasser;
    final entnahmen = Map<String, dynamic>.from(r.objekt.eigenschaften['entnahmen'] as Map? ?? const {});
    return DataRow(cells: [
      DataCell(Text('${r.objekt.kennung}\n${r.typ.name}', style: const TextStyle(fontSize: 12))),
      DataCell(Text('${_z(e.laengeM)} m')),
      DataCell(trink
          ? TextButton(
              onPressed: () => _entnahmenDialog(r.objekt.id, entnahmen),
              child: Text(entnahmen.isEmpty
                  ? 'Entnahmestellen …'
                  : [for (final x in entnahmen.entries) if ((x.value as num) > 0) '${x.value}× ${x.key}'].join(', '),
                  style: const TextStyle(fontSize: 12)),
            )
          : SizedBox(
              width: 90,
              child: SpeicherFeld(
                key: ValueKey('rw-${r.objekt.id}-${e.leistungW}'),
                initialValue: e.leistungW <= 0 ? '' : '${e.leistungW.round()}',
                textAlign: TextAlign.right,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(isDense: true, suffixText: 'W', hintText: 'Leistung'),
                onFieldSubmitted: (t) => _eigenschaft(r.objekt.id, {'leistung_w': int.tryParse(t)}),
              ),
            )),
      DataCell(Text('${r.ist.durchflussLh.round()} l/h')),
      DataCell(Text('${r.rohrName ?? r.ist.mass.name}\n${e.innen == null ? 'noch nicht gewählt' : 'Ø ${_z(e.innen!)} innen'}',
          style: const TextStyle(fontSize: 12))),
      DataCell(Text(e.innen == null ? '–' : '${_z(r.ist.v, 2)} m/s', style: TextStyle(color: e.innen != null && !r.ist.ok ? _rot : null))),
      DataCell(Text(e.innen == null ? '–' : '${r.ist.rProM.round()} Pa/m')),
      DataCell(Row(children: [
        Icon(e.innen == null ? Icons.lightbulb_outline : (r.ist.ok ? Icons.check_circle : Icons.warning_amber),
            size: 18, color: e.innen == null ? BsFarben.akzent : (r.ist.ok ? _gruen : _rot)),
        const SizedBox(width: 6),
        Text(
          r.ist.durchflussLh <= 0
              ? (trink ? 'Entnahmestellen eintragen' : 'Leistung eintragen')
              : '${r.vorschlag.mass.system} ${r.vorschlag.mass.name} · ${_z(r.vorschlag.v, 2)} m/s',
          style: const TextStyle(fontSize: 12),
        ),
        if (r.ist.durchflussLh > 0)
          TextButton(
            onPressed: () => _eigenschaft(r.objekt.id, {'dimension': '${r.vorschlag.mass.system} ${r.vorschlag.mass.name}', 'innen_mm': r.vorschlag.mass.innen}),
            child: const Text('Übernehmen'),
          ),
      ])),
    ]);
  }

  Future<void> _entnahmenDialog(String objektId, Map<String, dynamic> alt) async {
    final werte = {for (final a in entnahmeArten.keys) a: (alt[a] as num?)?.toInt() ?? 0};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Versorgte Entnahmestellen'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final a in entnahmeArten.keys)
                Row(children: [
                  Expanded(child: Text('$a  (${_z(entnahmeArten[a]!, 2)} l/s)')),
                  IconButton(onPressed: werte[a]! > 0 ? () => setD(() => werte[a] = werte[a]! - 1) : null, icon: const Icon(Icons.remove, size: 18)),
                  SizedBox(width: 24, child: Text('${werte[a]}', textAlign: TextAlign.center)),
                  IconButton(onPressed: () => setD(() => werte[a] = werte[a]! + 1), icon: const Icon(Icons.add, size: 18)),
                ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Übernehmen')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final m = {for (final e in werte.entries) if (e.value > 0) e.key: e.value};
    _eigenschaft(objektId, {'entnahmen': m.isEmpty ? null : m});
  }

  // ------------------------------------------------------------------ Liste

  List<LeitungsSumme> _summen() {
    final store = _s.store!;
    return leitungsliste(leitungsStuecke(store, name: (id) => _s.bibliothek.fuerProjekt(store, id)?.anzeige));
  }

  Widget _liste() {
    final store = _s.store!;
    final v = auslegungVorgaben(store);
    final summen = _summen();
    final gekauft = leitungGekauft(store);
    if (summen.isEmpty) {
      return const Center(child: Text('Noch keine Leitungen im Plan und keine Stromkreise mit Geräten.'));
    }
    String ringText(LeitungsSumme s) {
      final r = s.ringe(v.zuschlag, ringGroessen(s.art, s.bezeichnung));
      if (r.isEmpty) return '';
      final stange = ringGroessen(s.art, s.bezeichnung).length == 1 && ringGroessen(s.art, s.bezeichnung).first <= 6;
      return [for (final (n, g) in r) '$n× $g m${stange ? ' Stange' : ''}'].join(' + ');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Mit ${_z(v.zuschlag, 0)} % Zuschlag, auf ganze Meter und übliche Ringgrößen gerundet. '
              'Geschätzte Längen (Stromkreise ohne gezeichnete Leitung) sind markiert.',
              style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          FilledButton.tonalIcon(onPressed: () => _exportieren(summen, csv: true), icon: const Icon(Icons.table_view, size: 18), label: const Text('CSV (Excel)')),
          FilledButton.tonalIcon(onPressed: () => _exportieren(summen, csv: false), icon: const Icon(Icons.checklist, size: 18), label: const Text('Abhakliste fürs Handy (HTML)')),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          for (final art in {for (final s in summen) s.art}) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(art, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            Card(
              child: Column(children: [
                for (final s in summen.where((s) => s.art == art))
                  () {
                    final k = leitungSchluessel(s);
                    final ok = (gekauft[k] ?? 0) >= s.einkauf(v.zuschlag) && s.einkauf(v.zuschlag) > 0;
                    return ListTile(
                      dense: true,
                      leading: Checkbox(
                        value: ok,
                        onChanged: (b) {
                          leitungGekauftSetzen(store, k, b == true ? s.einkauf(v.zuschlag) : null);
                          _neu();
                        },
                      ),
                      title: Text(s.bezeichnung, style: TextStyle(decoration: ok ? TextDecoration.lineThrough : null)),
                      subtitle: Text(
                        [
                          if (s.gezeichnet > 0) '${_z(s.gezeichnet)} m gezeichnet',
                          if (s.geschaetzt > 0) '${_z(s.geschaetzt)} m geschätzt',
                          s.woher.take(6).join(', ') + (s.woher.length > 6 ? ' …' : ''),
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${s.einkauf(v.zuschlag).round()} m', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(ringText(s), style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
                      ]),
                    );
                  }(),
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }

  Future<void> _exportieren(List<LeitungsSumme> summen, {required bool csv}) async {
    final store = _s.store!;
    final v = auslegungVorgaben(store);
    final datei = File(p.join(store.ordner, 'exporte', csv ? 'Kabel- und Rohrliste.csv' : 'Kabel- und Rohrliste.html'));
    await datei.parent.create(recursive: true);
    await datei.writeAsString(csv ? '﻿${leitungslisteCsv(summen, v.zuschlag)}' : leitungslisteHtml(p.basename(store.ordner), summen, v.zuschlag, DateTime.now()));
    if (mounted) zeigeHinweis(context, 'Gespeichert unter ${datei.path}');
  }
}

String _csvFeld(String s) => '"${s.replaceAll('"', '""')}"';

/// Kabel-/Rohrliste als CSV (Semikolon, für Excel).
String leitungslisteCsv(List<LeitungsSumme> summen, double zuschlag) {
  final b = StringBuffer('Art;Bezeichnung;gezeichnet m;geschätzt m;Summe m;Einkauf m;Ringe/Rollen;Herkunft\n');
  for (final s in summen) {
    final r = s.ringe(zuschlag, ringGroessen(s.art, s.bezeichnung));
    b.writeln([
      _csvFeld(s.art),
      _csvFeld(s.bezeichnung),
      _z(s.gezeichnet),
      _z(s.geschaetzt),
      _z(s.summe),
      s.einkauf(zuschlag).round(),
      _csvFeld([for (final (n, g) in r) '$n× $g m'].join(' + ')),
      _csvFeld(s.woher.join(', ')),
    ].join(';'));
  }
  return b.toString();
}

String _h(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Kabel-/Rohrliste als HTML zum Abhaken auf dem Handy (Haken bleiben im Browser).
String leitungslisteHtml(String projekt, List<LeitungsSumme> summen, double zuschlag, DateTime stand) {
  final b = StringBuffer()
    ..writeln('<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>Kabel- und Rohrliste ${_h(projekt)}</title>')
    ..writeln('<style>body{font-family:system-ui,sans-serif;margin:0;padding:16px;background:#f7f5f0;color:#222}h1{font-size:20px;margin:0 0 4px}'
        'h2{font-size:16px;margin:20px 0 6px}.l{color:#777;font-size:13px}label{display:flex;gap:10px;align-items:flex-start;background:#fff;'
        'border-radius:8px;padding:10px;margin:6px 0}input{width:22px;height:22px;flex:none}label.ok{opacity:.45;text-decoration:line-through}'
        '.m{margin-left:auto;text-align:right;white-space:nowrap}</style></head><body>')
    ..writeln('<h1>Kabel- und Rohrliste</h1><div class="l">${_h(projekt)} · Stand ${stand.day}.${stand.month}.${stand.year} · ${_z(zuschlag, 0)} % Zuschlag</div>');
  for (final art in {for (final s in summen) s.art}) {
    b.writeln('<h2>${_h(art)}</h2>');
    for (final s in summen.where((s) => s.art == art)) {
      final r = s.ringe(zuschlag, ringGroessen(s.art, s.bezeichnung));
      b.writeln('<label><input type="checkbox" data-k="${_h(leitungSchluessel(s))}"><span>${_h(s.bezeichnung)}'
          '<br><span class="l">${s.geschaetzt > 0 ? 'teils geschätzt · ' : ''}${_h(s.woher.take(4).join(', '))}</span></span>'
          '<span class="m"><b>${s.einkauf(zuschlag).round()} m</b><br><span class="l">${_h([for (final (n, g) in r) '$n× $g m'].join(' + '))}</span></span></label>');
    }
  }
  b.writeln('<script>document.querySelectorAll("input[data-k]").forEach(function(c){var k="bsl-"+c.dataset.k;'
      'try{c.checked=localStorage.getItem(k)==="1"}catch(e){}c.parentNode.classList.toggle("ok",c.checked);'
      'c.addEventListener("change",function(){try{localStorage.setItem(k,c.checked?"1":"0")}catch(e){}'
      'c.parentNode.classList.toggle("ok",c.checked)})});</script></body></html>');
  return b.toString();
}
