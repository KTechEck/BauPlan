import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../core/waermebruecke.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets.dart';
import '../bauteile/profil_editor.dart' show profilLesen;

/// Fenster-/Türeinbau im Detail: Einbaulage in der Wand, Anschlussfuge,
/// Laibungsdämmung, Rollladen – mit 2D-Wärmebrückenberechnung (Ψ, fRsi).
class EinbaudetailPage extends StatefulWidget {
  const EinbaudetailPage({super.key, required this.state, required this.oeffnungId, required this.wand});
  final AppState state;
  final String oeffnungId;
  final Wand wand;

  @override
  State<EinbaudetailPage> createState() => _EinbaudetailPageState();
}

class _EinbaudetailPageState extends State<EinbaudetailPage> {
  WbErgebnis? _ergebnis;
  EinbauDetail? _gerechnetFuer;
  bool _rechnet = false;
  String? _fehler;

  AppState get _s => widget.state;

  Oeffnung? get _oeffnung => _s.store!.alleOeffnungen().where((o) => o.id == widget.oeffnungId).firstOrNull;

  Map<String, dynamic> get _einbau => Map<String, dynamic>.from(_oeffnung?.eigenschaften['einbau'] as Map? ?? const {});

  void _einbauSetzen(Map<String, dynamic> neu) {
    final o = _oeffnung;
    if (o == null) return;
    _s.store!.oeffnungAendern(o.id, {
      'eigenschaften': jsonEncode({...o.eigenschaften, 'einbau': {..._einbau, ...neu}}),
    });
    _s.geaendert();
    setState(() {});
  }

  /// Wandschichten von außen nach innen mit λ.
  (List<WbSchicht>, String?) _schichten() {
    final store = _s.store!;
    final typ = widget.wand.wandtypId == null ? null : store.wandtyp(widget.wand.wandtypId!);
    if (typ == null || typ.schichten.isEmpty) {
      return ([WbSchicht('Mauerwerk', widget.wand.dicke, 0.6)], 'Die Wand hat keinen Wandtyp – gerechnet wird mit einer Schicht λ = 0,6.');
    }
    final mat = {for (final m in store.materialien()) m.id: m};
    var l = [
      for (final s in typ.schichten)
        WbSchicht(
          mat[s.materialId]?.name ?? '?',
          s.dicke,
          (mat[s.materialId]?.eigenschaften['lambda'] as num?)?.toDouble() ?? lambdaVorschlag(mat[s.materialId]?.name ?? '', mat[s.materialId]?.kategorie ?? ''),
        ),
    ];
    if (_einbau['aussen_letzte'] == true) l = l.reversed.toList();
    return (l, null);
  }

  EinbauDetail _detail() {
    final store = _s.store!;
    final o = _oeffnung!;
    final e = _einbau;
    final fenster = _s.bibliothek.fuerProjekt(store, o.eigenschaften['bauelement'] as String?);
    double z(String k, double v) => fenster?.zahl(k)?.toDouble() ?? v;
    final (schichten, _) = _schichten();
    final dicke = schichten.fold<int>(0, (s, x) => s + x.dicke);
    final bautiefe = z('bautiefe', o.art == OeffnungsArt.tuer ? 90 : 82).round();
    int ganz(String k, int v) => (e[k] as num?)?.toInt() ?? v;
    // Vorgabe: Rahmen mittig in der tragenden Schicht bzw. außen bündig zur Dämmung
    // Vorgabe: Rahmen außen bündig mit der tragenden Schicht hinter einer Außendämmung, sonst mittig
    var aussenDaemmung = 0;
    var lauf = 0;
    for (final s in schichten) {
      if (s.lambda < 0.06) aussenDaemmung = lauf + s.dicke;
      lauf += s.dicke;
      if (lauf > dicke / 2) break;
    }
    return EinbauDetail(
      schichten: schichten,
      rahmenBautiefe: bautiefe,
      rahmenBreite: z('ansichtsbreite', 117).round(),
      uf: z('uf', o.art == OeffnungsArt.tuer ? (fenster?.zahl('ud')?.toDouble() ?? 1.3) : 1.0),
      ug: z('ug', o.art == OeffnungsArt.tuer ? (fenster?.zahl('ud')?.toDouble() ?? 1.3) : 0.6),
      glasdicke: z('glasdicke', 44).round(),
      einbaulage: ganz('einbaulage', math.max(0, math.min(dicke - bautiefe, aussenDaemmung > 0 ? aussenDaemmung : (dicke - bautiefe) ~/ 2))),
      fuge: ganz('fuge', 10),
      laibungDaemmung: ganz('laibung', 0),
      laibungLambda: (e['laibung_lambda'] as num?)?.toDouble() ?? 0.035,
      fugeLambda: (e['fuge_lambda'] as num?)?.toDouble() ?? 0.035,
      innenLaibungDaemmung: ganz('innenlaibung', 0),
      innenLaibungLambda: (e['innenlaibung_lambda'] as num?)?.toDouble() ?? 0.06,
    );
  }

  Future<void> _rechnen() async {
    final d = _detail();
    setState(() {
      _rechnet = true;
      _fehler = null;
    });
    try {
      final r = await Isolate.run(_aufgabe(d));
      if (!mounted) return;
      setState(() {
        _ergebnis = r;
        _gerechnetFuer = d;
      });
      _einbauSetzen({
        'einbaulage': d.einbaulage,
        'laibung': d.laibungDaemmung,
        'psi': double.parse(r.psi.toStringAsFixed(4)),
        'f_rsi': double.parse(r.fRsi.toStringAsFixed(3)),
        'theta_si_min': double.parse(r.thetaSiMin.toStringAsFixed(2)),
      });
    } catch (e) {
      setState(() => _fehler = '$e');
    } finally {
      if (mounted) setState(() => _rechnet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _oeffnung;
    if (o == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Öffnung nicht mehr vorhanden.')));
    final store = _s.store!;
    final e = _einbau;
    final d = _detail();
    final (_, schichtHinweis) = _schichten();
    final fenster = _s.bibliothek.fuerProjekt(store, o.eigenschaften['bauelement'] as String?);
    final rollladen = _s.bibliothek.fuerProjekt(store, o.eigenschaften['sonnenschutz'] as String?);
    final r = _ergebnis;
    final veraltet = r != null && _gerechnetFuer != null && jsonEncode(_kennung(_gerechnetFuer!)) != jsonEncode(_kennung(d));

    Widget zahl(String label, String schluessel, num wert, {String einheit = 'mm', String? hilfe, bool komma = false}) => SizedBox(
          width: 220,
          child: SpeicherFeld(
            key: ValueKey('ein-$schluessel-$wert'),
            initialValue: komma ? '$wert'.replaceAll('.', ',') : '$wert',
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(komma ? r'[0-9,.]' : r'[0-9]'))],
            decoration: InputDecoration(labelText: label, suffixText: einheit, helperText: hilfe),
            onFieldSubmitted: (v) {
              final n = num.tryParse(v.replaceAll(',', '.'));
              if (n != null) _einbauSetzen({schluessel: n});
            },
          ),
        );

    return Scaffold(
      backgroundColor: BsFarben.flaeche,
      appBar: AppBar(title: Text('Einbaudetail ${o.art.label} ${mmText(o.breite)} × ${mmText(o.hoehe)}')),
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 380,
          child: Material(
            color: Colors.white,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(fenster?.anzeige ?? 'Kein ${o.art.label} aus der Bibliothek gewählt', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                fenster == null
                    ? 'Gerechnet wird mit Uf 1,0 / Ug 0,6 und 82 mm Bautiefe. Im Grundriss bei der Öffnung ein Produkt wählen.'
                    : fenster.kurzdaten,
                style: const TextStyle(fontSize: 12, color: BsFarben.textLeise),
              ),
              if (rollladen != null) ...[
                const SizedBox(height: 6),
                Text('Sonnenschutz: ${rollladen.anzeige}', style: const TextStyle(fontSize: 12)),
                Text(rollladen.kurzdaten, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              ],
              const Divider(height: 24),
              Text('Wand (außen → innen)', style: Theme.of(context).textTheme.titleSmall),
              for (final s in d.schichten) Text('${s.dicke} mm  ${s.name}  λ ${s.lambda.toStringAsFixed(3).replaceAll('.', ',')}', style: const TextStyle(fontSize: 12)),
              Text('U Wand ${d.uWand.toStringAsFixed(2).replaceAll('.', ',')} W/(m²K)', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              if (schichtHinweis != null) Text(schichtHinweis, style: const TextStyle(fontSize: 12, color: Color(0xFFE67700))),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Außenseite ist die letzte Schicht des Wandtyps'),
                value: e['aussen_letzte'] == true,
                onChanged: (v) => _einbauSetzen({'aussen_letzte': v == true}),
              ),
              const Text('λ der Baustoffe: Bauteile → Bauphysik bzw. Bibliothek → Baustoffe; ohne Angabe gelten Richtwerte.',
                  style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
              const Divider(height: 24),
              Text('Einbau', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 10, children: [
                zahl('Einbaulage', 'einbaulage', d.einbaulage, hilfe: 'Außenkante Rahmen ab Wandaußenseite'),
                zahl('Fuge Rahmen–Laibung', 'fuge', d.fuge, hilfe: 'Kompriband, PU-Schaum oder Dämmstoff'),
                zahl('Laibungsdämmung außen', 'laibung', d.laibungDaemmung, hilfe: 'Dicke auf der äußeren Laibung'),
                zahl('λ Laibungsdämmung', 'laibung_lambda', d.laibungLambda, einheit: 'W/(mK)', komma: true),
                zahl('Dämmung innere Laibung', 'innenlaibung', d.innenLaibungDaemmung, hilfe: 'z. B. Kalziumsilikat, λ 0,06'),
                zahl('λ innere Laibung', 'innenlaibung_lambda', d.innenLaibungLambda, einheit: 'W/(mK)', komma: true),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                key: ValueKey('laib-mat-${e['laibung_material']}'),
                isExpanded: true,
                initialValue: _s.bibliothek.auswahl(store, BauelementKategorie.daemmstoff).any((x) => x.id == e['laibung_material']) ? e['laibung_material'] as String : null,
                decoration: const InputDecoration(labelText: 'Dämmstoff äußere Laibung (aus der Bibliothek)', helperText: 'übernimmt λ und Dicke – oder oben frei eingeben'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('– frei eingegeben –')),
                  for (final x in _s.bibliothek.auswahl(store, BauelementKategorie.daemmstoff))
                    DropdownMenuItem(value: x.id, child: Text('${x.anzeige} · ${x.kurzdaten}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) {
                  final x = _s.bibliothek.fuerProjekt(store, id);
                  _einbauSetzen({
                    'laibung_material': id,
                    if (x?.zahl('lambda') != null) 'laibung_lambda': x!.zahl('lambda'),
                    if (x?.zahl('dicke') != null) 'laibung': x!.zahl('dicke')!.toInt(),
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                key: ValueKey('ilaib-mat-${e['innenlaibung_material']}'),
                isExpanded: true,
                initialValue: _s.bibliothek.auswahl(store, BauelementKategorie.daemmstoff).any((x) => x.id == e['innenlaibung_material']) ? e['innenlaibung_material'] as String : null,
                decoration: const InputDecoration(labelText: 'Dämmstoff innere Laibung (aus der Bibliothek)', helperText: 'z. B. Kalziumsilikat- oder PIR-Laibungsplatte'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('– frei eingegeben –')),
                  for (final x in _s.bibliothek.auswahl(store, BauelementKategorie.daemmstoff))
                    DropdownMenuItem(value: x.id, child: Text('${x.anzeige} · ${x.kurzdaten}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) {
                  final x = _s.bibliothek.fuerProjekt(store, id);
                  _einbauSetzen({
                    'innenlaibung_material': id,
                    if (x?.zahl('lambda') != null) 'innenlaibung_lambda': x!.zahl('lambda'),
                    if (x?.zahl('dicke') != null) 'innenlaibung': x!.zahl('dicke')!.toInt(),
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                key: ValueKey('fuge-mat-${e['fuge_material']}'),
                isExpanded: true,
                initialValue: [
                  ..._s.bibliothek.auswahl(store, BauelementKategorie.dichtstoff),
                  ..._s.bibliothek.auswahl(store, BauelementKategorie.daemmstoff),
                ].any((x) => x.id == e['fuge_material'])
                    ? e['fuge_material'] as String
                    : null,
                decoration: InputDecoration(
                  labelText: 'Zwischen Rahmen und Laibung (Fuge / Dämmung)',
                  helperText: 'λ ${d.fugeLambda.toStringAsFixed(3).replaceAll('.', ',')} – PU-Schaum dämmt besser (≈ 0,035) als Kompriband (≈ 0,048), '
                      'Kompriband dichtet dafür dauerhaft gegen Schlagregen',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('– PU-Schaum (Vorgabe, λ 0,035) –')),
                  for (final x in [
                    ..._s.bibliothek.auswahl(store, BauelementKategorie.dichtstoff),
                    ..._s.bibliothek.auswahl(store, BauelementKategorie.daemmstoff),
                  ])
                    if (x.zahl('lambda') != null) DropdownMenuItem(value: x.id, child: Text('${x.anzeige} · λ ${x.zahl('lambda').toString().replaceAll('.', ',')}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) {
                  final x = _s.bibliothek.fuerProjekt(store, id);
                  _einbauSetzen({'fuge_material': id, 'fuge_lambda': x?.zahl('lambda') ?? 0.035});
                },
              ),
              const Divider(height: 24),
              Text('Sonnen- und Insektenschutz', style: Theme.of(context).textTheme.titleSmall),
              if (rollladen == null)
                const Text('Kein Rollladen zugeordnet (Grundriss → Öffnung).', style: TextStyle(fontSize: 12, color: BsFarben.textLeise))
              else
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Führungsschiene zeichnen (${rollladen.zahl('fuehrung_breite') ?? 53} × ${rollladen.zahl('fuehrung_tiefe') ?? 22} mm)'),
                  value: e['schiene'] != false,
                  onChanged: (v) => _einbauSetzen({'schiene': v == true}),
                ),
              DropdownButtonFormField<String>(
                key: ValueKey('fg-${e['fliegengitter']}'),
                isExpanded: true,
                initialValue: const ['kein', 'spannrahmen', 'rollo', 'tuer_schiene'].contains(e['fliegengitter']) ? e['fliegengitter'] as String : 'kein',
                decoration: const InputDecoration(labelText: 'Fliegengitter'),
                items: [
                  const DropdownMenuItem(value: 'kein', child: Text('keins')),
                  const DropdownMenuItem(value: 'spannrahmen', child: Text('Spannrahmen außen am Fensterrahmen')),
                  const DropdownMenuItem(value: 'rollo', child: Text('Insektenschutzrollo in der Laibung')),
                  if (rollladen != null)
                    const DropdownMenuItem(value: 'tuer_schiene', child: Text('Insektenschutztür in verbreiterter Rollladenschiene (hinter dem Panzer)')),
                ],
                onChanged: (v) => _einbauSetzen({'fliegengitter': v}),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _rechnet ? null : _rechnen,
                icon: _rechnet
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.calculate_outlined, size: 18),
                label: Text(_rechnet ? 'Rechne …' : 'Wärmebrücke berechnen'),
              ),
              if (_fehler != null) Text(_fehler!, style: const TextStyle(color: Color(0xFFB91C1C))),
              if (r != null) ...[
                const Divider(height: 28),
                if (veraltet) const Text('Eingaben geändert – bitte neu berechnen.', style: TextStyle(color: Color(0xFFE67700))),
                _wert('Ψ Einbau (Laibung)', '${r.psi.toStringAsFixed(3).replaceAll('.', ',')} W/(mK)'),
                _wert('fRsi (Rsi 0,25)', '${r.fRsi.toStringAsFixed(2).replaceAll('.', ',')}  ${r.schimmelOk ? '≥ 0,70 ✓' : '< 0,70 – Schimmelgefahr'}',
                    farbe: r.schimmelOk ? const Color(0xFF2F9E44) : const Color(0xFFB91C1C)),
                _wert('kälteste Oberfläche innen', '${r.thetaSiMin.toStringAsFixed(1).replaceAll('.', ',')} °C bei −5 °C außen'),
                if (fenster?.zahl('uw') != null)
                  _wert(
                    'Uw eingebaut',
                    '${uwEingebaut(uw: fenster!.zahl('uw')!.toDouble(), breite: o.breite, hoehe: o.hoehe, psi: r.psi, psiKasten: rollladen?.zahl('psi_kasten')?.toDouble()).toStringAsFixed(2).replaceAll('.', ',')} W/(m²K)  (Uw ${fenster.zahl('uw')!.toString().replaceAll('.', ',')})',
                  ),
                const SizedBox(height: 12),
                Text('Bewertung und Vorschläge', style: Theme.of(context).textTheme.titleSmall),
                for (final rat in waermebrueckeBeratung(_gerechnetFuer ?? d, r))
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: switch (rat.stufe) {
                      0 => const Color(0xFFEBFBEE),
                      1 => const Color(0xFFFFF9DB),
                      _ => const Color(0xFFFFF5F5),
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(
                            switch (rat.stufe) {
                              0 => Icons.check_circle_outline,
                              1 => Icons.lightbulb_outline,
                              _ => Icons.warning_amber,
                            },
                            size: 18,
                            color: switch (rat.stufe) {
                              0 => const Color(0xFF2F9E44),
                              1 => const Color(0xFFE67700),
                              _ => const Color(0xFFB91C1C),
                            },
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(rat.titel, style: const TextStyle(fontWeight: FontWeight.w600))),
                        ]),
                        const SizedBox(height: 4),
                        Text(rat.text, style: const TextStyle(fontSize: 12)),
                        if (rat.aenderung != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _rechnet
                                  ? null
                                  : () {
                                      _einbauSetzen({...rat.aenderung!});
                                      _rechnen();
                                    },
                              icon: const Icon(Icons.science_outlined, size: 16),
                              label: Text('Ausprobieren: ${rat.aenderung!.entries.map((e) => '${switch (e.key) {
                                    'laibung' => 'Laibung',
                                    'innenlaibung' => 'Innenlaibung',
                                    'einbaulage' => 'Einbaulage',
                                    'laibung_lambda' => 'λ',
                                    _ => e.key,
                                  }} ${e.value.toString().replaceAll('.', ',')}${e.key == 'laibung_lambda' ? '' : ' mm'}').join(', ')}'),
                            ),
                          ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Was bedeuten die Werte?'),
                  children: [
                    for (final (t, text) in wbErklaerungen)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(text, style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                    'Näherung nach DIN EN ISO 10211: Horizontalschnitt durch die Laibung, Rahmen und Glas als Ersatzschichten aus Uf/Ug, '
                    'θi 20 °C, θe −5 °C. Brüstung und Sturz (Rollladenkasten) können abweichen; für den Nachweis GEG/KfW ein Wärmebrückenprogramm nutzen.',
                    style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
              ],
            ]),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: r == null
                ? CustomPaint(painter: _SkizzePainter(d, _zubehoer(rollladen)), child: const SizedBox.expand())
                : CustomPaint(painter: _TemperaturPainter(r, d, _zubehoer(rollladen)), child: const SizedBox.expand()),
          ),
        ),
      ]),
    );
  }

  _Zubehoer _zubehoer(Bauelement? rollladen) {
    final e = _einbau;
    final mitSchiene = rollladen != null && e['schiene'] != false;
    final fg = e['fliegengitter'] as String? ?? 'kein';
    // aufgeweitete Schiene: zweite Kammer hinter dem Panzer für das Fliegengitter
    final kammer = !mitSchiene ? 0.0 : (rollladen.zahl('fliegengitter_tiefe')?.toDouble() ?? (fg == 'tuer_schiene' ? 20.0 : 0.0));
    return _Zubehoer(
      schieneTiefe: mitSchiene ? (rollladen.zahl('fuehrung_tiefe')?.toDouble() ?? 22) + kammer : 0,
      kammer: kammer,
      schieneBreite: mitSchiene ? (rollladen.zahl('fuehrung_breite')?.toDouble() ?? 53) : 0,
      vorbau: (rollladen?.daten['system'] as String? ?? '').startsWith('Vorbau'),
      profil: mitSchiene ? profilLesen(rollladen.daten['profil']) : const [],
      fliegengitter: fg,
    );
  }

  List<num> _kennung(EinbauDetail d) => [d.einbaulage, d.fuge, d.fugeLambda, d.laibungDaemmung, d.laibungLambda, d.innenLaibungDaemmung, d.innenLaibungLambda, d.rahmenBautiefe, d.uf, d.ug, ...d.schichten.map((s) => s.dicke)];

  Widget _wert(String label, String wert, {Color? farbe}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          Text(wert, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: farbe)),
        ]),
      );
}

Color _materialFarbe(WbZelle z, double lambda) => switch (z) {
      WbZelle.rahmen => const Color(0xFFE9ECEF),
      WbZelle.glas => const Color(0xFFD0EBFF),
      WbZelle.fuge => const Color(0xFFFFEC99),
      WbZelle.daemmung => const Color(0xFFFFD8A8),
      WbZelle.wand => lambda < 0.06 ? const Color(0xFFFFE8CC) : (lambda < 0.3 ? const Color(0xFFF1F3F5) : const Color(0xFFCED4DA)),
      _ => Colors.transparent,
    };

/// Rollladen-Führungsschiene und Fliegengitter im Laibungsschnitt (nur Zeichnung,
/// liegen vor der Dämmebene und ändern Ψ kaum).
class _Zubehoer {
  const _Zubehoer({this.schieneTiefe = 0, this.schieneBreite = 0, this.kammer = 0, this.vorbau = false, this.fliegengitter = 'kein', this.profil = const []});

  /// Gezeichnetes Schienenprofil aus der Bibliothek (mm, x = Tiefe, y = Breite), leer = Rechteck.
  final List<List<Offset>> profil;
  final double schieneTiefe, schieneBreite;

  /// Tiefe der Fliegengitter-Kammer (innen, hinter dem Panzer), 0 = einfache Schiene.
  final double kammer;
  final bool vorbau;
  final String fliegengitter;
}

void _zubehoerZeichnen(Canvas canvas, Offset Function(double x, double y) p, EinbauDetail d, _Zubehoer z, double yMin) {
  final e = d.einbaulage.toDouble();
  final rahmenAussen = -(d.fuge + d.rahmenBreite).toDouble();
  final alu = Paint()..color = const Color(0xFF868E96);
  final linie = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = Colors.black87;
  final netz = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const Color(0xFF2F9E44);
  if (z.schieneTiefe > 0) {
    // Schiene in der Laibung: vor dem Rahmen (Aufsatz/Einbau) oder vorne an der Fassade (Vorbau)
    final x1 = z.vorbau ? 10.0 : math.max(0.0, e - 5 - z.schieneTiefe);
    final x2 = x1 + z.schieneTiefe;
    final y2 = -d.laibungDaemmung.toDouble();
    final y1 = y2 - z.schieneBreite;
    final r = Rect.fromPoints(p(x1, y1), p(x2, y2));
    if (z.profil.isEmpty) {
      canvas.drawRect(r, alu);
      canvas.drawRect(r, linie);
    } else {
      // gezeichnetes Profil in die Schienenlage einpassen (x = Tiefe, y = Breite)
      final alle = z.profil.expand((k) => k).toList();
      final px0 = alle.map((q) => q.dx).reduce(math.min), py0 = alle.map((q) => q.dy).reduce(math.min);
      for (final kontur in z.profil) {
        final pfad = Path()..addPolygon([for (final q in kontur) p(x1 + (q.dx - px0), y2 - (q.dy - py0))], true);
        canvas.drawPath(pfad, alu);
        canvas.drawPath(pfad, linie);
      }
    }
    // Trennsteg zwischen Panzer- und Fliegengitterkammer
    if (z.kammer > 0) canvas.drawLine(p(x2 - z.kammer, y1), p(x2 - z.kammer, y2), linie);
    // Panzer (geschlossen) quer durch die Öffnung, in der äußeren Kammer
    final xp = x1 + (z.schieneTiefe - z.kammer) * 0.45;
    final strich = Paint()
      ..strokeWidth = 3
      ..color = const Color(0xFF495057);
    for (var y = y1; y > yMin; y -= 18) {
      canvas.drawLine(p(xp, y), p(xp, math.max(yMin, y - 10)), strich);
    }
    _text(canvas, 'Rollladenschiene', p(x1, y1) + const Offset(-110, -4), groesse: 10);
    if (z.kammer > 0 || z.fliegengitter == 'tuer_schiene') {
      final xf = z.kammer > 0 ? x2 - z.kammer / 2 : x1 + z.schieneTiefe * 0.8;
      canvas.drawLine(p(xf, y1), p(xf, yMin), netz);
      _text(canvas, 'Fliegengitter in der 2. Kammer (hinter dem Panzer)', p(xf, yMin + 30) + const Offset(6, 0), groesse: 10, farbe: const Color(0xFF2F9E44));
    }
  }
  switch (z.fliegengitter) {
    case 'spannrahmen':
      final r = Rect.fromPoints(p(e - 14, rahmenAussen), p(e - 2, rahmenAussen + 30));
      canvas.drawRect(r, Paint()..color = const Color(0xFFB2F2BB));
      canvas.drawRect(r, linie);
      canvas.drawLine(p(e - 8, rahmenAussen), p(e - 8, yMin), netz);
      _text(canvas, 'Spannrahmen', p(e - 8, yMin + 30) + const Offset(6, 0), groesse: 10, farbe: const Color(0xFF2F9E44));
    case 'rollo':
      final y2 = -d.laibungDaemmung.toDouble() - (z.schieneTiefe > 0 ? z.schieneBreite : 0);
      final r = Rect.fromPoints(p(e - 32, y2 - 40), p(e - 4, y2));
      canvas.drawRect(r, Paint()..color = const Color(0xFFB2F2BB));
      canvas.drawRect(r, linie);
      canvas.drawLine(p(e - 18, y2 - 40), p(e - 18, yMin), netz);
      _text(canvas, 'Insektenschutzrollo', p(e - 18, yMin + 30) + const Offset(6, 0), groesse: 10, farbe: const Color(0xFF2F9E44));
  }
}

/// Skizze vor der Berechnung: Schichten, Rahmen, Glas, Dämmung.
class _SkizzePainter extends CustomPainter {
  _SkizzePainter(this.d, this.z);
  final EinbauDetail d;
  final _Zubehoer z;

  @override
  void paint(Canvas canvas, Size size) {
    final yMin = -(d.fuge + d.rahmenBreite + d.glasLaenge).toDouble();
    const yMax = 500.0;
    final m = math.min(size.width / d.wanddicke, size.height / (yMax - yMin)) * 0.9;
    final ox = (size.width - d.wanddicke * m) / 2;
    Offset p(double x, double y) => Offset(ox + x * m, (y - yMin) * m);
    final stift = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black54;
    var x = 0.0;
    for (final s in d.schichten) {
      final r = Rect.fromPoints(p(x, 0), p(x + s.dicke, yMax));
      canvas.drawRect(r, Paint()..color = _materialFarbe(WbZelle.wand, s.lambda));
      canvas.drawRect(r, stift);
      x += s.dicke;
    }
    final e = d.einbaulage.toDouble(), b = d.rahmenBautiefe.toDouble();
    void rect(double x0, double y0, double x1, double y1, WbZelle z) {
      final r = Rect.fromPoints(p(x0, y0), p(x1, y1));
      canvas.drawRect(r, Paint()..color = _materialFarbe(z, 1));
      canvas.drawRect(r, stift);
    }

    rect(e, -d.fuge.toDouble(), e + b, 0, WbZelle.fuge);
    rect(e, -(d.fuge + d.rahmenBreite).toDouble(), e + b, -d.fuge.toDouble(), WbZelle.rahmen);
    final gx = e + b / 2 - d.glasdicke / 2;
    rect(gx, yMin, gx + d.glasdicke, -(d.fuge + d.rahmenBreite).toDouble(), WbZelle.glas);
    if (d.laibungDaemmung > 0) rect(0, -d.laibungDaemmung.toDouble(), e, 0, WbZelle.daemmung);
    if (d.innenLaibungDaemmung > 0) rect(e + b, -d.innenLaibungDaemmung.toDouble(), d.wanddicke.toDouble(), 0, WbZelle.daemmung);
    _zubehoerZeichnen(canvas, p, d, z, yMin);
    _text(canvas, 'außen', p(0, yMin) + const Offset(-50, 4));
    _text(canvas, 'innen', p(d.wanddicke.toDouble(), yMin) + const Offset(8, 4));
    _text(canvas, 'Horizontalschnitt Laibung – „Wärmebrücke berechnen“ zeigt die Temperaturen', const Offset(0, 0));
  }

  @override
  bool shouldRepaint(covariant _SkizzePainter old) => true;
}

void _text(Canvas c, String t, Offset o, {double groesse = 12, Color farbe = Colors.black87}) {
  final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: groesse, color: farbe)), textDirection: TextDirection.ltr)..layout();
  tp.paint(c, o);
}

/// Temperaturfeld mit Materialgrenzen und kältestem Punkt.
class _TemperaturPainter extends CustomPainter {
  _TemperaturPainter(this.r, this.d, this.zubehoer);
  final WbErgebnis r;
  final EinbauDetail d;
  final _Zubehoer zubehoer;

  Color _farbe(double t) {
    final f = ((t - thetaE) / (thetaI - thetaE)).clamp(0.0, 1.0);
    const stufen = [Color(0xFF1C3D99), Color(0xFF1C7ED6), Color(0xFF66D9E8), Color(0xFF8CE99A), Color(0xFFFFE066), Color(0xFFFF922B), Color(0xFFE03131)];
    final pos = f * (stufen.length - 1);
    final i = pos.floor().clamp(0, stufen.length - 2);
    return Color.lerp(stufen[i], stufen[i + 1], pos - i)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final breite = r.nx * r.h, hoehe = math.min(r.ny * r.h, -r.y0 + 600);
    final m = math.min((size.width - 120) / breite, (size.height - 40) / hoehe);
    const ox = 60.0, oy = 20.0;
    final zeilen = (hoehe / r.h).floor();
    final z = r.h * m;
    for (var j = 0; j < math.min(zeilen, r.ny); j++) {
      for (var i = 0; i < r.nx; i++) {
        final a = r.zelle(i, j);
        if (a == WbZelle.aussenluft || a == WbZelle.innenluft) continue;
        canvas.drawRect(Rect.fromLTWH(ox + i * z, oy + j * z, z + 0.5, z + 0.5), Paint()..color = _farbe(r.t(i, j)));
      }
    }
    // Materialgrenzen
    final linie = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1;
    for (var j = 0; j < math.min(zeilen, r.ny); j++) {
      for (var i = 0; i < r.nx; i++) {
        final a = r.zelle(i, j);
        if (i + 1 < r.nx && r.zelle(i + 1, j) != a) canvas.drawLine(Offset(ox + (i + 1) * z, oy + j * z), Offset(ox + (i + 1) * z, oy + (j + 1) * z), linie);
        if (j + 1 < r.ny && j + 1 < zeilen && r.zelle(i, j + 1) != a) canvas.drawLine(Offset(ox + i * z, oy + (j + 1) * z), Offset(ox + (i + 1) * z, oy + (j + 1) * z), linie);
      }
    }
    _zubehoerZeichnen(canvas, (x, y) => Offset(ox + x / r.h * z, oy + (y - r.y0) / r.h * z), d, zubehoer, r.y0);
    // kältester Punkt innen
    final mo = Offset(ox + r.minOrt.$1 / r.h * z, oy + (r.minOrt.$2 - r.y0) / r.h * z);
    canvas.drawCircle(mo, 6, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.black);
    _text(canvas, '${r.thetaSiMin.toStringAsFixed(1)} °C', mo + const Offset(8, -8), groesse: 12);
    _text(canvas, 'außen −5 °C', const Offset(4, oy + 4), groesse: 11);
    _text(canvas, 'innen 20 °C', Offset(ox + breite * m + 6, oy + 4), groesse: 11);
    // Legende
    for (var k = 0; k <= 25; k++) {
      canvas.drawRect(Rect.fromLTWH(size.width - 40, size.height - 30 - k * 8, 14, 8), Paint()..color = _farbe(thetaE + k.toDouble()));
    }
    _text(canvas, '20°', Offset(size.width - 24, size.height - 30 - 25 * 8 - 4), groesse: 10);
    _text(canvas, '−5°', Offset(size.width - 24, size.height - 30), groesse: 10);
  }

  @override
  bool shouldRepaint(covariant _TemperaturPainter old) => old.r != r;
}

/// Rechenaufgabe für den Hintergrund (nimmt nur die Eingaben mit, nicht die Seite).
WbErgebnis Function() _aufgabe(EinbauDetail d) => () => waermebrueckeBerechnen(d);
