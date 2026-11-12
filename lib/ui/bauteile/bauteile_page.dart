import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../core/ki.dart';
import '../../core/pdf_text.dart';
import '../../data/bauelement_bibliothek.dart';
import '../../state/app_state.dart';
import '../bibliothek.dart' show MaterialienAnsicht, WandtypenAnsicht;
import '../sensoren_page.dart' show SensorenAnsicht;
import '../widgets.dart';
import 'anschluss_editor.dart';
import 'bauelement_skizze.dart';
import '../../core/geraeteanschluesse.dart';
import 'bauelement_wahl.dart';
import 'einkauf_dialog.dart';

/// Modul Bauteile: Bibliothek konkreter Bauelemente (Fenster, Türen,
/// Rollläden, Steckdosen, Schrankgeräte, Technikgeräte …) anlegen und
/// bearbeiten – manuell oder aus einem Datenblatt (Regeln oder KI).
class BauteilePage extends StatefulWidget {
  const BauteilePage({super.key, required this.state, this.kiAnbieter});
  final AppState state;

  /// Für Tests: vorgegebenes Sprachmodell.
  final KiAnbieter? kiAnbieter;

  @override
  State<BauteilePage> createState() => _BauteilePageState();
}

class _BauteilePageState extends State<BauteilePage> {
  BauelementKategorie _kategorie = BauelementKategorie.fenster;
  String? _auswahl;
  String _suche = '';
  String? _sonder; // materialien, wandtypen, sensoren statt der Bauelemente
  final _fokus = FocusNode(debugLabel: 'bibliothek');
  Bauelement? _ablage; // Strg+C

  @override
  void dispose() {
    _fokus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final z = _s.einstellungenZiel;
    if (const ['materialien', 'wandtypen', 'sensoren'].contains(z)) {
      _sonder = z;
      _s.einstellungenZiel = null;
    }
  }

  AppState get _s => widget.state;
  BauelementBibliothek get _bib => _s.bibliothek;

  /// Wie oft ein Element im offenen Projekt verwendet wird.
  int _verwendung(String id) {
    final store = _s.store;
    if (store == null) return 0;
    var n = 0;
    for (final o in store.alleOeffnungen()) {
      if (o.eigenschaften['bauelement'] == id || o.eigenschaften['sonnenschutz'] == id) n++;
    }
    for (final o in store.alleObjekte()) {
      if (o.eigenschaften['bauelement'] == id) n++;
    }
    for (final s in store.schraenke()) {
      for (final g in store.schrankGeraete(s.id)) {
        if (g.eigenschaften['bauelement'] == id) n++;
      }
    }
    return n;
  }

  /// Bibliothekselement weicht von der Kopie im Projekt ab.
  bool _projektAbweichend(Bauelement e) {
    final m = _s.store?.einstellung<Map>('bauelemente')?[e.id];
    return m != null && jsonEncode(m) != jsonEncode(e.toJson());
  }

  Map<String, double> get _bestand => _s.store == null ? const {} : bestandLesen(_s.store!);

  String _menge(double m) => m == m.roundToDouble() ? m.toInt().toString() : m.toStringAsFixed(2).replaceAll('.', ',');

  Future<void> _einkauf() async {
    final n = await showDialog<int>(context: context, builder: (_) => EinkaufDialog(state: _s, textKi: widget.kiAnbieter));
    if (n != null && mounted) {
      setState(() {});
      zeigeHinweis(context, '$n Positionen in den Bestand übernommen.');
    }
  }

  void _einkaeufeZeigen() {
    final l = einkaeufeLesen(_s.store!).reversed.toList();
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Einkäufe'),
        content: SizedBox(
          width: 640,
          height: 480,
          child: l.isEmpty
              ? const Center(child: Text('Noch keine Einkäufe erfasst.'))
              : ListView(children: [
                  for (final ek in l)
                    ExpansionTile(
                      title: Text('${ek.datum.day}.${ek.datum.month}.${ek.datum.year} · ${ek.haendler.isEmpty ? 'ohne Händler' : ek.haendler}'),
                      subtitle: Text('${ek.positionen.length} Positionen · ${(ek.summeCent / 100).toStringAsFixed(2).replaceAll('.', ',')} €'),
                      children: [
                        for (final p in ek.positionen)
                          ListTile(
                            dense: true,
                            title: Text(p.text),
                            trailing: Text('${_menge(p.menge)} ${p.einheit}${p.preisCent == null ? '' : ' · ${(p.preisCent! / 100).toStringAsFixed(2).replaceAll('.', ',')} €'}'),
                          ),
                      ],
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
      ),
    );
  }

  Widget _bestandZeile(Bauelement e) {
    final store = _s.store;
    if (store == null || e.kategorie == BauelementKategorie.werkzeug) return const SizedBox.shrink();
    final b = _bestand[e.id] ?? 0;
    return Row(children: [
      SizedBox(
        width: 250,
        child: SpeicherFeld(
          key: ValueKey('${e.id}-bestand-$b'),
          initialValue: b == 0 ? '' : _menge(b),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          decoration: InputDecoration(labelText: 'Bestand im Projekt', suffixText: e.daten['einheit'] as String? ?? 'Stk', helperText: 'auf der Baustelle vorhanden'),
          onFieldSubmitted: (v) {
            bestandSetzen(store, e.id, double.tryParse(v.replaceAll(',', '.')) ?? 0);
            BauelementBibliothek.insProjekt(store, e);
            _s.geaendert();
            setState(() {});
          },
        ),
      ),
    ]);
  }

  void _speichern(Bauelement e) {
    // nur die Bibliothek ändern – ins Projekt (schon Gezeichnetes) erst auf Knopfdruck
    _bib.speichern(e);
    setState(() {});
    _s.geaendert();
  }

  void _neu({Bauelement? vorlage}) {
    final e = Bauelement(
      id: _bib.neueId(),
      kategorie: vorlage?.kategorie ?? _kategorie,
      name: vorlage == null ? 'Neues Element' : '${vorlage.name} (Kopie)',
      hersteller: vorlage?.hersteller ?? '',
      daten: {...?vorlage?.daten},
    );
    _bib.speichern(e);
    setState(() => _auswahl = e.id);
  }

  @override
  Widget build(BuildContext context) {
    final liste = _bib
        .auswahl(_s.store, _kategorie)
        .where((e) => _suche.isEmpty || '${e.anzeige} ${e.artikelnummer} ${e.kurzdaten}'.toLowerCase().contains(_suche.toLowerCase()))
        .toList();
    final gewaehlt = _bib.element(_auswahl) ?? _bib.fuerProjekt(_s.store!, _auswahl);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (gewaehlt != null) _loeschenMitRueckgaengig(gewaehlt);
        },
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
          if (gewaehlt != null) _neu(vorlage: gewaehlt);
        },
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          if (gewaehlt != null) {
            _ablage = gewaehlt;
            zeigeHinweis(context, '„${gewaehlt.anzeige}“ kopiert – Strg+V fügt eine Kopie ein.');
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          if (_ablage != null) _neu(vorlage: _ablage);
        },
      },
      child: Focus(
        focusNode: _fokus,
        autofocus: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Kategorien
      SizedBox(
        width: 250,
        child: Material(
          color: Colors.white,
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Bibliothek', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 2),
            child: Text('AUFBAUTEN (PROJEKT)', style: TextStyle(fontSize: 11, letterSpacing: 0.6, color: BsFarben.textLeise, fontWeight: FontWeight.w600)),
          ),
          for (final (id, text, icon) in const [
            ('wandtypen', 'Wandaufbauten', Icons.layers_outlined),
            ('materialien', 'Baustoffe und Farben', Icons.palette_outlined),
            ('sensoren', 'Eigene Sensoren', Icons.sensors),
          ])
            ListTile(
              dense: true,
              selected: _sonder == id,
              selectedTileColor: BsFarben.akzentHell,
              leading: Icon(icon, size: 20),
              title: Text(text),
              onTap: () => setState(() => _sonder = id),
            ),
          for (final g in BauelementGruppe.values) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Text(g.label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 0.6, color: BsFarben.textLeise, fontWeight: FontWeight.w600)),
            ),
            for (final k in BauelementKategorie.values.where((k) => k.gruppe == g))
              ListTile(
                dense: true,
                selected: _sonder == null && k == _kategorie,
                selectedTileColor: BsFarben.akzentHell,
                leading: Icon(kategorieSymbol(k), size: 20),
                title: Text(k.label),
                trailing: Text('${_bib.inKategorie(k).length}', style: const TextStyle(color: BsFarben.textLeise)),
                onTap: () => setState(() {
                  _kategorie = k;
                  _auswahl = null;
                  _sonder = null;
                }),
              ),
          ],
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'Die Bibliothek gilt für alle Projekte auf diesem PC. Was du in einem Projekt einsetzt, wird dort mitgespeichert.',
                style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              onPressed: () {
                final n = _bib.grundbestandWiederherstellen();
                setState(() {});
                zeigeHinweis(context, n == 0 ? 'Grundbibliothek ist vollständig.' : '$n Einträge der Grundbibliothek wiederhergestellt.');
              },
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Grundbibliothek wiederherstellen'),
            ),
          ),
        ]),
        ),
      ),
      const VerticalDivider(width: 1),
      if (_sonder != null)
        Expanded(
          child: Material(
            color: Colors.white,
            child: switch (_sonder) {
              'wandtypen' => WandtypenAnsicht(state: _s),
              'materialien' => MaterialienAnsicht(state: _s),
              _ => SensorenAnsicht(state: _s),
            },
          ),
        )
      else ...[
      // Liste
      SizedBox(
        width: 380,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Suchen'),
                  onChanged: (v) => setState(() => _suche = v),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton.icon(onPressed: () => _neu(), icon: const Icon(Sym.hinzufuegen, size: 18), label: const Text('Neu')),
              OutlinedButton.icon(
                onPressed: () => _ausDatenblatt(null),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Aus Datenblatt …'),
              ),
              OutlinedButton.icon(
                onPressed: _einkauf,
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('Einkauf erfassen …'),
              ),
              IconButton(
                tooltip: 'Besorgungsliste: was laut Plan gebraucht wird und noch fehlt',
                onPressed: () => besorgungslisteZeigen(context, _s),
                icon: const Icon(Icons.shopping_cart_outlined),
              ),
              IconButton(
                tooltip: 'Bisherige Einkäufe',
                onPressed: _einkaeufeZeigen,
                icon: const Icon(Icons.history),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: liste.isEmpty
                ? const Center(child: Text('Noch keine Einträge.', style: TextStyle(color: BsFarben.textLeise)))
                : ListView(children: [
                    for (final e in liste)
                      ListTile(
                        selected: e.id == _auswahl,
                        selectedTileColor: BsFarben.akzentHell,
                        leading: Icon(kategorieSymbol(e.kategorie)),
                        title: Text(e.anzeige),
                        subtitle: Text([e.kurzdaten, if ((_bestand[e.id] ?? 0) > 0) 'Bestand ${_menge(_bestand[e.id]!)} ${e.daten['einheit'] ?? 'Stk'}'].where((t) => t.isNotEmpty).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: () {
                          final n = _verwendung(e.id);
                          return n == 0 ? null : Chip(label: Text('$n× im Projekt'), visualDensity: VisualDensity.compact);
                        }(),
                        onTap: () {
                          _fokus.requestFocus();
                          setState(() => _auswahl = e.id);
                        },
                      ),
                  ]),
          ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: gewaehlt == null
            ? const Center(child: Text('Element wählen oder neu anlegen.', style: TextStyle(color: BsFarben.textLeise)))
            : Material(color: Colors.white, child: _editor(gewaehlt)),
      ),
      ],
    ])));
  }

  /// Löschen per Entf mit Rückgängig in der Meldung; im Projekt verwendete bleiben.
  void _loeschenMitRueckgaengig(Bauelement e) {
    final n = _verwendung(e.id);
    if (n > 0) {
      zeigeWarnung(context, '„${e.anzeige}“ wird $n× im Projekt verwendet und bleibt deshalb erhalten.');
      return;
    }
    _bib.loeschen(e.id);
    setState(() => _auswahl = null);
    zeigeHinweis(context, '„${e.anzeige}“ gelöscht.',
        aktion: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () {
            _bib.speichern(e);
            if (mounted) setState(() => _auswahl = e.id);
          },
        ));
  }

  Widget _editor(Bauelement e) {
    Widget feld(FeldDef f) {
      final wert = e.daten[f.schluessel];
      void setzen(Object? v) {
        final d = {...e.daten};
        if (v == null || (v is String && v.trim().isEmpty)) {
          d.remove(f.schluessel);
        } else {
          d[f.schluessel] = v;
        }
        _speichern(e.mit(daten: d));
      }

      return SizedBox(
        width: 250,
        child: switch (f.typ) {
          FeldTyp.auswahl => DropdownButtonFormField<String>(
              key: ValueKey('${e.id}-${f.schluessel}-$wert'),
              isExpanded: true,
              initialValue: f.optionen.contains(wert) ? wert as String : null,
              decoration: InputDecoration(labelText: f.label, helperText: f.hilfe.isEmpty ? null : f.hilfe),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('–')),
                for (final o in f.optionen) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: setzen,
            ),
          FeldTyp.jaNein => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(f.label),
              value: wert == true,
              onChanged: (v) => setzen(v == true ? true : null),
            ),
          FeldTyp.text => SpeicherFeld(
              key: ValueKey('${e.id}-${f.schluessel}'),
              initialValue: wert?.toString() ?? '',
              decoration: InputDecoration(labelText: f.label, helperText: f.hilfe.isEmpty ? null : f.hilfe),
              onFieldSubmitted: (v) => setzen(v.trim()),
            ),
          FeldTyp.zahl => SpeicherFeld(
              key: ValueKey('${e.id}-${f.schluessel}'),
              initialValue: wert == null ? '' : '$wert'.replaceAll('.', ','),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]'))],
              decoration: InputDecoration(labelText: f.label, suffixText: f.einheit, helperText: f.hilfe.isEmpty ? null : f.hilfe),
              onFieldSubmitted: (v) {
                final z = num.tryParse(v.trim().replaceAll(',', '.'));
                setzen(z == null ? null : (z == z.roundToDouble() && !v.contains(RegExp('[,.]')) ? z.toInt() : z));
              },
            ),
        },
      );
    }

    final datei = _bib.datenblattDatei(e);
    final n = _verwendung(e.id);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(child: Text(e.anzeige, style: Theme.of(context).textTheme.titleLarge)),
        FilledButton.tonalIcon(onPressed: () => _neu(vorlage: e), icon: const Icon(Icons.copy_outlined, size: 18), label: const Text('Duplizieren')),
        const SizedBox(width: 4),
        IconButton(
          tooltip: n > 0 ? 'Wird im Projekt verwendet' : 'Löschen',
          onPressed: n > 0
              ? null
              : () {
                  _loeschenMitRueckgaengig(e);
                },
          icon: const Icon(Sym.loeschen),
        ),
      ]),
      Text(e.kategorie.label, style: const TextStyle(color: BsFarben.textLeise)),
      const SizedBox(height: 12),
      Wrap(spacing: 16, runSpacing: 12, children: [
        SizedBox(
          width: 516,
          child: SpeicherFeld(
            key: ValueKey('${e.id}-name'),
            initialValue: e.name,
            decoration: const InputDecoration(labelText: 'Bezeichnung'),
            onFieldSubmitted: (v) => _speichern(e.mit(name: v.trim())),
          ),
        ),
        SizedBox(
          width: 250,
          child: SpeicherFeld(
            key: ValueKey('${e.id}-hersteller'),
            initialValue: e.hersteller,
            decoration: const InputDecoration(labelText: 'Hersteller'),
            onFieldSubmitted: (v) => _speichern(e.mit(hersteller: v.trim())),
          ),
        ),
        SizedBox(
          width: 250,
          child: SpeicherFeld(
            key: ValueKey('${e.id}-artikel'),
            initialValue: e.artikelnummer,
            decoration: const InputDecoration(labelText: 'Artikelnummer'),
            onFieldSubmitted: (v) => _speichern(e.mit(artikelnummer: v.trim())),
          ),
        ),
        SizedBox(
          width: 250,
          child: SpeicherFeld(
            key: ValueKey('${e.id}-preis'),
            initialValue: e.preisCent == null ? '' : (e.preisCent! / 100).toStringAsFixed(2).replaceAll('.', ','),
            decoration: const InputDecoration(labelText: 'Preis netto', suffixText: '€'),
            onFieldSubmitted: (v) {
              final z = double.tryParse(v.trim().replaceAll('.', '').replaceAll(',', '.'));
              _speichern(e.mit(preisCent: z == null ? null : (z * 100).round()));
            },
          ),
        ),
        for (final (k, label, breite) in const [('haendler', 'Händler (Einkaufsliste)', 250.0), ('link', 'Händler-Link', 516.0)])
          SizedBox(
            width: breite,
            child: SpeicherFeld(
              key: ValueKey('${e.id}-$k'),
              initialValue: '${e.daten[k] ?? ''}',
              decoration: InputDecoration(labelText: label, hintText: k == 'link' ? 'https://…' : 'z. B. Bauhaus, Elektro-Großhandel'),
              onFieldSubmitted: (v) {
                final d = {...e.daten};
                v.trim().isEmpty ? d.remove(k) : d[k] = v.trim();
                _speichern(e.mit(daten: d));
              },
            ),
          ),
      ]),
      if (_projektAbweichend(e))
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: BsFarben.akzentHell, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Expanded(
              child: Text('Im Projekt ist noch der alte Stand gespeichert. Bereits Gezeichnetes bleibt unverändert, bis du übernimmst.',
                  style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                BauelementBibliothek.insProjekt(_s.store!, e);
                _s.geaendert();
                setState(() {});
                zeigeHinweis(context, 'Änderungen ins Projekt übernommen ($n× verwendet).');
              },
              child: const Text('Ins Projekt übernehmen'),
            ),
          ]),
        ),
      const SizedBox(height: 20),
      _bestandZeile(e),
      const SizedBox(height: 16),
      Text('Technische Daten', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      BauelementSkizze(element: e, setzen: (d) => _speichern(e.mit(daten: d))),
      const SizedBox(height: 12),
      Wrap(spacing: 16, runSpacing: 12, children: [
        for (final f in e.kategorie.felder)
          if (!skizzenFelder(e.kategorie).contains(f.schluessel)) feld(f),
      ]),
      if (kategorieMitAnschluessen(e.kategorie)) ...[
        const SizedBox(height: 20),
        AnschlussEditor(element: e, setzen: (d) => _speichern(e.mit(daten: d))),
      ],
      const SizedBox(height: 20),
      Text('Datenblatt', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (datei != null && datei.existsSync()) ...[
          const Icon(Icons.description_outlined, size: 18),
          Text(p.basename(datei.path).replaceFirst('${e.id}_', '')),
          TextButton(onPressed: () => Process.run('explorer', [datei.path]), child: const Text('Öffnen')),
        ] else
          const Text('Kein Datenblatt hinterlegt.', style: TextStyle(color: BsFarben.textLeise)),
        OutlinedButton.icon(
          onPressed: () => _ausDatenblatt(e),
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(datei == null ? 'Datenblatt einlesen …' : 'Neu einlesen …'),
        ),
      ]),
      const SizedBox(height: 16),
      SpeicherFeld(
        key: ValueKey('${e.id}-notiz'),
        initialValue: e.notiz,
        maxLines: 4,
        minLines: 2,
        decoration: const InputDecoration(labelText: 'Notiz'),
        onFieldSubmitted: (v) => _speichern(e.mit(notiz: v)),
      ),
    ]);
  }

  /// Datenblatt einlesen: Datei (PDF/Text) oder eingefügter Text → Werte
  /// erkennen (Regeln, optional KI) → prüfen → übernehmen.
  Future<void> _ausDatenblatt(Bauelement? ziel) async {
    final ergebnis = await showDialog<_DatenblattErgebnis>(
      context: context,
      builder: (_) => _DatenblattDialog(
        kategorie: ziel?.kategorie ?? _kategorie,
        ki: widget.kiAnbieter ?? OllamaAnbieter(KiEinstellung.ausJson(_s.settings.ki)),
      ),
    );
    if (ergebnis == null || !mounted) return;
    final basis = ziel ??
        Bauelement(
          id: _bib.neueId(),
          kategorie: ergebnis.kategorie,
          name: ergebnis.name.isEmpty ? 'Aus Datenblatt' : ergebnis.name,
        );
    var e = basis.mit(
      kategorie: ergebnis.kategorie,
      daten: {...basis.daten, ...ergebnis.werte},
      name: ziel == null || ergebnis.name.isEmpty ? null : ergebnis.name,
      hersteller: ergebnis.hersteller.isEmpty ? null : ergebnis.hersteller,
      artikelnummer: ergebnis.artikel.isEmpty ? null : ergebnis.artikel,
    );
    if (ergebnis.datei != null) e = e.mit(datenblatt: _bib.datenblattAblegen(ergebnis.datei!, e.id));
    _speichern(e);
    setState(() {
      _kategorie = e.kategorie;
      _auswahl = e.id;
    });
    zeigeHinweis(context, '${ergebnis.werte.length} Werte übernommen – bitte prüfen.');
  }
}

class _DatenblattErgebnis {
  _DatenblattErgebnis(this.kategorie, this.werte, this.datei, {this.name = '', this.hersteller = '', this.artikel = ''});
  final BauelementKategorie kategorie;
  final Map<String, dynamic> werte;
  final File? datei;
  final String name, hersteller, artikel;
}

class _DatenblattDialog extends StatefulWidget {
  const _DatenblattDialog({required this.kategorie, required this.ki});
  final BauelementKategorie kategorie;
  final KiAnbieter ki;

  @override
  State<_DatenblattDialog> createState() => _DatenblattDialogState();
}

class _DatenblattDialogState extends State<_DatenblattDialog> {
  late BauelementKategorie _k = widget.kategorie;
  final _text = TextEditingController();
  File? _datei;
  Map<String, dynamic> _werte = {};
  String _name = '', _hersteller = '', _artikel = '';
  bool _kiLaeuft = false;
  String? _meldung;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _oeffnen() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Datenblatt', extensions: ['pdf', 'txt', 'csv', 'png', 'jpg', 'jpeg']),
    ]);
    if (f == null) return;
    final datei = File(f.path);
    final endung = p.extension(f.path).toLowerCase();
    String text = '';
    if (endung == '.pdf') {
      text = pdfText(await datei.readAsBytes());
    } else if (endung == '.txt' || endung == '.csv') {
      text = await datei.readAsString();
    }
    setState(() {
      _datei = datei;
      _text.text = text;
      _meldung = text.trim().length < 40
          ? 'Aus der Datei ließ sich kaum Text lesen. Text im PDF-Programm markieren, kopieren und unten einfügen – oder Werte von Hand eintragen.'
          : null;
    });
    _erkennen();
  }

  void _erkennen() => setState(() => _werte = {..._werte, ...datenblattWerte(_text.text, _k)});

  Future<void> _mitKi() async {
    setState(() {
      _kiLaeuft = true;
      _meldung = null;
    });
    try {
      final antwort = await widget.ki.fragen('Du extrahierst technische Daten aus Datenblättern. Antworte nur mit JSON.', kiDatenblattAnfrage(_text.text, _k));
      final m = kiJsonLesen(antwort);
      if (m == null) throw const FormatException('Die Antwort enthielt kein JSON.');
      setState(() {
        _werte = {..._werte, ...kiWerteBereinigen(m, _k)};
        _name = '${m['name'] ?? _name}';
        _hersteller = '${m['hersteller'] ?? _hersteller}';
        _artikel = '${m['artikelnummer'] ?? _artikel}';
      });
    } catch (e) {
      setState(() => _meldung = 'KI nicht erreichbar oder Antwort unbrauchbar: $e. Einrichtung unter Einstellungen → KI.');
    } finally {
      if (mounted) setState(() => _kiLaeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final felder = {for (final f in _k.felder) f.schluessel: f};
    return AlertDialog(
      title: const Text('Datenblatt einlesen'),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<BauelementKategorie>(
                initialValue: _k,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategorie'),
                items: [for (final k in BauelementKategorie.values) DropdownMenuItem(value: k, child: Text('${k.gruppe.label} · ${k.label}'))],
                onChanged: (v) => setState(() {
                  _k = v ?? _k;
                  _werte = {};
                  _erkennen();
                }),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(onPressed: _oeffnen, icon: const Icon(Icons.file_open_outlined, size: 18), label: const Text('Datei wählen …')),
                if (_datei != null) Text(p.basename(_datei!.path), overflow: TextOverflow.ellipsis),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(hintText: 'Text des Datenblatts (wird aus der Datei gelesen oder hier einfügen)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: _erkennen, child: const Text('Werte erkennen')),
                FilledButton.tonalIcon(
                  onPressed: _kiLaeuft || _text.text.trim().isEmpty ? null : _mitKi,
                  icon: _kiLaeuft ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Sym.assistent, size: 18),
                  label: const Text('Mit KI auslesen'),
                ),
              ]),
              if (_meldung != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_meldung!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12))),
            ]),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 260,
            child: ListView(children: [
              Text('Erkannt (${_werte.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (_name.isNotEmpty) Text('Name: $_name'),
              if (_hersteller.isNotEmpty) Text('Hersteller: $_hersteller'),
              if (_artikel.isNotEmpty) Text('Artikel: $_artikel'),
              const SizedBox(height: 6),
              for (final e in _werte.entries)
                Row(children: [
                  Expanded(child: Text('${felder[e.key]?.label ?? e.key}: ${e.value} ${felder[e.key]?.einheit ?? ''}')),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: 'Wert verwerfen',
                    onPressed: () => setState(() => _werte = {..._werte}..remove(e.key)),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              if (_werte.isEmpty) const Text('Noch nichts erkannt.', style: TextStyle(color: BsFarben.textLeise)),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _DatenblattErgebnis(_k, _werte, _datei, name: _name, hersteller: _hersteller, artikel: _artikel)),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}
