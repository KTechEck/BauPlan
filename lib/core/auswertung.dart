import 'dart:math' as math;

import '../data/models.dart';
import 'fbh.dart';
import 'raumerkennung.dart';

/// Menge eines Objekts in seiner Einheit: Stück, Meter (Leitungen, Heizrohr
/// der Heizkreise) oder m² (sonstige Flächen).
double objektMenge(Objekt o, Objekttyp t) => switch (t.geometrie) {
      Geometrieart.punkt => 1.0,
      Geometrieart.linie => o.laenge / 1000,
      Geometrieart.flaeche => t.kuerzel == 'HK'
          ? rohrlaenge(o.punkte, FbhEinstellung.ausJson(o.eigenschaften)) / 1000
          : polygonFlaeche(o.punkte).abs() / 1e6,
    };

String objektEinheit(Objekttyp t) => switch (t.geometrie) {
      Geometrieart.punkt => 'Stk',
      Geometrieart.linie => 'm',
      Geometrieart.flaeche => t.kuerzel == 'HK' ? 'm' : 'm²',
    };

/// Plan/Ist einer Objektart: geplante Menge gesamt und wie viel davon
/// verlegt, geprüft und verdeckt ist (jeweils „mindestens“ dieser Stand).
class FortschrittZeile {
  FortschrittZeile(this.typ, this.einheit);
  final Objekttyp typ;
  final String einheit;
  double gesamt = 0;
  double verlegt = 0; // verlegt, geprüft oder verdeckt
  double geprueft = 0; // geprüft oder verdeckt
  double verdeckt = 0;
  int anzahl = 0;

  double get anteil => gesamt <= 0 ? 0 : verlegt / gesamt;
  double get offen => math.max(0, gesamt - verlegt);
}

/// Fortschritt je Objektart, optional nur für einen Raum oder ein Gewerk.
List<FortschrittZeile> fortschritt(Iterable<Objekt> objekte, Map<String, Objekttyp> typen, {String? raumId, String? gewerkId}) {
  final zeilen = <String, FortschrittZeile>{};
  for (final o in objekte) {
    final t = typen[o.typId];
    if (t == null || (raumId != null && o.raumId != raumId) || (gewerkId != null && t.gewerkId != gewerkId)) continue;
    if (t.kuerzel == 'WD' || t.kuerzel == 'MP') continue; // keine Mengen
    final z = zeilen.putIfAbsent(t.id, () => FortschrittZeile(t, objektEinheit(t)));
    final m = objektMenge(o, t);
    z
      ..gesamt += m
      ..anzahl += 1;
    if (o.status != ObjektStatus.geplant) z.verlegt += m;
    if (o.status == ObjektStatus.geprueft || o.status == ObjektStatus.verdeckt) z.geprueft += m;
    if (o.status == ObjektStatus.verdeckt) z.verdeckt += m;
  }
  return zeilen.values.toList()..sort((a, b) => a.typ.name.compareTo(b.typ.name));
}

/// Kosten Plan/Ist je Gewerk (brutto, Cent): Plan = alle Positionen,
/// beauftragt = bestellt oder geliefert, bezahlt, offen = noch nicht bestellt.
class KostenVergleich {
  KostenVergleich(this.gewerkId);
  final String? gewerkId;
  int plan = 0;
  int beauftragt = 0;
  int bezahlt = 0;
  int offen = 0;

  int get ist => beauftragt + bezahlt;
  double get anteilBezahlt => plan <= 0 ? 0 : bezahlt / plan;
}

List<KostenVergleich> kostenVergleich(Iterable<Kostenposition> positionen) {
  final zeilen = <String?, KostenVergleich>{};
  for (final p in positionen) {
    final z = zeilen.putIfAbsent(p.gewerkId, () => KostenVergleich(p.gewerkId));
    z.plan += p.bruttoCent;
    switch (p.status) {
      case KostenStatus.geplant || KostenStatus.angefragt:
        z.offen += p.bruttoCent;
      case KostenStatus.bestellt || KostenStatus.geliefert:
        z.beauftragt += p.bruttoCent;
      case KostenStatus.bezahlt:
        z.bezahlt += p.bruttoCent;
    }
  }
  return zeilen.values.toList();
}

/// Eine Zeile der Einkaufsliste.
class EinkaufsPosition {
  EinkaufsPosition({required this.position, required this.produkt, required this.angebot, required this.menge});
  final Kostenposition position;
  final Produkt? produkt;
  final Angebot? angebot;

  /// Einkaufsmenge: mit Zuschlag für Verschnitt (nur Meter und m²), aufgerundet.
  final double menge;

  int get einzelCent => angebot?.preisCent ?? position.einzelCent;
  int get steuer => angebot?.steuer ?? position.steuer;
  int get bruttoCent => (menge * einzelCent * (1 + steuer / 10000)).round();
  String get haendler => angebot?.haendler ?? 'ohne Händler';
}

/// Einkaufsmenge aus der Planmenge: Stück aufrunden; Meter und m² mit
/// [zuschlagProzent] Verschnitt, auf ganze Einheiten aufgerundet.
double einkaufsMenge(double menge, String einheit, {double zuschlagProzent = 10}) {
  if (menge <= 0) return 0;
  if (einheit == 'Stk' || einheit == 'Stück') return menge.ceilToDouble();
  if (einheit == 'm' || einheit == 'm²') return (menge * (1 + zuschlagProzent / 100) - 1e-9).ceilToDouble();
  return menge;
}

/// Einkaufsliste: Material-Positionen, die noch nicht bestellt sind
/// (geplant oder angefragt), mit dem günstigsten Händlerangebot, gruppiert
/// nach Händler. Mit [auchUnterwegs] kommen bestellte, noch nicht gelieferte dazu.
Map<String, List<EinkaufsPosition>> einkaufsliste(
  Iterable<Kostenposition> positionen,
  Iterable<Produkt> produkte, {
  double zuschlagProzent = 10,
  bool auchUnterwegs = false,
}) {
  final nachId = {for (final p in produkte) p.id: p};
  final gruppen = <String, List<EinkaufsPosition>>{};
  for (final p in positionen) {
    if (p.kostenart != 'Material') continue;
    final offen = p.status == KostenStatus.geplant || p.status == KostenStatus.angefragt;
    if (!offen && !(auchUnterwegs && p.status == KostenStatus.bestellt)) continue;
    if (p.mengeMilli <= 0) continue;
    final produkt = nachId[p.produktId];
    final e = EinkaufsPosition(
      position: p,
      produkt: produkt,
      angebot: produkt?.bestesAngebot,
      menge: einkaufsMenge(p.mengeMilli / 1000, p.einheit, zuschlagProzent: zuschlagProzent),
    );
    gruppen.putIfAbsent(e.haendler, () => []).add(e);
  }
  for (final g in gruppen.values) {
    g.sort((a, b) => a.position.text.compareTo(b.position.text));
  }
  return Map.fromEntries(gruppen.entries.toList()
    ..sort((a, b) => a.key == 'ohne Händler'
        ? 1
        : b.key == 'ohne Händler'
            ? -1
            : a.key.compareTo(b.key)));
}

String _menge(double m) => m == m.roundToDouble() ? m.round().toString() : m.toStringAsFixed(2).replaceAll('.', ',');
String _euro(int cent) => '${(cent / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

/// Einkaufsliste als CSV (Semikolon, für Excel).
String einkaufCsv(Map<String, List<EinkaufsPosition>> liste) {
  final b = StringBuffer('Händler;Position;Artikelnummer;Menge;Einheit;Einzelpreis brutto;Summe brutto;Link\n');
  String feld(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
  for (final e in liste.entries) {
    for (final p in e.value) {
      final ep = (p.einzelCent * (1 + p.steuer / 10000)).round();
      b.writeln([
        feld(e.key),
        feld(p.position.text),
        feld(p.produkt?.artikelnummer),
        _menge(p.menge),
        feld(p.position.einheit),
        _euro(ep),
        _euro(p.bruttoCent),
        feld(p.angebot?.link),
      ].join(';'));
    }
  }
  return b.toString();
}

String _html(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Einkaufsliste als HTML-Seite zum Abhaken auf dem Handy (Haken bleiben im
/// Browser des Handys gespeichert). Liegt im Projektordner unter `exporte/`.
String einkaufHtml(String projekt, Map<String, List<EinkaufsPosition>> liste, DateTime stand) {
  final b = StringBuffer()
    ..writeln('<!doctype html><html lang="de"><head><meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>Einkaufsliste ${_html(projekt)}</title>')
    ..writeln('<style>body{font-family:system-ui,sans-serif;margin:0;padding:16px;background:#f7f5f0;color:#222}'
        'h1{font-size:20px;margin:0 0 4px}h2{font-size:16px;margin:20px 0 6px}.leise{color:#777;font-size:13px}'
        'label{display:flex;gap:10px;align-items:flex-start;background:#fff;border-radius:8px;padding:10px;margin:6px 0}'
        'input{width:22px;height:22px;flex:none}label.ok{opacity:.45;text-decoration:line-through}'
        '.m{margin-left:auto;text-align:right;white-space:nowrap}a{color:#2b6cb0}</style></head><body>')
    ..writeln('<h1>Einkaufsliste</h1><div class="leise">${_html(projekt)} · Stand ${stand.day}.${stand.month}.${stand.year}</div>');
  var i = 0;
  for (final e in liste.entries) {
    final summe = e.value.fold<int>(0, (s, p) => s + p.bruttoCent);
    b.writeln('<h2>${_html(e.key)} <span class="leise">· ${_euro(summe)}</span></h2>');
    for (final p in e.value) {
      final link = p.angebot?.link;
      b.writeln('<label><input type="checkbox" data-k="${_html(p.position.id)}" id="k${i++}">'
          '<span>${_html(p.position.text)}${p.produkt?.artikelnummer == null ? '' : '<br><span class="leise">Art.-Nr. ${_html(p.produkt!.artikelnummer!)}</span>'}'
          '${link == null || link.isEmpty ? '' : '<br><a href="${_html(link)}">zum Händler</a>'}</span>'
          '<span class="m"><b>${_menge(p.menge)} ${_html(p.position.einheit)}</b><br><span class="leise">${_euro(p.bruttoCent)}</span></span></label>');
    }
  }
  b.writeln('<script>document.querySelectorAll("input[data-k]").forEach(function(c){var k="bs-"+c.dataset.k;'
      'try{c.checked=localStorage.getItem(k)==="1"}catch(e){}c.parentNode.classList.toggle("ok",c.checked);'
      'c.addEventListener("change",function(){try{localStorage.setItem(k,c.checked?"1":"0")}catch(e){}'
      'c.parentNode.classList.toggle("ok",c.checked)})});</script></body></html>');
  return b.toString();
}
