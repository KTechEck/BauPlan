import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../core/einkauf.dart';
import '../../core/fbh.dart';
import '../../core/oberflaechen.dart';
import '../bauphysik/oberflaechen_ansicht.dart' show lichteHoeheVon;
import '../../core/ki.dart';
import '../../core/pdf_text.dart';
import '../../data/bauelement_bibliothek.dart';
import '../../data/project_store.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Bestand im Projekt (Element-ID → Menge).
Map<String, double> bestandLesen(ProjectStore store) => {
      for (final e in (store.einstellung<Map>('bestand') ?? const {}).entries) '${e.key}': (e.value as num).toDouble(),
    };

void bestandSetzen(ProjectStore store, String id, double menge) {
  final m = Map<String, dynamic>.from(store.einstellung<Map>('bestand') ?? const {});
  if (menge <= 0) {
    m.remove(id);
  } else {
    m[id] = menge;
  }
  store.einstellungSetzen('bestand', m);
}

List<Einkauf> einkaeufeLesen(ProjectStore store) => [
      for (final m in (store.einstellung<List>('einkaeufe') ?? const [])) Einkauf.ausJson(Map<String, dynamic>.from(m as Map)),
    ];

/// Signatur einer Bildfrage (für Tests austauschbar).
typedef BildFrage = Future<String> Function(String frage, List<List<int>> bilder);

/// Einkauf erfassen: Kassenzettel als Bild/PDF/Text einlesen (KI oder Regeln),
/// erkannte Zeilen prüfen, Bibliothekselementen zuordnen oder neu anlegen,
/// dann Bestand erhöhen und Einkauf speichern.
class EinkaufDialog extends StatefulWidget {
  const EinkaufDialog({super.key, required this.state, this.textKi, this.bildKi});
  final AppState state;
  final KiAnbieter? textKi;
  final BildFrage? bildKi;

  @override
  State<EinkaufDialog> createState() => _EinkaufDialogState();
}

/// Was mit einer Zeile passiert.
enum _Ziel { vorhanden, neu, weglassen }

class _Zeile {
  _Zeile(this.pos, this.ziel, this.kategorie);
  final EinkaufPosition pos;
  _Ziel ziel;
  BauelementKategorie kategorie;
}

class _EinkaufDialogState extends State<EinkaufDialog> {
  final _text = TextEditingController();
  final _haendler = TextEditingController();
  DateTime _datum = DateTime.now();
  File? _beleg;
  List<_Zeile> _zeilen = [];
  bool _laeuft = false;
  String? _meldung;

  AppState get _s => widget.state;
  BauelementBibliothek get _bib => _s.bibliothek;

  @override
  void dispose() {
    _text.dispose();
    _haendler.dispose();
    super.dispose();
  }

  List<Bauelement> get _alle => [for (final k in BauelementKategorie.values) ..._bib.auswahl(_s.store, k)];

  void _uebernehmen(List<EinkaufPosition> pos, {String? haendler, DateTime? datum}) {
    final alle = _alle;
    setState(() {
      if (haendler != null && haendler.isNotEmpty) _haendler.text = haendler;
      if (datum != null) _datum = datum;
      _zeilen = [
        for (final p in pos)
          () {
            final v = elementVorschlagen(p.text, alle);
            p.elementId = v?.id;
            return _Zeile(p, v == null ? _Ziel.neu : _Ziel.vorhanden, v?.kategorie ?? kategorieRaten(p.text));
          }(),
      ];
      _meldung = pos.isEmpty ? 'Keine Artikelzeilen erkannt – Zeilen unten von Hand hinzufügen.' : '${pos.length} Zeilen erkannt. Bitte prüfen und zuordnen.';
    });
  }

  Future<void> _belegWaehlen() async {
    final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Kassenzettel / Rechnung', extensions: ['jpg', 'jpeg', 'png', 'pdf', 'txt'])]);
    if (f == null) return;
    final datei = File(f.path);
    final endung = p.extension(f.path).toLowerCase();
    setState(() => _beleg = datei);
    if (endung == '.pdf') {
      _text.text = pdfText(await datei.readAsBytes());
    } else if (endung == '.txt') {
      _text.text = await datei.readAsString();
    }
    if (_text.text.trim().isNotEmpty) {
      _uebernehmen(kassenzettelLesen(_text.text));
    } else {
      setState(() => _meldung = 'Bild gewählt – mit „Mit KI erkennen“ auslesen (braucht ein Bildmodell, Einstellungen → KI).');
    }
  }

  Future<void> _kiErkennen() async {
    setState(() {
      _laeuft = true;
      _meldung = null;
    });
    try {
      final beleg = _beleg;
      final istBild = beleg != null && const {'.jpg', '.jpeg', '.png'}.contains(p.extension(beleg.path).toLowerCase());
      String antwort;
      if (istBild) {
        final bildmodell = _s.settings.ki?['bildmodell'] as String?;
        if (widget.bildKi == null && bildmodell == null) throw StateError('Kein Bildmodell eingerichtet (Einstellungen → KI-Assistent → „Bilder lesen“).');
        antwort = await (widget.bildKi ??
            (f, b) => ollamaBildFrage(KiEinstellung.ausJson(_s.settings.ki), bildmodell!, f, b))(kiKassenzettelAnfrage, [await beleg.readAsBytes()]);
      } else {
        final ki = widget.textKi ?? OllamaAnbieter(KiEinstellung.ausJson(_s.settings.ki));
        antwort = await ki.fragen('Du liest Kassenzettel aus. Antworte nur mit JSON.', '$kiKassenzettelAnfrage\n\nTEXT:\n${_text.text}');
      }
      final r = kiKassenzettelLesen(antwort);
      if (r == null) throw const FormatException('Die Antwort enthielt kein JSON.');
      _uebernehmen(r.positionen, haendler: r.haendler, datum: r.datum);
    } catch (e) {
      setState(() => _meldung = 'KI: $e');
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  void _speichern() {
    final store = _s.store!;
    final bestand = bestandLesen(store);
    final positionen = <EinkaufPosition>[];
    for (final z in _zeilen) {
      if (z.ziel == _Ziel.weglassen) continue;
      var id = z.pos.elementId;
      if (z.ziel == _Ziel.neu || id == null) {
        final e = Bauelement(
          id: _bib.neueId(),
          kategorie: z.kategorie,
          name: z.pos.text,
          daten: {'einheit': z.pos.einheit},
          preisCent: z.pos.preisCent == null || z.pos.menge == 0 ? null : (z.pos.preisCent! / z.pos.menge).round(),
        );
        _bib.speichern(e);
        id = e.id;
      }
      final e = _bib.fuerProjekt(store, id);
      if (e != null) BauelementBibliothek.insProjekt(store, e);
      z.pos.elementId = id;
      bestandSetzen(store, id, (bestand[id] ?? 0) + z.pos.menge);
      bestand[id] = (bestand[id] ?? 0) + z.pos.menge;
      positionen.add(z.pos);
    }
    String? belegName;
    final beleg = _beleg;
    if (beleg != null) {
      final ziel = Directory(p.join(store.ordner, 'belege'))..createSync(recursive: true);
      belegName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(beleg.path)}';
      beleg.copySync(p.join(ziel.path, belegName));
    }
    final ek = Einkauf(id: 'ek-${DateTime.now().microsecondsSinceEpoch}', datum: _datum, haendler: _haendler.text.trim(), positionen: positionen, beleg: belegName);
    store.einstellungSetzen('einkaeufe', [...(store.einstellung<List>('einkaeufe') ?? const []), ek.toJson()]);
    _s.geaendert();
    Navigator.pop(context, positionen.length);
  }

  @override
  Widget build(BuildContext context) {
    final alle = _alle;
    final summe = _zeilen.where((z) => z.ziel != _Ziel.weglassen).fold<int>(0, (s, z) => s + (z.pos.preisCent ?? 0));
    return AlertDialog(
      title: const Text('Einkauf erfassen'),
      content: SizedBox(
        width: 1040,
        height: 620,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 320,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 6, children: [
                OutlinedButton.icon(onPressed: _belegWaehlen, icon: const Icon(Icons.receipt_long, size: 18), label: const Text('Beleg wählen …')),
                FilledButton.tonalIcon(
                  onPressed: _laeuft || (_beleg == null && _text.text.trim().isEmpty) ? null : _kiErkennen,
                  icon: _laeuft ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Sym.assistent, size: 18),
                  label: const Text('Mit KI erkennen'),
                ),
              ]),
              if (_beleg != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(p.basename(_beleg!.path), style: const TextStyle(fontSize: 12))),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(hintText: 'Text des Kassenzettels (aus PDF/Text oder hier einfügen)'),
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton(onPressed: () => _uebernehmen(kassenzettelLesen(_text.text)), child: const Text('Zeilen aus dem Text erkennen')),
              if (_meldung != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_meldung!, style: const TextStyle(fontSize: 12))),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: TextField(controller: _haendler, decoration: const InputDecoration(labelText: 'Händler'))),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: _datum, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => _datum = d);
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('${_datum.day}.${_datum.month}.${_datum.year}'),
                ),
              ]),
              const SizedBox(height: 8),
              const Text('Erkannte Artikel – bitte prüfen', style: TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: ListView(children: [
                  for (final (i, z) in _zeilen.indexed) _zeileWidget(i, z, alle),
                  TextButton.icon(
                    onPressed: () => setState(() => _zeilen.add(_Zeile(EinkaufPosition(text: ''), _Ziel.neu, BauelementKategorie.kleinmaterial))),
                    icon: const Icon(Sym.hinzufuegen, size: 18),
                    label: const Text('Zeile'),
                  ),
                ]),
              ),
              Text('Summe ${(summe / 100).toStringAsFixed(2).replaceAll('.', ',')} €', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _zeilen.any((z) => z.ziel != _Ziel.weglassen && z.pos.text.trim().isNotEmpty) ? _speichern : null,
          child: const Text('Passt so – in Bestand übernehmen'),
        ),
      ],
    );
  }

  Widget _zeileWidget(int i, _Zeile z, List<Bauelement> alle) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Row(children: [
            Expanded(
              flex: 5,
              child: SpeicherFeld(
                key: ValueKey('ek-t-$i-${z.pos.text}'),
                initialValue: z.pos.text,
                decoration: const InputDecoration(labelText: 'Artikel'),
                onFieldSubmitted: (v) => setState(() => z.pos.text = v.trim()),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 80,
              child: SpeicherFeld(
                key: ValueKey('ek-m-$i-${z.pos.menge}'),
                initialValue: '${z.pos.menge}'.replaceAll('.0', '').replaceAll('.', ','),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                decoration: const InputDecoration(labelText: 'Menge'),
                onFieldSubmitted: (v) => setState(() => z.pos.menge = double.tryParse(v.replaceAll(',', '.')) ?? z.pos.menge),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 80,
              child: SpeicherFeld(
                key: ValueKey('ek-e-$i-${z.pos.einheit}'),
                initialValue: z.pos.einheit,
                decoration: const InputDecoration(labelText: 'Einheit'),
                onFieldSubmitted: (v) => setState(() => z.pos.einheit = v.trim()),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 90,
              child: SpeicherFeld(
                key: ValueKey('ek-p-$i-${z.pos.preisCent}'),
                initialValue: z.pos.preisCent == null ? '' : (z.pos.preisCent! / 100).toStringAsFixed(2).replaceAll('.', ','),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]'))],
                decoration: const InputDecoration(labelText: 'Preis €'),
                onFieldSubmitted: (v) => setState(() {
                  final d = double.tryParse(v.replaceAll(',', '.'));
                  z.pos.preisCent = d == null ? null : (d * 100).round();
                }),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            SegmentedButton<_Ziel>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Ziel.vorhanden, label: Text('Bibliothek')),
                ButtonSegment(value: _Ziel.neu, label: Text('neu anlegen')),
                ButtonSegment(value: _Ziel.weglassen, label: Text('weglassen')),
              ],
              selected: {z.ziel},
              onSelectionChanged: (v) => setState(() => z.ziel = v.first),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: switch (z.ziel) {
                _Ziel.vorhanden => DropdownButtonFormField<String>(
                    key: ValueKey('ek-z-$i-${z.pos.elementId}'),
                    isExpanded: true,
                    initialValue: alle.any((e) => e.id == z.pos.elementId) ? z.pos.elementId : null,
                    decoration: const InputDecoration(labelText: 'Element'),
                    items: [for (final e in alle) DropdownMenuItem(value: e.id, child: Text('${e.anzeige} · ${e.kategorie.label}', overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => z.pos.elementId = v),
                  ),
                _Ziel.neu => DropdownButtonFormField<BauelementKategorie>(
                    key: ValueKey('ek-k-$i-${z.kategorie.name}'),
                    isExpanded: true,
                    initialValue: z.kategorie,
                    decoration: const InputDecoration(labelText: 'Kategorie'),
                    items: [for (final k in BauelementKategorie.values) DropdownMenuItem(value: k, child: Text('${k.gruppe.label} · ${k.label}', overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => z.kategorie = v ?? z.kategorie),
                  ),
                _Ziel.weglassen => const Text('wird nicht übernommen', style: TextStyle(color: BsFarben.textLeise)),
              },
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Eine Zeile der Besorgungsliste: was laut Plan gebraucht wird, was da ist, was fehlt.
typedef BedarfZeile = ({Bauelement element, double bedarf, double bestand, String einheit, String herkunft});

/// Bedarf aus dem Plan: Produkte an Objekten, Öffnungen und im Schrank (Stück),
/// Dosen je Gerät, Rohre und Kabel nach Leitungslänge (+10 % Verschnitt).
List<BedarfZeile> besorgungsliste(AppState s) {
  final store = s.store!;
  final bedarf = <String, double>{};
  final herkunft = <String, Set<String>>{};
  final einheitVorgabe = <String, String>{};
  void plus(String? id, double m, String woher) {
    if (id == null || id.isEmpty) return;
    bedarf[id] = (bedarf[id] ?? 0) + m;
    herkunft.putIfAbsent(id, () => {}).add(woher);
  }

  final hkTyp = {for (final t in store.objekttypen()) if (t.kuerzel == 'HK') t.id};
  for (final o in store.alleObjekte()) {
    final e = o.eigenschaften;
    plus(e['bauelement'] as String?, 1, 'Installation');
    plus(e['dose'] as String?, 1, 'Dosen');
    if (hkTyp.contains(o.typId)) {
      // Heizkreis: Rohr, Platte, Halter, Randstreifen, Verschraubungen
      for (final (k, m, einheit) in fbhBedarf(o.punkte, e)) {
        final id = e[k] as String?;
        if (id == null || id.isEmpty) continue;
        plus(id, m, 'Fußbodenheizung');
        einheitVorgabe[id] = einheit;
      }
      continue;
    }
    if (o.punkte.length >= 2) {
      final m = o.laenge / 1000 * 1.1;
      plus(e['rohr'] as String?, m, 'Leitungen');
      for (final k in (e['kabel_liste'] as List? ?? const [])) {
        plus('$k', m, 'Leitungen');
      }
    }
  }
  for (final o in store.alleOeffnungen()) {
    plus(o.eigenschaften['bauelement'] as String?, 1, 'Fenster/Türen');
    plus(o.eigenschaften['sonnenschutz'] as String?, 1, 'Sonnenschutz');
  }
  // Oberflächen: Schichtsysteme je Raum (Wände ohne Öffnungsabzug, eher reichlich)
  for (final geb in store.gebaeude()) {
    for (final gs in store.geschosse(geb.id)) {
      for (final r in store.raeume(gs.id)) {
        if (r.umriss == null) continue;
        for (final a in Flaechenart.values) {
          final m2 = raumFlaeche(a, grundflaecheMm2: r.flaeche ?? 0, umfangMm: r.umfang ?? 0, lichteHoeheMm: lichteHoeheVon(r, gs));
          for (final b in beschichtungen(r.eigenschaften, a)) {
            if (b.material == null) continue;
            plus(b.material, b.bedarf(m2), 'Oberflächen');
            einheitVorgabe[b.material!] = b.einheit;
          }
        }
      }
    }
  }
  for (final sch in store.schraenke()) {
    for (final g in store.schrankGeraete(sch.id)) {
      plus(g.eigenschaften['bauelement'] as String?, 1, 'Verteiler');
    }
  }
  final bestand = bestandLesen(store);
  final l = <BedarfZeile>[];
  for (final e in bedarf.entries) {
    final el = s.bibliothek.fuerProjekt(store, e.key);
    if (el == null) continue;
    final m = e.value;
    l.add((
      element: el,
      bedarf: (el.daten['einheit'] == 'm' || herkunft[e.key]!.contains('Leitungen') || einheitVorgabe[e.key] != null && einheitVorgabe[e.key] != 'Stk')
          ? (m * 10).ceilToDouble() / 10
          : m.ceilToDouble(),
      bestand: bestand[e.key] ?? 0,
      einheit: el.daten['einheit'] as String? ?? einheitVorgabe[e.key] ?? (herkunft[e.key]!.contains('Leitungen') ? 'm' : 'Stk'),
      herkunft: herkunft[e.key]!.join(', '),
    ));
  }
  l.sort((a, b) => a.element.kategorie.index != b.element.kategorie.index
      ? a.element.kategorie.index.compareTo(b.element.kategorie.index)
      : a.element.anzeige.compareTo(b.element.anzeige));
  return l;
}

/// Besorgungsliste als Dialog mit Speichern als CSV.
Future<void> besorgungslisteZeigen(BuildContext context, AppState s) async {
  final l = besorgungsliste(s);
  String z(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
  final fehlt = l.where((r) => r.bedarf > r.bestand).toList();
  // Formteile aus Leitungen mit Rohr (Sanitär, Heizung, Leerrohr)
  final store = s.store!;
  final formteile = formteileSchaetzen([
    for (final o in store.alleObjekte())
      if (o.punkte.length >= 2 && o.eigenschaften['rohr'] is String)
        (
          punkte: [for (final p in o.punkte) (p.x, p.y)],
          dimension: s.bibliothek.fuerProjekt(store, o.eigenschaften['rohr'] as String)?.daten['nennweite'] as String? ?? '?',
          anderLeitung: (o.eigenschaften['anfang'] as Map?)?['leitung'] != null || (o.eigenschaften['ende'] as Map?)?['leitung'] != null,
        ),
  ]);
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Besorgungsliste (${fehlt.length} fehlen)'),
      content: SizedBox(
        width: 820,
        height: 520,
        child: l.isEmpty && formteile.isEmpty
            ? const Center(child: Text('Im Plan sind noch keine Produkte aus der Bibliothek zugeordnet.'))
            : SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (formteile.isNotEmpty) ...[
                  const Text('Formteile und Halter (geschätzt aus dem Leitungsverlauf)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Text('Richtungswechsel = Winkel, Anschluss an eine andere Leitung = T-Stück, etwa je Meter eine Schelle.',
                      style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final e in (formteile.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                      Chip(label: Text('${e.value}× ${e.key}')),
                  ]),
                  const Divider(height: 24),
                ],
                DataTable(columnSpacing: 18, columns: const [
                  DataColumn(label: Text('Artikel')),
                  DataColumn(label: Text('Bedarf'), numeric: true),
                  DataColumn(label: Text('Bestand'), numeric: true),
                  DataColumn(label: Text('fehlt'), numeric: true),
                  DataColumn(label: Text('aus')),
                ], rows: [
                  for (final r in l)
                    DataRow(cells: [
                      DataCell(Text(r.element.anzeige)),
                      DataCell(Text('${z(r.bedarf)} ${r.einheit}')),
                      DataCell(Text(z(r.bestand))),
                      DataCell(Text(r.bedarf > r.bestand ? z(r.bedarf - r.bestand) : '–',
                          style: TextStyle(fontWeight: FontWeight.w600, color: r.bedarf > r.bestand ? const Color(0xFFB91C1C) : const Color(0xFF2F9E44)))),
                      DataCell(Text(r.herkunft, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise))),
                    ]),
                ]),
                ]),
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: fehlt.isEmpty
              ? null
              : () async {
                  final csv = StringBuffer('Artikel;Hersteller;Artikelnummer;Menge;Einheit\n');
                  for (final r in fehlt) {
                    csv.writeln('${r.element.name};${r.element.hersteller};${r.element.artikelnummer};${z(r.bedarf - r.bestand)};${r.einheit}');
                  }
                  final f = File(p.join(s.store!.ordner, 'exporte', 'Besorgungsliste.csv'));
                  await f.parent.create(recursive: true);
                  await f.writeAsString(csv.toString());
                  await Clipboard.setData(ClipboardData(text: csv.toString()));
                  if (c.mounted) zeigeHinweis(c, 'Gespeichert unter ${f.path} und in die Zwischenablage kopiert.');
                },
          icon: const Icon(Icons.save_alt, size: 18),
          label: const Text('Fehlende als CSV'),
        ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen')),
      ],
    ),
  );
}
