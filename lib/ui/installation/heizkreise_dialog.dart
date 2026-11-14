import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/fbh.dart';
import '../../core/raumerkennung.dart';
import '../../core/verteiler.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';

/// Heizkreise nach Räumen auswählen: je Raum ein Vorschlag (Anzahl der Kreise
/// nach maximaler Kreislänge, Flächen gleich groß geteilt, Zugang zum
/// Heizkreisverteiler hin). Legt die gewählten Kreise an und gibt ihre Anzahl zurück.
Future<int> heizkreiseNachRaeumen(
  BuildContext context, {
  required ProjectStore store,
  required String geschossId,
  required List<Raum> raeume,
  required List<Objekt> vorhandene,
  required Objekttyp hkTyp,
  Punkt? verteiler,
  ObjektStatus status = ObjektStatus.geplant,
}) async {
  final mitUmriss = [for (final r in raeume) if (r.umriss != null && r.umriss!.length >= 3 && r.art == RaumArt.raum) r];
  if (mitUmriss.isEmpty) return 0;
  final anzahl = await showDialog<int>(
    context: context,
    builder: (_) => _HeizkreiseDialog(
      store: store,
      geschossId: geschossId,
      raeume: mitUmriss,
      vorhandene: vorhandene,
      hkTyp: hkTyp,
      verteiler: verteiler,
      status: status,
    ),
  );
  return anzahl ?? 0;
}

class _HeizkreiseDialog extends StatefulWidget {
  const _HeizkreiseDialog({
    required this.store,
    required this.geschossId,
    required this.raeume,
    required this.vorhandene,
    required this.hkTyp,
    required this.verteiler,
    required this.status,
  });
  final ProjectStore store;
  final String geschossId;
  final List<Raum> raeume;
  final List<Objekt> vorhandene;
  final Objekttyp hkTyp;
  final Punkt? verteiler;
  final ObjektStatus status;

  @override
  State<_HeizkreiseDialog> createState() => _HeizkreiseDialogState();
}

class _HeizkreiseDialogState extends State<_HeizkreiseDialog> {
  final _gewaehlt = <String>{};
  var _abstand = 150;
  var _muster = Verlegemuster.schnecke;
  var _maxM = 100;
  var _rand = 100;

  List<Objekt> _schonDa(Raum r) => [
        for (final o in widget.vorhandene)
          if (o.typId == widget.hkTyp.id && (o.raumId == r.id || (o.punkte.isNotEmpty && punktInPolygon(_mitte(o.punkte), r.umriss!)))) o
      ];

  /// Geräte mit Aufstellfläche im Raum (Technik, Möbel, Sanitär mit Maßen) –
  /// darunter wird keine Fußbodenheizung verlegt.
  List<Objekt> _sperren(Raum r) => [
        for (final o in widget.vorhandene)
          if (o.typId != widget.hkTyp.id &&
              o.punkte.length == 1 &&
              o.eigenschaften['masse'] is List &&
              o.eigenschaften['montage'] != 'Wand' &&
              punktInPolygon(o.punkte.first, r.umriss!))
            o
      ];

  static Punkt _mitte(List<Punkt> p) {
    var x = 0.0, y = 0.0;
    for (final q in p) {
      x += q.x;
      y += q.y;
    }
    return Punkt(x / p.length, y / p.length);
  }

  FbhEinstellung get _e => FbhEinstellung.ausJson({'va_mm': _abstand, 'rand_mm': _rand, 'muster': _muster.name});

  List<(List<Punkt>, Map<String, Object?>)> _vorschlag(Raum r) {
    final sperren = [
      for (final o in _sperren(r))
        aufstellflaeche(o.punkte.first, ((o.eigenschaften['masse'] as List)[0] as num).toDouble(), ((o.eigenschaften['masse'] as List)[1] as num).toDouble(),
            (o.eigenschaften['drehung'] as num?) ?? 0),
    ];
    return heizkreiseVorschlagen(r.umriss!, _e, ziel: widget.verteiler, maxLaenge: _maxM * 1000.0,
        basis: sperren.isEmpty ? const {} : {'sperren': sperrenJson(sperren)});
  }

  @override
  void initState() {
    super.initState();
    // Räume ohne Heizkreis vorwählen
    for (final r in widget.raeume) {
      if (_schonDa(r).isEmpty) _gewaehlt.add(r.id);
    }
  }

  void _anlegen() {
    var n = 0;
    for (final r in widget.raeume) {
      if (!_gewaehlt.contains(r.id)) continue;
      final kreise = _vorschlag(r);
      for (final (i, (umriss, eig)) in kreise.indexed) {
        final id = widget.store.objektAnlegen(
          geschossId: widget.geschossId,
          typ: widget.hkTyp,
          punkte: umriss,
          raumId: r.id,
          lage: 'im Estrich',
          status: widget.status,
        );
        widget.store.objektAendern(id, {
          'eigenschaften': jsonEncode({...eig, 'bezeichnung': kreise.length == 1 ? r.name : '${r.name} ${i + 1}'}),
        });
        n++;
      }
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final zeilen = [
      for (final r in widget.raeume) (r, _schonDa(r), _gewaehlt.contains(r.id) ? _vorschlag(r) : const <(List<Punkt>, Map<String, Object?>)>[]),
    ];
    final summe = zeilen.fold<int>(0, (s, z) => s + z.$3.length);
    String m(double mm) => '${(mm / 1000).toStringAsFixed(0)} m';
    return AlertDialog(
      title: const Text('Heizkreise nach Räumen'),
      content: SizedBox(
        width: 640,
        height: 520,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _auswahl<int>('Verlegeabstand', _abstand, const [75, 100, 125, 150, 200, 250, 300], (v) => '$v mm', (v) => _abstand = v),
            _auswahl<Verlegemuster>('Muster', _muster, Verlegemuster.values, (v) => v.label, (v) => _muster = v),
            _auswahl<int>('Max. Kreislänge', _maxM, const [80, 100, 120], (v) => '$v m', (v) => _maxM = v),
            _auswahl<int>('Randabstand', _rand, const [50, 100, 150, 200], (v) => '$v mm', (v) => _rand = v),
          ]),
          const SizedBox(height: 6),
          Text(
            widget.verteiler == null
                ? 'Kein Heizkreisverteiler (HV) in diesem Geschoss – Zugang und Zuleitung bitte danach anpassen.'
                : 'Zugang je Kreis zum Heizkreisverteiler hin, Zuleitung als rechtwinkliger Weg geschätzt.',
            style: const TextStyle(fontSize: 12, color: BsFarben.textLeise),
          ),
          const Divider(),
          Expanded(
            child: ListView(children: [
              for (final (r, da, kreise) in zeilen)
                CheckboxListTile(
                  dense: true,
                  value: _gewaehlt.contains(r.id),
                  onChanged: (v) => setState(() => v == true ? _gewaehlt.add(r.id) : _gewaehlt.remove(r.id)),
                  title: Text('${r.name}  ·  ${(polygonFlaeche(r.umriss!).abs() / 1e6).toStringAsFixed(1).replaceAll('.', ',')} m²'),
                  subtitle: Text([
                    if (da.isNotEmpty) 'hat schon ${da.length} Kreis${da.length == 1 ? '' : 'e'}',
                    for (final x in _sperren(r)) 'Sperrfläche: ${x.kennung} (wird ausgespart)',
                    if (kreise.isNotEmpty)
                      '${kreise.length} Kreis${kreise.length == 1 ? '' : 'e'}: ${[
                        for (final k in kreise) m(rohrlaenge(k.$1, FbhEinstellung.ausJson(k.$2)))
                      ].join(' / ')}',
                  ].join(' · ')),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: summe == 0 ? null : _anlegen, child: Text('$summe Heizkreise anlegen')),
      ],
    );
  }

  Widget _auswahl<T>(String label, T wert, List<T> werte, String Function(T) text, void Function(T) setzen) => SizedBox(
        width: 140,
        child: DropdownButtonFormField<T>(
          initialValue: wert,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final v in werte) DropdownMenuItem(value: v, child: Text(text(v), overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v != null) setState(() => setzen(v));
          },
        ),
      );
}

/// Anbindeleitungen (VL/RL) für mehrere Heizkreise gebündelt zum Verteiler
/// zeichnen: rechtwinklig, durch die Tür des Raums, parallel im Abstand von
/// 2 × Rohrbreite nebeneinander (je Kreis ein eigenes Paar), am Verteiler auf
/// die Abgänge verteilt. Vorhandene Anbindeleitungen der Kreise werden ersetzt.
/// Gibt die Anzahl gezeichneter Leitungen zurück.
int anbindeleitungenBuendeln(ProjectStore store, String geschossId, List<Objekt> kreise, Objekt verteiler, {ObjektStatus status = ObjektStatus.geplant}) {
  final typen = store.objekttypen();
  final hr = typen.where((t) => t.kuerzel == 'HR').firstOrNull;
  if (hr == null || verteiler.punkte.isEmpty) return 0;
  final waende = {for (final w in store.waende(geschossId)) w.id: w};
  final raeume = store.raeume(geschossId);
  final tueren = <Durchgang>[
    for (final oe in store.oeffnungen(geschossId))
      if (oe.art == OeffnungsArt.tuer && waende[oe.wandId] != null)
        () {
          final w = waende[oe.wandId]!;
          final a = Punkt(w.x1.toDouble(), w.y1.toDouble()), b = Punkt(w.x2.toDouble(), w.y2.toDouble());
          final r = (b - a) * (1 / math.max(1, (b - a).laenge));
          return (mitte: a + r * (oe.abstand + oe.breite / 2), richtung: r, dicke: w.dicke.toDouble());
        }(),
  ];
  final hv = verteiler.punkte.first;
  // alte Anbindeleitungen dieser Kreise entfernen
  final ids = {for (final k in kreise) k.id};
  for (final o in store.objekte(geschossId)) {
    if (o.typId == hr.id && ids.contains(o.eigenschaften['heizkreis'])) store.objektLoeschen(o.id);
  }
  // Ziele: Anschlüsse VL/RL des belegten Abgangs am Verteilerschrank, sonst nebeneinander am Verteiler
  final vd = VerteilerDaten.ausJson(verteiler.eigenschaften);
  final wandStrecken = [
    for (final w in waende.values) (a: Punkt(w.x1.toDouble(), w.y1.toDouble()), b: Punkt(w.x2.toDouble(), w.y2.toDouble()), dicke: w.dicke.toDouble()),
  ];
  final anschluss = {for (final (name, p) in verteilerAnschlussPunkte(hv, vd, wandStrecken)) name: p};
  const rohr = 20.0, teilung = 2 * rohr;
  final anfragen = <AnbindungsAnfrage>[];
  final plaene = <String, Objekt>{};
  for (final (i, hk) in kreise.indexed) {
    final z = verlegeplan(hk.punkte, FbhEinstellung.ausJson(hk.eigenschaften));
    if (z.anschlussVl == null || z.anschlussRl == null) continue;
    final raum = raeume.where((r) => r.id == hk.raumId).firstOrNull?.umriss ??
        raeume.where((r) => r.umriss != null && r.umriss!.length >= 3 && punktInPolygon(hk.punkte.first, r.umriss!)).firstOrNull?.umriss;
    final abgang = vd.kreise.indexOf(hk.id) + 1;
    for (final (ende, art, seite) in [(z.anschlussVl!, 'VL', 0), (z.anschlussRl!, 'RL', 1)]) {
      final ziel = abgang > 0 && anschluss['$abgang $art'] != null ? anschluss['$abgang $art']! : hv + Punkt((2 * i + seite) * teilung - teilung * kreise.length, 0);
      final id = '${hk.id}|$art';
      anfragen.add((id: id, start: ende, ziel: ziel, raum: raum));
      plaene[id] = hk;
    }
  }
  final wege = anbindungenBuendeln(anfragen, tueren, teilung: teilung);
  var n = 0;
  final summe = <String, double>{}, erste = <String, String>{};
  for (final a in anfragen) {
    final w = wege[a.id];
    final hk = plaene[a.id]!;
    if (w == null || w.length < 2) continue;
    final art = a.id.split('|').last;
    final id = store.objektAnlegen(geschossId: geschossId, typ: hr, punkte: w, raumId: hk.raumId, lage: 'im Estrich', status: status);
    store.objektAendern(id, {'eigenschaften': jsonEncode({'leitung': art, 'heizkreis': hk.id, 'verteiler': verteiler.id, 'breite_mm': rohr, 'verlegung': 'unterputz'})});
    n++;
    erste.putIfAbsent(hk.id, () => id);
    for (var k = 0; k + 1 < w.length; k++) {
      summe[hk.id] = (summe[hk.id] ?? 0) + (w[k + 1] - w[k]).laenge / 2; // Mittel aus VL und RL
    }
  }
  for (final hk in kreise) {
    if (summe[hk.id] == null) continue;
    final aktuell = store.objekte(geschossId).where((o) => o.id == hk.id).firstOrNull ?? hk;
    store.objektAendern(hk.id, {
      'eigenschaften': jsonEncode({...aktuell.eigenschaften, 'zuleitung_mm': summe[hk.id]!.round(), 'anbindung': erste[hk.id], 'verteiler': verteiler.id}),
    });
  }
  return n;
}
