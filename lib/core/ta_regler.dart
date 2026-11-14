import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'ki.dart' show adresseLokal;

/// Anbindung Technische Alternative (UVR16x2, UVR610, RSM610 … über C.M.I.):
/// Ein-/Ausgangsbelegung mit Kapazitätswarnung, Fühlerplan mit Kabelweg,
/// Vorlage für die TAPPS2-Programmierung, Platzhalter für die C.M.I.-
/// Schemaseite und Live-Werte über die C.M.I.-JSON-Schnittstelle (nur lesend).
/// Kapazitäten sind Richtwerte – Datenblatt prüfen.

/// Reglertypen: Eingänge, Ausgänge (davon Relais), Anzeige.
const taRegler = <String, ({int eingaenge, int ausgaenge, int relais, String hinweis})>{
  'UVR16x2': (eingaenge: 16, ausgaenge: 16, relais: 11, hinweis: '16 Eingänge, 16 Ausgänge (11 Relais, 5 analog/PWM), CAN, DL-Bus'),
  'UVR610': (eingaenge: 6, ausgaenge: 10, relais: 6, hinweis: '6 Eingänge, 10 Ausgänge'),
  'RSM610': (eingaenge: 6, ausgaenge: 8, relais: 4, hinweis: 'Erweiterung am CAN-Bus: 6 Eingänge, 4 Relais, 4 analog'),
  'UVR1611': (eingaenge: 16, ausgaenge: 14, relais: 11, hinweis: 'Vorgänger: 16 Eingänge, 14 Ausgänge'),
  'CAN-I/O45': (eingaenge: 4, ausgaenge: 5, relais: 3, hinweis: 'CAN-Ein-/Ausgangsmodul'),
};

/// Fühler- und Signaltypen für Eingänge.
const taEingangsTypen = ['PT1000', 'KTY', 'Digital (Kontakt)', 'Impuls (Volumenstrom)', '0–10 V', 'Raumsensor RAS', 'Strahlungssensor GBS'];

/// Ausgangsarten.
const taAusgangsTypen = ['Pumpe (Relais)', 'Pumpe (PWM / 0–10 V)', 'Mischer auf', 'Mischer zu', 'Umschaltventil', 'Brenner / WP-Freigabe', 'Relais allgemein', 'Analog 0–10 V'];

class TaKanal {
  TaKanal({required this.nr, required this.regler, required this.eingang, required this.typ, this.name = '', this.objekt, this.kabelM});
  final int nr;
  final String regler; // Regler-ID
  final bool eingang;
  final String typ;
  final String name;
  final String? objekt; // Objekt im Grundriss (Fühler, Pumpe …)
  final double? kabelM; // von Hand, sonst geschätzt

  String get kurz => '${eingang ? 'E' : 'A'}$nr';
  Map<String, dynamic> toJson() => {'nr': nr, 'regler': regler, 'e': eingang, 'typ': typ, if (name.isNotEmpty) 'name': name, if (objekt != null) 'objekt': objekt, if (kabelM != null) 'kabel_m': kabelM};
  static TaKanal ausJson(Map m) => TaKanal(
        nr: (m['nr'] as num).toInt(),
        regler: '${m['regler']}',
        eingang: m['e'] == true,
        typ: '${m['typ'] ?? ''}',
        name: '${m['name'] ?? ''}',
        objekt: m['objekt'] as String?,
        kabelM: (m['kabel_m'] as num?)?.toDouble(),
      );
}

class TaGeraet {
  TaGeraet({required this.id, required this.typ, this.name = '', this.objekt, this.canKnoten = 1});
  final String id, typ, name;
  final String? objekt; // Regler-Ort im Grundriss
  final int canKnoten;
  Map<String, dynamic> toJson() => {'id': id, 'typ': typ, if (name.isNotEmpty) 'name': name, if (objekt != null) 'objekt': objekt, 'knoten': canKnoten};
  static TaGeraet ausJson(Map m) => TaGeraet(id: '${m['id']}', typ: '${m['typ'] ?? 'UVR16x2'}', name: '${m['name'] ?? ''}', objekt: m['objekt'] as String?, canKnoten: (m['knoten'] as num?)?.toInt() ?? 1);
}

/// Belegung (Projekteinstellung `ta_regelung`).
class TaBelegung {
  TaBelegung(this.geraete, this.kanaele, {this.cmi = ''});
  final List<TaGeraet> geraete;
  final List<TaKanal> kanaele;
  final String cmi; // Adresse des C.M.I. im Heimnetz

  Map<String, dynamic> toJson() => {'geraete': [for (final g in geraete) g.toJson()], 'kanaele': [for (final k in kanaele) k.toJson()], if (cmi.isNotEmpty) 'cmi': cmi};
  static TaBelegung ausJson(Map? m) => TaBelegung(
        [for (final g in (m?['geraete'] as List? ?? const [])) if (g is Map) TaGeraet.ausJson(g)],
        [for (final k in (m?['kanaele'] as List? ?? const [])) if (k is Map) TaKanal.ausJson(k)],
        cmi: '${m?['cmi'] ?? ''}',
      );
}

/// Kapazität prüfen: belegte Ein-/Ausgänge je Regler gegen den Typ.
List<String> taKapazitaet(TaBelegung b) {
  final h = <String>[];
  for (final g in b.geraete) {
    final k = taRegler[g.typ];
    if (k == null) continue;
    final e = b.kanaele.where((x) => x.regler == g.id && x.eingang).toList();
    final a = b.kanaele.where((x) => x.regler == g.id && !x.eingang).toList();
    final relais = a.where((x) => !x.typ.contains('PWM') && !x.typ.contains('Analog')).length;
    final n = g.name.isEmpty ? g.typ : g.name;
    if (e.length > k.eingaenge) h.add('$n: ${e.length} Eingänge belegt, nur ${k.eingaenge} vorhanden – Erweiterung (z. B. RSM610/CAN-I/O) nötig');
    if (a.length > k.ausgaenge) h.add('$n: ${a.length} Ausgänge belegt, nur ${k.ausgaenge} vorhanden');
    if (relais > k.relais) h.add('$n: $relais Relaisausgänge, nur ${k.relais} Relais');
    if (e.length > k.eingaenge * 0.85 && e.length <= k.eingaenge) h.add('$n: Eingänge fast voll (${e.length}/${k.eingaenge}) – Reserve einplanen');
    final doppelt = <int>{};
    for (final x in [...e, ...a]) {
      if (!doppelt.add(x.nr * (x.eingang ? 1 : -1))) h.add('$n: ${x.kurz} doppelt belegt');
    }
  }
  return h;
}

/// Kabelweg Regler ↔ Fühler/Aktor (m), rechtwinklig plus Steigstrecken und Reserve.
double taKabelweg((double, double) regler, (double, double) ziel, {double hoehenM = 2.5, double reserveM = 1}) =>
    ((regler.$1 - ziel.$1).abs() + (regler.$2 - ziel.$2).abs()) / 1000 + hoehenM + reserveM;

/// Fühlerkabel je Eingangstyp.
String taKabeltyp(String typ) => typ.contains('Impuls') || typ.contains('0–10') ? 'LiYCY 4×0,5 (geschirmt)' : (typ.contains('Raumsensor') ? 'LiYY 4×0,5' : 'LiYY 2×0,5');

/// Vorlage für TAPPS2: Funktionen mit ihren Ein-/Ausgängen als Text (zum
/// Nachbauen in TAPPS2; das Dateiformat von TAPPS2 ist nicht offen).
String tapps2Vorlage(TaBelegung b, {String projekt = ''}) {
  final s = StringBuffer('TAPPS2-Vorlage${projekt.isEmpty ? '' : ' – $projekt'}\n')..writeln('Erzeugt mit BauSpur. Funktionen in TAPPS2 anlegen und die Ein-/Ausgänge wie folgt verknüpfen.\n');
  for (final g in b.geraete) {
    s.writeln('== ${g.name.isEmpty ? g.typ : g.name} (${g.typ}, CAN-Knoten ${g.canKnoten}) ==');
    final e = b.kanaele.where((x) => x.regler == g.id && x.eingang).toList()..sort((a, c) => a.nr.compareTo(c.nr));
    final a = b.kanaele.where((x) => x.regler == g.id && !x.eingang).toList()..sort((a, c) => a.nr.compareTo(c.nr));
    s.writeln('Eingänge:');
    for (final k in e) {
      s.writeln('  ${k.kurz.padRight(4)} ${k.typ.padRight(22)} ${k.name}');
    }
    s.writeln('Ausgänge:');
    for (final k in a) {
      s.writeln('  ${k.kurz.padRight(4)} ${k.typ.padRight(22)} ${k.name}');
    }
    // Funktionsvorschläge aus Namen
    final f = <String>[];
    String? ein(RegExp r) => e.where((k) => r.hasMatch(k.name.toLowerCase())).map((k) => k.kurz).firstOrNull;
    String? aus(RegExp r) => a.where((k) => r.hasMatch(k.name.toLowerCase())).map((k) => k.kurz).firstOrNull;
    final aussen = ein(RegExp('außen|aussen'));
    for (final hk in e.where((k) => RegExp(r'vorlauf.*(hk|heizkreis)|(hk|heizkreis).*vorlauf').hasMatch(k.name.toLowerCase()))) {
      f.add('Heizkreisregler: Außentemp ${aussen ?? '?'}, Vorlauf ${hk.kurz}, Pumpe ${aus(RegExp('pumpe.*(hk|heiz)')) ?? '?'}, Mischer ${aus(RegExp('mischer')) ?? '?'}');
    }
    if (ein(RegExp('speicher|tww|warmwasser')) != null) f.add('Ladepumpe/Warmwasser: Speicherfühler ${ein(RegExp('speicher|tww|warmwasser'))}, Freigabe ${aus(RegExp('lade|tww|warmwasser|umschalt')) ?? '?'}');
    if (ein(RegExp('kollektor|solar')) != null) f.add('Solarregelung: Kollektor ${ein(RegExp('kollektor|solar'))}, Speicher unten ${ein(RegExp('unten')) ?? '?'}, Pumpe ${aus(RegExp('solar')) ?? '?'}');
    if (f.isNotEmpty) {
      s.writeln('Funktionsvorschläge:');
      for (final x in f) {
        s.writeln('  - $x');
      }
    }
    s.writeln();
  }
  return s.toString();
}

/// Live-Werte über die C.M.I.-JSON-Schnittstelle (nur lesend, nur Heimnetz).
/// Liefert „E1“ → Wert-Text je Knoten. Zugang wie im C.M.I. (Benutzer/Passwort).
Future<Map<String, String>> cmiLesen(String adresse, int knoten, String benutzer, String passwort, {HttpClient? client}) async {
  final basis = adresse.startsWith('http') ? adresse : 'http://$adresse';
  if (!adresseLokal(basis)) throw StateError('C.M.I. nur im Heimnetz abfragen.');
  final c = client ?? HttpClient();
  try {
    final uri = Uri.parse('${basis.replaceAll(RegExp(r'/+$'), '')}/INCLUDE/api.cgi?jsonnode=$knoten&jsonparam=I,O');
    final r = await c.getUrl(uri).timeout(const Duration(seconds: 8));
    r.headers.set(HttpHeaders.authorizationHeader, 'Basic ${base64Encode(utf8.encode('$benutzer:$passwort'))}');
    final a = await r.close().timeout(const Duration(seconds: 15));
    final text = await a.transform(utf8.decoder).join();
    return cmiAntwortLesen(text);
  } finally {
    if (client == null) c.close(force: true);
  }
}

/// Antwort der C.M.I.-JSON-API lesen: Data.Inputs / Data.Outputs mit Number und Value.
Map<String, String> cmiAntwortLesen(String json) {
  final aus = <String, String>{};
  final m = jsonDecode(json) as Map<String, dynamic>;
  final data = m['Data'] as Map? ?? const {};
  for (final (key, praefix) in const [('Inputs', 'E'), ('Outputs', 'A')]) {
    for (final e in (data[key] as List? ?? const [])) {
      if (e is! Map) continue;
      final nr = e['Number'];
      final v = e['Value'] as Map? ?? const {};
      final wert = v['Value'];
      final einheit = '${v['Unit'] ?? ''}';
      final txt = wert is num ? (wert == wert.roundToDouble() ? wert.toInt().toString() : wert.toStringAsFixed(1).replaceAll('.', ',')) : '$wert';
      aus['$praefix$nr'] = '$txt ${_einheit(einheit)}'.trim();
    }
  }
  return aus;
}

String _einheit(String code) => switch (code) { '1' => '°C', '8' => '%', '3' => 'l/h', '10' => 'kW', '11' => 'kWh', '43' => '', _ => '' };

/// Ungefähre Mitte eines Punkts (x, y) – kleine Hilfe für Abstände.
double abstandMm((double, double) a, (double, double) b) => math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
