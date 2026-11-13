import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../kontext.dart';
import '../planstand.dart';

/// Maß eintippen (wie mit dem Zollstock/Laser gemessen): Einheit wählbar,
/// Planwert und Abweichung sofort sichtbar. Liefert mm.
Future<({int wert, String text})?> massEingeben(BuildContext context, {required String titel, required num plan, int? bisher, String? hinweis, int verkleidung = 0}) {
  return showModalBottomSheet<({int wert, String text})>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: _MassEingabe(titel: titel, plan: plan, bisher: bisher, hinweis: hinweis, verkleidung: verkleidung),
    ),
  );
}

class _MassEingabe extends StatefulWidget {
  const _MassEingabe({required this.titel, required this.plan, this.bisher, this.hinweis, this.verkleidung = 0});
  final int verkleidung; // je Wandseite; fertig gemessen = Rohbau − 2 × Verkleidung
  final String titel;
  final num plan;
  final int? bisher;
  final String? hinweis;

  @override
  State<_MassEingabe> createState() => _MassEingabeState();
}

class _MassEingabeState extends State<_MassEingabe> {
  String _einheit = 'cm';
  bool _istFertig = false;
  final _ctrl = TextEditingController();
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    final b = widget.bisher;
    if (b != null) _ctrl.text = (b / 10).toStringAsFixed(b % 10 == 0 ? 0 : 1).replaceAll('.', ',');
  }

  /// Rohbaumaß in mm (fertig gemessen → Verkleidung beider Enden dazu).
  int? get _mm {
    final z = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    if (z == null || z <= 0) return null;
    return (z * switch (_einheit) { 'm' => 1000, 'cm' => 10, _ => 1 }).round() + (_istFertig ? 2 * widget.verkleidung : 0);
  }

  @override
  Widget build(BuildContext context) {
    final mm = _mm;
    final diff = mm == null ? null : mm - widget.plan;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.titel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Plan (grob gezeichnet): ${mmCm(widget.plan)}', style: const TextStyle(color: BsFarben.textLeise)),
          if (widget.hinweis != null) Text(widget.hinweis!, style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                decoration: const InputDecoration(labelText: 'Gemessen'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _fertig(),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'mm', label: Text('mm')), ButtonSegment(value: 'cm', label: Text('cm')), ButtonSegment(value: 'm', label: Text('m'))],
              selected: {_einheit},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _einheit = v.first),
            ),
          ]),
          if (widget.verkleidung > 0) ...[
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: false, label: Text('Rohbau gemessen')),
                ButtonSegment(value: true, label: Text('fertig (−${2 * widget.verkleidung} mm)')),
              ],
              selected: {_istFertig},
              onSelectionChanged: (v) => setState(() => _istFertig = v.first),
            ),
          ],
          const SizedBox(height: 8),
          if (diff != null)
            Text('= ${mmCm(mm!)}${_istFertig ? ' Rohbau' : ''} · Abweichung zum Plan ${diff >= 0 ? '+' : ''}${mmCm(diff)}',
                style: TextStyle(fontWeight: FontWeight.w600, color: diff.abs() > 50 ? massOffen : massGemessen)),
          const SizedBox(height: 8),
          TextField(controller: _text, decoration: const InputDecoration(labelText: 'Bemerkung (optional)', isDense: true)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: mm == null ? null : _fertig, icon: const Icon(Icons.check), label: const Text('Maß speichern'))),
        ]),
      ),
    );
  }

  void _fertig() {
    final mm = _mm;
    if (mm != null) Navigator.pop(context, (wert: mm, text: _text.text.trim()));
  }
}

/// Seitenbezeichnung einer Wandseite: Raumname oder „außen“.
String seitenName(Planstand plan, Map<String, dynamic> wand, bool links) {
  final r = (links ? wand['rl'] : wand['rr']) as String?;
  return r == null ? (links ? 'Seite A (außen)' : 'Seite B (außen)') : plan.raumName(r);
}

/// Wandlänge einer Seite messen und senden.
Future<void> wandLaengeMessen(BuildContext context, MobilKontext k, Map<String, dynamic> wand, bool links) async {
  final seite = links ? 'l' : 'r';
  final plan = ((links ? wand['li'] : wand['re']) as num?) ?? (wand['l'] as num? ?? 0);
  final bisher = k.gemessen(wand, 'laenge', seite: seite, bezug: 'innen');
  final r = await massEingeben(context,
      titel: 'Wandlänge ${seitenName(k.plan, wand, links)}',
      plan: plan,
      bisher: bisher?.wert,
      hinweis: 'Von Ecke zu Ecke an der Wandoberfläche messen.',
      verkleidung: k.verkleidung((links ? wand['rl'] : wand['rr']) as String?));
  if (r == null) return;
  await k.massSenden(ziel: 'wand', objekt: wand, feld: 'laenge', wert: r.wert, plan: plan, seite: seite, bezug: 'innen', raum: (links ? wand['rl'] : wand['rr']) as String?, text: r.text);
}

Future<void> wandDickeMessen(BuildContext context, MobilKontext k, Map<String, dynamic> wand) async {
  final plan = (wand['d'] as num?) ?? 0;
  final r = await massEingeben(context, titel: 'Wanddicke', plan: plan, bisher: k.gemessen(wand, 'dicke')?.wert, hinweis: 'z. B. in der Türlaibung messen.');
  if (r == null) return;
  await k.massSenden(ziel: 'wand', objekt: wand, feld: 'dicke', wert: r.wert, plan: plan, text: r.text);
}

const oeffnungFelder = {'breite': 'Breite (Rohbau)', 'hoehe': 'Höhe (Rohbau)', 'bruestung': 'Brüstung über FFB', 'abstand': 'Abstand ab Wandanfang'};

Future<void> oeffnungMessen(BuildContext context, MobilKontext k, Map<String, dynamic> o, String feld, {String? raum}) async {
  final plan = (o[feld] as num?) ?? 0;
  final r = await massEingeben(context, titel: '${o['art'] == 'tuer' ? 'Tür' : o['art'] == 'fenster' ? 'Fenster' : 'Öffnung'}: ${oeffnungFelder[feld]}', plan: plan, bisher: k.gemessen(o, feld)?.wert);
  if (r == null) return;
  await k.massSenden(ziel: 'oeffnung', objekt: o, feld: feld, wert: r.wert, plan: plan, raum: raum, text: r.text);
}

Future<void> raumHoeheMessen(BuildContext context, MobilKontext k, Map<String, dynamic> raum, Map<String, dynamic> geschoss) async {
  final plan = raumHoehe(geschoss, raum['id'] as String?);
  final r = await massEingeben(context, titel: 'Lichte Raumhöhe ${raum['name']}', plan: plan, bisher: k.gemessen(raum, 'hoehe')?.wert, hinweis: 'Fertigfußboden bis Decke.');
  if (r == null) return;
  await k.massSenden(ziel: 'raum', objekt: raum, feld: 'hoehe', wert: r.wert, plan: plan, raum: raum['id'] as String?, text: r.text);
}

Future<void> bemassungMessen(BuildContext context, MobilKontext k, Map<String, dynamic> b) async {
  final plan = (b['l'] as num?) ?? 0;
  final r = await massEingeben(context, titel: 'Bemaßung', plan: plan, bisher: k.gemessen(b, 'laenge')?.wert);
  if (r == null) return;
  await k.massSenden(ziel: 'bemassung', objekt: b, feld: 'laenge', wert: r.wert, plan: plan, text: r.text);
}

/// Text und Farbe für ein Maß (gemessen grün, offen orange, grob grau).
({String text, Color farbe}) massAnzeige(MobilKontext k, Map<String, dynamic> ziel, String feld, num plan, {String? seite, String? bezug, int abzug = 0}) {
  final g = k.gemessen(ziel, feld, seite: seite, bezug: bezug);
  if (g == null) return (text: mmCm(plan - abzug), farbe: massGrob);
  return (text: mmCm(g.wert - abzug), farbe: g.uebernommen ? massGemessen : massOffen);
}

/// Eine Wandseite aus Sicht eines Raums: ganze Seite ([voll]) oder nur das
/// Stück, das an diesen Raum grenzt (lange Wand an mehreren Zimmern).
typedef RaumSeite = ({Map<String, dynamic> wand, bool links, double t1, double t2, bool voll});

List<RaumSeite> raumSeiten(Map<String, dynamic> geschoss, String raumId) {
  final aus = <RaumSeite>[];
  for (final w in Planstand.liste(geschoss['waende'])) {
    for (final links in [true, false]) {
      final s = AppWandSeite(w, links);
      for (final st in (w[links ? 'sl' : 'sr'] as List? ?? const [])) {
        final l = st as List;
        if (l[0] != raumId) continue;
        final t1 = (l[1] as num).toDouble(), t2 = (l[2] as num).toDouble();
        aus.add((wand: w, links: links, t1: t1, t2: t2, voll: (t1 - s.tA).abs() < 15 && (t2 - s.tB).abs() < 15));
      }
      // ältere Planstände ohne Stücke
      if (w['sl'] == null && (links ? w['rl'] : w['rr']) == raumId) aus.add((wand: w, links: links, t1: s.tA, t2: s.tB, voll: true));
    }
  }
  return aus;
}

String raumSeiteFeld(RaumSeite r, String raumId) => r.voll ? 'laenge' : 'laenge_$raumId';

({String text, Color farbe}) raumSeiteAnzeige(MobilKontext k, RaumSeite r, String raumId) =>
    massAnzeige(k, r.wand, raumSeiteFeld(r, raumId), r.t2 - r.t1, seite: r.links ? 'l' : 'r', bezug: r.voll ? 'innen' : null, abzug: k.fertigAbzug(raumId));

/// Gängige Wandverkleidungen (Dicke je Wandseite in mm).
const verkleidungVorlagen = <(String, int)>[
  ('keine (Rohbau)', 0),
  ('Putz', 15),
  ('GK direkt geklebt', 25),
  ('GK auf Unterkonstruktion', 62),
  ('Vorsatzschale 75 + GK', 90),
  ('Fliesen auf Putz', 25),
];

/// Wandverkleidung eines Raums wählen (geht als Aufmaß an den PC).
Future<void> verkleidungWaehlen(BuildContext context, MobilKontext k, Map<String, dynamic> raum) async {
  final aktuell = k.verkleidung(raum['id'] as String?);
  final dicke = TextEditingController(text: '$aktuell');
  final w = await showDialog<(String, int)>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Wandverkleidung ${raum['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (art, d) in verkleidungVorlagen)
          ListTile(dense: true, title: Text(art), trailing: Text('$d mm'), onTap: () => Navigator.pop(c, (art, d))),
        TextField(controller: dicke, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'eigene Dicke je Wandseite', suffixText: 'mm')),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(c, ('eigene', int.tryParse(dicke.text.trim()) ?? 0)), child: const Text('Eigene übernehmen'))],
    ),
  );
  if (w == null) return;
  await k.massSenden(ziel: 'verkleidung', objekt: raum, feld: 'verkleidung', wert: w.$2, plan: aktuell, raum: raum['id'] as String?, text: w.$1);
}

bool raumSeiteGemessen(MobilKontext k, RaumSeite r, String raumId) =>
    k.gemessen(r.wand, raumSeiteFeld(r, raumId), seite: r.links ? 'l' : 'r', bezug: r.voll ? 'innen' : null) != null;

Future<void> raumSeiteMessen(BuildContext context, MobilKontext k, RaumSeite r, String raumId) async {
  if (r.voll) return wandLaengeMessen(context, k, r.wand, r.links);
  final plan = r.t2 - r.t1;
  final seite = r.links ? 'l' : 'r';
  final e = await massEingeben(context,
      titel: 'Raumlänge an dieser Wand (${k.plan.raumName(raumId)})',
      plan: plan,
      bisher: k.gemessen(r.wand, 'laenge_$raumId', seite: seite)?.wert,
      hinweis: 'Die Wand läuft weiter in einen anderen Raum: hier von Wand zu Wand im Raum messen.',
      verkleidung: k.verkleidung(raumId));
  if (e == null) return;
  await k.massSenden(ziel: 'raumseite', objekt: r.wand, feld: 'laenge_$raumId', wert: e.wert, plan: plan, seite: seite, raum: raumId, text: e.text, extra: {'von': r.t1.round(), 'bis': r.t2.round()});
}
