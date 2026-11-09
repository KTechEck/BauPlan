import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/tagebuch_models.dart';
import '../../state/app_state.dart';

String datumText(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Modul Bautagebuch: Tageseinträge, Aufgaben (mit Abhängigkeit und
/// Wartungsintervall), Prüfprotokolle und automatischer Verlauf.
class TagebuchPage extends StatefulWidget {
  const TagebuchPage({super.key, required this.state});
  final AppState state;

  @override
  State<TagebuchPage> createState() => _TagebuchPageState();
}

class _TagebuchPageState extends State<TagebuchPage> {
  int _ansicht = 0;
  bool _erledigteZeigen = false;
  final List<VoidCallback> _rueckgaengig = [];

  AppState get _s => widget.state;

  void _rueck() {
    if (_rueckgaengig.isEmpty) return;
    _rueckgaengig.removeLast()();
    _s.geaendert();
  }

  /// Alle Räume des Projekts (ID → „EG · Bad“).
  Map<String, String> get _raeume => {
        for (final geb in _s.store!.gebaeude())
          for (final g in _s.store!.geschosse(geb.id))
            for (final r in _s.store!.raeume(g.id)) r.id: '${g.kuerzel} · ${r.name}',
      };

  Future<DateTime?> _datum(DateTime start) =>
      showDatePicker(context: context, initialDate: start, firstDate: DateTime(2000), lastDate: DateTime(2100));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _rueck},
        child: Focus(
          autofocus: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: BsFarben.rand))),
              child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, icon: Icon(Icons.menu_book_outlined, size: 18), label: Text('Tagebuch')),
                    ButtonSegment(value: 1, icon: Icon(Icons.checklist, size: 18), label: Text('Aufgaben')),
                    ButtonSegment(value: 2, icon: Icon(Icons.speed_outlined, size: 18), label: Text('Prüfprotokolle')),
                    ButtonSegment(value: 3, icon: Icon(Icons.history, size: 18), label: Text('Verlauf')),
                  ],
                  selected: {_ansicht},
                  onSelectionChanged: (v) => setState(() => _ansicht = v.first),
                ),
                IconButton(tooltip: 'Rückgängig (Strg+Z)', onPressed: _rueckgaengig.isEmpty ? null : _rueck, icon: const Icon(Sym.rueckgaengig)),
                if (_ansicht == 0) FilledButton.icon(onPressed: () => _eintragDialog(), icon: const Icon(Sym.hinzufuegen), label: const Text('Eintrag')),
                if (_ansicht == 1) ...[
                  FilledButton.icon(onPressed: () => _aufgabeDialog(), icon: const Icon(Sym.hinzufuegen), label: const Text('Aufgabe')),
                  FilterChip(label: const Text('erledigte zeigen'), selected: _erledigteZeigen, onSelected: (v) => setState(() => _erledigteZeigen = v)),
                ],
                if (_ansicht == 2) FilledButton.icon(onPressed: () => _pruefDialog(), icon: const Icon(Sym.hinzufuegen), label: const Text('Protokoll')),
              ]),
            ),
            Expanded(
              child: switch (_ansicht) {
                0 => _tagebuch(),
                1 => _aufgaben(),
                2 => _pruefungen(),
                _ => _verlauf(),
              },
            ),
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- Tagebuch

  Future<void> _eintragDialog({TagebuchEintrag? alt}) async {
    final store = _s.store!;
    final raeume = _raeume;
    final gewerke = store.gewerke();
    var datum = alt?.datum ?? DateTime.now();
    final text = TextEditingController(text: alt?.text ?? '');
    final stunden = TextEditingController(text: alt == null || alt.stunden == 0 ? '' : '${alt.stunden}'.replaceAll('.', ','));
    final wetter = TextEditingController(text: alt?.wetter ?? '');
    final personen = TextEditingController(text: alt?.personen ?? '');
    final rs = {...?alt?.raeume}, gs = {...?alt?.gewerke};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(alt == null ? 'Tagebucheintrag' : 'Eintrag bearbeiten'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(datumText(datum), style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextButton(
                    onPressed: () async {
                      final d = await _datum(datum);
                      if (d != null) setD(() => datum = d);
                    },
                    child: const Text('Datum ändern'),
                  ),
                ]),
                TextField(controller: text, maxLines: 5, decoration: const InputDecoration(labelText: 'Was wurde gemacht?')),
                Row(children: [
                  Expanded(child: TextField(controller: stunden, decoration: const InputDecoration(labelText: 'Stunden', suffixText: 'h'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: personen, decoration: const InputDecoration(labelText: 'Wer'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: wetter, decoration: const InputDecoration(labelText: 'Wetter'))),
                ]),
                const SizedBox(height: 12),
                const Text('Räume', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final e in raeume.entries)
                    FilterChip(label: Text(e.value), selected: rs.contains(e.key), onSelected: (v) => setD(() => v ? rs.add(e.key) : rs.remove(e.key))),
                ]),
                const SizedBox(height: 8),
                const Text('Gewerke', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final g in gewerke)
                    FilterChip(label: Text(g.name), selected: gs.contains(g.id), onSelected: (v) => setD(() => v ? gs.add(g.id) : gs.remove(g.id))),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final h = double.tryParse(stunden.text.trim().replaceAll(',', '.')) ?? 0;
    if (alt == null) {
      final id = store.tagebuchAnlegen(
          datum: datum, text: text.text.trim(), stunden: h, raeume: rs.toList(), gewerke: gs.toList(), wetter: wetter.text.trim(), personen: personen.text.trim());
      _rueckgaengig.add(() => store.tagebuchLoeschen(id));
    } else {
      final vorher = store.tagebuchAendern(alt.id, {
        'datum': '${datum.year.toString().padLeft(4, '0')}-${datum.month.toString().padLeft(2, '0')}-${datum.day.toString().padLeft(2, '0')}',
        'text': text.text.trim(),
        'stunden_hundertstel': (h * 100).round(),
        'raeume': jsonEncode(rs.toList()),
        'gewerke': jsonEncode(gs.toList()),
        'wetter': wetter.text.trim(),
        'personen': personen.text.trim(),
      });
      _rueckgaengig.add(() => store.tagebuchAendern(alt.id, vorher));
    }
    _s.geaendert();
  }

  /// Fotos eines Tages (alle Geschosse), optional nur aus bestimmten Räumen.
  List<Foto> _fotosAm(DateTime tag, List<String> raeume) {
    final store = _s.store!;
    return [
      for (final geb in store.gebaeude())
        for (final g in store.geschosse(geb.id))
          for (final f in store.fotos(g.id))
            if (f.aufnahme.year == tag.year && f.aufnahme.month == tag.month && f.aufnahme.day == tag.day && (raeume.isEmpty || raeume.contains(f.raumId))) f,
    ];
  }

  Widget _tagebuch() {
    final store = _s.store!;
    final eintraege = store.tagebuch();
    final raeume = _raeume;
    final gewerke = {for (final g in store.gewerke()) g.id: g};
    final summe = eintraege.fold<double>(0, (a, e) => a + e.stunden);
    if (eintraege.isEmpty) {
      return const Center(child: Text('Noch keine Einträge. „Eintrag“ legt den heutigen Tag an – Fotos des Tages erscheinen automatisch.'));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${eintraege.length} Einträge · ${summe.toStringAsFixed(1).replaceAll('.', ',')} Stunden', style: const TextStyle(color: BsFarben.textLeise)),
      for (final e in eintraege)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(datumText(e.datum), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 12),
                if (e.stunden > 0) Text('${e.stunden.toStringAsFixed(1).replaceAll('.', ',')} h', style: const TextStyle(color: BsFarben.textLeise)),
                if (e.personen.isNotEmpty) Text(' · ${e.personen}', style: const TextStyle(color: BsFarben.textLeise)),
                if (e.wetter.isNotEmpty) Text(' · ${e.wetter}', style: const TextStyle(color: BsFarben.textLeise)),
                const Spacer(),
                IconButton(tooltip: 'Bearbeiten', icon: const Icon(Sym.bearbeiten, size: 18), onPressed: () => _eintragDialog(alt: e)),
                IconButton(
                  tooltip: 'Löschen',
                  icon: const Icon(Sym.loeschen, size: 18),
                  onPressed: () {
                    store.tagebuchLoeschen(e.id);
                    _rueckgaengig.add(() => store.tagebuchWiederherstellen(e.id));
                    _s.geaendert();
                  },
                ),
              ]),
              if (e.text.isNotEmpty) Text(e.text),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final r in e.raeume) if (raeume[r] != null) Chip(label: Text(raeume[r]!, style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                for (final g in e.gewerke)
                  if (gewerke[g] != null)
                    Chip(
                      avatar: CircleAvatar(backgroundColor: Color(gewerke[g]!.farbe), radius: 5),
                      label: Text(gewerke[g]!.name, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
              ]),
              Builder(builder: (_) {
                final fotos = _fotosAm(e.datum, e.raeume);
                if (fotos.isEmpty) return const SizedBox.shrink();
                return SizedBox(
                  height: 72,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final f in fotos.take(20))
                      Padding(
                        padding: const EdgeInsets.only(right: 6, top: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(File(p.join(store.ordner, f.datei)), width: 88, height: 66, fit: BoxFit.cover, cacheWidth: 176,
                              errorBuilder: (_, __, ___) => Container(width: 88, height: 66, color: BsFarben.flaeche, child: const Icon(Icons.image_outlined))),
                        ),
                      ),
                  ]),
                );
              }),
            ]),
          ),
        ),
    ]);
  }

  // ---------------------------------------------------------- Aufgaben

  Future<void> _aufgabeDialog({Aufgabe? alt}) async {
    final store = _s.store!;
    final raeume = _raeume;
    final gewerke = store.gewerke();
    final alle = store.aufgaben();
    final titel = TextEditingController(text: alt?.titel ?? '');
    final beschreibung = TextEditingController(text: alt?.beschreibung ?? '');
    String? raum = alt?.raumId, gewerk = alt?.gewerkId, vor = alt?.abhaengigVon;
    DateTime? faellig = alt?.faellig;
    int? intervall = alt?.intervallTage;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(alt == null ? 'Aufgabe' : 'Aufgabe bearbeiten'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: titel, autofocus: true, decoration: const InputDecoration(labelText: 'Titel', hintText: 'z. B. Leerrohre fotografieren')),
              TextField(controller: beschreibung, maxLines: 2, decoration: const InputDecoration(labelText: 'Beschreibung')),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: raum,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Raum'),
                    items: [const DropdownMenuItem(value: null, child: Text('–')), for (final e in raeume.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setD(() => raum = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: gewerk,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Gewerk'),
                    items: [const DropdownMenuItem(value: null, child: Text('–')), for (final g in gewerke) DropdownMenuItem(value: g.id, child: Text(g.name))],
                    onChanged: (v) => setD(() => gewerk = v),
                  ),
                ),
              ]),
              DropdownButtonFormField<String?>(
                initialValue: vor,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'erst nach (Abhängigkeit)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('– keine –')),
                  for (final a in alle) if (a.id != alt?.id) DropdownMenuItem(value: a.id, child: Text(a.titel)),
                ],
                onChanged: (v) => setD(() => vor = v),
              ),
              Row(children: [
                Text(faellig == null ? 'ohne Fälligkeit' : 'fällig ${datumText(faellig!)}'),
                TextButton(
                  onPressed: () async {
                    final d = await _datum(faellig ?? DateTime.now());
                    if (d != null) setD(() => faellig = d);
                  },
                  child: const Text('Datum'),
                ),
                if (faellig != null) TextButton(onPressed: () => setD(() => faellig = null), child: const Text('ohne')),
                const Spacer(),
                DropdownButton<int?>(
                  value: intervall,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('einmalig')),
                    DropdownMenuItem(value: 90, child: Text('Wartung vierteljährlich')),
                    DropdownMenuItem(value: 182, child: Text('Wartung halbjährlich')),
                    DropdownMenuItem(value: 365, child: Text('Wartung jährlich')),
                    DropdownMenuItem(value: 730, child: Text('Wartung alle 2 Jahre')),
                  ],
                  onChanged: (v) => setD(() => intervall = v),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (ok != true || titel.text.trim().isEmpty) return;
    String? tag(DateTime? d) => d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (alt == null) {
      final id = store.aufgabeAnlegen(
          titel: titel.text.trim(), beschreibung: beschreibung.text.trim(), raumId: raum, gewerkId: gewerk, faellig: faellig, abhaengigVon: vor, intervallTage: intervall);
      _rueckgaengig.add(() => store.aufgabeLoeschen(id));
    } else {
      final vorher = store.aufgabeAendern(alt.id, {
        'titel': titel.text.trim(),
        'beschreibung': beschreibung.text.trim(),
        'raum_id': raum,
        'gewerk_id': gewerk,
        'faellig': tag(faellig),
        'abhaengig_von': vor,
        'intervall_tage': intervall,
      });
      _rueckgaengig.add(() => store.aufgabeAendern(alt.id, vorher));
    }
    _s.geaendert();
  }

  Widget _aufgaben() {
    final store = _s.store!;
    final alle = store.aufgaben();
    final raeume = _raeume;
    final gewerke = {for (final g in store.gewerke()) g.id: g};
    final heute = DateTime.now();
    final liste = [for (final a in alle) if (_erledigteZeigen || a.status != AufgabenStatus.erledigt) a];
    if (liste.isEmpty) return const Center(child: Text('Keine offenen Aufgaben.'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final a in liste)
        Builder(builder: (_) {
          final frei = aufgabeFrei(a, alle);
          final ueberfaellig = a.faellig != null && a.status != AufgabenStatus.erledigt && a.faellig!.isBefore(DateTime(heute.year, heute.month, heute.day));
          final vor = alle.where((x) => x.id == a.abhaengigVon).firstOrNull;
          return Card(
            child: ListTile(
              leading: Checkbox(
                value: a.status == AufgabenStatus.erledigt,
                onChanged: !frei && a.status != AufgabenStatus.erledigt
                    ? null
                    : (v) {
                        final vorher = v == true ? store.aufgabeErledigen(a.id) : store.aufgabeAendern(a.id, {'status': AufgabenStatus.offen.name, 'erledigt_am': null});
                        _rueckgaengig.add(() => store.aufgabeAendern(a.id, vorher));
                        _s.geaendert();
                      },
              ),
              title: Text(a.titel, style: TextStyle(decoration: a.status == AufgabenStatus.erledigt ? TextDecoration.lineThrough : null)),
              subtitle: Text([
                if (a.raumId != null && raeume[a.raumId] != null) raeume[a.raumId]!,
                if (a.gewerkId != null && gewerke[a.gewerkId] != null) gewerke[a.gewerkId]!.name,
                if (a.faellig != null) 'fällig ${datumText(a.faellig!)}${ueberfaellig ? ' (überfällig)' : ''}',
                if (a.istWartung) 'Wartung alle ${a.intervallTage} Tage${a.erledigtAm == null ? '' : ', zuletzt ${datumText(a.erledigtAm!)}'}',
                if (vor != null) frei ? 'nach „${vor.titel}“ ✓' : 'wartet auf „${vor.titel}“',
                if (a.beschreibung.isNotEmpty) a.beschreibung,
              ].join(' · '), style: TextStyle(color: ueberfaellig ? const Color(0xFFB91C1C) : null)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                DropdownButton<AufgabenStatus>(
                  value: a.status,
                  underline: const SizedBox.shrink(),
                  items: [for (final s in AufgabenStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                  onChanged: (s) {
                    if (s == null) return;
                    final vorher = s == AufgabenStatus.erledigt ? store.aufgabeErledigen(a.id) : store.aufgabeAendern(a.id, {'status': s.name});
                    _rueckgaengig.add(() => store.aufgabeAendern(a.id, vorher));
                    _s.geaendert();
                  },
                ),
                IconButton(icon: const Icon(Sym.bearbeiten, size: 18), onPressed: () => _aufgabeDialog(alt: a)),
                IconButton(
                  icon: const Icon(Sym.loeschen, size: 18),
                  onPressed: () {
                    store.aufgabeLoeschen(a.id);
                    _rueckgaengig.add(() => store.aufgabeWiederherstellen(a.id));
                    _s.geaendert();
                  },
                ),
              ]),
            ),
          );
        }),
    ]);
  }

  // ---------------------------------------------------- Prüfprotokolle

  Future<void> _pruefDialog() async {
    final store = _s.store!;
    final raeume = _raeume;
    var art = pruefVorlagen.keys.first;
    var datum = DateTime.now();
    String? raum;
    var ergebnis = 'bestanden';
    final werte = <String, TextEditingController>{};
    final pruefer = TextEditingController(), notiz = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Prüfprotokoll'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: art,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Art'),
                  items: [for (final k in pruefVorlagen.keys) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (v) => setD(() => art = v ?? art),
                ),
                Row(children: [
                  Text(datumText(datum)),
                  TextButton(
                    onPressed: () async {
                      final d = await _datum(datum);
                      if (d != null) setD(() => datum = d);
                    },
                    child: const Text('Datum'),
                  ),
                  const Spacer(),
                  DropdownButton<String>(
                    value: ergebnis,
                    items: [for (final e in const ['bestanden', 'nicht bestanden', 'offen']) DropdownMenuItem(value: e, child: Text(e))],
                    onChanged: (v) => setD(() => ergebnis = v ?? ergebnis),
                  ),
                ]),
                DropdownButtonFormField<String?>(
                  initialValue: raum,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Raum'),
                  items: [const DropdownMenuItem(value: null, child: Text('–')), for (final e in raeume.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setD(() => raum = v),
                ),
                for (final f in pruefVorlagen[art]!)
                  TextField(controller: werte.putIfAbsent('$art|$f', TextEditingController.new), decoration: InputDecoration(labelText: f)),
                TextField(controller: pruefer, decoration: const InputDecoration(labelText: 'geprüft von (bei Elektro: Elektrofachkraft)')),
                TextField(controller: notiz, decoration: const InputDecoration(labelText: 'Notiz')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final id = store.pruefprotokollAnlegen(
      art: art,
      datum: datum,
      raumId: raum,
      messwerte: {
        for (final f in pruefVorlagen[art]!)
          if ((werte['$art|$f']?.text.trim() ?? '').isNotEmpty) f: werte['$art|$f']!.text.trim(),
      },
      ergebnis: ergebnis,
      pruefer: pruefer.text.trim(),
      notiz: notiz.text.trim(),
    );
    _rueckgaengig.add(() => store.pruefprotokollLoeschen(id));
    _s.geaendert();
  }

  Widget _pruefungen() {
    final store = _s.store!;
    final liste = store.pruefprotokolle();
    final raeume = _raeume;
    if (liste.isEmpty) return const Center(child: Text('Noch keine Prüfprotokolle (Druckprobe, Isolationsmessung, Belegreifheizen …).'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final x in liste)
        Card(
          child: ListTile(
            leading: Icon(
              x.ergebnis == 'bestanden' ? Icons.verified_outlined : (x.ergebnis == 'offen' ? Icons.pending_outlined : Icons.error_outline),
              color: x.ergebnis == 'bestanden' ? const Color(0xFF2F9E44) : (x.ergebnis == 'offen' ? BsFarben.textLeise : const Color(0xFFB91C1C)),
            ),
            title: Text('${x.art} · ${datumText(x.datum)}'),
            subtitle: Text([
              if (x.raumId != null && raeume[x.raumId] != null) raeume[x.raumId]!,
              for (final e in x.messwerte.entries) '${e.key}: ${e.value}',
              if (x.pruefer.isNotEmpty) 'geprüft von ${x.pruefer}',
              if (x.notiz.isNotEmpty) x.notiz,
            ].join(' · ')),
            trailing: IconButton(
              icon: const Icon(Sym.loeschen, size: 18),
              onPressed: () {
                store.pruefprotokollLoeschen(x.id);
                _rueckgaengig.add(() => store.pruefprotokollWiederherstellen(x.id));
                _s.geaendert();
              },
            ),
          ),
        ),
    ]);
  }

  // ------------------------------------------------------------ Verlauf

  Widget _verlauf() {
    final store = _s.store!;
    final verlauf = store.statusVerlauf();
    final objekte = {for (final o in store.alleObjekte()) o.id: o};
    final typen = {for (final t in store.objekttypen()) t.id: t};
    if (verlauf.isEmpty) return const Center(child: Text('Noch keine Statuswechsel (verlegt, geprüft, verdeckt).'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Automatisch aus dem Änderungsprotokoll: jeder Statuswechsel eines Objekts.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      for (final (zeit, wer, id, status) in verlauf)
        ListTile(
          dense: true,
          leading: const Icon(Icons.swap_horiz, size: 18),
          title: Text('${objekte[id]?.kennung ?? id} · ${typen[objekte[id]?.typId]?.name ?? ''} → ${ObjektStatus.values.where((s) => s.name == status).firstOrNull?.label ?? status}'),
          subtitle: Text('${datumText(zeit)} ${zeit.hour.toString().padLeft(2, '0')}:${zeit.minute.toString().padLeft(2, '0')} · $wer'),
        ),
    ]);
  }
}
