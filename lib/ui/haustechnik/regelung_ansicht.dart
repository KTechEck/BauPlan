import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../core/hydraulik_schema.dart';
import '../../core/ids.dart';
import '../../core/ta_regler.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Regelung mit Technischer Alternative: Regler, Ein-/Ausgangsbelegung,
/// Kapazitätsprüfung, Fühlerplan mit Kabelweg, TAPPS2-Vorlage,
/// C.M.I.-Schemaseite und Live-Werte (nur lesend).
class RegelungAnsicht extends StatefulWidget {
  const RegelungAnsicht({super.key, required this.state});
  final AppState state;

  @override
  State<RegelungAnsicht> createState() => _RegelungAnsichtState();
}

class _RegelungAnsichtState extends State<RegelungAnsicht> {
  Map<String, Map<String, String>> _live = {};
  String? _meldung;
  bool _laedt = false;

  AppState get _s => widget.state;
  TaBelegung get _b => TaBelegung.ausJson(_s.store!.einstellung<Map>('ta_regelung'));
  void _speichern(TaBelegung b) {
    _s.store!.einstellungSetzen('ta_regelung', b.toJson());
    _s.geaendert();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final b = _b;
    final objekte = {for (final o in store.alleObjekte()) if (o.punkte.length == 1) o.id: o};
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final kap = taKapazitaet(b);
    final kabel = <String, double>{};
    for (final k in b.kanaele) {
      final g = b.geraete.where((x) => x.id == k.regler).firstOrNull;
      final ro = objekte[g?.objekt], zo = objekte[k.objekt];
      final m = k.kabelM ?? (ro != null && zo != null ? taKabelweg((ro.punkte.first.x, ro.punkte.first.y), (zo.punkte.first.x, zo.punkte.first.y)) : null);
      if (m != null && k.eingang) kabel[taKabeltyp(k.typ)] = (kabel[taKabeltyp(k.typ)] ?? 0) + m;
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final t in taRegler.keys)
          OutlinedButton.icon(
            onPressed: () => _speichern(TaBelegung([...b.geraete, TaGeraet(id: neueId(), typ: t, canKnoten: b.geraete.length + 1)], b.kanaele, cmi: b.cmi)),
            icon: const Icon(Icons.add, size: 18),
            label: Text(t),
          ),
      ]),
      const SizedBox(height: 4),
      const Text('Kapazitäten sind Richtwerte – Datenblatt des Reglers prüfen. Kabelwege werden aus der Lage von Regler und Fühler im Grundriss geschätzt.',
          style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
      for (final h in kap) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $h', style: const TextStyle(color: Color(0xFFB45309)))),
      for (final g in b.geraete) _regler(g, b, objekte, typen),
      if (b.geraete.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Fühlerkabel (geschätzt)', style: Theme.of(context).textTheme.titleSmall),
        for (final e in kabel.entries) Text('${e.key}: ${e.value.ceil()} m'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: () async {
              final f = File(p.join(store.ordner, 'exporte', 'technische_alternative', 'TAPPS2-Vorlage.txt'));
              await f.parent.create(recursive: true);
              await f.writeAsString(tapps2Vorlage(b, projekt: store.name));
              if (context.mounted) zeigeHinweis(context, 'Gespeichert unter ${f.path}');
            },
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('TAPPS2-Vorlage'),
          ),
          FilledButton.tonalIcon(
            onPressed: () async {
              // Schema mit Platzhaltern der verknüpften Ein-/Ausgänge als C.M.I.-Hintergrund
              final schema = HydraulikSchema.ausJson(store.einstellung<Map>('hydraulikschema'));
              final ph = <String, String>{};
              for (final sy in schema.symbole) {
                final k = b.kanaele.where((k) => k.objekt != null && k.objekt == sy.objekt).toList();
                if (k.isNotEmpty) ph[sy.id] = k.map((x) => x.kurz).join(' ');
              }
              final ordner = Directory(p.join(store.ordner, 'exporte', 'technische_alternative'));
              await ordner.create(recursive: true);
              await File(p.join(ordner.path, 'CMI-Schema.svg')).writeAsString(schemaSvg(schema, platzhalter: ph, titel: store.name));
              final csv = StringBuffer('Symbol;Platzhalter;x;y\n');
              for (final sy in schema.symbole) {
                if (ph[sy.id] != null) csv.writeln('${sy.name.isEmpty ? sy.art : sy.name};${ph[sy.id]};${sy.x.round()};${sy.y.round()}');
              }
              await File(p.join(ordner.path, 'CMI-Platzhalter.csv')).writeAsString('﻿$csv');
              if (context.mounted) zeigeHinweis(context, 'Schema und Platzhalterliste gespeichert unter ${ordner.path}');
            },
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text('C.M.I.-Schemaseite (SVG + Platzhalter)'),
          ),
        ]),
        const Divider(height: 32),
        Text('Live-Werte über C.M.I. (nur lesend, Heimnetz)', style: Theme.of(context).textTheme.titleSmall),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 200,
            child: SpeicherFeld(
              key: ValueKey('cmi-${b.cmi}'),
              initialValue: b.cmi,
              decoration: const InputDecoration(labelText: 'Adresse C.M.I.', hintText: '192.168.1.50', isDense: true),
              onFieldSubmitted: (t) => _speichern(TaBelegung(b.geraete, b.kanaele, cmi: t.trim())),
            ),
          ),
          SizedBox(
            width: 140,
            child: SpeicherFeld(
              key: ValueKey('cmiu-${_s.settings.cmi?['benutzer']}'),
              initialValue: '${_s.settings.cmi?['benutzer'] ?? 'admin'}',
              decoration: const InputDecoration(labelText: 'Benutzer', isDense: true),
              onFieldSubmitted: (t) {
                _s.settings.cmi = {...?_s.settings.cmi, 'benutzer': t.trim()};
                _s.settings.speichern();
              },
            ),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort', isDense: true, helperText: 'nur auf diesem PC'),
              onSubmitted: (t) {
                _s.settings.cmi = {...?_s.settings.cmi, 'passwort': t};
                _s.settings.speichern();
              },
            ),
          ),
          FilledButton.icon(
            onPressed: b.cmi.isEmpty || _laedt
                ? null
                : () async {
                    setState(() {
                      _laedt = true;
                      _meldung = null;
                    });
                    final neu = <String, Map<String, String>>{};
                    try {
                      for (final g in b.geraete) {
                        neu[g.id] = await cmiLesen(b.cmi, g.canKnoten, '${_s.settings.cmi?['benutzer'] ?? 'admin'}', '${_s.settings.cmi?['passwort'] ?? ''}');
                      }
                    } catch (e) {
                      _meldung = 'C.M.I.: $e';
                    }
                    if (mounted) {
                      setState(() {
                        _live = neu;
                        _laedt = false;
                      });
                    }
                  },
            icon: const Icon(Icons.sensors, size: 18),
            label: const Text('Werte holen'),
          ),
        ]),
        if (_meldung != null) Text(_meldung!, style: const TextStyle(color: Color(0xFFB91C1C))),
      ],
    ]);
  }

  Widget _regler(TaGeraet g, TaBelegung b, Map<String, dynamic> objekte, Map<String, dynamic> typen) {
    final kap = taRegler[g.typ];
    final kan = b.kanaele.where((k) => k.regler == g.id).toList()..sort((a, c) => a.eingang == c.eingang ? a.nr.compareTo(c.nr) : (a.eingang ? -1 : 1));
    void kanalAendern(TaKanal alt, TaKanal neu) => _speichern(TaBelegung(b.geraete, [for (final k in b.kanaele) identical(k, alt) ? neu : k], cmi: b.cmi));
    final live = _live[g.id] ?? const {};
    final punktObjekte = objekte.values.toList();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: SpeicherFeld(
                key: ValueKey('tan-${g.id}-${g.name}'),
                initialValue: g.name.isEmpty ? g.typ : g.name,
                decoration: InputDecoration(labelText: '${g.typ} · ${kap?.hinweis ?? ''}', isDense: true),
                onFieldSubmitted: (t) => _speichern(TaBelegung([for (final x in b.geraete) x.id == g.id ? TaGeraet(id: g.id, typ: g.typ, name: t.trim(), objekt: g.objekt, canKnoten: g.canKnoten) : x], b.kanaele, cmi: b.cmi)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: objekte.containsKey(g.objekt) ? g.objekt : null,
                decoration: const InputDecoration(labelText: 'Ort im Grundriss', isDense: true),
                items: [const DropdownMenuItem(value: null, child: Text('–')), for (final o in punktObjekte) DropdownMenuItem(value: o.id as String, child: Text('${o.kennung}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => _speichern(TaBelegung([for (final x in b.geraete) x.id == g.id ? TaGeraet(id: g.id, typ: g.typ, name: g.name, objekt: v, canKnoten: g.canKnoten) : x], b.kanaele, cmi: b.cmi)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: SpeicherFeld(
                key: ValueKey('tak-${g.id}-${g.canKnoten}'),
                initialValue: '${g.canKnoten}',
                decoration: const InputDecoration(labelText: 'CAN-Knoten', isDense: true),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onFieldSubmitted: (t) => _speichern(TaBelegung([for (final x in b.geraete) x.id == g.id ? TaGeraet(id: g.id, typ: g.typ, name: g.name, objekt: g.objekt, canKnoten: int.tryParse(t) ?? 1) : x], b.kanaele, cmi: b.cmi)),
              ),
            ),
            IconButton(
              tooltip: 'Regler entfernen',
              onPressed: () => _speichern(TaBelegung([for (final x in b.geraete) if (x.id != g.id) x], [for (final k in b.kanaele) if (k.regler != g.id) k], cmi: b.cmi)),
              icon: const Icon(Icons.delete_outline),
            ),
          ]),
          const SizedBox(height: 6),
          for (final k in kan)
            Row(children: [
              SizedBox(width: 40, child: Text(k.kurz, style: const TextStyle(fontWeight: FontWeight.w700))),
              SizedBox(
                width: 190,
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: (k.eingang ? taEingangsTypen : taAusgangsTypen).contains(k.typ) ? k.typ : null,
                  items: [for (final t in (k.eingang ? taEingangsTypen : taAusgangsTypen)) DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => kanalAendern(k, TaKanal(nr: k.nr, regler: k.regler, eingang: k.eingang, typ: v ?? k.typ, name: k.name, objekt: k.objekt, kabelM: k.kabelM)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SpeicherFeld(
                  key: ValueKey('tkn-${g.id}-${k.kurz}-${k.name}'),
                  initialValue: k.name,
                  decoration: const InputDecoration(hintText: 'z. B. Vorlauf HK1, Außentemperatur, Pumpe HK1', isDense: true),
                  onFieldSubmitted: (t) => kanalAendern(k, TaKanal(nr: k.nr, regler: k.regler, eingang: k.eingang, typ: k.typ, name: t.trim(), objekt: k.objekt, kabelM: k.kabelM)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 170,
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: objekte.containsKey(k.objekt) ? k.objekt : null,
                  hint: const Text('Objekt …'),
                  items: [const DropdownMenuItem(value: null, child: Text('–')), for (final o in punktObjekte) DropdownMenuItem(value: o.id as String, child: Text('${o.kennung}', overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => kanalAendern(k, TaKanal(nr: k.nr, regler: k.regler, eingang: k.eingang, typ: k.typ, name: k.name, objekt: v, kabelM: k.kabelM)),
                ),
              ),
              SizedBox(width: 90, child: Text(live[k.kurz] ?? '', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF2F9E44), fontWeight: FontWeight.w600))),
              IconButton(
                onPressed: () => _speichern(TaBelegung(b.geraete, [for (final x in b.kanaele) if (!identical(x, k)) x], cmi: b.cmi)),
                icon: const Icon(Icons.close, size: 16),
              ),
            ]),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              onPressed: () {
                final belegt = {for (final k in kan.where((k) => k.eingang)) k.nr};
                var n = 1;
                while (belegt.contains(n)) {
                  n++;
                }
                _speichern(TaBelegung(b.geraete, [...b.kanaele, TaKanal(nr: n, regler: g.id, eingang: true, typ: 'PT1000')], cmi: b.cmi));
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Eingang'),
            ),
            TextButton.icon(
              onPressed: () {
                final belegt = {for (final k in kan.where((k) => !k.eingang)) k.nr};
                var n = 1;
                while (belegt.contains(n)) {
                  n++;
                }
                _speichern(TaBelegung(b.geraete, [...b.kanaele, TaKanal(nr: n, regler: g.id, eingang: false, typ: 'Pumpe (Relais)')], cmi: b.cmi));
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ausgang'),
            ),
            if (kap != null)
              Text('belegt: ${kan.where((k) => k.eingang).length}/${kap.eingaenge} Eingänge, ${kan.where((k) => !k.eingang).length}/${kap.ausgaenge} Ausgänge',
                  style: const TextStyle(fontSize: 12, color: BsFarben.textLeise)),
          ]),
        ]),
      ),
    );
  }
}
