/// Benannte Einkäufe („Bauhaus Samstag“): Positionen aus der Planung
/// („Noch zu beschaffen“) oder von Hand, abhakbar am PC und auf dem iPhone,
/// danach mit Kassenzettel verknüpfbar. Gespeichert in der Projekteinstellung
/// `einkaufslisten`.
///
/// Schlüssel einer Position: `e:<Element>` (Besorgungsliste), `l:<Leitung>`
/// (Kabel-/Rohrliste), `k:<Kostenposition>`, `m:<id>` (von Hand).
library;

import 'dart:math' as math;

class ListenPosition {
  ListenPosition({required this.schluessel, required this.text, this.menge = 1, this.einheit = 'Stk', this.herkunft = '', this.abgehakt = false, this.haendler = ''});
  final String schluessel;
  String text;
  double menge;
  String einheit, herkunft, haendler;
  bool abgehakt;

  bool get manuell => schluessel.startsWith('m:');

  Map<String, dynamic> toJson() => {
        'key': schluessel,
        'text': text,
        'menge': menge,
        'einheit': einheit,
        if (herkunft.isNotEmpty) 'herkunft': herkunft,
        if (haendler.isNotEmpty) 'haendler': haendler,
        if (abgehakt) 'ok': true,
      };

  static ListenPosition ausJson(Map<String, dynamic> m) => ListenPosition(
        schluessel: '${m['key']}',
        text: m['text'] as String? ?? '',
        menge: (m['menge'] as num?)?.toDouble() ?? 1,
        einheit: m['einheit'] as String? ?? 'Stk',
        herkunft: m['herkunft'] as String? ?? '',
        haendler: m['haendler'] as String? ?? '',
        abgehakt: m['ok'] == true,
      );
}

class Einkaufsliste {
  Einkaufsliste({required this.id, required this.name, required this.erstellt, List<ListenPosition>? positionen, this.erledigt = false, this.einkaufId, this.beleg})
      : positionen = positionen ?? [];
  final String id;
  String name;
  final DateTime erstellt;
  final List<ListenPosition> positionen;
  bool erledigt;
  String? einkaufId; // verknüpfter Einkauf (Kassenzettel erfasst)
  String? beleg; // Datei des Kassenzettels im Projektordner

  int get offen => positionen.where((p) => !p.abgehakt).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'erstellt': erstellt.toIso8601String(),
        'positionen': [for (final p in positionen) p.toJson()],
        if (erledigt) 'erledigt': true,
        if (einkaufId != null) 'einkauf': einkaufId,
        if (beleg != null) 'beleg': beleg,
      };

  static Einkaufsliste ausJson(Map<String, dynamic> m) => Einkaufsliste(
        id: '${m['id']}',
        name: m['name'] as String? ?? 'Einkauf',
        erstellt: DateTime.tryParse(m['erstellt'] as String? ?? '') ?? DateTime.now(),
        positionen: [for (final p in (m['positionen'] as List? ?? const [])) ListenPosition.ausJson(Map<String, dynamic>.from(p as Map))],
        erledigt: m['erledigt'] == true,
        einkaufId: m['einkauf'] as String?,
        beleg: m['beleg'] as String?,
      );
}

/// Zugriff auf die Projekteinstellungen (lesen/schreiben), damit der Kern
/// ohne Datenbank testbar bleibt.
typedef EinstellungLesen = Object? Function(String key);
typedef EinstellungSchreiben = void Function(String key, Object? wert);

List<Einkaufsliste> listenLesen(EinstellungLesen lesen) => [
      for (final m in (lesen('einkaufslisten') as List? ?? const []))
        if (m is Map) Einkaufsliste.ausJson(Map<String, dynamic>.from(m)),
    ];

void listenSchreiben(EinstellungSchreiben schreiben, List<Einkaufsliste> l) => schreiben('einkaufslisten', [for (final x in l) x.toJson()]);

String neueListenId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 20).toRadixString(36)}';

/// In welcher offenen Liste eine Position steht (Schlüssel → Listenname).
Map<String, String> zuordnung(List<Einkaufsliste> l) => {
      for (final x in l)
        if (!x.erledigt)
          for (final p in x.positionen) p.schluessel: x.name,
    };

/// Positionen in eine Liste legen (aus anderen offenen Listen herausnehmen).
void inListeLegen(List<Einkaufsliste> l, String listeId, List<ListenPosition> neu) {
  final keys = {for (final p in neu) p.schluessel};
  for (final x in l) {
    if (x.erledigt || x.id == listeId) continue;
    x.positionen.removeWhere((p) => keys.contains(p.schluessel));
  }
  final ziel = l.firstWhere((x) => x.id == listeId);
  for (final p in neu) {
    final da = ziel.positionen.where((q) => q.schluessel == p.schluessel).firstOrNull;
    if (da == null) {
      ziel.positionen.add(p);
    } else {
      da.menge = p.menge;
    }
  }
}

/// App-ID (Planstand-Einkauf) zu Listenschlüssel und zurück.
String schluesselAusAppId(String id) => id.startsWith('b-')
    ? 'e:${id.substring(2)}'
    : id.startsWith('l-')
        ? 'l:${id.substring(2)}'
        : id.startsWith('m-')
            ? 'm:${id.substring(2)}'
            : 'k:$id';

String appIdAusSchluessel(String k) => switch (k.substring(0, 2)) {
      'e:' => 'b-${k.substring(2)}',
      'l:' => 'l-${k.substring(2)}',
      'm:' => 'm-${k.substring(2)}',
      _ => k.substring(2),
    };

/// Abhaken aus der App übernehmen: Position in allen offenen Listen setzen.
bool listenAbhaken(List<Einkaufsliste> l, String schluessel, bool ok) {
  var gefunden = false;
  for (final x in l) {
    if (x.erledigt) continue;
    for (final p in x.positionen) {
      if (p.schluessel == schluessel) {
        p.abgehakt = ok;
        gefunden = true;
      }
    }
  }
  return gefunden;
}

/// Einkaufszettel als HTML (fürs Handy, druckbar).
String einkaufszettelHtml(Einkaufsliste l) {
  String z(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
  String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  final b = StringBuffer()
    ..writeln('<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>${esc(l.name)}</title><style>body{font-family:system-ui;margin:16px;background:#f7f5f0}label{display:flex;gap:10px;background:#fff;'
        'border-radius:8px;padding:10px;margin:6px 0}input{width:22px;height:22px}.m{margin-left:auto;font-weight:600}small{color:#777}</style></head><body>')
    ..writeln('<h1>${esc(l.name)}</h1><div>${l.positionen.length} Positionen</div>');
  final gruppen = <String, List<ListenPosition>>{};
  for (final p in l.positionen) {
    gruppen.putIfAbsent(p.haendler.isEmpty ? 'ohne Händler' : p.haendler, () => []).add(p);
  }
  for (final g in gruppen.entries) {
    b.writeln('<h2>${esc(g.key)}</h2>');
    for (final p in g.value) {
      b.writeln('<label><input type="checkbox"${p.abgehakt ? ' checked' : ''}><span>${esc(p.text)}${p.herkunft.isEmpty ? '' : '<br><small>${esc(p.herkunft)}</small>'}</span><span class="m">${z(p.menge)} ${esc(p.einheit)}</span></label>');
    }
  }
  b.writeln('</body></html>');
  return b.toString();
}
