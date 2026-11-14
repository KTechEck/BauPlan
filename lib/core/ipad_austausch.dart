import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'zip_lesen.dart';

/// Projekt zwischen PC und iPad (volle BauSpur auf dem iPad): Das iPad holt
/// den ganzen Projektordner als ZIP vom PC-Dienst, arbeitet darauf und schickt
/// die Projektdatenbank zurück. Der PC legt sie ab; übernommen wird erst, wenn
/// der Eigentümer am PC „Stand vom iPad übernehmen“ wählt (vorher Sicherung).

/// ZIP in einen (neuen oder leeren) Ordner entpacken. Pfade mit „..“ werden übersprungen.
int projektEntpacken(Uint8List zip, String ziel) {
  final a = ZipArchiv(zip);
  var n = 0;
  for (final name in a.namen) {
    if (name.endsWith('/') || name.contains('..')) continue;
    final rel = name.startsWith('./') ? name.substring(2) : name;
    if (rel.isEmpty || rel == 'projekt.lock') continue;
    final b = a.lesen(name);
    if (b == null) continue;
    final f = File(p.join(ziel, rel))..parent.createSync(recursive: true);
    f.writeAsBytesSync(b);
    n++;
  }
  return n;
}

/// Ablage des vom iPad geschickten Stands im Austauschordner.
String ipadStandPfad(String austauschOrdner) => p.join(austauschOrdner, 'ipad', 'projekt.bauspur');

/// Liegt ein Stand vom iPad bereit? (Datum der Datei)
DateTime? ipadStandVom(String austauschOrdner) {
  final f = File(ipadStandPfad(austauschOrdner));
  return f.existsSync() ? f.lastModifiedSync() : null;
}
