import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/ipad_austausch.dart';
import '../core/speicher.dart';
import '../data/project_store.dart';
import '../mobil/ordner.dart';
import '../ui/widgets.dart';

/// Gerätemodus auf Tablet/Handy: „voll“ (ganze BauSpur, iPad-optimiert) oder
/// „baustelle“ (Erfassen/Nachschlagen). Datei im Dokumente-Ordner der App.
Future<String> geraeteModus({required bool tablet}) async {
  try {
    final f = File(p.join((await getApplicationDocumentsDirectory()).path, 'bauspur_modus.txt'));
    if (f.existsSync()) {
      final m = f.readAsStringSync().trim();
      if (m == 'voll' || m == 'baustelle') return m;
    }
  } catch (_) {}
  return tablet ? 'voll' : 'baustelle';
}

Future<void> geraeteModusSetzen(String modus) async {
  final f = File(p.join((await getApplicationDocumentsDirectory()).path, 'bauspur_modus.txt'));
  f.writeAsStringSync(modus);
}

/// Verbindung zum PC aus der Kopplung der Baustellen-App, sonst abfragen.
Future<PcSpeicher?> pcVerbindung(BuildContext context) async {
  final e = await MobilEinstellungen.laden();
  final v = e.verbindung;
  final adresse = TextEditingController(text: v['art'] == 'pc' ? '${v['adresse'] ?? ''}' : '');
  final code = TextEditingController(text: v['art'] == 'pc' ? '${v['code'] ?? ''}' : '');
  if (!context.mounted) return null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Mit dem PC verbinden'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('BauSpur muss am PC laufen und das Projekt geöffnet haben (gleiches WLAN). Den Kopplungscode findest du am PC unter Einstellungen › Speicher und Abgleich.'),
            const SizedBox(height: 8),
            TextField(controller: adresse, decoration: const InputDecoration(labelText: 'Adresse des PCs (z. B. 192.168.1.20)')),
            TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kopplungscode')),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final l = await pcSuchen();
                  if (l.isNotEmpty) setD(() => adresse.text = l.first.adresse);
                },
                icon: const Icon(Icons.search),
                label: const Text('PC im WLAN suchen'),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Verbinden')),
        ],
      ),
    ),
  );
  if (ok != true || adresse.text.trim().isEmpty) return null;
  e.verbindung = {...v, 'art': 'pc', 'adresse': adresse.text.trim(), 'code': code.text.trim()};
  e.speichern();
  return PcSpeicher(adresse.text.trim(), code: code.text.trim());
}

/// Ganzes Projekt vom PC holen und im Dokumente-Ordner ablegen. Liefert den Projektordner.
Future<String?> projektVomPcHolen(BuildContext context) async {
  final pc = await pcVerbindung(context);
  if (pc == null || !context.mounted) return null;
  try {
    final info = await pc.pruefen();
    final name = '${info['projekt'] ?? ''}'.trim();
    if (name.isEmpty) throw StateError('Am PC ist kein Projekt geöffnet.');
    final Uint8List? zip = await pc.projektHolen();
    if (zip == null) throw StateError('Der PC hat das Projekt nicht geliefert.');
    final ziel = Directory(p.join((await getApplicationDocumentsDirectory()).path, name));
    if (ziel.existsSync()) {
      // alten Stand auf dem iPad zur Seite legen statt löschen
      final stempel = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '');
      ziel.renameSync('${ziel.path}_alt_$stempel');
    }
    ziel.createSync(recursive: true);
    projektEntpacken(zip, ziel.path);
    return ziel.path;
  } catch (e) {
    if (context.mounted) zeigeFehler(context, 'Projekt holen fehlgeschlagen: $e');
    return null;
  }
}

/// Projektstand (Datenbank) an den PC zurückschicken. Am PC wird er erst nach Bestätigung übernommen.
Future<void> projektZumPc(BuildContext context, ProjectStore store) async {
  final pc = await pcVerbindung(context);
  if (pc == null || !context.mounted) return;
  try {
    store.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  } catch (_) {}
  try {
    final ok = await pc.projektZurueck(File(p.join(store.ordner, datenbankDatei)).readAsBytesSync());
    if (!context.mounted) return;
    if (ok) {
      zeigeHinweis(context, 'An den PC geschickt. Am PC unter Einstellungen › Speicher und Abgleich „Stand vom iPad übernehmen“ wählen.');
    } else {
      zeigeFehler(context, 'Der PC hat den Stand nicht angenommen (Projekt dort geöffnet? Code des Eigentümers?).');
    }
  } catch (e) {
    if (context.mounted) zeigeFehler(context, 'Senden fehlgeschlagen: $e');
  }
}
