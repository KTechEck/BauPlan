import 'package:bauspur/app/theme.dart';
import 'package:bauspur/core/bauelemente.dart';
import 'package:bauspur/ui/bauteile/bauelement_skizze.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Maßskizze für jede Kategorie ohne Fehler', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final k in BauelementKategorie.values) {
      final e = Bauelement(id: 'x-${k.name}', kategorie: k, name: k.label, daten: const {});
      await tester.pumpWidget(MaterialApp(
        theme: bauSpurTheme(),
        home: Scaffold(body: SingleChildScrollView(child: BauelementSkizze(element: e, setzen: (_) {}))),
      ));
      expect(tester.takeException(), isNull, reason: k.name);
      expect(find.byType(CustomPaint), findsWidgets, reason: k.name);
      expect(skizzenFelder(k), isNotEmpty, reason: 'Skizze mit Feldern für ${k.name}');
    }
  });
}
