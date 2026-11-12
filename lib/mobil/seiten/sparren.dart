import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/ids.dart';
import '../../core/sparren.dart';
import '../kontext.dart';
import '../planstand.dart';
import 'aufmass.dart';

/// Sparrenfelder eines Geschosses: vom PC und hier neu angelegte.
List<Map<String, dynamic>> appSparrenfelder(MobilKontext k, Map<String, dynamic> geschoss) {
  final plan = Planstand.liste(geschoss['sparren']);
  final ids = {for (final f in plan) f['id']};
  return [
    ...plan,
    for (final e in k.einstellungen.aufmass.entries)
      if (e.key.startsWith('sparrenfeld|') && e.value['geschoss'] == geschoss['id'] && !ids.contains(e.key.substring(12)))
        Map<String, dynamic>.from(e.value['json'] as Map),
  ];
}

/// Feld mit den hier gemessenen Werten (für Anzeige im Plan).
Sparrenfeld appSparrenfeld(MobilKontext k, Map<String, dynamic> f) {
  var s = Sparrenfeld.ausJson(f);
  for (final feld in [...sparrenFelder.keys, for (var i = 0; i < 80; i++) 'pos_$i']) {
    final g = k.gemessen(f, feld);
    if (g != null && !g.uebernommen) s = s.mitWert(feld, g.wert);
  }
  return s;
}

/// Neues Sparrenfeld an einer Wand anlegen (ganzes Geschoss oder nur Raum).
Future<void> sparrenfeldAnlegen(BuildContext context, MobilKontext k, Map<String, dynamic> g, Map<String, dynamic> w, bool links, {required bool geschossweit}) async {
  final s = AppWandSeite(w, links);
  final raum = s.raumId;
  double t1 = 0, t2 = s.achse;
  if (!geschossweit && raum != null) {
    for (final st in (w[links ? 'sl' : 'sr'] as List? ?? const [])) {
      if ((st as List)[0] == raum) {
        t1 = (st[1] as num).toDouble();
        t2 = (st[2] as num).toDouble();
      }
    }
  }
  final a = s.a + s.u * t1, b = s.a + s.u * t2;
  final id = neueId();
  final f = Sparrenfeld(id: id, ax: a.dx, ay: a.dy, bx: b.dx, by: b.dy, seite: links ? 1 : -1, raumId: geschossweit ? null : raum).toJson();
  k.einstellungen.aufmass['sparrenfeld|$id'] = {'wert': 0, 'zeit': DateTime.now().toUtc().toIso8601String(), 'json': f, 'geschoss': g['id']};
  await k.massSenden(ziel: 'sparren', objekt: f, feld: 'neu', wert: 0, plan: 0, raum: raum, extra: {'feld_json': f});
  if (context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SparrenSeite(k: k, geschoss: g, feldId: id)));
  }
}

/// Sparren aufmessen: Achsabstand, Querschnitt, Länge mit Überstand, Neigung
/// und auf Wunsch jeden Sparren einzeln ab Linienanfang.
class SparrenSeite extends StatefulWidget {
  const SparrenSeite({super.key, required this.k, required this.geschoss, this.feldId});
  final MobilKontext k;
  final Map<String, dynamic> geschoss;
  final String? feldId;

  @override
  State<SparrenSeite> createState() => _SparrenSeiteState();
}

class _SparrenSeiteState extends State<SparrenSeite> {
  late String? _id = widget.feldId;

  MobilKontext get k => widget.k;

  Future<void> _messen(Map<String, dynamic> f, String feld, String titel, num plan) async {
    ({int wert, String text})? e;
    if (feld == 'neigung') {
      final c = TextEditingController(text: '${k.gemessen(f, feld)?.wert ?? plan}');
      final v = await showDialog<int>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Dachneigung'),
          content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: '°')),
          actions: [FilledButton(onPressed: () => Navigator.pop(d, int.tryParse(c.text.trim())), child: const Text('OK'))],
        ),
      );
      if (v != null) e = (wert: v, text: '');
    } else {
      e = await massEingeben(context, titel: titel, plan: plan, bisher: k.gemessen(f, feld)?.wert);
    }
    if (e == null) return;
    await k.massSenden(ziel: 'sparren', objekt: f, feld: feld, wert: e.wert, plan: plan, raum: f['raum'] as String?, text: e.text);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final felder = appSparrenfelder(k, widget.geschoss);
    final f = felder.where((x) => x['id'] == _id).firstOrNull ?? felder.firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Sparren aufmessen')),
      body: felder.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Noch kein Sparrenfeld. Im Plan die Traufwand antippen › „Sparren hier anlegen“ (ganzes Geschoss oder nur der Raum).', textAlign: TextAlign.center),
            ))
          : ListView(padding: const EdgeInsets.all(12), children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in felder)
                  ChoiceChip(
                    label: Text('${x['art'] ?? 'Sparren'}${x['raum'] == null ? ' · Geschoss' : ' · ${k.plan.raumName(x['raum'] as String)}'}'),
                    selected: x['id'] == f?['id'],
                    onSelected: (_) => setState(() => _id = x['id'] as String),
                  ),
              ]),
              if (f != null) ...[
                const SizedBox(height: 8),
                Text('${appSparrenfeld(k, f).lagen.length} Sparren · Linie ${mmCm(Sparrenfeld.ausJson(f).linienlaenge)}', style: const TextStyle(color: BsFarben.textLeise)),
                for (final e in sparrenFelder.entries)
                  Builder(builder: (_) {
                    final plan = (f[e.key] as num?) ?? 0;
                    final a = e.key == 'neigung'
                        ? (text: '${k.gemessen(f, e.key)?.wert ?? plan}°', farbe: k.gemessen(f, e.key) == null ? massGrob : massOffen)
                        : massAnzeige(k, f, e.key, plan);
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.straighten),
                      title: Text(e.value),
                      trailing: Text(a.text, style: TextStyle(fontWeight: FontWeight.w700, color: a.farbe)),
                      onTap: () => _messen(f, e.key, e.value, plan),
                    );
                  }),
                const Divider(),
                const Text('Einzeln einmessen (alte Dächer mit ungleichen Abständen): Abstand jedes Sparrens (Mitte) ab Linienanfang.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                for (var i = 0; i < appSparrenfeld(k, f).lagen.length + 1; i++)
                  Builder(builder: (_) {
                    final lagen = appSparrenfeld(k, f).lagen;
                    final plan = i < lagen.length ? lagen[i] : (lagen.isEmpty ? 0.0 : lagen.last + ((f['achsabstand'] as num?) ?? 750));
                    final a = massAnzeige(k, f, 'pos_$i', plan);
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 10))),
                      title: Text(i < lagen.length ? 'Sparren ${i + 1}' : 'weiterer Sparren'),
                      trailing: Text(a.text, style: TextStyle(fontWeight: FontWeight.w700, color: a.farbe)),
                      onTap: () => _messen(f, 'pos_$i', 'Sparren ${i + 1}: Abstand ab Linienanfang', plan),
                    );
                  }),
              ],
            ]),
    );
  }
}
