import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../data/app_settings.dart';

/// Eigene Tastenbelegung: Standardtaste → gewünschte Taste (einzelne Buchstaben),
/// gespeichert in den Benutzereinstellungen (darstellung.tasten).
class TastenBelegung {
  static Map<String, String> karte = const {};

  static void laden(AppSettings s) => karte = {for (final e in (s.darstellung['tasten'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'.toUpperCase()};

  /// Übersetzt die gedrückte Taste in die Standardtaste der Funktion. Eine
  /// Standardtaste, die umbelegt wurde, löst ihre alte Funktion nicht mehr aus.
  static LogicalKeyboardKey uebersetzen(LogicalKeyboardKey k) {
    if (karte.isEmpty || HardwareKeyboard.instance.isControlPressed) return k;
    final label = k.keyLabel.toUpperCase();
    for (final e in karte.entries) {
      if (e.value == label && e.key != label) return _taste(e.key) ?? k;
    }
    if (karte.containsKey(label) && karte[label] != label) return LogicalKeyboardKey.f24; // umbelegt: nichts tun
    return k;
  }

  static LogicalKeyboardKey? _taste(String buchstabe) {
    if (buchstabe.length != 1) return null;
    final c = buchstabe.toLowerCase().codeUnitAt(0);
    if (c < 0x61 || c > 0x7a) return null;
    return LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + (c - 0x61));
  }

  /// Anzeige einer Taste mit eigener Belegung.
  static String anzeige(String standard) => karte[standard] ?? standard;
}

/// Einheitliche Tastenkürzel in allen Planmodulen (Grundriss, Installation,
/// Fotos). Gleiche Taste = gleiche Funktion; F1 zeigt diese Übersicht.
const tastenkuerzel = <(String, List<(String, String)>)>[
  ('Überall', [
    ('F1', 'diese Übersicht'),
    ('V', 'Auswahl'),
    ('Esc', 'abbrechen / Auswahl aufheben'),
    ('Entf', 'Gewähltes löschen'),
    ('Strg+Z', 'rückgängig'),
    ('Enter', 'Eingabe übernehmen / Linienzug beenden'),
    ('Rücktaste', 'letzten Punkt zurücknehmen'),
    ('Umschalt', 'beim Zeichnen: rechtwinklig'),
  ]),
  ('Ansicht', [
    ('Mausrad', 'zoomen'),
    ('Umschalt+Mausrad', 'verschieben'),
    ('rechte / mittlere Maustaste', 'verschieben'),
    ('Leertaste + Ziehen', 'verschieben'),
    ('Pfeiltasten', 'verschieben (ohne Auswahl)'),
    ('Touchpad', 'zwei Finger verschieben, spreizen zoomt'),
  ]),
  ('Grundriss', [
    ('W', 'Wand zeichnen'),
    ('Tab', 'Länge / Winkel eingeben, auf einer Wand: Abstand'),
    ('R', 'Raum anlegen'),
    ('O', 'Tür / Fenster / Durchbruch'),
    ('M', 'Bemaßen'),
    ('K', 'Winkel bemaßen'),
    ('Strg+A', 'alle Wände wählen'),
    ('Pfeiltasten', 'Auswahl verschieben (Umschalt ×10)'),
    ('Doppelklick', 'Maß / Länge direkt bearbeiten'),
  ]),
  ('Installation', [
    ('P', 'Objekt setzen (Platzieren)'),
    ('Doppelklick Wand', 'Wandansicht öffnen'),
  ]),
  ('Wandansicht', [
    ('L', 'Leitung / Rohr zeichnen (auch senkrecht, z. B. zum Verteiler)'),
    ('Enter / Rücktaste', 'Leitung beenden / letzten Punkt zurücknehmen'),
  ]),
  ('Deckenansicht', [
    ('L', 'LED-Streifen / Lichtband zeichnen, Enter beendet'),
    ('P', 'Leuchte / Melder setzen'),
    ('Ziehen', 'Objekt verschieben (Abstände zu den Raumkanten)'),
    ('Esc', 'ohne Auswahl: Deckenansicht schließen'),
  ]),
  ('Fotos', [
    ('I', 'Fotos importieren'),
  ]),
];

void tastenkuerzelZeigen(BuildContext context, {AppSettings? einstellungen}) {
  showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Tastenkürzel')),
        if (einstellungen != null && TastenBelegung.karte.isNotEmpty)
          TextButton(
            onPressed: () {
              einstellungen.darstellung.remove('tasten');
              einstellungen.speichern();
              TastenBelegung.laden(einstellungen);
              setD(() {});
            },
            child: const Text('Standard wiederherstellen'),
          ),
      ]),
      content: SizedBox(
        width: 520,
        child: ListView(shrinkWrap: true, children: [
          for (final (gruppe, liste) in tastenkuerzel) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(gruppe.toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: BsFarben.textLeise)),
            ),
            for (final (taste, funktion) in liste)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Container(
                    width: 190,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: einstellungen != null && taste.length == 1 && RegExp('[A-Z]').hasMatch(taste)
                        ? Row(children: [
                            SizedBox(
                              width: 44,
                              child: TextFormField(
                                key: ValueKey('t-$gruppe-$taste-${TastenBelegung.anzeige(taste)}'),
                                initialValue: TastenBelegung.anzeige(taste),
                                maxLength: 1,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(isDense: true, counterText: ''),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Consolas'),
                                onChanged: (v) {
                                  final neu = v.trim().toUpperCase();
                                  if (neu.isEmpty || !RegExp('[A-Z]').hasMatch(neu)) return;
                                  final m = Map<String, dynamic>.from(einstellungen.darstellung['tasten'] as Map? ?? const {});
                                  if (neu == taste) {
                                    m.remove(taste);
                                  } else {
                                    m[taste] = neu;
                                  }
                                  einstellungen.darstellung['tasten'] = m;
                                  einstellungen.speichern();
                                  TastenBelegung.laden(einstellungen);
                                },
                              ),
                            ),
                            if (TastenBelegung.anzeige(taste) != taste) Text('  (sonst $taste)', style: const TextStyle(fontSize: 11, color: BsFarben.textLeise)),
                          ])
                        : Text(taste, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Consolas')),
                  ),
                  Expanded(child: Text(funktion)),
                ]),
              ),
          ],
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
    )),
  );
}
