import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app/symbole.dart';
import '../app/theme.dart';
import '../core/sensoren.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Sensor-Vorlagen des Projekts (Einstellung `sensoren`).
List<SensorVorlage> sensorVorlagen(AppState s) => [
      for (final m in (s.store!.einstellung<List>('sensoren') ?? const [])) SensorVorlage.ausJson(Map<String, dynamic>.from(m as Map)),
    ];

/// Bibliothek → Eigene Sensoren: Vorlagen anlegen und bearbeiten,
/// Dateien ablegen, als Inhaltspaket weitergeben.
class SensorenAnsicht extends StatefulWidget {
  const SensorenAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<SensorenAnsicht> createState() => _SensorenAnsichtState();
}

class _SensorenAnsichtState extends State<SensorenAnsicht> {
  String? _auswahl;
  AppState get _s => widget.state;

  void _speichern(List<SensorVorlage> liste) {
    _s.store!.einstellungSetzen('sensoren', [for (final v in liste) v.toJson()]);
    _s.geaendert();
  }

  void _aendern(SensorVorlage v) => _speichern([for (final x in sensorVorlagen(_s)) x.id == v.id ? v : x]);

  Future<void> _paketExport() async {
    final ort = await getSaveLocation(suggestedName: 'Sensoren.bauspur-paket.json', acceptedTypeGroups: const [
      XTypeGroup(label: 'Inhaltspaket', extensions: ['json']),
    ]);
    if (ort == null) return;
    await File(ort.path).writeAsString(inhaltspaket(sensorVorlagen(_s)));
    if (mounted) zeigeHinweis(context, 'Inhaltspaket gespeichert: ${ort.path}');
  }

  Future<void> _paketImport() async {
    final datei = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Inhaltspaket', extensions: ['json'])]);
    if (datei == null) return;
    try {
      final neu = inhaltspaketLesen(await File(datei.path).readAsString());
      final vorhanden = sensorVorlagen(_s);
      final ids = {for (final v in vorhanden) v.id};
      _speichern([...vorhanden, for (final v in neu) if (!ids.contains(v.id)) v]);
      if (mounted) zeigeHinweis(context, '${neu.where((v) => !ids.contains(v.id)).length} Sensoren übernommen.');
    } on FormatException catch (e) {
      if (mounted) zeigeFehler(context, e.message);
    }
  }

  Future<void> _dateiHinzu(SensorVorlage v) async {
    final datei = await openFile();
    if (datei == null) return;
    final rel = p.join('dokumente', 'sensoren', v.id, p.basename(datei.path));
    final ziel = File(p.join(_s.store!.ordner, rel));
    await ziel.parent.create(recursive: true);
    await File(datei.path).copy(ziel.path);
    _aendern(v.mit(dateien: [...v.dateien, rel]));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final liste = sensorVorlagen(_s);
        final v = liste.where((x) => x.id == _auswahl).firstOrNull ?? liste.firstOrNull;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 260,
            child: Material(
              color: Colors.white,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                Text('Eigene Sensoren', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('Vorlagen für selbst gebaute Sensoren; in der Installation beim Objekt „Eigener Sensor“ wählbar.',
                    style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                const SizedBox(height: 8),
                for (final x in liste)
                  ListTile(
                    dense: true,
                    selected: x.id == v?.id,
                    title: Text(x.name),
                    subtitle: Text('${x.kategorie} · ${x.protokoll}'),
                    onTap: () => setState(() => _auswahl = x.id),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    final neu = SensorVorlage(
                      id: '${DateTime.now().microsecondsSinceEpoch}',
                      name: 'Neuer Sensor',
                      anschluesse: const [(name: '+5 V', farbe: 'rot'), (name: 'GND', farbe: 'schwarz'), (name: 'Daten', farbe: 'gelb')],
                      entitaeten: const ['temperatur', 'feuchte'],
                    );
                    _speichern([...liste, neu]);
                    setState(() => _auswahl = neu.id);
                  },
                  icon: const Icon(Sym.hinzufuegen),
                  label: const Text('Sensor'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _paketImport, icon: const Icon(Icons.file_download_outlined, size: 18), label: const Text('Inhaltspaket laden')),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: liste.isEmpty ? null : _paketExport,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Als Inhaltspaket speichern'),
                ),
              ]),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: v == null ? const Center(child: Text('Noch keine eigenen Sensoren.')) : _editor(v, liste)),
        ]);
      },
    );
  }

  Widget _editor(SensorVorlage v, List<SensorVorlage> liste) {
    Widget zahl(String label, int wert, SensorVorlage Function(int) setzen) => Expanded(
          child: SpeicherFeld(
            key: ValueKey('$label-${v.id}-$wert'),
            initialValue: wert == 0 ? '' : '$wert',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, suffixText: 'mm'),
            onFieldSubmitted: (x) => _aendern(setzen(int.tryParse(x) ?? 0)),
          ),
        );
    Widget auswahl(String label, String wert, List<String> werte, SensorVorlage Function(String) setzen) => DropdownButtonFormField<String>(
          key: ValueKey('$label-${v.id}-$wert'),
          initialValue: werte.contains(wert) ? wert : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final w in werte) DropdownMenuItem(value: w, child: Text(w))],
          onChanged: (x) => x == null ? null : _aendern(setzen(x)),
        );

    return ListView(padding: const EdgeInsets.all(20), children: [
      SpeicherFeld(
        key: ValueKey('name-${v.id}-${v.name}'),
        initialValue: v.name,
        style: Theme.of(context).textTheme.titleLarge,
        decoration: const InputDecoration(labelText: 'Name'),
        onFieldSubmitted: (x) => x.trim().isEmpty ? null : _aendern(v.mit(name: x.trim())),
      ),
      Row(children: [
        Expanded(child: auswahl('Kategorie', v.kategorie, sensorKategorien, (x) => v.mit(kategorie: x))),
        const SizedBox(width: 12),
        Expanded(child: auswahl('Montage', v.montage, sensorMontagen, (x) => v.mit(montage: x))),
      ]),
      Row(children: [
        Expanded(child: auswahl('Schnittstelle / Protokoll', v.protokoll, sensorProtokolle, (x) => v.mit(protokoll: x))),
        const SizedBox(width: 12),
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('vers-${v.id}-${v.versorgung}'),
            initialValue: v.versorgung,
            decoration: const InputDecoration(labelText: 'Versorgung'),
            onFieldSubmitted: (x) => _aendern(v.mit(versorgung: x.trim())),
          ),
        ),
      ]),
      Row(children: [
        zahl('Breite', v.breite, (x) => v.mit(breite: x)),
        const SizedBox(width: 12),
        zahl('Höhe', v.hoehe, (x) => v.mit(hoehe: x)),
        const SizedBox(width: 12),
        zahl('Tiefe', v.tiefe, (x) => v.mit(tiefe: x)),
      ]),
      const SizedBox(height: 16),
      Text('Anschlüsse', style: Theme.of(context).textTheme.titleSmall),
      for (var i = 0; i < v.anschluesse.length; i++)
        Row(children: [
          Expanded(
            child: SpeicherFeld(
              key: ValueKey('an-${v.id}-$i-${v.anschluesse[i].name}'),
              initialValue: v.anschluesse[i].name,
              decoration: const InputDecoration(labelText: 'Bezeichnung'),
              onFieldSubmitted: (x) => _aendern(v.mit(anschluesse: [
                for (var j = 0; j < v.anschluesse.length; j++) j == i ? (name: x.trim(), farbe: v.anschluesse[j].farbe) : v.anschluesse[j],
              ])),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<String>(
              key: ValueKey('af-${v.id}-$i-${v.anschluesse[i].farbe}'),
              isExpanded: true,
              initialValue: aderfarben.contains(v.anschluesse[i].farbe) ? v.anschluesse[i].farbe : null,
              decoration: const InputDecoration(labelText: 'Aderfarbe'),
              items: [for (final f in aderfarben) DropdownMenuItem(value: f, child: Text(f))],
              onChanged: (x) => _aendern(v.mit(anschluesse: [
                for (var j = 0; j < v.anschluesse.length; j++) j == i ? (name: v.anschluesse[j].name, farbe: x ?? '') : v.anschluesse[j],
              ])),
            ),
          ),
          IconButton(
            icon: const Icon(Sym.loeschen, size: 18),
            onPressed: () => _aendern(v.mit(anschluesse: [for (var j = 0; j < v.anschluesse.length; j++) if (j != i) v.anschluesse[j]])),
          ),
        ]),
      TextButton.icon(
        onPressed: () => _aendern(v.mit(anschluesse: [...v.anschluesse, (name: 'Anschluss ${v.anschluesse.length + 1}', farbe: 'weiß')])),
        icon: const Icon(Sym.hinzufuegen, size: 18),
        label: const Text('Anschluss'),
      ),
      const SizedBox(height: 12),
      SpeicherFeld(
        key: ValueKey('ent-${v.id}-${v.entitaeten.join(',')}'),
        initialValue: v.entitaeten.join(', '),
        decoration: const InputDecoration(
          labelText: 'Home-Assistant-Entitäten (Vorlage)',
          helperText: 'durch Komma getrennt, z. B. temperatur, feuchte, co2 – jede eingebaute Instanz bekommt eigene IDs',
        ),
        onFieldSubmitted: (x) => _aendern(v.mit(entitaeten: [for (final e in x.split(',')) if (e.trim().isNotEmpty) e.trim().toLowerCase()])),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Text('Dateien', style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        TextButton.icon(onPressed: () => _dateiHinzu(v), icon: const Icon(Icons.attach_file, size: 18), label: const Text('Datei ablegen')),
      ]),
      const Text('Schaltplan, Firmware, 3D-Druck-Gehäuse (STL/STEP), Fotos – werden in den Projektordner kopiert.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      for (final d in v.dateien)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.insert_drive_file_outlined, size: 18),
          title: Text(p.basename(d)),
          trailing: IconButton(
            icon: const Icon(Sym.loeschen, size: 18),
            onPressed: () => _aendern(v.mit(dateien: [for (final x in v.dateien) if (x != d) x])),
          ),
        ),
      const SizedBox(height: 12),
      SpeicherFeld(
        key: ValueKey('notiz-${v.id}-${v.notiz}'),
        initialValue: v.notiz,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Notiz'),
        onFieldSubmitted: (x) => _aendern(v.mit(notiz: x)),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: () {
          _speichern([for (final x in liste) if (x.id != v.id) x]);
          setState(() => _auswahl = null);
        },
        icon: const Icon(Sym.loeschen),
        label: const Text('Vorlage löschen'),
      ),
    ]);
  }
}
