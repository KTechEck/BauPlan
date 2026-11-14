import 'dart:convert';

/// Fotos Räumen und Objekten zuordnen: offline über die Aufnahmezeit
/// (Foto kurz vor/nach einem schon zugeordneten Foto → gleicher Raum) und
/// optional über die lokale Bild-KI. Alles sind Vorschläge zum Bestätigen.

typedef FotoInfo = ({String id, DateTime zeit, String? raumId});

/// Ein Vorschlag: Raum (und ggf. Objekt) für ein Foto, mit Begründung.
typedef FotoVorschlag = ({String fotoId, String? raumId, String? objektId, String grund});

/// Zeitnachbarn: unzugeordnete Fotos bekommen den Raum des zeitlich nächsten
/// zugeordneten Fotos, wenn es höchstens [fenster] entfernt aufgenommen wurde.
List<FotoVorschlag> zeitVorschlaege(List<FotoInfo> fotos, {Duration fenster = const Duration(minutes: 10)}) {
  final mit = fotos.where((f) => f.raumId != null).toList()..sort((a, b) => a.zeit.compareTo(b.zeit));
  final aus = <FotoVorschlag>[];
  if (mit.isEmpty) return aus;
  for (final f in fotos.where((f) => f.raumId == null)) {
    FotoInfo? best;
    var d = fenster;
    for (final m in mit) {
      final x = (m.zeit.difference(f.zeit)).abs();
      if (x <= d) {
        d = x;
        best = m;
      }
    }
    if (best != null) {
      aus.add((fotoId: f.id, raumId: best.raumId, objektId: null, grund: 'aufgenommen ${d.inMinutes < 1 ? 'kurz' : '${d.inMinutes} min'} ${best.zeit.isAfter(f.zeit) ? 'vor' : 'nach'} einem Foto aus diesem Raum'));
    }
  }
  return aus;
}

/// Frage an die Bild-KI: welcher Raum, welches Objekt?
String kiFotoAnfrage(List<String> raeume, List<String> objekte) => 'Das ist ein Baustellenfoto aus einem Hausumbau. '
    'Welcher Raum ist es und welches Objekt (falls eines klar im Mittelpunkt steht)? '
    'Räume: ${raeume.join(', ')}. Objekte (Kennung: Art): ${objekte.take(60).join('; ')}. '
    'Antworte NUR mit JSON: {"raum": "Name oder null", "objekt": "Kennung oder null", "beschreibung": "kurz, was zu sehen ist"}. Rate nicht, wenn unklar.';

/// Antwort der KI lesen.
({String? raum, String? objekt, String beschreibung})? kiFotoLesen(String antwort) {
  final m = RegExp(r'\{[\s\S]*\}').firstMatch(antwort);
  if (m == null) return null;
  try {
    final j = jsonDecode(m.group(0)!) as Map<String, dynamic>;
    String? s(Object? v) => v == null || '$v'.trim().isEmpty || '$v' == 'null' ? null : '$v'.trim();
    return (raum: s(j['raum']), objekt: s(j['objekt']), beschreibung: s(j['beschreibung']) ?? '');
  } catch (_) {
    return null;
  }
}
