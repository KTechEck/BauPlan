import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../core/knx.dart';
import '../../core/schrank.dart';
import '../../core/stromlaufplan.dart';
import '../../core/verdrahtung.dart';
import '../../data/bauelement_bibliothek.dart';
import '../../data/models.dart';
import '../../data/schrank_models.dart';
import '../../state/app_state.dart';
import '../../core/ha_live.dart';
import '../floorplan/floorplan_painter.dart' show abstandZuStrecke;
import '../widgets.dart';
import 'ets_abgleich_page.dart';
import 'ha_live_page.dart';
import 'stromlaufplan_ansicht.dart';

/// Farbe je Geräteart in der Schrankansicht.
Color geraeteFarbe(GeraeteArt a) => switch (a) {
      GeraeteArt.hauptschalter => const Color(0xFFB91C1C),
      GeraeteArt.rcd => const Color(0xFF1C7ED6),
      GeraeteArt.ls => const Color(0xFF495057),
      GeraeteArt.fils => const Color(0xFF7048E8),
      GeraeteArt.spd => const Color(0xFFE67700),
      GeraeteArt.knx => const Color(0xFF2F9E44),
      GeraeteArt.netzteil => const Color(0xFF0C8599),
      GeraeteArt.relais => const Color(0xFF868E96),
      GeraeteArt.klemme => const Color(0xFFADB5BD),
      GeraeteArt.sonstiges => const Color(0xFF868E96),
    };

Color phasenFarbe(String? p) => switch (p) {
      'L1' => const Color(0xFF8B5A2B), // braun
      'L2' => Colors.black,
      'L3' => const Color(0xFF868E96), // grau
      '3P' => const Color(0xFFE67700),
      _ => Colors.transparent,
    };

/// Modul Verteiler: Zähler- und Unterverteiler planen – Geräte auf der
/// Hutschiene, Stromkreise, Übersichtsschaltbild und Beschriftung.
class SchrankPage extends StatefulWidget {
  const SchrankPage({super.key, required this.state});
  final AppState state;

  @override
  State<SchrankPage> createState() => _SchrankPageState();
}

class _SchrankPageState extends State<SchrankPage> {
  String? _schrankId;
  String? _auswahl; // Gerät
  int _ansicht = 0; // 0 Schrank, 1 Stromkreise, 2 Übersichtsschaltbild, 3 Beschriftung
  GeraeteArt? _setzen; // Gerät zum Setzen gewählt
  String? _setzenBauelement; // Gerät aus der Bibliothek
  int _pole = 1;
  final List<VoidCallback> _rueckgaengig = [];
  final _schrankScroll = ScrollController();
  final _doppel = Doppelklick();
  double _schrankZoom = 1;
  double _paletteBreite = 200;
  bool _listeOffen = false, _listeFest = false;
  bool _echt = true; // echte Darstellung (Vorgabe): Gehäuse, Anschlussräume, Seitenraum, Einführungen
  final Set<String> _mehr = {}; // Mehrfachauswahl (Umschalt/Strg-Klick, Rahmen)
  Offset? _rahmenA, _rahmenB;
  final _fokus = FocusNode(debugLabel: 'schrank');
  Offset _schrankPan = Offset.zero;
  Offset? _schrankPanStart;

  void _schrankZoomen(Offset cursor, double f) {
    final neu = (_schrankZoom * f).clamp(0.3, 6.0);
    final faktor = neu / _schrankZoom;
    setState(() {
      _schrankPan = cursor - (cursor - _schrankPan) * faktor;
      _schrankZoom = neu;
    });
  }

  @override
  void dispose() {
    _schrankScroll.dispose();
    super.dispose();
  }
  // Ziehen
  String? _ziehId;
  (int, int)? _ziel;

  AppState get _s => widget.state;

  void _rueck() {
    if (_rueckgaengig.isEmpty) return;
    _rueckgaengig.removeLast()();
    _s.geaendert();
  }

  Future<void> _schrankNeu({Objekt? objekt}) async {
    final store = _s.store!;
    final vorhandene = store.schraenke();
    final name = TextEditingController(text: objekt == null ? 'Unterverteiler ${vorhandene.length + 1}' : 'Verteiler ${objekt.kennung}');
    final kennz = TextEditingController(text: 'UV${vorhandene.length + 1}');
    var art = SchrankArt.unterverteiler;
    var reihen = 4, te = 12;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Schrank anlegen'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                controller: kennz,
                decoration: const InputDecoration(labelText: 'Kennzeichen', helperText: 'Anlage nach DIN EN 81346, z. B. UV1 → =UV1-F3'),
              ),
              DropdownButtonFormField<SchrankArt>(
                initialValue: art,
                decoration: const InputDecoration(labelText: 'Art'),
                items: [for (final a in SchrankArt.values) DropdownMenuItem(value: a, child: Text(a.label))],
                onChanged: (a) => setD(() => art = a ?? art),
              ),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: reihen,
                    decoration: const InputDecoration(labelText: 'Reihen'),
                    items: [for (var i = 1; i <= 8; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => setD(() => reihen = v ?? reihen),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: te,
                    decoration: const InputDecoration(labelText: 'TE je Reihe'),
                    items: [
                      for (final v in const [12, 14, 18, 24]) DropdownMenuItem(value: v, child: Text('$v'))
                    ],
                    onChanged: (v) => setD(() => te = v ?? te),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Anlegen')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final id = store.schrankAnlegen(
      name: name.text.trim(),
      kennzeichen: kennz.text.trim().replaceAll('=', '').toUpperCase(),
      art: art,
      reihen: reihen,
      teJeReihe: te,
      objektId: objekt?.id,
      geschossId: objekt?.geschossId,
    );
    _rueckgaengig.add(() => store.schrankLoeschen(id));
    setState(() => _schrankId = id);
    _s.geaendert();
  }

  /// Gerätepalette direkt neben dem Schrank: anklicken, dann in den Schrank klicken.
  Widget _palette() {
    final store = _s.store!;
    Widget eintrag(String text, Color farbe, bool aktiv, VoidCallback tap) => ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          selected: aktiv,
          selectedTileColor: BsFarben.akzentHell,
          leading: Container(width: 12, height: 12, color: farbe),
          minLeadingWidth: 12,
          title: Text(text, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: tap,
        );
    Widget titel(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 2),
          child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: BsFarben.textLeise)),
        );
    final bib = _s.bibliothek.auswahl(store, BauelementKategorie.schrankgeraet);
    return ListView(children: [
      const Padding(padding: EdgeInsets.fromLTRB(12, 10, 8, 0), child: Text('Gerät setzen', style: TextStyle(fontWeight: FontWeight.w600))),
      for (final (t, arten) in const [
        ('Schutz und Einspeisung', [GeraeteArt.hauptschalter, GeraeteArt.rcd, GeraeteArt.ls, GeraeteArt.fils, GeraeteArt.spd]),
        ('Steuerung', [GeraeteArt.knx, GeraeteArt.netzteil, GeraeteArt.relais]),
        ('Verbindung', [GeraeteArt.klemme, GeraeteArt.sonstiges]),
      ]) ...[
        titel(t),
        for (final a in arten)
          eintrag(a.label, geraeteFarbe(a), _setzenBauelement == null && _setzen == a, () => setState(() {
                _setzenBauelement = null;
                _setzen = _setzen == a ? null : a;
              })),
      ],
      if (bib.isNotEmpty) ...[
        titel('Aus der Bibliothek'),
        for (final e in bib)
          eintrag(e.anzeige, geraeteFarbe(_artAusBauelement(e)), _setzenBauelement == e.id, () => setState(() {
                _setzenBauelement = _setzenBauelement == e.id ? null : e.id;
                _setzen = _setzenBauelement == null ? null : _artAusBauelement(e);
              })),
      ],
    ]);
  }

  GeraeteArt _artAusBauelement(Bauelement e) =>
      GeraeteArt.values.where((a) => a.name == e.daten['geraeteart']).firstOrNull ?? GeraeteArt.sonstiges;

  void _geraetSetzen(Schrank s, List<SchrankGeraet> geraete, int reihe, int position) {
    final art = _setzen;
    if (art == null) return;
    final be = _setzenBauelement == null ? null : _s.bibliothek.fuerProjekt(_s.store!, _setzenBauelement);
    final pole = be?.zahl('pole')?.toInt() ??
        (art == GeraeteArt.ls || art == GeraeteArt.hauptschalter ? _pole : (art == GeraeteArt.rcd ? (_pole == 1 ? 2 : 4) : 1));
    final breite = be?.zahl('te')?.toInt() ?? art.breite(pole);
    var ziel = (reihe, position);
    if (!platzFrei(s, geraete, reihe, position, breite)) {
      final f = freierPlatz(s, geraete, breite, abReihe: reihe, abPosition: position);
      if (f == null) {
        zeigeHinweis(context, 'Kein Platz mehr für $breite TE.');
        return;
      }
      ziel = f;
    }
    final store = _s.store!;
    // LS bekommt den RCD links davon in derselben Reihe als Vorschaltung
    String? vor;
    if (art == GeraeteArt.ls) {
      final rcd = geraete.where((g) => g.art == GeraeteArt.rcd && g.reihe == ziel.$1 && g.position < ziel.$2).toList()
        ..sort((a, b) => b.position.compareTo(a.position));
      vor = rcd.firstOrNull?.id;
    }
    final id = store.geraetAnlegen(
      schrankId: s.id,
      reihe: ziel.$1,
      position: ziel.$2,
      art: art,
      pole: pole,
      breite: breite,
      bezeichnung: be?.anzeige ?? '',
      kennzeichen: naechstesKennzeichen(art, geraete),
      nennstrom: be?.zahl('nennstrom')?.toInt() ?? switch (art) {
        GeraeteArt.ls || GeraeteArt.fils => 16,
        GeraeteArt.rcd => 40,
        GeraeteArt.hauptschalter => 63,
        _ => null,
      },
      charakteristik: be?.daten['charakteristik'] as String? ?? (art == GeraeteArt.ls || art == GeraeteArt.fils ? 'B' : null),
      fehlerstrom: be?.zahl('fehlerstrom')?.toInt() ?? (art == GeraeteArt.rcd || art == GeraeteArt.fils ? 30 : null),
      phase: art == GeraeteArt.ls || art == GeraeteArt.fils ? (pole == 3 ? '3P' : _naechstePhase(geraete)) : null,
      vorgeschaltetId: vor,
    );
    if (be != null) {
      BauelementBibliothek.insProjekt(store, be);
      store.geraetAendern(id, {
        'eigenschaften': jsonEncode({
          'bauelement': be.id,
          for (final k in const ['aktortyp', 'kanaele', 'rcd_typ', 'schaltvermoegen', 'spd_typ', 'verlust', 'busstrom', 'strom_kanal'])
            if (be.daten[k] != null) k: be.daten[k],
        }),
      });
    }
    _rueckgaengig.add(() => store.geraetLoeschen(id));
    setState(() => _auswahl = id);
    _s.geaendert();
  }

  /// Phase für einen neuen LS: die bisher am wenigsten belegte.
  String _naechstePhase(List<SchrankGeraet> geraete) {
    final n = {'L1': 0, 'L2': 0, 'L3': 0};
    for (final g in geraete) {
      if (n.containsKey(g.phase)) n[g.phase!] = n[g.phase!]! + 1;
    }
    return (n.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).first.key;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final store = _s.store!;
        final schraenke = store.schraenke();
        if (_schrankId != null && !schraenke.any((s) => s.id == _schrankId)) _schrankId = null;
        _schrankId ??= schraenke.firstOrNull?.id;
        final s = schraenke.where((x) => x.id == _schrankId).firstOrNull;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _rueck,
            const SingleActivator(LogicalKeyboardKey.delete): () {
              final ids = {..._mehr, if (_auswahl != null) _auswahl!};
              if (ids.isEmpty) return;
              final store = _s.store!;
              for (final id in ids) {
                store.geraetLoeschen(id);
              }
              _rueckgaengig.add(() {
                for (final id in ids) {
                  store.geraetWiederherstellen(id);
                }
              });
              setState(() {
                _auswahl = null;
                _mehr.clear();
              });
              _s.geaendert();
              zeigeHinweis(context, '${ids.length} Gerät(e) gelöscht – Strg+Z holt sie zurück.');
            },
            const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
                  _auswahl = null;
                  _mehr.clear();
                }),
          },
          child: Focus(
            focusNode: _fokus,
            autofocus: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _schrankListe(schraenke),
              const VerticalDivider(width: 1),
              Expanded(
                child: s == null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Noch kein Schrank angelegt.'),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: _schrankNeu, icon: const Icon(Sym.hinzufuegen), label: const Text('Schrank anlegen')),
                        ]),
                      )
                    : _schrankBereich(s),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _schrankListe(List<Schrank> schraenke) {
    final store = _s.store!;
    // Verteiler-Objekte im Grundriss ohne Schrank
    final vtTyp = store.objekttypen().where((t) => t.kuerzel == 'VT').map((t) => t.id).toSet();
    final verknuepft = {for (final s in schraenke) s.objektId};
    final offen = [
      for (final o in store.alleObjekte())
        if (vtTyp.contains(o.typId) && !verknuepft.contains(o.id)) o
    ];
    final offenAnzeigen = _listeOffen || _listeFest || schraenke.isEmpty;
    if (!offenAnzeigen) {
      // eingeklappt: schmale Leiste, klappt beim Darüberfahren auf
      return MouseRegion(
        onEnter: (_) => setState(() => _listeOffen = true),
        child: Material(
          color: Colors.white,
          child: SizedBox(
            width: 44,
            child: Column(children: [
              const SizedBox(height: 10),
              const Icon(Icons.view_list_outlined, color: BsFarben.textLeise),
              const SizedBox(height: 8),
              for (final s in schraenke)
                Tooltip(
                  message: s.name,
                  child: InkWell(
                    onTap: () => setState(() {
                      _schrankId = s.id;
                      _auswahl = null;
                    }),
                    child: Container(
                      width: 40,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      color: s.id == _schrankId ? BsFarben.akzentHell : null,
                      child: Text(s.kennzeichen, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
    }
    return MouseRegion(
      onExit: (_) => setState(() => _listeOffen = false),
      child: Material(
        color: Colors.white,
        child: SizedBox(
          width: 230,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              Expanded(child: Text('Schränke', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: _listeFest ? 'Liste einklappen' : 'Liste offen halten',
                isSelected: _listeFest,
                onPressed: () => setState(() => _listeFest = !_listeFest),
                icon: const Icon(Icons.push_pin_outlined, size: 18),
              ),
            ]),
            const SizedBox(height: 8),
            for (final s in schraenke)
              ListTile(
                dense: true,
                selected: s.id == _schrankId,
                selectedTileColor: BsFarben.akzentHell,
                title: Text(s.name),
                subtitle: Text('=${s.kennzeichen} · ${s.art.label}'),
                onTap: () => setState(() {
                  _schrankId = s.id;
                  _auswahl = null;
                }),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _schrankNeu, icon: const Icon(Sym.hinzufuegen, size: 18), label: const Text('Schrank')),
            if (offen.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Verteiler im Grundriss ohne Schrankplanung:', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              for (final o in offen) TextButton(onPressed: () => _schrankNeu(objekt: o), child: Text('${o.kennung} planen')),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _schrankBereich(Schrank s) {
    final store = _s.store!;
    final geraete = store.schrankGeraete(s.id);
    final kreise = store.stromkreise(s.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Schrank')),
              ButtonSegment(value: 4, label: Text('Verdrahtung')),
              ButtonSegment(value: 1, label: Text('Stromkreise')),
              ButtonSegment(value: 2, label: Text('Übersichtsschaltbild')),
              ButtonSegment(value: 6, label: Text('Stromlaufplan')),
              ButtonSegment(value: 3, label: Text('Beschriftung')),
              ButtonSegment(value: 5, label: Text('KNX / Home Assistant')),
            ],
            selected: {_ansicht},
            onSelectionChanged: (v) => setState(() => _ansicht = v.first),
          ),
          IconButton(tooltip: 'Rückgängig (Strg+Z)', onPressed: _rueckgaengig.isEmpty ? null : _rueck, icon: const Icon(Sym.rueckgaengig)),
          if (_ansicht == 0 || _ansicht == 4)
            FilterChip(
              label: const Text('Echte Darstellung'),
              tooltip: 'Gehäuse mit Anschlussräumen, Platz neben den Hutschienen und Kabeleinführungen maßstäblich',
              selected: _echt,
              onSelected: (v) => setState(() => _echt = v),
            ),
          if (_ansicht == 0) ...[
            if (_setzen != null)
              TextButton(onPressed: () => setState(() {
                    _setzen = null;
                    _setzenBauelement = null;
                  }), child: const Text('Setzen beenden')),
            if (_setzenBauelement == null && (_setzen == GeraeteArt.ls || _setzen == GeraeteArt.hauptschalter || _setzen == GeraeteArt.rcd))
              DropdownButton<int>(
                value: _pole,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1-polig / 2-polig (RCD)')),
                  DropdownMenuItem(value: 3, child: Text('3-polig / 4-polig (RCD)')),
                ],
                onChanged: (v) => setState(() => _pole = v ?? 1),
              ),
          ],
          if (_ansicht == 1)
            FilledButton.icon(
              onPressed: () {
                final id = store.stromkreisAnlegen(schrankId: s.id, nummer: '${kreise.length + 1}');
                _rueckgaengig.add(() => store.stromkreisLoeschen(id));
                _s.geaendert();
              },
              icon: const Icon(Sym.hinzufuegen),
              label: const Text('Stromkreis'),
            ),
          if (_ansicht == 6)
            FilledButton.icon(
              onPressed: () => _stromlaufplanPdf(s, geraete, kreise),
              icon: const Icon(Sym.pdf),
              label: const Text('Als PDF (A3)'),
            ),
          if (_ansicht == 3)
            FilledButton.icon(
              onPressed: () => _beschriftungPdf(s, geraete, kreise),
              icon: const Icon(Sym.pdf),
              label: const Text('Als PDF (1:1 zum Ausdrucken)'),
            ),
        ]),
      ),
      Expanded(
        child: switch (_ansicht) {
          0 => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: _paletteBreite, child: Material(color: Colors.white, child: _palette())),
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) => setState(() => _paletteBreite = (_paletteBreite + d.delta.dx).clamp(120.0, 420.0)),
                  child: Container(width: 6, color: BsFarben.rand),
                ),
              ),
              Expanded(child: _schrankAnsicht(s, geraete, kreise)),
              SizedBox(
                width: 320,
                child: Material(color: Colors.white, child: _rechts(s, geraete, kreise)),
              ),
            ]),
          1 => _stromkreisListe(s, geraete, kreise),
          2 => _uebersicht(s, geraete, kreise),
          3 => _beschriftungVorschau(s, geraete, kreise),
          5 => _knxAnsicht(),
          6 => StromlaufplanAnsicht(key: ValueKey('slp-${s.id}'), plan: _stromlaufplan(s, geraete, kreise)),
          _ => _verdrahtungAnsicht(s, geraete, kreise),
        },
      ),
    ]);
  }

  // ------------------------------------------------------- Schrankansicht

  Widget _schrankAnsicht(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
    return LayoutBuilder(builder: (context, c) {
      final te = math.min(44.0, math.max(16.0, (c.maxWidth - 80) / s.teJeReihe));
      final reiheH = te * 4.2;
      final aufbau = SchrankAufbau.aus(s.eigenschaften);
      final mmPx = te / 17.5;
      final links = 40.0 + (_echt ? aufbau.seite * mmPx : 0), oben = 30.0 + (_echt ? aufbau.raumOben * mmPx : 0);
      (int, int)? platz(Offset l) {
        final r = ((l.dy - oben) / (reiheH + 18)).floor();
        final pos = ((l.dx - links) / te).floor();
        if (r < 0 || r >= s.reihen || pos < 0 || pos >= s.teJeReihe) return null;
        return (r, pos);
      }

      SchrankGeraet? treffer(Offset l) {
        final pl = platz(l);
        if (pl == null) return null;
        return geraete.where((g) => g.reihe == pl.$1 && pl.$2 >= g.position && pl.$2 < g.ende).firstOrNull;
      }

      final hoehe = oben + s.reihen * (reiheH + 18) + 40 + (_ansicht == 4 ? _SchrankPainter.raumHoehe + 30 : 0) + (_echt ? aufbau.raumUnten * mmPx : 0);
      final breite = math.max(c.maxWidth, links + s.teJeReihe * te + 80 + (_echt ? aufbau.seite * mmPx : 0));
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) _schrankZoomen(e.localPosition, e.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12);
        },
        onPointerDown: (e) {
          if (e.buttons == kMiddleMouseButton || e.buttons == kSecondaryMouseButton) _schrankPanStart = e.localPosition;
        },
        onPointerMove: (e) {
          final p = _schrankPanStart;
          if (p == null) return;
          setState(() {
            _schrankPan += e.localPosition - p;
            _schrankPanStart = e.localPosition;
          });
        },
        onPointerUp: (_) => _schrankPanStart = null,
        child: ClipRect(
        child: Transform(
        transform: Matrix4.identity()
          ..setEntry(0, 0, _schrankZoom)
          ..setEntry(1, 1, _schrankZoom)
          ..setEntry(0, 3, _schrankPan.dx)
          ..setEntry(1, 3, _schrankPan.dy),
        child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Listener(
        onPointerDown: (e) {
          _fokus.requestFocus();
          if (e.buttons != kPrimaryMouseButton) return;
          final g = treffer(e.localPosition);
          final zusatz = HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isControlPressed;
          if (g != null && _doppel.erkannt(e.localPosition)) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _eigenschaftenDialog(s, g, geraete, kreise));
          }
          if (g != null) {
            setState(() {
              if (zusatz) {
                if (_auswahl != null) _mehr.add(_auswahl!);
                if (!_mehr.remove(g.id)) _mehr.add(g.id);
              } else if (!_mehr.contains(g.id)) {
                _mehr.clear();
              }
              _auswahl = g.id;
              _ziehId = zusatz ? null : g.id;
              _ziel = null;
            });
            return;
          }
          final pl = platz(e.localPosition);
          if (pl != null && _setzen != null) {
            _geraetSetzen(s, geraete, pl.$1, pl.$2);
          } else {
            setState(() {
              _auswahl = null;
              if (!zusatz) _mehr.clear();
              _rahmenA = e.localPosition;
              _rahmenB = e.localPosition;
            });
          }
        },
        onPointerMove: (e) {
          if (_rahmenA != null) {
            setState(() => _rahmenB = e.localPosition);
            return;
          }
          final id = _ziehId;
          if (id == null) return;
          final pl = platz(e.localPosition);
          setState(() => _ziel = pl);
        },
        onPointerUp: (_) {
          final ra = _rahmenA, rb = _rahmenB;
          if (ra != null) {
            final r = Rect.fromPoints(ra, rb ?? ra);
            setState(() {
              _rahmenA = null;
              _rahmenB = null;
              if (r.width > 4 || r.height > 4) {
                for (final g in geraete) {
                  final gr = Rect.fromLTWH(links + g.position * te, oben + g.reihe * (reiheH + 18), g.breite * te, reiheH);
                  if (r.overlaps(gr)) _mehr.add(g.id);
                }
                if (_mehr.isNotEmpty) _auswahl ??= _mehr.first;
              }
            });
            return;
          }
          final id = _ziehId, z = _ziel;
          setState(() {
            _ziehId = null;
            _ziel = null;
          });
          if (id == null || z == null) return;
          final g = geraete.firstWhere((x) => x.id == id);
          if (g.reihe == z.$1 && g.position == z.$2) return;
          if (!platzFrei(s, geraete, z.$1, z.$2, g.breite, ausser: id)) {
            zeigeHinweis(context, 'Dort ist kein Platz für ${g.breite} TE.');
            return;
          }
          final store = _s.store!;
          final alt = store.geraetAendern(id, {'reihe': z.$1, 'position': z.$2});
          _rueckgaengig.add(() => store.geraetAendern(id, alt));
          _s.geaendert();
        },
        child: CustomPaint(
          size: Size(breite, math.max(hoehe, c.maxHeight)),
          painter: _SchrankPainter(
            schrank: s,
            geraete: geraete,
            kreise: kreise,
            te: te,
            reiheH: reiheH,
            links: links,
            oben: oben,
            auswahl: _auswahl,
            ziehen: _ziehId == null || _ziel == null ? null : (_ziehId!, _ziel!),
            schienen: kammschienen(s),
            draehte: _ansicht == 4 ? _gefiltert(verdrahtung(s, geraete, kreise), geraete) : const [],
            anschlussraum: _ansicht == 4,
            mehr: _mehr,
            rahmen: _rahmenA == null || _rahmenB == null ? null : Rect.fromPoints(_rahmenA!, _rahmenB!),
            aufbau: _echt ? aufbau : null,
            mmPx: mmPx,
          ),
        ),
      )))));
    });
  }

  /// Eigenschaften eines Geräts im Dialog (Doppelklick).
  Future<void> _eigenschaftenDialog(Schrank s, SchrankGeraet g, List<SchrankGeraet> geraete, List<Stromkreis> kreise) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 420,
          height: 640,
          child: ListenableBuilder(
            listenable: _s,
            builder: (context, _) {
              final store = _s.store!;
              final akt = store.schrankGeraete(s.id).where((x) => x.id == g.id).firstOrNull;
              if (akt == null) return const Center(child: Text('Gerät gelöscht.'));
              return Material(color: Colors.white, child: _geraetInfo(s, akt, store.schrankGeraete(s.id), store.stromkreise(s.id)));
            },
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _rechts(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
    final g = geraete.where((x) => x.id == _auswahl).firstOrNull;
    return g == null ? _schrankInfo(s, geraete, kreise) : _geraetInfo(s, g, geraete, kreise);
  }

  Widget _schrankInfo(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
    final store = _s.store!;
    final b = belegung(s, geraete);
    final last = phasenLast(kreise, geraete);
    final maxLast = math.max(1, last.values.fold<int>(0, math.max));
    final hinweise = schrankHinweise(s, geraete, kreise);
    void aendern(Map<String, Object?> f) {
      final alt = store.schrankAendern(s.id, f);
      _rueckgaengig.add(() => store.schrankAendern(s.id, alt));
      _s.geaendert();
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(s.art.label, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      SpeicherFeld(
        key: ValueKey('sn-${s.id}-${s.name}'),
        initialValue: s.name,
        style: Theme.of(context).textTheme.titleLarge,
        decoration: const InputDecoration(border: InputBorder.none),
        onFieldSubmitted: (v) => v.trim().isEmpty ? null : aendern({'name': v.trim()}),
      ),
      SpeicherFeld(
        key: ValueKey('sk-${s.id}-${s.kennzeichen}'),
        initialValue: s.kennzeichen,
        decoration: const InputDecoration(labelText: 'Kennzeichen (=…)'),
        onFieldSubmitted: (v) => v.trim().isEmpty ? null : aendern({'kennzeichen': v.trim().replaceAll('=', '').toUpperCase()}),
      ),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('sr-${s.id}-${s.reihen}'),
            initialValue: s.reihen,
            decoration: const InputDecoration(labelText: 'Reihen'),
            items: [for (var i = 1; i <= 8; i++) DropdownMenuItem(value: i, child: Text('$i'))],
            onChanged: (v) => aendern({'reihen': v}),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('st-${s.id}-${s.teJeReihe}'),
            initialValue: s.teJeReihe,
            decoration: const InputDecoration(labelText: 'TE je Reihe'),
            items: [
              for (final v in {12, 14, 18, 24, s.teJeReihe}) DropdownMenuItem(value: v, child: Text('$v'))
            ],
            onChanged: (v) => aendern({'te_je_reihe': v}),
          ),
        ),
      ]),
      ..._aussenmasse(s, aendern),
      if (s.art == SchrankArt.netzwerk) ..._patchfeld(s),
      const SizedBox(height: 16),
      Text('Belegung', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      LinearProgressIndicator(value: b.gesamt == 0 ? 0 : b.belegt / b.gesamt, minHeight: 8),
      const SizedBox(height: 4),
      Text('${b.belegt} von ${b.gesamt} TE belegt · Reserve ${(b.reserve * 100).round()} %'),
      const SizedBox(height: 16),
      Text('Last je Phase (geschätzt aus den Stromkreisen)', style: Theme.of(context).textTheme.titleSmall),
      for (final e in last.entries)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            SizedBox(width: 26, child: Text(e.key)),
            Expanded(child: LinearProgressIndicator(value: e.value / maxLast, minHeight: 8, color: phasenFarbe(e.key))),
            SizedBox(width: 72, child: Text('${(e.value / 1000).toStringAsFixed(1).replaceAll('.', ',')} kW', textAlign: TextAlign.right)),
          ]),
        ),
      const SizedBox(height: 16),
      Text('Hinweise', style: Theme.of(context).textTheme.titleSmall),
      if (hinweise.isEmpty) const Text('Keine Auffälligkeiten.', style: TextStyle(color: BsFarben.textLeise)),
      for (final h in hinweise)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('• $h', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
        ),
      const SizedBox(height: 6),
      const Text('Nur Hinweise – Auslegung und Abnahme durch eine Elektrofachkraft.',
          style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
      const SizedBox(height: 16),
      const Text('Gerät oben wählen und in einen freien Platz klicken; Geräte lassen sich ziehen.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () {
          store.schrankLoeschen(s.id);
          _rueckgaengig.add(() => store.schrankWiederherstellen(s.id));
          _s.geaendert();
        },
        icon: const Icon(Sym.loeschen),
        label: const Text('Schrank löschen'),
      ),
    ]);
  }

  Widget _geraetInfo(Schrank s, SchrankGeraet g, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
    final store = _s.store!;
    void aendern(Map<String, Object?> f) {
      final alt = store.geraetAendern(g.id, f);
      _rueckgaengig.add(() => store.geraetAendern(g.id, alt));
      _s.geaendert();
    }

    final schutz = g.art == GeraeteArt.ls || g.art == GeraeteArt.fils;
    final rcds = [
      for (final x in geraete)
        if (x.art == GeraeteArt.rcd) x
    ];
    final meineKreise = [
      for (final k in kreise)
        if (k.schutzId == g.id) k
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Container(width: 12, height: 12, color: geraeteFarbe(g.art)),
        const SizedBox(width: 6),
        Text(g.art.label, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      ]),
      Text(betriebsmittel(s, g), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      Text('Reihe ${g.reihe + 1}, TE ${g.position + 1}–${g.ende} (${g.breite} TE)', style: const TextStyle(color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      SpeicherFeld(
        key: ValueKey('gk-${g.id}-${g.kennzeichen}'),
        initialValue: g.kennzeichen,
        decoration: const InputDecoration(labelText: 'Kennzeichen'),
        onFieldSubmitted: (v) => v.trim().isEmpty ? null : aendern({'kennzeichen': v.trim().startsWith('-') ? v.trim() : '-${v.trim()}'}),
      ),
      SpeicherFeld(
        key: ValueKey('gb-${g.id}-${g.bezeichnung}'),
        initialValue: g.bezeichnung,
        decoration: const InputDecoration(labelText: 'Bezeichnung'),
        onFieldSubmitted: (v) => aendern({'bezeichnung': v.trim()}),
      ),
      DropdownButtonFormField<String?>(
        key: ValueKey('gbe-${g.id}-${g.eigenschaften['bauelement']}'),
        isExpanded: true,
        initialValue: _s.bibliothek.auswahl(store, BauelementKategorie.schrankgeraet).any((e) => e.id == g.eigenschaften['bauelement'])
            ? g.eigenschaften['bauelement'] as String
            : null,
        decoration: const InputDecoration(labelText: 'Produkt aus der Bibliothek', helperText: 'übernimmt Breite, Nennstrom und Daten'),
        items: [
          const DropdownMenuItem(value: null, child: Text('– ohne –')),
          for (final e in _s.bibliothek.auswahl(store, BauelementKategorie.schrankgeraet))
            if (_artAusBauelement(e) == g.art) DropdownMenuItem(value: e.id, child: Text(e.anzeige, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (id) {
          final be = _s.bibliothek.fuerProjekt(store, id);
          final eig = {...g.eigenschaften}..remove('bauelement');
          final f = <String, Object?>{};
          if (be != null) {
            BauelementBibliothek.insProjekt(store, be);
            eig['bauelement'] = be.id;
            for (final k in const ['aktortyp', 'kanaele', 'rcd_typ', 'schaltvermoegen', 'spd_typ', 'verlust', 'busstrom', 'strom_kanal']) {
              if (be.daten[k] != null) eig[k] = be.daten[k];
            }
            final te = be.zahl('te')?.toInt();
            if (te != null && platzFrei(s, geraete, g.reihe, g.position, te, ausser: g.id)) f['breite'] = te;
            if (be.zahl('pole') != null) f['pole'] = be.zahl('pole')!.toInt();
            if (be.zahl('nennstrom') != null) f['nennstrom'] = be.zahl('nennstrom')!.toInt();
            if (be.daten['charakteristik'] is String) f['charakteristik'] = be.daten['charakteristik'];
            if (be.zahl('fehlerstrom') != null) f['fehlerstrom'] = be.zahl('fehlerstrom')!.toInt();
            if (g.bezeichnung.isEmpty) f['bezeichnung'] = be.anzeige;
          }
          f['eigenschaften'] = jsonEncode(eig);
          aendern(f);
        },
      ),
      Row(children: [
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('gte-${g.id}-${g.breite}'),
            initialValue: '${g.breite}',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Breite', suffixText: 'TE'),
            pruefen: (v) {
              final te = int.tryParse(v);
              if (te == null || te < 1) return 'mindestens 1 TE';
              if (!platzFrei(s, geraete, g.reihe, g.position, te, ausser: g.id)) return 'kein Platz für $te TE';
              return null;
            },
            onFieldSubmitted: (v) => aendern({'breite': int.parse(v)}),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('gpo-${g.id}-${g.pole}'),
            initialValue: '${g.pole}',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Pole'),
            onFieldSubmitted: (v) => int.tryParse(v) == null ? null : aendern({'pole': int.parse(v)}),
          ),
        ),
      ]),
      if (g.art.istSchutz || g.art == GeraeteArt.fils)
        Row(children: [
          if (schutz)
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('gc-${g.id}-${g.charakteristik}'),
                initialValue: const ['B', 'C', 'D', 'K', 'Z'].contains(g.charakteristik) ? g.charakteristik : 'B',
                decoration: const InputDecoration(labelText: 'Char.'),
                items: [
                  for (final c in const ['B', 'C', 'D', 'K', 'Z']) DropdownMenuItem(value: c, child: Text(c))
                ],
                onChanged: (v) => aendern({'charakteristik': v}),
              ),
            ),
          if (schutz) const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('gn-${g.id}-${g.nennstrom}'),
              initialValue: const [6, 10, 13, 16, 20, 25, 32, 40, 50, 63, 80, 100].contains(g.nennstrom) ? g.nennstrom : null,
              decoration: const InputDecoration(labelText: 'Nennstrom'),
              items: [
                for (final n in const [6, 10, 13, 16, 20, 25, 32, 40, 50, 63, 80, 100]) DropdownMenuItem(value: n, child: Text('$n A'))
              ],
              onChanged: (v) => aendern({'nennstrom': v}),
            ),
          ),
        ]),
      if (g.art == GeraeteArt.rcd || g.art == GeraeteArt.fils)
        DropdownButtonFormField<int>(
          key: ValueKey('gf-${g.id}-${g.fehlerstrom}'),
          initialValue: const [10, 30, 100, 300].contains(g.fehlerstrom) ? g.fehlerstrom : 30,
          decoration: const InputDecoration(labelText: 'Bemessungsfehlerstrom'),
          items: [
            for (final n in const [10, 30, 100, 300]) DropdownMenuItem(value: n, child: Text('$n mA'))
          ],
          onChanged: (v) => aendern({'fehlerstrom': v}),
        ),
      if (schutz)
        DropdownButtonFormField<String?>(
          key: ValueKey('gp-${g.id}-${g.phase}'),
          initialValue: g.phase,
          decoration: const InputDecoration(labelText: 'Phase'),
          items: const [
            DropdownMenuItem(value: null, child: Text('–')),
            DropdownMenuItem(value: 'L1', child: Text('L1')),
            DropdownMenuItem(value: 'L2', child: Text('L2')),
            DropdownMenuItem(value: 'L3', child: Text('L3')),
            DropdownMenuItem(value: '3P', child: Text('3-phasig')),
          ],
          onChanged: (v) => aendern({'phase': v}),
        ),
      if (g.art == GeraeteArt.ls)
        DropdownButtonFormField<String?>(
          key: ValueKey('gv-${g.id}-${g.vorgeschaltetId}'),
          initialValue: rcds.any((r) => r.id == g.vorgeschaltetId) ? g.vorgeschaltetId : null,
          decoration: const InputDecoration(labelText: 'vorgeschalteter FI/RCD'),
          items: [
            const DropdownMenuItem(value: null, child: Text('– keiner –')),
            for (final r in rcds) DropdownMenuItem(value: r.id, child: Text('${r.kennzeichen} ${r.kurz}')),
          ],
          onChanged: (v) => aendern({'vorgeschaltet_id': v}),
        ),
      if (g.art == GeraeteArt.knx) ..._aktorFelder(g),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Weitere technische Daten'),
        children: [
          for (final fd in BauelementKategorie.schrankgeraet.felder)
            if (const {'rcd_typ', 'schaltvermoegen', 'spd_typ', 'verlust', 'busstrom', 'strom_kanal', 'hilfskontakt'}.contains(fd.schluessel) &&
                (fd.schluessel != 'rcd_typ' || g.art == GeraeteArt.rcd || g.art == GeraeteArt.fils) &&
                (fd.schluessel != 'spd_typ' || g.art == GeraeteArt.spd) &&
                (!const {'busstrom', 'strom_kanal'}.contains(fd.schluessel) || g.art == GeraeteArt.knx))
              switch (fd.typ) {
                FeldTyp.auswahl => DropdownButtonFormField<String?>(
                    key: ValueKey('gz-${g.id}-${fd.schluessel}-${g.eigenschaften[fd.schluessel]}'),
                    initialValue: fd.optionen.contains(g.eigenschaften[fd.schluessel]) ? g.eigenschaften[fd.schluessel] as String : null,
                    decoration: InputDecoration(labelText: fd.label),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('–')),
                      for (final o in fd.optionen) DropdownMenuItem(value: o, child: Text(o)),
                    ],
                    onChanged: (v) => aendern({'eigenschaften': jsonEncode({...g.eigenschaften, fd.schluessel: v}..removeWhere((_, x) => x == null))}),
                  ),
                FeldTyp.jaNein => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(fd.label),
                    value: g.eigenschaften[fd.schluessel] == true,
                    onChanged: (v) => aendern({'eigenschaften': jsonEncode({...g.eigenschaften, fd.schluessel: v == true})}),
                  ),
                _ => SpeicherFeld(
                    key: ValueKey('gz-${g.id}-${fd.schluessel}-${g.eigenschaften[fd.schluessel]}'),
                    initialValue: '${g.eigenschaften[fd.schluessel] ?? ''}'.replaceAll('.', ','),
                    decoration: InputDecoration(labelText: fd.label, suffixText: fd.einheit),
                    onFieldSubmitted: (v) {
                      final z = num.tryParse(v.trim().replaceAll(',', '.'));
                      final eig = {...g.eigenschaften};
                      if (z == null) {
                        eig.remove(fd.schluessel);
                      } else {
                        eig[fd.schluessel] = z;
                      }
                      aendern({'eigenschaften': jsonEncode(eig)});
                    },
                  ),
              },
          SpeicherFeld(
            key: ValueKey('gnotiz-${g.id}'),
            initialValue: g.eigenschaften['notiz'] as String? ?? '',
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Bemerkung'),
            onFieldSubmitted: (v) => aendern({'eigenschaften': jsonEncode({...g.eigenschaften, 'notiz': v})}),
          ),
        ],
      ),
      if (g.art == GeraeteArt.klemme)
        DropdownButtonFormField<String?>(
          key: ValueKey('kl-${g.id}-${g.eigenschaften['stromkreis']}'),
          initialValue: kreise.any((k) => k.id == g.eigenschaften['stromkreis']) ? g.eigenschaften['stromkreis'] as String : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Abgang für Stromkreis'),
          items: [
            const DropdownMenuItem(value: null, child: Text('–')),
            for (final k in kreise) DropdownMenuItem(value: k.id, child: Text('${k.nummer} ${k.bezeichnung}')),
          ],
          onChanged: (v) => aendern({'eigenschaften': jsonEncode({...g.eigenschaften, 'stromkreis': v})}),
        ),
      if (schutz) ...[
        const SizedBox(height: 12),
        Text('Stromkreise', style: Theme.of(context).textTheme.titleSmall),
        for (final k in meineKreise) Text('${k.nummer} ${k.bezeichnung} · ${k.querschnittText}'),
        TextButton.icon(
          onPressed: () async {
            final name = await texteingabe(context, titel: 'Stromkreis', feld: 'Bezeichnung', vorschlag: 'Steckdosen ');
            if (name == null) return;
            final id = store.stromkreisAnlegen(
              schrankId: s.id,
              nummer: '${kreise.length + 1}',
              bezeichnung: name.trim(),
              schutzId: g.id,
              querschnitt: (g.nennstrom ?? 16) > 16 ? 250 : 150,
              leitung: (g.nennstrom ?? 16) > 16 ? 'NYM-J 3x2,5' : 'NYM-J 3x1,5',
            );
            _rueckgaengig.add(() => store.stromkreisLoeschen(id));
            _s.geaendert();
          },
          icon: const Icon(Sym.hinzufuegen, size: 18),
          label: const Text('Stromkreis an diesem Schutzorgan'),
        ),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () {
          store.geraetLoeschen(g.id);
          _rueckgaengig.add(() => store.geraetWiederherstellen(g.id));
          setState(() => _auswahl = null);
          _s.geaendert();
        },
        icon: const Icon(Sym.loeschen),
        label: const Text('Gerät entfernen'),
      ),
    ]);
  }

  // ------------------------------------------------------- Stromkreise

  Widget _stromkreisListe(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
    final store = _s.store!;
    final schutz = [
      for (final g in geraete)
        if (g.art == GeraeteArt.ls || g.art == GeraeteArt.fils) g
    ];
    final alleObjekte = store.alleObjekte();
    final raeume = {
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) r.id: r.name,
    };
    void aendern(Stromkreis k, Map<String, Object?> f) {
      final alt = store.stromkreisAendern(k.id, f);
      _rueckgaengig.add(() => store.stromkreisAendern(k.id, alt));
      _s.geaendert();
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
          'Objekte im Grundriss (Steckdosen, Leuchten …) ordnest du in der Installation dem Stromkreis zu; Räume und Anzahl erscheinen hier.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 8),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            columns: const [
              DataColumn(label: Text('Nr.')),
              DataColumn(label: Text('Bezeichnung')),
              DataColumn(label: Text('Schutzorgan')),
              DataColumn(label: Text('FI/RCD')),
              DataColumn(label: Text('Querschnitt')),
              DataColumn(label: Text('Leitung')),
              DataColumn(label: Text('Last W'), numeric: true),
              DataColumn(label: Text('Räume')),
              DataColumn(label: Text('Objekte'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final k in kreise)
                () {
                  final objekte = [
                    for (final o in alleObjekte)
                      if (o.eigenschaften['stromkreis'] == k.id) o
                  ];
                  final rs = {
                    for (final o in objekte)
                      if (raeume[o.raumId] != null) raeume[o.raumId]!
                  }.join(', ');
                  final sch = geraete.where((g) => g.id == k.schutzId).firstOrNull;
                  final rcd = sch?.art == GeraeteArt.fils ? sch : geraete.where((g) => g.id == sch?.vorgeschaltetId).firstOrNull;
                  return DataRow(cells: [
                    DataCell(SizedBox(
                      width: 40,
                      child: SpeicherFeld(
                        key: ValueKey('kn-${k.id}-${k.nummer}'),
                        initialValue: k.nummer,
                        onFieldSubmitted: (v) => aendern(k, {'nummer': v.trim()}),
                      ),
                    )),
                    DataCell(SizedBox(
                      width: 180,
                      child: SpeicherFeld(
                        key: ValueKey('kb-${k.id}-${k.bezeichnung}'),
                        initialValue: k.bezeichnung,
                        onFieldSubmitted: (v) => aendern(k, {'bezeichnung': v.trim()}),
                      ),
                    )),
                    DataCell(DropdownButton<String?>(
                      value: schutz.any((g) => g.id == k.schutzId) ? k.schutzId : null,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('–')),
                        for (final g in schutz) DropdownMenuItem(value: g.id, child: Text('${g.kennzeichen} ${g.kurz}')),
                      ],
                      onChanged: (v) => aendern(k, {'schutz_id': v}),
                    )),
                    DataCell(Text(rcd == null ? '–' : '${rcd.kennzeichen} ${rcd.fehlerstrom ?? 30} mA')),
                    DataCell(DropdownButton<int>(
                      value: const [150, 250, 400, 600, 1000, 1600].contains(k.querschnitt) ? k.querschnitt : 150,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final q in const [150, 250, 400, 600, 1000, 1600])
                          DropdownMenuItem(
                              value: q, child: Text('${(q / 100).toStringAsFixed(q % 100 == 0 ? 0 : 1).replaceAll('.', ',')} mm²')),
                      ],
                      onChanged: (v) => aendern(k, {'querschnitt': v}),
                    )),
                    DataCell(SizedBox(
                      width: 120,
                      child: SpeicherFeld(
                        key: ValueKey('kl-${k.id}-${k.leitung}'),
                        initialValue: k.leitung,
                        onFieldSubmitted: (v) => aendern(k, {'leitung': v.trim()}),
                      ),
                    )),
                    DataCell(SizedBox(
                      width: 70,
                      child: SpeicherFeld(
                        key: ValueKey('kw-${k.id}-${k.leistung}'),
                        initialValue: '${k.leistung}',
                        textAlign: TextAlign.right,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onFieldSubmitted: (v) => aendern(k, {'leistung_w': int.tryParse(v) ?? 0}),
                      ),
                    )),
                    DataCell(Text(rs.isEmpty ? '–' : rs)),
                    DataCell(TextButton(
                      onPressed: objekte.isEmpty
                          ? null
                          : () {
                              _s.markiert = {for (final o in objekte) o.id};
                              _s.geschossId = objekte.first.geschossId;
                              _s.modulWaehlen(Modul.installation);
                            },
                      child: Text(objekte.isEmpty ? '0' : '${objekte.length} zeigen'),
                    )),
                    DataCell(IconButton(
                      tooltip: 'Stromkreis löschen',
                      icon: const Icon(Sym.loeschen, size: 18),
                      onPressed: () {
                        store.stromkreisLoeschen(k.id);
                        _rueckgaengig.add(() => store.stromkreisWiederherstellen(k.id));
                        _s.geaendert();
                      },
                    )),
                  ]);
                }(),
            ],
          ),
        ),
      ),
    ]);
  }


  // ------------------------------------------------------- Verdrahtung

  String _drahtFilter = 'alle'; // alle, L1, L2, L3, N, PE oder Stromkreis-ID

  List<Draht> _gefiltert(List<Draht> d, List<SchrankGeraet> geraete) => switch (_drahtFilter) {
        'alle' => d,
        'L1' || 'L2' || 'L3' || 'N' || 'PE' => [for (final x in d) if (x.leiter == _drahtFilter) x],
        _ => [for (final x in d) if (x.stromkreis == _drahtFilter) x],
      };

  Future<void> _schieneNeu(Schrank s, List<SchrankGeraet> geraete) async {
    final store = _s.store!;
    var reihe = 0, von = 0, bis = s.teJeReihe, art = '1P+N';
    String? einspeisung;
    final quellen = [for (final g in geraete) if (g.art == GeraeteArt.rcd || g.art == GeraeteArt.hauptschalter) g];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Kammschiene'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                initialValue: reihe,
                decoration: const InputDecoration(labelText: 'Reihe'),
                items: [for (var i = 0; i < s.reihen; i++) DropdownMenuItem(value: i, child: Text('${i + 1}'))],
                onChanged: (v) => setD(() => reihe = v ?? 0),
              ),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: von,
                    decoration: const InputDecoration(labelText: 'ab TE'),
                    items: [for (var i = 0; i < s.teJeReihe; i++) DropdownMenuItem(value: i, child: Text('${i + 1}'))],
                    onChanged: (v) => setD(() {
                      von = v ?? 0;
                      if (bis <= von) bis = von + 1;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('bis-$von'),
                    initialValue: bis,
                    decoration: const InputDecoration(labelText: 'bis TE'),
                    items: [for (var i = von + 1; i <= s.teJeReihe; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => setD(() => bis = v ?? bis),
                  ),
                ),
              ]),
              DropdownButtonFormField<String>(
                initialValue: art,
                decoration: const InputDecoration(labelText: 'Art'),
                items: [for (final a in const ['1P', '1P+N', '3P', '3P+N']) DropdownMenuItem(value: a, child: Text(a))],
                onChanged: (v) => setD(() => art = v ?? art),
              ),
              DropdownButtonFormField<String?>(
                initialValue: einspeisung,
                decoration: const InputDecoration(labelText: 'Einspeisung von'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('– noch offen –')),
                  for (final g in quellen) DropdownMenuItem(value: g.id, child: Text('${g.kennzeichen} ${g.kurz}')),
                ],
                onChanged: (v) => setD(() => einspeisung = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Anlegen')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final liste = [
      ...kammschienen(s).map((k) => k.toJson()),
      Kammschiene(id: DateTime.now().microsecondsSinceEpoch.toString(), reihe: reihe, von: von, bis: bis, art: art, einspeisung: einspeisung).toJson(),
    ];
    final alt = store.schrankAendern(s.id, {'eigenschaften': jsonEncode({...s.eigenschaften, 'kammschienen': liste})});
    _rueckgaengig.add(() => store.schrankAendern(s.id, alt));
    _s.geaendert();
  }

  void _schieneLoeschen(Schrank s, Kammschiene k) {
    final store = _s.store!;
    final liste = [for (final x in kammschienen(s)) if (x.id != k.id) x.toJson()];
    final alt = store.schrankAendern(s.id, {'eigenschaften': jsonEncode({...s.eigenschaften, 'kammschienen': liste})});
    _rueckgaengig.add(() => store.schrankAendern(s.id, alt));
    _s.geaendert();
  }

  Widget _verdrahtungAnsicht(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
    final store = _s.store!;
    final alle = verdrahtung(s, geraete, kreise);
    final draehte = _gefiltert(alle, geraete);
    final schienen = kammschienen(s);
    final material = verdrahtungsMaterial(alle, schienen);
    final hinweise = verdrahtungsHinweise(s, geraete, kreise);
    final filterWerte = {'alle', 'L1', 'L2', 'L3', 'N', 'PE', for (final k in kreise) k.id};
    if (!filterWerte.contains(_drahtFilter)) _drahtFilter = 'alle';
    String q(int x) => '${(x / 100).toStringAsFixed(x % 100 == 0 ? 0 : 1).replaceAll('.', ',')} mm²';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _schrankAnsicht(s, geraete, kreise)),
          SizedBox(
            width: 340,
            child: Material(
              color: Colors.white,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  const Text('Zeigen: '),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _drahtFilter,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: 'alle', child: Text('alle Drähte')),
                        for (final l in const ['L1', 'L2', 'L3', 'N', 'PE']) DropdownMenuItem(value: l, child: Text('nur $l')),
                        for (final k in kreise) DropdownMenuItem(value: k.id, child: Text('Stromkreis ${k.nummer} ${k.bezeichnung}')),
                      ],
                      onChanged: (v) => setState(() => _drahtFilter = v ?? 'alle'),
                    ),
                  ),
                ]),
                Text('${alle.length} Drähte, zusammen ca. ${drahtGesamt(alle).toStringAsFixed(1).replaceAll('.', ',')} m',
                    style: const TextStyle(color: BsFarben.textLeise)),
                const SizedBox(height: 12),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                  Text('Kammschienen', style: Theme.of(context).textTheme.titleSmall),
                  TextButton.icon(onPressed: () => _schieneNeu(s, geraete), icon: const Icon(Sym.hinzufuegen, size: 18), label: const Text('Schiene')),
                ]),
                for (final k in schienen)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Reihe ${k.reihe + 1}, TE ${k.von + 1}–${k.bis} · ${k.art}'),
                    subtitle: Text('Einspeisung: ${geraete.where((g) => g.id == k.einspeisung).firstOrNull?.kennzeichen ?? 'offen'}'),
                    trailing: IconButton(icon: const Icon(Sym.loeschen, size: 18), onPressed: () => _schieneLoeschen(s, k)),
                  ),
                if (schienen.isEmpty)
                  const Text('Ohne Kammschiene wird jeder LS einzeln verdrahtet.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                const SizedBox(height: 12),
                Text('Material', style: Theme.of(context).textTheme.titleSmall),
                for (final (text, menge, einheit) in material)
                  Text('${menge == menge.roundToDouble() ? menge.round() : menge.toStringAsFixed(1).replaceAll('.', ',')} $einheit  $text',
                      style: const TextStyle(fontSize: 12)),
                if (material.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      final ids = [
                        for (final (text, menge, einheit) in material)
                          store.kostenpositionAnlegen(
                            text: '$text (${s.name})',
                            mengeMilli: (menge * 1000).round(),
                            einheit: einheit,
                            gewerkId: store.gewerke().where((g) => g.kuerzel == 'EL').firstOrNull?.id,
                          ),
                      ];
                      _rueckgaengig.add(() {
                        for (final id in ids) {
                          store.kostenpositionLoeschen(id);
                        }
                      });
                      _s.geaendert();
                      zeigeHinweis(context, '${ids.length} Positionen in die Kostenliste übernommen.');
                    },
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('In die Kostenliste'),
                  ),
                const SizedBox(height: 12),
                Text('Hinweise', style: Theme.of(context).textTheme.titleSmall),
                if (hinweise.isEmpty) const Text('Keine Auffälligkeiten.', style: TextStyle(color: BsFarben.textLeise)),
                for (final h in hinweise) Text('• $h', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
                const SizedBox(height: 8),
                const Text(
                    'Die Drähte entstehen aus der Schrankplanung (Vorschaltung, Kammschienen, Stromkreise, Klemmen). Längen sind Schätzwerte. '
                    'Nur Hinweise – Auslegung und Abnahme durch eine Elektrofachkraft.',
                    style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
              ]),
            ),
          ),
        ]),
      ),
      Container(
        height: 230,
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: BsFarben.rand))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              Text('Verdrahtungsliste', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final b = StringBuffer('Nr.;von;nach;Leiter;Querschnitt;Farbe;Länge mm\n');
                  for (final d in alle) {
                    b.writeln('${d.nr};${d.von};${d.nach};${d.leiter};${q(d.querschnitt)};${d.farbe};${d.laenge.round()}');
                  }
                  final datei = File(p.join(store.ordner, 'exporte', 'Verdrahtung_${s.kennzeichen}.csv'));
                  await datei.parent.create(recursive: true);
                  await datei.writeAsString('﻿$b');
                  if (mounted) zeigeHinweis(context, 'Gespeichert: ${datei.path}');
                },
                icon: const Icon(Icons.table_view_outlined, size: 18),
                label: const Text('CSV'),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                headingRowHeight: 32,
                dataRowMinHeight: 26,
                dataRowMaxHeight: 30,
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Nr.'), numeric: true),
                  DataColumn(label: Text('von')),
                  DataColumn(label: Text('nach')),
                  DataColumn(label: Text('Leiter')),
                  DataColumn(label: Text('Querschnitt')),
                  DataColumn(label: Text('Farbe')),
                  DataColumn(label: Text('Länge'), numeric: true),
                ],
                rows: [
                  for (final d in draehte)
                    DataRow(cells: [
                      DataCell(Text('${d.nr}')),
                      DataCell(Text(d.von)),
                      DataCell(Text(d.nach)),
                      DataCell(Text(d.leiter)),
                      DataCell(Text(q(d.querschnitt))),
                      DataCell(Text(d.farbe)),
                      DataCell(Text('${d.laenge.round()} mm')),
                    ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ------------------------------------------------- KNX / Home Assistant

  static const aktortypen = ['Schalt', 'Dimm', 'Jalousie', 'Heizung', 'Binäreingang / Taster', 'Sonstiges'];

  List<Gruppenadresse> _gas() => [
        for (final m in (_s.store!.einstellung<List>('knx_gruppenadressen') ?? const []))
          Gruppenadresse.ausJson(Map<String, dynamic>.from(m as Map)),
      ]..sort((a, b) => a.sortierwert.compareTo(b.sortierwert));

  void _gasSpeichern(List<Gruppenadresse> neu) {
    final store = _s.store!;
    final alt = store.einstellung<List>('knx_gruppenadressen');
    store.einstellungSetzen('knx_gruppenadressen', [for (final g in neu) g.toJson()]);
    _rueckgaengig.add(() => store.einstellungSetzen('knx_gruppenadressen', alt));
    _s.geaendert();
  }

  /// Verbraucher, die an einem Aktorkanal hängen können (Elektro und KNX).
  List<Objekt> _verbraucher() {
    final store = _s.store!;
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final gewerke = {for (final g in store.gewerke()) g.id: g.kuerzel};
    return [
      for (final o in store.alleObjekte())
        if (typen[o.typId]?.geometrie == Geometrieart.punkt && (gewerke[typen[o.typId]?.gewerkId] == 'EL' || gewerke[typen[o.typId]?.gewerkId] == 'KX')) o
    ];
  }

  /// Alle belegten Aktorkanäle im Projekt.
  List<KanalBelegung> _kanalBelegung() {
    final store = _s.store!;
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final raeume = {
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) r.id: r.name,
    };
    final aktoren = {
      for (final s in store.schraenke())
        for (final g in store.schrankGeraete(s.id))
          if (g.art == GeraeteArt.knx) g.id: (s, g),
    };
    final liste = <KanalBelegung>[];
    for (final o in store.alleObjekte()) {
      final k = o.eigenschaften['knx_kanal'];
      if (k is! String || !k.contains(':')) continue;
      final (aktorId, kanal) = (k.substring(0, k.lastIndexOf(':')), k.substring(k.lastIndexOf(':') + 1));
      final a = aktoren[aktorId];
      if (a == null) continue;
      final (s, g) = a;
      final raum = raeume[o.raumId];
      liste.add((
        aktorId: g.id,
        aktor: betriebsmittel(s, g),
        aktortyp: g.eigenschaften['aktortyp'] as String? ?? 'Schalt',
        kanal: kanal,
        objektId: o.id,
        name: '${raum == null ? '' : '$raum '}${typen[o.typId]?.name ?? ''} ${o.kennung}'.trim(),
        kuerzel: typen[o.typId]?.kuerzel ?? '',
      ));
    }
    liste.sort((a, b) => '${a.aktor}${a.kanal}'.compareTo('${b.aktor}${b.kanal}'));
    return liste;
  }

  /// Kanalbelegung eines KNX-Aktors im Gerätefeld.
  List<Widget> _aktorFelder(SchrankGeraet g) {
    final store = _s.store!;
    final typ = g.eigenschaften['aktortyp'] as String? ?? 'Schalt';
    final anzahl = (g.eigenschaften['kanaele'] as num?)?.toInt() ?? 8;
    final pa = g.eigenschaften['pa'] as String? ?? '';
    final verbraucher = _verbraucher();
    void eig(String k, Object? v) {
      final alt = store.geraetAendern(g.id, {'eigenschaften': jsonEncode({...g.eigenschaften, k: v})});
      _rueckgaengig.add(() => store.geraetAendern(g.id, alt));
      _s.geaendert();
    }

    void belegen(String kanal, String? objektId) {
      final schluessel = '${g.id}:$kanal';
      final rueck = <VoidCallback>[];
      for (final o in verbraucher) {
        final istHier = o.eigenschaften['knx_kanal'] == schluessel;
        if (istHier && o.id != objektId) {
          final alt = store.objektAendern(o.id, {'eigenschaften': jsonEncode({...o.eigenschaften}..remove('knx_kanal'))});
          rueck.add(() => store.objektAendern(o.id, alt));
        } else if (!istHier && o.id == objektId) {
          final alt = store.objektAendern(o.id, {'eigenschaften': jsonEncode({...o.eigenschaften, 'knx_kanal': schluessel})});
          rueck.add(() => store.objektAendern(o.id, alt));
        }
      }
      _rueckgaengig.add(() {
        for (final r in rueck.reversed) {
          r();
        }
      });
      _s.geaendert();
    }

    return [
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('at-${g.id}-$typ'),
            initialValue: aktortypen.contains(typ) ? typ : 'Schalt',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Aktortyp'),
            items: [for (final t in aktortypen) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => eig('aktortyp', v),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: DropdownButtonFormField<int>(
            key: ValueKey('ak-${g.id}-$anzahl'),
            initialValue: anzahl,
            decoration: const InputDecoration(labelText: 'Kanäle'),
            items: [for (final n in {1, 2, 4, 6, 8, 12, 16, 20, 24, anzahl}) DropdownMenuItem(value: n, child: Text('$n'))],
            onChanged: (v) => eig('kanaele', v),
          ),
        ),
      ]),
      SpeicherFeld(
        key: ValueKey('pa-${g.id}-$pa'),
        initialValue: pa,
        decoration: InputDecoration(
          labelText: 'Physikalische Adresse',
          hintText: '1.1.10',
          errorText: pa.isEmpty || paGueltig(pa) ? null : 'Format Bereich.Linie.Teilnehmer',
        ),
        onFieldSubmitted: (v) => eig('pa', v.trim()),
      ),
      const SizedBox(height: 8),
      Text('Kanalbelegung', style: Theme.of(context).textTheme.titleSmall),
      for (final k in kanalNamen(anzahl))
        Row(children: [
          SizedBox(width: 28, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: verbraucher.where((o) => o.eigenschaften['knx_kanal'] == '${g.id}:$k').firstOrNull?.id,
              hint: const Text('frei', style: TextStyle(color: BsFarben.textLeise)),
              items: [
                const DropdownMenuItem(value: null, child: Text('– frei –')),
                for (final o in verbraucher) DropdownMenuItem(value: o.id, child: Text(o.kennung, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => belegen(k, v),
            ),
          ),
        ]),
    ];
  }

  Widget _knxAnsicht() {
    final store = _s.store!;
    final belegung = _kanalBelegung();
    final gas = _gas();
    final doppelt = doppelteAdressen(gas);
    final objekte = {for (final o in store.alleObjekte()) o.id: o};
    final typen = {for (final t in store.objekttypen()) t.id: t};

    List<HaEintrag> haEintraege() {
      final nach = <String, List<Gruppenadresse>>{};
      for (final g in gas) {
        for (final o in g.objekte) {
          nach.putIfAbsent(o, () => []).add(g);
        }
      }
      return [
        for (final e in nach.entries)
          if (objekte[e.key] case final o?)
            () {
              final b = belegung.where((x) => x.objektId == o.id).firstOrNull;
              final dom = haDomaene(typen[o.typId]?.kuerzel ?? '', aktortyp: b?.aktortyp);
              final name = b?.name ?? o.kennung;
              final entity = o.eigenschaften['ha_entity'] as String? ?? '$dom.${haSlug(name)}';
              return (domaene: entity.contains('.') ? entity.split('.').first : dom, name: name, entity: entity, gas: e.value);
            }(),
      ];
    }

    Future<void> speichern(String datei, String inhalt) async {
      final f = File(p.join(store.ordner, 'exporte', datei));
      await f.parent.create(recursive: true);
      await f.writeAsString(inhalt);
      await Clipboard.setData(ClipboardData(text: inhalt));
      if (mounted) zeigeHinweis(context, 'Gespeichert unter ${f.path} und in die Zwischenablage kopiert.');
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          onPressed: belegung.isEmpty
              ? null
              : () {
                  var n = 0;
                  final t = DateTime.now().microsecondsSinceEpoch;
                  _gasSpeichern(gruppenadressenVorschlagen(belegung, gas, neueId: () => '$t-${n++}'));
                },
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: const Text('Gruppenadressen aus Kanalbelegung'),
        ),
        OutlinedButton.icon(
          onPressed: () => _gasSpeichern([
            ...gas,
            Gruppenadresse(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              haupt: 1,
              mittel: 0,
              unter: naechsteUntergruppe(gas, 1, 0),
              name: 'Neue Gruppenadresse',
            ),
          ]),
          icon: const Icon(Sym.hinzufuegen, size: 18),
          label: const Text('Gruppenadresse'),
        ),
        OutlinedButton.icon(
          onPressed: gas.isEmpty ? null : () => speichern('Gruppenadressen_ETS.csv', etsCsv(gas)),
          icon: const Icon(Icons.table_view_outlined, size: 18),
          label: const Text('ETS-Export (CSV)'),
        ),
        OutlinedButton.icon(
          onPressed: gas.isEmpty ? null : () => speichern('home_assistant_knx.yaml', haYaml(haEintraege())),
          icon: const Icon(Icons.home_outlined, size: 18),
          label: const Text('Home Assistant (YAML)'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => EtsAbgleichPage(state: _s, gas: gas, speichern: _gasSpeichern)))
              .then((_) => mounted ? setState(() {}) : null),
          icon: const Icon(Icons.compare_arrows, size: 18),
          label: const Text('ETS-Projekt abgleichen'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            final z = <HaZuordnung>[];
            final belegt = <String>{};
            for (final o in objekte.values) {
              final e = (o.eigenschaften['ha_entity'] as String? ?? '').trim();
              if (e.isNotEmpty) {
                z.add((entity: e, objektId: o.id, objekt: o.kennung, rolle: 'Objekt'));
                belegt.add(o.id);
              }
              for (final x in Map<String, dynamic>.from(o.eigenschaften['ha_entities'] as Map? ?? const {}).entries) {
                if ('${x.value}'.trim().isNotEmpty) z.add((entity: '${x.value}'.trim(), objektId: o.id, objekt: o.kennung, rolle: x.key));
              }
            }
            for (final h in haEintraege()) {
              final o = objekte.values.where((o) => o.eigenschaften['ha_entity'] == null && h.gas.any((g) => g.objekte.contains(o.id))).firstOrNull;
              if (o != null && !belegt.contains(o.id)) z.add((entity: h.entity, objektId: o.id, objekt: o.kennung, rolle: haRolleVorschlag));
            }
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => HaLivePage(state: _s, zuordnungen: z)))
                .then((_) => mounted ? setState(() {}) : null);
          },
          icon: const Icon(Icons.sensors, size: 18),
          label: const Text('Home Assistant live'),
        ),
      ]),
      if (doppelt.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Doppelt vergeben: ${doppelt.join(', ')}', style: const TextStyle(color: Color(0xFFB91C1C))),
        ),
      const SizedBox(height: 16),
      Text('Kanalbelegung (${belegung.length})', style: Theme.of(context).textTheme.titleMedium),
      const Text('Kanäle belegst du im Schrank beim KNX-Aktor (Gerät anklicken).', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      const SizedBox(height: 6),
      Card(
        child: belegung.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Text('Noch keine Aktorkanäle belegt.'))
            : DataTable(columnSpacing: 24, columns: const [
                DataColumn(label: Text('Aktor')),
                DataColumn(label: Text('Kanal')),
                DataColumn(label: Text('Typ')),
                DataColumn(label: Text('Verbraucher')),
              ], rows: [
                for (final b in belegung)
                  DataRow(cells: [DataCell(Text(b.aktor)), DataCell(Text(b.kanal)), DataCell(Text(b.aktortyp)), DataCell(Text(b.name))]),
              ]),
      ),
      const SizedBox(height: 16),
      Text('Gruppenadressen (${gas.length})', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columnSpacing: 18, columns: const [
            DataColumn(label: Text('Adresse')),
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Funktion')),
            DataColumn(label: Text('Objekte')),
            DataColumn(label: Text('')),
          ], rows: [
            for (final g in gas)
              DataRow(cells: [
                DataCell(SizedBox(
                  width: 80,
                  child: SpeicherFeld(
                    key: ValueKey('ga-${g.id}-${g.adresse}'),
                    initialValue: g.adresse,
                    style: TextStyle(color: doppelt.contains(g.adresse) ? const Color(0xFFB91C1C) : null),
                    pruefen: (v) => gaLesen(v) == null ? 'Format 1/0/12' : null,
                    onFieldSubmitted: (v) {
                      final a = gaLesen(v)!;
                      _gasSpeichern([for (final x in gas) x.id == g.id ? x.mit(haupt: a.$1, mittel: a.$2, unter: a.$3) : x]);
                    },
                  ),
                )),
                DataCell(SizedBox(
                  width: 260,
                  child: SpeicherFeld(
                    key: ValueKey('gn-${g.id}-${g.name}'),
                    initialValue: g.name,
                    onFieldSubmitted: (v) => _gasSpeichern([for (final x in gas) x.id == g.id ? x.mit(name: v.trim()) : x]),
                  ),
                )),
                DataCell(DropdownButton<String>(
                  value: gaFunktionen.containsKey(g.funktion) ? g.funktion : 'schalten',
                  underline: const SizedBox.shrink(),
                  items: [for (final e in gaFunktionen.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
                  onChanged: (v) => _gasSpeichern([for (final x in gas) x.id == g.id ? x.mit(funktion: v) : x]),
                )),
                DataCell(Text([for (final o in g.objekte) objekte[o]?.kennung ?? '?'].join(', '))),
                DataCell(IconButton(
                  icon: const Icon(Sym.loeschen, size: 18),
                  onPressed: () => _gasSpeichern([for (final x in gas) if (x.id != g.id) x]),
                )),
              ]),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
          'Home-Assistant-Entitäten werden aus Raum und Objekt vorgeschlagen (z. B. light.bad_leuchte_eg_bad_le_01); '
          'eigene IDs trägst du in der Installation beim Objekt ein.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
    ]);
  }

  // ------------------------------------------------------- Außenmaße

  /// Außenmaße und Einbauart des Schranks; Vorschlag aus Reihen × TE und
  /// Prüfung, ob er in die Wand passt (Unterputz/Hohlwand).
  List<Widget> _aussenmasse(Schrank s, void Function(Map<String, Object?>) aendern) {
    final a = Map<String, dynamic>.from(s.eigenschaften['aussen'] as Map? ?? const {});
    int? z(String k) => (a[k] as num?)?.toInt();
    final vorschlagB = (s.teJeReihe * 17.5 + 2 * 75).round(), vorschlagH = s.reihen * 150 + 2 * 100;
    final einbau = s.eigenschaften['einbau'] as String? ?? 'Aufputz';
    void setzen(Map<String, Object?> neu) => aendern({'eigenschaften': jsonEncode({...s.eigenschaften, ...neu})});
    Widget feld(String label, String k, int vorschlag) => Expanded(
          child: SpeicherFeld(
            key: ValueKey('sa-${s.id}-$k-${z(k)}'),
            initialValue: z(k)?.toString() ?? '',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, suffixText: 'mm', hintText: '$vorschlag'),
            onFieldSubmitted: (v) {
              final n = int.tryParse(v);
              final neu = {...a};
              if (n == null) {
                neu.remove(k);
              } else {
                neu[k] = n;
              }
              setzen({'aussen': neu});
            },
          ),
        );
    // Wand, in der der Schrank sitzt (über das Verteiler-Objekt im Grundriss)
    String? pruefung;
    final store = _s.store!;
    final obj = s.objektId == null ? null : store.alleObjekte().where((o) => o.id == s.objektId).firstOrNull;
    if (obj != null && obj.punkte.isNotEmpty && einbau != 'Aufputz' && z('tiefe') != null) {
      final p = obj.punkte.first;
      Wand? beste;
      var bester = double.infinity;
      for (final w in store.waende(obj.geschossId)) {
        final d = abstandZuStrecke(Offset(p.x, p.y), Offset(w.x1.toDouble(), w.y1.toDouble()), Offset(w.x2.toDouble(), w.y2.toDouble()));
        if (d < bester) {
          bester = d;
          beste = w;
        }
      }
      if (beste != null && bester < beste.dicke) {
        final rest = beste.dicke - z('tiefe')!;
        pruefung = rest < 30
            ? 'Passt nicht: Wand ${beste.dicke} mm, Schrank ${z('tiefe')} mm tief – Restwand $rest mm (mind. 30 mm, bei Brandwänden mehr).'
            : 'Passt: Wand ${beste.dicke} mm, Restwand hinter dem Schrank $rest mm.';
      }
    }
    return [
      const SizedBox(height: 12),
      Text('Außenmaße', style: Theme.of(context).textTheme.titleSmall),
      Row(children: [
        feld('Breite', 'breite', vorschlagB),
        const SizedBox(width: 8),
        feld('Höhe', 'hoehe', vorschlagH),
        const SizedBox(width: 8),
        feld('Tiefe', 'tiefe', einbau == 'Aufputz' ? 120 : 95),
      ]),
      DropdownButtonFormField<String>(
        key: ValueKey('se-${s.id}-$einbau'),
        initialValue: const ['Aufputz', 'Unterputz', 'Hohlwand', 'Standschrank'].contains(einbau) ? einbau : 'Aufputz',
        decoration: const InputDecoration(labelText: 'Einbau'),
        items: [for (final e in const ['Aufputz', 'Unterputz', 'Hohlwand', 'Standschrank']) DropdownMenuItem(value: e, child: Text(e))],
        onChanged: (v) => setzen({'einbau': v}),
      ),
      Text(
        'Richtwert für ${s.reihen} × ${s.teJeReihe} TE: ca. $vorschlagB × $vorschlagH mm. Genaue Maße aus dem Herstellerdatenblatt.',
        style: const TextStyle(fontSize: 12, color: BsFarben.textLeise),
      ),
      if (pruefung != null)
        Text(pruefung, style: TextStyle(fontSize: 12, color: pruefung.startsWith('Passt nicht') ? const Color(0xFFB91C1C) : const Color(0xFF2F9E44))),
      const SizedBox(height: 12),
      Text('Aufbau für die echte Darstellung', style: Theme.of(context).textTheme.titleSmall),
      Builder(builder: (_) {
        final ab = Map<String, dynamic>.from(s.eigenschaften['aufbau'] as Map? ?? const {});
        final d = SchrankAufbau.aus(s.eigenschaften);
        Widget f(String label, String k, int wert, {String einheit = 'mm'}) => SizedBox(
              width: 130,
              child: SpeicherFeld(
                key: ValueKey('sab-${s.id}-$k-$wert'),
                initialValue: '$wert',
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: label, suffixText: einheit),
                onFieldSubmitted: (v) => setzen({'aufbau': {...ab, k: int.tryParse(v) ?? wert}}),
              ),
            );
        return Wrap(spacing: 8, runSpacing: 8, children: [
          f('Anschlussraum oben', 'raum_oben', d.raumOben),
          f('Anschlussraum unten', 'raum_unten', d.raumUnten),
          f('Platz neben Schienen', 'seite', d.seite),
          f('Einführungen oben', 'einf_oben', d.einfuehrungenOben, einheit: 'Stk'),
          f('Einführungen unten', 'einf_unten', d.einfuehrungenUnten, einheit: 'Stk'),
          f('Breite/Ø je Einführung', 'einf_breite', d.einfuehrungBreite),
          f('Einführungen hinten', 'einf_hinten', d.einfuehrungenHinten, einheit: 'Stk'),
          SizedBox(
            width: 270,
            child: DropdownButtonFormField<String>(
              key: ValueKey('sab-${s.id}-art-${d.art}'),
              isExpanded: true,
              initialValue: d.art,
              decoration: const InputDecoration(labelText: 'Art der Einführungen'),
              items: const [
                DropdownMenuItem(value: 'nippel', child: Text('viele kleine (Würgenippel/Membran)')),
                DropdownMenuItem(value: 'ausbruch', child: Text('breite Ausbrüche zum Aufstemmen')),
              ],
              onChanged: (v) => setzen({'aufbau': {...ab, 'art': v}}),
            ),
          ),
        ]);
      }),
    ];
  }

  // ------------------------------------------------------- Patchfeld

  List<Widget> _patchfeld(Schrank s) {
    final store = _s.store!;
    final ports = (s.eigenschaften['ports'] as num?)?.toInt() ?? 24;
    final belegung = Map<String, dynamic>.from(s.eigenschaften['patch'] as Map? ?? const {});
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final dosen = [for (final o in store.alleObjekte()) if (typen[o.typId]?.kuerzel == 'ND' || typen[o.typId]?.kuerzel == 'AP') o];
    final raeume = {
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) r.id: r.name,
    };
    void setzen(Map<String, Object?> eig) {
      final alt = store.schrankAendern(s.id, {'eigenschaften': jsonEncode({...s.eigenschaften, ...eig})});
      _rueckgaengig.add(() => store.schrankAendern(s.id, alt));
      _s.geaendert();
    }

    return [
      const SizedBox(height: 16),
      Row(children: [
        Text('Patchfeld', style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        DropdownButton<int>(
          value: ports,
          items: [for (final n in {12, 16, 24, 48, ports}) DropdownMenuItem(value: n, child: Text('$n Ports'))],
          onChanged: (v) => setzen({'ports': v}),
        ),
      ]),
      for (var i = 1; i <= ports; i++)
        Row(children: [
          SizedBox(width: 30, child: Text('$i', style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: dosen.any((o) => o.id == belegung['$i']) ? belegung['$i'] as String : null,
              hint: const Text('frei', style: TextStyle(color: BsFarben.textLeise)),
              items: [
                const DropdownMenuItem(value: null, child: Text('– frei –')),
                for (final o in dosen)
                  DropdownMenuItem(value: o.id, child: Text('${o.kennung}${raeume[o.raumId] == null ? '' : ' · ${raeume[o.raumId]}'}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setzen({'patch': {...belegung, '$i': v}..removeWhere((_, x) => x == null)}),
            ),
          ),
        ]),
      TextButton.icon(
        onPressed: () async {
          final b = StringBuffer('Port;Dose;Raum\n');
          for (var i = 1; i <= ports; i++) {
            final o = dosen.where((x) => x.id == belegung['$i']).firstOrNull;
            b.writeln('$i;${o?.kennung ?? ''};${o == null ? '' : raeume[o.raumId] ?? ''}');
          }
          final f = File(p.join(store.ordner, 'exporte', 'Patchfeld_${s.kennzeichen}.csv'));
          await f.parent.create(recursive: true);
          await f.writeAsString('﻿$b');
          if (mounted) zeigeHinweis(context, 'Gespeichert: ${f.path}');
        },
        icon: const Icon(Icons.table_view_outlined, size: 18),
        label: const Text('Patchfeldbelegung als CSV'),
      ),
    ];
  }
  // ------------------------------------------------ Übersichtsschaltbild

  Widget _uebersicht(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
    return InteractiveViewer(
      constrained: false,
      minScale: 0.3,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(200),
      child: CustomPaint(
        size: _UebersichtPainter.groesse(geraete),
        painter: _UebersichtPainter(schrank: s, geraete: geraete, kreise: kreise),
      ),
    );
  }

  // ------------------------------------------------------- Beschriftung

  Widget _beschriftungVorschau(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
    final streifen = beschriftung(s, geraete, kreise);
    const te = 30.0;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Beschriftungsstreifen je Reihe (Vorschau). Das PDF hat echte Größe: 1 TE = 17,5 mm, Streifenhöhe 12 mm.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      for (var r = 0; r < streifen.length; r++) ...[
        const SizedBox(height: 12),
        Text('Reihe ${r + 1}'),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (_, breite, text) in streifen[r])
              Container(
                width: breite * te,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border.all(color: Colors.black54), color: Colors.white),
                child: Text(text,
                    style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis, maxLines: 2, textAlign: TextAlign.center),
              ),
          ]),
        ),
      ],
    ]);
  }

  Stromlaufplan _stromlaufplan(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) {
    final store = _s.store!;
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final raeume = {
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final r in store.raeume(g.id)) r.id: r.name,
    };
    final vb = <String, List<SlpVerbraucher>>{};
    for (final o in store.alleObjekte()) {
      final k = o.eigenschaften['stromkreis'];
      if (k is! String || !kreise.any((x) => x.id == k)) continue;
      vb.putIfAbsent(k, () => []).add((
        kennung: o.kennung,
        kuerzel: typen[o.typId]?.kuerzel ?? '',
        typ: typen[o.typId]?.name ?? '',
        raum: raeume[o.raumId] ?? '',
        knxKanal: o.eigenschaften['knx_kanal'] as String?,
      ));
    }
    return stromlaufplanErzeugen(schrank: s, geraete: geraete, kreise: kreise, verbraucher: vb, projekt: p.basename(store.ordner));
  }

  Future<void> _stromlaufplanPdf(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) async {
    final plan = _stromlaufplan(s, geraete, kreise);
    final datei = File(p.join(_s.store!.ordner, 'exporte', 'Stromlaufplan_${s.kennzeichen}.pdf'));
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(await stromlaufplanPdf(plan, titel: 'Stromlaufplan ${s.name}'));
    if (!mounted) return;
    zeigeHinweis(context, 'Gespeichert: ${datei.path} (${plan.blaetter.length} Blätter)',
        aktion: SnackBarAction(label: 'Pfad kopieren', onPressed: () => Clipboard.setData(ClipboardData(text: datei.path))));
  }

  Future<void> _beschriftungPdf(Schrank s, List<SchrankGeraet> geraete, List<Stromkreis> kreise) async {
    final streifen = beschriftung(s, geraete, kreise);
    final doc = pw.Document(title: 'Beschriftung ${s.name}');
    const mm = PdfPageFormat.mm;
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(10 * mm),
      build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('${s.name} (=${s.kennzeichen}) – Beschriftungsstreifen, 1 TE = 17,5 mm', style: const pw.TextStyle(fontSize: 9)),
        for (var r = 0; r < streifen.length; r++) ...[
          pw.SizedBox(height: 4 * mm),
          pw.Text('Reihe ${r + 1}', style: const pw.TextStyle(fontSize: 7)),
          pw.Row(children: [
            for (final (_, breite, text) in streifen[r])
              pw.Container(
                width: breite * 17.5 * mm,
                height: 12 * mm,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.3)),
                child: pw.Text(text, style: const pw.TextStyle(fontSize: 6.5), textAlign: pw.TextAlign.center, maxLines: 3),
              ),
          ]),
        ],
      ]),
    ));
    final datei = File(p.join(_s.store!.ordner, 'exporte', 'Beschriftung_${s.kennzeichen}.pdf'));
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(await doc.save());
    if (!mounted) return;
    zeigeHinweis(context, 'Gespeichert: ${datei.path}',
        aktion: SnackBarAction(label: 'Pfad kopieren', onPressed: () => Clipboard.setData(ClipboardData(text: datei.path))));
  }
}

class _SchrankPainter extends CustomPainter {
  _SchrankPainter({
    required this.schrank,
    required this.geraete,
    required this.kreise,
    required this.te,
    required this.reiheH,
    required this.links,
    required this.oben,
    required this.auswahl,
    required this.ziehen,
    this.schienen = const [],
    this.draehte = const [],
    this.anschlussraum = false,
    this.aufbau,
    this.mmPx = 1,
    this.mehr = const {},
    this.rahmen,
  });

  /// Mehrfachauswahl und Auswahlrahmen.
  final Set<String> mehr;
  final Rect? rahmen;
  final Schrank schrank;

  /// Echte Darstellung (null = schematisch).
  final SchrankAufbau? aufbau;
  final double mmPx;

  /// Verdrahtungsansicht: Anschlussraum mit N- und PE-Schiene sowie Kabeleinführungen zeigen.
  final bool anschlussraum;
  static const raumHoehe = 110.0;
  final List<SchrankGeraet> geraete;
  final List<Stromkreis> kreise;
  final double te, reiheH, links, oben;
  final String? auswahl;
  final (String, (int, int))? ziehen;
  final List<Kammschiene> schienen;
  final List<Draht> draehte;

  void _text(Canvas c, String t, Offset p, {double groesse = 10, Color farbe = Colors.black87, double? breite, bool fett = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: groesse, color: farbe, fontWeight: fett ? FontWeight.w600 : null)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: breite ?? double.infinity);
    tp.paint(c, p - Offset(tp.width / 2, 0));
  }

  /// Gehäuse maßstäblich: Außenkontur, Anschlussräume oben/unten, Seitenraum, Einführungen.
  void _gehaeuse(Canvas canvas, SchrankAufbau ab) {
    final s = schrank;
    final innenB = s.teJeReihe * te, innenH = s.reihen * (reiheH + 18).toDouble();
    final g = Rect.fromLTWH(links - ab.seite * mmPx, oben - ab.raumOben * mmPx, innenB + 2 * ab.seite * mmPx,
        innenH + (ab.raumOben + ab.raumUnten) * mmPx);
    canvas.drawRect(g.inflate(6), Paint()..color = const Color(0xFFDEE2E6));
    canvas.drawRect(g, Paint()..color = Colors.white);
    canvas.drawRect(g.inflate(6), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF495057));
    final band = Paint()..color = const Color(0x1A1C7ED6);
    canvas.drawRect(Rect.fromLTRB(g.left, g.top, g.right, oben - 18), band);
    canvas.drawRect(Rect.fromLTRB(g.left, oben + innenH, g.right, g.bottom), band);
    final seite = Paint()..color = const Color(0x142F9E44);
    canvas.drawRect(Rect.fromLTRB(g.left, oben - 18, links - 16, oben + innenH), seite);
    canvas.drawRect(Rect.fromLTRB(links + innenB + 16, oben - 18, g.right, oben + innenH), seite);
    _text(canvas, 'Anschlussraum oben ${ab.raumOben} mm', Offset(g.center.dx, (g.top + oben - 18) / 2 + 10), groesse: 9, farbe: const Color(0xFF1C7ED6));
    _text(canvas, 'Anschlussraum unten ${ab.raumUnten} mm', Offset(g.center.dx, (oben + innenH + g.bottom) / 2 - 20), groesse: 9, farbe: const Color(0xFF1C7ED6));
    if (ab.seite * mmPx > 40) {
      _text(canvas, '${ab.seite} mm', Offset(g.left + ab.seite * mmPx / 2 - 8, oben + innenH / 2), groesse: 9, farbe: const Color(0xFF2F9E44));
    }
    // Einführungen: viele kleine Würgenippel (Kreise) oder breite Ausbrüche (gestrichelt, zum Aufstemmen)
    final ein = Paint()..color = const Color(0xFF868E96);
    final rand = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF495057);
    for (final (n, y) in [(ab.einfuehrungenOben, g.top - 6), (ab.einfuehrungenUnten, g.bottom + 6)]) {
      if (n <= 0) continue;
      if (ab.art == 'ausbruch') {
        final w = ab.einfuehrungBreite * mmPx;
        final frei = (g.width - n * w) / (n + 1);
        for (var i = 0; i < n; i++) {
          final x = g.left + frei * (i + 1) + w * i;
          final r = Rect.fromLTWH(x, y - 6, w, 12);
          canvas.drawRect(r, Paint()..color = const Color(0xFFE9ECEF));
          for (var t = 0.0; t < w; t += 6) {
            canvas.drawLine(Offset(x + t, r.top), Offset(x + math.min(w, t + 3), r.top), rand);
            canvas.drawLine(Offset(x + t, r.bottom), Offset(x + math.min(w, t + 3), r.bottom), rand);
          }
          canvas.drawLine(r.topLeft, r.bottomLeft, rand);
          canvas.drawLine(r.topRight, r.bottomRight, rand);
        }
      } else {
        // Würgenippel/Membranen in Reihen im Gehäuseboden bzw. -deckel (Ø max. 40 mm, üblich M20–M32)
        final d = math.max(6.0, math.min(40, ab.einfuehrungBreite) * mmPx);
        final abstand = d * 0.4;
        final proReihe = math.max(1, ((g.width - 20) / (d + abstand)).floor());
        final oben = y < g.center.dy;
        for (var i = 0; i < n; i++) {
          final reihe = i ~/ proReihe, sp = i % proReihe;
          final x = g.left + 10 + d / 2 + sp * (d + abstand);
          final yy = oben ? g.top + 4 + d / 2 + reihe * (d + abstand) : g.bottom - 4 - d / 2 - reihe * (d + abstand);
          canvas.drawCircle(Offset(x, yy), d / 2, ein);
          canvas.drawCircle(Offset(x, yy), d / 2, rand);
        }
      }
    }
    if (ab.einfuehrungenHinten > 0) {
      _text(canvas, '${ab.einfuehrungenHinten} Einführungen hinten', Offset(g.right - 70, g.top + 18), groesse: 9, farbe: const Color(0xFF495057));
    }
    _text(canvas, 'Außen ${ab.breite ?? (g.width / mmPx).round()} × ${ab.hoehe ?? (g.height / mmPx).round()} mm', Offset(g.center.dx, g.bottom + 14),
        groesse: 9, farbe: BsFarben.textLeise);
  }

  Rect _rect(int reihe, int pos, int breite) => Rect.fromLTWH(links + pos * te, oben + reihe * (reiheH + 18), breite * te, reiheH);

  @override
  void paint(Canvas canvas, Size size) {
    final s = schrank;
    final ab = aufbau;
    if (ab != null) _gehaeuse(canvas, ab);
    // Schrankkasten
    final kasten = Rect.fromLTWH(links - 16, oben - 18, s.teJeReihe * te + 32, s.reihen * (reiheH + 18) + 18 + (anschlussraum ? raumHoehe : 0));
    canvas.drawRRect(RRect.fromRectAndRadius(kasten, const Radius.circular(6)), Paint()..color = const Color(0xFFF1F3F5));
    canvas.drawRRect(
        RRect.fromRectAndRadius(kasten, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFADB5BD));
    final kreisZu = <String, List<Stromkreis>>{};
    for (final k in kreise) {
      if (k.schutzId != null) kreisZu.putIfAbsent(k.schutzId!, () => []).add(k);
    }
    for (var r = 0; r < s.reihen; r++) {
      // Hutschiene und TE-Raster
      final y = oben + r * (reiheH + 18);
      canvas.drawRect(Rect.fromLTWH(links - 6, y + reiheH / 2 - 5, s.teJeReihe * te + 12, 10), Paint()..color = const Color(0xFFCED4DA));
      for (var i = 0; i < s.teJeReihe; i++) {
        canvas.drawRect(
            _rect(r, i, 1).deflate(1),
            Paint()
              ..style = PaintingStyle.stroke
              ..color = const Color(0xFFDEE2E6));
      }
      _text(canvas, '${r + 1}', Offset(links - 28, y + reiheH / 2 - 6), farbe: BsFarben.textLeise);
    }
    for (final g in geraete) {
      var r = _rect(g.reihe, g.position, g.breite);
      final gezogen = ziehen != null && ziehen!.$1 == g.id;
      if (gezogen) r = _rect(ziehen!.$2.$1, ziehen!.$2.$2, g.breite);
      final farbe = geraeteFarbe(g.art);
      final rr = RRect.fromRectAndRadius(r.deflate(1.5), const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..color = Colors.white.withValues(alpha: gezogen ? 0.7 : 1));
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = g.id == auswahl || mehr.contains(g.id) ? 3 : 1.5
            ..color = farbe);
      canvas.drawRect(Rect.fromLTWH(r.left + 2, r.top + 2, r.width - 4, 8), Paint()..color = farbe);
      if (g.phase != null) canvas.drawRect(Rect.fromLTWH(r.left + 2, r.bottom - 6, r.width - 4, 4), Paint()..color = phasenFarbe(g.phase));
      _text(canvas, g.kennzeichen, Offset(r.center.dx, r.top + 12), groesse: 10, fett: true, breite: r.width);
      _text(canvas, g.kurz, Offset(r.center.dx, r.top + 26), groesse: 9, breite: r.width, farbe: farbe);
      // weitere wichtige Daten unten auf dem Gerät
      final extra = [
        if (g.phase != null) g.phase == '3P' ? '3~' : g.phase!,
        if (g.eigenschaften['rcd_typ'] is String) 'Typ ${g.eigenschaften['rcd_typ']}',
        if (g.eigenschaften['schaltvermoegen'] is num) '${g.eigenschaften['schaltvermoegen']} kA',
        if (g.eigenschaften['pa'] is String && (g.eigenschaften['pa'] as String).isNotEmpty) 'PA ${g.eigenschaften['pa']}',
        if (g.eigenschaften['kanaele'] is num) '${g.eigenschaften['kanaele']} K',
      ].join(' · ');
      if (extra.isNotEmpty && reiheH > 60) _text(canvas, extra, Offset(r.center.dx, r.bottom - 20), groesse: 8, breite: r.width - 2, farbe: BsFarben.textLeise);
      final k = kreisZu[g.id];
      if (k != null && reiheH > 70) {
        _text(canvas, k.map((e) => e.bezeichnung.isEmpty ? e.nummer : e.bezeichnung).join(', '), Offset(r.center.dx, r.top + 40),
            groesse: 8, breite: r.width - 2, farbe: BsFarben.textLeise);
      }
    }
    // Kammschienen: Balken über den verbundenen Geräten
    for (final k in schienen) {
      if (k.reihe >= s.reihen) continue;
      final r = _rect(k.reihe, k.von, k.laenge);
      final balken = Rect.fromLTWH(r.left + 2, r.top - 7, r.width - 4, 5);
      canvas.drawRect(balken, Paint()..color = k.einspeisung == null ? const Color(0xFFE03131) : const Color(0xFFB08D57));
      _text(canvas, k.art, Offset(r.left + 12, r.top - 17), groesse: 8, farbe: BsFarben.textLeise);
    }
    // Anschlussraum: N- und PE-Schiene, Kabeleinführungen oben (Zuleitung) und unten (Abgänge)
    final raumOben = oben + s.reihen * (reiheH + 18);
    final yN = raumOben + 30, yPE = raumOben + 62;
    final breiteGesamt = s.teJeReihe * te;
    if (anschlussraum) {
      canvas.drawRect(Rect.fromLTWH(links, raumOben + 4, breiteGesamt, raumHoehe - 14), Paint()..color = const Color(0xFFE9ECEF));
      for (final (y, farbe, name) in [(yN, const Color(0xFF1C7ED6), 'N-Klemmschiene'), (yPE, const Color(0xFF2F9E44), 'PE-Klemmschiene')]) {
        canvas.drawRect(Rect.fromLTWH(links + 20, y - 4, breiteGesamt - 40, 8), Paint()..color = farbe);
        for (var x = links + 26.0; x < links + breiteGesamt - 26; x += 12) {
          canvas.drawCircle(Offset(x, y), 2, Paint()..color = Colors.white);
        }
        _text(canvas, name, Offset(links + breiteGesamt / 2, y + 6), groesse: 9, farbe: farbe);
      }
      // Einführungen
      final einfuehrung = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF495057);
      canvas.drawCircle(Offset(links + 30, oben - 18), 8, einfuehrung);
      _text(canvas, 'Zuleitung', Offset(links + 30, oben - 42), groesse: 9, farbe: BsFarben.textLeise);
      for (var i = 0; i < 6; i++) {
        canvas.drawCircle(Offset(links + 30 + i * (breiteGesamt - 60) / 5, raumOben + raumHoehe), 7, einfuehrung);
      }
      _text(canvas, 'Kabeleinführungen Abgänge', Offset(links + breiteGesamt / 2, raumOben + raumHoehe + 10), groesse: 9, farbe: BsFarben.textLeise);
    }
    // Drähte: vom Ausgang (unten) über den Kanal zum Eingang (oben) bzw. zum Abgang rechts
    final nachId = {for (final g in geraete) g.id: g};
    for (var i = 0; i < draehte.length; i++) {
      final d = draehte[i];
      final a = nachId[d.vonGeraet], b = nachId[d.nachGeraet];
      final versatz = ((i % 7) - 3) * 3.0;
      final farbe = switch (d.leiter) {
        'N' => const Color(0xFF1C7ED6),
        'PE' => const Color(0xFF2F9E44),
        _ => phasenFarbe(d.leiter),
      };
      final stift = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = farbe;
      final rechtsAussen = links + s.teJeReihe * te + 10;
      final start = a == null
          ? (anschlussraum ? Offset(links + 30 + versatz, oben - 10) : Offset(links - 10, oben - 10 + versatz))
          : Offset(_rect(a.reihe, a.position, a.breite).center.dx + versatz, _rect(a.reihe, a.position, a.breite).bottom);
      Offset? zielImRaum;
      if (anschlussraum && b == null && a != null) {
        final x = _rect(a.reihe, a.position, a.breite).center.dx + versatz;
        zielImRaum = switch (d.leiter) {
          'N' => Offset(x, yN),
          'PE' => Offset(x, yPE),
          _ => Offset(x, raumOben + raumHoehe - 6),
        };
      }
      final ende = zielImRaum ??
          (b == null
              ? Offset(rechtsAussen, (a == null ? oben : _rect(a.reihe, 0, 1).bottom + 9) + versatz)
              : Offset(_rect(b.reihe, b.position, b.breite).center.dx + versatz, _rect(b.reihe, b.position, b.breite).top));
      if (zielImRaum != null) {
        // senkrecht im Kanal hinunter in den Anschlussraum
        final seite = links + s.teJeReihe * te + 6 + versatz;
        canvas.drawPath(
            Path()
              ..moveTo(start.dx, start.dy)
              ..lineTo(start.dx, start.dy + 9)
              ..lineTo(seite, start.dy + 9)
              ..lineTo(seite, zielImRaum.dy - 12)
              ..lineTo(zielImRaum.dx, zielImRaum.dy - 12)
              ..lineTo(zielImRaum.dx, zielImRaum.dy),
            stift);
        continue;
      }
      final kanalA = a == null ? start.dy : start.dy + 9 + versatz.abs() / 2;
      final kanalB = b == null ? ende.dy : ende.dy - 9 - versatz.abs() / 2;
      final pfad = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(start.dx, kanalA);
      if (b != null && a != null && b.reihe > a.reihe) {
        // senkrecht im seitlichen Kanal nach unten
        final seite = links - 8 + versatz;
        pfad
          ..lineTo(seite, kanalA)
          ..lineTo(seite, kanalB)
          ..lineTo(ende.dx, kanalB);
      } else {
        pfad.lineTo(ende.dx, kanalA);
        if (b != null) pfad.lineTo(ende.dx, kanalB);
      }
      pfad.lineTo(ende.dx, ende.dy);
      canvas.drawPath(pfad, stift);
    }
    final rr = rahmen;
    if (rr != null) {
      canvas.drawRect(rr, Paint()..color = BsFarben.akzent.withValues(alpha: 0.08));
      canvas.drawRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..color = BsFarben.akzent);
    }
  }

  @override
  bool shouldRepaint(covariant _SchrankPainter old) => true;
}

/// Einpoliges Übersichtsschaltbild: Einspeisung, Hauptschalter, FI-Gruppen
/// mit ihren Leitungsschutzschaltern und Stromkreisen.
class _UebersichtPainter extends CustomPainter {
  _UebersichtPainter({required this.schrank, required this.geraete, required this.kreise});
  final Schrank schrank;
  final List<SchrankGeraet> geraete;
  final List<Stromkreis> kreise;

  static const abstand = 90.0;

  static Size groesse(List<SchrankGeraet> geraete) {
    final n = geraete.where((g) => g.art == GeraeteArt.ls || g.art == GeraeteArt.fils || g.art == GeraeteArt.spd).length;
    return Size(math.max(800, 160 + (n + geraete.where((g) => g.art == GeraeteArt.rcd).length) * abstand), 560);
  }

  void _text(Canvas c, String t, Offset p, {double groesse = 10, Color farbe = Colors.black87, bool mitte = true}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: groesse, color: farbe)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: abstand - 6);
    tp.paint(c, mitte ? p - Offset(tp.width / 2, 0) : p);
  }

  void _schalter(Canvas c, Offset oben, Color f, String art) {
    // Schaltzeichen vereinfacht: Strich mit Schrägkontakt und Kästchen
    final st = Paint()
      ..color = f
      ..strokeWidth = 1.5;
    c.drawLine(oben, oben + const Offset(0, 14), st);
    c.drawLine(oben + const Offset(0, 14), oben + const Offset(10, 30), st);
    c.drawLine(oben + const Offset(0, 32), oben + const Offset(0, 46), st);
    final r = Rect.fromCenter(center: oben + const Offset(0, 23), width: 18, height: 10);
    if (art == 'rcd') c.drawOval(r.inflate(4), st..style = PaintingStyle.stroke);
    if (art == 'ls') c.drawRect(Rect.fromLTWH(oben.dx - 9, oben.dy + 16, 6, 10), st..style = PaintingStyle.stroke);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final st = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2;
    final s = schrank;
    _text(canvas, '${s.name}  =${s.kennzeichen}  – Übersichtsschaltbild (einpolig)', const Offset(20, 12), groesse: 13, mitte: false);
    // Einspeisung
    const x0 = 60.0, yBus = 140.0;
    canvas.drawLine(const Offset(x0, 40), const Offset(x0, 70), st);
    _text(canvas, 'Einspeisung', const Offset(x0, 44 - 14), groesse: 9);
    final haupt = geraete.where((g) => g.art == GeraeteArt.hauptschalter).firstOrNull;
    if (haupt != null) {
      _schalter(canvas, const Offset(x0, 70), Colors.black87, 'haupt');
      _text(canvas, '${haupt.kennzeichen}\n${haupt.kurz}', const Offset(x0 + 40, 80), groesse: 9);
    } else {
      canvas.drawLine(const Offset(x0, 70), const Offset(x0, 116), st);
    }
    canvas.drawLine(const Offset(x0, 116), const Offset(x0, yBus), st);
    final kreisZu = <String, List<Stromkreis>>{};
    for (final k in kreise) {
      if (k.schutzId != null) kreisZu.putIfAbsent(k.schutzId!, () => []).add(k);
    }
    // Gruppen: je RCD seine LS, danach LS ohne RCD, FI/LS, SPD
    final rcds = [
      for (final g in geraete)
        if (g.art == GeraeteArt.rcd) g
    ]..sort((a, b) => (a.reihe * 100 + a.position).compareTo(b.reihe * 100 + b.position));
    final ohne = [
      for (final g in geraete)
        if ((g.art == GeraeteArt.ls && !rcds.any((r) => r.id == g.vorgeschaltetId)) || g.art == GeraeteArt.fils || g.art == GeraeteArt.spd)
          g
    ];
    var x = x0 + 40;
    void abgang(SchrankGeraet g, double xa, double yOben) {
      final f = g.art == GeraeteArt.spd ? const Color(0xFFE67700) : Colors.black87;
      canvas.drawLine(Offset(xa, yOben), Offset(xa, yOben + 20), st..color = f);
      _schalter(canvas, Offset(xa, yOben + 20), f, g.art == GeraeteArt.spd ? 'spd' : 'ls');
      canvas.drawLine(Offset(xa, yOben + 66), Offset(xa, yOben + 120), st..color = f);
      _text(canvas, '${g.kennzeichen}\n${g.kurz}${g.phase == null ? '' : '\n${g.phase}'}', Offset(xa + 26, yOben + 24), groesse: 8);
      final k = kreisZu[g.id];
      final t =
          k == null ? (g.bezeichnung.isEmpty ? '' : g.bezeichnung) : k.map((e) => '${e.nummer} ${e.bezeichnung}\n${e.leitung}').join('\n');
      _text(canvas, t, Offset(xa, yOben + 126), groesse: 8);
      st.color = Colors.black87;
    }

    final ende = x;
    for (final r in rcds) {
      final ls = [
        for (final g in geraete)
          if (g.art == GeraeteArt.ls && g.vorgeschaltetId == r.id) g
      ];
      final breite = math.max(1, ls.length) * abstand;
      final xr = x + breite / 2 - abstand / 2 + abstand / 2;
      canvas.drawLine(Offset(xr, yBus), Offset(xr, yBus + 16), st);
      _schalter(canvas, Offset(xr, yBus + 16), const Color(0xFF1C7ED6), 'rcd');
      _text(canvas, '${r.kennzeichen}\n${r.kurz}', Offset(xr + 40, yBus + 18), groesse: 8, farbe: const Color(0xFF1C7ED6));
      const yGruppe = yBus + 90;
      canvas.drawLine(Offset(xr, yBus + 62), Offset(xr, yGruppe), st);
      if (ls.isNotEmpty) {
        canvas.drawLine(Offset(x + abstand / 2, yGruppe), Offset(x + breite - abstand / 2, yGruppe), st);
      }
      for (var i = 0; i < ls.length; i++) {
        abgang(ls[i], x + abstand / 2 + i * abstand, yGruppe);
      }
      x += breite + 20;
    }
    for (final g in ohne) {
      abgang(g, x + abstand / 2, yBus);
      x += abstand;
    }
    // Sammelschiene
    canvas.drawLine(const Offset(x0, yBus), Offset(math.max(ende, x - abstand / 2), yBus), st..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant _UebersichtPainter old) => true;
}

/// Gehäuseaufbau eines Schranks für die echte Darstellung (mm).
class SchrankAufbau {
  const SchrankAufbau({
    this.raumOben = 100,
    this.raumUnten = 100,
    this.seite = 75,
    this.einfuehrungenOben = 4,
    this.einfuehrungenUnten = 6,
    this.einfuehrungBreite = 60,
    this.breite,
    this.hoehe,
    this.art = 'nippel',
    this.einfuehrungenHinten = 0,
  });
  final int raumOben, raumUnten, seite, einfuehrungenOben, einfuehrungenUnten, einfuehrungBreite;

  /// Art der Einführungen: 'nippel' (viele kleine Würgenippel/Membranen) oder 'ausbruch' (breite Ausbrüche zum Aufstemmen).
  final String art;
  final int einfuehrungenHinten;
  final int? breite, hoehe;

  static SchrankAufbau aus(Map<String, dynamic> eig) {
    final a = Map<String, dynamic>.from(eig['aufbau'] as Map? ?? const {});
    final aussen = Map<String, dynamic>.from(eig['aussen'] as Map? ?? const {});
    int z(String k, int v) => (a[k] as num?)?.toInt() ?? v;
    return SchrankAufbau(
      raumOben: z('raum_oben', 100),
      raumUnten: z('raum_unten', 100),
      seite: z('seite', 75),
      einfuehrungenOben: z('einf_oben', 4),
      einfuehrungenUnten: z('einf_unten', 6),
      einfuehrungBreite: z('einf_breite', 60),
      breite: (aussen['breite'] as num?)?.toInt(),
      hoehe: (aussen['hoehe'] as num?)?.toInt(),
      art: a['art'] as String? ?? 'nippel',
      einfuehrungenHinten: z('einf_hinten', 0),
    );
  }
}
