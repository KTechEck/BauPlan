import 'dart:math' as math;

import '../../core/brandschutz.dart';
import '../../core/fbh.dart';
import '../../core/height.dart';
import '../../core/ki.dart';
import '../../core/knx.dart';
import '../../core/licht.dart';
import '../../core/raumerkennung.dart';
import '../../core/schrank.dart';
import '../../core/technik.dart';
import '../../core/verdrahtung.dart';
import '../../core/verteiler.dart';
import '../../data/models.dart';
import '../../data/project_store.dart';

/// Feste Regeln über das ganze Projekt – exakt gerechnet, ohne Sprachmodell.
List<PruefHinweis> projektPruefen(ProjectStore store, Regelwerte r) {
  final h = <PruefHinweis>[];
  final typen = {for (final t in store.objekttypen()) t.id: t};
  final gewerke = {for (final g in store.gewerke()) g.id: g.kuerzel};
  final geschosse = [for (final geb in store.gebaeude()) ...store.geschosse(geb.id)];
  final schraenke = store.schraenke();

  for (final g in geschosse) {
    final raeume = store.raeume(g.id);
    final flaechen = store.flaechenErkennen(g.id);
    final objekte = store.objekte(g.id);
    // Räume
    for (final raum in raeume) {
      if (raum.istBodenplatte) continue;
      if (raum.umriss == null) {
        h.add(PruefHinweis(bereich: 'Grundriss', text: '${g.kuerzel} ${raum.name}: noch nicht im Grundriss verortet.'));
      } else if (raum.bezug != null && !flaechen.any((f) => f.enthaelt(raum.bezug!))) {
        h.add(PruefHinweis(bereich: 'Grundriss', text: '${g.kuerzel} ${raum.name}: Wandzug offen.'));
      }
    }
    // Objekte ohne Raum
    final ohneRaum = objekte.where((o) => o.raumId == null && typen[o.typId]?.geometrie == Geometrieart.punkt).toList();
    if (ohneRaum.isNotEmpty) {
      h.add(PruefHinweis(
          bereich: 'Installation',
          text: '${g.kuerzel}: ${ohneRaum.length} Objekt(e) ohne Raum (${ohneRaum.take(4).map((o) => o.kennung).join(', ')}${ohneRaum.length > 4 ? ' …' : ''}).',
          objektId: ohneRaum.first.id));
    }
    // Brandschutz: Rauchwarnmelder (Landesbauordnungen, DIN 14676)
    h.addAll(brandschutzPruefen(store, g, raeume, objekte, typen));
    // Fußbodenheizung
    final verteiler =[for (final o in objekte) if (typen[o.typId]?.kuerzel == 'HV') o];
    final zugeordnet = {
      for (final v in verteiler)
        for (final k in VerteilerDaten.ausJson(v.eigenschaften).kreise)
          if (k != null) k,
    };
    for (final o in objekte) {
      if (typen[o.typId]?.kuerzel != 'HK') continue;
      final l = rohrlaenge(o.punkte, FbhEinstellung.ausJson(o.eigenschaften)) / 1000;
      if (l > r.maxKreislaengeM) {
        h.add(PruefHinweis(bereich: 'Fußbodenheizung', text: '${o.kennung}: Kreislänge ${l.round()} m über ${r.maxKreislaengeM} m.', objektId: o.id));
      }
      if (verteiler.isNotEmpty && !zugeordnet.contains(o.id)) {
        h.add(PruefHinweis(bereich: 'Fußbodenheizung', text: '${o.kennung}: keinem Verteilerabgang zugeordnet.', objektId: o.id));
      }
    }
    for (final v in verteiler) {
      for (final t in VerteilerDaten.ausJson(v.eigenschaften).hinweise()) {
        h.add(PruefHinweis(bereich: 'Fußbodenheizung', text: '${v.kennung}: $t', objektId: v.id));
      }
    }
    // Elektro ohne Stromkreis (nur wenn schon Schränke geplant sind)
    if (schraenke.isNotEmpty) {
      final ohne = [
        for (final o in objekte)
          if (const {'SD', 'LE', 'FA'}.contains(typen[o.typId]?.kuerzel) && o.eigenschaften['stromkreis'] == null) o
      ];
      if (ohne.isNotEmpty) {
        h.add(PruefHinweis(
            bereich: 'Elektro',
            text: '${g.kuerzel}: ${ohne.length} Steckdose(n)/Leuchte(n)/Festanschlüsse ohne Stromkreis.',
            objektId: ohne.first.id));
      }
    }
    // Licht und Technik je Raum
    for (final raum in raeume) {
      final umriss = raum.umriss;
      if (umriss == null) continue;
      final hoehen = raum.hoehen(g);
      final imRaum = [for (final o in objekte) if (o.punkte.length == 1 && (o.raumId == raum.id || punktInPolygon(o.punkte.first, umriss))) o];
      double ueberFfb(Objekt o) => o.z == null || o.zBezug == null ? (hoehen.rohdecke - hoehen.ffb).toDouble() : (absolut(o.z!, o.zBezug!, hoehen) - hoehen.ffb).toDouble();
      final leuchten = [
        for (final o in imRaum)
          if (typen[o.typId]?.kuerzel == 'LE')
            (
              x: o.punkte.first.x,
              y: o.punkte.first.y,
              hoehe: ueberFfb(o),
              lumen: (o.eigenschaften['lumen'] as num?)?.toDouble() ?? 800,
              winkel: (o.eigenschaften['winkel'] as num?)?.toDouble() ?? 90,
            ),
      ];
      if (leuchten.isNotEmpty) {
        final ziel = ((store.einstellung<Map>('licht_ziel')?[raum.id] as num?)?.toInt() ?? zielBeleuchtung(raum.name)).toDouble();
        final e = lichtraster(umriss, leuchten, raster: math.max(150, polygonUmfang(umriss) / 80));
        if (e.mittel < ziel * r.lichtAnteilZiel / 100) {
          h.add(PruefHinweis(bereich: 'Licht', text: '${raum.name}: Em ${e.mittel.round()} lx bei Zielwert ${ziel.round()} lx.'));
        }
      }
      final geraete = <TechnikGeraet>[];
      for (final o in imRaum) {
        final m = o.eigenschaften['masse'];
        if (m is! List || m.length < 3) continue;
        final f = Map<String, dynamic>.from(o.eigenschaften['freiraum'] as Map? ?? const {});
        geraete.add((
          id: o.id,
          name: o.eigenschaften['geraet'] as String? ?? o.kennung,
          x: o.punkte.first.x,
          y: o.punkte.first.y,
          b: (m[0] as num).toInt(),
          t: (m[1] as num).toInt(),
          drehung: (o.eigenschaften['drehung'] as num?)?.toInt() ?? 0,
          vorn: (f['vorn'] as num?)?.toInt() ?? 0,
          links: (f['links'] as num?)?.toInt() ?? 0,
          rechts: (f['rechts'] as num?)?.toInt() ?? 0,
        ));
      }
      for (final t in technikKollisionen(geraete, raum: umriss)) {
        h.add(PruefHinweis(bereich: 'Technikraum', text: '${raum.name}: $t'));
      }
      final elektro = [
        for (final o in imRaum)
          if (gewerke[typen[o.typId]?.gewerkId] == 'EL' && o.eigenschaften['masse'] == null)
            (name: o.kennung, x: o.punkte.first.x, y: o.punkte.first.y, z: ueberFfb(o)),
      ];
      final wasser = [
        for (final o in objekte)
          if (o.punkte.length >= 2 && const {'SA', 'HZ', 'FH'}.contains(gewerke[typen[o.typId]?.gewerkId]) && typen[o.typId]?.geometrie == Geometrieart.linie)
            (name: o.kennung, punkte: o.punkte, z: o.zPunkte != null ? o.zPunkte!.reduce(math.max) - hoehen.ffb.toDouble() : ueberFfb(o)),
      ];
      for (final t in elektroUnterWasser(elektro, wasser, abstand: r.minAbstandWasserElektro.toDouble())) {
        h.add(PruefHinweis(bereich: 'Elektro', text: '${raum.name}: $t'));
      }
    }
  }
  // Schränke
  for (final s in schraenke) {
    final geraete = store.schrankGeraete(s.id);
    final kreise = store.stromkreise(s.id);
    final b = belegung(s, geraete);
    for (final t in schrankHinweise(s, geraete, kreise)) {
      if (t.startsWith('Weniger als 20 % Reserve')) continue; // eigener Grenzwert unten
      h.add(PruefHinweis(bereich: 'Verteiler ${s.kennzeichen}', text: t));
    }
    if (b.reserve * 100 < r.minReserveSchrank) {
      h.add(PruefHinweis(bereich: 'Verteiler ${s.kennzeichen}', text: 'Reserve ${(b.reserve * 100).round()} % unter ${r.minReserveSchrank} %.'));
    }
    for (final t in verdrahtungsHinweise(s, geraete, kreise)) {
      h.add(PruefHinweis(bereich: 'Verteiler ${s.kennzeichen}', text: t));
    }
  }
  // KNX
  final gas = [
    for (final m in (store.einstellung<List>('knx_gruppenadressen') ?? const [])) Gruppenadresse.ausJson(Map<String, dynamic>.from(m as Map)),
  ];
  for (final a in doppelteAdressen(gas)) {
    h.add(PruefHinweis(bereich: 'KNX', text: 'Gruppenadresse $a doppelt vergeben.'));
  }
  // Schächte
  for (final m in (store.einstellung<List>('schaechte') ?? const [])) {
    final s = Schacht.ausJson(Map<String, dynamic>.from(m as Map));
    for (final t in schachtHinweise(s)) {
      h.add(PruefHinweis(bereich: 'Schacht ${s.name}', text: t));
    }
  }
  return h;
}

/// Kurzer Projektsteckbrief als Text für das Sprachmodell (nur Zahlen und
/// Bezeichnungen, keine Fotos oder Dateien).
String projektSteckbrief(ProjectStore store, List<PruefHinweis> regeln) {
  final b = StringBuffer('Projekt: ${store.name}\n');
  final typen = {for (final t in store.objekttypen()) t.id: t};
  for (final geb in store.gebaeude()) {
    for (final g in store.geschosse(geb.id)) {
      b.writeln('Geschoss ${g.kuerzel} ${g.name}:');
      final objekte = store.objekte(g.id);
      for (final r in store.raeume(g.id)) {
        final imRaum = objekte.where((o) => o.raumId == r.id);
        final zaehlung = <String, int>{};
        for (final o in imRaum) {
          final n = typen[o.typId]?.name ?? '?';
          zaehlung[n] = (zaehlung[n] ?? 0) + 1;
        }
        b.writeln('- ${r.name} (${r.art.label}${r.flaeche == null ? '' : ', ${(r.flaeche! / 1e6).toStringAsFixed(1)} m²'}): '
            '${zaehlung.entries.map((e) => '${e.value}× ${e.key}').join(', ')}');
      }
    }
  }
  for (final s in store.schraenke()) {
    final g = store.schrankGeraete(s.id);
    b.writeln('Schrank =${s.kennzeichen} ${s.name}: ${g.length} Geräte, ${store.stromkreise(s.id).length} Stromkreise.');
  }
  if (regeln.isNotEmpty) {
    b.writeln('Bereits von festen Regeln gefunden:');
    for (final r in regeln.take(30)) {
      b.writeln('- [${r.bereich}] ${r.text}');
    }
  }
  return b.toString();
}
