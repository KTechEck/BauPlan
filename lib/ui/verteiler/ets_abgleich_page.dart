import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/ets_projekt.dart';
import '../../core/knx.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// ETS-Projekt (.knxproj) oder ETS-CSV einlesen und mit den Gruppenadressen
/// und physikalischen Adressen in BauSpur vergleichen.
class EtsAbgleichPage extends StatefulWidget {
  const EtsAbgleichPage({super.key, required this.state, required this.gas, required this.speichern, this.vorgabe});
  final AppState state;
  final List<Gruppenadresse> gas;
  final void Function(List<Gruppenadresse>) speichern;

  /// Bereits gelesenes Projekt (für Tests).
  final EtsProjekt? vorgabe;

  @override
  State<EtsAbgleichPage> createState() => _EtsAbgleichPageState();
}

class _EtsAbgleichPageState extends State<EtsAbgleichPage> {
  EtsProjekt? _ets;
  String? _datei;
  String? _fehler;
  late List<Gruppenadresse> _gas = widget.gas;
  bool _nurAbweichungen = true;

  @override
  void initState() {
    super.initState();
    _ets = widget.vorgabe;
  }

  Future<void> _oeffnen() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'ETS-Projekt oder Gruppenadressen-CSV', extensions: ['knxproj', 'csv', 'txt']),
    ]);
    if (f == null) return;
    try {
      final daten = await File(f.path).readAsBytes();
      final ets = p.extension(f.path).toLowerCase() == '.knxproj' ? knxprojLesen(daten) : etsCsvLesen(etsText(daten));
      final store = widget.state.store!;
      store.einstellungSetzen('ets_abgleich', {
        'datei': p.basename(f.path),
        'zeit': DateTime.now().toIso8601String(),
        'projekt': ets.name,
        'gas': ets.gas.length,
        'geraete': ets.geraete.length,
      });
      setState(() {
        _ets = ets;
        _datei = p.basename(f.path);
        _fehler = null;
      });
    } on EtsFehler catch (e) {
      setState(() => _fehler = e.meldung);
    } catch (e) {
      setState(() => _fehler = 'Die Datei konnte nicht gelesen werden: $e');
    }
  }

  void _uebernehmen(List<AbgleichZeile> abgleich, {required bool namen, Set<String>? nur}) {
    var n = 0;
    final t = DateTime.now().microsecondsSinceEpoch;
    final neu = etsUebernehmen(_gas, abgleich, namenUebernehmen: namen, nurAdressen: nur, neueId: () => 'ets-$t-${n++}');
    widget.speichern(neu);
    setState(() => _gas = neu);
    zeigeHinweis(context, 'ETS-Stand übernommen.');
  }

  Map<String, String> _bauspurPas() {
    final store = widget.state.store!;
    final pas = <String, String>{};
    for (final s in store.schraenke()) {
      for (final g in store.schrankGeraete(s.id)) {
        final pa = (g.eigenschaften['pa'] as String? ?? '').trim();
        if (pa.isNotEmpty) pas[pa] = '${s.kennzeichen}${g.kennzeichen} ${g.bezeichnung}'.trim();
      }
    }
    for (final o in store.alleObjekte()) {
      final pa = (o.eigenschaften['knx_pa'] as String? ?? '').trim();
      if (pa.isNotEmpty) pas[pa] = o.kennung;
    }
    return pas;
  }

  Color _farbe(AbgleichArt a) => switch (a) {
        AbgleichArt.gleich => const Color(0xFF2F9E44),
        AbgleichArt.nameAnders || AbgleichArt.dptAnders => const Color(0xFFE67700),
        AbgleichArt.nurEts => const Color(0xFF1C7ED6),
        AbgleichArt.nurBauspur => const Color(0xFFB91C1C),
      };

  @override
  Widget build(BuildContext context) {
    final ets = _ets;
    final letzter = widget.state.store?.einstellung<Map>('ets_abgleich');
    return Scaffold(
      appBar: AppBar(title: const Text('ETS-Projekt abgleichen')),
      backgroundColor: BsFarben.flaeche,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(onPressed: _oeffnen, icon: const Icon(Icons.file_open_outlined, size: 18), label: const Text('ETS-Projekt oder CSV öffnen …')),
          if (_datei != null) Text('Gelesen: $_datei${ets!.name.isEmpty ? '' : ' (${ets.name})'}')
          else if (letzter != null) Text('Zuletzt abgeglichen: ${letzter['datei']} am ${_datum(letzter['zeit'] as String?)}', style: const TextStyle(color: BsFarben.textLeise)),
        ]),
        const SizedBox(height: 6),
        const Text(
            '.knxproj aus ETS 5/6 (ohne Projektpasswort) oder der CSV-Export der Gruppenadressen. BauSpur liest nur – das ETS-Projekt wird nicht verändert.',
            style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        if (_fehler != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_fehler!, style: const TextStyle(color: Color(0xFFB91C1C)))),
        if (ets != null) ..._ergebnis(ets),
      ]),
    );
  }

  String _datum(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '?';
    return '${d.day}.${d.month}.${d.year}';
  }

  List<Widget> _ergebnis(EtsProjekt ets) {
    final abgleich = gaAbgleich(_gas, ets.gas);
    final zahl = {for (final a in AbgleichArt.values) a: abgleich.where((z) => z.art == a).length};
    final zeilen = _nurAbweichungen ? abgleich.where((z) => z.art != AbgleichArt.gleich).toList() : abgleich;
    final pa = paAbgleich(_bauspurPas(), ets.geraete);
    return [
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in AbgleichArt.values)
          Chip(
            avatar: CircleAvatar(backgroundColor: _farbe(a), radius: 6),
            label: Text('${a.label}: ${zahl[a]}'),
          ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.tonal(
          onPressed: zahl[AbgleichArt.nurEts] == 0 ? null : () => _uebernehmen(abgleich, namen: false),
          child: Text('${zahl[AbgleichArt.nurEts]} fehlende Adressen aus der ETS anlegen'),
        ),
        OutlinedButton(
          onPressed: zahl[AbgleichArt.nameAnders] == 0 ? null : () => _uebernehmen(abgleich.where((z) => z.art == AbgleichArt.nameAnders).toList(), namen: true),
          child: Text('${zahl[AbgleichArt.nameAnders]} Namen wie in der ETS'),
        ),
        FilterChip(label: const Text('nur Abweichungen'), selected: _nurAbweichungen, onSelected: (v) => setState(() => _nurAbweichungen = v)),
      ]),
      const SizedBox(height: 8),
      Card(
        child: zeilen.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Text('Alle Gruppenadressen stimmen mit der ETS überein.'))
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(columnSpacing: 18, columns: const [
                  DataColumn(label: Text('Adresse')),
                  DataColumn(label: Text('Ergebnis')),
                  DataColumn(label: Text('BauSpur')),
                  DataColumn(label: Text('ETS')),
                  DataColumn(label: Text('DPT BauSpur / ETS')),
                  DataColumn(label: Text('')),
                ], rows: [
                  for (final z in zeilen)
                    DataRow(cells: [
                      DataCell(Text(z.adresse)),
                      DataCell(Text(z.art.label, style: TextStyle(color: _farbe(z.art), fontWeight: FontWeight.w600))),
                      DataCell(Text(z.bauspur?.name ?? '–')),
                      DataCell(Text(z.ets?.name ?? '–')),
                      DataCell(Text('${z.bauspur == null ? '–' : dptKurz(z.bauspur!.dpt)} / ${z.ets == null || z.ets!.dpt.isEmpty ? '–' : dptKurz(z.ets!.dpt)}')),
                      DataCell(switch (z.art) {
                        AbgleichArt.nurEts => TextButton(onPressed: () => _uebernehmen(abgleich, namen: false, nur: {z.adresse}), child: const Text('anlegen')),
                        AbgleichArt.nameAnders => TextButton(onPressed: () => _uebernehmen(abgleich, namen: true, nur: {z.adresse}), child: const Text('ETS-Name')),
                        _ => const SizedBox.shrink(),
                      }),
                    ]),
                ]),
              ),
      ),
      const SizedBox(height: 20),
      Text('Physikalische Adressen', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ets.geraete.isEmpty
              ? const Text('Die Datei enthält keine Geräte (beim CSV-Export der Gruppenadressen normal).')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${pa.gleich.length} Geräte stimmen überein, ${ets.geraete.length} Geräte in der ETS.'),
                  if (pa.nurBauspur.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('In BauSpur vergeben, in der ETS nicht vorhanden:', style: TextStyle(fontWeight: FontWeight.w600)),
                    for (final x in pa.nurBauspur) Text('  $x  ${_bauspurPas()[x]}'),
                  ],
                  if (pa.nurEts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Nur in der ETS (in BauSpur keinem Gerät zugeordnet):', style: TextStyle(fontWeight: FontWeight.w600)),
                    for (final g in pa.nurEts) Text('  ${g.pa}  ${g.name}'),
                  ],
                ]),
        ),
      ),
    ];
  }
}
