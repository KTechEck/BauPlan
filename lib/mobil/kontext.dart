import 'package:flutter/material.dart';

import 'ordner.dart';
import 'planstand.dart';

/// iPhone und iPad bekommen getrennte Oberflächen: das iPhone ist das
/// handliche Baustellen-Fernbediengerät, das iPad (kommt später ausgebaut)
/// zeigt mehr gleichzeitig (großer Plan + Seitenleiste). Entscheidung über
/// die kürzere Bildschirmseite, damit es auch für Android-Tablets passt.
enum MobilGeraet { telefon, tablet }

MobilGeraet mobilGeraet(BuildContext context) => MediaQuery.sizeOf(context).shortestSide >= 600 ? MobilGeraet.tablet : MobilGeraet.telefon;

typedef Erfassen = Future<void> Function(Map<String, dynamic> eintrag, {List<int>? foto});

/// Alles, was die Seiten der App brauchen – für iPhone und iPad gleich.
class MobilKontext {
  MobilKontext({
    required this.plan,
    required this.einstellungen,
    required this.erfasst,
    required this.abgleichen,
    required this.verbindungAendern,
    required this.wartend,
    required this.ordnerName,
    this.kamera,
  });

  final Planstand plan;
  final MobilEinstellungen einstellungen;
  final Erfassen erfasst;
  final Future<void> Function() abgleichen;
  final Future<void> Function() verbindungAendern;
  final int wartend;
  final String? ordnerName;
  final Future<List<int>?> Function(int qualitaet)? kamera;

  Map<String, dynamic>? get geschoss => plan.geschoss(einstellungen.geschoss);

  /// Gemessener Wert für ein Ziel: am PC übernommen (grün), unterwegs/offen (orange) oder null.
  ({int wert, bool uebernommen})? gemessen(Map<String, dynamic> ziel, String feld, {String? seite, String? bezug}) {
    final schluessel = aufmassSchluessel('${ziel['id']}', feld, seite: seite, bezug: bezug);
    final lokal = einstellungen.aufmass[schluessel];
    final offen = plan.aufmassOffen.where((a) =>
        a['id_ziel'] == ziel['id'] && a['feld'] == feld && (seite == null || a['seite'] == seite) && (bezug == null || a['bezug'] == bezug));
    if (offen.isNotEmpty) return (wert: (offen.last['wert'] as num).round(), uebernommen: false);
    final g = ziel['gemessen'];
    if (g is Map) {
      final v = g[bezug == null ? feld : '${feld}_$bezug'] ?? g[feld];
      if (v is num) {
        // lokal neuer gemessen als der Stand am PC?
        if (lokal != null && DateTime.tryParse('${lokal['zeit']}')?.isAfter(plan.erstellt ?? DateTime(2000)) == true) {
          return (wert: (lokal['wert'] as num).round(), uebernommen: false);
        }
        return (wert: v.round(), uebernommen: true);
      }
    }
    if (lokal != null) return (wert: (lokal['wert'] as num).round(), uebernommen: false);
    return null;
  }

  /// Ein Maß aufnehmen: lokal merken und als Erfassung schicken.
  Future<void> massSenden({
    required String ziel,
    required Map<String, dynamic> objekt,
    required String feld,
    required int wert,
    required num plan,
    String? seite,
    String? bezug,
    String? raum,
    String? text,
    Map<String, dynamic> extra = const {},
  }) async {
    einstellungen.aufmass[aufmassSchluessel('${objekt['id']}', feld, seite: seite, bezug: bezug)] = {
      'wert': wert,
      'zeit': DateTime.now().toUtc().toIso8601String(),
    };
    einstellungen.speichern();
    await erfasst({
      'art': 'aufmass',
      'ziel': ziel,
      'id': objekt['id'],
      'feld': feld,
      'wert': wert,
      'plan': plan.round(),
      if (seite != null) 'seite': seite,
      if (bezug != null) 'bezug': bezug,
      'geschoss': geschoss?['id'],
      if (raum != null) 'raum': raum,
      if (text != null && text.isNotEmpty) 'text': text,
      ...extra,
    });
  }
}

String aufmassSchluessel(String id, String feld, {String? seite, String? bezug}) => '$id|$feld|${seite ?? ''}|${bezug ?? ''}';

/// Farben für Maße: grün = gemessen und am PC übernommen, orange = gemessen,
/// noch nicht übernommen, grau = nur grob gezeichnet.
const massGemessen = Color(0xFF2F9E44);
const massOffen = Color(0xFFE8590C);
const massGrob = Color(0xFF6B7178);
