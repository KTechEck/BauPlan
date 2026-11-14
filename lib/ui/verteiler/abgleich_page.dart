import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/abgleich_projekt.dart';
import '../../core/hydraulik.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

String _z(double v, [int stellen = 1]) => v.toStringAsFixed(stellen).replaceAll('.', ',');

/// Hydraulischer Abgleich eines Heizkreisverteilers: Soll-Durchfluss je
/// Abgang (für den Durchflussmesser), Voreinstellung der Rücklaufventile,
/// nötiger Differenzdruck; eingestellte Werte festhalten.
class AbgleichPage extends StatefulWidget {
  const AbgleichPage({super.key, required this.state, required this.verteilerId});
  final AppState state;
  final String verteilerId;

  @override
  State<AbgleichPage> createState() => _AbgleichPageState();
}

class _AbgleichPageState extends State<AbgleichPage> {
  AppState get _s => widget.state;

  void _einstellungSetzen(AbgleichEinstellung e) {
    _s.store!.einstellungSetzen('abgleich', e.toJson());
    _s.geaendert();
    setState(() {});
  }

  void _kreisSetzen(String id, Map<String, Object?> neu) {
    final store = _s.store!;
    final o = store.alleObjekte().where((x) => x.id == id).firstOrNull;
    if (o == null) return;
    store.objektAendern(id, {'eigenschaften': jsonEncode({...o.eigenschaften, ...neu}..removeWhere((_, v) => v == null))});
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final v = store.alleObjekte().where((o) => o.id == widget.verteilerId).firstOrNull;
    if (v == null) return const Scaffold(body: Center(child: Text('Verteiler nicht gefunden.')));
    final e = abgleichEinstellung(store);
    final a = abgleichBerechnen(abgleichKreise(store, v, einstellung: e), e);
    final heizlast = heizlastJeRaum(store);
    double? zahl(String t) => double.tryParse(t.trim().replaceAll(',', '.'));
    final kopf = Theme.of(context).textTheme.titleSmall;
    return Scaffold(
      backgroundColor: BsFarben.flaeche,
      appBar: AppBar(title: Text('Hydraulischer Abgleich · ${v.kennung}'), backgroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final (label, wert, suffix, setzen) in [
                ('Spreizung', e.spreizung, 'K', (double x) => e.mit(spreizung: x)),
                ('Leistung ohne Heizlast', e.spezLeistung, 'W/m²', (double x) => e.mit(spezLeistung: x)),
                ('Rohr innen', e.rohrInnen, 'mm', (double x) => e.mit(rohrInnen: x)),
                ('Zuschlag Formteile', e.zuschlag * 100, '%', (double x) => e.mit(zuschlag: x / 100)),
                ('kv voll offen', e.kvOffen, 'm³/h', (double x) => e.mit(kvOffen: x)),
              ])
                SizedBox(
                  width: 170,
                  child: SpeicherFeld(
                    key: ValueKey('$label-$wert'),
                    initialValue: _z(wert, wert % 1 == 0 ? 0 : 2),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                    decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
                    onFieldSubmitted: (t) {
                      final x = zahl(t);
                      if (x != null && x > 0) _einstellungSetzen(setzen(x));
                    },
                  ),
                ),
              SizedBox(
                width: 360,
                child: SpeicherFeld(
                  key: ValueKey('kv-${e.kvStufen.join('/')}'),
                  initialValue: e.kvStufen.map((k) => _z(k, 2)).join('; '),
                  decoration: const InputDecoration(labelText: 'kv je Voreinstellstufe 1 … n (Hersteller)', isDense: true),
                  onFieldSubmitted: (t) {
                    final l = [for (final x in t.split(';')) if (zahl(x) case final k? when k > 0) k];
                    if (l.isNotEmpty) _einstellungSetzen(e.mit(kvStufen: l));
                  },
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (a.kreise.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Noch keine Heizkreise auf die Abgänge gelegt (im Verteiler-Editor unter „Belegung der Abgänge“).'))
        else ...[
          Text(
              'Summe ${_z(a.volumenstrom, 0)} l/h (${_z(a.volumenstrom / 60)} l/min) · nötiger Differenzdruck am Verteiler ca. ${_z(a.foerderhoehe / 1000)} kPa '
              '(${_z(a.foerderhoeheM, 2)} m Förderhöhe, inkl. ${_z(e.verteilerVerlust / 1000)} kPa Verteiler/Zuleitung)',
              style: kopf),
          if (a.unguenstigster case final u?)
            Text('Ungünstigster Kreis: ${u.kreis.name} (${u.kreis.raum}) – dessen Ventil bleibt ganz offen, alle anderen werden gedrosselt.',
                style: const TextStyle(color: BsFarben.textLeise)),
          const SizedBox(height: 8),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowHeight: 40,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 64,
                columns: const [
                  DataColumn(label: Text('Abg.')),
                  DataColumn(label: Text('Kreis / Raum')),
                  DataColumn(label: Text('Fläche'), numeric: true),
                  DataColumn(label: Text('Rohr'), numeric: true),
                  DataColumn(label: Text('Leistung'), numeric: true),
                  DataColumn(label: Text('Soll l/min'), numeric: true),
                  DataColumn(label: Text('Δp Kreis'), numeric: true),
                  DataColumn(label: Text('Voreinst.'), numeric: true),
                  DataColumn(label: Text('Ist l/min')),
                  DataColumn(label: Text('Ist Stufe')),
                  DataColumn(label: Text('Abw.'), numeric: true),
                ],
                rows: [
                  for (final r in a.kreise)
                    DataRow(cells: [
                      DataCell(Text('${r.kreis.abgang ?? ''}')),
                      DataCell(Tooltip(
                        message: r.hinweise.isEmpty ? '${_z(r.geschwindigkeit, 2)} m/s' : r.hinweise.join('\n'),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (r.hinweise.isNotEmpty) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.warning_amber, size: 16, color: Color(0xFFB45309))),
                          Text('${r.kreis.name}\n${r.kreis.raum}', style: const TextStyle(fontSize: 12)),
                        ]),
                      )),
                      DataCell(Text('${_z(r.kreis.flaeche)} m²')),
                      DataCell(Text('${_z(r.kreis.rohrlaenge, 0)} m')),
                      DataCell(SizedBox(
                        width: 90,
                        child: SpeicherFeld(
                          key: ValueKey('lw-${r.kreis.id}-${r.kreis.leistung.round()}'),
                          initialValue: '${r.kreis.leistung.round()}',
                          textAlign: TextAlign.end,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                              isDense: true,
                              suffixText: 'W',
                              helperText: r.kreis.leistungVonHand ? 'von Hand' : (heizlast.isEmpty ? 'W/m²-Wert' : 'aus Heizlast'),
                              helperStyle: const TextStyle(fontSize: 9)),
                          onFieldSubmitted: (t) => _kreisSetzen(r.kreis.id, {'leistung_w': int.tryParse(t)}),
                        ),
                      )),
                      DataCell(Text(_z(r.lMin, 2), style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text('${_z(r.druckverlust / 1000)} kPa')),
                      DataCell(Text(r.stufe == null ? 'offen' : '${r.stufe}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(SizedBox(
                        width: 70,
                        child: SpeicherFeld(
                          key: ValueKey('ist-${r.kreis.id}-${r.kreis.istLMin}'),
                          initialValue: r.kreis.istLMin == null ? '' : _z(r.kreis.istLMin!, 2),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                          decoration: const InputDecoration(isDense: true),
                          onFieldSubmitted: (t) => _kreisSetzen(r.kreis.id, {'ist_l_min': zahl(t)}),
                        ),
                      )),
                      DataCell(SizedBox(
                        width: 50,
                        child: SpeicherFeld(
                          key: ValueKey('ists-${r.kreis.id}-${r.kreis.istStufe}'),
                          initialValue: r.kreis.istStufe?.toString() ?? '',
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(isDense: true),
                          onFieldSubmitted: (t) => _kreisSetzen(r.kreis.id, {'ist_stufe': int.tryParse(t)}),
                        ),
                      )),
                      DataCell(Text(
                        r.abweichung == null ? '–' : '${r.abweichung! >= 0 ? '+' : ''}${_z(r.abweichung!, 0)} %',
                        style: TextStyle(color: r.abweichung == null ? null : (r.abweichung!.abs() <= 10 ? const Color(0xFF15803D) : const Color(0xFFB91C1C))),
                      )),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final r in a.kreise)
            for (final h in r.hinweise) Text('• ${r.kreis.name}: $h', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
          const SizedBox(height: 10),
          const Text(
            'So geht es: Am Durchflussmesser (Vorlauf) den Soll-Wert in l/min einstellen; bei Ventilen mit Voreinstellung (Rücklauf) die Stufe. '
            'Die Leistung je Kreis kommt aus der Heizlast des Raums (Modul Bauphysik, nach Fläche auf die Kreise verteilt) oder von Hand. '
            'Eingestellte Werte unter „Ist“ eintragen – auch vom Handy (Mehr › Hydraulischer Abgleich). '
            'Vereinfachte Rechnung (Wasser 30 °C, Blasius) – Herstellerdiagramme gehen vor.',
            style: TextStyle(fontSize: 12, color: BsFarben.textLeise, height: 1.4),
          ),
        ],
      ]),
    );
  }
}

/// Knopf für den Verteiler-Editor.
Widget abgleichKnopf(BuildContext context, AppState s, Objekt v) => OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AbgleichPage(state: s, verteilerId: v.id))),
      icon: const Icon(Icons.speed, size: 18),
      label: const Text('Hydraulischer Abgleich …'),
    );
