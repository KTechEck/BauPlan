import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/symbole.dart';
import '../../app/theme.dart';
import '../../core/fbh.dart';
import '../../core/raumerkennung.dart';
import '../../core/verteiler.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../installation/heizkreise_dialog.dart';
import '../widgets.dart';

/// Editor für einen Heizkreisverteiler: Ausstattung, Montage, Zuleitung und
/// Belegung der Abgänge mit Heizkreisen.
class VerteilerEditor extends StatefulWidget {
  const VerteilerEditor({super.key, required this.state, required this.objektId});
  final AppState state;
  final String objektId;

  @override
  State<VerteilerEditor> createState() => _VerteilerEditorState();
}

class _VerteilerEditorState extends State<VerteilerEditor> {
  AppState get _s => widget.state;
  final List<VoidCallback> _rueckgaengig = [];

  /// Wegelänge (rechtwinklig) vom Verteiler zur nächsten Ecke eines Heizkreises.
  static int wegZu(Objekt verteiler, Objekt kreis) {
    final p = verteiler.punkte.first;
    var best = double.infinity;
    for (final q in kreis.punkte) {
      best = math.min(best, (p.x - q.x).abs() + (p.y - q.y).abs());
    }
    return best.isFinite ? best.round() : 0;
  }

  void _speichern(Objekt v, VerteilerDaten d) {
    final store = _s.store!;
    final alt = store.objektAendern(v.id, {'eigenschaften': jsonEncode({...v.eigenschaften, ...d.toJson()})});
    _rueckgaengig.add(() => store.objektAendern(v.id, alt));
    _s.geaendert();
  }

  /// Ordnet einen Heizkreis einem Abgang zu und setzt seine Zuleitung.
  void _zuordnen(Objekt v, VerteilerDaten d, int abgang, Objekt? kreis, List<Objekt> alleKreise) {
    final store = _s.store!;
    // ein Kreis hängt nur an einem Abgang
    for (var i = 0; i < d.kreise.length; i++) {
      if (kreis != null && d.kreise[i] == kreis.id) d.kreise[i] = null;
    }
    d.kreise[abgang] = kreis?.id;
    _speichern(v, d);
    if (kreis != null) {
      final alt = store.objektAendern(kreis.id, {
        'eigenschaften': jsonEncode({...kreis.eigenschaften, 'zuleitung_mm': wegZu(v, kreis), 'verteiler': v.id}),
      });
      _rueckgaengig.add(() => store.objektAendern(kreis.id, alt));
      _s.geaendert();
    }
  }

  /// Heizkreise nach Räumen auswählen: alle Kreise der gewählten Räume auf
  /// freie Abgänge legen (nächstgelegene zuerst), bei Bedarf Abgänge ergänzen.
  /// Räume ohne Heizkreis können direkt mit einem Vorschlag belegt werden.
  Future<void> _nachRaeumen(Objekt v, VerteilerDaten d, List<Objekt> kreise, Map<String, Raum> raeume, Set<String> belegt) async {
    final store = _s.store!;
    final nachRaum = <String?, List<Objekt>>{};
    for (final k in kreise) {
      nachRaum.putIfAbsent(k.raumId, () => []).add(k);
    }
    final ohne = [for (final r in raeume.values) if (r.umriss != null && r.umriss!.length >= 3 && r.art == RaumArt.raum && !nachRaum.containsKey(r.id)) r];
    final gewaehlt = <String?>{for (final e in nachRaum.entries) if (e.value.any((k) => !belegt.contains(k.id))) e.key};
    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Heizkreise nach Räumen'),
          content: SizedBox(
            width: 480,
            child: ListView(shrinkWrap: true, children: [
              for (final e in nachRaum.entries)
                CheckboxListTile(
                  dense: true,
                  value: gewaehlt.contains(e.key),
                  onChanged: (x) => setD(() => x == true ? gewaehlt.add(e.key) : gewaehlt.remove(e.key)),
                  title: Text(raeume[e.key]?.name ?? 'ohne Raum'),
                  subtitle: Text('${e.value.length} Kreis(e) · ${e.value.where((k) => belegt.contains(k.id)).length} schon am Verteiler · '
                      '${meterText(e.value.fold(0.0, (s, k) => s + rohrlaenge(k.punkte, FbhEinstellung.ausJson(k.eigenschaften))))}'),
                ),
              if (ohne.isNotEmpty) ...[
                const Divider(),
                Text('Noch ohne Heizkreis: ${ohne.map((r) => r.name).join(', ')}', style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
              ],
            ]),
          ),
          actions: [
            if (ohne.isNotEmpty) TextButton(onPressed: () => Navigator.pop(ctx, 'neu'), child: const Text('Kreise in Räumen vorschlagen …')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('Auf Abgänge legen')),
          ],
        ),
      ),
    );
    if (!mounted || ok == null) return;
    if (ok == 'neu') {
      final hkTyp = store.objekttypen().where((t) => t.kuerzel == 'HK').firstOrNull;
      if (hkTyp == null) return;
      final n = await heizkreiseNachRaeumen(context,
          store: store, geschossId: v.geschossId, raeume: ohne, vorhandene: kreise, hkTyp: hkTyp, verteiler: v.punkte.first);
      if (n > 0) _s.geaendert();
      return;
    }
    final neu = [for (final k in kreise) if (gewaehlt.contains(k.raumId) && !belegt.contains(k.id)) k]..sort((a, b) => wegZu(v, a).compareTo(wegZu(v, b)));
    final frei = d.kreise.where((k) => k == null).length;
    if (neu.length > frei) d.abgaengeSetzen(math.min(16, d.abgaenge + neu.length - frei));
    for (var i = 0; i < d.abgaenge && neu.isNotEmpty; i++) {
      if (d.kreise[i] == null) _zuordnen(v, d, i, neu.removeAt(0), kreise);
    }
    if (neu.isNotEmpty && mounted) zeigeWarnung(context, '${neu.length} Kreis(e) passen nicht mehr an den Verteiler (max. 16 Abgänge)');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final store = _s.store!;
        final g = _s.geschossId;
        final objekte = g == null ? <Objekt>[] : store.objekte(g);
        final v = objekte.where((o) => o.id == widget.objektId).firstOrNull;
        if (v == null) {
          return Scaffold(appBar: AppBar(title: const Text('Verteiler')), body: const Center(child: Text('Verteiler nicht gefunden.')));
        }
        final typen = {for (final t in store.objekttypen()) t.id: t};
        final kreise = [for (final o in objekte) if (typen[o.typId]?.kuerzel == 'HK') o];
        final raeume = {for (final r in store.raeume(g!)) r.id: r};
        final d = VerteilerDaten.ausJson(v.eigenschaften);
        final belegt = {for (final k in d.kreise) if (k != null) k};
        var summe = 0.0;
        for (final id in d.kreise) {
          final k = kreise.where((e) => e.id == id).firstOrNull;
          if (k != null) summe += rohrlaenge(k.punkte, FbhEinstellung.ausJson(k.eigenschaften));
        }

        Widget schalter(String text, bool wert, void Function(bool) setzen) => SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(text),
              value: wert,
              onChanged: (x) {
                setzen(x);
                _speichern(v, d);
              },
            );

        return Shortcuts(
          shortcuts: const {SingleActivator(LogicalKeyboardKey.keyZ, control: true): _RueckgaengigIntent()},
          child: Actions(
            actions: {
              _RueckgaengigIntent: CallbackAction<_RueckgaengigIntent>(onInvoke: (_) {
                if (_rueckgaengig.isNotEmpty) {
                  _rueckgaengig.removeLast()();
                  _s.geaendert();
                }
                return null;
              }),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: BsFarben.flaeche,
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  title: Text('Heizkreisverteiler ${v.kennung}'),
                  actions: [
                    IconButton(
                      tooltip: 'Rückgängig (Strg+Z)',
                      onPressed: _rueckgaengig.isEmpty
                          ? null
                          : () {
                              _rueckgaengig.removeLast()();
                              _s.geaendert();
                            },
                      icon: const Icon(Sym.rueckgaengig),
                    ),
                  ],
                ),
                body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Einstellungen
                  SizedBox(
                    width: 320,
                    child: Material(color: Colors.white, child: ListView(padding: const EdgeInsets.all(16), children: [
                      Text('Verteiler', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Text('Abgänge'),
                        const Spacer(),
                        IconButton(
                          onPressed: d.abgaenge <= 1 ? null : () => setState(() => _speichern(v, d..abgaengeSetzen(d.abgaenge - 1))),
                          icon: const Icon(Icons.remove),
                        ),
                        Text('${d.abgaenge}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        IconButton(
                          onPressed: d.abgaenge >= 16 ? null : () => setState(() => _speichern(v, d..abgaengeSetzen(d.abgaenge + 1))),
                          icon: const Icon(Icons.add),
                        ),
                      ]),
                      DropdownButtonFormField<Montage>(
                        isExpanded: true,
                        initialValue: d.montage,
                        decoration: const InputDecoration(labelText: 'Montageart'),
                        items: [for (final m in Montage.values) DropdownMenuItem(value: m, child: Text(m.label))],
                        onChanged: (m) => _speichern(v, d..montage = m ?? d.montage),
                      ),
                      const SizedBox(height: 6),
                      Text('Schrank ca. ${d.schrankBreite} × ${d.schrankHoehe} × ${d.montage.tiefe} mm (B × H × T)',
                          style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<bool>(
                        isExpanded: true,
                        initialValue: d.anschlussLinks,
                        decoration: const InputDecoration(labelText: 'Anschluss Vor-/Rücklauf'),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('von links')),
                          DropdownMenuItem(value: false, child: Text('von rechts')),
                        ],
                        onChanged: (x) => _speichern(v, d..anschlussLinks = x ?? true),
                      ),
                      const SizedBox(height: 16),
                      Text('Ventile und Steuerung', style: Theme.of(context).textTheme.titleSmall),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: antriebe.contains(d.antrieb) ? d.antrieb : antriebe.first,
                        decoration: const InputDecoration(labelText: 'Stellantriebe (Rücklauf)'),
                        items: [for (final a in antriebe) DropdownMenuItem(value: a, child: Text(a))],
                        onChanged: (a) => _speichern(v, d..antrieb = a ?? d.antrieb),
                      ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: d.vorlaufVentil,
                        decoration: const InputDecoration(labelText: 'Ventil im Vorlauf (je Abgang)'),
                        items: [for (final a in vorlaufVentile) DropdownMenuItem(value: a, child: Text(a))],
                        onChanged: (a) => _speichern(v, d..vorlaufVentil = a ?? d.vorlaufVentil),
                      ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: d.ruecklaufVentil,
                        decoration: const InputDecoration(labelText: 'Ventil im Rücklauf (je Abgang)'),
                        items: [for (final a in ruecklaufVentile) DropdownMenuItem(value: a, child: Text(a))],
                        onChanged: (a) => _speichern(v, d..ruecklaufVentil = a ?? d.ruecklaufVentil),
                      ),
                      schalter('Kugelhähne Vor-/Rücklauf', d.kugelhaehne, (x) => d.kugelhaehne = x),
                      schalter('Entlüftung / Entleerung (KFE)', d.entlueftung, (x) => d.entlueftung = x),
                      schalter('Mischer / Festwertregelung', d.mischer, (x) => d.mischer = x),
                      schalter('eigene Umwälzpumpe', d.pumpe, (x) => d.pumpe = x),
                      schalter('Wärmemengenzähler', d.waermemengenzaehler, (x) => d.waermemengenzaehler = x),
                      schalter('Thermometer Vor-/Rücklauf', d.thermometer, (x) => d.thermometer = x),
                      schalter('Überströmventil (Differenzdruck)', d.ueberstroemventil, (x) => d.ueberstroemventil = x),
                      schalter('Sicherheitstemperaturbegrenzer (STB)', d.temperaturbegrenzer, (x) => d.temperaturbegrenzer = x),
                      schalter('Schmutzfänger in der Zuleitung', d.schmutzfaenger, (x) => d.schmutzfaenger = x),
                      for (final h in d.hinweise())
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(h, style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
                        ),
                      const SizedBox(height: 16),
                      Text('Zuleitung vom Wärmeerzeuger', style: Theme.of(context).textTheme.titleSmall),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: dimensionen.contains(d.dimension) ? d.dimension : dimensionen[1],
                        decoration: const InputDecoration(labelText: 'Dimension'),
                        items: [for (final x in dimensionen) DropdownMenuItem(value: x, child: Text(x))],
                        onChanged: (x) => _speichern(v, d..dimension = x ?? d.dimension),
                      ),
                      const SizedBox(height: 8),
                      SpeicherFeld(
                        key: ValueKey('zul-${d.zuleitung}'),
                        initialValue: '${d.zuleitung}',
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Länge (einfach)', suffixText: 'mm'),
                        onFieldSubmitted: (x) => _speichern(v, d..zuleitung = int.tryParse(x) ?? 0),
                      ),
                      const SizedBox(height: 16),
                      Text('Stückliste', style: Theme.of(context).textTheme.titleSmall),
                      for (final (text, n) in d.stueckliste()) Text('$n × $text', style: const TextStyle(fontSize: 12)),
                      Text('${meterText(2 * d.zuleitung)} Zuleitung ${d.dimension} (Vor- + Rücklauf)',
                          style: const TextStyle(fontSize: 12)),
                    ])),
                  ),
                  // Schema und Belegung
                  Expanded(
                    child: ListView(padding: const EdgeInsets.all(20), children: [
                      Card(
                        child: SizedBox(
                          height: 300,
                          child: CustomPaint(
                            painter: _SchemaPainter(d: d, kreise: {for (final k in kreise) k.id: k}),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('Belegung der Abgänge', style: Theme.of(context).textTheme.titleMedium),
                        OutlinedButton.icon(
                          onPressed: () {
                            final belegte = [for (final k in kreise) if (belegt.contains(k.id)) k];
                            if (belegte.isEmpty) {
                              zeigeHinweis(context, 'Erst Heizkreise auf Abgänge legen.');
                              return;
                            }
                            final n = anbindeleitungenBuendeln(_s.store!, v.geschossId, belegte, v);
                            _s.geaendert();
                            zeigeHinweis(context, '$n Anbindeleitungen gebündelt gezeichnet (${belegte.length} Kreise).');
                          },
                          icon: const Icon(Icons.alt_route, size: 18),
                          label: const Text('Anbindeleitungen bündeln'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _nachRaeumen(v, d, kreise, raeume, belegt),
                          icon: const Icon(Icons.meeting_room_outlined, size: 18),
                          label: const Text('Nach Räumen …'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            // freie Abgänge mit den nächstgelegenen, noch freien Heizkreisen füllen
                            final frei = [for (final k in kreise) if (!belegt.contains(k.id)) k]
                              ..sort((a, b) => wegZu(v, a).compareTo(wegZu(v, b)));
                            for (var i = 0; i < d.abgaenge && frei.isNotEmpty; i++) {
                              if (d.kreise[i] == null) _zuordnen(v, d, i, frei.removeAt(0), kreise);
                            }
                          },
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                          label: const Text('Heizkreise automatisch zuordnen'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Card(
                        child: Column(children: [
                          for (var i = 0; i < d.abgaenge; i++)
                            Builder(builder: (_) {
                              final k = kreise.where((e) => e.id == d.kreise[i]).firstOrNull;
                              final laenge = k == null ? 0.0 : rohrlaenge(k.punkte, FbhEinstellung.ausJson(k.eigenschaften));
                              final raum = raeume[k?.raumId];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                                title: DropdownButton<String?>(
                                  value: k?.id,
                                  isExpanded: true,
                                  underline: const SizedBox.shrink(),
                                  hint: const Text('– frei –'),
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('– frei –')),
                                    for (final x in kreise)
                                      DropdownMenuItem(
                                        value: x.id,
                                        child: Text('${x.kennung}${raeume[x.raumId] == null ? '' : ' · ${raeume[x.raumId]!.name}'}'
                                            '${belegt.contains(x.id) && x.id != k?.id ? '  (belegt)' : ''}'),
                                      ),
                                  ],
                                  onChanged: (id) => _zuordnen(v, d, i, kreise.where((e) => e.id == id).firstOrNull, kreise),
                                ),
                                subtitle: k == null
                                    ? null
                                    : Text('${raum?.name ?? 'kein Raum'} · ${flaecheText(polygonFlaeche(k.punkte).abs())} · '
                                        'VA ${FbhEinstellung.ausJson(k.eigenschaften).abstand} mm'),
                                trailing: k == null
                                    ? null
                                    : Text(meterText(laenge),
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: laenge > maxKreislaenge ? const Color(0xFFB91C1C) : null)),
                              );
                            }),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      Text('Summe Heizrohr ${meterText(summe)} · ${kreise.where((k) => !belegt.contains(k.id)).length} Heizkreis(e) noch ohne Abgang',
                          style: const TextStyle(color: BsFarben.textLeise)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RueckgaengigIntent extends Intent {
  const _RueckgaengigIntent();
}

/// Prinzipschema: Vor- und Rücklaufbalken, Abgänge mit ihren Ventilen und die
/// gewählte Zusatzausstattung (Kugelhähne, Schmutzfänger, Mischer, Pumpe, STB,
/// Wärmemengenzähler, Thermometer, Überströmventil, KFE) als Skizze.
class _SchemaPainter extends CustomPainter {
  _SchemaPainter({required this.d, required this.kreise});
  final VerteilerDaten d;
  final Map<String, Objekt> kreise;

  static const rot = Color(0xFFE03131), blau = Color(0xFF1C7ED6), grau = Color(0xFF495057);

  void _text(Canvas c, String t, Offset p, {double groesse = 10, Color farbe = BsFarben.textLeise, bool mitte = true}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: groesse, color: farbe)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, mitte ? p - Offset(tp.width / 2, 0) : p);
  }

  Paint _strich(Color f, [double b = 1.4]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = b
    ..color = f;

  /// Ventil (zwei Dreiecke, „Fliege“) um [c]; [senkrecht] für Leitungen nach unten.
  void _ventil(Canvas c, Offset m, {bool senkrecht = true, Color farbe = grau, double g = 6}) {
    final p = Path();
    if (senkrecht) {
      p
        ..moveTo(m.dx - g, m.dy - g)
        ..lineTo(m.dx + g, m.dy - g)
        ..lineTo(m.dx - g, m.dy + g)
        ..lineTo(m.dx + g, m.dy + g)
        ..close();
    } else {
      p
        ..moveTo(m.dx - g, m.dy - g)
        ..lineTo(m.dx - g, m.dy + g)
        ..lineTo(m.dx + g, m.dy - g)
        ..lineTo(m.dx + g, m.dy + g)
        ..close();
    }
    c.drawPath(p, Paint()..color = Colors.white);
    c.drawPath(p, _strich(farbe));
  }

  void _kasten(Canvas c, Offset m, String t, Color farbe, {double b = 22, double h = 14}) {
    final r = Rect.fromCenter(center: m, width: b, height: h);
    c.drawRect(r, Paint()..color = Colors.white);
    c.drawRect(r, _strich(farbe));
    _text(c, t, m - const Offset(0, 6), groesse: 8, farbe: farbe);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const yVl = 90.0, yRl = 160.0, yUnten = 250.0;
    // Platz für die Zusatzausstattung auf der Anschlussseite
    final zusatzVl = [
      if (d.kugelhaehne) 'KH',
      if (d.schmutzfaenger) 'SF',
      if (d.pumpe) 'P',
      if (d.temperaturbegrenzer) 'STB',
      if (d.thermometer) 'T',
    ];
    final zusatzRl = [
      if (d.kugelhaehne) 'KH',
      if (d.waermemengenzaehler) 'WMZ',
      if (d.thermometer) 'T',
    ];
    final n = math.max(zusatzVl.length, zusatzRl.length) + (d.mischer ? 1 : 0);
    final rand = 50.0 + n * 34;
    final links = d.anschlussLinks ? rand : 40.0;
    final rechts = size.width - (d.anschlussLinks ? 40.0 : rand);
    final s = d.anschlussLinks ? -1.0 : 1.0; // Richtung von den Balken zur Zuleitung
    final xBalken = d.anschlussLinks ? links : rechts; // Balkenende an der Zuleitung
    final xFern = d.anschlussLinks ? rechts : links;

    // Balken
    final balken = Paint()
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(links, yVl), Offset(rechts, yVl), balken..color = rot);
    canvas.drawLine(Offset(links, yRl), Offset(rechts, yRl), balken..color = blau);

    // Zuleitung mit Ausstattung
    final xEnde = xBalken + s * (rand - 20);
    canvas.drawLine(Offset(xBalken, yVl), Offset(xEnde, yVl), _strich(rot, 3));
    canvas.drawLine(Offset(xBalken, yRl), Offset(xEnde, yRl), _strich(blau, 3));
    _text(canvas, 'VL vom Wärmeerzeuger', Offset(xEnde, yVl - 26), groesse: 9, farbe: rot);
    _text(canvas, 'RL', Offset(xEnde, yRl + 10), groesse: 9, farbe: blau);
    var x = xBalken + s * 30;
    if (d.mischer) {
      // Mischer: Dreiwegeventil mit Bypass zwischen Rück- und Vorlauf
      canvas.drawLine(Offset(x, yVl), Offset(x, yRl), _strich(grau, 2));
      final m = Offset(x, yVl);
      _ventil(canvas, m, senkrecht: false);
      canvas.drawPath(
          Path()
            ..moveTo(m.dx - 6, m.dy + 6)
            ..lineTo(m.dx + 6, m.dy + 6)
            ..lineTo(m.dx, m.dy)
            ..close(),
          _strich(grau));
      _text(canvas, 'Mischer', Offset(x, yVl - 24), groesse: 8, farbe: grau);
      x += s * 34;
    }
    final xStart = x;
    for (final t in zusatzVl) {
      final m = Offset(x, yVl);
      switch (t) {
        case 'KH':
          _ventil(canvas, m, senkrecht: false, farbe: Colors.black87);
          canvas.drawLine(m, m - const Offset(0, 11), _strich(Colors.black87));
        case 'SF':
          canvas.drawLine(m, m + const Offset(8, 12), _strich(grau, 2));
          canvas.drawCircle(m + const Offset(8, 12), 3, _strich(grau));
        case 'P':
          canvas.drawCircle(m, 8, Paint()..color = Colors.white);
          canvas.drawCircle(m, 8, _strich(grau));
          canvas.drawPath(
              Path()
                ..moveTo(m.dx - 4 * s, m.dy - 5)
                ..lineTo(m.dx + 5 * s, m.dy)
                ..lineTo(m.dx - 4 * s, m.dy + 5)
                ..close(),
              Paint()..color = grau);
        case 'STB':
          _kasten(canvas, m, 'STB', grau, b: 26);
        case 'T':
          canvas.drawCircle(m - const Offset(0, 14), 5, _strich(rot));
          canvas.drawLine(m, m - const Offset(0, 9), _strich(rot));
      }
      _text(canvas, t == 'T' ? '' : t, m + const Offset(0, 12), groesse: 8, farbe: grau);
      x += s * 34;
    }
    x = xStart;
    for (final t in zusatzRl) {
      final m = Offset(x, yRl);
      switch (t) {
        case 'KH':
          _ventil(canvas, m, senkrecht: false, farbe: Colors.black87);
          canvas.drawLine(m, m + const Offset(0, 11), _strich(Colors.black87));
        case 'WMZ':
          _kasten(canvas, m, 'WMZ', grau, b: 28);
        case 'T':
          canvas.drawCircle(m + const Offset(0, 14), 5, _strich(blau));
          canvas.drawLine(m, m + const Offset(0, 9), _strich(blau));
      }
      x += s * 34;
    }

    // Abgänge
    final innenA = math.min(xBalken, xFern) + 30, innenB = math.max(xBalken, xFern) - 40;
    final dx = (innenB - innenA) / math.max(1, d.abgaenge);
    for (var i = 0; i < d.abgaenge; i++) {
      final xi = d.anschlussLinks ? innenA + dx * (i + 0.5) : innenB - dx * (i + 0.5);
      final k = kreise[d.kreise[i]];
      final xv = xi - 6, xr = xi + 6;
      canvas.drawLine(Offset(xv, yVl), Offset(xv, 34), _strich(rot, 2.5));
      canvas.drawLine(Offset(xv, 34), Offset(xv, 22), _strich(rot, 2.5));
      canvas.drawLine(Offset(xr, yRl), Offset(xr, yUnten), _strich(blau, 2.5));
      // Ventil im Vorlauf
      final mv = Offset(xv, yVl - 26);
      switch (d.vorlaufVentil) {
        case 'Durchflussmesser (Topmeter)':
          final r = Rect.fromCenter(center: mv, width: 9, height: 18);
          canvas.drawRect(r, Paint()..color = Colors.white);
          canvas.drawRect(r, _strich(rot));
        case 'Regulierventil mit Skala':
          _ventil(canvas, mv, farbe: rot, g: 5);
          canvas.drawLine(mv + const Offset(-7, 7), mv + const Offset(7, -7), _strich(rot));
        case 'Absperrventil':
          _ventil(canvas, mv, farbe: rot, g: 5);
      }
      // Ventil im Rücklauf, darauf ggf. der Stellantrieb
      final mr = Offset(xr, yRl + 26);
      _ventil(canvas, mr, farbe: blau, g: 5);
      switch (d.ruecklaufVentil) {
        case 'Ventil mit Voreinstellung':
          canvas.drawCircle(mr + const Offset(9, 0), 2, Paint()..color = blau);
        case 'druckunabhängiges Regelventil (dynamisch)':
          _text(canvas, 'Δp', mr + const Offset(13, -5), groesse: 8, farbe: blau);
        case 'Handregulierventil':
          canvas.drawLine(mr + const Offset(6, 0), mr + const Offset(14, 0), _strich(blau));
          canvas.drawLine(mr + const Offset(14, -4), mr + const Offset(14, 4), _strich(blau));
      }
      if (!d.antrieb.startsWith('keine')) {
        final a = Rect.fromCenter(center: mr + const Offset(0, 17), width: 13, height: 12);
        canvas.drawRect(a, Paint()..color = grau);
        _text(canvas, 'M', a.center - const Offset(0, 6), groesse: 8, farbe: Colors.white);
      }
      _text(canvas, '${i + 1}', Offset(xi, 6), groesse: 11, farbe: Colors.black87);
      _text(canvas, k?.kennung.split('-').skip(1).join('-') ?? 'frei', Offset(xi, yUnten + 6), groesse: 9);
    }

    // Fernes Balkenende: KFE / Entlüftung, Überströmventil
    if (d.entlueftung) {
      for (final (y, f) in [(yVl, rot), (yRl, blau)]) {
        final m = Offset(xFern - s * 14, y);
        canvas.drawLine(Offset(xFern, y), m, _strich(f, 2));
        _ventil(canvas, m + Offset(-s * 6, 0), senkrecht: false, farbe: f, g: 4);
      }
      _text(canvas, 'KFE / Entlüftung', Offset(xFern - s * 14, yRl + 12), groesse: 8);
    }
    if (d.ueberstroemventil) {
      final xu = xFern + s * 24;
      canvas.drawLine(Offset(xu, yVl + 6), Offset(xu, yRl - 6), _strich(grau, 2));
      final m = Offset(xu, (yVl + yRl) / 2);
      _ventil(canvas, m);
      final zick = Path()..moveTo(m.dx + 7, m.dy - 8);
      for (var j = 0; j < 4; j++) {
        zick.lineTo(m.dx + (j.isEven ? 13 : 7), m.dy - 8 + (j + 1) * 4);
      }
      canvas.drawPath(zick, _strich(grau));
      _text(canvas, 'Überström', m + const Offset(0, 12), groesse: 8, farbe: grau);
    }
  }

  @override
  bool shouldRepaint(covariant _SchemaPainter old) => true;
}
