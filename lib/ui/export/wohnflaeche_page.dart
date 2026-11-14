import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/dach.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../floorplan/dach_dialog.dart' show dachLesen, gebaeuderahmen;
import '../widgets.dart';

/// Eine Zeile der Wohnflächenberechnung.
typedef WohnZeile = ({String geschoss, Raum raum, double grund, double angerechnet, String regel, bool zaehlt});

/// Räume, die nach WoFlV nicht zur Wohnfläche zählen (Zubehör, Technik, Garage …).
bool zubehoerraum(String name) =>
    RegExp(r'keller|heiz|technik|hausanschluss|garage|werkstatt|wasch(küche|keller)|abstell.*keller|dachboden|spitzboden|schacht', caseSensitive: false).hasMatch(name);

/// Wohnflächenberechnung nach WoFlV für das ganze Projekt: Dachgeschoss mit
/// Höhenstaffel (unter 1 m nicht, 1–2 m zur Hälfte), Balkone/Terrassen/Loggien
/// anteilig (Einstellung `balkon_anteil`, Vorgabe 25 %), Zubehörräume nicht.
/// Je Raum abschaltbar über `raum.eigenschaften['wohnflaeche']`.
List<WohnZeile> wohnflaechen(AppState s) {
  final store = s.store!;
  final anteil = ((store.einstellung<num>('balkon_anteil')) ?? 25) / 100;
  final aus = <WohnZeile>[];
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      final dach = dachLesen(store, g.id);
      final rahmen = gebaeuderahmen(store.waende(g.id));
      for (final r in store.raeume(g.id)) {
        final grund = (r.flaeche ?? 0) / 1e6;
        if (grund <= 0) continue;
        final schalter = r.eigenschaften['wohnflaeche'];
        final zaehlt = schalter is bool ? schalter : !zubehoerraum(r.name);
        double ang;
        String regel;
        if (r.art != RaumArt.raum) {
          ang = grund * anteil;
          regel = '${r.art.label} ${(anteil * 100).round()} %';
        } else if (dach.aktiv && rahmen != null && r.umriss != null) {
          final w = wohnflaeche(r.umriss!, dach, rahmen);
          ang = w.wohn / 1e6;
          regel = w.unter1 > 0 || w.zwischen > 0 ? 'Dachschräge: ${(w.unter1 / 1e6).toStringAsFixed(2)} m² unter 1 m, ${(w.zwischen / 1e6).toStringAsFixed(2)} m² 1–2 m' : 'voll';
        } else {
          ang = grund;
          regel = 'voll';
        }
        aus.add((geschoss: g.kuerzel, raum: r, grund: grund, angerechnet: zaehlt ? ang : 0, regel: zaehlt ? regel : 'zählt nicht (Zubehör/Technik)', zaehlt: zaehlt));
      }
    }
  }
  return aus;
}

String _m2(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} m²';

class WohnflaechePage extends StatefulWidget {
  const WohnflaechePage({super.key, required this.state});
  final AppState state;
  @override
  State<WohnflaechePage> createState() => _WohnflaecheState();
}

class _WohnflaecheState extends State<WohnflaechePage> {
  AppState get _s => widget.state;

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final zeilen = wohnflaechen(_s);
    final summe = zeilen.fold<double>(0, (a, z) => a + z.angerechnet);
    final grund = zeilen.fold<double>(0, (a, z) => a + z.grund);
    final text = StringBuffer('Wohnflächenberechnung nach WoFlV – ${store.name}\n');
    for (final z in zeilen) {
      text.writeln('${z.geschoss}\t${z.raum.name}\t${_m2(z.grund)}\t${_m2(z.angerechnet)}\t${z.regel}');
    }
    text.writeln('Summe Wohnfläche\t\t${_m2(grund)}\t${_m2(summe)}');
    return Scaffold(
      backgroundColor: BsFarben.flaeche,
      appBar: AppBar(
        title: const Text('Wohnfläche nach WoFlV'),
        backgroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text.toString()));
              zeigeHinweis(context, 'Tabelle kopiert (zum Einfügen in Excel/Word).');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Kopieren'),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Wohnfläche ${_m2(summe)} (Grundflächen ${_m2(grund)})', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Lichte Grundflächen aus dem Grundriss. Dachgeschoss mit Dach-Einstellung: unter 1 m Höhe nicht, 1–2 m zur Hälfte. Balkone, Terrassen und Loggien anteilig. '
          'Keller, Technik, Garage zählen nicht (je Raum umschaltbar). Richtwert, kein Aufmaß nach DIN 277.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 260,
          child: SpeicherFeld(
            key: ValueKey('ba-${store.einstellung<num>('balkon_anteil')}'),
            initialValue: '${store.einstellung<num>('balkon_anteil') ?? 25}',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Balkone/Terrassen angerechnet', suffixText: '%', helperText: 'WoFlV: in der Regel 25 %, höchstens 50 %'),
            onFieldSubmitted: (v) {
              final n = int.tryParse(v);
              if (n == null) return;
              store.einstellungSetzen('balkon_anteil', n.clamp(0, 50));
              _s.geaendert();
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: DataTable(columns: const [
            DataColumn(label: Text('Geschoss')),
            DataColumn(label: Text('Raum')),
            DataColumn(label: Text('Grundfläche'), numeric: true),
            DataColumn(label: Text('Wohnfläche'), numeric: true),
            DataColumn(label: Text('Regel')),
            DataColumn(label: Text('zählt')),
          ], rows: [
            for (final z in zeilen)
              DataRow(cells: [
                DataCell(Text(z.geschoss)),
                DataCell(Text(z.raum.name)),
                DataCell(Text(_m2(z.grund))),
                DataCell(Text(_m2(z.angerechnet), style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(z.regel, style: const TextStyle(fontSize: 12))),
                DataCell(Checkbox(
                  value: z.zaehlt,
                  onChanged: (v) {
                    store.raumEigenschaftenSetzen(z.raum.id, {...z.raum.eigenschaften, 'wohnflaeche': v ?? true});
                    _s.geaendert();
                    setState(() {});
                  },
                )),
              ]),
          ]),
        ),
      ]),
    );
  }
}
