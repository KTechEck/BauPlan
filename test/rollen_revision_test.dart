import 'dart:convert';
import 'dart:io';

import 'package:bauspur/core/raumerkennung.dart';
import 'package:bauspur/core/revision.dart';
import 'package:bauspur/core/rollen.dart';
import 'package:bauspur/core/speicher.dart';
import 'package:bauspur/data/austausch.dart';
import 'package:bauspur/data/models.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Rollen: eigener Code je Benutzer, Gast liest nur, Mitarbeit landet in der Prüfung, Planstand nach Räumen', () async {
    final tmp = Directory.systemTemp.createTempSync('bauspur_rollen_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'planstand', 'planstand.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'projekt': 'Wohnhaus',
        'geschosse': [
          {
            'id': 'eg',
            'objekte': [
              {'id': 'a', 'raum': 'bad'},
              {'id': 'b', 'raum': 'kueche'},
            ],
          }
        ],
        'aufgaben': [],
      }));
    final nutzer = [
      Benutzer(id: 'm', name: 'Elektriker', rolle: Rolle.mitarbeit, code: '111111', raeume: const ['bad']),
      Benutzer(id: 'g', name: 'Oma', rolle: Rolle.gast, code: '222222'),
    ];
    final dienst = PcDienst(
      ordner: () => tmp.path,
      code: () => '123456',
      auskunft: () => {'name': 'PC'},
      benutzer: (c) => nutzer.where((b) => b.code == c).firstOrNull?.auskunft,
      planFiltern: (b, n) => utf8.encode(jsonEncode(planstandFuerBenutzer(Map<String, dynamic>.from(jsonDecode(utf8.decode(b)) as Map), n))),
    );
    expect(await dienst.starten(port: 0), isTrue);
    addTearDown(dienst.stoppen);
    final adresse = '127.0.0.1:${dienst.port}';

    expect((await PcSpeicher(adresse, code: '123456').pruefen())['rolle'], 'eigentuemer');
    final elektriker = PcSpeicher(adresse, code: '111111');
    expect((await elektriker.pruefen())['rolle'], 'mitarbeit');
    final plan = jsonDecode(utf8.decode((await elektriker.lesen(planstandPfad))!)) as Map;
    expect(plan['rolle'], 'mitarbeit');
    expect([for (final o in (plan['geschosse'] as List).first['objekte'] as List) o['id']], ['a']);

    final gast = PcSpeicher(adresse, code: '222222');
    expect((await gast.pruefen())['rolle'], 'gast');
    expect(await gast.schreiben('eingang/x.json', utf8.encode('{"art":"notiz"}')), isFalse);

    expect(await elektriker.schreiben('eingang/n.json', utf8.encode('{"art":"notiz","text":"Dose gesetzt","autor":"falsch"}')), isTrue);
    final e = jsonDecode(File(p.join(tmp.path, 'eingang', 'n.json')).readAsStringSync()) as Map;
    expect(e['autor'], 'Elektriker');
    expect(e['rolle'], 'mitarbeit');
    expect(e['pruefen'], isTrue);
  });

  test('Eingang: Einträge mit Prüfpflicht warten, Übernehmen schreibt ins Tagebuch', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_pruef_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'P');
    final ein = Directory(p.join(austauschOrdner(store), 'eingang'))..createSync(recursive: true);
    File(p.join(ein.path, '1.json')).writeAsStringSync(jsonEncode({'art': 'notiz', 'text': 'Leerrohr verlegt', 'autor': 'Elektriker', 'pruefen': true, 'zeit': '2026-11-14T10:00:00'}));
    final r = eingangUebernehmen(store);
    expect(r.uebernommen, 1);
    expect(store.tagebuch().length, 0);
    final liste = pruefListe(store);
    expect(liste.length, 1);
    expect(eintragText(liste.single.$2), contains('Leerrohr'));
    pruefEintragErledigen(store, liste.single.$1, uebernehmen: true);
    expect(pruefListe(store), isEmpty);
    expect(store.tagebuch().single.text, contains('Leerrohr verlegt'));
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });

  test('Revisionsöffnung: Abzweigdose in der Decke braucht eine Öffnung in Reichweite', () {
    final tmp = Directory.systemTemp.createTempSync('bauspur_rev_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'R');
    final g = store.geschosse(store.gebaeude().single.id).single.id;
    Objekttyp typ(String k) => store.objekttypen().firstWhere((t) => t.kuerzel == k);
    final dose = store.objektAnlegen(geschossId: g, typ: typ('DO'), punkte: const [Punkt(1000, 1000)], lage: 'in Decke');
    final typen = {for (final t in store.objekttypen()) t.id: t};
    var r = revisionPruefen(store.objekte(g), typen);
    expect(r.single.objekt.id, dose);
    expect(r.single.erreichbar, isFalse);
    store.objektAnlegen(geschossId: g, typ: typ('RO'), punkte: const [Punkt(1200, 800), Punkt(1500, 800), Punkt(1500, 1100), Punkt(1200, 1100)], lage: 'in Decke');
    r = revisionPruefen(store.objekte(g), typen);
    expect(r.single.erreichbar, isTrue);
    expect(r.single.abstand, closeTo(200, 0.1));
    store.schliessen();
    tmp.deleteSync(recursive: true);
  });
}
