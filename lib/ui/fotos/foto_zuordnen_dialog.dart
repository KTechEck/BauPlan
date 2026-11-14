import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/foto_zuordnung.dart';
import '../../core/ki.dart';
import '../../state/app_state.dart';

/// Fotos ohne Raum zuordnen: Vorschläge aus der Aufnahmezeit (offline) und
/// auf Wunsch von der lokalen Bild-KI. Übernommen wird nur, was angehakt ist;
/// jede Zuordnung bleibt am Foto änderbar.
Future<void> fotosZuordnenDialog(BuildContext context, AppState s) async {
  final store = s.store!;
  final gid = s.geschossId;
  if (gid == null) return;
  final fotos = store.fotos(gid);
  final raeume = {for (final r in store.raeume(gid)) r.id: r.name};
  final typen = {for (final t in store.objekttypen()) t.id: t.name};
  final objekte = {for (final o in store.objekte(gid)) o.kennung: (o.id, typen[o.typId] ?? '')};
  final vorschlaege = <String, FotoVorschlag>{
    for (final v in zeitVorschlaege([for (final f in fotos) (id: f.id, zeit: f.aufnahme, raumId: f.raumId)])) v.fotoId: v,
  };
  final an = <String, bool>{for (final k in vorschlaege.keys) k: true};
  final bildmodell = s.settings.ki?['bildmodell'] as String?;
  var laeuft = false;
  String? meldung;

  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      final offen = fotos.where((f) => f.raumId == null).toList();
      Future<void> kiFragen() async {
        setD(() {
          laeuft = true;
          meldung = null;
        });
        var n = 0;
        for (final f in offen.take(20)) {
          if (!c.mounted) break;
          try {
            final a = await ollamaBildFrage(KiEinstellung.ausJson(s.settings.ki), bildmodell!,
                kiFotoAnfrage(raeume.values.toList(), [for (final e in objekte.entries) '${e.key}: ${e.value.$2}']),
                [await File(p.join(store.ordner, f.datei)).readAsBytes()]);
            final r = kiFotoLesen(a);
            if (r == null) continue;
            final raumId = raeume.entries.where((e) => e.value.toLowerCase() == (r.raum ?? '').toLowerCase()).firstOrNull?.key;
            final objektId = objekte[r.objekt]?.$1;
            if (raumId == null && objektId == null) continue;
            setD(() {
              vorschlaege[f.id] = (fotoId: f.id, raumId: raumId ?? vorschlaege[f.id]?.raumId, objektId: objektId, grund: 'KI: ${r.beschreibung}');
              an[f.id] = true;
            });
            n++;
          } catch (e) {
            setD(() => meldung = 'KI: $e');
            break;
          }
        }
        setD(() {
          laeuft = false;
          meldung ??= '$n Vorschläge von der KI.';
        });
      }

      return AlertDialog(
        title: Text('Fotos zuordnen (${offen.length} ohne Raum)'),
        content: SizedBox(
          width: 720,
          height: 480,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Vorschläge aus der Aufnahmezeit: Fotos, die kurz vor oder nach einem schon zugeordneten Foto entstanden sind, '
                'kommen in denselben Raum. Mit der Bild-KI (lokal) gibt es weitere Vorschläge. Übernommen wird nur, was angehakt ist.',
                style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
            if (meldung != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(meldung!, style: const TextStyle(fontSize: 12))),
            const SizedBox(height: 8),
            Expanded(
              child: vorschlaege.isEmpty
                  ? Center(
                      child: Text(offen.isEmpty
                          ? 'Alle Fotos haben einen Raum.'
                          : 'Keine Vorschläge aus der Aufnahmezeit.${bildmodell == null ? ' Für KI-Vorschläge unter Einstellungen › KI-Assistent ein Bildmodell einrichten.' : ''}'))
                  : ListView(children: [
                      for (final v in vorschlaege.values)
                        () {
                          final f = fotos.firstWhere((x) => x.id == v.fotoId);
                          return CheckboxListTile(
                            value: an[v.fotoId] ?? false,
                            onChanged: (b) => setD(() => an[v.fotoId] = b ?? false),
                            secondary: Image.file(File(p.join(store.ordner, f.datei)), width: 64, height: 48, fit: BoxFit.cover,
                                errorBuilder: (c, e, st) => const Icon(Icons.image_outlined)),
                            title: Text([
                              if (v.raumId != null) raeume[v.raumId] ?? '?',
                              if (v.objektId != null) objekte.entries.firstWhere((e) => e.value.$1 == v.objektId).key,
                            ].join(' · ')),
                            subtitle: Text(v.grund, style: const TextStyle(fontSize: 12)),
                          );
                        }(),
                    ]),
            ),
          ]),
        ),
        actions: [
          if (bildmodell != null && offen.isNotEmpty)
            TextButton.icon(
              onPressed: laeuft ? null : kiFragen,
              icon: laeuft ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Mit KI vorschlagen'),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: an.values.any((b) => b)
                ? () {
                    for (final v in vorschlaege.values) {
                      if (an[v.fotoId] != true) continue;
                      if (v.raumId != null) store.fotoMarkerAendern(v.fotoId, {'raum_id': v.raumId});
                      if (v.objektId != null) store.fotoObjektZuordnen(v.fotoId, v.objektId!, true);
                    }
                    s.geaendert();
                    Navigator.pop(c);
                  }
                : null,
            child: const Text('Angehakte übernehmen'),
          ),
        ],
      );
    }),
  );
}
