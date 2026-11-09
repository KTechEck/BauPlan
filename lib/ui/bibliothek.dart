import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Farbauswahl aus einer festen Palette.
const farbPalette = <int>[
  0xFFE6A700, 0xFF2F9E44, 0xFF7048E8, 0xFF1C7ED6, 0xFFE03131, 0xFFF08C00,
  0xFF0C8599, 0xFF15AABF, 0xFF8B5A2B, 0xFFC2255C, 0xFF6B7178, 0xFF1C2024,
  // Materialtöne
  0xFFD98B6E, 0xFFC4704F, 0xFFE4E0D2, 0xFFEDEAE0, 0xFFA9AEB3, 0xFFF1EEE6,
  0xFFCED4DA, 0xFFC9A26B, 0xFFF2DC8C, 0xFFB9D8F0, 0xFFB98E5A, 0xFFB7D3D0,
];

Future<int?> farbeWaehlen(BuildContext context, {required String titel, required int aktuell}) {
  return showDialog<int>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titel),
      content: SizedBox(
        width: 340,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in farbPalette)
              InkWell(
                onTap: () => Navigator.pop(c, f),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(f),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: f == aktuell ? BsFarben.leiste : Colors.black12, width: f == aktuell ? 3 : 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class Farbfeld extends StatelessWidget {
  const Farbfeld(this.farbe, {super.key, this.groesse = 24, this.onTap});
  final int farbe;
  final double groesse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          width: groesse,
          height: groesse,
          decoration: BoxDecoration(
            color: Color(farbe),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.black26),
          ),
        ),
      );
}

/// Schnitt durch einen Wandaufbau: Schichten maßstäblich nebeneinander.
class SchichtenVorschau extends StatelessWidget {
  const SchichtenVorschau({super.key, required this.schichten, required this.materialien, this.hoehe = 56});

  final List<Schicht> schichten;
  final Map<String, Baustoff> materialien;
  final double hoehe;

  @override
  Widget build(BuildContext context) {
    final summe = schichten.fold<int>(0, (s, e) => s + e.dicke);
    if (summe <= 0) return SizedBox(height: hoehe);
    return SizedBox(
      height: hoehe,
      child: Row(
        children: [
          for (final s in schichten)
            Expanded(
              flex: s.dicke.clamp(1, 100000),
              child: Tooltip(
                message: '${materialien[s.materialId]?.name ?? '?'} · ${s.dicke} mm',
                child: Container(
                  decoration: BoxDecoration(
                    color: Color(materialien[s.materialId]?.farbe ?? 0xFFDDDDDD),
                    border: const Border.symmetric(vertical: BorderSide(color: Colors.black38, width: 0.5)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ======================================================== Materialien

class MaterialienAnsicht extends StatelessWidget {
  const MaterialienAnsicht({super.key, required this.state});
  final AppState state;

  static const einheiten = ['m²', 'm³', 'm', 'Stk', 'kg'];

  Future<void> _bearbeiten(BuildContext context, {Baustoff? m}) async {
    final store = state.store!;
    final kategorien = {...store.materialien().map((e) => e.kategorie), 'Mauerwerk', 'Beton', 'Trockenbau', 'Holz', 'Dämmung', 'Putz', 'Belag'}.toList();
    final name = TextEditingController(text: m?.name ?? '');
    var kategorie = m?.kategorie ?? kategorien.first;
    var einheit = m?.einheit ?? 'm²';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(m == null ? 'Neues Material' : 'Material bearbeiten'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: kategorie),
                optionsBuilder: (v) => kategorien.where((k) => k.toLowerCase().contains(v.text.toLowerCase())),
                onSelected: (v) => kategorie = v,
                fieldViewBuilder: (c, ctrl, fokus, fertig) => TextField(
                  controller: ctrl,
                  focusNode: fokus,
                  decoration: const InputDecoration(labelText: 'Kategorie'),
                  onChanged: (v) => kategorie = v,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: einheiten.contains(einheit) ? einheit : 'm²',
                decoration: const InputDecoration(labelText: 'Mengeneinheit'),
                items: [for (final e in einheiten) DropdownMenuItem(value: e, child: Text(e))],
                onChanged: (v) => setDialog(() => einheit = v ?? einheit),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(m == null ? 'Anlegen' : 'Speichern')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final kat = kategorie.trim().isEmpty ? 'Sonstiges' : kategorie.trim();
    if (m == null) {
      final farbe = farbPalette[12 + store.materialien().length % 12];
      store.materialAnlegen(name: name.text.trim(), kategorie: kat, farbe: farbe, einheit: einheit);
    } else {
      store.materialAendern(m.id, name: name.text.trim(), kategorie: kat, einheit: einheit);
    }
    state.geaendert();
  }

  Future<void> _loeschen(BuildContext context, Baustoff m) async {
    final n = state.store!.materialVerwendung(m.id);
    final ja = await frage(
      context,
      titel: '„${m.name}“ löschen?',
      text: n == 0
          ? 'Das Material wird aus der Bibliothek entfernt (im Änderungsprotokoll bleibt es erhalten).'
          : 'Das Material steckt noch in $n Wandtyp(en). Diese behalten die Schicht, '
              'sie wird dort aber als unbekanntes Material angezeigt.',
      ja: 'Löschen',
    );
    if (!ja) return;
    state.store!.materialLoeschen(m.id);
    state.geaendert();
  }

  @override
  Widget build(BuildContext context) {
    final store = state.store!;
    final materialien = store.materialien();
    final gruppen = <String, List<Baustoff>>{};
    for (final m in materialien) {
      (gruppen[m.kategorie] ??= []).add(m);
    }
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text('Projekteinstellung · gilt für alle Geräte und Nutzer',
            style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        Row(children: [
          Expanded(child: Text('Materialien', style: Theme.of(context).textTheme.headlineSmall)),
          FilledButton.icon(
            onPressed: () => _bearbeiten(context),
            icon: const Icon(Icons.add),
            label: const Text('Material'),
          ),
        ]),
        const SizedBox(height: 8),
        const Text('Baustoffe für Wände, Decken, Böden und Dämmung. Die Farbe erscheint im Grundriss '
            'in den Schichten der Wände; die Mengeneinheit gilt später für die Kosten.'),
        const SizedBox(height: 16),
        for (final e in gruppen.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(e.key.toUpperCase(),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: BsFarben.textLeise)),
          ),
          Card(
            child: Column(children: [
              for (final m in e.value)
                ListTile(
                  dense: true,
                  leading: Farbfeld(
                    m.farbe,
                    groesse: 28,
                    onTap: () async {
                      final f = await farbeWaehlen(context, titel: 'Farbe für ${m.name}', aktuell: m.farbe);
                      if (f == null) return;
                      store.materialAendern(m.id, farbe: f);
                      state.geaendert();
                    },
                  ),
                  title: Text(m.name),
                  subtitle: Text('Menge in ${m.einheit}'),
                  onTap: () => _bearbeiten(context, m: m),
                  trailing: IconButton(
                    tooltip: 'Löschen',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _loeschen(context, m),
                  ),
                ),
            ]),
          ),
        ],
      ],
    );
  }
}

// ========================================================== Wandtypen

class WandtypenAnsicht extends StatefulWidget {
  const WandtypenAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<WandtypenAnsicht> createState() => _WandtypenAnsichtState();
}

class _WandtypenAnsichtState extends State<WandtypenAnsicht> {
  String? _auswahl;
  List<Schicht>? _entwurf; // ungespeicherte Schichten des gewählten Typs
  final _name = TextEditingController();
  int _feldVersion = 0; // erneuert die Dickenfelder nach Speichern/Verwerfen

  AppState get _s => widget.state;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _waehlen(Wandtyp t) {
    setState(() {
      _auswahl = t.id;
      _entwurf = null;
      _name.text = t.name;
      _feldVersion++;
    });
  }

  Future<void> _neu({Wandtyp? vorlage}) async {
    final store = _s.store!;
    final name = await texteingabe(context,
        titel: vorlage == null ? 'Neuer Wandtyp' : 'Wandtyp kopieren',
        feld: 'Name',
        vorschlag: vorlage == null ? 'Innenwand' : '${vorlage.name} (Kopie)');
    if (name == null || name.trim().isEmpty) return;
    final materialien = store.materialien();
    final schichten = vorlage?.schichten ??
        [
          if (materialien.isNotEmpty)
            Schicht((materialien.where((m) => m.kategorie == 'Mauerwerk').firstOrNull ?? materialien.first).id, 240),
        ];
    final id = store.wandtypAnlegen(name.trim(), schichten);
    _s.geaendert();
    final t = store.wandtyp(id);
    if (t != null) _waehlen(t);
  }

  Future<void> _loeschen(Wandtyp t) async {
    final n = _s.store!.wandtypVerwendung(t.id);
    final ja = await frage(
      context,
      titel: '„${t.name}“ löschen?',
      text: n == 0
          ? 'Der Wandtyp wird aus der Liste entfernt.'
          : '$n Wand/Wände nutzen diesen Typ. Sie behalten ihre Dicke und gelten danach als Wand ohne Typ.',
      ja: 'Löschen',
    );
    if (!ja) return;
    _s.store!.wandtypLoeschen(t.id);
    setState(() {
      _auswahl = null;
      _entwurf = null;
    });
    _s.geaendert();
  }

  void _speichern(Wandtyp t) {
    final store = _s.store!;
    final entwurf = _entwurf;
    if (entwurf != null) {
      if (entwurf.isEmpty || entwurf.any((e) => e.dicke <= 0)) {
        zeigeFehler(context, 'Jede Schicht braucht eine Dicke über 0 mm.');
        return;
      }
      store.wandtypSchichtenSetzen(t.id, entwurf);
    }
    final name = _name.text.trim();
    if (name.isNotEmpty && name != t.name) store.wandtypUmbenennen(t.id, name);
    setState(() {
      _entwurf = null;
      _feldVersion++;
    });
    _s.geaendert();
    final n = store.wandtypVerwendung(t.id);
    if (entwurf != null && n > 0) zeigeHinweis(context, '$n Wand/Wände auf die neue Dicke angepasst.');
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final typen = store.wandtypen();
    final materialien = {for (final m in store.materialien()) m.id: m};
    final t = typen.where((e) => e.id == _auswahl).firstOrNull;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 380,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 28, 12, 28),
            children: [
              const Text('Projekteinstellung · gilt für alle Geräte und Nutzer',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              Row(children: [
                Expanded(child: Text('Wandtypen', style: Theme.of(context).textTheme.headlineSmall)),
                FilledButton.icon(onPressed: _neu, icon: const Icon(Icons.add), label: const Text('Wandtyp')),
              ]),
              const SizedBox(height: 8),
              const Text('Mehrschichtige Wände, z. B. Mauerwerk + WDVS + Putz. Im Grundriss wählen und '
                  'zuweisen; die Wanddicke ergibt sich aus den Schichten.'),
              const SizedBox(height: 16),
              Card(
                child: Column(children: [
                  for (final w in typen)
                    ListTile(
                      selected: w.id == _auswahl,
                      selectedTileColor: BsFarben.akzentHell,
                      title: Text(w.name),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          SizedBox(
                            width: 120,
                            child: SchichtenVorschau(schichten: w.schichten, materialien: materialien, hoehe: 14),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text('${w.dicke} mm · ${w.schichten.length} Schichten',
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ),
                      onTap: () => _waehlen(w),
                    ),
                ]),
              ),
            ],
          ),
        ),
        Expanded(
          child: t == null
              ? const Center(child: Text('Links einen Wandtyp wählen oder neu anlegen.'))
              : _editor(t, materialien),
        ),
      ],
    );
  }

  Widget _editor(Wandtyp t, Map<String, Baustoff> materialien) {
    final store = _s.store!;
    final schichten = _entwurf ?? t.schichten;
    final summe = schichten.fold<int>(0, (s, e) => s + e.dicke);
    final verwendung = store.wandtypVerwendung(t.id);
    final liste = materialien.values.toList();
    final geaendert = _entwurf != null || _name.text.trim() != t.name;

    void setzen(List<Schicht> neu) => setState(() => _entwurf = neu);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 28, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  const Text('Seite 1', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                  const Spacer(),
                  Text('Gesamt $summe mm', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const Text('Seite 2', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                ]),
                const SizedBox(height: 6),
                SchichtenVorschau(schichten: schichten, materialien: materialien),
                const SizedBox(height: 6),
                const Text(
                  'Seite 1 liegt links der Zeichenrichtung. Im Grundriss dreht „Wand umdrehen“ den Aufbau.',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < schichten.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(color: BsFarben.textLeise))),
                      Farbfeld(materialien[schichten[i].materialId]?.farbe ?? 0xFFDDDDDD),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('m-$_feldVersion-$i-${schichten[i].materialId}'),
                          initialValue: materialien.containsKey(schichten[i].materialId) ? schichten[i].materialId : null,
                          hint: const Text('unbekanntes Material'),
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Material'),
                          items: [
                            for (final m in liste)
                              DropdownMenuItem(value: m.id, child: Text('${m.name} · ${m.kategorie}', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setzen([...schichten]..[i] = Schicht(v, schichten[i].dicke));
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 110,
                        child: TextFormField(
                          key: ValueKey('d-$_feldVersion-$i-${schichten.length}'),
                          initialValue: '${schichten[i].dicke}',
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Dicke', suffixText: 'mm'),
                          onChanged: (v) {
                            final d = int.tryParse(v) ?? 0;
                            setzen([...schichten]..[i] = Schicht(schichten[i].materialId, d));
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'nach Seite 1',
                        onPressed: i == 0
                            ? null
                            : () {
                                final l = [...schichten];
                                l.insert(i - 1, l.removeAt(i));
                                _feldVersion++;
                                setzen(l);
                              },
                        icon: const Icon(Icons.arrow_upward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'nach Seite 2',
                        onPressed: i == schichten.length - 1
                            ? null
                            : () {
                                final l = [...schichten];
                                l.insert(i + 1, l.removeAt(i));
                                _feldVersion++;
                                setzen(l);
                              },
                        icon: const Icon(Icons.arrow_downward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Schicht entfernen',
                        onPressed: schichten.length <= 1
                            ? null
                            : () {
                                _feldVersion++;
                                setzen([...schichten]..removeAt(i));
                              },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ]),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: liste.isEmpty
                        ? null
                        : () {
                            _feldVersion++;
                            setzen([...schichten, Schicht(liste.firstWhere((m) => m.kategorie == 'Putz', orElse: () => liste.first).id, 15)]);
                          },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Schicht hinzufügen'),
                  ),
                ),
                const Divider(height: 28),
                Row(children: [
                  Expanded(
                    child: Text(
                      verwendung == 0 ? 'Noch keiner Wand zugewiesen.' : 'Verwendet von $verwendung Wand/Wänden – deren Dicke wird beim Speichern angepasst.',
                      style: const TextStyle(fontSize: 12, color: BsFarben.textLeise),
                    ),
                  ),
                  TextButton(onPressed: () => _neu(vorlage: t), child: const Text('Kopieren')),
                  TextButton(onPressed: () => _loeschen(t), child: const Text('Löschen')),
                  const SizedBox(width: 8),
                  if (geaendert)
                    TextButton(
                      onPressed: () => _waehlen(t),
                      child: const Text('Verwerfen'),
                    ),
                  FilledButton(onPressed: geaendert ? () => _speichern(t) : null, child: const Text('Speichern')),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
