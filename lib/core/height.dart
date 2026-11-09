/// Höhenbezüge: Jede Höhe wird mit dem Bezug gespeichert, von dem aus sie
/// gemessen wurde. Umrechnen geht über eine absolute Höhe im Geschoss
/// (Nullpunkt = Rohfußboden des Geschosses).
enum Hoehenbezug { rfb, ffb, rohdecke, meterriss }

extension HoehenbezugText on Hoehenbezug {
  String get label => switch (this) {
        Hoehenbezug.rfb => 'über RFB',
        Hoehenbezug.ffb => 'über FFB',
        Hoehenbezug.rohdecke => 'unter Rohdecke',
        Hoehenbezug.meterriss => 'zum Meterriss',
      };

  String get kurz => switch (this) {
        Hoehenbezug.rfb => 'RFB',
        Hoehenbezug.ffb => 'FFB',
        Hoehenbezug.rohdecke => 'RD',
        Hoehenbezug.meterriss => 'MR',
      };

  /// „unter Rohdecke“ wird nach unten gemessen.
  int get richtung => this == Hoehenbezug.rohdecke ? -1 : 1;
}

/// Bezugshöhen eines Geschosses oder Raums in mm, absolut im Geschoss.
class Bezugshoehen {
  const Bezugshoehen({
    required this.rfb,
    required this.ffb,
    required this.rohdecke,
    required this.meterriss,
  });

  final int rfb;
  final int ffb;
  final int rohdecke;
  final int meterriss;

  int von(Hoehenbezug b) => switch (b) {
        Hoehenbezug.rfb => rfb,
        Hoehenbezug.ffb => ffb,
        Hoehenbezug.rohdecke => rohdecke,
        Hoehenbezug.meterriss => meterriss,
      };

  /// Raumwerte überschreiben die Geschosswerte, wo sie gesetzt sind.
  Bezugshoehen mitRaum({int? rfb, int? ffb, int? rohdecke}) {
    final neuFfb = ffb ?? this.ffb;
    return Bezugshoehen(
      rfb: rfb ?? this.rfb,
      ffb: neuFfb,
      rohdecke: rohdecke ?? this.rohdecke,
      // Meterriss hängt am Fertigfußboden: Abstand bleibt erhalten.
      meterriss: meterriss + (neuFfb - this.ffb),
    );
  }
}

/// Absolute Höhe im Geschoss aus Wert + Bezug.
int absolut(int wertMm, Hoehenbezug bezug, Bezugshoehen h) =>
    h.von(bezug) + bezug.richtung * wertMm;

/// Rechnet einen Wert von einem Bezug in einen anderen um.
int umrechnen(int wertMm, Hoehenbezug von, Hoehenbezug nach, Bezugshoehen h) {
  final abs = absolut(wertMm, von, h);
  return (abs - h.von(nach)) * nach.richtung;
}
