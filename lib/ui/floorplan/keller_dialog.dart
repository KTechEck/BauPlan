import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/fassade.dart' show WdvsVorgaben, eckenZaehlen;
import '../../core/keller_sockel.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import 'fassade_dialog.dart' show aussenSeiten;

String _z(double v, [int n = 1]) => v.toStringAsFixed(n).replaceAll('.', ',');

/// Keller, Sockel, Putzprofile und Fensterbänke für das aktuelle Geschoss.
Future<void> kellerSockelDialog(BuildContext context, AppState s) => showDialog<void>(
      context: context,
      builder: (_) => Dialog(child: SizedBox(width: 960, height: 680, child: _KellerSockel(state: s))),
    );

class _KellerSockel extends StatefulWidget {
  const _KellerSockel({required this.state});
  final AppState state;
  @override
  State<_KellerSockel> createState() => _KellerSockelState();
}

class _KellerSockelState extends State<_KellerSockel> {
  AppState get _s => widget.state;

  Widget _positionen(KellerErgebnis e) => Card(
        child: Column(children: [
          for (final x in e.positionen)
            ListTile(dense: true, title: Text(x.was), trailing: Text('${_z(x.menge, x.menge >= 100 ? 0 : 1)} ${x.einheit}', style: const TextStyle(fontWeight: FontWeight.w600))),
          if (e.positionen.isEmpty) const ListTile(title: Text('Keine Mengen – Maßnahmen wählen.')),
        ]),
      );

  Widget _hinweise(List<String> h) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final x in h)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 15, color: BsFarben.textLeise),
              const SizedBox(width: 6),
              Expanded(child: Text(x, style: const TextStyle(fontSize: 12))),
            ]),
          ),
      ]);

  Future<void> _csv(String name, KellerErgebnis e) async {
    final b = StringBuffer('Position;Menge;Einheit\n');
    for (final x in e.positionen) {
      b.writeln('"${x.was}";${_z(x.menge, 2)};${x.einheit}');
    }
    final f = File(p.join(_s.store!.ordner, 'exporte', '$name.csv'));
    await f.parent.create(recursive: true);
    await f.writeAsString('﻿$b');
    if (mounted) zeigeHinweis(context, 'Gespeichert unter ${f.path}');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Keller, Sockel, Putzprofile, Fensterbänke'),
          automaticallyImplyLeading: false,
          actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))],
          bottom: const TabBar(tabs: [Tab(text: 'Keller'), Tab(text: 'Sockel'), Tab(text: 'Putzprofile'), Tab(text: 'Fensterbänke')]),
        ),
        body: TabBarView(children: [_keller(), _sockel(), _profile(), _fensterbaenke()]),
      ),
    );
  }

  // --------------------------------------------------------------- Keller

  Widget _keller() {
    final store = _s.store!;
    final gid = _s.geschossId!;
    final g = store.geschoss(gid)!;
    final schluessel = 'keller_$gid';
    final v = KellerVorgaben.ausJson(store.einstellung<Map>(schluessel));
    void setzen(Map<String, Object?> w) {
      store.einstellungSetzen(schluessel, {...v.toJson(), ...w});
      _s.geaendert();
      setState(() {});
    }

    final waende = store.waende(gid);
    final seiten = aussenSeiten(waende, store.raeume(gid));
    final kw = [
      for (final w in waende)
        if (seiten.containsKey(w.id)) (id: w.id, laenge: w.laenge + w.dicke, dicke: w.dicke, freilegbar: !v.nichtFreilegbar.contains(w.id)),
    ];
    final decke = store.raeume(gid).fold<double>(0, (a, r) => a + (r.flaeche ?? 0) / 1e6);
    final e = kellerBerechnen(kw, v, kellerHoeheInnen: g.hoehen.rohdecke - g.hoehen.ffb, deckenFlaeche: decke);
    final istKeller = RegExp(r'^(UG|KG)', caseSensitive: false).hasMatch(g.kuerzel) || g.name.toLowerCase().contains('keller');
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (!istKeller)
        Text('Hinweis: Geschoss ${g.kuerzel} heißt nicht „Keller/UG“ – Werte gelten trotzdem für seine Außenwände.', style: const TextStyle(color: Color(0xFFB45309))),
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 380,
          child: DropdownButtonFormField<Lastfall>(
            isExpanded: true,
            initialValue: v.lastfall,
            decoration: const InputDecoration(labelText: 'Wassereinwirkung (DIN 18533)', isDense: true),
            items: [for (final l in Lastfall.values) DropdownMenuItem(value: l, child: Text(l.label, overflow: TextOverflow.ellipsis))],
            onChanged: (l) => setzen({'lastfall': l?.name}),
          ),
        ),
        for (final (k, l, w) in [('tiefe', 'Tiefe unter GOK', v.tiefe), ('sockel', 'Abdichtung über GOK', v.sockelUeberGok), ('perimeter', 'Perimeterdämmung', v.perimeterDicke), ('innendaemmung', 'Innendämmung', v.innenDaemmung), ('decke', 'Kellerdecke', v.deckenDaemmung)])
          SizedBox(
            width: 130,
            child: SpeicherFeld(
              key: ValueKey('ks-$k-$w'),
              initialValue: '$w',
              decoration: InputDecoration(labelText: l, suffixText: 'mm', isDense: true),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (t) => setzen({k: int.tryParse(t) ?? w}),
            ),
          ),
      ]),
      Wrap(spacing: 8, runSpacing: 4, children: [
        FilterChip(label: const Text('Außenabdichtung'), selected: v.aussenabdichtung, onSelected: (b) => setzen({'aussen': b})),
        FilterChip(label: const Text('Drainage'), selected: v.drainage, onSelected: (b) => setzen({'drainage': b})),
        FilterChip(label: const Text('Innenabdichtung'), selected: v.innenabdichtung, onSelected: (b) => setzen({'innen': b})),
        FilterChip(label: const Text('Sanierputz'), selected: v.sanierputz, onSelected: (b) => setzen({'sanierputz': b})),
        DropdownButton<String>(
          value: v.horizontalsperre,
          items: const [
            DropdownMenuItem(value: 'keine', child: Text('keine Horizontalsperre')),
            DropdownMenuItem(value: 'injektion', child: Text('Horizontalsperre: Injektion')),
            DropdownMenuItem(value: 'saege', child: Text('Horizontalsperre: Mauersäge')),
            DropdownMenuItem(value: 'edelstahl', child: Text('Horizontalsperre: Chromstahlblech')),
          ],
          onChanged: (x) => setzen({'sperre': x}),
        ),
        DropdownButton<String>(
          value: v.innenMaterial,
          items: const [
            DropdownMenuItem(value: 'Kalziumsilikat', child: Text('Innendämmung Kalziumsilikat')),
            DropdownMenuItem(value: 'Mineraldämmplatte', child: Text('Innendämmung Mineraldämmplatte')),
            DropdownMenuItem(value: 'Holzfaser (kapillaraktiv)', child: Text('Innendämmung Holzfaser')),
          ],
          onChanged: (x) => setzen({'innenmaterial': x}),
        ),
      ]),
      const SizedBox(height: 6),
      Text('Kellerwände (${kw.length}) – außen freilegbar?', style: const TextStyle(fontWeight: FontWeight.w600)),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final (i, w) in kw.indexed)
          FilterChip(
            label: Text('Wand ${i + 1}: ${_z(w.laenge / 1000)} m'),
            selected: w.freilegbar,
            onSelected: (b) => setzen({'nicht_frei': (b ? ({...v.nichtFreilegbar}..remove(w.id)) : {...v.nichtFreilegbar, w.id}).toList()}),
          ),
      ]),
      const SizedBox(height: 8),
      _positionen(e),
      _hinweise(e.hinweise),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _csv('Keller_${g.kuerzel}', e), icon: const Icon(Icons.table_view, size: 18), label: const Text('Als CSV'))),
    ]);
  }

  // --------------------------------------------------------------- Sockel

  Widget _sockel() {
    final store = _s.store!;
    final gid = _s.geschossId!;
    final v = SockelVorgaben.ausJson(store.einstellung<Map>('sockel'));
    void setzen(Map<String, Object?> w) {
      store.einstellungSetzen('sockel', {...v.toJson(), ...w});
      _s.geaendert();
      setState(() {});
    }

    final waende = store.waende(gid);
    final seiten = aussenSeiten(waende, store.raeume(gid));
    var laenge = 0.0;
    var tueren = 0;
    for (final w in waende.where((w) => seiten.containsKey(w.id))) {
      laenge += (w.laenge + w.dicke) / 1000;
      for (final o in store.oeffnungen(gid).where((o) => o.wandId == w.id && (o.art == OeffnungsArt.tuer || o.art == OeffnungsArt.balkontuer))) {
        laenge -= o.breite / 1000;
        tueren++;
      }
    }
    final e = sockelBerechnen(math.max(0, laenge), v, tueren: tueren);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Sockel des Geschosses ${store.geschoss(gid)?.kuerzel}: ${_z(laenge)} m Außenlänge ohne Türen. Eigener Bereich unter dem WDVS (Übergang über das Sockelprofil).',
          style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 8, children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: v.daemmstoff,
            decoration: const InputDecoration(labelText: 'Sockeldämmstoff', isDense: true),
            items: [for (final d in sockelDaemmstoffe) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (d) => setzen({'daemmstoff': d}),
          ),
        ),
        for (final (k, l, w) in [('dicke', 'Dicke', v.dicke), ('unter', 'unter GOK', v.unterGok), ('ueber', 'über GOK', v.ueberGok)])
          SizedBox(
            width: 120,
            child: SpeicherFeld(
              key: ValueKey('so-$k-$w'),
              initialValue: '$w',
              decoration: InputDecoration(labelText: l, suffixText: 'mm', isDense: true),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (t) => setzen({k: int.tryParse(t) ?? w}),
            ),
          ),
        FilterChip(label: const Text('Kiesstreifen'), selected: v.kiesstreifen, onSelected: (b) => setzen({'kies': b})),
      ]),
      if (v.dicke < WdvsVorgaben.ausJson(store.einstellung<Map>('wdvs')).dicke - 40)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Sockel deutlich dünner als das WDVS: Rücksprung mit Sockelabschlussprofil/Tropfkante ausbilden.', style: TextStyle(fontSize: 12, color: Color(0xFFB45309))),
        ),
      const SizedBox(height: 8),
      _positionen(e),
      _hinweise(e.hinweise),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _csv('Sockel', e), icon: const Icon(Icons.table_view, size: 18), label: const Text('Als CSV'))),
    ]);
  }

  // ---------------------------------------------------------- Putzprofile

  Widget _profile() {
    final store = _s.store!;
    final gid = _s.geschossId!;
    final g = store.geschoss(gid)!;
    final hoehe = (g.hoehen.rohdecke - g.hoehen.rfb + 200) / 1000;
    final waende = store.waende(gid);
    final raeume = store.raeume(gid);
    final seiten = aussenSeiten(waende, raeume);
    final oeff = store.oeffnungen(gid);
    final aussen = [
      for (final o in oeff)
        if (seiten.containsKey(o.wandId) && o.art != OeffnungsArt.nische && o.art != OeffnungsArt.durchbruch)
          (b: o.breite.toDouble(), h: o.hoehe.toDouble(), fenster: o.art == OeffnungsArt.fenster, tuer: o.art != OeffnungsArt.fenster),
    ];
    final innen = [for (final o in oeff) if (o.art == OeffnungsArt.fenster) (b: o.breite.toDouble(), h: o.hoehe.toDouble())];
    var sockel = 0.0;
    for (final w in waende.where((w) => seiten.containsKey(w.id))) {
      sockel += (w.laenge + w.dicke) / 1000;
    }
    var innenEcken = 0.0;
    for (final r in raeume) {
      if (r.umriss == null) continue;
      final (_, a) = eckenZaehlen([for (final q in r.umriss!) (q.x, q.y)]);
      innenEcken += a * (g.hoehen.rohdecke - g.hoehen.ffb) / 1000;
    }
    final balkonRand = raeume.where((r) => r.art != RaumArt.raum && r.umriss != null).fold<double>(0, (a, r) => a + (r.umfang ?? 0) / 1000 * 0.75);
    final manuell = Map<String, dynamic>.from(store.einstellung<Map>('putzprofile') ?? const {});
    final auto = putzprofileAusPlan(
      aussenEckenHoeheM: math.max(4, seiten.length) * hoehe,
      oeffnungenAussen: aussen,
      sockelLaengeM: sockel,
      innenEckenHoeheM: innenEcken,
      oeffnungenInnen: innen,
      balkonRandM: balkonRand,
    );
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Aus dem Plan geschätzt (Außenecken, Fenster/Türen in Außenwänden, Sockel, vorspringende Innenecken, Balkonränder). '
          'Je Profil lässt sich eine Menge von Hand ergänzen (z. B. Dehnfugen). Stäbe mit 10 % Verschnitt.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      for (final gruppe in const ['Außen', 'Innen']) ...[
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(gruppe, style: const TextStyle(fontWeight: FontWeight.w700))),
        Card(
          child: Column(children: [
            for (final e in putzprofile.entries.where((e) => e.value.$1 == gruppe))
              () {
                final a = auto[e.key] ?? 0;
                final m = (manuell[e.key] as num?)?.toDouble() ?? 0;
                return ListTile(
                  dense: true,
                  title: Text(e.key),
                  subtitle: Text('Plan ${_z(a)} m'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 90,
                      child: SpeicherFeld(
                        key: ValueKey('pp-${e.key}-$m'),
                        initialValue: m == 0 ? '' : _z(m),
                        decoration: const InputDecoration(hintText: '+ m', isDense: true),
                        onFieldSubmitted: (t) {
                          final d = double.tryParse(t.replaceAll(',', '.'));
                          final n = {...manuell};
                          d == null || d == 0 ? n.remove(e.key) : n[e.key] = d;
                          store.einstellungSetzen('putzprofile', n);
                          setState(() {});
                        },
                      ),
                    ),
                    SizedBox(width: 130, child: Text('${_z(a + m)} m = ${profilStaebe(e.key, a + m)} Stäbe', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                );
              }(),
          ]),
        ),
      ],
    ]);
  }

  // --------------------------------------------------------- Fensterbänke

  Widget _fensterbaenke() {
    final store = _s.store!;
    final gid = _s.geschossId!;
    final waende = {for (final w in store.waende(gid)) w.id: w};
    final wdvs = WdvsVorgaben.ausJson(store.einstellung<Map>('wdvs'));
    final mitWdvs = store.einstellung<Map>('wdvs') != null;
    final fenster = [for (final o in store.oeffnungen(gid)) if (o.art == OeffnungsArt.fenster) o];
    void setzen(Oeffnung o, Map<String, Object?> w) {
      store.oeffnungAendern(o.id, {'eigenschaften': jsonEncode({...o.eigenschaften, ...w}..removeWhere((k, v) => v == null))});
      _s.geaendert();
      setState(() {});
    }

    final bestellung = <String, (int, double)>{}; // Material + Maß → Stück
    final zeilen = <Widget>[];
    for (final (i, o) in fenster.indexed) {
      final w = waende[o.wandId];
      final dicke = (w?.dicke ?? 365).toDouble();
      final ma = o.eigenschaften['fb_aussen'] as String? ?? fensterbankAussen.first;
      final mi = o.eigenschaften['fb_innen'] as String? ?? fensterbankInnen.first;
      final lAussen = ((o.eigenschaften['laibung_aussen'] as num?) ?? dicke * 0.45).toDouble();
      final lInnen = ((o.eigenschaften['laibung_innen'] as num?) ?? dicke * 0.35).toDouble();
      final a = ma == 'keine' ? null : fensterbankAussenBerechnen(material: ma, breite: o.breite.toDouble(), laibungstiefe: lAussen, daemmung: mitWdvs ? wdvs.dicke.toDouble() : 0);
      final inn = fensterbankInnenBerechnen(material: mi, breite: o.breite.toDouble(), laibungInnen: lInnen);
      if (a != null) {
        final k = 'Außen $ma ${(a.laenge).round()} × ${(a.tiefe / 5).ceil() * 5} mm';
        bestellung[k] = ((bestellung[k]?.$1 ?? 0) + 1, a.laenge);
      }
      if (inn.laenge > 0) {
        final k = 'Innen $mi ${inn.laenge.round()} × ${(inn.tiefe / 5).ceil() * 5} mm';
        bestellung[k] = ((bestellung[k]?.$1 ?? 0) + 1, inn.laenge);
      }
      zeilen.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Fenster ${i + 1}: ${o.breite} × ${o.hoehe} mm, Brüstung ${o.bruestung} mm, Wand ${dicke.round()} mm', style: const TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: ma,
                  decoration: const InputDecoration(labelText: 'Außenfensterbank', isDense: true),
                  items: [for (final m in fensterbankAussen) DropdownMenuItem(value: m, child: Text(m))],
                  onChanged: (m) => setzen(o, {'fb_aussen': m}),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: mi,
                  decoration: const InputDecoration(labelText: 'Innenfensterbank', isDense: true),
                  items: [for (final m in fensterbankInnen) DropdownMenuItem(value: m, child: Text(m))],
                  onChanged: (m) => setzen(o, {'fb_innen': m}),
                ),
              ),
              for (final (k, l, v) in [('laibung_aussen', 'Laibung außen', lAussen), ('laibung_innen', 'Laibung innen', lInnen)])
                SizedBox(
                  width: 120,
                  child: SpeicherFeld(
                    key: ValueKey('fb-$k-${o.id}-$v'),
                    initialValue: '${v.round()}',
                    decoration: InputDecoration(labelText: l, suffixText: 'mm', isDense: true),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onFieldSubmitted: (t) => setzen(o, {k: int.tryParse(t)}),
                  ),
                ),
            ]),
            if (a != null)
              Text('Außen: ${a.laenge.round()} × ${a.tiefe.round()} mm${a.endkappen > 0 ? ', ${a.endkappen} Bordprofile' : ''} · ${a.zubehoer.join(', ')}', style: const TextStyle(fontSize: 12)),
            if (inn.laenge > 0) Text('Innen: ${inn.laenge.round()} × ${inn.tiefe.round()} mm${inn.zubehoer.isEmpty ? '' : ' · ${inn.zubehoer.join(', ')}'}', style: const TextStyle(fontSize: 12)),
            _hinweise([...?a?.hinweise, ...inn.hinweise]),
          ]),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Fensterbänke im Geschoss ${store.geschoss(gid)?.kuerzel}${mitWdvs ? ' (mit WDVS ${wdvs.dicke} mm)' : ''}. Tiefe außen = Laibung + Dämmung + 40 mm Überstand, gerundet auf 5 mm.',
          style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      if (fenster.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Keine Fenster in diesem Geschoss.')),
      ...zeilen,
      if (bestellung.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Bestellliste', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final e in bestellung.entries) Text('${e.value.$1}× ${e.key}'),
      ],
    ]);
  }
}
