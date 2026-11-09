/// Verdrahtungskette in der Installation: welches Gerät speist welches (Dose zu
/// Dose weitergeschleift), wie viele Adern die Zuleitung braucht und worauf
/// bei Kombinationen (Schalter + Steckdose im Rahmen) zu achten ist.
///
/// Grundlagen (vereinfacht, ersetzt keine Planung durch die Elektrofachkraft):
/// - Steckdose: L, N, PE → 3 Adern.
/// - Ausschalter: L hin, geschaltete Phase zurück. Geht die Leuchtenleitung
///   direkt von der Schalterdose ab, reichen 3 Adern zur Dose (L, N, PE) und
///   3 Adern zur Leuchte (L geschaltet, N, PE). Muss die geschaltete Phase zur
///   Abzweigdose zurück, braucht die Leitung 4–5 Adern (L, L', N, PE).
/// - Serienschalter: zwei geschaltete Phasen → 5 Adern, wenn beide zurückgehen.
/// - Wechselschaltung: zwischen den Schaltern 2 korrespondierende Adern + L/L'
///   → üblich 5 × 1,5 mm².
/// - Weiterschleifen nur über Klemmen in tiefen Dosen (Geräteverbindungsdose),
///   nicht über die Gerätekontakte, wenn diese dafür nicht zugelassen sind.
/// - DIN 18015-2: Mindestanzahl Steckdosen/Auslässe/Stromkreise je Raum,
///   VDE 0100-520: Spannungsfall, VDE 0298-4: Belastbarkeit der Leitung.
library;

/// Schaltungsart eines Schalters.
enum Schaltung {
  aus('Ausschaltung'),
  serie('Serienschaltung'),
  wechsel('Wechselschaltung'),
  kreuz('Kreuzschaltung'),
  taster('Taster / Stromstoß'),
  dimmer('Dimmer');

  const Schaltung(this.label);
  final String label;
}

/// Adern, die ein Gerät an seiner Zuleitung mindestens braucht. [leuchteAbHier]:
/// die Leuchtenleitung geht von dieser Dose ab (geschaltete Phase muss nicht zurück).
int aderBedarf(String kuerzel, {Schaltung schaltung = Schaltung.aus, bool leuchteAbHier = true}) => switch (kuerzel) {
      'SD' || 'FA' || 'DO' || 'LE' => 3,
      'TA' => switch (schaltung) {
          Schaltung.aus || Schaltung.dimmer || Schaltung.taster => leuchteAbHier ? 3 : 4,
          Schaltung.serie => leuchteAbHier ? 3 : 5,
          Schaltung.wechsel || Schaltung.kreuz => 5,
        },
      'KX' || 'PM' || 'BM' => 3,
      _ => 3,
    };

/// Bedarf für alles in einer Dose bzw. einem Mehrfachrahmen.
int aderBedarfRahmen(List<String> kuerzel, {Schaltung schaltung = Schaltung.aus, bool leuchteAbHier = true}) {
  var n = 3;
  for (final k in kuerzel) {
    final b = aderBedarf(k, schaltung: schaltung, leuchteAbHier: leuchteAbHier);
    if (b > n) n = b;
  }
  // Schalter und Steckdose zusammen, geschaltete Phase muss zurück: L, L', N, PE
  if (kuerzel.contains('TA') && kuerzel.contains('SD') && !leuchteAbHier && n < 4) n = 4;
  return n;
}

/// Ein Glied der Kette: Gerät mit dem, was es speist.
typedef Kettenglied = ({String id, String kennung, String kuerzel, String? gespeistVon, int? adern, double? querschnitt, int leistung});

/// Reihenfolge ab der Einspeisung (Stromkreis) bis zum Ende; Zyklen werden abgebrochen.
List<List<Kettenglied>> ketten(List<Kettenglied> glieder) {
  final nach = <String?, List<Kettenglied>>{};
  final ids = {for (final g in glieder) g.id};
  for (final g in glieder) {
    nach.putIfAbsent(ids.contains(g.gespeistVon) ? g.gespeistVon : null, () => []).add(g);
  }
  final aus = <List<Kettenglied>>[];
  void lauf(Kettenglied g, List<Kettenglied> bisher, Set<String> besucht) {
    if (besucht.contains(g.id)) return;
    final weg = [...bisher, g];
    final weiter = nach[g.id] ?? const [];
    if (weiter.isEmpty) {
      aus.add(weg);
      return;
    }
    for (final w in weiter) {
      lauf(w, weg, {...besucht, g.id});
    }
  }

  for (final s in nach[null] ?? const <Kettenglied>[]) {
    lauf(s, const [], {});
  }
  return aus;
}

/// Hinweise zur Kette eines Geräts.
List<String> kettenHinweise({
  required Kettenglied geraet,
  required List<String> imRahmen,
  required List<Kettenglied> alle,
  Schaltung schaltung = Schaltung.aus,
  bool leuchteAbHier = true,
  int? schutzAmpere,
}) {
  final h = <String>[];
  final bedarf = aderBedarfRahmen(imRahmen.isEmpty ? [geraet.kuerzel] : imRahmen, schaltung: schaltung, leuchteAbHier: leuchteAbHier);
  if (geraet.adern != null && geraet.adern! < bedarf) {
    h.add('Zuleitung hat ${geraet.adern} Adern, hier werden mindestens $bedarf gebraucht.');
  }
  if (imRahmen.contains('TA') && imRahmen.contains('SD')) {
    h.add(leuchteAbHier
        ? 'Schalter + Steckdose: 3 Adern (L, N, PE) reichen, wenn die Leitung zur Leuchte von dieser Dose abgeht (3 × 1,5: L geschaltet, N, PE).'
        : 'Schalter + Steckdose, Leuchte wird von einer anderen Dose versorgt: die geschaltete Phase muss zurück – 5 × 1,5 (L, L\', N, PE + Reserve).');
  }
  if (schaltung == Schaltung.wechsel || schaltung == Schaltung.kreuz) {
    h.add('${schaltung.label}: zwischen den Schaltern zwei korrespondierende Adern – üblich NYM-J 5 × 1,5.');
  }
  // weitergeschleift: was hängt dahinter?
  final dahinter = <Kettenglied>[];
  void sammeln(String id) {
    for (final g in alle.where((x) => x.gespeistVon == id)) {
      if (dahinter.contains(g)) continue;
      dahinter.add(g);
      sammeln(g.id);
    }
  }

  sammeln(geraet.id);
  if (dahinter.isNotEmpty) {
    final last = dahinter.fold<int>(geraet.leistung, (s, g) => s + g.leistung);
    h.add('Speist weiter: ${dahinter.map((g) => g.kennung).join(', ')} – Klemmen in einer tiefen Dose (Geräteverbindungsdose) vorsehen.');
    final q = geraet.querschnitt ?? 1.5;
    final grenze = (schutzAmpere ?? (q >= 2.5 ? 20 : 16)) * 230;
    if (last > grenze) h.add('Summe ${(last / 1000).toStringAsFixed(1)} kW über der Grenze des Stromkreises (${(grenze / 1000).toStringAsFixed(1)} kW).');
  }
  final steckdosen = [geraet, ...dahinter].where((g) => g.kuerzel == 'SD').length;
  if (steckdosen > 8) h.add('$steckdosen Steckdosen an einer Kette – DIN 18015-2 empfiehlt, Steckdosen auf mehrere Stromkreise zu verteilen.');
  return h;
}
