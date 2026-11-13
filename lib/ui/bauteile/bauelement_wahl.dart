import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../data/bauelement_bibliothek.dart';
import '../../state/app_state.dart';

/// Passende Kategorien zu einem Objekttyp (Kürzel) in der Installation.
List<BauelementKategorie> kategorienFuerKuerzel(String kuerzel) => switch (kuerzel) {
      'SD' || 'SC' || 'TA' || 'ND' || 'AP' || 'HD' || 'DS' || 'RT' => const [BauelementKategorie.elektro],
      'LE' || 'LB' || 'LS' => const [BauelementKategorie.leuchte],
      'PM' || 'BM' || 'RM' || 'ES' || 'FK' => const [BauelementKategorie.sensor],
      'HK' || 'HV' => const [BauelementKategorie.heizkoerper, BauelementKategorie.technik],
      'WC' || 'WT' || 'DU' || 'BW' || 'SP' || 'WM' => const [BauelementKategorie.sanitaer],
      'VB' || 'VH' => const [BauelementKategorie.verbinder],
      'AV' => const [BauelementKategorie.armatur],
      'KM' => const [BauelementKategorie.technik, BauelementKategorie.sonstiges],
      'SR' => const [BauelementKategorie.rohr, BauelementKategorie.kabel],
      'TR' || 'TP' => const [BauelementKategorie.sonstiges],
      'RW' || 'WR' || 'CM' || 'FL' || 'BA' || 'BK' || 'SI' || 'BW' => const [BauelementKategorie.brandschutz],
      _ => const [],
    };

/// Auswahl eines Bauelements aus der Bibliothek (gruppiert, passende Kategorien zuerst).
class BauelementWahl extends StatelessWidget {
  const BauelementWahl({
    super.key,
    required this.state,
    required this.wert,
    required this.onChanged,
    this.kategorien = const [],
    this.nurKategorien = false,
    this.label = 'Produkt aus der Bibliothek',
  });

  final AppState state;
  final String? wert;
  final ValueChanged<Bauelement?> onChanged;
  final List<BauelementKategorie> kategorien;
  final bool nurKategorien;
  final String label;

  @override
  Widget build(BuildContext context) {
    final store = state.store;
    final bib = state.bibliothek;
    final reihenfolge = [
      ...kategorien,
      if (!nurKategorien)
        for (final k in BauelementKategorie.values)
          if (!kategorien.contains(k)) k,
    ];
    final items = <DropdownMenuItem<String?>>[const DropdownMenuItem(value: null, child: Text('– ohne –'))];
    final ids = <String>{};
    for (final k in reihenfolge) {
      final l = bib.auswahl(store, k);
      if (l.isEmpty) continue;
      items.add(DropdownMenuItem<String?>(
        enabled: false,
        value: '__${k.name}',
        child: Text(k.label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BsFarben.textLeise)),
      ));
      for (final e in l) {
        ids.add(e.id);
        items.add(DropdownMenuItem<String?>(
          value: e.id,
          child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(e.anzeige, overflow: TextOverflow.ellipsis)),
        ));
      }
    }
    final aktuell = store == null ? null : bib.fuerProjekt(store, wert);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String?>(
        key: ValueKey('bew-$label-$wert'),
        isExpanded: true,
        menuMaxHeight: 520,
        initialValue: ids.contains(wert) ? wert : null,
        decoration: InputDecoration(labelText: label),
        items: items,
        onChanged: (id) {
          final e = id == null || store == null ? null : bib.fuerProjekt(store, id);
          if (e != null && store != null) BauelementBibliothek.insProjekt(store, e);
          onChanged(e);
        },
      ),
      if (aktuell != null && aktuell.kurzdaten.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(aktuell.kurzdaten, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        ),
    ]);
  }
}

/// Symbol je Kategorie (Liste, Auswahl, Bibliothek).
IconData kategorieSymbol(BauelementKategorie k) => switch (k) {
      BauelementKategorie.balkontuer => Icons.door_sliding_outlined,
      BauelementKategorie.fenster => Icons.window_outlined,
      BauelementKategorie.tuer => Icons.door_front_door_outlined,
      BauelementKategorie.sonnenschutz => Icons.blinds_outlined,
      BauelementKategorie.fensterbank => Icons.horizontal_rule,
      BauelementKategorie.elektro => Icons.power_outlined,
      BauelementKategorie.leuchte => Icons.lightbulb_outline,
      BauelementKategorie.sensor => Icons.sensors,
      BauelementKategorie.brandschutz => Icons.fire_extinguisher,
      BauelementKategorie.schrankgeraet => Icons.electrical_services,
      BauelementKategorie.technik => Icons.heat_pump_outlined,
      BauelementKategorie.heizkoerper => Icons.local_fire_department_outlined,
      BauelementKategorie.sanitaer => Icons.water_drop_outlined,
      BauelementKategorie.verbinder => Icons.plumbing,
      BauelementKategorie.armatur => Icons.tune,
      BauelementKategorie.daemmstoff => Icons.layers_outlined,
      BauelementKategorie.baustoff => Icons.foundation,
      BauelementKategorie.dichtstoff => Icons.format_color_fill,
      BauelementKategorie.kabel => Icons.cable,
      BauelementKategorie.rohr => Icons.linear_scale,
      BauelementKategorie.dose => Icons.radio_button_unchecked,
      BauelementKategorie.kleinmaterial => Icons.hardware_outlined,
      BauelementKategorie.werkzeug => Icons.handyman_outlined,
      BauelementKategorie.sonstiges => Icons.category_outlined,
    };
