import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/symbole.dart';
import '../app/theme.dart';
import '../data/models.dart';
import '../data/project_store.dart';
import '../state/app_state.dart';
import 'decke/decke_page.dart';
import 'dialogs.dart';
import 'widgets.dart';

/// Projektbaum als aufklappbare Liste: Gebäude → Geschoss → Raum → Gewerk →
/// Gerätetyp → einzelne Geräte. Ein Klick auf ein Gerät wählt es in der
/// Installation an.
class ProjectTree extends StatefulWidget {
  const ProjectTree({super.key, required this.state});

  final AppState state;

  @override
  State<ProjectTree> createState() => _ProjectTreeState();
}

class _ProjectTreeState extends State<ProjectTree> {
  final Set<String> _offen = {};
  bool _erstesMal = true;

  /// Mehrfachauswahl von Räumen (Strg/Umschalt-Klick).
  final Set<String> _raumMarkiert = {};
  String? _letzterRaum;

  AppState get state => widget.state;

  bool _istOffen(String k) => _offen.contains(k);
  void _umschalten(String k) => setState(() => _offen.contains(k) ? _offen.remove(k) : _offen.add(k));

  @override
  Widget build(BuildContext context) {
    final ProjectStore store = state.store!;
    if (_erstesMal) {
      _erstesMal = false;
      for (final geb in store.gebaeude()) {
        _offen.add('geb:${geb.id}');
      }
      if (state.geschossId != null) _offen.add('g:${state.geschossId}');
      if (state.raumId != null) _offen.add('r:${state.raumId}');
    }
    final gewerke = {for (final g in store.gewerke()) g.id: g};
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final alle = store.alleObjekte();
    final eintraege = <Widget>[];

    void objekteEinfuegen(String schluessel, List<Objekt> objekte, int einzug) {
      final nachGewerk = <String, List<Objekt>>{};
      for (final o in objekte) {
        nachGewerk.putIfAbsent(typen[o.typId]?.gewerkId ?? '', () => []).add(o);
      }
      final reihenfolge = nachGewerk.keys.toList()..sort((a, b) => (gewerke[a]?.name ?? '').compareTo(gewerke[b]?.name ?? ''));
      for (final gid in reihenfolge) {
        final gw = gewerke[gid];
        final kg = '$schluessel|gw:$gid';
        final liste = nachGewerk[gid]!;
        eintraege.add(_zeile(
          text: gw?.name ?? 'Sonstiges',
          einzug: einzug,
          offen: _istOffen(kg),
          aufklappbar: true,
          farbe: gw == null ? null : Color(gw.farbe),
          nebentext: '${liste.length}',
          onTap: () => _umschalten(kg),
        ));
        if (!_istOffen(kg)) continue;
        final nachTyp = <String, List<Objekt>>{};
        for (final o in liste) {
          nachTyp.putIfAbsent(o.typId, () => []).add(o);
        }
        final typReihe = nachTyp.keys.toList()..sort((a, b) => (typen[a]?.name ?? '').compareTo(typen[b]?.name ?? ''));
        for (final tid in typReihe) {
          final t = typen[tid];
          final kt = '$kg|t:$tid';
          final objekte = nachTyp[tid]!..sort((a, b) => a.kennung.compareTo(b.kennung));
          eintraege.add(_zeile(
            text: t == null ? '?' : '${t.name} (${t.kuerzel})',
            einzug: einzug + 1,
            offen: _istOffen(kt),
            aufklappbar: true,
            nebentext: '${objekte.length}',
            onTap: () => _umschalten(kt),
          ));
          if (!_istOffen(kt)) continue;
          for (final o in objekte) {
            final laenge = o.punkte.length >= 2 ? ' · ${(o.laenge / 1000).toStringAsFixed(1).replaceAll('.', ',')} m' : '';
            eintraege.add(_zeile(
              text: o.kennung,
              einzug: einzug + 2,
              aktiv: state.objektAuswahl == o.id,
              nebentext: '${o.status.label}$laenge',
              klein: true,
              onTap: () {
                state.geschossWaehlen(o.geschossId);
                if (o.raumId != null) state.raumWaehlen(o.raumId);
                state.objektAuswahl = o.id;
                state.markiert = {o.id};
                if (state.modul != Modul.installation) {
                  state.modulWaehlen(Modul.installation);
                } else {
                  state.geaendert();
                }
              },
            ));
          }
        }
      }
    }

    for (final geb in store.gebaeude()) {
      final kb = 'geb:${geb.id}';
      eintraege.add(_zeile(
        text: geb.name,
        einzug: 0,
        fett: true,
        aufklappbar: true,
        offen: _istOffen(kb),
        onTap: () => _umschalten(kb),
        aktion: IconButton(
          tooltip: 'Geschoss hinzufügen',
          icon: const Icon(Icons.add, size: 18),
          onPressed: () async {
            if (await geschossDialog(context, store, geb.id)) state.geaendert();
          },
        ),
      ));
      if (!_istOffen(kb)) continue;
      for (final g in store.geschosse(geb.id)) {
        final kgs = 'g:${g.id}';
        final aktiv = state.geschossId == g.id && state.raumId == null;
        eintraege.add(_zeile(
          text: '${g.kuerzel} · ${g.name}',
          einzug: 1,
          aktiv: aktiv,
          aufklappbar: true,
          offen: _istOffen(kgs),
          onPfeil: () => _umschalten(kgs),
          onTap: () {
            state.geschossWaehlen(g.id);
            _offen.add(kgs);
          },
          aktion: IconButton(
            tooltip: 'Raum hinzufügen',
            icon: const Icon(Icons.add, size: 18),
            onPressed: () async {
              if (await raumDialog(context, store, g) != null) state.geaendert();
            },
          ),
        ));
        if (!_istOffen(kgs)) continue;
        final raeume = store.raeume(g.id);
        for (final r in raeume) {
          final kr = 'r:${r.id}';
          final imRaum = [for (final o in alle) if (o.raumId == r.id) o];
          eintraege.add(_zeile(
            text: r.name,
            einzug: 2,
            aktiv: state.raumId == r.id,
            aufklappbar: imRaum.isNotEmpty,
            offen: _istOffen(kr),
            markierung: r.hatEigeneHoehen ? 'eigene Höhen' : null,
            nebentext: r.flaeche == null ? null : flaecheText(r.flaeche!),
            onPfeil: () => _umschalten(kr),
            aktion: state.raumId == r.id && r.umriss != null
                ? IconButton(
                    tooltip: 'Deckenansicht',
                    icon: const Icon(Sym.decke, size: 18),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DeckePage(state: state, raumId: r.id))),
                  )
                : null,
            markiert: _raumMarkiert.contains(r.id),
            onTap: () {
              final strg = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
              final umschalt = HardwareKeyboard.instance.isShiftPressed;
              setState(() {
                if (umschalt && _letzterRaum != null) {
                  final ids = [for (final x in raeume) x.id];
                  final a = ids.indexOf(_letzterRaum!), b = ids.indexOf(r.id);
                  if (a >= 0 && b >= 0) _raumMarkiert.addAll(ids.sublist(a < b ? a : b, (a < b ? b : a) + 1));
                } else if (strg) {
                  if (_raumMarkiert.isEmpty && state.raumId != null && state.raumId != r.id) _raumMarkiert.add(state.raumId!);
                  _raumMarkiert.contains(r.id) ? _raumMarkiert.remove(r.id) : _raumMarkiert.add(r.id);
                } else {
                  _raumMarkiert.clear();
                }
                _letzterRaum = r.id;
              });
              state.geschossWaehlen(g.id);
              state.raumWaehlen(r.id);
            },
          ));
          if (_istOffen(kr)) objekteEinfuegen(kr, imRaum, 3);
        }
        final ohne = [for (final o in alle) if (o.geschossId == g.id && (o.raumId == null || !raeume.any((r) => r.id == o.raumId))) o];
        if (ohne.isNotEmpty) {
          final ko = 'ohne:${g.id}';
          eintraege.add(_zeile(
            text: 'ohne Raum',
            einzug: 2,
            aufklappbar: true,
            offen: _istOffen(ko),
            nebentext: '${ohne.length}',
            onTap: () => _umschalten(ko),
          ));
          if (_istOffen(ko)) objekteEinfuegen(ko, ohne, 3);
        }
      }
    }
    eintraege.add(Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextButton.icon(
        onPressed: () async {
          final name = await texteingabe(context, titel: 'Neues Gebäude', feld: 'Name', vorschlag: 'Garage');
          if (name != null && name.trim().isNotEmpty) {
            store.gebaeudeAnlegen(name.trim());
            state.geaendert();
          }
        },
        icon: const Icon(Icons.add_home_outlined, size: 18),
        label: const Text('Gebäude'),
      ),
    ));

    final markiert = _raumMarkiert.length;
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: BsFarben.rand)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 8),
            child: Row(children: [
              const Expanded(
                child: Text('PROJEKT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: BsFarben.textLeise)),
              ),
              IconButton(
                tooltip: 'Alles zuklappen',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () => setState(() => _offen.removeWhere((k) => !k.startsWith('geb:'))),
                icon: const Icon(Icons.unfold_less),
              ),
            ]),
          ),
          if (markiert > 1)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: BsFarben.akzentHell, borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Expanded(child: Text('$markiert Räume markiert', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                IconButton(
                  tooltip: 'Markierte Räume löschen (Wände bleiben)',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _markierteLoeschen(store),
                ),
                IconButton(
                  tooltip: 'Markierung aufheben',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(_raumMarkiert.clear),
                ),
              ]),
            ),
          ...eintraege,
        ],
      ),
    );
  }

  Future<void> _markierteLoeschen(ProjectStore store) async {
    final n = _raumMarkiert.length;
    final ok = await frage(context, titel: '$n Räume löschen?', text: 'Die Räume verschwinden aus der Liste, die Wände bleiben stehen. Die Flächen lassen sich wieder als Räume zuordnen.', ja: 'Löschen');
    if (!ok) return;
    final ids = _raumMarkiert.toList();
    for (final id in ids) {
      store.raumLoeschen(id);
    }
    _raumMarkiert.clear();
    state.raumWaehlen(null);
    state.geaendert();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$n Räume gelöscht'),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () {
          for (final id in ids) {
            store.raumWiederherstellen(id);
          }
          state.geaendert();
        },
      ),
    ));
  }

  Widget _zeile({
    required String text,
    required int einzug,
    bool aktiv = false,
    bool markiert = false,
    bool fett = false,
    bool aufklappbar = false,
    bool offen = false,
    bool klein = false,
    Color? farbe,
    String? markierung,
    String? nebentext,
    VoidCallback? onTap,
    VoidCallback? onPfeil,
    Widget? aktion,
  }) {
    return Material(
      color: aktiv || markiert ? BsFarben.akzentHell : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(left: 2.0 + einzug * 12, right: 2),
          child: SizedBox(
            height: klein ? 28 : 34,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: aufklappbar
                      ? InkWell(
                          onTap: onPfeil ?? onTap,
                          child: Icon(offen ? Icons.expand_more : Icons.chevron_right, size: 18, color: BsFarben.textLeise),
                        )
                      : null,
                ),
                if (farbe != null) ...[Container(width: 10, height: 10, color: farbe), const SizedBox(width: 6)],
                Expanded(
                  child: Text(
                    text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: klein ? 12 : 13,
                      fontWeight: fett || aktiv ? FontWeight.w600 : FontWeight.w400,
                      color: aktiv ? BsFarben.akzentDunkel : null,
                    ),
                  ),
                ),
                if (nebentext != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 4),
                    child: Text(nebentext, style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
                  ),
                if (markierung != null)
                  Tooltip(
                    message: markierung,
                    child: const Icon(Icons.height, size: 16, color: BsFarben.akzentDunkel),
                  ),
                if (aktion != null) aktion,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
