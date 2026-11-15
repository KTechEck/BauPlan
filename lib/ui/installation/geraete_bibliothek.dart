import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../symbole_plan.dart';

/// Bereiche der Gerätebibliothek (wie in Elektro-CAD-Programmen): Gewerke-
/// bzw. Typ-Kürzel, die dazugehören.
const geraeteBereiche = <String, ({Set<String> gewerke, Set<String> typen})>{
  'Elektro': (gewerke: {'EL'}, typen: {'SD', 'TA', 'DO', 'FA', 'VT', 'SR', 'TO'}),
  'Licht': (gewerke: {}, typen: {'LE', 'LB', 'AE', 'PO', 'EB', 'SI'}),
  'Netzwerk': (gewerke: {'NW'}, typen: {'ND', 'NK', 'AP'}),
  'Sicherheit': (gewerke: {}, typen: {'RW', 'WR', 'CM', 'FL', 'BA', 'BK', 'SI', 'BM', 'AP', 'MP'}),
  'Smart Home': (gewerke: {'KX'}, typen: {'KX', 'PM', 'BM', 'ES', 'BL', 'SL'}),
  'Sanitär': (gewerke: {'SA'}, typen: {'EN', 'KW', 'WW', 'ZI', 'AW'}),
  'Heizung': (gewerke: {'HZ', 'FH'}, typen: {'HZ', 'HV', 'HK', 'VL', 'RL', 'HR'}),
  'Lüftung / Klima': (gewerke: {'LU', 'KL'}, typen: {'LV', 'LG', 'KG', 'LK', 'KL'}),
  'Außen': (gewerke: {'AU'}, typen: {}),
};

/// Produktkategorie aus der Bibliothek → passender Objekttyp (Kürzel).
String? typFuerProdukt(Bauelement e) {
  final t = '${e.daten['typ'] ?? e.daten['technikart'] ?? ''} ${e.name}'.toLowerCase();
  return switch (e.kategorie) {
    BauelementKategorie.elektro => t.contains('netzwerk') || t.contains('daten') || t.contains('rj45')
        ? 'ND'
        : (t.contains('schalter') || t.contains('taster') || t.contains('dimmer') ? 'TA' : 'SD'),
    BauelementKategorie.leuchte => 'LE',
    BauelementKategorie.sensor => t.contains('präsenz') || t.contains('praesenz') ? 'PM' : 'BM',
    BauelementKategorie.brandschutz => t.contains('wärme') ? 'WR' : (t.contains('co') ? 'CM' : 'RW'),
    BauelementKategorie.technik => t.contains('lüft') ? 'LG' : (t.contains('klima') ? 'KG' : 'HZ'),
    BauelementKategorie.heizkoerper => 'HZ',
    BauelementKategorie.sanitaer || BauelementKategorie.armatur => 'EN',
    _ => null,
  };
}

/// Ein Eintrag der Gerätebibliothek: Objekttyp, optional mit Produkt.
typedef GeraetEintrag = ({String schluessel, Objekttyp typ, Bauelement? produkt, Color farbe, String titel, String zeile});

/// Alle Einträge: jeder Objekttyp (Punkt/Linie) und jedes passende Produkt.
List<GeraetEintrag> geraeteEintraege(AppState s) {
  final store = s.store!;
  final gewerke = {for (final g in store.gewerke()) g.id: g};
  final typen = store.objekttypen();
  final nachKuerzel = <String, Objekttyp>{};
  for (final t in typen) {
    nachKuerzel.putIfAbsent(t.kuerzel, () => t);
  }
  final aus = <GeraetEintrag>[
    for (final t in typen)
      if (t.geometrie != Geometrieart.flaeche)
        (schluessel: 'typ:${t.id}', typ: t, produkt: null, farbe: Color(gewerke[t.gewerkId]?.farbe ?? 0xFF868E96), titel: t.name, zeile: '${t.kuerzel} · ${gewerke[t.gewerkId]?.name ?? ''}'),
  ];
  for (final e in s.bibliothek.alle) {
    final k = typFuerProdukt(e);
    final t = k == null ? null : nachKuerzel[k];
    if (t == null) continue;
    final d = e.daten;
    final daten = [
      if (d['leistung_w'] != null) '${d['leistung_w']} W',
      if (d['leistung_kw'] != null) '${d['leistung_kw']} kW',
      if (d['breite'] != null && d['hoehe'] != null) '${d['breite']}×${d['hoehe']}${d['tiefe'] == null ? '' : '×${d['tiefe']}'} mm',
      if (d['ip'] != null) '${d['ip']}',
      if (e.artikelnummer.isNotEmpty) 'Art. ${e.artikelnummer}',
    ];
    aus.add((schluessel: 'el:${e.id}', typ: t, produkt: e, farbe: Color(gewerke[t.gewerkId]?.farbe ?? 0xFF868E96), titel: e.anzeige, zeile: ['Produkt · ${t.kuerzel}', ...daten].join(' · ')));
  }
  return aus;
}

bool imBereich(GeraetEintrag e, String bereich, Map<String, Gewerk> gewerke) {
  final b = geraeteBereiche[bereich];
  if (b == null) return true;
  return b.typen.contains(e.typ.kuerzel) || b.gewerke.contains(gewerke[e.typ.gewerkId]?.kuerzel);
}

/// Favoriten (je PC): Schlüssel `typ:<id>` oder `el:<id>`.
List<String> geraeteFavoriten(AppState s) => [for (final x in (s.settings.darstellung['geraete_favoriten'] as List? ?? const [])) '$x'];

void favoritUmschalten(AppState s, String k) {
  final l = geraeteFavoriten(s);
  l.contains(k) ? l.remove(k) : l.add(k);
  s.settings.darstellung['geraete_favoriten'] = l;
  s.settings.speichern();
}

/// Produktdaten, die ein neues Objekt vom gewählten Produkt übernimmt.
Map<String, dynamic> produktEigenschaften(Bauelement e) {
  final d = e.daten;
  num? z(String k) => d[k] is num ? d[k] as num : num.tryParse('${d[k] ?? ''}'.replaceAll(',', '.'));
  final b = z('breite'), t = z('tiefe'), h = z('hoehe');
  final w = z('leistung_w') ?? (z('leistung_kw') == null ? null : z('leistung_kw')! * 1000);
  return {
    'bauelement': e.id,
    if (b != null && t != null && h != null) 'masse': [b, t, h],
    if (w != null) 'leistung_w': w,
  };
}

/// Gerätebibliothek als Dialog: Bereiche, Suche, Favoriten (Stern), Produkte
/// mit Daten. Liefert den gewählten Eintrag zum Setzen.
Future<GeraetEintrag?> geraeteBibliothekZeigen(BuildContext context, AppState s) =>
    showDialog<GeraetEintrag>(context: context, builder: (_) => _GeraeteBibliothek(state: s));

class _GeraeteBibliothek extends StatefulWidget {
  const _GeraeteBibliothek({required this.state});
  final AppState state;
  @override
  State<_GeraeteBibliothek> createState() => _GeraeteBibliothekState();
}

class _GeraeteBibliothekState extends State<_GeraeteBibliothek> {
  String _bereich = 'Favoriten';
  String _suche = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final gewerke = {for (final g in s.store!.gewerke()) g.id: g};
    final alle = geraeteEintraege(s);
    final fav = geraeteFavoriten(s);
    final liste = [
      for (final e in alle)
        if ((_suche.isNotEmpty || (_bereich == 'Favoriten' ? fav.contains(e.schluessel) : _bereich == 'Alle' || imBereich(e, _bereich, gewerke))) &&
            (_suche.isEmpty || '${e.titel} ${e.zeile}'.toLowerCase().contains(_suche)))
          e
    ];
    return AlertDialog(
      title: const Text('Gerätebibliothek'),
      content: SizedBox(
        width: 860,
        height: 560,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 170,
            child: ListView(children: [
              for (final b in ['Favoriten', 'Alle', ...geraeteBereiche.keys])
                ListTile(
                  dense: true,
                  selected: _suche.isEmpty && _bereich == b,
                  leading: b == 'Favoriten' ? const Icon(Icons.star, size: 18, color: Color(0xFFF59F00)) : null,
                  title: Text(b),
                  onTap: () => setState(() {
                    _bereich = b;
                    _suche = '';
                  }),
                ),
            ]),
          ),
          const VerticalDivider(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Suchen: Steckdose, Rauchmelder, Hersteller, Artikelnummer …'),
                onChanged: (v) => setState(() => _suche = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: liste.isEmpty
                    ? Center(
                        child: Text(_bereich == 'Favoriten' && _suche.isEmpty ? 'Noch keine Favoriten – Stern bei einem Gerät setzen. Favoriten erscheinen als Schnellleiste über dem Plan.' : 'Nichts gefunden.',
                            textAlign: TextAlign.center, style: const TextStyle(color: BsFarben.textLeise)),
                      )
                    : ListView(children: [
                        for (final e in liste)
                          ListTile(
                            dense: true,
                            leading: SizedBox(width: 30, height: 30, child: CustomPaint(painter: SymbolPainter(e.typ.kuerzel, e.farbe, linie: e.typ.geometrie == Geometrieart.linie))),
                            title: Text(e.titel),
                            subtitle: Text(e.zeile, style: const TextStyle(fontSize: 11)),
                            trailing: IconButton(
                              tooltip: fav.contains(e.schluessel) ? 'Aus den Favoriten' : 'Zu den Favoriten (Schnellleiste)',
                              icon: Icon(fav.contains(e.schluessel) ? Icons.star : Icons.star_border, color: const Color(0xFFF59F00)),
                              onPressed: () => setState(() => favoritUmschalten(s, e.schluessel)),
                            ),
                            onTap: () => Navigator.pop(context, e),
                          ),
                      ]),
              ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
    );
  }
}

/// Plansymbol als kleines Bild (Liste, Schnellleiste).
class SymbolPainter extends CustomPainter {
  SymbolPainter(this.kuerzel, this.farbe, {this.linie = false});
  final String kuerzel;
  final Color farbe;
  final bool linie;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    if (linie) {
      canvas.drawLine(Offset(2, c.dy), Offset(size.width - 2, c.dy), Paint()
        ..color = farbe
        ..strokeWidth = 2.5);
      return;
    }
    geraetSymbol(canvas, c, size.shortestSide * 0.36, kuerzel, farbe);
  }

  @override
  bool shouldRepaint(covariant SymbolPainter old) => old.kuerzel != kuerzel || old.farbe != farbe;
}

/// Schnellleiste: Favoriten als Symbolknöpfe zum direkten Setzen.
class GeraeteSchnellleiste extends StatelessWidget {
  const GeraeteSchnellleiste({super.key, required this.state, required this.waehlen, this.aktiv});
  final AppState state;
  final void Function(GeraetEintrag e) waehlen;
  final String? aktiv; // Schlüssel des gewählten Eintrags

  @override
  Widget build(BuildContext context) {
    final fav = geraeteFavoriten(state);
    if (fav.isEmpty) return const SizedBox.shrink();
    final nach = {for (final e in geraeteEintraege(state)) e.schluessel: e};
    return Wrap(spacing: 2, children: [
      for (final k in fav)
        if (nach[k] case final e?)
          Tooltip(
            message: '${e.titel} setzen',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => waehlen(e),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: aktiv == k ? BsFarben.akzentHell : null,
                  border: Border.all(color: aktiv == k ? BsFarben.akzent : BsFarben.rand),
                ),
                child: CustomPaint(painter: SymbolPainter(e.typ.kuerzel, e.farbe, linie: e.typ.geometrie == Geometrieart.linie)),
              ),
            ),
          ),
    ]);
  }
}
