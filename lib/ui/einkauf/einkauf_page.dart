import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/auslegung.dart';
import '../../core/auslegung_projekt.dart';
import '../../core/auswertung.dart';
import '../../core/einkaufslisten.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';
import '../../state/app_state.dart';
import '../bauteile/einkauf_dialog.dart';
import '../widgets.dart';

/// Was laut Planung noch zu beschaffen ist (Besorgungsliste, Kabel-/Rohrliste,
/// Material-Kostenpositionen), als Listenpositionen.
List<ListenPosition> nochZuBeschaffen(AppState s) {
  final store = s.store!;
  double r1(double v) => (v * 10).ceil() / 10;
  final aus = <ListenPosition>[
    for (final r in besorgungsliste(s))
      if (r.bedarf > r.bestand + 1e-9)
        ListenPosition(
          schluessel: 'e:${r.element.id}',
          text: r.element.anzeige,
          menge: r1(r.bedarf - r.bestand),
          einheit: r.einheit,
          herkunft: r.herkunft,
          haendler: elementHaendler(r.element) == 'ohne Händler' ? '' : elementHaendler(r.element),
        ),
  ];
  final v = auslegungVorgaben(store);
  final gekauft = leitungGekauft(store);
  for (final l in leitungsliste(leitungsStuecke(store, name: (id) => s.bibliothek.fuerProjekt(store, id)?.anzeige))) {
    final m = l.einkauf(v.zuschlag) - (gekauft[leitungSchluessel(l)] ?? 0);
    if (m <= 0) continue;
    aus.add(ListenPosition(schluessel: 'l:${leitungSchluessel(l)}', text: l.bezeichnung, menge: m.ceilToDouble(), einheit: 'm', herkunft: 'Kabel-/Rohrliste · ${l.art}'));
  }
  for (final e in einkaufsliste(store.kostenpositionen(), store.produkte()).entries) {
    for (final x in e.value) {
      aus.add(ListenPosition(
        schluessel: 'k:${x.position.id}',
        text: x.position.text,
        menge: x.menge,
        einheit: x.position.einheit,
        herkunft: 'Kostenliste',
        haendler: e.key == 'ohne Händler' ? '' : e.key,
      ));
    }
  }
  return aus;
}

/// Gekauft buchen (oder zurücknehmen): Bestand, gekaufte Meter bzw. Status
/// der Kostenposition – genauso wie beim Abhaken auf dem iPhone.
void einkaufBuchen(ProjectStore store, ListenPosition p, bool gekauft) {
  final k = p.schluessel;
  final id = k.substring(2);
  switch (k.substring(0, 2)) {
    case 'e:':
      final alt = bestandLesen(store)[id] ?? 0;
      bestandSetzen(store, id, alt + (gekauft ? p.menge : -p.menge));
    case 'l:':
      final alt = leitungGekauft(store)[id] ?? 0;
      leitungGekauftSetzen(store, id, alt + (gekauft ? p.menge : -p.menge));
    case 'k:':
      store.kostenpositionAendern(id, {'status': gekauft ? KostenStatus.geliefert.name : KostenStatus.geplant.name});
  }
}

/// Seite „Einkauf“: links was noch zu beschaffen ist, rechts die Einkäufe
/// (benannte Listen) – abhaken, von Hand ergänzen, aufs iPhone, Kassenzettel.
class EinkaufPage extends StatefulWidget {
  const EinkaufPage({super.key, required this.state});
  final AppState state;

  @override
  State<EinkaufPage> createState() => _EinkaufPageState();
}

class _EinkaufPageState extends State<EinkaufPage> {
  final _gewaehlt = <String>{};
  bool _nurOhneListe = false;
  String _suche = '';
  final _manuell = <String, TextEditingController>{};

  AppState get _s => widget.state;
  ProjectStore get _store => _s.store!;
  List<Einkaufsliste> _listen() => listenLesen((k) => _store.einstellung<Object>(k));
  void _speichern(List<Einkaufsliste> l) {
    listenSchreiben((k, v) => _store.einstellungSetzen(k, v), l);
    _s.geaendert();
    setState(() {});
  }

  String _z(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

  @override
  void dispose() {
    for (final c in _manuell.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _nameFragen({String titel = 'Neuer Einkauf', String vorgabe = ''}) async {
    final c = TextEditingController(text: vorgabe);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(titel),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'z. B. Bauhaus Samstag, Elektro-Großhandel'),
          onSubmitted: (_) => Navigator.pop(d, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('OK')),
        ],
      ),
    );
    final t = c.text.trim();
    c.dispose();
    return ok == true && t.isNotEmpty ? t : null;
  }

  Future<String?> _neueListe() async {
    final d = DateTime.now();
    final name = await _nameFragen(vorgabe: 'Einkauf ${d.day}.${d.month}.');
    if (name == null) return null;
    final l = _listen()..add(Einkaufsliste(id: neueListenId(), name: name, erstellt: DateTime.now()));
    _speichern(l);
    return l.last.id;
  }

  Future<void> _inListe(String? listeId, List<ListenPosition> pos) async {
    final id = listeId ?? await _neueListe();
    if (id == null) return;
    final l = _listen();
    inListeLegen(l, id, pos);
    _gewaehlt.clear();
    _speichern(l);
  }

  void _abhaken(Einkaufsliste liste, ListenPosition pos, bool ok) {
    final l = _listen();
    final x = l.firstWhere((e) => e.id == liste.id);
    final q = x.positionen.firstWhere((e) => e.schluessel == pos.schluessel);
    if (q.abgehakt == ok) return;
    q.abgehakt = ok;
    einkaufBuchen(_store, q, ok);
    _speichern(l);
  }

  Future<void> _kassenzettel(Einkaufsliste liste) async {
    final vorher = einkaeufeLesen(_store).map((e) => e.id).toSet();
    final n = await showDialog<int>(context: context, builder: (_) => EinkaufDialog(state: _s));
    final neu = einkaeufeLesen(_store).where((e) => !vorher.contains(e.id)).toList();
    if (neu.isEmpty) return;
    final l = _listen();
    final x = l.firstWhere((e) => e.id == liste.id);
    x.einkaufId = neu.last.id;
    x.beleg = neu.last.beleg ?? x.beleg;
    _speichern(l);
    if (mounted) zeigeHinweis(context, 'Kassenzettel mit „${x.name}“ verknüpft${n == null ? '' : ' ($n Positionen)'}');
  }

  Future<void> _zettel(Einkaufsliste liste) async {
    final f = File(p.join(_store.ordner, 'exporte', 'Einkauf ${liste.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.html'));
    await f.parent.create(recursive: true);
    await f.writeAsString(einkaufszettelHtml(liste));
    if (mounted) zeigeHinweis(context, 'Gespeichert unter ${f.path}');
  }

  @override
  Widget build(BuildContext context) {
    final listen = _listen();
    final offen = [for (final l in listen) if (!l.erledigt) l];
    final fertig = [for (final l in listen) if (l.erledigt) l];
    final zu = zuordnung(listen);
    final alle = nochZuBeschaffen(_s);
    final sichtbar = [
      for (final x in alle)
        if ((!_nurOhneListe || !zu.containsKey(x.schluessel)) && (_suche.isEmpty || x.text.toLowerCase().contains(_suche))) x
    ];
    final gruppen = <String, List<ListenPosition>>{};
    for (final x in sichtbar) {
      gruppen.putIfAbsent(x.herkunft.split(',').first.split('·').first.trim().isEmpty ? 'Sonstiges' : x.herkunft.split(',').first.split('·').first.trim(), () => []).add(x);
    }
    final gewaehlt = [for (final x in alle) if (_gewaehlt.contains(x.schluessel)) x];
    final belege = belegeOffen(_store).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Row(children: [
          const Icon(Icons.shopping_cart_outlined, color: BsFarben.akzentDunkel),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Einkauf', style: Theme.of(context).textTheme.titleLarge),
              const Text('Links steht, was laut Planung noch fehlt. Auswählen und einem Einkauf zuordnen – der Einkauf erscheint auf dem iPhone '
                  'unter Einkauf und lässt sich dort abhaken. Abhaken = gekauft (Bestand steigt).', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            ]),
          ),
          if (belege > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(avatar: const Icon(Icons.receipt_long, size: 16), label: Text('$belege Kassenbon(s) vom Handy')),
            ),
          FilledButton.tonalIcon(
            onPressed: () async {
              await showDialog<int>(context: context, builder: (_) => EinkaufDialog(state: _s));
              setState(() {});
            },
            icon: const Icon(Icons.receipt_long, size: 18),
            label: const Text('Kassenzettel erfassen …'),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ------------------------------------------------ links: noch zu beschaffen
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Noch zu beschaffen (${alle.length})', style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'suchen'),
                      onChanged: (v) => setState(() => _suche = v.trim().toLowerCase()),
                    ),
                  ),
                  FilterChip(label: const Text('nur ohne Einkauf'), selected: _nurOhneListe, onSelected: (v) => setState(() => _nurOhneListe = v)),
                  TextButton(
                    onPressed: () => setState(() => _gewaehlt
                      ..clear()
                      ..addAll([for (final x in sichtbar) if (!zu.containsKey(x.schluessel)) x.schluessel])),
                    child: const Text('Alle ohne Einkauf wählen'),
                  ),
                ]),
              ),
              if (gewaehlt.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: BsFarben.akzentHell.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
                  child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${gewaehlt.length} ausgewählt', style: const TextStyle(fontWeight: FontWeight.w600)),
                    PopupMenuButton<String>(
                      tooltip: 'Einem Einkauf zuordnen',
                      onSelected: (id) => _inListe(id == '' ? null : id, gewaehlt),
                      itemBuilder: (_) => [
                        for (final l in offen) PopupMenuItem(value: l.id, child: Text('zu „${l.name}“')),
                        const PopupMenuItem(value: '', child: Text('Neuer Einkauf …')),
                      ],
                      child: const Chip(avatar: Icon(Icons.playlist_add, size: 18), label: Text('Zu Einkauf hinzufügen ▾')),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        for (final x in gewaehlt) {
                          einkaufBuchen(_store, x, true);
                        }
                        _gewaehlt.clear();
                        _s.geaendert();
                        setState(() {});
                        zeigeHinweis(context, 'Als gekauft gebucht (Bestand erhöht).');
                      },
                      icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                      label: const Text('Schon gekauft'),
                    ),
                    TextButton(onPressed: () => setState(_gewaehlt.clear), child: const Text('Auswahl aufheben')),
                  ]),
                ),
              Expanded(
                child: alle.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Laut Planung fehlt nichts. Die Liste füllt sich aus Produkten an Objekten/Öffnungen (Bibliothek), '
                              'der Kabel-/Rohrliste, den Oberflächen und den Material-Kostenpositionen.',
                              textAlign: TextAlign.center, style: TextStyle(color: BsFarben.textLeise)),
                        ),
                      )
                    : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                        for (final g in gruppen.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                            child: Text(g.key.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: BsFarben.textLeise)),
                          ),
                          for (final x in g.value)
                            CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _gewaehlt.contains(x.schluessel),
                              onChanged: (v) => setState(() => v == true ? _gewaehlt.add(x.schluessel) : _gewaehlt.remove(x.schluessel)),
                              title: Text(x.text),
                              subtitle: Text([x.herkunft, if (x.haendler.isNotEmpty) x.haendler].join(' · '), style: const TextStyle(fontSize: 11)),
                              secondary: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (zu[x.schluessel] case final n?)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Chip(visualDensity: VisualDensity.compact, label: Text(n, style: const TextStyle(fontSize: 11))),
                                  ),
                                Text('${_z(x.menge)} ${x.einheit}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ]),
                            ),
                        ],
                      ]),
              ),
            ]),
          ),
          // ------------------------------------------------ rechts: Einkäufe
          Material(
            color: Colors.white,
            shape: const Border(left: BorderSide(color: BsFarben.rand)),
            child: SizedBox(
            width: 440,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Row(children: [
                Expanded(child: Text('Einkäufe', style: Theme.of(context).textTheme.titleMedium)),
                FilledButton.icon(onPressed: _neueListe, icon: const Icon(Icons.add, size: 18), label: const Text('Neuer Einkauf')),
              ]),
              const SizedBox(height: 4),
              const Text('Jeder offene Einkauf steht auf dem iPhone unter „Einkauf“ (Gruppierung „Einkauf“). Abhaken dort kommt beim nächsten Abgleich hier an.',
                  style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
              const SizedBox(height: 8),
              if (offen.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Noch kein Einkauf. Links Positionen wählen und „Zu Einkauf hinzufügen“.')),
              for (final l in offen) _liste(l),
              if (fertig.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Erledigte Einkäufe (${fertig.length})'),
                  children: [for (final l in fertig.reversed) _liste(l)],
                ),
            ]),
          ),
          ),
        ]),
      ),
    ]);
  }

  Widget _liste(Einkaufsliste l) {
    final c = _manuell.putIfAbsent(l.id, TextEditingController.new);
    final ok = l.positionen.where((x) => x.abgehakt).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(l.erledigt ? Icons.check_circle : Icons.shopping_basket_outlined, size: 18, color: l.erledigt ? const Color(0xFF2F9E44) : BsFarben.akzentDunkel),
            const SizedBox(width: 6),
            Expanded(child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('$ok/${l.positionen.length}', style: const TextStyle(color: BsFarben.textLeise)),
            PopupMenuButton<String>(
              onSelected: (a) async {
                final alle = _listen();
                final x = alle.firstWhere((e) => e.id == l.id);
                switch (a) {
                  case 'umbenennen':
                    final n = await _nameFragen(titel: 'Einkauf umbenennen', vorgabe: l.name);
                    if (n == null) return;
                    x.name = n;
                  case 'fertig':
                    x.erledigt = !x.erledigt;
                  case 'loeschen':
                    if (!mounted) return;
                    if (!await frage(context, titel: 'Einkauf „${l.name}“ löschen?', text: 'Gebuchte Mengen (Bestand) bleiben, nur die Liste verschwindet.', ja: 'Löschen')) return;
                    alle.removeWhere((e) => e.id == l.id);
                }
                _speichern(alle);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'umbenennen', child: Text('Umbenennen …')),
                PopupMenuItem(value: 'fertig', child: Text(l.erledigt ? 'Wieder öffnen' : 'Als erledigt ablegen')),
                const PopupMenuItem(value: 'loeschen', child: Text('Löschen …')),
              ],
            ),
          ]),
          if (l.positionen.isEmpty) const Text('leer', style: TextStyle(color: BsFarben.textLeise)),
          for (final x in l.positionen)
            Row(children: [
              Checkbox(value: x.abgehakt, onChanged: l.erledigt ? null : (v) => _abhaken(l, x, v == true)),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: x.text, style: TextStyle(decoration: x.abgehakt ? TextDecoration.lineThrough : null)),
                    if (x.manuell) const TextSpan(text: '  (von Hand)', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
                  ]),
                ),
              ),
              Text('${_z(x.menge)} ${x.einheit}', style: const TextStyle(fontSize: 12)),
              if (!l.erledigt)
                IconButton(
                  tooltip: 'Aus diesem Einkauf nehmen',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    final alle = _listen();
                    alle.firstWhere((e) => e.id == l.id).positionen.removeWhere((q) => q.schluessel == x.schluessel);
                    _speichern(alle);
                  },
                ),
            ]),
          if (!l.erledigt)
            Row(children: [
              Expanded(
                child: TextField(
                  controller: c,
                  decoration: const InputDecoration(isDense: true, hintText: 'Von Hand ergänzen, z. B. „2 Kartuschen Silikon weiß“'),
                  onSubmitted: (_) => _manuellDazu(l, c),
                ),
              ),
              IconButton(tooltip: 'Hinzufügen', onPressed: () => _manuellDazu(l, c), icon: const Icon(Icons.add)),
            ]),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            TextButton.icon(onPressed: () => _zettel(l), icon: const Icon(Icons.checklist, size: 16), label: const Text('Einkaufszettel')),
            TextButton.icon(
              onPressed: () => _kassenzettel(l),
              icon: Icon(l.einkaufId == null ? Icons.receipt_long_outlined : Icons.receipt_long, size: 16),
              label: Text(l.einkaufId == null ? 'Kassenzettel …' : 'Kassenzettel verknüpft'),
            ),
            if (!l.erledigt && l.positionen.isNotEmpty && l.offen == 0)
              FilledButton.tonal(
                onPressed: () {
                  final alle = _listen();
                  alle.firstWhere((e) => e.id == l.id).erledigt = true;
                  _speichern(alle);
                },
                child: const Text('Erledigt ablegen'),
              ),
          ]),
        ]),
      ),
    );
  }

  void _manuellDazu(Einkaufsliste l, TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return;
    // „2 Kartuschen Silikon“ → Menge 2, Einheit „Kartuschen“ bleibt im Text
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(m²|m|stk\.?|stück|x)?\s+(.+)$', caseSensitive: false).firstMatch(t);
    final menge = m == null ? 1.0 : double.parse(m.group(1)!.replaceAll(',', '.'));
    final e = m?.group(2)?.toLowerCase();
    final einheit = e == null || e.startsWith('st') || e == 'x' ? 'Stk' : e;
    final alle = _listen();
    alle.firstWhere((x) => x.id == l.id).positionen.add(ListenPosition(schluessel: 'm:${neueListenId()}', text: m == null ? t : m.group(3)!, menge: menge, einheit: einheit, herkunft: 'von Hand'));
    c.clear();
    _speichern(alle);
  }
}
