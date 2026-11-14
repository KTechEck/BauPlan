import '../data/models.dart';

/// Wartungsplan (Lastenheft 7, Wartung): je eingebautem Gerät mit
/// Wartungsintervall (Bibliothek, Feld `wartung` in Monaten) eine
/// wiederkehrende Aufgabe. Marker in der Beschreibung verhindert Doppelte.
typedef WartungsPosten = ({Objekt objekt, String geraet, int monate});

String wartungsMarker(String objektId) => '[wartung:$objektId]';

/// Geräte mit Wartungsintervall. [geraet] liefert Name und Daten des
/// zugeordneten Bibliothekselements (oder null).
List<WartungsPosten> wartungsPosten(Iterable<Objekt> objekte, ({String name, Map<String, dynamic> daten})? Function(String? id) geraet) {
  final aus = <WartungsPosten>[];
  for (final o in objekte) {
    final g = geraet(o.eigenschaften['bauelement'] as String?);
    if (g == null) continue;
    final v = g.daten['wartung'];
    final m = v is num ? v.round() : int.tryParse('$v');
    if (m == null || m <= 0) continue;
    aus.add((objekt: o, geraet: g.name, monate: m));
  }
  aus.sort((a, b) => a.objekt.kennung.compareTo(b.objekt.kennung));
  return aus;
}
