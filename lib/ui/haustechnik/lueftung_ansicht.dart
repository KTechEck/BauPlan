import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/gebaeude.dart' show himmelsrichtung, fcSonnenschutz;
import '../../core/klima_lueftung.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

String _z(double v, [int n = 0]) => v.toStringAsFixed(n).replaceAll('.', ',');

List<(Raum, Geschoss)> _alleRaeume(AppState s) => [
      for (final geb in s.store!.gebaeude())
        for (final g in s.store!.geschosse(geb.id))
          for (final r in s.store!.raeume(g.id))
            if (r.umriss != null && r.art == RaumArt.raum) (r, g),
    ];

/// Lüftung Eigenbau nach DIN 1946-6 (vereinfacht): Zu-/Ab-/Überströmräume,
/// Volumenströme, Rohrdurchmesser, Überströmquerschnitte, eigene Komponenten
/// im Druckverlust, Dämmung und Kühloption mit Taupunkt.
class LueftungAnsicht extends StatefulWidget {
  const LueftungAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<LueftungAnsicht> createState() => _LueftungAnsichtState();
}

class _LueftungAnsichtState extends State<LueftungAnsicht> {
  AppState get _s => widget.state;
  Map<String, dynamic> get _e => Map<String, dynamic>.from(_s.store!.einstellung<Map>('lueftung') ?? const {});
  void _setzen(Map<String, Object?> w) {
    _s.store!.einstellungSetzen('lueftung', {..._e, ...w}..removeWhere((k, v) => v == null));
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final e = _e;
    final arten = Map<String, dynamic>.from(e['art'] as Map? ?? const {});
    final hand = Map<String, dynamic>.from(e['von_hand'] as Map? ?? const {});
    final raeume = _alleRaeume(_s);
    final luft = [
      for (final (r, _) in raeume)
        (
          id: r.id,
          name: r.name,
          flaeche: polygonFlaeche(r.umriss!).abs() / 1e6,
          art: LuftArt.values.where((a) => a.name == arten[r.id]).firstOrNull ?? luftArtVorschlag(r.name),
          vonHand: (hand[r.id] as num?)?.toDouble(),
        ),
    ];
    final v = lueftungVerteilen(luft);
    final komponenten = [
      for (final k in (e['komponenten'] as List? ?? const []))
        if (k is Map) (name: '${k['name']}', druckverlust: (k['dp'] as num? ?? 0).toDouble(), leistungW: (k['w'] as num?)?.toDouble(), art: '${k['art'] ?? 'sonstiges'}'),
    ];
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final kanaele = [for (final o in store.alleObjekte()) if (typen[o.typId]?.kuerzel == 'LK' && o.punkte.length >= 2) o];
    final laengster = kanaele.fold<double>(0, (m, o) => o.laenge > m ? o.laenge : m) / 1000;
    final haupt = (e['hauptrohr'] as num?)?.toInt() ?? luftrohrVorschlag(v.gesamt, vMax: 4);
    final hauptL = luftleitung(v.gesamt, haupt.toDouble());
    final strangPa = (laengster > 0 ? laengster : 15) * hauptL.r * 1.5;
    final bedarf = druckbedarf(strangPa: strangPa, komponenten: komponenten);
    final kuehlung = e['kuehlung'] == true;
    final geraetMax = (e['geraet_m3h'] as num?)?.toDouble();
    final geraetPa = (e['geraet_pa'] as num?)?.toDouble();

    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
          'Lüftung der ganzen Wohnung (eine Nutzungseinheit). Abluft aus Küche/Bad/WC/HWR, Zuluft in Wohn- und Schlafräume, Flure als Überströmzone. '
          'Volumenströme nach DIN 1946-6 vereinfacht (Nennlüftung), Raumart je Raum änderbar. Planungshilfe.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 6, children: [
        Chip(label: Text('Nennlüftung ${_z(v.gesamt)} m³/h')),
        for (final s in lueftungsStufen.entries) Chip(label: Text('${s.key} ${_z(v.gesamt * s.value)} m³/h')),
      ]),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columnSpacing: 16, columns: const [
            DataColumn(label: Text('Raum')),
            DataColumn(label: Text('Art')),
            DataColumn(label: Text('m³/h'), numeric: true),
            DataColumn(label: Text('Rohr (≤ 3 m/s)')),
            DataColumn(label: Text('Hinweis')),
          ], rows: [
            for (final r in v.raeume)
              DataRow(cells: [
                DataCell(Text(r.name)),
                DataCell(DropdownButton<LuftArt>(
                  value: r.art,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: LuftArt.zuluft, child: Text('Zuluft')),
                    DropdownMenuItem(value: LuftArt.abluft, child: Text('Abluft')),
                    DropdownMenuItem(value: LuftArt.ueberstroem, child: Text('Überström')),
                    DropdownMenuItem(value: LuftArt.keine, child: Text('keine')),
                  ],
                  onChanged: (a) => _setzen({'art': {...arten, r.id: a?.name}}),
                )),
                DataCell(r.art == LuftArt.ueberstroem || r.art == LuftArt.keine
                    ? const Text('–')
                    : SizedBox(
                        width: 70,
                        child: SpeicherFeld(
                          key: ValueKey('lv-${r.id}-${r.volumenstrom.round()}-${hand[r.id]}'),
                          initialValue: _z(r.volumenstrom),
                          textAlign: TextAlign.right,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onFieldSubmitted: (t) {
                            final m = {...hand};
                            final n = int.tryParse(t);
                            n == null ? m.remove(r.id) : m[r.id] = n;
                            _setzen({'von_hand': m});
                          },
                        ),
                      )),
                DataCell(Text(r.volumenstrom > 0 ? 'DN ${luftrohrVorschlag(r.volumenstrom)}' : '–')),
                DataCell(Text(
                  r.art == LuftArt.abluft
                      ? 'Überströmung zur Tür ca. ${_z(ueberstroemQuerschnitt(r.volumenstrom))} cm² (Türspalt/Gitter)'
                      : r.art == LuftArt.zuluft
                          ? 'Überströmung aus dem Raum ca. ${_z(ueberstroemQuerschnitt(r.volumenstrom))} cm²'
                          : '',
                  style: const TextStyle(fontSize: 12),
                )),
              ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text('Gerät und Leitungsnetz', style: Theme.of(context).textTheme.titleSmall),
      Wrap(spacing: 10, runSpacing: 8, children: [
        for (final (k, l, w) in [('hauptrohr', 'Hauptleitung DN', haupt.toDouble()), ('geraet_m3h', 'Gerät max. m³/h', geraetMax ?? 0), ('geraet_pa', 'Gerät ext. Pressung Pa', geraetPa ?? 0)])
          SizedBox(
            width: 180,
            child: SpeicherFeld(
              key: ValueKey('lg-$k-$w'),
              initialValue: w == 0 ? '' : _z(w),
              decoration: InputDecoration(labelText: l, isDense: true),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (t) => _setzen({k: int.tryParse(t)}),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      Text('Hauptleitung DN $haupt: ${_z(hauptL.v, 1)} m/s, ${_z(hauptL.r, 1)} Pa/m · längster Kanal ${laengster > 0 ? '${_z(laengster, 1)} m (Luftkanäle im Plan)' : 'angenommen 15 m'} '
          '→ Strang ${_z(strangPa)} Pa + Komponenten + Ventile/Außen-/Fortluft = ${_z(bedarf)} Pa'),
      if (hauptL.v > 4) const Text('• Hauptleitung über 4 m/s – größer wählen (Geräusche).', style: TextStyle(color: Color(0xFFB45309))),
      if (geraetMax != null && geraetMax > 0 && geraetMax < v.gesamt * 1.3)
        Text('• Gerät schafft ${_z(geraetMax)} m³/h – Intensivlüftung braucht ${_z(v.gesamt * 1.3)} m³/h.', style: const TextStyle(color: Color(0xFFB45309))),
      if (geraetPa != null && geraetPa > 0 && geraetPa < bedarf)
        Text('• Externe Pressung ${_z(geraetPa)} Pa reicht nicht für ${_z(bedarf)} Pa.', style: const TextStyle(color: Color(0xFFB45309))),
      const SizedBox(height: 12),
      Row(children: [
        Text('Eigene Komponenten (laufen im Druckverlust mit)', style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _setzen({
            'komponenten': [...(e['komponenten'] as List? ?? const []), {'name': 'Schalldämpfer', 'dp': 15, 'art': 'schalldaempfer'}]
          }),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Komponente'),
        ),
      ]),
      for (final (i, k) in komponenten.indexed)
        Row(children: [
          Expanded(
            child: SpeicherFeld(
              key: ValueKey('lk-$i-${k.name}'),
              initialValue: k.name,
              decoration: const InputDecoration(hintText: 'Filter F7, Erdwärmetauscher, Kühlregister …', isDense: true),
              onFieldSubmitted: (t) {
                final l = [...(e['komponenten'] as List)];
                l[i] = {...(l[i] as Map), 'name': t.trim()};
                _setzen({'komponenten': l});
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: SpeicherFeld(
              key: ValueKey('lkd-$i-${k.druckverlust}'),
              initialValue: _z(k.druckverlust),
              decoration: const InputDecoration(suffixText: 'Pa', isDense: true),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (t) {
                final l = [...(e['komponenten'] as List)];
                l[i] = {...(l[i] as Map), 'dp': int.tryParse(t) ?? 0};
                _setzen({'komponenten': l});
              },
            ),
          ),
          SizedBox(
            width: 100,
            child: SpeicherFeld(
              key: ValueKey('lkw-$i-${k.leistungW}'),
              initialValue: k.leistungW == null ? '' : _z(k.leistungW!),
              decoration: const InputDecoration(suffixText: 'W', isDense: true, hintText: 'Leistung'),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (t) {
                final l = [...(e['komponenten'] as List)];
                l[i] = {...(l[i] as Map), 'w': int.tryParse(t)}..removeWhere((k, v) => v == null);
                _setzen({'komponenten': l});
              },
            ),
          ),
          IconButton(
            onPressed: () => _setzen({'komponenten': [...(e['komponenten'] as List)]..removeAt(i)}),
            icon: const Icon(Icons.close, size: 16),
          ),
        ]),
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Zuluft kühlen (Kühlregister/Erdwärmetauscher)'),
        value: kuehlung,
        onChanged: (b) => _setzen({'kuehlung': b ? true : null}),
      ),
      for (final h in daemmHinweise(kuehlung: kuehlung, zuluftTemp: ((e['zuluft_temp'] as num?) ?? 16).toDouble()))
        Text('• $h', style: const TextStyle(fontSize: 12)),
    ]);
  }
}

/// Kühlung und Klima: Taupunkt je Raum, kleinste Kühl-Vorlauftemperatur,
/// Kühllast-Richtwert und passende Klimagerätegröße.
class KlimaAnsicht extends StatefulWidget {
  const KlimaAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<KlimaAnsicht> createState() => _KlimaAnsichtState();
}

class _KlimaAnsichtState extends State<KlimaAnsicht> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final store = s.store!;
    final e = Map<String, dynamic>.from(store.einstellung<Map>('klima') ?? const {});
    final t = ((e['raum_temp'] as num?) ?? 26).toDouble();
    final f = ((e['feuchte'] as num?) ?? 55).toDouble();
    final tp = taupunkt(t, f);
    final nord = (store.einstellung<num>('norden_grad') ?? 0).toDouble();
    final typen = {for (final x in store.objekttypen()) x.id: x};
    void setzen(String k, Object? v) {
      store.einstellungSetzen('klima', {...e, k: v}..removeWhere((k, v) => v == null));
      setState(() {});
    }

    final zeilen = <DataRow>[];
    for (final (r, g) in _alleRaeume(s)) {
      final fenster = <({double glas, String richtung, double fc})>[];
      final waende = {for (final w in store.waende(g.id)) w.id: w};
      for (final o in store.oeffnungen(g.id)) {
        if (!o.art.verglast) continue;
        final w = waende[o.wandId];
        if (w == null || w.laenge < 1) continue;
        final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge;
        final m = Punkt(w.x1 + ux * (o.abstand + o.breite / 2), w.y1 + uy * (o.abstand + o.breite / 2));
        final d = w.dicke / 2 + 60;
        final links = punktInPolygon(Punkt(m.x - uy * d, m.y + ux * d), r.umriss!), rechts = punktInPolygon(Punkt(m.x + uy * d, m.y - ux * d), r.umriss!);
        if (links == rechts) continue;
        final ss = s.bibliothek.fuerProjekt(store, o.eigenschaften['sonnenschutz'] as String?);
        fenster.add((
          glas: o.breite * o.hoehe / 1e6 * 0.7,
          richtung: himmelsrichtung(links ? uy : -uy, links ? -ux : ux, nordGrad: nord),
          fc: ss == null ? 1.0 : fcSonnenschutz('${ss.name} ${ss.daten['art'] ?? ''}'),
        ));
      }
      final flaeche = polygonFlaeche(r.umriss!).abs() / 1e6;
      final last = kuehllast(flaeche: flaeche, fenster: fenster, personen: RegExp(r'schlaf').hasMatch(r.name.toLowerCase()) ? 2 : 1);
      final kg = store.objekte(g.id).where((o) => typen[o.typId]?.kuerzel == 'KG' && (o.raumId == r.id || (o.punkte.isNotEmpty && punktInPolygon(o.punkte.first, r.umriss!)))).toList();
      final kw = kg.fold<double>(0, (a, o) => a + ((o.eigenschaften['leistung_kw'] as num?) ?? 0).toDouble());
      zeilen.add(DataRow(cells: [
        DataCell(Text('${g.kuerzel} ${r.name}')),
        DataCell(Text(_z(flaeche, 1))),
        DataCell(Text('${_z(last)} W')),
        DataCell(Text('${_z(last / flaeche)} W/m²')),
        DataCell(Text('${_z(klimageraetGroesse(last), 1)} kW')),
        DataCell(Text(kg.isEmpty ? '–' : '${_z(kw, 1)} kW ${kw * 1000 >= last ? '✓' : '✗'}')),
      ]));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final (k, l, w) in [('raum_temp', 'Raumtemperatur Sommer °C', t), ('feuchte', 'rel. Feuchte %', f)])
          SizedBox(
            width: 200,
            child: SpeicherFeld(
              key: ValueKey('kl-$k-$w'),
              initialValue: _z(w),
              decoration: InputDecoration(labelText: l, isDense: true),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (x) => setzen(k, int.tryParse(x)),
            ),
          ),
        Chip(label: Text('Taupunkt ${_z(tp, 1)} °C')),
        Chip(label: Text('Flächenkühlung: Vorlauf mindestens ${_z(minKuehlVorlauf(t, f), 1)} °C')),
      ]),
      const SizedBox(height: 6),
      const Text(
          'Flächenkühlung (Fußboden/Decke) nie unter Taupunkt + 2 K fahren, Taupunktwächter am Vorlauf. Kühlleitungen und Kältemittelleitungen diffusionsdicht dämmen. '
          'Kühllast als Richtwert aus Fläche, Fenstern nach Himmelsrichtung und Sonnenschutz – Klimageräte (Typ „Klimagerät“, Feld leistung_kw) werden verglichen.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: const [
            DataColumn(label: Text('Raum')),
            DataColumn(label: Text('m²'), numeric: true),
            DataColumn(label: Text('Kühllast'), numeric: true),
            DataColumn(label: Text('spez.'), numeric: true),
            DataColumn(label: Text('Gerät ca.')),
            DataColumn(label: Text('geplant')),
          ], rows: zeilen),
        ),
      ),
    ]);
  }
}
