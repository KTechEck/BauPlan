import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../kontext.dart';
import '../planstand.dart';
import 'aufmass.dart';
import 'sparren.dart';
import 'wandansicht.dart';

/// Plan auf der Baustelle: Grundriss mit allen Maßen (Wandseiten, Bemaßungen,
/// Räume), Ebenen ein/aus, Wand antippen → Maße ansehen und nachmessen,
/// Wandansicht mit Bohrhilfe; Bohr-Check auch direkt im Grundriss.
class PlanSeite extends StatefulWidget {
  const PlanSeite({super.key, required this.k});
  final MobilKontext k;

  @override
  State<PlanSeite> createState() => _PlanSeiteState();
}

enum PlanModus { masse, bohren }

class _PlanSeiteState extends State<PlanSeite> {
  final Set<String> _aus = {};
  PlanModus _modus = PlanModus.masse;
  bool _masse = true, _objekte = true;

  MobilKontext get k => widget.k;

  @override
  Widget build(BuildContext context) {
    final g = k.geschoss;
    if (g == null) return const Center(child: Text('Kein Geschoss im Planstand.'));
    final gewerke = k.plan.gewerke;
    return Column(children: [
      SizedBox(
        height: 50,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), children: [
          for (final x in k.plan.geschosse)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${x['kuerzel']}'),
                selected: x['id'] == g['id'],
                onSelected: (_) => setState(() {
                  k.einstellungen.geschoss = x['id'] as String;
                  k.einstellungen.speichern();
                }),
              ),
            ),
          const VerticalDivider(),
          FilterChip(label: const Text('Maße'), selected: _masse, onSelected: (v) => setState(() => _masse = v)),
          const SizedBox(width: 6),
          FilterChip(label: const Text('Objekte'), selected: _objekte, onSelected: (v) => setState(() => _objekte = v)),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.roofing, size: 16),
            label: Text('Sparren (${appSparrenfelder(k, g).length})'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SparrenSeite(k: k, geschoss: g))).then((_) => setState(() {})),
          ),
          const SizedBox(width: 6),
          for (final e in gewerke.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                avatar: CircleAvatar(backgroundColor: e.value.farbe, radius: 6),
                label: Text(e.value.name),
                selected: !_aus.contains(e.key),
                onSelected: (v) => setState(() => v ? _aus.remove(e.key) : _aus.add(e.key)),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SegmentedButton<PlanModus>(
          segments: const [
            ButtonSegment(value: PlanModus.masse, icon: Icon(Icons.straighten), label: Text('Maße / Wand')),
            ButtonSegment(value: PlanModus.bohren, icon: Icon(Icons.hardware_outlined), label: Text('Bohr-Check')),
          ],
          selected: {_modus},
          onSelectionChanged: (v) => setState(() => _modus = v.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Text(
          _modus == PlanModus.masse
              ? 'Wand oder Raum antippen: Maße ansehen, nachmessen, Wandansicht. Grau = grob gezeichnet, orange = gemessen, grün = am PC übernommen.'
              : 'Stelle antippen: Leitungen und Geräte im Umkreis von 30 cm. Genauer mit Höhe: Wand antippen › Wandansicht.',
          style: const TextStyle(fontSize: 11, color: BsFarben.textLeise),
        ),
      ),
      Expanded(
        child: GrundrissAnsicht(
          plan: k.plan,
          geschoss: g,
          k: k,
          aus: _aus,
          masse: _masse,
          objekte: _objekte,
          bohrCheck: _modus == PlanModus.bohren,
          wandGetippt: _modus == PlanModus.masse ? (w) => wandBlatt(context, k, g, w).then((_) => setState(() {})) : null,
          raumGetippt: _modus == PlanModus.masse ? (r) => raumBlatt(context, k, g, r).then((_) => setState(() {})) : null,
          bemassungGetippt: _modus == PlanModus.masse ? (b) => bemassungMessen(context, k, b).then((_) => setState(() {})) : null,
        ),
      ),
    ]);
  }
}

/// Wand-Blatt: Maße beider Seiten, Dicke, Öffnungen, Brandschutz; nachmessen; Wandansicht.
Future<void> wandBlatt(BuildContext context, MobilKontext k, Map<String, dynamic> g, Map<String, dynamic> w) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, setState) {
      final oeffnungen = [for (final o in Planstand.liste(g['oeffnungen'])) if (o['wand'] == w['id']) o];
      Widget massZeile(String titel, Map<String, dynamic> ziel, String feld, num plan, Future<void> Function() messen, {String? seite, String? bezug}) {
        final m = massAnzeige(k, ziel, feld, plan, seite: seite, bezug: bezug);
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(titel),
          subtitle: Text(m.farbe == massGrob ? 'Plan ${mmCm(plan)} – noch nicht gemessen' : 'Plan ${mmCm(plan)}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(m.text, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: m.farbe)),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () async {
                await messen();
                setState(() {});
              },
              icon: const Icon(Icons.straighten, size: 18),
              label: const Text('Messen'),
            ),
          ]),
        );
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Text('Wand · ${seitenName(k.plan, w, true)} | ${seitenName(k.plan, w, false)}', style: Theme.of(c).textTheme.titleMedium),
          Text([
            'Achse ${mmCm(w['l'] as num? ?? 0)}',
            'Dicke ${mmCm(w['d'] as num? ?? 0)}',
            if (w['zustand'] != null) '${w['zustand']}',
            if (w['brandschutz'] != null) 'Brandschutz ${w['brandschutz']}',
          ].join(' · '), style: const TextStyle(color: BsFarben.textLeise)),
          const SizedBox(height: 8),
          Row(children: [
            for (final links in [true, false])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: links ? 6 : 0),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => WandansichtSeite(k: k, geschoss: g, wand: w, links: links))),
                    icon: const Icon(Icons.view_agenda_outlined, size: 18),
                    label: Text('Ansicht ${seitenName(k.plan, w, links)}', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final links in [true, false]) ...[
              OutlinedButton.icon(
                onPressed: () => sparrenfeldAnlegen(c, k, g, w, links, geschossweit: true),
                icon: const Icon(Icons.roofing, size: 16),
                label: Text('Sparren ganzes Geschoss → ${seitenName(k.plan, w, links)}', overflow: TextOverflow.ellipsis),
              ),
              if ((links ? w['rl'] : w['rr']) != null)
                OutlinedButton.icon(
                  onPressed: () => sparrenfeldAnlegen(c, k, g, w, links, geschossweit: false),
                  icon: const Icon(Icons.roofing, size: 16),
                  label: Text('Sparren nur ${seitenName(k.plan, w, links)}', overflow: TextOverflow.ellipsis),
                ),
            ],
          ]),
          const Divider(),
          for (final links in [true, false]) ...() {
            // Grenzt die Seite an mehrere Räume (oder nur teilweise an einen), gilt je Raum seine lichte Strecke
            final stuecke = [
              for (final st in (w[links ? 'sl' : 'sr'] as List? ?? const []))
                for (final r in raumSeiten(g, '${(st as List)[0]}'))
                  if (r.wand['id'] == w['id'] && r.links == links) ('${st[0]}', r)
            ];
            if (stuecke.isEmpty || (stuecke.length == 1 && stuecke.first.$2.voll)) {
              return [
                massZeile('Länge ${seitenName(k.plan, w, links)}', w, 'laenge', ((links ? w['li'] : w['re']) as num?) ?? (w['l'] as num? ?? 0),
                    () => wandLaengeMessen(c, k, w, links),
                    seite: links ? 'l' : 'r', bezug: 'innen'),
              ];
            }
            return [
              for (final (raumId, r) in stuecke)
                Builder(builder: (_) {
                  final m = raumSeiteAnzeige(k, r, raumId);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Lichte Länge im Raum ${k.plan.raumName(raumId)}'),
                    subtitle: Text('Plan ${mmCm(r.t2 - r.t1)} · von Wand zu Wand in diesem Raum'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(m.text, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: m.farbe)),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await raumSeiteMessen(c, k, r, raumId);
                          setState(() {});
                        },
                        icon: const Icon(Icons.straighten, size: 18),
                        label: const Text('Messen'),
                      ),
                    ]),
                  );
                }),
            ];
          }(),
          massZeile('Wanddicke', w, 'dicke', w['d'] as num? ?? 0, () => wandDickeMessen(c, k, w)),
          if (oeffnungen.isNotEmpty) ...[
            const Divider(),
            for (final o in oeffnungen) ...[
              Text(switch (o['art']) { 'tuer' => 'Tür', 'fenster' => 'Fenster', 'balkontuer' => 'Balkontür', _ => 'Durchbruch' },
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final f in oeffnungFelder.keys)
                if (o[f] != null && !(f == 'bruestung' && o['art'] != 'fenster'))
                  massZeile(oeffnungFelder[f]!, o, f, o[f] as num, () => oeffnungMessen(c, k, o, f, raum: w['rl'] as String? ?? w['rr'] as String?)),
            ],
          ],
          if (w['gesperrt'] == true) const Text('Am PC gesperrt – Maße werden dort trotzdem angezeigt und können geprüft werden.', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        ]),
      );
    }),
  );
}

/// Raum-Blatt: Fläche, Höhe (messen), Wände reihum messen, Objekte.
Future<void> raumBlatt(BuildContext context, MobilKontext k, Map<String, dynamic> g, Map<String, dynamic> r) {
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RaumAufmassSeite(k: k, geschoss: g, raum: r)));
}

/// Aufmaß eines Raums: alle Wandseiten, Öffnungen und die Raumhöhe in einer
/// Liste – reihum messen, der Plan oben zeigt, welche Wand gerade dran ist.
class RaumAufmassSeite extends StatefulWidget {
  const RaumAufmassSeite({super.key, required this.k, required this.geschoss, required this.raum});
  final MobilKontext k;
  final Map<String, dynamic> geschoss;
  final Map<String, dynamic> raum;

  @override
  State<RaumAufmassSeite> createState() => _RaumAufmassSeiteState();
}

class _RaumAufmassSeiteState extends State<RaumAufmassSeite> {
  int? _auswahl; // gewählte Raumseite (Index)

  /// Diagonalen über je eine Ecke (Ecke i → i+2); beim Viereck die zwei Raumdiagonalen.
  List<(int, int)> _diagonalen(int n) => n == 4 ? const [(0, 2), (1, 3)] : [for (var i = 0; i < n; i++) (i, (i + 2) % n)];

  MobilKontext get k => widget.k;

  @override
  Widget build(BuildContext context) {
    final g = widget.geschoss, r = widget.raum;
    final id = r['id'];
    final seiten = raumSeiten(g, '$id');
    final wandIds = {for (final r in seiten) r.wand['id']};
    final oeffnungen = [for (final o in Planstand.liste(g['oeffnungen'])) if (wandIds.contains(o['wand'])) o];
    final gemessen = seiten.where((r) => raumSeiteGemessen(k, r, '$id')).length;
    final hoehe = raumHoehe(g, id as String?);
    final hm = massAnzeige(k, r, 'hoehe', hoehe);
    return Scaffold(
      appBar: AppBar(title: Text('Aufmaß ${r['name']}')),
      body: Column(children: [
        SizedBox(
          height: 220,
          child: GrundrissAnsicht(
            plan: k.plan,
            geschoss: g,
            k: k,
            nurRaum: id,
            objekte: false,
            strecke: _auswahl != null && _auswahl! < seiten.length ? seiten[_auswahl!] : null,
            wandGetippt: (w) => setState(() {
              final i = seiten.indexWhere((r) => r.wand['id'] == w['id']);
              if (i >= 0) _auswahl = i;
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: LinearProgressIndicator(value: seiten.isEmpty ? 0 : gemessen / seiten.length, color: massGemessen, backgroundColor: const Color(0xFFE9ECEF)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('$gemessen von ${seiten.length} Wänden gemessen · Fläche ${((r['flaeche'] as num? ?? 0) / 1e6).toStringAsFixed(2).replaceAll('.', ',')} m²',
              style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(8), children: [
            ListTile(
              leading: const Icon(Icons.height),
              title: const Text('Lichte Raumhöhe'),
              subtitle: Text('Plan ${mmCm(hoehe)}'),
              trailing: Text(hm.text, style: TextStyle(fontWeight: FontWeight.w700, color: hm.farbe)),
              onTap: () async {
                await raumHoeheMessen(context, k, r, g);
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Wandverkleidung'),
              subtitle: Text(k.verkleidung('$id') == 0 ? 'keine – Maße sind Rohbaumaße' : '${k.verkleidung('$id')} mm je Wandseite · Anzeige ${k.einstellungen.massart == 'fertig' ? 'fertig' : 'Rohbau'}'),
              trailing: Switch(
                value: k.einstellungen.massart == 'fertig',
                onChanged: (v) => setState(() {
                  k.einstellungen.massart = v ? 'fertig' : 'roh';
                  k.einstellungen.speichern();
                }),
              ),
              onTap: () async {
                await verkleidungWaehlen(context, k, r);
                setState(() {});
              },
            ),
            const Divider(),
            for (var i = 0; i < seiten.length; i++)
              Builder(builder: (context) {
                final r = seiten[i];
                final w = r.wand;
                final m = raumSeiteAnzeige(k, r, '$id');
                return ListTile(
                  selected: _auswahl == i,
                  leading: CircleAvatar(radius: 14, backgroundColor: m.farbe.withValues(alpha: 0.15), child: Text('${i + 1}', style: TextStyle(color: m.farbe, fontSize: 12))),
                  title: Text('Wand ${i + 1}${r.voll ? '' : ' (Teilstück)'}${w['brandschutz'] == null ? '' : ' · ${w['brandschutz']}'}'),
                  subtitle: Text('Plan ${mmCm(r.t2 - r.t1)} · Dicke ${mmCm(w['d'] as num? ?? 0)}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(m.text, style: TextStyle(fontWeight: FontWeight.w700, color: m.farbe)),
                    IconButton(
                      tooltip: 'Wandansicht',
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WandansichtSeite(k: k, geschoss: g, wand: w, links: r.links))),
                      icon: const Icon(Icons.view_agenda_outlined),
                    ),
                  ]),
                  onTap: () async {
                    setState(() => _auswahl = i);
                    await raumSeiteMessen(context, k, r, '$id');
                    if (!mounted) return;
                    // nächste ungemessene Wand vormerken
                    final naechste = seiten.skip(i + 1).where((s) => !raumSeiteGemessen(k, s, '$id')).firstOrNull;
                    setState(() => _auswahl = naechste == null ? _auswahl : seiten.indexOf(naechste));
                  },
                );
              }),
            if (punkte(r['umriss']).length >= 4) ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('Diagonalen (bestimmen die Winkel, Ecken A, B, C … im Plan oben)', style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              ),
              for (final (i, j) in _diagonalen(punkte(r['umriss']).length))
                Builder(builder: (context) {
                  final u = punkte(r['umriss']);
                  final plan = (u[i] - u[j]).distance;
                  final feld = 'diag_${i}_$j';
                  final m = massAnzeige(k, r, feld, plan);
                  return ListTile(
                    leading: const Icon(Icons.open_in_full),
                    title: Text('Diagonale ${String.fromCharCode(65 + i)} → ${String.fromCharCode(65 + j)}'),
                    subtitle: Text('Plan ${mmCm(plan)}'),
                    trailing: Text(m.text, style: TextStyle(fontWeight: FontWeight.w700, color: m.farbe)),
                    onTap: () async {
                      final e = await massEingeben(context,
                          titel: 'Diagonale ${String.fromCharCode(65 + i)} → ${String.fromCharCode(65 + j)}',
                          plan: plan,
                          bisher: k.gemessen(r, feld)?.wert,
                          hinweis: 'Von Ecke zu Ecke quer durch den Raum (Laser). Daraus rechnet der PC den Winkel der Ecke dazwischen.');
                      if (e == null) return;
                      await k.massSenden(ziel: 'diagonale', objekt: r, feld: feld, wert: e.wert, plan: plan, raum: '$id', text: e.text, extra: {'ecken': [i, j]});
                      if (mounted) setState(() {});
                    },
                  );
                }),
            ],
            if (oeffnungen.isNotEmpty) ...[
              const Divider(),
              for (final o in oeffnungen)
                ListTile(
                  leading: Icon(o['art'] == 'fenster' ? Icons.window_outlined : Icons.door_front_door_outlined),
                  title: Text('${switch (o['art']) { 'tuer' => 'Tür', 'fenster' => 'Fenster', 'balkontuer' => 'Balkontür', _ => 'Durchbruch' }} '
                      '${massAnzeige(k, o, 'breite', o['breite'] as num).text} × ${massAnzeige(k, o, 'hoehe', o['hoehe'] as num).text}'),
                  subtitle: o['art'] == 'fenster' ? Text('Brüstung ${massAnzeige(k, o, 'bruestung', o['bruestung'] as num).text}') : null,
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.straighten),
                    onSelected: (f) async {
                      await oeffnungMessen(context, k, o, f, raum: id);
                      setState(() {});
                    },
                    itemBuilder: (_) => [for (final e in oeffnungFelder.entries) PopupMenuItem(value: e.key, child: Text('${e.value} messen'))],
                  ),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Grundriss zum Ansehen (Zoomen/Verschieben) mit Maßen; Antippen wählt
/// Wand, Raum oder Bemaßung, prüft Bohrstellen oder liefert eine Position.
class GrundrissAnsicht extends StatefulWidget {
  const GrundrissAnsicht({
    super.key,
    required this.plan,
    required this.geschoss,
    this.k,
    this.aus = const {},
    this.waehlen,
    this.bohrCheck = false,
    this.masse = true,
    this.objekte = true,
    this.wandGetippt,
    this.raumGetippt,
    this.bemassungGetippt,
    this.nurRaum,
    this.hervor,
    this.strecke,
  });

  /// Hervorgehobene Messstrecke (Raumseite): nur die lichte Strecke, nicht die ganze Wand.
  final RaumSeite? strecke;
  final Planstand plan;
  final Map<String, dynamic> geschoss;
  final MobilKontext? k;
  final Set<String> aus;
  final ValueChanged<Offset>? waehlen;
  final bool bohrCheck, masse, objekte;
  final ValueChanged<Map<String, dynamic>>? wandGetippt, raumGetippt, bemassungGetippt;
  final Object? nurRaum;
  final String? hervor;

  @override
  State<GrundrissAnsicht> createState() => _GrundrissAnsichtState();
}

class _GrundrissAnsichtState extends State<GrundrissAnsicht> {
  final _tc = TransformationController();
  Offset? _markiert;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final g = widget.geschoss;
      final raeume = Planstand.liste(g['raeume']);
      final nur = widget.nurRaum == null ? null : raeume.where((r) => r['id'] == widget.nurRaum).firstOrNull;
      final alle = nur != null
          ? punkte(nur['umriss'])
          : [
              for (final w in Planstand.liste(g['waende'])) ...[punkt(w['a']), punkt(w['b'])],
              for (final r in raeume) ...punkte(r['umriss']),
            ];
      if (alle.isEmpty) return const Center(child: Text('Keine Wände in diesem Geschoss.'));
      var x0 = alle.first.dx, y0 = alle.first.dy, x1 = x0, y1 = y0;
      for (final q in alle) {
        x0 = math.min(x0, q.dx);
        y0 = math.min(y0, q.dy);
        x1 = math.max(x1, q.dx);
        y1 = math.max(y1, q.dy);
      }
      const rand = 44.0;
      final m = math.min((c.maxWidth - 2 * rand) / math.max(1, x1 - x0), (c.maxHeight - 2 * rand) / math.max(1, y1 - y0));
      final versatz = Offset((c.maxWidth - (x1 - x0) * m) / 2, (c.maxHeight - (y1 - y0) * m) / 2);
      Offset zuBild(Offset w) => versatz + Offset((w.dx - x0) * m, (w.dy - y0) * m);
      Offset zuWelt(Offset b) => Offset((b.dx - versatz.dx) / m + x0, (b.dy - versatz.dy) / m + y0);
      return GestureDetector(
        onTapUp: (d) {
          final bild = _tc.toScene(d.localPosition);
          final welt = zuWelt(bild);
          if (widget.waehlen != null) {
            widget.waehlen!(welt);
            return;
          }
          if (widget.bohrCheck) {
            setState(() => _markiert = welt);
            _bohrBlatt(context, g, welt);
            return;
          }
          // Bemaßungstext, dann Wand, dann Raum
          final skala = _tc.value.getMaxScaleOnAxis();
          if (widget.bemassungGetippt != null && widget.masse) {
            for (final b in Planstand.liste(g['bemassungen'])) {
              final mitte = zuBild(_bemassungMitte(b));
              if ((mitte - bild).distance < 22 / skala) return widget.bemassungGetippt!(b);
            }
          }
          if (widget.wandGetippt != null) {
            Map<String, dynamic>? best;
            var bd = double.infinity;
            for (final w in Planstand.liste(g['waende'])) {
              final dd = abstandStrecke(welt, punkt(w['a']), punkt(w['b'])) - ((w['d'] as num?) ?? 175) / 2;
              if (dd < bd) {
                bd = dd;
                best = w;
              }
            }
            if (best != null && bd * m * skala < 18) return widget.wandGetippt!(best);
          }
          if (widget.raumGetippt != null) {
            for (final r in raeume) {
              final u = punkte(r['umriss']);
              if (u.length >= 3 && imPolygon(welt, u)) return widget.raumGetippt!(r);
            }
          }
        },
        child: InteractiveViewer(
          transformationController: _tc,
          minScale: 0.5,
          maxScale: 16,
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _PlanPainter(
              plan: widget.plan,
              k: widget.k,
              g: g,
              aus: widget.aus,
              zuBild: zuBild,
              m: m,
              markiert: _markiert,
              masse: widget.masse,
              objekte: widget.objekte,
              nurRaum: widget.nurRaum,
              hervor: widget.hervor,
              strecke: widget.strecke,
              tc: _tc,
            ),
          ),
        ),
      );
    });
  }

  void _bohrBlatt(BuildContext context, Map<String, dynamic> g, Offset welt) {
    final treffer = bohrCheck(g, welt);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(padding: const EdgeInsets.all(16), shrinkWrap: true, children: [
        Text(treffer.isEmpty ? 'Bohr-Check: im Umkreis von 30 cm nichts geplant ✓' : 'Bohr-Check: ${treffer.length} Leitung(en)/Gerät(e) in 30 cm',
            style: TextStyle(fontWeight: FontWeight.w600, color: treffer.isEmpty ? massGemessen : const Color(0xFFB91C1C))),
        const SizedBox(height: 8),
        for (final (o, d) in treffer)
          ListTile(
            dense: true,
            leading: Icon(d < 100 ? Icons.dangerous_outlined : Icons.warning_amber, color: d < 100 ? const Color(0xFFB91C1C) : const Color(0xFFB45309)),
            title: Text('${o['kennung']} · ${o['name']}'),
            subtitle: Text('${mmCm(d)} entfernt${o['lage'] == null ? '' : ' · ${o['lage']}'}${o['h'] == null ? '' : ' · Höhe ${mmCm(o['h'] as num)} über FFB'}'),
          ),
        const Text('Im Grundriss fehlt die Höhe: für die Wand die Wandansicht öffnen (Plan › Wand › Ansicht). Ohne Gewähr – vor dem Bohren mit Leitungssucher prüfen.',
            style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      ]),
    );
  }
}

Offset _bemassungMitte(Map<String, dynamic> b) {
  final a = punkt(b['a']), e = punkt(b['b']);
  final d = e - a;
  final l = math.max(1.0, d.distance);
  final n = Offset(-d.dy / l, d.dx / l) * ((b['abstand'] as num?)?.toDouble() ?? 500);
  return (a + e) / 2 + n;
}

class _PlanPainter extends CustomPainter {
  _PlanPainter({
    required this.plan,
    required this.g,
    required this.aus,
    required this.zuBild,
    required this.m,
    this.k,
    this.markiert,
    this.masse = true,
    this.objekte = true,
    this.nurRaum,
    this.hervor,
    this.strecke,
    this.tc,
  }) : super(repaint: tc);
  final RaumSeite? strecke;
  final TransformationController? tc;

  /// Aktueller Zoom: Schrift bleibt auf dem Bildschirm gleich groß, Maße ohne Platz werden ausgeblendet.
  double get zoom => tc?.value.getMaxScaleOnAxis() ?? 1;
  double get dichte => k?.einstellungen.massDichte ?? 1;
  double get schrift => k?.einstellungen.massSchrift ?? 1;
  final Planstand plan;
  final MobilKontext? k;
  final Map<String, dynamic> g;
  final Set<String> aus;
  final Offset Function(Offset) zuBild;
  final double m;
  final Offset? markiert;
  final bool masse, objekte;
  final Object? nurRaum;
  final String? hervor;

  void _text(Canvas canvas, String t, Offset p, {double groesse = 10, Color farbe = BsFarben.textLeise, double winkel = 0, bool fett = false, Color? grund}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontFamily: 'Roboto', fontSize: groesse * schrift / zoom, color: farbe, fontWeight: fett ? FontWeight.w700 : FontWeight.w400, backgroundColor: grund)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(p.dx, p.dy);
    var w = winkel;
    if (w > math.pi / 2) w -= math.pi;
    if (w < -math.pi / 2) w += math.pi;
    canvas.rotate(w);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final r in Planstand.liste(g['raeume'])) {
      final u = punkte(r['umriss']);
      if (u.length < 3) continue;
      final hier = nurRaum == null || r['id'] == nurRaum;
      canvas.drawPath(Path()..addPolygon([for (final q in u) zuBild(q)], true), Paint()..color = hier ? const Color(0xFFF1F3F5) : const Color(0xFFFAFAFA));
      if (nurRaum != null && r['id'] == nurRaum) {
        for (var i = 0; i < u.length; i++) {
          _text(canvas, String.fromCharCode(65 + i), zuBild(u[i]), groesse: 11, farbe: BsFarben.akzent, fett: true, grund: Colors.white);
        }
      }
      var cx = 0.0, cy = 0.0;
      for (final q in u) {
        cx += q.dx;
        cy += q.dy;
      }
      final mitte = zuBild(Offset(cx / u.length, cy / u.length));
      _text(canvas, '${r['name']}', mitte - const Offset(0, 7), groesse: 11, farbe: const Color(0xFF343A40), fett: true);
      final breite = (u.map((q) => q.dx).reduce(math.max) - u.map((q) => q.dx).reduce(math.min)) * m * zoom;
      if (masse && r['flaeche'] != null && breite > 80 * dichte * schrift) {
        final kk = k;
        final hm = kk == null ? null : massAnzeige(kk, r, 'hoehe', raumHoehe(g, r['id'] as String?));
        _text(canvas, '${((r['flaeche'] as num) / 1e6).toStringAsFixed(2).replaceAll('.', ',')} m²${hm == null ? '' : ' · h ${hm.text}'}', mitte + const Offset(0, 7),
            groesse: 9, farbe: hm?.farbe ?? BsFarben.textLeise);
      }
    }
    final oeffnungen = Planstand.liste(g['oeffnungen']);
    for (final w in Planstand.liste(g['waende'])) {
      final a = punkt(w['a']), b = punkt(w['b']);
      final hier = nurRaum == null || w['rl'] == nurRaum || w['rr'] == nurRaum;
      canvas.drawLine(zuBild(a), zuBild(b), Paint()
        ..color = w['id'] == hervor ? BsFarben.akzent : (hier ? BsFarben.wandBestand : const Color(0xFFCED4DA))
        ..strokeWidth = math.max(1.5, ((w['d'] as num?)?.toDouble() ?? 175) * m)
        ..strokeCap = StrokeCap.square);
      if (w['brandschutz'] != null) {
        canvas.drawLine(zuBild(a), zuBild(b), Paint()
          ..color = const Color(0xFFC92A2A)
          ..strokeWidth = 1.5);
      }
      // Öffnungen als Lücke
      final l = (b - a).distance;
      if (l < 1) continue;
      final u = (b - a) / l;
      for (final o in oeffnungen.where((o) => o['wand'] == w['id'])) {
        final t1 = (o['abstand'] as num).toDouble(), t2 = t1 + (o['breite'] as num).toDouble();
        canvas.drawLine(zuBild(a + u * t1), zuBild(a + u * t2), Paint()
          ..color = o['art'] == 'fenster' ? const Color(0xFFA5D8FF) : Colors.white
          ..strokeWidth = math.max(1.5, ((w['d'] as num?)?.toDouble() ?? 175) * m - 1));
      }
      if (!masse || !hier) continue;
      // Maße beider Wandseiten
      final nl = Offset(u.dy, -u.dx);
      final winkel = math.atan2(u.dy, u.dx);
      final d = ((w['d'] as num?)?.toDouble() ?? 175);
      for (final links in [true, false]) {
        final raum = (links ? w['rl'] : w['rr']) as String?;
        if (nurRaum != null && raum != nurRaum) continue;
        if (raum == null && nurRaum == null && (links ? w['rr'] : w['rl']) != null) {
          // Außenseite: nur zeigen, wenn genug Platz
          if (l * m * zoom < 60 * dichte * schrift) continue;
        }
        // Seite an mehreren Räumen: je Raum seine lichte Strecke beschriften
        final st = [for (final x in (w[links ? 'sl' : 'sr'] as List? ?? const [])) x as List];
        final sw = AppWandSeite(w, links);
        if (st.length > 1 || st.any((x) => ((x[1] as num) - sw.tA).abs() > 5 || ((x[2] as num) - sw.tB).abs() > 5)) {
          final kk = k;
          for (final x in st) {
            if (nurRaum != null && x[0] != nurRaum) continue;
            final t1 = (x[1] as num).toDouble(), t2 = (x[2] as num).toDouble();
            if ((t2 - t1) * m * zoom < 34 * dichte * schrift) continue;
            final rs = (wand: w, links: links, t1: t1, t2: t2, voll: false);
            final anz = kk == null ? (text: mmCm(t2 - t1), farbe: massGrob) : raumSeiteAnzeige(kk, rs, '${x[0]}');
            final p = zuBild(sw.a + sw.u * ((t1 + t2) / 2) + nl * ((links ? 1 : -1) * (d / 2 + 9 * schrift / (m * zoom))));
            _text(canvas, anz.text, p, groesse: 9, farbe: anz.farbe, winkel: winkel, fett: anz.farbe != massGrob, grund: const Color(0xCCFFFFFF));
          }
          continue;
        }
        final plan = ((links ? w['li'] : w['re']) as num?) ?? l;
        if (plan * m * zoom < 34 * dichte * schrift) continue;
        final kk = k;
        final anz = kk == null
            ? (text: mmCm(plan), farbe: massGrob)
            : massAnzeige(kk, w, 'laenge', plan, seite: links ? 'l' : 'r', bezug: 'innen', abzug: kk.fertigAbzug(raum));
        final s = links ? 1.0 : -1.0;
        final p = zuBild((a + b) / 2 + nl * (s * (d / 2 + 9 * schrift / (m * zoom))));
        _text(canvas, anz.text, p, groesse: 9, farbe: anz.farbe, winkel: winkel, fett: anz.farbe != massGrob, grund: const Color(0xCCFFFFFF));
      }
    }
    // eigene Bemaßungen
    if (masse) {
      for (final bm in Planstand.liste(g['bemassungen'])) {
        final a = punkt(bm['a']), e = punkt(bm['b']);
        final d = e - a;
        final l = math.max(1.0, d.distance);
        if (l * m * zoom < 40 * dichte * schrift) continue;
        final n = Offset(-d.dy / l, d.dx / l) * ((bm['abstand'] as num?)?.toDouble() ?? 500);
        final stift = Paint()
          ..color = const Color(0xFF1C7ED6)
          ..strokeWidth = 1;
        canvas.drawLine(zuBild(a + n), zuBild(e + n), stift);
        canvas.drawLine(zuBild(a), zuBild(a + n), stift..color = const Color(0x661C7ED6));
        canvas.drawLine(zuBild(e), zuBild(e + n), stift);
        final kk = k;
        final anz = kk == null ? (text: mmCm(bm['l'] as num), farbe: const Color(0xFF1C7ED6)) : massAnzeige(kk, bm, 'laenge', bm['l'] as num);
        _text(canvas, anz.text, zuBild((a + e) / 2 + n), groesse: 9, farbe: anz.farbe == massGrob ? const Color(0xFF1C7ED6) : anz.farbe, winkel: math.atan2(d.dy, d.dx), grund: Colors.white);
      }
    }
    final kk = k;
    if (kk != null) {
      for (final f in appSparrenfelder(kk, g)) {
        final sf = appSparrenfeld(kk, f);
        final p = Paint()
          ..color = const Color(0xAA8D6E63)
          ..strokeWidth = math.max(1.0, sf.breite * m);
        for (final (a, e) in sf.strecken) {
          canvas.drawLine(zuBild(Offset(a.$1, a.$2)), zuBild(Offset(e.$1, e.$2)), p);
        }
      }
    }
    if (objekte) {
      final gewerke = plan.gewerke;
      for (final o in Planstand.liste(g['objekte'])) {
        if (aus.contains(o['gewerk'])) continue;
        final farbe = gewerke[o['gewerk']]?.farbe ?? const Color(0xFF888888);
        final pts = [for (final q in punkte(o['punkte'])) zuBild(q)];
        if (pts.isEmpty) continue;
        switch (o['geometrie']) {
          case 'linie':
            canvas.drawPath(Path()..addPolygon(pts, false), Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = farbe);
          case 'flaeche':
            canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = farbe.withValues(alpha: 0.12));
          default:
            canvas.drawCircle(pts.first, 6, Paint()..color = farbe);
            _text(canvas, '${o['typ']}', pts.first, groesse: 7, farbe: Colors.white, fett: true);
        }
      }
    }
    final st = strecke;
    if (st != null) {
      final s = AppWandSeite(st.wand, st.links);
      final versatz = s.dicke / 2 + 10 / (m * zoom);
      final p1 = zuBild(s.a + s.u * st.t1 + s.nl * (s.s * versatz)), p2 = zuBild(s.a + s.u * st.t2 + s.nl * (s.s * versatz));
      final stift = Paint()
        ..color = BsFarben.akzent
        ..strokeWidth = 3 / zoom
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(p1, p2, stift);
      final q = Offset(-(p2 - p1).dy, (p2 - p1).dx) / math.max(0.001, (p2 - p1).distance) * (7 / zoom);
      canvas.drawLine(p1 - q, p1 + q, stift);
      canvas.drawLine(p2 - q, p2 + q, stift);
    }
    final mk = markiert;
    if (mk != null) {
      final c = zuBild(mk);
      canvas.drawCircle(c, 300 * m, Paint()..color = const Color(0x22E03131));
      canvas.drawCircle(c, 4, Paint()..color = const Color(0xFFE03131));
    }
  }

  @override
  bool shouldRepaint(_PlanPainter old) => true;
}
