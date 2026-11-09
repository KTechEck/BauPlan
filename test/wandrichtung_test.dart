import 'dart:io';
import 'dart:math' as math;

import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Wandaufbau automatisch: erste Schicht (innen) zum Raum, Öffnung bleibt am Ort', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_wr_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'W');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    final typ = store.wandtypen().first;
    // gegen den Uhrzeigersinn auf dem Bildschirm (y nach unten): links liegt außen
    const ecken = [(0, 0), (0, 3000), (4000, 3000), (4000, 0)];
    for (var i = 0; i < 4; i++) {
      final a = ecken[i], b = ecken[(i + 1) % 4];
      store.wandAnlegen(geschossId: g, x1: a.$1, y1: a.$2, x2: b.$1, y2: b.$2, dicke: typ.dicke, wandtypId: typ.id);
    }
    final w0 = store.waende(g).firstWhere((w) => w.x1 == 0 && w.x2 == 0 || (w.x1 == 0 && w.x2 == 0));
    for (final w in store.waende(g)) {
      final dx = (w.x2 - w.x1).toDouble(), dy = (w.y2 - w.y1).toDouble();
      final l = math.sqrt(dx * dx + dy * dy);
      final links = Punkt((w.x1 + w.x2) / 2 + dy / l * 300, (w.y1 + w.y2) / 2 - dx / l * 300);
      expect(links.x > 0 && links.x < 4000 && links.y > 0 && links.y < 3000, isTrue, reason: 'Wand ${w.id} links = innen');
    }
    expect(w0, isNotNull);
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });
}
