import 'package:flutter/material.dart';

import '../app/theme.dart';

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

void tastenkuerzelZeigen(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Tastenkürzel'),
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
                    child: Text(taste, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Consolas')),
                  ),
                  Expanded(child: Text(funktion)),
                ]),
              ),
          ],
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
    ),
  );
}
