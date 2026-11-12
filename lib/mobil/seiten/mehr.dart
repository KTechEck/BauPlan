import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../kontext.dart';
import '../planstand.dart';
import 'erfassen.dart';
import 'aufmass.dart';
import 'plan.dart';
import 'wandansicht.dart';

/// Objekte auf der Baustelle nachschlagen: suchen, Gewerk filtern, Details
/// mit Höhe, Gerät und Anschlüssen, Status ändern, Foto dazu.
class ObjekteSeite extends StatefulWidget {
  const ObjekteSeite({super.key, required this.k});
  final MobilKontext k;

  @override
  State<ObjekteSeite> createState() => _ObjekteSeiteState();
}

class _ObjekteSeiteState extends State<ObjekteSeite> {
  String _suche = '';
  String? _gewerk;

  MobilKontext get k => widget.k;

  @override
  Widget build(BuildContext context) {
    final g = k.geschoss;
    final gewerke = k.plan.gewerke;
    final liste = [
      for (final o in Planstand.liste(g?['objekte']))
        if ((_gewerk == null || o['gewerk'] == _gewerk) &&
            (_suche.isEmpty || '${o['kennung']} ${o['name']} ${k.plan.raumName(o['raum'] as String?)} ${o['produkt'] ?? ''}'.toLowerCase().contains(_suche)))
          o
    ]..sort((a, b) => '${a['kennung']}'.compareTo('${b['kennung']}'));
    return Scaffold(
      appBar: AppBar(title: Text('Objekte ${g?['kuerzel'] ?? ''}')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Kennung, Typ, Raum …', isDense: true),
            onChanged: (v) => setState(() => _suche = v.trim().toLowerCase()),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(6), children: [
            ChoiceChip(label: const Text('alle'), selected: _gewerk == null, onSelected: (_) => setState(() => _gewerk = null)),
            for (final e in gewerke.entries)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: e.value.farbe, radius: 6),
                  label: Text(e.value.name),
                  selected: _gewerk == e.key,
                  onSelected: (_) => setState(() => _gewerk = e.key),
                ),
              ),
          ]),
        ),
        Expanded(
          child: ListView(children: [
            for (final o in liste)
              ListTile(
                leading: CircleAvatar(radius: 14, backgroundColor: gewerke[o['gewerk']]?.farbe ?? Colors.grey, child: Text('${o['typ']}', style: const TextStyle(fontSize: 9, color: Colors.white))),
                title: Text('${o['kennung']} · ${o['name']}'),
                subtitle: Text([
                  k.plan.raumName(o['raum'] as String?),
                  k.plan.status.where((s) => s.name == o['status']).firstOrNull?.label ?? '${o['status']}',
                  if (o['h'] != null) 'h ${mmCm(o['h'] as num)}',
                ].where((x) => x.isNotEmpty).join(' · ')),
                onTap: () => _details(context, o),
              ),
            if (liste.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Keine Objekte gefunden.', textAlign: TextAlign.center)),
          ]),
        ),
      ]),
    );
  }

  void _details(BuildContext context, Map<String, dynamic> o) {
    final geraet = o['geraet'] as Map?;
    final daten = Map<String, dynamic>.from(geraet?['daten'] as Map? ?? const {});
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
          Text('${o['kennung']} · ${o['name']}', style: Theme.of(c).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final (l, v) in [
            ('Raum', k.plan.raumName(o['raum'] as String?)),
            ('Status', k.plan.status.where((s) => s.name == o['status']).firstOrNull?.label),
            ('Höhe', o['h'] == null ? null : '${mmCm(o['h'] as num)} über FFB'),
            ('Länge', o['laenge'] == null ? null : mmM(o['laenge'] as num)),
            ('Lage', o['lage']),
            ('Kabel', o['kabel']),
            ('Stromkreis', o['stromkreis']),
            ('Produkt', o['produkt']),
            ('Gerät', geraet?['name']),
            ('Art.-Nr.', geraet?['artikel']),
            ('Maße', daten['breite'] == null ? null : '${daten['breite']} × ${daten['hoehe'] ?? '?'} × ${daten['tiefe'] ?? '?'} mm'),
          ])
            if (v != null && '$v'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [SizedBox(width: 100, child: Text(l, style: const TextStyle(color: BsFarben.textLeise))), Expanded(child: Text('$v'))]),
              ),
          if ((daten['anschluesse'] as List?)?.isNotEmpty == true) ...[
            const Divider(),
            const Text('Anschlüsse', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final a in daten['anschluesse'] as List)
              if (a is Map)
                Text('• ${a['name'] ?? a['art']} (${a['art']}${'${a['groesse'] ?? ''}'.isEmpty ? '' : ', ${a['groesse']}'}) – ${a['seite']}, x ${a['x']} / y ${a['y']} mm'),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                Navigator.pop(c);
                final e = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => StatusSeite(plan: k.plan, objekte: [o], vorwahl: o['id'] as String)));
                if (e != null && context.mounted) await statusSenden(context, k, e, {'geschoss': k.geschoss?['id'], if (o['raum'] != null) 'raum': o['raum']});
              },
              icon: const Icon(Icons.task_alt),
              label: const Text('Status'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                Navigator.pop(c);
                final f = await fotoAufnehmen(k);
                if (f != null) await k.erfasst({'art': 'foto', 'geschoss': k.geschoss?['id'], 'objekt': o['id'], if (o['raum'] != null) 'raum': o['raum']}, foto: f);
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Foto'),
            ),
            if (_wandVon(o) != null)
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(c);
                  final (w, links) = _wandVon(o)!;
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WandansichtSeite(k: k, geschoss: k.geschoss!, wand: w, links: links)));
                },
                icon: const Icon(Icons.view_agenda_outlined),
                label: const Text('Wandansicht'),
              ),
          ]),
        ]),
      ),
    );
  }

  /// Wand, an der ein Punktobjekt sitzt (für die Wandansicht).
  (Map<String, dynamic>, bool)? _wandVon(Map<String, dynamic> o) {
    final g = k.geschoss;
    final p = punkte(o['punkte']);
    if (g == null || p.isEmpty) return null;
    (Map<String, dynamic>, bool)? best;
    var bd = 400.0;
    for (final w in Planstand.liste(g['waende'])) {
      final d = abstandStrecke(p.first, punkt(w['a']), punkt(w['b']));
      if (d < bd) {
        bd = d;
        final s = AppWandSeite(w, true);
        best = (w, s.vor(p.first) > -s.dicke / 2);
      }
    }
    return best;
  }
}

/// Offene Aufgaben vom PC: abhaken, Notiz dazu.
class AufgabenSeite extends StatefulWidget {
  const AufgabenSeite({super.key, required this.k});
  final MobilKontext k;

  @override
  State<AufgabenSeite> createState() => _AufgabenSeiteState();
}

class _AufgabenSeiteState extends State<AufgabenSeite> {
  final Set<String> _erledigt = {};

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    final l = k.plan.aufgaben;
    return Scaffold(
      appBar: AppBar(title: const Text('Aufgaben')),
      body: l.isEmpty
          ? const Center(child: Text('Keine offenen Aufgaben.'))
          : ListView(children: [
              for (final a in l)
                CheckboxListTile(
                  value: _erledigt.contains(a['id']),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('${a['titel']}'),
                  subtitle: Text([
                    if (a['raum'] != null) k.plan.raumName(a['raum'] as String),
                    if (a['faellig'] != null) 'fällig ${DateTime.parse('${a['faellig']}').day}.${DateTime.parse('${a['faellig']}').month}.',
                    if (a['status'] == 'inArbeit') 'in Arbeit',
                    if (a['text'] != null) '${a['text']}',
                  ].join(' · ')),
                  onChanged: (v) async {
                    setState(() => v == true ? _erledigt.add(a['id'] as String) : _erledigt.remove(a['id']));
                    await k.erfasst({'art': 'aufgabe', 'aufgabe': a['id'], 'status': v == true ? 'erledigt' : 'offen', if (a['raum'] != null) 'raum': a['raum'], 'text': '${a['titel']} ${v == true ? 'erledigt' : 'wieder offen'}'});
                  },
                ),
            ]),
    );
  }
}

/// „Mehr“: Nachschlagen (Objekte, Räume, Aufgaben), Abgleich, Einstellungen, Ablauf.
class MehrSeite extends StatelessWidget {
  const MehrSeite({super.key, required this.k, required this.neuZeichnen});
  final MobilKontext k;
  final VoidCallback neuZeichnen;

  @override
  Widget build(BuildContext context) {
    final e = k.einstellungen;
    final plan = k.plan;
    final offeneMasse = e.aufmass.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Nachschlagen', style: Theme.of(context).textTheme.titleMedium),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.search),
        title: const Text('Objekte suchen'),
        subtitle: const Text('Geräte, Leitungen, Höhen, Anschlüsse, Status'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ObjekteSeite(k: k))),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.checklist),
        title: Text('Aufgaben (${plan.aufgaben.length} offen)'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AufgabenSeite(k: k))),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.meeting_room_outlined),
        title: const Text('Räume und Aufmaß'),
        subtitle: Text('${plan.aufmassOffen.length} Maß(e) warten am PC auf Übernahme · $offeneMasse auf diesem Handy gemessen'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Räume')), body: RaeumeListe(k: k)))),
      ),
      const Divider(),
      Text('Abgleich', style: Theme.of(context).textTheme.titleMedium),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.link),
        title: Text('Verbunden mit: ${k.ordnerName ?? '–'}'),
        subtitle: Text('Planstand vom ${plan.erstellt == null ? '–' : _datum(plan.erstellt!)}'),
        trailing: TextButton(onPressed: k.verbindungAendern, child: const Text('Ändern')),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_upload_outlined),
        title: Text('${k.wartend} Erfassung(en) warten auf Übertragung'),
        trailing: TextButton(onPressed: k.abgleichen, child: const Text('Jetzt')),
      ),
      const Divider(),
      Text('Einstellungen', style: Theme.of(context).textTheme.titleMedium),
      TextFormField(
        initialValue: e.benutzer,
        decoration: const InputDecoration(labelText: 'Dein Name (steht an jeder Erfassung)'),
        onChanged: (v) {
          e.benutzer = v.trim();
          e.speichern();
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        initialValue: const [50, 80, 95].contains(e.fotoQualitaet) ? e.fotoQualitaet : 80,
        decoration: const InputDecoration(labelText: 'Fotoqualität'),
        items: const [
          DropdownMenuItem(value: 50, child: Text('klein (schnell übertragen)')),
          DropdownMenuItem(value: 80, child: Text('normal')),
          DropdownMenuItem(value: 95, child: Text('hoch')),
        ],
        onChanged: (v) {
          e.fotoQualitaet = v ?? 80;
          e.speichern();
        },
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: e.aufmass.isEmpty
            ? null
            : () {
                e.aufmass.clear();
                e.speichern();
                neuZeichnen();
              },
        icon: const Icon(Icons.cleaning_services_outlined),
        label: const Text('Gemerkte eigene Maße vergessen (nach Übernahme am PC)'),
      ),
      const Divider(),
      const Text('So läuft das Aufmaß', style: TextStyle(fontWeight: FontWeight.w600)),
      const Text(
        '1. Am PC grob zeichnen.\n2. Auf der Baustelle: Plan › Wand antippen › Messen, oder Erfassen › Aufmaß für einen ganzen Raum.\n'
        '3. Am PC: Grundriss › Lineal-Knopf „Aufmaß“ – Maße prüfen und übernehmen. Danach sind sie hier grün.',
        style: TextStyle(fontSize: 13, height: 1.4),
      ),
    ]);
  }
}

/// Räume des Geschosses mit Fläche, Höhe und Aufmaß-Fortschritt.
class RaeumeListe extends StatefulWidget {
  const RaeumeListe({super.key, required this.k});
  final MobilKontext k;

  @override
  State<RaeumeListe> createState() => _RaeumeListeState();
}

class _RaeumeListeState extends State<RaeumeListe> {
  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    final g = k.geschoss;
    if (g == null) return const Center(child: Text('Kein Geschoss im Planstand.'));
    return ListView(children: [
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(6), children: [
          for (final x in k.plan.geschosse)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${x['name']}'),
                selected: x['id'] == g['id'],
                onSelected: (_) => setState(() {
                  k.einstellungen.geschoss = x['id'] as String;
                  k.einstellungen.speichern();
                }),
              ),
            ),
        ]),
      ),
      for (final r in Planstand.liste(g['raeume']))
        Builder(builder: (context) {
          final seiten = raumSeiten(g, '${r['id']}');
          final n = seiten.where((s) => raumSeiteGemessen(k, s, '${r['id']}')).length;
          return ListTile(
            leading: CircularProgressIndicator(value: seiten.isEmpty ? 0 : n / seiten.length, color: massGemessen, backgroundColor: const Color(0xFFE9ECEF)),
            title: Text('${r['name']}'),
            subtitle: Text('${((r['flaeche'] as num? ?? 0) / 1e6).toStringAsFixed(2).replaceAll('.', ',')} m² · h ${mmCm(raumHoehe(g, r['id'] as String?))} · $n/${seiten.length} Wände gemessen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => raumBlatt(context, k, g, r).then((_) => setState(() {})),
          );
        }),
    ]);
  }
}

String _datum(DateTime d) => '${d.day}.${d.month}.${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
