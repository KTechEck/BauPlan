import 'package:bauspur/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Millimeter mit Tausendertrennung', () {
    expect(mmText(2135), '2 135');
    expect(mmText(-35), '−35');
    expect(mmText(1000000), '1 000 000');
  });

  test('Fläche und Länge in m', () {
    expect(flaecheText(12345678), '12,35 m²');
    expect(meterText(14020), '14,02 m');
  });

  testWidgets('Logo lässt sich zeichnen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BauSpurLogo())));
    expect(find.byType(BauSpurLogo), findsOneWidget);
  });
}
