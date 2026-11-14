/// Sprechende Kennungen wie EG-BAD-SD-03. Schema einstellbar: Trennzeichen,
/// Stellen der laufenden Nummer, Geschoss/Raum weglassen, eigenes Präfix (z. B. Gebäude).
String naechsteKennung({
  required String geschoss,
  required String raum,
  required String typ,
  required Iterable<String> vorhandene,
  String trenner = '-',
  int stellen = 2,
  bool mitGeschoss = true,
  bool mitRaum = true,
  String praefix = '',
}) {
  final teile = [
    if (praefix.trim().isNotEmpty) praefix.trim().toUpperCase(),
    if (mitGeschoss) geschoss.toUpperCase(),
    if (mitRaum) raum.toUpperCase(),
    typ.toUpperCase(),
  ];
  final prefix = '${teile.join(trenner)}$trenner';
  var max = 0;
  for (final k in vorhandene) {
    final ku = k.toUpperCase();
    if (!ku.startsWith(prefix)) continue;
    final n = int.tryParse(ku.substring(prefix.length));
    if (n != null && n > max) max = n;
  }
  return '$prefix${(max + 1).toString().padLeft(stellen.clamp(1, 5), '0')}';
}

/// Schlägt ein Kürzel aus einem Namen vor: „Wohnen“ → „WOH“, „Bad oben“ → „BO“.
String kuerzelVorschlag(String name) {
  final sauber = name
      .trim()
      .toUpperCase()
      .replaceAll('Ä', 'AE')
      .replaceAll('Ö', 'OE')
      .replaceAll('Ü', 'UE')
      .replaceAll('ß', 'SS')
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), '');
  if (sauber.isEmpty) return 'R';
  final woerter = sauber.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (woerter.length > 1) {
    return woerter.take(3).map((w) => w[0]).join();
  }
  final w = woerter.first;
  return w.length <= 3 ? w : w.substring(0, 3);
}
