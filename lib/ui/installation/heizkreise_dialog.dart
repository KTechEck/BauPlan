import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/fbh.dart';
import '../../core/raumerkennung.dart';
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

  List<(List<Punkt>, Map<String, Object?>)> _vorschlag(Raum r) =>
      heizkreiseVorschlagen(r.umriss!, _e, ziel: widget.verteiler, maxLaenge: _maxM * 1000.0);

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
                    for (final x in _sperren(r)) 'Sperrfläche: ${x.kennung} (Kreis aussparen)',
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
