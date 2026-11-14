import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/ki.dart';
import '../../core/texterkennung.dart';
import '../../core/typenschild.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// Typenschild eines Geräts lesen: Foto wählen (eigenes Objektfoto oder
/// Datei), offline per Windows-Texterkennung auslesen, optional mit der
/// lokalen Bild-KI; Werte prüfen und am Objekt speichern
/// (`eigenschaften.typenschild`, Leistung zusätzlich als `leistung_w`).
Future<void> typenschildDialog(BuildContext context, AppState s, Objekt o) async {
  final store = s.store!;
  final fotos = [for (final f in store.fotos(o.geschossId)) if (f.objektIds.contains(o.id)) f];
  final werte = <String, TextEditingController>{
    for (final k in Typenschild.felder.keys) k: TextEditingController(text: '${(o.eigenschaften['typenschild'] as Map?)?[k] ?? ''}'),
  };
  String? bild;
  String? meldung;
  var laeuft = false;
  final bildmodell = s.settings.ki?['bildmodell'] as String?;

  void uebernehmen(Typenschild t, void Function(void Function()) setD) {
    setD(() {
      for (final e in t.werte.entries) {
        werte[e.key]?.text = e.value is double ? '${e.value}'.replaceAll('.', ',') : '${e.value}';
      }
      meldung = t.leer ? 'Nichts Verwertbares erkannt – Foto schärfer/gerader aufnehmen oder Werte von Hand eintragen.' : '${t.werte.length} Werte erkannt – bitte prüfen.';
    });
  }

  Future<void> lesen(String pfad, void Function(void Function()) setD) async {
    setD(() {
      bild = pfad;
      laeuft = true;
      meldung = null;
    });
    final text = await textErkennen(pfad);
    if (text == null || text.trim().isEmpty) {
      setD(() {
        laeuft = false;
        meldung = 'Kein Text erkannt (Windows-Texterkennung). ${bildmodell != null ? '„Mit KI lesen“ versuchen.' : ''}';
      });
      return;
    }
    setD(() => laeuft = false);
    uebernehmen(typenschildLesen(text), setD);
  }

  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      return AlertDialog(
        title: Text('Typenschild · ${o.kennung}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Foto des Typenschilds wählen. Gelesen wird offline (Windows-Texterkennung), auf Wunsch zusätzlich mit der lokalen Bild-KI.',
                  style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in fotos.take(6))
                  InkWell(
                    onTap: laeuft ? null : () => lesen(p.join(store.ordner, f.datei), setD),
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: bild == p.join(store.ordner, f.datei) ? BsFarben.akzent : BsFarben.rand, width: 2)),
                      child: Image.file(File(p.join(store.ordner, f.datei)), width: 96, height: 72, fit: BoxFit.cover,
                          errorBuilder: (c, e, st) => const SizedBox(width: 96, height: 72, child: Icon(Icons.image_outlined))),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: laeuft
                      ? null
                      : () async {
                          final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Foto', extensions: ['jpg', 'jpeg', 'png'])]);
                          if (f != null) await lesen(f.path, setD);
                        },
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Foto-Datei …'),
                ),
                if (bildmodell != null && bild != null)
                  OutlinedButton.icon(
                    onPressed: laeuft
                        ? null
                        : () async {
                            setD(() => laeuft = true);
                            try {
                              final a = await ollamaBildFrage(KiEinstellung.ausJson(s.settings.ki), bildmodell, kiTypenschildAnfrage, [await File(bild!).readAsBytes()]);
                              final t = kiTypenschildLesen(a);
                              if (t == null) throw const FormatException('keine verwertbare Antwort');
                              uebernehmen(t, setD);
                            } catch (e) {
                              setD(() => meldung = 'KI: $e');
                            } finally {
                              setD(() => laeuft = false);
                            }
                          },
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Mit KI lesen'),
                  ),
                if (laeuft) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              if (meldung != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(meldung!, style: const TextStyle(fontSize: 12))),
              const SizedBox(height: 10),
              Wrap(spacing: 12, runSpacing: 4, children: [
                for (final e in Typenschild.felder.entries)
                  SizedBox(
                    width: 220,
                    child: TextField(controller: werte[e.key], decoration: InputDecoration(labelText: e.value, isDense: true)),
                  ),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              final m = <String, Object>{};
              for (final e in werte.entries) {
                final t = e.value.text.trim();
                if (t.isEmpty) continue;
                final zahl = num.tryParse(t.replaceAll(',', '.'));
                m[e.key] = const {'leistung_w', 'spannung_v', 'strom_a', 'frequenz_hz', 'druck_bar', 'volumen_l', 'gewicht_kg', 'baujahr'}.contains(e.key) && zahl != null ? zahl : t;
              }
              final neu = {...o.eigenschaften};
              if (m.isEmpty) {
                neu.remove('typenschild');
              } else {
                neu['typenschild'] = m;
                if (m['leistung_w'] is num && neu['leistung_w'] == null) neu['leistung_w'] = (m['leistung_w'] as num).round();
              }
              store.objektAendern(o.id, {'eigenschaften': jsonEncode(neu)});
              s.geaendert();
              Navigator.pop(c);
            },
            child: const Text('Am Gerät speichern'),
          ),
        ],
      );
    }),
  );
}
