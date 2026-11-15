import 'dart:io';

import 'package:flutter/material.dart';

import '../data/sync.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/ipad_austausch.dart';
import '../core/speicher.dart';
import '../core/zip_schreiben.dart';
import '../state/app_state.dart';
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

/// Kennung dieses iPads (einmal erzeugt, im Dokumente-Ordner).
Future<String> geraetKennung() async {
  final f = File(p.join((await getApplicationDocumentsDirectory()).path, 'bauspur_geraet.txt'));
  if (f.existsSync()) return f.readAsStringSync().trim();
  final id = 'ipad-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  f.writeAsStringSync(id);
  return id;
}

/// Projekt vom PC ausleihen und im Dokumente-Ordner ablegen. Liefert den Projektordner.
/// Am PC ist das Projekt danach nur lesbar, bis es zurückgegeben wird.
Future<String?> projektVomPcHolen(BuildContext context) async {
  final art = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Projekt vom PC'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, 'live'),
          child: const ListTile(
            leading: Icon(Icons.sync),
            title: Text('Live mitarbeiten (empfohlen)'),
            subtitle: Text('PC und iPad arbeiten gleichzeitig, Änderungen gehen sofort hin und her. Ohne WLAN arbeitest du weiter, abgeglichen wird beim nächsten Kontakt.'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, 'leihen'),
          child: const ListTile(
            leading: Icon(Icons.lock_clock_outlined),
            title: Text('Ausleihen (lange ohne Netz)'),
            subtitle: Text('Ganzes Projekt mitnehmen; am PC ist es bis zur Rückgabe nur lesbar.'),
          ),
        ),
      ],
    ),
  );
  if (art == null || !context.mounted) return null;
  final pc = await pcVerbindung(context);
  if (pc == null || !context.mounted) return null;
  if (art == 'live') return _liveHolen(context, pc);
  try {
    final info = await pc.pruefen();
    final name = '${info['projekt'] ?? ''}'.trim();
    if (name.isEmpty) throw StateError('Am PC ist kein Projekt geöffnet.');
    final ziel = Directory(p.join((await getApplicationDocumentsDirectory()).path, name));
    // Noch nicht zurückgegebene Ausleihe auf dem iPad? Sonst gingen die iPad-Änderungen verloren.
    final alt = ziel.existsSync() ? Ausleihe.lesen(ziel.path) : null;
    if (alt != null && !alt.amPc && !alt.zurueckgegeben) {
      if (!context.mounted) return null;
      final verwerfen = await frage(context,
          titel: 'Noch nicht zurückgegeben',
          text: 'Auf diesem iPad liegt „$name“ noch als Ausleihe mit Änderungen. Öffne das Projekt und wähle „An PC zurückgeben“.\n\n'
              'Nur wenn du die Änderungen auf dem iPad wirklich verwerfen willst: trotzdem neu holen (der alte Stand bleibt als Ordner „…_alt“ liegen).',
          ja: 'Trotzdem neu holen');
      if (!verwerfen) return null;
    }
    final zip = await pc.projektAusleihen(await geraetKennung(), 'iPad');
    if (ziel.existsSync()) {
      final stempel = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '');
      ziel.renameSync('${ziel.path}_alt_$stempel');
    }
    ziel.createSync(recursive: true);
    projektEntpacken(zip, ziel.path);
    Ausleihe(geraet: await geraetKennung(), name: 'iPad', seit: DateTime.now(), amPc: false, pc: '${info['name'] ?? ''}').schreiben(ziel.path);
    return ziel.path;
  } catch (e) {
    if (context.mounted) zeigeFehler(context, 'Projekt holen fehlgeschlagen: ${'$e'.replaceFirst('Bad state: ', '')}');
    return null;
  }
}

/// Projekt für die Live-Arbeit holen (PC bleibt frei), Abgleichstand ablegen.
Future<String?> _liveHolen(BuildContext context, PcSpeicher pc) async {
  try {
    final info = await pc.pruefen();
    final name = '${info['projekt'] ?? ''}'.trim();
    if (name.isEmpty) throw StateError('Am PC ist kein Projekt geöffnet.');
    final ziel = Directory(p.join((await getApplicationDocumentsDirectory()).path, name));
    final alt = ziel.existsSync() ? Ausleihe.lesen(ziel.path) : null;
    if (alt != null && !alt.amPc && !alt.zurueckgegeben) {
      if (!context.mounted) return null;
      final weiter = await frage(context,
          titel: 'Noch nicht zurückgegeben',
          text: 'Auf diesem iPad liegt „$name“ noch als Ausleihe mit Änderungen. Erst öffnen und „An PC zurückgeben“ – sonst bleibt der alte Stand als Ordner „…_alt“ liegen.',
          ja: 'Trotzdem live holen');
      if (!weiter) return null;
    }
    final geraet = await geraetKennung();
    final (zip, stand, pcZeit) = await pc.projektLive(geraet);
    if (ziel.existsSync()) {
      final stempel = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '');
      ziel.renameSync('${ziel.path}_alt_$stempel');
    }
    ziel.createSync(recursive: true);
    projektEntpacken(zip, ziel.path);
    SyncStand(pc: stand, eigen: -1, dateienSeit: pcZeit, eigeneDateienSeit: DateTime.now(), adresse: pc.adresse, code: pc.code, geraet: geraet).schreiben(ziel.path);
    return ziel.path;
  } catch (e) {
    if (context.mounted) zeigeFehler(context, 'Projekt holen fehlgeschlagen: ${'$e'.replaceFirst('Bad state: ', '')}');
    return null;
  }
}

/// Projekt an den PC zurückgeben: Datenbank und alle seit der Ausleihe neuen oder
/// geänderten Dateien (Fotos, Dokumente). Danach ist die iPad-Kopie nur lesbar.
Future<void> projektZumPc(BuildContext context, AppState state) async {
  final store = state.store!;
  final a = Ausleihe.lesen(store.ordner);
  if (a == null || a.amPc) {
    zeigeFehler(context, 'Dieses Projekt ist kein vom PC ausgeliehenes. Erst „Projekt vom PC holen“.');
    return;
  }
  if (a.zurueckgegeben) {
    zeigeHinweis(context, 'Schon zurückgegeben. Zum Weiterarbeiten neu vom PC holen.');
    return;
  }
  final pc = await pcVerbindung(context);
  if (pc == null || !context.mounted) return;
  try {
    try {
      store.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    final zip = ordnerPacken(store.ordner,
        nach: a.seit.subtract(const Duration(minutes: 1)),
        immer: {datenbankDatei},
        aus: {'backup', 'austausch', 'projekt.lock', ausleiheDatei, '$datenbankDatei-shm'});
    await pc.projektZurueckgeben(a.geraet, zip);
    Ausleihe(geraet: a.geraet, name: a.name, seit: a.seit, amPc: false, zurueckgegeben: true, pc: a.pc).schreiben(store.ordner);
    store.nurLesenSetzen(true);
    state.geaendert();
    if (context.mounted) zeigeHinweis(context, 'Zurückgegeben – der PC hat den Stand übernommen. Diese iPad-Kopie ist jetzt nur zum Lesen.');
  } catch (e) {
    if (context.mounted) zeigeFehler(context, 'Zurückgeben fehlgeschlagen: ${'$e'.replaceFirst('Bad state: ', '')}');
  }
}
