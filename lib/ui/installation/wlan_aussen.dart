import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/aussen.dart';
import '../../core/raumerkennung.dart';
import '../../core/wlan.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

String _z(double v, [int n = 1]) => v.toStringAsFixed(n).replaceAll('.', ',');

/// Access Points eines Geschosses (Typ AP) mit Sendeleistung.
List<WlanAp> wlanAps(ProjectStore store, String gid) {
  final typen = {for (final t in store.objekttypen()) t.id: t.kuerzel};
  return [
    for (final o in store.objekte(gid))
      if (typen[o.typId] == 'AP' && o.punkte.isNotEmpty) (id: o.id, p: o.punkte.first, dbm: ((o.eigenschaften['sendeleistung_dbm'] as num?) ?? 20).toDouble()),
  ];
}

/// Wände eines Geschosses mit ihrer Funkdämpfung (Decke zu anderen Geschossen bleibt außen vor).
List<WlanWand> wlanWaende(ProjectStore store, String gid) => [
      for (final w in store.waende(gid))
        (
          a: Punkt(w.x1.toDouble(), w.y1.toDouble()),
          b: Punkt(w.x2.toDouble(), w.y2.toDouble()),
          db: wandDaempfung(w.wandtypId == null ? '' : (store.wandtyp(w.wandtypId!)?.name ?? ''), w.dicke),
        ),
    ];

/// Ausleuchtung als farbiges Raster über dem Plan (rechnet nur bei Änderungen neu).
class WlanPainter extends CustomPainter {
  WlanPainter({required this.raster, required this.weite, required this.massstab, required this.verschiebung});
  final List<(Punkt, double)> raster;
  final double weite;
  final double massstab;
  final Offset verschiebung;

  @override
  void paint(Canvas canvas, Size size) {
    final s = weite * massstab;
    for (final (q, pg) in raster) {
      final m = Offset(q.x, q.y) * massstab + verschiebung;
      canvas.drawRect(Rect.fromCenter(center: m, width: s + 0.5, height: s + 0.5), Paint()..color = Color(wlanFarbe(pg)));
    }
  }

  @override
  bool shouldRepaint(WlanPainter o) => o.raster != raster || o.massstab != massstab || o.verschiebung != verschiebung;
}

/// Raster für ein Geschoss berechnen (Gebäude + 3 m Rand für den Außenbereich).
List<(Punkt, double)> wlanRasterGeschoss(ProjectStore store, String gid, WlanBand band, {double weite = 500}) {
  final aps = wlanAps(store, gid);
  final w = store.waende(gid);
  if (aps.isEmpty || w.isEmpty) return const [];
  final xs = [for (final x in w) ...[x.x1, x.x2]], ys = [for (final x in w) ...[x.y1, x.y2]];
  return wlanRaster(xs.reduce(math.min) - 3000.0, ys.reduce(math.min) - 3000.0, xs.reduce(math.max) + 3000.0, ys.reduce(math.max) + 3000.0, aps, wlanWaende(store, gid), band, raster: weite);
}

/// Auswertung je Raum und Hinweise zur Platzierung.
Future<void> wlanDialog(BuildContext context, AppState s, WlanBand band) async {
  final store = s.store!;
  final gid = s.geschossId!;
  final aps = wlanAps(store, gid);
  final waende = wlanWaende(store, gid);
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('WLAN-Abdeckung ${band.label} · ${store.geschoss(gid)?.kuerzel}'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: ListView(children: [
          Text('${aps.length} Access Points (Typ „Access Point“, Sendeleistung je Gerät im Feld sendeleistung_dbm, Vorgabe 20 dBm). '
              'Wände dämpfen nach Wandtyp (Beton ~15 dB, KS ~12, Ziegel ~9, Trockenbau ~4 bei 2,4 GHz; 5/6 GHz stärker).',
              style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          if (aps.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Noch kein Access Point im Geschoss – Netzwerk › Access Point setzen.')),
          for (final r in store.raeume(gid))
            if (r.umriss != null && aps.isNotEmpty)
              () {
                final e = wlanRaum(r.umriss!, aps, waende, band);
                final ok = e.anteilGut >= 0.9;
                return ListTile(
                  dense: true,
                  leading: Icon(ok ? Icons.wifi : Icons.wifi_2_bar, color: ok ? const Color(0xFF2F9E44) : const Color(0xFFE67700)),
                  title: Text(r.name),
                  subtitle: Text('${(e.anteilGut * 100).round()} % gut versorgt · schwächster Punkt ${e.minimum.round()} dBm (${wlanStufe(e.minimum)})'),
                  trailing: ok ? null : const Text('AP näher/zusätzlich', style: TextStyle(fontSize: 12)),
                );
              }(),
          const SizedBox(height: 8),
          const Text('Richtwerte: ≥ −67 dBm für Video/Telefonie, Access Points an der Decke mittig, je Etage meist einer pro 2–3 Räume, Kabel (LAN/PoE) statt Mesh-Funk.',
              style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
    ),
  );
}

// ------------------------------------------------------------------- Außen

/// Außenbereich: Regenwasser, Bewässerung, Licht und Strom außen, Kabel außen.
Future<void> aussenDialog(BuildContext context, AppState s) => showDialog<void>(
      context: context,
      builder: (_) => Dialog(child: SizedBox(width: 920, height: 660, child: _Aussen(state: s))),
    );

class _Aussen extends StatefulWidget {
  const _Aussen({required this.state});
  final AppState state;
  @override
  State<_Aussen> createState() => _AussenState();
}

class _AussenState extends State<_Aussen> {
  AppState get _s => widget.state;
  Map<String, dynamic> get _e => Map<String, dynamic>.from(_s.store!.einstellung<Map>('aussen') ?? const {});
  void _setzen(String k, Object? v) {
    _s.store!.einstellungSetzen('aussen', {..._e, k: v}..removeWhere((k, v) => v == null));
    _s.geaendert();
    setState(() {});
  }

  List<Objekt> _objekte(String k) {
    final store = _s.store!;
    final typen = {for (final t in store.objekttypen()) t.id: t.kuerzel};
    final gewerk = {for (final g in store.gewerke()) g.id: g.kuerzel};
    final au = {for (final t in store.objekttypen()) if (gewerk[t.gewerkId] == 'AU') t.id};
    return [for (final o in store.alleObjekte()) if (typen[o.typId] == k && au.contains(o.typId)) o];
  }

  Widget _zahl(String k, String l, num w, {String einheit = ''}) => SizedBox(
        width: 160,
        child: SpeicherFeld(
          key: ValueKey('au-$k-$w'),
          initialValue: '$w'.replaceAll('.', ','),
          decoration: InputDecoration(labelText: l, suffixText: einheit, isDense: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          onFieldSubmitted: (t) => _setzen(k, double.tryParse(t.replaceAll(',', '.'))),
        ),
      );

  Widget _liste(List<({String was, double menge, String einheit})> l) => Card(
        child: Column(children: [for (final x in l) ListTile(dense: true, title: Text(x.was), trailing: Text('${_z(x.menge)} ${x.einheit}', style: const TextStyle(fontWeight: FontWeight.w600)))]),
      );

  Widget _h(List<String> l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final x in l)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 15, color: BsFarben.textLeise),
              const SizedBox(width: 6),
              Expanded(child: Text(x, style: const TextStyle(fontSize: 12))),
            ]),
          ),
      ]);

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Außenbereich'),
            automaticallyImplyLeading: false,
            actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))],
            bottom: const TabBar(tabs: [Tab(text: 'Regenwasser'), Tab(text: 'Bewässerung'), Tab(text: 'Licht und Strom'), Tab(text: 'Kabel außen')]),
          ),
          body: TabBarView(children: [_regen(), _bewaesserung(), _licht(), _kabel()]),
        ),
      );

  Widget _regen() {
    final e = _e;
    final dach = (e['dach_m2'] as num? ?? 120).toDouble();
    final art = e['dach_art'] as String? ?? abflussbeiwerte.keys.first;
    final c = abflussbeiwerte[art] ?? 1.0;
    final fallrohre = _objekte('RF');
    final q = regenabfluss(dach, c);
    final qJe = fallrohre.isEmpty ? q : q / fallrohre.length;
    final z = zisterne(dachM2: dach, c: c, niederschlagMm: (e['niederschlag'] as num? ?? 750).toDouble(), personen: (e['personen'] as num? ?? 4).toInt(), gartenM2: _flaeche('GA'));
    final rg = rigole(dach, c);
    final zs = _objekte('ZS');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 10, runSpacing: 8, children: [
        _zahl('dach_m2', 'Dachfläche (Grundriss)', dach, einheit: 'm²'),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: art,
            decoration: const InputDecoration(labelText: 'Dachart', isDense: true),
            items: [for (final a in abflussbeiwerte.keys) DropdownMenuItem(value: a, child: Text(a))],
            onChanged: (a) => _setzen('dach_art', a),
          ),
        ),
        _zahl('niederschlag', 'Niederschlag', e['niederschlag'] as num? ?? 750, einheit: 'mm/a'),
        _zahl('personen', 'Personen', e['personen'] as num? ?? 4),
      ]),
      const SizedBox(height: 10),
      Text('Regenabfluss ${_z(q, 2)} l/s bei 300 l/(s·ha) · ${fallrohre.length} Fallrohre im Plan → je Fallrohr ${_z(qJe, 2)} l/s → mindestens DN ${fallrohrDn(qJe)}'),
      Text('Zisterne: Ertrag ${_z(z.ertrag)} m³/a, Bedarf ${_z(z.bedarf)} m³/a (WC, Waschmaschine, Garten ${_z(_flaeche('GA'), 0)} m²) → ca. ${_z(math.max(z.volumen, 2))} m³ Speicher${zs.isEmpty ? ' (noch keine Zisterne im Plan)' : ''}'),
      Text('Rigole (Versickerung, Richtwert): Speicher ${_z(rg.speicher)} m³ → ca. ${_z(rg.kiesVolumen)} m³ Kies oder Rigolenkörper'),
      _h([
        'Regenwasser getrennt vom Schmutzwasser führen (Trennsystem), Grundleitung DN 100–150 mit Gefälle ≥ 0,5 %.',
        'Versickerung nur bei geeignetem Boden (kf-Wert, Abstand zum Grundwasser ≥ 1 m, 6 m Abstand zu Kellern ohne Abdichtung) – Wasserbehörde fragen.',
        'Zisterne mit Filter, beruhigtem Zulauf, Überlauf mit Rückstauschutz; Regenwasserleitungen im Haus kennzeichnen (kein Trinkwasser).',
      ]),
    ]);
  }

  double _flaeche(String k) => _objekte(k).fold<double>(0, (a, o) => a + (o.punkte.length >= 3 ? polygonFlaeche(o.punkte).abs() / 1e6 : 0));

  Widget _bewaesserung() {
    final regner = [
      for (final o in _objekte('RE'))
        if (o.punkte.isNotEmpty)
          (p: o.punkte.first, radius: ((o.eigenschaften['radius_mm'] as num?) ?? 4000).toDouble(), lmin: ((o.eigenschaften['l_min'] as num?) ?? 8).toDouble(), ventil: o.eigenschaften['ventil'] as String?),
    ];
    final flaechen = [for (final o in _objekte('GA')) o.punkte];
    final ab = bewaesserungAbdeckung(flaechen, regner);
    final verf = (_e['wasser_lmin'] as num? ?? 25).toDouble();
    final leitung = _objekte('BW').fold<double>(0, (a, o) => a + o.laenge / 1000);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 10, children: [_zahl('wasser_lmin', 'Verfügbar (Hahn/Pumpe)', verf, einheit: 'l/min')]),
      const SizedBox(height: 8),
      Text('${regner.length} Regner/Tropfer, ${flaechen.length} Gartenflächen (${_z(_flaeche('GA'), 0)} m²), ${_z(leitung)} m Bewässerungsleitung.'),
      Text('Abdeckung der Gartenflächen: ${(ab * 100).round()} %', style: TextStyle(fontWeight: FontWeight.w600, color: ab >= 0.9 ? const Color(0xFF2F9E44) : const Color(0xFFE67700))),
      _h([
        ...bewaesserungZonen(regner, verfuegbarLmin: verf),
        'Regner: Radius im Feld radius_mm, Durchfluss l_min, Zone über Feld ventil (Name des Ventils). Head-to-Head: Regner so setzen, dass jeder den nächsten erreicht.',
        'Leitungen frostsicher entleerbar (Gefälle zum Entleerungsventil), PE-Rohr 25/32 mm, Ventilbox zugänglich; Steuerung z. B. über Home Assistant mit Regensensor.',
      ]),
    ]);
  }

  Widget _licht() {
    final store = _s.store!;
    final leuchten = [
      for (final k in const ['AE', 'PO', 'EB'])
        for (final o in _objekte(k))
          if (o.punkte.isNotEmpty) (o.punkte.first, lichtRadius(k, hoehe: (o.z ?? (k == 'PO' ? 800 : 2200)).toDouble())),
    ];
    final wege = [for (final o in _objekte('WG')) o.punkte];
    final aus = wegAusleuchtung(wege, leuchten);
    final steckdosen = _objekte('AS');
    final ohneKreis = steckdosen.where((o) => o.eigenschaften['stromkreis'] == null).length;
    final bm = store.alleObjekte().any((o) => o.eigenschaften['bewegungsmelder'] == true) || _objekte('AE').any((o) => o.eigenschaften['melder'] == true);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${leuchten.length} Außenleuchten, ${wege.length} Wege/Terrassen – ausgeleuchtet: ${(aus * 100).round()} %',
          style: TextStyle(fontWeight: FontWeight.w600, color: aus >= 0.6 ? const Color(0xFF2F9E44) : const Color(0xFFE67700))),
      Text('${steckdosen.length} Außensteckdosen${ohneKreis > 0 ? ', $ohneKreis ohne Stromkreis' : ''}'),
      _h([
        ...aussenlichtHinweise(leuchten: leuchten.length, bewegungsmelder: bm, ausleuchtung: aus),
        'Außensteckdosen: IP44 (mit Klappdeckel), RCD 30 mA, eigener Außenstromkreis, von innen abschaltbar; an Terrasse, Garten, Zufahrt, Mülltonnen.',
      ]),
    ]);
  }

  Widget _kabel() {
    final ek = _objekte('EK'), ak = _objekte('AK');
    final lEk = ek.fold<double>(0, (a, o) => a + o.laenge / 1000), lAk = ak.fold<double>(0, (a, o) => a + o.laenge / 1000);
    final befahren = _e['befahren'] == true;
    final kabelTypen = {for (final o in [...ek, ...ak]) '${o.eigenschaften['kabel'] ?? 'NYY-J 3x1,5'}'};
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('Erdkabel ${_z(lEk)} m, Kabel auf Putz außen ${_z(lAk)} m (Typen „Erdkabel“ und „Außenkabel auf Putz“, Kabel im Feld kabel).')),
        FilterChip(label: const Text('Trasse unter Zufahrt'), selected: befahren, onSelected: (b) => _setzen('befahren', b ? true : null)),
      ]),
      if (lEk > 0) ...[const SizedBox(height: 8), const Text('Erdkabel', style: TextStyle(fontWeight: FontWeight.w700)), _liste(erdkabelMengen(lEk, befahren: befahren))],
      if (lAk > 0) ...[const SizedBox(height: 8), const Text('Auf Putz außen', style: TextStyle(fontWeight: FontWeight.w700)), _liste(aufputzAussenMengen(lAk))],
      _h([
        for (final k in kabelTypen) ...aussenKabelHinweise(k, erdverlegt: lEk > 0),
        if (kabelTypen.isEmpty) 'Noch keine Außenkabel gezeichnet. Erdkabel mit Typ „Erdkabel“, Leitungen an der Fassade mit „Außenkabel auf Putz“.',
        'Die Längen laufen in die Kabel-/Rohrliste (Kabel plus Schutzrohr).',
      ]),
    ]);
  }
}

/// Felder für Außenobjekte im Objektpanel (Kabeltyp, Regner, Leistung).
Map<String, Object?> aussenStandard(String kuerzel) => switch (kuerzel) {
      'EK' => {'kabel': 'NYY-J 3x2,5'},
      'AK' => {'kabel': 'NYY-J 3x1,5'},
      'RE' => {'radius_mm': 4000, 'l_min': 8},
      'AE' || 'PO' => {'ip': 'IP44', 'kelvin': 2700},
      'EB' => {'ip': 'IP67'},
      'AS' => {'ip': 'IP44'},
      _ => const {},
    };

String aussenJson(Map<String, dynamic> e) => jsonEncode(e);
