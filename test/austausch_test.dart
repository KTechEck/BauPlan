import 'dart:convert';
import 'dart:io';

import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/austausch.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Planstand für die App und Übernahme des Eingangs (Foto, Status, Notiz)', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_aus_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'A');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final sd = store.objekttypen().firstWhere((t) => t.kuerzel == 'SD');
    final o = store.objektAnlegen(geschossId: g, typ: sd, punkte: const [Punkt(500, 100)]);

    planstandSchreiben(store);
    final plan = jsonDecode(File(p.join(store.ordner, planstandDatei)).readAsStringSync()) as Map;
    expect(plan['version'], planstandVersion);
    final obj = ((plan['geschosse'] as List).first['objekte'] as List).single as Map;
    expect(obj['id'], o);
    expect(obj['typ'], 'SD');

    final ein = Directory(p.join(store.ordner, 'eingang'));
    File(p.join(ein.path, '20261109_a.jpg')).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    File(p.join(ein.path, '20261109_a.json')).writeAsStringSync(jsonEncode(
        {'id': 'a', 'art': 'foto', 'zeit': '2026-11-09T10:00:00Z', 'autor': 'Tim', 'geschoss': g, 'objekt': o, 'x': 480, 'y': 120, 'datei': '20261109_a.jpg', 'text': 'Dose vor dem Verputzen'}));
    File(p.join(ein.path, '20261109_b.json')).writeAsStringSync(
        jsonEncode({'id': 'b', 'art': 'status', 'zeit': '2026-11-09T10:01:00Z', 'autor': 'Tim', 'geschoss': g, 'objekt': o, 'status': 'verdeckt'}));
    File(p.join(ein.path, '20261109_c.json')).writeAsStringSync(
        jsonEncode({'id': 'c', 'art': 'messwert', 'zeit': '2026-11-09T10:02:00Z', 'autor': 'Tim', 'geschoss': g, 'objekt': o, 'wert': 315, 'einheit': 'mm', 'text': 'Höhe OK FFB'}));

    final r = eingangUebernehmen(store);
    expect(r.uebernommen, 3, reason: r.hinweise.join('; '));
    expect(store.fotos(g).single.objektIds, [o]);
    expect(store.fotos(g).single.x, 480);
    final neu = store.objekte(g).single;
    expect(neu.status, ObjektStatus.verdeckt);
    expect((neu.eigenschaften['erfassungen'] as List).single['wert'], 315);
    expect(ein.listSync().whereType<File>(), isEmpty);
    expect(Directory(p.join(ein.path, '_archiv')).listSync().length, 4);
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });
}
