import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/tagebuch_models.dart';
import '../../state/app_state.dart';

String _d(DateTime t) => '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';

/// Objekte, die verdeckt sind, aber kein Foto haben (Pflichtfoto-Übersicht).
Future<void> pflichtfotoUebersicht(BuildContext context, AppState s) async {
  final store = s.store!;
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final raeume = {
    for (final geb in store.gebaeude())
      for (final g in store.geschosse(geb.id))
        for (final r in store.raeume(g.id)) r.id: '${g.kuerzel} ${r.name}',
  };
  final mitFoto = <String>{};
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      for (final f in store.fotos(g.id)) {
        mitFoto.addAll(f.objektIds);
      }
    }
  }
  final fehlt = [
    for (final o in store.alleObjekte())
      if ((o.status == ObjektStatus.verdeckt || o.status == ObjektStatus.geprueft) && !mitFoto.contains(o.id)) o
  ];
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Fotos vor dem Verdecken (${fehlt.length} fehlen)'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: fehlt.isEmpty
            ? const Center(child: Text('Alle geprüften und verdeckten Objekte haben ein Foto.'))
            : ListView(children: [
                const Text('Geprüfte oder verdeckte Objekte ohne zugeordnetes Foto. Foto im Modul Fotos dem Objekt zuordnen oder mit der App aufnehmen.',
                    style: TextStyle(fontSize: 12, color: BsFarben.textLeise)),
                for (final o in fehlt)
                  ListTile(
                    dense: true,
                    leading: Icon(o.status == ObjektStatus.verdeckt ? Icons.visibility_off_outlined : Icons.check, size: 18),
                    title: Text('${o.kennung} · ${typen[o.typId]?.name ?? ''}'),
                    subtitle: Text('${raeume[o.raumId] ?? '–'} · ${o.status.label}'),
                    trailing: TextButton(
                      onPressed: () {
                        s.markiert = {o.id};
                        s.geschossId = o.geschossId;
                        s.modulWaehlen(Modul.installation);
                        Navigator.pop(c);
                      },
                      child: const Text('zeigen'),
                    ),
                  ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
    ),
  );
}

/// Zeitleiste eines Raums: Fotos, Tagebucheinträge und Aufgaben nach Datum.
Future<void> zeitleisteRaum(BuildContext context, AppState s) async {
  final store = s.store!;
  final gid = s.geschossId;
  if (gid == null) return;
  final raeume = store.raeume(gid);
  if (raeume.isEmpty) return;
  var raumId = raeume.first.id;
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      final fotos = [for (final f in store.fotos(gid)) if (f.raumId == raumId) f];
      final tage = [for (final t in store.tagebuch()) if (t.raeume.contains(raumId)) t];
      final aufg = [for (final a in store.aufgaben()) if (a.raumId == raumId) a];
      final eintraege = <(DateTime, Widget)>[
        for (final f in fotos)
          (
            f.aufnahme.toLocal(),
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(File(p.join(store.ordner, f.datei)), width: 72, height: 54, fit: BoxFit.cover, errorBuilder: (c, e, st) => const Icon(Icons.image_outlined)),
              ),
              title: Text('Foto · ${_d(f.aufnahme.toLocal())}'),
              subtitle: Text(f.notiz ?? f.autor),
            ),
          ),
        for (final t in tage) (t.datum, ListTile(leading: const Icon(Icons.menu_book_outlined), title: Text('Tagebuch · ${_d(t.datum)}'), subtitle: Text(t.text))),
        for (final a in aufg)
          (
            a.erledigtAm ?? a.faellig ?? DateTime(2000),
            ListTile(
              leading: Icon(a.status == AufgabenStatus.erledigt ? Icons.check_circle_outline : (a.art == 'mangel' ? Icons.report_problem_outlined : Icons.radio_button_unchecked)),
              title: Text('${aufgabenArten[a.art] ?? 'Aufgabe'}: ${a.titel}'),
              subtitle: Text(a.status.label),
            ),
          ),
      ]..sort((x, y) => y.$1.compareTo(x.$1));
      return AlertDialog(
        title: Row(children: [
          const Text('Zeitleiste '),
          DropdownButton<String>(
            value: raumId,
            items: [for (final r in raeume) DropdownMenuItem(value: r.id, child: Text(r.name))],
            onChanged: (v) => setD(() => raumId = v ?? raumId),
          ),
        ]),
        content: SizedBox(
          width: 640,
          height: 520,
          child: eintraege.isEmpty ? const Center(child: Text('Für diesen Raum gibt es noch nichts.')) : ListView(children: [for (final e in eintraege) e.$2]),
        ),
        actions: [
          if (fotos.length >= 2)
            TextButton.icon(
              onPressed: () => vorherNachher(c, s, fotos),
              icon: const Icon(Icons.compare, size: 18),
              label: const Text('Vorher / Nachher'),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen')),
        ],
      );
    }),
  );
}

/// Vorher/Nachher-Schieber: zwei Fotos übereinander, Trennlinie ziehen.
Future<void> vorherNachher(BuildContext context, AppState s, List<Foto> fotos) async {
  final store = s.store!;
  final sortiert = [...fotos]..sort((a, b) => a.aufnahme.compareTo(b.aufnahme));
  var vorher = sortiert.first, nachher = sortiert.last;
  var anteil = 0.5;
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      Widget bild(Foto f) => Image.file(File(p.join(store.ordner, f.datei)), fit: BoxFit.cover, errorBuilder: (c, e, st) => const Center(child: Icon(Icons.image_outlined)));
      return AlertDialog(
        title: const Text('Vorher / Nachher'),
        content: SizedBox(
          width: 820,
          height: 560,
          child: Column(children: [
            Row(children: [
              const Text('Vorher: '),
              DropdownButton<String>(
                value: vorher.id,
                items: [for (final f in sortiert) DropdownMenuItem(value: f.id, child: Text(_d(f.aufnahme.toLocal())))],
                onChanged: (v) => setD(() => vorher = sortiert.firstWhere((f) => f.id == v)),
              ),
              const SizedBox(width: 20),
              const Text('Nachher: '),
              DropdownButton<String>(
                value: nachher.id,
                items: [for (final f in sortiert) DropdownMenuItem(value: f.id, child: Text(_d(f.aufnahme.toLocal())))],
                onChanged: (v) => setD(() => nachher = sortiert.firstWhere((f) => f.id == v)),
              ),
            ]),
            Expanded(
              child: LayoutBuilder(builder: (c, box) {
                return GestureDetector(
                  onHorizontalDragUpdate: (d) => setD(() => anteil = (anteil + d.delta.dx / box.maxWidth).clamp(0.0, 1.0)),
                  onTapDown: (d) => setD(() => anteil = (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
                  child: Stack(fit: StackFit.expand, children: [
                    bild(nachher),
                    ClipRect(clipper: _Links(anteil), child: bild(vorher)),
                    Positioned(
                      left: box.maxWidth * anteil - 1.5,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 3, color: Colors.white),
                    ),
                    Positioned(left: 8, top: 8, child: Chip(label: Text('vorher ${_d(vorher.aufnahme.toLocal())}'))),
                    Positioned(right: 8, top: 8, child: Chip(label: Text('nachher ${_d(nachher.aufnahme.toLocal())}'))),
                  ]),
                );
              }),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
      );
    }),
  );
}

class _Links extends CustomClipper<Rect> {
  _Links(this.anteil);
  final double anteil;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * anteil, size.height);
  @override
  bool shouldReclip(_Links o) => o.anteil != anteil;
}
