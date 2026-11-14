import '../data/models.dart';
import '../data/project_store.dart';

/// Technikbereiche: ein ganzer Raum (Heizraum, HWR …) oder eine Technikwand
/// in einem anderen Raum (z. B. Büro mit Netzwerk-, Smart-Home- und
/// 230-V-Schrank). Räume mit Technik im Namen werden automatisch erkannt;
/// das lässt sich je Raum lösen (Einstellung `technikbereich_aus`).
class Technikbereich {
  Technikbereich({required this.id, required this.name, required this.raumId, this.wandId, this.schraenke = const [], this.automatisch = false});
  final String id;
  final String name;
  final String raumId;
  final String? wandId; // gesetzt = Technikwand
  final List<String> schraenke;
  final bool automatisch;

  bool get istWand => wandId != null;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'raum': raumId, if (wandId != null) 'wand': wandId, if (schraenke.isNotEmpty) 'schraenke': schraenke};

  static Technikbereich ausJson(Map m) => Technikbereich(
        id: '${m['id']}',
        name: '${m['name'] ?? 'Technikbereich'}',
        raumId: '${m['raum']}',
        wandId: m['wand'] as String?,
        schraenke: [for (final s in (m['schraenke'] as List? ?? const [])) '$s'],
      );
}

/// Erkennt Technikräume am Namen.
bool technikraumName(String name) => RegExp(r'technik|heiz|hwr|hauswirtschaft|hausanschluss|haustechnik', caseSensitive: false).hasMatch(name);

/// Alle Technikbereiche: eigene (Einstellung `technikbereiche`) und
/// automatisch erkannte Räume, die nicht gelöst wurden.
List<Technikbereich> technikbereiche(ProjectStore store) {
  final eigene = [for (final m in (store.einstellung<List>('technikbereiche') ?? const [])) if (m is Map) Technikbereich.ausJson(m)];
  final aus = {for (final e in (store.einstellung<List>('technikbereich_aus') ?? const [])) '$e'};
  final auto = <Technikbereich>[];
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      for (final r in store.raeume(g.id)) {
        if (r.umriss == null || !technikraumName(r.name) || aus.contains(r.id)) continue;
        if (eigene.any((b) => b.raumId == r.id && !b.istWand)) continue;
        auto.add(Technikbereich(id: 'auto-${r.id}', name: r.name, raumId: r.id, automatisch: true));
      }
    }
  }
  return [...auto, ...eigene];
}

void technikbereicheSpeichern(ProjectStore store, List<Technikbereich> eigene) =>
    store.einstellungSetzen('technikbereiche', [for (final b in eigene.where((b) => !b.automatisch)) b.toJson()]);

/// Automatische Erkennung für einen Raum lösen bzw. wieder zulassen.
void technikbereichAutoLoesen(ProjectStore store, String raumId, bool loesen) {
  final l = {for (final e in (store.einstellung<List>('technikbereich_aus') ?? const [])) '$e'};
  loesen ? l.add(raumId) : l.remove(raumId);
  store.einstellungSetzen('technikbereich_aus', l.toList());
}

/// Schränke, die in einem Bereich stehen: zugeordnet oder deren Verteiler-Objekt im Raum liegt.
List<String> schraenkeImBereich(ProjectStore store, Technikbereich b) {
  final ids = {...b.schraenke};
  final objekte = {for (final o in store.alleObjekte()) o.id: o};
  for (final s in store.schraenke()) {
    final o = objekte[s.objektId];
    if (o != null && o.raumId == b.raumId) ids.add(s.id);
  }
  return ids.toList();
}

/// Vorlagen für Technikbereiche (Gerätenamen aus `technikVorlagen`).
const bereichVorlagen = <String, List<String>>{
  'Technikwand Büro': ['Netzwerkschrank 12 HE', 'Zählerschrank'],
};

/// Raum eines Bereichs.
Raum? bereichRaum(ProjectStore store, Technikbereich b) {
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      for (final r in store.raeume(g.id)) {
        if (r.id == b.raumId) return r;
      }
    }
  }
  return null;
}
