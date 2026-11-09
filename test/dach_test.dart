import 'package:bauspur/core/dach.dart';
import 'package:bauspur/core/raumerkennung.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const g = (x0: 0.0, y0: 0.0, x1: 10000.0, y1: 8000.0);
  const d = DachEinstellung(form: Dachform.sattel, neigung: 45, kniestock: 500);

  test('Höhe unter der Schräge: Kniestock an der Traufe, steigt mit tan(Neigung)', () {
    expect(dachHoehe(d, g, const Punkt(5000, 0)), closeTo(500, 1e-6));
    expect(dachHoehe(d, g, const Punkt(5000, 1000)), closeTo(1500, 1e-6));
    expect(dachHoehe(d, g, const Punkt(5000, 7000)), closeTo(1500, 1e-6)); // andere Seite
    const kehl = DachEinstellung(form: Dachform.sattel, neigung: 45, kniestock: 500, kehlbalken: 2400);
    expect(dachHoehe(kehl, g, const Punkt(5000, 4000)), 2400);
    expect(hoehenLinie(d, g, 1000).map((v) => v.round()), [500, 7500]);
    expect(firstLage(d, g), 4000);
  });

  test('Wohnfläche: unter 1 m nicht, 1–2 m halb, ab 2 m voll', () {
    // Raum über die ganze Tiefe: je Seite 0,5 m < 1 m, 1 m zwischen 1 und 2 m, Rest voll
    const raum = [Punkt(0, 0), Punkt(1000, 0), Punkt(1000, 8000), Punkt(0, 8000)];
    final w = wohnflaeche(raum, d, g, raster: 50);
    expect(w.grund, closeTo(8, 1e-9));
    expect(w.unter1, closeTo(1.0, 0.05));
    expect(w.zwischen, closeTo(2.0, 0.05));
    expect(w.wohn, closeTo(5 + 1.0, 0.1));
  });

  test('U-Wert Dach sinkt mit Untersparrendämmung, Sparren als Wärmebrücke', () {
    const ohne = DachEinstellung(form: Dachform.sattel, sparrenHoehe: 180, zwischenDicke: 180);
    const mit = DachEinstellung(form: Dachform.sattel, sparrenHoehe: 180, zwischenDicke: 180, unterDicke: 60);
    expect(uDach(ohne), inInclusiveRange(0.18, 0.26));
    expect(uDach(mit), lessThan(uDach(ohne)));
    expect(sparrenLagen(const DachEinstellung(form: Dachform.sattel, sparrenAbstand: 1000), g).length, 10);
  });

  test('Kniestock abschnittsweise und je Traufseite', () {
    const k = DachEinstellung(form: Dachform.sattel, neigung: 45, kniestock: 500, abschnitte: [KniestockAbschnitt(von: 0, bis: 4000, vorne: 1200, hinten: 800)]);
    expect(kniestockBei(k, g, const Punkt(2000, 100)), 1200);
    expect(kniestockBei(k, g, const Punkt(2000, 7900)), 800);
    expect(kniestockBei(k, g, const Punkt(6000, 100)), 500);
    expect(dachHoehe(k, g, const Punkt(2000, 0)), closeTo(1200, 1e-6));
    final linien = hoehenLinienAbschnitte(k, g, 2000);
    expect(linien.where((l) => l.$1 == 0 && l.$2 == 4000).map((l) => l.$3.round()), [800, 6800]);
    expect(linien.where((l) => l.$1 == 4000).map((l) => l.$3.round()), [1500, 6500]);
  });
}
