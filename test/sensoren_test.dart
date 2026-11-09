import 'dart:io';

import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/anschluesse.dart';
import 'package:bauspur/core/sensoren.dart';
import 'package:bauspur/data/app_settings.dart';
import 'package:bauspur/data/project_store.dart';
import 'package:bauspur/state/app_state.dart';
import 'package:bauspur/ui/sensoren_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final v = SensorVorlage(
    id: 's1',
    name: 'Raumklima ESP',
    protokoll: '1-Wire',
    breite: 80,
    hoehe: 80,
    tiefe: 25,
    anschluesse: const [(name: '+5 V', farbe: 'rot'), (name: 'GND', farbe: 'schwarz'), (name: 'Daten', farbe: 'gelb')],
    entitaeten: const ['temperatur', 'bewegung'],
  );

  test('Vorlage: JSON, Inhaltspaket, Instanz-Entitäten', () {
    final z = SensorVorlage.ausJson(v.toJson());
    expect(z.name, 'Raumklima ESP');
    expect(z.tiefe, 25);
    expect(z.anschluesse[2], (name: 'Daten', farbe: 'gelb'));
    final paket = inhaltspaket([v]);
    expect(inhaltspaketLesen(paket).single.id, 's1');
    expect(() => inhaltspaketLesen('{"x":1}'), throwsFormatException);
    expect(instanzEntitaeten(v, 'bad_klima'), {'temperatur': 'sensor.bad_klima_temperatur', 'bewegung': 'binary_sensor.bad_klima_bewegung'});
    expect(standardBelegung('I²C')['weiß'], 'SDA');
    expect(kabelTypen['CAT 7 S/FTP']!.length, 8);
  });

  test('Anschlüsse eines eigenen Sensors aus der Instanz', () {
    final a = anschluesse('ES', {
      'anschluesse': [
        {'name': '+5 V', 'farbe': 'rot'},
        {'name': 'GND', 'farbe': 'schwarz'},
      ]
    });
    expect(a.map((e) => e.name), ['+5 V', 'GND']);
    expect(a.first.dx, -7.5);
    expect(anschluesse('ES', const {}), isEmpty);
  });

  test('Topologie: Linie, Stern, Baum', () {
    expect(topologie(const []), isNull);
    expect(topologie(const [[(0, 0), (100, 0)], [(100, 0), (200, 0)]]), 'Linie');
    expect(topologie(const [[(0, 0), (100, 0)], [(0, 0), (0, 100)], [(0, 0), (-100, 0)]]), 'Stern');
    expect(
        topologie(const [
          [(0, 0), (100, 0)], [(0, 0), (0, 100)], [(0, 0), (-100, 0)],
          [(100, 0), (200, 0)], [(100, 0), (100, 100)],
        ]),
        'Baum');
  });

  testWidgets('Bibliothek: Sensor anlegen und Anschluss ergänzen', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('bauspur_se_');
    final store = ProjectStore.anlegen(elternOrdner: tmp.path, projektName: 'S');
    addTearDown(() {
      store.schliessen();
      tmp.deleteSync(recursive: true);
    });
    final state = AppState(AppSettings.inDatei(File('${tmp.path}/einstellungen.json')))..store = store;
    await tester.pumpWidget(MaterialApp(theme: bauSpurTheme(), home: Scaffold(body: SensorenAnsicht(state: state))));
    expect(find.text('Noch keine eigenen Sensoren.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sensor'));
    await tester.pump();
    expect(sensorVorlagen(state).single.anschluesse.length, 3);
    await tester.tap(find.text('Anschluss'));
    await tester.pump();
    expect(sensorVorlagen(state).single.anschluesse.length, 4);
    expect(find.text('Neuer Sensor'), findsWidgets);
  });
}
