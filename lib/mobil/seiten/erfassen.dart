import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../foto_markieren.dart';
import '../kontext.dart';
import '../ordner.dart';
import '../planstand.dart';
import 'plan.dart';

/// Erfassen in höchstens drei Schritten: Raum wählen, aufnehmen, zuordnen.
class ErfassenSeite extends StatefulWidget {
  const ErfassenSeite({super.key, required this.k, this.zumAufmass});
  final MobilKontext k;

  /// Wechselt zum Aufmaß des gewählten Raums.
  final VoidCallback? zumAufmass;

  @override
  State<ErfassenSeite> createState() => _ErfassenSeiteState();
}

Future<List<int>?> fotoAufnehmen(MobilKontext k) async {
  final e = k.einstellungen;
  if (k.kamera != null) return k.kamera!(e.fotoQualitaet);
  try {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: e.fotoQualitaet, maxWidth: 2400);
    return x == null ? null : await x.readAsBytes();
  } catch (_) {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: e.fotoQualitaet, maxWidth: 2400);
    return x == null ? null : await x.readAsBytes();
  }
}

class _ErfassenSeiteState extends State<ErfassenSeite> {
  MobilKontext get k => widget.k;
  MobilEinstellungen get _e => k.einstellungen;
  Map<String, dynamic>? get _geschoss => k.geschoss;
  List<Map<String, dynamic>> get _raeume => Planstand.liste(_geschoss?['raeume']);
  Map<String, dynamic>? get _raum => _raeume.where((r) => r['id'] == _e.raum).firstOrNull;

  List<Map<String, dynamic>> _objekteImRaum({bool alleGewerke = false}) {
    final g = _geschoss;
    if (g == null) return const [];
    final r = _raum;
    final umriss = r == null ? const <Offset>[] : punkte(r['umriss']);
    return [
      for (final o in Planstand.liste(g['objekte']))
        if (o['geometrie'] != 'flaeche' &&
            (alleGewerke || _e.gewerk == null || o['gewerk'] == _e.gewerk) &&
            (r == null || o['raum'] == r['id'] || (umriss.length >= 3 && punkte(o['punkte']).any((q) => imPolygon(q, umriss)))))
          o
    ];
  }

  Map<String, dynamic> _basis() => {
        'geschoss': _geschoss?['id'],
        if (_raum != null) 'raum': _raum!['id'],
        if (_e.gewerk != null) 'gewerk': _e.gewerk,
      };

  @override
  Widget build(BuildContext context) {
    final g = _geschoss;
    final gewerke = k.plan.gewerke;
    final breit = MediaQuery.sizeOf(context).width > 700;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('g-${g?['id']}'),
            initialValue: g?['id'] as String?,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Geschoss'),
            items: [for (final x in k.plan.geschosse) DropdownMenuItem(value: x['id'] as String, child: Text('${x['name']}'))],
            onChanged: (v) => setState(() {
              _e.geschoss = v;
              _e.raum = null;
              _e.speichern();
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey('gw-${_e.gewerk}'),
            initialValue: gewerke.containsKey(_e.gewerk) ? _e.gewerk : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Gewerk'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('alle')),
              for (final e in gewerke.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _e.gewerk = v;
              _e.speichern();
            }),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Text('Raum', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final r in _raeume)
          ChoiceChip(
            label: Text('${r['name']}'),
            selected: r['id'] == _e.raum,
            onSelected: (v) => setState(() {
              _e.raum = v ? r['id'] as String : null;
              _e.speichern();
            }),
          ),
        if (_raeume.isEmpty) const Text('Keine Räume im Planstand.', style: TextStyle(color: BsFarben.textLeise)),
      ]),
      const SizedBox(height: 20),
      GridView.count(
        crossAxisCount: breit ? 6 : 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          _kachel(Icons.photo_camera_outlined, 'Foto', _fotoErfassen),
          _kachel(Icons.edit_note, 'Notiz', () => _formular('notiz')),
          _kachel(Icons.speed, 'Messwert', () => _formular('messwert')),
          _kachel(Icons.inventory_2_outlined, 'Material', () => _formular('material')),
          _kachel(Icons.task_alt, 'Status', _statusErfassen),
          _kachel(Icons.straighten, 'Aufmaß', () {
            final r = _raum;
            if (r == null || g == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erst den Raum wählen.')));
              return;
            }
            raumBlatt(context, k, g, r).then((_) => setState(() {}));
          }),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        _raum == null ? 'Tipp: erst den Raum wählen – dann ist alles gleich richtig zugeordnet.' : 'Erfassungen gehen an: ${_raum!['name']}${_e.gewerk == null ? '' : ' · ${gewerke[_e.gewerk]?.name ?? _e.gewerk}'}',
        style: const TextStyle(color: BsFarben.textLeise),
      ),
      if (_raum != null) ...[
        const SizedBox(height: 16),
        Text('Im Raum geplant', style: Theme.of(context).textTheme.labelLarge),
        for (final o in _objekteImRaum().take(12))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 12, backgroundColor: gewerke[o['gewerk']]?.farbe ?? Colors.grey, child: Text('${o['typ']}', style: const TextStyle(fontSize: 8, color: Colors.white))),
            title: Text('${o['kennung']} · ${o['name']}'),
            subtitle: Text([
              k.plan.status.where((s) => s.name == o['status']).firstOrNull?.label ?? '${o['status']}',
              if (o['h'] != null) 'Höhe ${mmCm(o['h'] as num)}',
              if (o['laenge'] != null) mmM(o['laenge'] as num),
            ].join(' · ')),
          ),
      ],
    ]);
  }

  Widget _kachel(IconData icon, String text, VoidCallback tippen) => Material(
        color: BsFarben.akzentHell,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: tippen,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 34, color: BsFarben.akzentDunkel),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Future<void> _fotoErfassen() async {
    final bytes = await fotoAufnehmen(k);
    if (bytes == null || !mounted || _geschoss == null) return;
    final ergebnis = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => ZuordnenSeite(titel: 'Foto zuordnen', k: k, geschoss: _geschoss!, objekte: _objekteImRaum(), foto: bytes),
    ));
    if (ergebnis == null) return;
    final foto = ergebnis.remove('_foto') as List<int>? ?? bytes;
    await k.erfasst({..._basis(), 'art': 'foto', ...ergebnis}, foto: foto);
  }

  Future<void> _formular(String art) async {
    if (_geschoss == null) return;
    final ergebnis = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => ZuordnenSeite(
        titel: switch (art) { 'messwert' => 'Messwert', 'material' => 'Material', _ => 'Notiz' },
        k: k,
        geschoss: _geschoss!,
        objekte: _objekteImRaum(),
        art: art,
      ),
    ));
    if (ergebnis == null) return;
    final foto = ergebnis.remove('_foto') as List<int>?;
    await k.erfasst({..._basis(), 'art': art, ...ergebnis}, foto: foto);
  }

  Future<void> _statusErfassen() async {
    final objekte = _objekteImRaum();
    if (objekte.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('In diesem Raum gibt es keine Objekte.')));
      return;
    }
    final ergebnis = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => StatusSeite(plan: k.plan, objekte: objekte)));
    if (ergebnis == null || !mounted) return;
    await statusSenden(context, k, ergebnis, _basis());
  }
}

/// Status senden; „verdeckt“ braucht ein Foto als Nachweis (Lastenheft).
Future<void> statusSenden(BuildContext context, MobilKontext k, Map<String, dynamic> ergebnis, Map<String, dynamic> basis) async {
  List<int>? bytes;
  if (ergebnis['status'] == 'verdeckt') {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Foto vor dem Verdecken'),
        content: const Text('Bevor „verdeckt“ gesetzt wird, braucht es ein Foto als Nachweis, wie es unter Putz bzw. Estrich aussieht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Foto aufnehmen')),
        ],
      ),
    );
    if (ok != true) return;
    bytes = await fotoAufnehmen(k);
    if (bytes == null) return;
  }
  await k.erfasst({...basis, 'art': 'status', ...ergebnis}, foto: bytes);
}

/// Zuordnen: Objekt, Position im Grundriss, Text bzw. Wert; Foto (auch zum
/// Messwert) mit Markierungen – der Messwert lässt sich im Foto einzeichnen.
class ZuordnenSeite extends StatefulWidget {
  const ZuordnenSeite({super.key, required this.titel, required this.k, required this.geschoss, required this.objekte, this.foto, this.art = 'foto'});
  final String titel;
  final MobilKontext k;
  final Map<String, dynamic> geschoss;
  final List<Map<String, dynamic>> objekte;
  final List<int>? foto;
  final String art;

  @override
  State<ZuordnenSeite> createState() => _ZuordnenSeiteState();
}

class _ZuordnenSeiteState extends State<ZuordnenSeite> {
  String? _objekt;
  Offset? _position;
  late List<int>? _foto = widget.foto;
  List<Map<String, dynamic>> _marken = [];
  final _text = TextEditingController(), _wert = TextEditingController();
  String _einheit = 'mm';

  static const _einheitenMess = ['mm', 'cm', 'm', 'm²', '°C', 'bar', 'V', 'Ω', 'MΩ', 'A', '%', 'l/h'];
  static const _einheitenMaterial = ['Stk', 'm', 'm²', 'kg', 'l', 'Pkg', 'Rolle', 'Sack'];

  @override
  void initState() {
    super.initState();
    if (widget.art == 'material') _einheit = 'Stk';
  }

  Future<void> _markieren() async {
    var f = _foto;
    f ??= await fotoAufnehmen(widget.k);
    if (f == null || !mounted) return;
    final wert = _wert.text.trim();
    final m = await Navigator.of(context).push<List<Map<String, dynamic>>>(MaterialPageRoute(
      builder: (_) => FotoMarkierenSeite(foto: f!, marken: _marken, massText: wert.isEmpty ? null : '$wert $_einheit'),
    ));
    setState(() {
      _foto = f;
      if (m != null) _marken = m;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mitWert = widget.art == 'messwert' || widget.art == 'material';
    final materialVorschlaege = widget.art == 'material'
        ? {for (final e in widget.k.plan.einkauf) '${e['text']}'}.take(30).toList()
        : const <String>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.titel), actions: [
        TextButton(
          onPressed: () {
            final wert = num.tryParse(_wert.text.replaceAll(',', '.'));
            if (mitWert && wert == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte einen Wert eingeben.')));
              return;
            }
            if (widget.art == 'notiz' && _text.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte eine Notiz eingeben.')));
              return;
            }
            Navigator.pop(context, {
              if (_objekt != null) 'objekt': _objekt,
              if (_position != null) 'x': _position!.dx.round(),
              if (_position != null) 'y': _position!.dy.round(),
              if (_text.text.trim().isNotEmpty) 'text': _text.text.trim(),
              if (mitWert) 'wert': wert,
              if (mitWert) 'einheit': _einheit,
              if (_marken.isNotEmpty) 'markierungen': _marken,
              if (_foto != null && widget.foto == null) '_foto': _foto,
            });
          },
          child: const Text('Speichern'),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_foto != null)
          GestureDetector(
            onTap: _markieren,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(children: [
                Image.memory(Uint8List.fromList(_foto!), height: 220, width: double.infinity, fit: BoxFit.cover, errorBuilder: (c, e, s) => const SizedBox(height: 120, child: Center(child: Icon(Icons.image_outlined)))),
                if (_marken.isNotEmpty)
                  Positioned(right: 8, top: 8, child: Chip(avatar: const Icon(Icons.draw_outlined, size: 16), label: Text('${_marken.length} Markierung(en)'))),
              ]),
            ),
          ),
        if (mitWert) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _wert,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: widget.art == 'material' ? 'Menge' : 'Wert'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                initialValue: _einheit,
                decoration: const InputDecoration(labelText: 'Einheit'),
                items: [for (final x in widget.art == 'material' ? _einheitenMaterial : _einheitenMess) DropdownMenuItem(value: x, child: Text(x))],
                onChanged: (v) => _einheit = v ?? _einheit,
              ),
            ),
          ]),
        ],
        const SizedBox(height: 8),
        if (widget.art != 'notiz')
          OutlinedButton.icon(
            onPressed: _markieren,
            icon: const Icon(Icons.draw_outlined),
            label: Text(_foto == null
                ? (widget.art == 'messwert' ? 'Foto aufnehmen und Messwert im Foto markieren' : 'Foto dazu und markieren')
                : (widget.art == 'messwert' ? 'Messwert im Foto markieren' : 'Im Foto markieren (Maß, Pfeil, Kreis, Text)')),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: widget.art == 'notiz',
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: switch (widget.art) { 'material' => 'Was (z. B. NYM-J 3×1,5)', 'messwert' => 'Was wurde gemessen?', _ => 'Notiz' },
            helperText: 'Diktieren: Mikrofon auf der Tastatur',
          ),
        ),
        if (materialVorschlaege.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in materialVorschlaege) ActionChip(label: Text(t, overflow: TextOverflow.ellipsis), onPressed: () => setState(() => _text.text = t)),
          ]),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _objekt,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Zu Objekt (optional)'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('– kein bestimmtes –')),
            for (final o in widget.objekte) DropdownMenuItem<String?>(value: o['id'] as String, child: Text('${o['kennung']} · ${o['name']}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _objekt = v),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final q = await Navigator.of(context).push<Offset>(MaterialPageRoute(
              builder: (c) => Scaffold(
                appBar: AppBar(title: const Text('Position antippen')),
                body: GrundrissAnsicht(plan: widget.k.plan, geschoss: widget.geschoss, k: widget.k, waehlen: (p) => Navigator.pop(c, p)),
              ),
            ));
            if (q != null) setState(() => _position = q);
          },
          icon: const Icon(Icons.place_outlined),
          label: Text(_position == null ? 'Position im Grundriss setzen (optional)' : 'Position gesetzt ✓ – ändern'),
        ),
      ]),
    );
  }
}

class StatusSeite extends StatefulWidget {
  const StatusSeite({super.key, required this.plan, required this.objekte, this.vorwahl});
  final Planstand plan;
  final List<Map<String, dynamic>> objekte;
  final String? vorwahl;

  @override
  State<StatusSeite> createState() => _StatusSeiteState();
}

class _StatusSeiteState extends State<StatusSeite> {
  late String? _objekt = widget.vorwahl;

  @override
  Widget build(BuildContext context) {
    final o = widget.objekte.where((x) => x['id'] == _objekt).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Status ändern')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('1. Objekt', style: Theme.of(context).textTheme.titleSmall),
        for (final x in widget.objekte)
          ListTile(
            selected: _objekt == x['id'],
            leading: Icon(_objekt == x['id'] ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            onTap: () => setState(() => _objekt = x['id'] as String),
            title: Text('${x['kennung']} · ${x['name']}'),
            subtitle: Text('jetzt: ${widget.plan.status.where((s) => s.name == x['status']).firstOrNull?.label ?? x['status']}'),
          ),
        if (o != null) ...[
          const Divider(),
          Text('2. Neuer Status', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in widget.plan.status)
              FilledButton.tonal(
                onPressed: s.name == o['status'] ? null : () => Navigator.pop(context, {'objekt': o['id'], 'status': s.name}),
                child: Text(s.label),
              ),
          ]),
        ],
      ]),
    );
  }
}
