import 'dart:convert';
import 'dart:io';

import 'package:bauspur/core/einkauf.dart';
import 'package:bauspur/core/texterkennung.dart';
import 'package:bauspur/data/austausch.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/ui/bauteile/einkauf_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Texterkennung bereinigt Kassenzettel-Text, Positionen werden gelesen', () {
    final t = texterkennungBereinigen('BAUHAUS Mannheim\n14. 11. 2026\nNYM-J 3x1,5 50m 49,90\n2X Gira E2 Steckdose 17, 80\nAbzweigdose 3,49\nSUMME EUR 71,19');
    expect(t, contains('17,80'));
    expect(t, contains('14.11.2026'));
    final p = kassenzettelLesen(t);
    expect(p.length, 3);
    expect(p.firstWhere((x) => x.text.contains('Gira')).menge, 2);
  });

  test('Kassenbon vom Handy landet unter „Belege vom Handy“', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_beleg_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'B');
    final ein = Directory('${store.ordner}/eingang')..createSync(recursive: true);
    File('${ein.path}/1_b.jpg').writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    File('${ein.path}/1_b.json').writeAsStringSync(jsonEncode({'art': 'beleg', 'datei': '1_b.jpg', 'text': 'Bauhaus', 'autor': 'Tim'}));
    expect(eingangUebernehmen(store).uebernommen, 1);
    final b = belegeOffen(store).single;
    expect(b['text'], 'Bauhaus');
    expect(File('${store.ordner}/${b['datei']}').existsSync(), isTrue);
    store.schliessen();
  });
}
