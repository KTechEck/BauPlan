import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/leitung_wand.dart';
import '../../data/models.dart';
import '../widgets.dart';

/// Eingabefelder „Lage im Bauteil“ einer Leitung: Verlegeart, Breite (aus
/// Material oder von Hand), Überdeckung (Tiefe der Vorderkante), Schlitzmaße
/// mit Richtwert-Prüfung. [setzen] übernimmt geänderte Eigenschaften
/// (null-Werte entfernen den Schlüssel). [wanddicke] und [senkrecht] für die
/// Schlitzprüfung, wenn bekannt.
List<Widget> leitungLageFelder(BuildContext context, Objekt o, void Function(Map<String, Object?>) setzen, {int? wanddicke, bool? senkrecht}) {
  final eig = o.eigenschaften;
  final l = LeitungImBauteil.aus(eig, lage: o.lage);
  final hand = eig['breite_hand'] == true;
  int? zahl(String v) => int.tryParse(v.trim());
  final schlitzT = l.schlitzT(), schlitzB = l.schlitzB;
  // Schlitzprüfung: senkrecht, wenn die Leitung überwiegend senkrecht läuft
  String? hinweis;
  if (wanddicke != null && l.verlegung.mitSchlitz) {
    final zs = o.zPunkte;
    var senk = senkrecht ?? false;
    var waag = 0.0;
    if (senkrecht == null && zs != null) {
      var dz = 0.0, dxy = 0.0;
      for (var i = 0; i + 1 < zs.length; i++) {
        dz += (zs[i + 1] - zs[i]).abs();
        final d = (o.punkte[i + 1] - o.punkte[i]).laenge;
        dxy += d;
        if ((zs[i + 1] - zs[i]).abs() < d) waag = math.max(waag, d);
      }
      senk = dz >= dxy;
    }
    hinweis = schlitzPruefen(wanddicke: wanddicke, tiefe: schlitzT, breite: schlitzB, senkrecht: senk, laenge: waag);
  }
  return [
    const SizedBox(height: 10),
    Text('Lage im Bauteil', style: Theme.of(context).textTheme.titleSmall),
    const SizedBox(height: 4),
    DropdownButtonFormField<Verlegung>(
      key: ValueKey('verl-${o.id}-${l.verlegung.name}'),
      initialValue: l.verlegung,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Verlegung', isDense: true),
      items: [for (final v in Verlegung.values) DropdownMenuItem(value: v, child: Text(v.label, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => setzen({'verlegung': v?.name, if (eig['tiefe_mm'] == null && v != null) 'tiefe_mm': v.ueberdeckung}),
    ),
    const SizedBox(height: 6),
    Row(children: [
      Expanded(
        child: SpeicherFeld(
          key: ValueKey('lb-${o.id}-${eig['breite_mm']}'),
          initialValue: l.breite == 0 ? '' : l.breite.round().toString(),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: hand ? 'Breite (von Hand)' : 'Breite', suffixText: 'mm', isDense: true),
          onFieldSubmitted: (v) => setzen({'breite_mm': zahl(v), 'breite_hand': zahl(v) == null ? null : true}),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: SpeicherFeld(
          key: ValueKey('lt-${o.id}-${eig['tiefe_mm']}-${l.verlegung.name}'),
          initialValue: '${l.ueberdeckung}',
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Tiefe (Vorderkante)', suffixText: 'mm', isDense: true),
          onFieldSubmitted: (v) => setzen({'tiefe_mm': zahl(v)}),
        ),
      ),
    ]),
    if (l.verlegung.mitSchlitz) ...[
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('sb-${o.id}-${eig['schlitz_b']}-$schlitzB'),
            initialValue: '$schlitzB',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'Schlitz breit${eig['schlitz_b'] == null ? ' (Vorschlag)' : ''}', suffixText: 'mm', isDense: true),
            onFieldSubmitted: (v) => setzen({'schlitz_b': zahl(v)}),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('st-${o.id}-${eig['schlitz_t']}-$schlitzT'),
            initialValue: '$schlitzT',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'Schlitz tief${eig['schlitz_t'] == null ? ' (Vorschlag)' : ''}', suffixText: 'mm', isDense: true),
            onFieldSubmitted: (v) => setzen({'schlitz_t': zahl(v)}),
          ),
        ),
      ]),
    ],
    const SizedBox(height: 4),
    Text(
      l.verlegung == Verlegung.aufputz || l.verlegung == Verlegung.kanal
          ? 'Liegt vor der Wand – Bohr-Check zeigt sie als sichtbar.'
          : 'Achse ${l.achsTiefe.round()} mm, Hinterkante ${l.hinterkante.round()} mm hinter der Oberfläche. Bohr-Check: bis ${l.sicherBohren} mm Tiefe frei.',
      style: const TextStyle(fontSize: 11, color: BsFarben.textLeise),
    ),
    if (hinweis != null)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(hinweis, style: const TextStyle(fontSize: 11, color: Color(0xFFB45309))),
      ),
  ];
}
