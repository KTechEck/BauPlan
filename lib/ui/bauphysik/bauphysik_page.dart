import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/heizlast.dart';
import '../../core/raumerkennung.dart';
import '../../core/waermebruecke.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import '../floorplan/dach_dialog.dart' show dachLesen;
import '../../core/dach.dart' show uDach, dachflaecheUeber;
import 'oberflaechen_ansicht.dart';

/// λ eines Baustoffs: hinterlegt oder Richtwert.
double lambdaVon(Baustoff m) => (m.eigenschaften['lambda'] as num?)?.toDouble() ?? lambdaVorschlag(m.name, m.kategorie);

/// Projektparameter der Heizlast (Einstellungen → Standort und Klima).
HlParameter heizlastParameter(ProjectStore store) {
  final m = store.einstellung<Map>('heizlast') ?? const {};
  double z(String k, double v) => (m[k] as num?)?.toDouble() ?? v;
  return HlParameter(normAussen: z('theta_e', -12), jahresmittel: z('theta_m', 9), unbeheizt: z('unbeheizt', 5), deltaUwb: z('delta_uwb', 0.05));
}

(double, double) systemTemperaturen(ProjectStore store) {
  final m = store.einstellung<Map>('heizlast') ?? const {};
  return ((m['vorlauf'] as num?)?.toDouble() ?? 55, (m['ruecklauf'] as num?)?.toDouble() ?? 45);
}

List<Aufbau> aufbauten(ProjectStore store) => [
      for (final m in (store.einstellung<List>('aufbauten') ?? const [])) Aufbau.ausJson(Map<String, dynamic>.from(m as Map)),
    ];

/// Modul Bauphysik: Heizlast je Raum, Boden-/Deckenaufbauten, Baustoffkennwerte.
class BauphysikPage extends StatefulWidget {
  const BauphysikPage({super.key, required this.state});
  final AppState state;

  @override
  State<BauphysikPage> createState() => _BauphysikPageState();
}

class _BauphysikPageState extends State<BauphysikPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
        child: Row(children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Heizlast')),
              ButtonSegment(value: 1, label: Text('Boden- und Deckenaufbauten')),
              ButtonSegment(value: 2, label: Text('Baustoffkennwerte')),
              ButtonSegment(value: 3, label: Text('Oberflächen')),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
        ]),
      ),
      Expanded(
        child: switch (_tab) {
          0 => HeizlastAnsicht(state: widget.state),
          1 => AufbautenAnsicht(state: widget.state),
          3 => OberflaechenAnsicht(state: widget.state),
          _ => _BaustoffAnsicht(state: widget.state),
        },
      ),
    ]);
  }
}

// ------------------------------------------------------------ Heizlast

class HeizlastAnsicht extends StatefulWidget {
  const HeizlastAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<HeizlastAnsicht> createState() => _HeizlastAnsichtState();
}

class _HeizlastAnsichtState extends State<HeizlastAnsicht> {
  String? _raum;
  AppState get _s => widget.state;

  /// Räume, Wände und Öffnungen eines Geschosses für die Berechnung aufbereiten.
  (List<HlErgebnis>, Map<String, double>) _rechnen(Geschoss g, List<Geschoss> alle) {
    final store = _s.store!;
    final mat = {for (final m in store.materialien()) m.id: m};
    double lam(String id) => mat[id] == null ? 0.8 : lambdaVon(mat[id]!);
    final aufb = {for (final a in aufbauten(store)) a.id: a};
    final sortiert = [...alle]..sort((a, b) => a.hoehen.rfb.compareTo(b.hoehen.rfb));
    final unten = sortiert.first.id == g.id, oben = sortiert.last.id == g.id;
    final raeume = <HlRaum>[];
    // Dachgeschoss: Dach als Decke gegen außen, U aus Sparren/Dämmung, Fläche geneigt
    final dach = dachLesen(store, g.id);
    for (final r in store.raeume(g.id)) {
      if (r.umriss == null || r.umriss!.length < 3) continue;
      final e = r.eigenschaften;
      final h = r.hoehen(g);
      final bodenGegen = Gegen.values.where((x) => x.name == e['boden_gegen']).firstOrNull ?? (unten ? Gegen.erdreich : Gegen.beheizt);
      final deckeGegen = Gegen.values.where((x) => x.name == e['decke_gegen']).firstOrNull ?? (oben || dach.aktiv ? Gegen.aussen : Gegen.beheizt);
      double uAus(String? aufbauId, Gegen gegen, {required bool decke}) {
        final a = aufb[aufbauId];
        if (a != null) return a.uWert(lam, alsDecke: decke);
        return (e[decke ? 'u_decke' : 'u_boden'] as num?)?.toDouble() ??
            switch (gegen) {
              Gegen.erdreich => 1.0,
              Gegen.aussen => 0.8,
              Gegen.unbeheizt => 1.0,
              Gegen.beheizt => 0.0,
            };
      }

      raeume.add(HlRaum(
        id: r.id,
        name: r.name,
        umriss: r.umriss!,
        hoehe: math.max(1000, (r.ukDecke ?? h.rohdecke) - h.ffb),
        temperatur: (e['temp'] as num?)?.toDouble() ?? innenTemperaturVorschlag(r.name),
        luftwechsel: (e['luftwechsel'] as num?)?.toDouble() ?? luftwechselVorschlag(r.name),
        beheizt: e['beheizt'] != false && r.art == RaumArt.raum,
        boden: bodenGegen,
        uBoden: uAus(e['boden_aufbau'] as String?, bodenGegen, decke: false),
        decke: deckeGegen,
        uDecke: dach.aktiv && e['decke_aufbau'] == null && e['u_decke'] == null
            ? uDach(dach) * dachflaecheUeber(1, dach)
            : uAus(e['decke_aufbau'] as String?, deckeGegen, decke: true),
      ));
    }
    final waende = <HlWand>[];
    for (final w in store.waende(g.id)) {
      final typ = w.wandtypId == null ? null : store.wandtyp(w.wandtypId!);
      double? u(double rsi, double rse) {
        if (typ == null || typ.schichten.isEmpty) return null;
        return 1 / (rsi + rse + typ.schichten.fold<double>(0, (s, x) => s + x.dicke / 1000 / lam(x.materialId)));
      }

      waende.add(HlWand(
        id: w.id,
        a: Punkt(w.x1.toDouble(), w.y1.toDouble()),
        b: Punkt(w.x2.toDouble(), w.y2.toDouble()),
        dicke: w.dicke,
        u: u(0.13, 0.04) ?? (w.dicke >= 300 ? 1.0 : 1.4),
        uInnen: u(0.13, 0.13) ?? 2.0,
      ));
    }
    final oeff = <HlOeffnung>[];
    for (final o in store.oeffnungen(g.id)) {
      if (o.art == OeffnungsArt.durchbruch) continue;
      final be = _s.bibliothek.fuerProjekt(store, o.eigenschaften['bauelement'] as String?);
      final rolll = _s.bibliothek.fuerProjekt(store, o.eigenschaften['sonnenschutz'] as String?);
      final psi = ((o.eigenschaften['einbau'] as Map?)?['psi'] as num?)?.toDouble();
      var u = be?.zahl(o.art.verglast ? 'uw' : 'ud')?.toDouble() ?? (o.art.verglast ? 1.3 : 1.8);
      if (psi != null) u = uwEingebaut(uw: u, breite: o.breite, hoehe: o.hoehe, psi: psi, psiKasten: rolll?.zahl('psi_kasten')?.toDouble());
      oeff.add(HlOeffnung(wandId: o.wandId, abstand: o.abstand, breite: o.breite, hoehe: o.hoehe, u: u, name: '${o.art.label} ${mmText(o.breite)}×${mmText(o.hoehe)}'));
    }
    final erg = heizlastBerechnen(raeume, waende, oeff, heizlastParameter(store));
    // Vorhandene Heizflächen (Heizkörper mit Produktdaten) je Raum
    final (vl, rl) = systemTemperaturen(store);
    final flaechen = <String, double>{};
    for (final o in store.alleObjekte()) {
      if (o.raumId == null || o.geschossId != g.id) continue;
      final be = _s.bibliothek.fuerProjekt(store, o.eigenschaften['bauelement'] as String?);
      final qn = be?.zahl('q_norm')?.toDouble();
      if (qn == null) continue;
      final ti = erg.where((e) => e.raum.id == o.raumId).firstOrNull?.raum.temperatur ?? 20;
      flaechen[o.raumId!] = (flaechen[o.raumId!] ?? 0) + heizkoerperLeistung(qn, be!.zahl('exponent')?.toDouble() ?? 1.3, vl, rl, ti);
    }
    return (erg, flaechen);
  }

  void _raumSetzen(Raum r, Map<String, dynamic> neu) {
    final eig = {...r.eigenschaften, ...neu}..removeWhere((_, v) => v == null);
    _s.store!.raumEigenschaftenSetzen(r.id, eig);
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final geschosse = [for (final geb in store.gebaeude()) ...store.geschosse(geb.id)];
    final g = geschosse.where((x) => x.id == _s.geschossId).firstOrNull ?? geschosse.firstOrNull;
    if (g == null) return const Center(child: Text('Noch kein Geschoss angelegt.'));
    final (erg, flaechen) = _rechnen(g, geschosse);
    final p = heizlastParameter(store);
    final (vl, rl) = systemTemperaturen(store);
    final summe = erg.fold<double>(0, (s, e) => s + e.gesamt);
    final ohneUmriss = store.raeume(g.id).where((r) => r.umriss == null).length;
    final gewaehlt = erg.where((e) => e.raum.id == _raum).firstOrNull;
    final raeume = {for (final r in store.raeume(g.id)) r.id: r};
    final aufb = aufbauten(store);
    String w(double x) => '${x.round()} W';

    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<String>(
              value: g.id,
              items: [for (final x in geschosse) DropdownMenuItem(value: x.id, child: Text('${x.kuerzel} · ${x.name}'))],
              onChanged: (v) => v == null ? null : _s.geschossWaehlen(v),
            ),
            Text('θe ${p.normAussen.toStringAsFixed(0)} °C · θm,e ${p.jahresmittel.toStringAsFixed(0)} °C · ΔU_WB ${p.deltaUwb.toStringAsFixed(2)} · System $vl/$rl °C',
                style: const TextStyle(color: BsFarben.textLeise)),
            TextButton(onPressed: () => _s.modulWaehlen(Modul.einstellungen), child: const Text('ändern (Einstellungen → Standort und Klima)')),
          ]),
          if (ohneUmriss > 0)
            Text('$ohneUmriss Räume ohne Umriss im Grundriss fehlen in der Berechnung.', style: const TextStyle(color: Color(0xFFE67700))),
          const SizedBox(height: 8),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Raum')),
                  DataColumn(label: Text('θi'), numeric: true),
                  DataColumn(label: Text('A m²'), numeric: true),
                  DataColumn(label: Text('V m³'), numeric: true),
                  DataColumn(label: Text('Transmission'), numeric: true),
                  DataColumn(label: Text('Lüftung'), numeric: true),
                  DataColumn(label: Text('Heizlast'), numeric: true),
                  DataColumn(label: Text('W/m²'), numeric: true),
                  DataColumn(label: Text('Heizkörper'), numeric: true),
                ],
                rows: [
                  for (final e in erg)
                    DataRow(
                      selected: e.raum.id == _raum,
                      onSelectChanged: (_) => setState(() => _raum = e.raum.id),
                      cells: [
                        DataCell(Text(e.raum.name)),
                        DataCell(Text('${e.raum.temperatur.toStringAsFixed(0)} °C')),
                        DataCell(Text(e.raum.flaeche.toStringAsFixed(1).replaceAll('.', ','))),
                        DataCell(Text(e.raum.volumen.toStringAsFixed(1).replaceAll('.', ','))),
                        DataCell(Text(w(e.transmission))),
                        DataCell(Text(w(e.lueftung))),
                        DataCell(Text(w(e.gesamt), style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(e.proQm.toStringAsFixed(0))),
                        DataCell(() {
                          final f = flaechen[e.raum.id];
                          if (f == null) return const Text('–');
                          final ok = f >= e.gesamt;
                          return Text('${w(f)} ${ok ? '✓' : '✗'}', style: TextStyle(color: ok ? const Color(0xFF2F9E44) : const Color(0xFFB91C1C)));
                        }()),
                      ],
                    ),
                  DataRow(cells: [
                    const DataCell(Text('Summe Geschoss', style: TextStyle(fontWeight: FontWeight.w600))),
                    const DataCell(Text('')),
                    DataCell(Text(erg.fold<double>(0, (s, e) => s + e.raum.flaeche).toStringAsFixed(1).replaceAll('.', ','))),
                    const DataCell(Text('')),
                    DataCell(Text(w(erg.fold<double>(0, (s, e) => s + e.transmission)))),
                    DataCell(Text(w(erg.fold<double>(0, (s, e) => s + e.lueftung)))),
                    DataCell(Text(w(summe), style: const TextStyle(fontWeight: FontWeight.w700))),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              'Vereinfachtes Verfahren nach DIN EN 12831-1: Innenmaße, pauschaler Wärmebrückenzuschlag, Mindestluftwechsel, '
              'ohne Aufheizzuschlag. U-Werte aus Wandtypen, Aufbauten und Fenster-/Türdaten der Bibliothek (Ψ aus dem Einbaudetail, wenn berechnet). '
              'Für Förderanträge und die Auslegung der Wärmepumpe eine normgerechte Heizlastberechnung durch Fachplaner.',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        ]),
      ),
      SizedBox(
        width: 360,
        child: Material(
          color: Colors.white,
          child: gewaehlt == null || raeume[gewaehlt.raum.id] == null
              ? const Center(child: Text('Raum in der Tabelle wählen.', style: TextStyle(color: BsFarben.textLeise)))
              : _raumDetails(gewaehlt, raeume[gewaehlt.raum.id]!, aufb),
        ),
      ),
    ]);
  }

  Widget _raumDetails(HlErgebnis e, Raum r, List<Aufbau> aufb) {
    Widget zahl(String label, String k, double wert, String einheit) => SpeicherFeld(
          key: ValueKey('hl-$k-${r.id}-$wert'),
          initialValue: wert.toString().replaceAll('.', ','),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]'))],
          decoration: InputDecoration(labelText: label, suffixText: einheit),
          onFieldSubmitted: (v) => _raumSetzen(r, {k: num.tryParse(v.replaceAll(',', '.'))}),
        );

    Widget lage(String titel, String kGegen, String kAufbau, Gegen gegen, bool decke) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          DropdownButtonFormField<Gegen>(
            key: ValueKey('hl-$kGegen-${r.id}-${gegen.name}'),
            initialValue: gegen,
            isExpanded: true,
            decoration: InputDecoration(labelText: '$titel grenzt an'),
            items: [for (final x in Gegen.values) DropdownMenuItem(value: x, child: Text(x.label))],
            onChanged: (v) => _raumSetzen(r, {kGegen: v?.name}),
          ),
          if (gegen != Gegen.beheizt)
            DropdownButtonFormField<String?>(
              key: ValueKey('hl-$kAufbau-${r.id}-${r.eigenschaften[kAufbau]}'),
              initialValue: aufb.any((a) => a.id == r.eigenschaften[kAufbau]) ? r.eigenschaften[kAufbau] as String : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: '$titel-Aufbau', helperText: 'ohne Aufbau: Richtwert für Bestand'),
              items: [
                const DropdownMenuItem(value: null, child: Text('– Richtwert –')),
                for (final a in aufb) DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => _raumSetzen(r, {kAufbau: v}),
            ),
        ]);

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(r.name, style: Theme.of(context).textTheme.titleLarge),
      Text('Heizlast ${e.gesamt.round()} W · ${e.proQm.round()} W/m²', style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('beheizt'),
        value: r.eigenschaften['beheizt'] != false,
        onChanged: (v) => _raumSetzen(r, {'beheizt': v ? null : false}),
      ),
      zahl('Norm-Innentemperatur', 'temp', e.raum.temperatur, '°C'),
      zahl('Mindestluftwechsel', 'luftwechsel', e.raum.luftwechsel, '1/h'),
      lage('Boden', 'boden_gegen', 'boden_aufbau', e.raum.boden, false),
      lage('Decke', 'decke_gegen', 'decke_aufbau', e.raum.decke, true),
      const Divider(height: 28),
      Text('Wärmeverluste', style: Theme.of(context).textTheme.titleSmall),
      for (final p in e.posten)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
              child: Text('${p.bauteil}\n${p.flaeche.toStringAsFixed(2).replaceAll('.', ',')} m² · U ${p.u.toStringAsFixed(2).replaceAll('.', ',')} · ΔT ${p.deltaT.toStringAsFixed(0)} K',
                  style: const TextStyle(fontSize: 12)),
            ),
            Text('${p.leistung.round()} W'),
          ]),
        ),
      Row(children: [
        Expanded(child: Text('Lüftung ${e.raum.luftwechsel.toString().replaceAll('.', ',')}/h · ${e.raum.volumen.toStringAsFixed(1).replaceAll('.', ',')} m³', style: const TextStyle(fontSize: 12))),
        Text('${e.lueftung.round()} W'),
      ]),
    ]);
  }
}

// ------------------------------------------------------------ Aufbauten

/// Boden- und Deckenaufbauten zeichnen (Schichten oben → unten) mit U-Wert.
class AufbautenAnsicht extends StatefulWidget {
  const AufbautenAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<AufbautenAnsicht> createState() => _AufbautenAnsichtState();
}

class _AufbautenAnsichtState extends State<AufbautenAnsicht> {
  String? _auswahl;
  AppState get _s => widget.state;

  void _speichern(List<Aufbau> l) {
    _s.store!.einstellungSetzen('aufbauten', [for (final a in l) a.toJson()]);
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final liste = aufbauten(store);
    final mat = store.materialien();
    final nach = {for (final m in mat) m.id: m};
    final a = liste.where((x) => x.id == _auswahl).firstOrNull;
    void aendern(Aufbau neu) => _speichern([for (final x in liste) x.id == neu.id ? neu : x]);

    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 300,
        child: Material(
          color: Colors.white,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final (titel, art, schichten) in [
                ('Geschossdecke', Gegen.beheizt, ['Estrich:60', 'Dämm:40', 'Beton:180', 'Putz:10']),
                ('Bodenplatte', Gegen.erdreich, ['Estrich:60', 'Dämm:100', 'Beton:250']),
                ('Kellerdecke', Gegen.unbeheizt, ['Estrich:50', 'Dämm:40', 'Beton:180', 'Dämm:100']),
                ('Oberste Decke / Dach', Gegen.aussen, ['Gipskarton:13', 'Dämm:240', 'Holz:22']),
              ])
                OutlinedButton(
                  onPressed: () {
                    String? suche(String w) => mat.where((m) => '${m.name} ${m.kategorie}'.toLowerCase().contains(w.toLowerCase())).firstOrNull?.id;
                    final s = [
                      for (final x in schichten)
                        if (suche(x.split(':').first) case final id?) (id, int.parse(x.split(':').last)),
                    ];
                    final neu = Aufbau(id: 'auf-${DateTime.now().microsecondsSinceEpoch}', name: titel, art: art, schichten: s);
                    _speichern([...liste, neu]);
                    setState(() => _auswahl = neu.id);
                  },
                  child: Text('+ $titel'),
                ),
            ]),
            const SizedBox(height: 12),
            for (final x in liste)
              ListTile(
                selected: x.id == _auswahl,
                selectedTileColor: BsFarben.akzentHell,
                title: Text(x.name),
                subtitle: Text('${x.dicke} mm · U ${x.uWert((id) => nach[id] == null ? 0.8 : lambdaVon(nach[id]!), alsDecke: x.art != Gegen.erdreich).toStringAsFixed(2).replaceAll('.', ',')}'),
                onTap: () => setState(() => _auswahl = x.id),
              ),
            if (liste.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Noch keine Aufbauten. Oben eine Vorlage wählen und dann die Schichten anpassen.', style: TextStyle(color: BsFarben.textLeise)),
              ),
          ]),
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: a == null
            ? const Center(child: Text('Aufbau wählen oder anlegen.', style: TextStyle(color: BsFarben.textLeise)))
            : ListView(padding: const EdgeInsets.all(20), children: [
                Row(children: [
                  Expanded(
                    child: SpeicherFeld(
                      key: ValueKey('auf-name-${a.id}'),
                      initialValue: a.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      decoration: const InputDecoration(border: InputBorder.none),
                      onFieldSubmitted: (v) => aendern(Aufbau(id: a.id, name: v.trim(), art: a.art, schichten: a.schichten)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Löschen',
                    onPressed: () {
                      _speichern([for (final x in liste) if (x.id != a.id) x]);
                      setState(() => _auswahl = null);
                    },
                    icon: const Icon(Sym.loeschen),
                  ),
                ]),
                SizedBox(
                  width: 360,
                  child: DropdownButtonFormField<Gegen>(
                    key: ValueKey('auf-art-${a.id}-${a.art.name}'),
                    initialValue: a.art,
                    decoration: const InputDecoration(labelText: 'Unterseite / Oberseite grenzt an'),
                    items: [for (final g in Gegen.values) DropdownMenuItem(value: g, child: Text(g.label))],
                    onChanged: (v) => aendern(Aufbau(id: a.id, name: a.name, art: v ?? a.art, schichten: a.schichten)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 520,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Schichten von oben nach unten', style: TextStyle(fontWeight: FontWeight.w600)),
                      for (var i = 0; i < a.schichten.length; i++)
                        Row(children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('auf-m-${a.id}-$i-${a.schichten[i].$1}'),
                              isExpanded: true,
                              initialValue: nach.containsKey(a.schichten[i].$1) ? a.schichten[i].$1 : null,
                              items: [for (final m in mat) DropdownMenuItem(value: m.id, child: Text('${m.name} (λ ${lambdaVon(m).toString().replaceAll('.', ',')})'))],
                              onChanged: (v) {
                                final s = [...a.schichten];
                                s[i] = (v ?? s[i].$1, s[i].$2);
                                aendern(Aufbau(id: a.id, name: a.name, art: a.art, schichten: s));
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 90,
                            child: SpeicherFeld(
                              key: ValueKey('auf-d-${a.id}-$i-${a.schichten[i].$2}'),
                              initialValue: '${a.schichten[i].$2}',
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(suffixText: 'mm'),
                              onFieldSubmitted: (v) {
                                final s = [...a.schichten];
                                s[i] = (s[i].$1, int.tryParse(v) ?? s[i].$2);
                                aendern(Aufbau(id: a.id, name: a.name, art: a.art, schichten: s));
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'nach oben',
                            onPressed: i == 0
                                ? null
                                : () {
                                    final s = [...a.schichten];
                                    final x = s.removeAt(i);
                                    s.insert(i - 1, x);
                                    aendern(Aufbau(id: a.id, name: a.name, art: a.art, schichten: s));
                                  },
                            icon: const Icon(Icons.arrow_upward, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Schicht entfernen',
                            onPressed: () => aendern(Aufbau(id: a.id, name: a.name, art: a.art, schichten: [...a.schichten]..removeAt(i))),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ]),
                      TextButton.icon(
                        onPressed: mat.isEmpty ? null : () => aendern(Aufbau(id: a.id, name: a.name, art: a.art, schichten: [...a.schichten, (mat.first.id, 50)])),
                        icon: const Icon(Sym.hinzufuegen, size: 18),
                        label: const Text('Schicht'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gesamt ${a.dicke} mm · U = ${a.uWert((id) => nach[id] == null ? 0.8 : lambdaVon(nach[id]!), alsDecke: a.art != Gegen.erdreich).toStringAsFixed(3).replaceAll('.', ',')} W/(m²K)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: SizedBox(
                      height: math.max(160, a.dicke * 0.9 + 40),
                      child: CustomPaint(painter: _AufbauPainter(a, nach)),
                    ),
                  ),
                ]),
              ]),
      ),
    ]);
  }
}

/// Schnitt durch den Aufbau mit Schraffur je Materialfarbe.
class _AufbauPainter extends CustomPainter {
  _AufbauPainter(this.a, this.mat);
  final Aufbau a;
  final Map<String, Baustoff> mat;

  @override
  void paint(Canvas canvas, Size size) {
    if (a.dicke == 0) return;
    final m = (size.height - 20) / a.dicke;
    var y = 10.0;
    final breite = math.min(size.width - 160, 360.0);
    for (final s in a.schichten) {
      final h = s.$2 * m;
      final b = mat[s.$1];
      final r = Rect.fromLTWH(0, y, breite, h);
      canvas.drawRect(r, Paint()..color = Color(b?.farbe ?? 0xFFCCCCCC));
      if ((b?.eigenschaften['lambda'] as num? ?? lambdaVorschlag(b?.name ?? '', b?.kategorie ?? '')) < 0.06) {
        // Dämmung: Wellenlinie
        final pfad = Path()..moveTo(0, y + h / 2);
        for (var x = 0.0; x <= breite; x += 8) {
          pfad.lineTo(x, y + h / 2 + (((x / 8).round()).isEven ? -h * 0.3 : h * 0.3));
        }
        canvas.drawPath(pfad, Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black45);
      }
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black54);
      final tp = TextPainter(
        text: TextSpan(text: '${s.$2} mm ${b?.name ?? '?'}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 150);
      tp.paint(canvas, Offset(breite + 8, y + h / 2 - tp.height / 2));
      y += h;
    }
  }

  @override
  bool shouldRepaint(covariant _AufbauPainter old) => true;
}

// ------------------------------------------------------------ Baustoffe

class _BaustoffAnsicht extends StatefulWidget {
  const _BaustoffAnsicht({required this.state});
  final AppState state;

  @override
  State<_BaustoffAnsicht> createState() => _BaustoffAnsichtState();
}

class _BaustoffAnsichtState extends State<_BaustoffAnsicht> {
  @override
  Widget build(BuildContext context) {
    final store = widget.state.store!;
    final mat = store.materialien();
    Widget feld(Baustoff m, String k, String einheit, String? vorschlag) => SizedBox(
          width: 130,
          child: SpeicherFeld(
            key: ValueKey('bs-$k-${m.id}-${m.eigenschaften[k]}'),
            initialValue: m.eigenschaften[k]?.toString().replaceAll('.', ',') ?? '',
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
            decoration: InputDecoration(isDense: true, suffixText: einheit, hintText: vorschlag),
            onFieldSubmitted: (v) {
              final z = num.tryParse(v.replaceAll(',', '.'));
              final eig = {...m.eigenschaften};
              if (z == null) {
                eig.remove(k);
              } else {
                eig[k] = z;
              }
              store.materialEigenschaftenSetzen(m.id, eig);
              widget.state.geaendert();
              setState(() {});
            },
          ),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Wärmeleitfähigkeit λ und Rohdichte der Baustoffe. Leere Felder: Richtwert (grau) wird verwendet. Bemessungswerte stehen im Datenblatt oder in DIN 4108-4.',
          style: TextStyle(color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (final m in mat)
            ListTile(
              leading: Container(width: 18, height: 18, color: Color(m.farbe)),
              title: Text(m.name),
              subtitle: Text(m.kategorie),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('λ '),
                feld(m, 'lambda', 'W/(mK)', lambdaVorschlag(m.name, m.kategorie).toString().replaceAll('.', ',')),
                const SizedBox(width: 12),
                const Text('ρ '),
                feld(m, 'rho', 'kg/m³', null),
              ]),
            ),
        ]),
      ),
    ]);
  }
}
