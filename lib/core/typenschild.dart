import 'dart:convert';

/// Typenschild lesen: aus dem erkannten Text (Windows-Texterkennung offline
/// oder lokale Bild-KI) Hersteller, Typ, Seriennummer und Kennwerte ziehen.
class Typenschild {
  Typenschild(this.werte);

  /// Schlüssel: hersteller, typ, seriennummer, artikelnummer, baujahr,
  /// leistung_w, spannung_v, strom_a, frequenz_hz, schutzart, druck_bar,
  /// volumen_l, kaeltemittel, gewicht_kg.
  final Map<String, Object> werte;

  bool get leer => werte.isEmpty;

  static const felder = <String, String>{
    'hersteller': 'Hersteller',
    'typ': 'Typ / Modell',
    'seriennummer': 'Seriennummer',
    'artikelnummer': 'Artikelnummer',
    'baujahr': 'Baujahr',
    'leistung_w': 'Leistung (W)',
    'spannung_v': 'Spannung (V)',
    'strom_a': 'Strom (A)',
    'frequenz_hz': 'Frequenz (Hz)',
    'schutzart': 'Schutzart',
    'druck_bar': 'max. Druck (bar)',
    'volumen_l': 'Inhalt (l)',
    'kaeltemittel': 'Kältemittel',
    'gewicht_kg': 'Gewicht (kg)',
  };
}

/// Bekannte Hersteller (Haustechnik, Elektro, Sanitär) – Treffer im Text gewinnt.
const _hersteller = [
  'Viessmann', 'Vaillant', 'Buderus', 'Bosch', 'Wolf', 'Stiebel Eltron', 'Junkers', 'Daikin', 'Mitsubishi', 'Panasonic', 'Samsung', 'LG',
  'Nibe', 'Alpha Innotec', 'Weishaupt', 'Brötje', 'Remeha', 'Grundfos', 'Wilo', 'Oventrop', 'Danfoss', 'Honeywell', 'Siemens', 'ABB',
  'Hager', 'Schneider', 'Eaton', 'Gira', 'Jung', 'Busch-Jaeger', 'Theben', 'MDT', 'Zehnder', 'Helios', 'Pluggit', 'Maico', 'Vallox',
  'Geberit', 'Grohe', 'Hansgrohe', 'Kermi', 'Purmo', 'Uponor', 'Rehau', 'Viega', 'Technische Alternative', 'Fronius', 'SMA', 'Kostal',
  'AEG', 'Clage', 'Dimplex', 'Glen Dimplex', 'Ochsner', 'Lambda', 'iDM', 'Hoval', 'Elco', 'Rotex', 'Fujitsu', 'Toshiba', 'Gree',
];

double? _zahl(String s) => double.tryParse(s.replaceAll(' ', '').replaceAll(',', '.'));

/// Typenschild aus Text lesen (Regeln, ohne KI).
Typenschild typenschildLesen(String text) {
  final w = <String, Object>{};
  final t = text.replaceAll('\r', '');
  final klein = t.toLowerCase();
  for (final h in _hersteller) {
    if (klein.contains(h.toLowerCase())) {
      w['hersteller'] = h;
      break;
    }
  }
  String? nach(List<String> marken, {String muster = r'([A-Za-z0-9][A-Za-z0-9 ./\-]{1,40})'}) {
    for (final m in marken) {
      final r = RegExp('(?:$m)[\\s:.#]*$muster', caseSensitive: false).firstMatch(t);
      if (r != null) return r.group(1)!.trim().split(RegExp(r'\s{2,}|\n')).first.trim();
    }
    return null;
  }

  final sn = nach([r'S/?N', r'Ser\.?\s*-?Nr', r'Serien-?nr\.?', r'Seriennummer', r'Serial(?:\s*No\.?)?', r'Fabr\.?\s*-?Nr\.?', r'F\.?-?Nr\.?'],
      muster: r'([A-Za-z0-9][A-Za-z0-9\-/]{3,30})');
  if (sn != null) w['seriennummer'] = sn;
  final typ = nach([r'Typ(?:e)?', r'Type', r'Modell', r'Model', r'Bez\.?']);
  if (typ != null) w['typ'] = typ;
  final art = nach([r'Art\.?\s*-?Nr\.?', r'Artikel-?nr\.?', r'Best\.?\s*-?Nr\.?', r'Part\s*No\.?', r'Mat\.?\s*-?Nr\.?'], muster: r'([A-Za-z0-9][A-Za-z0-9.\-/]{3,30})');
  if (art != null) w['artikelnummer'] = art;
  final bj = RegExp(r'(?:Baujahr|BJ|Herst(?:ell)?(?:jahr|datum)|Prod\.?\s*(?:date|datum)|Year)\s*[:.]?\s*(?:\d{1,2}[./])?((?:19|20)\d{2})', caseSensitive: false).firstMatch(t);
  if (bj != null) w['baujahr'] = int.parse(bj.group(1)!);
  // Kennwerte mit Einheit
  final kw = RegExp(r'(\d+(?:[.,]\d+)?)\s*kW\b').allMatches(t).map((m) => _zahl(m.group(1)!)).whereType<double>().toList();
  final ww = RegExp(r'(\d{2,5}(?:[.,]\d+)?)\s*W\b').allMatches(t).map((m) => _zahl(m.group(1)!)).whereType<double>().toList();
  if (kw.isNotEmpty) {
    w['leistung_w'] = (kw.reduce((a, b) => a > b ? a : b) * 1000).round();
  } else if (ww.isNotEmpty) {
    w['leistung_w'] = ww.reduce((a, b) => a > b ? a : b).round();
  }
  final v = RegExp(r'(\d{2,3})(?:\s*[-/~]\s*\d{2,3})?\s*V\b(?!A)').firstMatch(t);
  if (v != null) w['spannung_v'] = int.parse(v.group(1)!);
  final a = RegExp(r'(\d+(?:[.,]\d+)?)\s*A\b').firstMatch(t);
  if (a != null) w['strom_a'] = _zahl(a.group(1)!)!;
  final hz = RegExp(r'(50|60)\s*Hz', caseSensitive: false).firstMatch(t);
  if (hz != null) w['frequenz_hz'] = int.parse(hz.group(1)!);
  final ip = RegExp(r'\bIP\s?([0-9X]{2}[A-Z]?)\b').firstMatch(t);
  if (ip != null) w['schutzart'] = 'IP${ip.group(1)}';
  final bar = RegExp(r'(\d+(?:[.,]\d+)?)\s*bar\b', caseSensitive: false).allMatches(t).map((m) => _zahl(m.group(1)!)).whereType<double>().toList();
  if (bar.isNotEmpty) w['druck_bar'] = bar.reduce((a, b) => a > b ? a : b);
  final l = RegExp(r'(\d{1,4}(?:[.,]\d+)?)\s*(?:l|Liter|Ltr)\b').firstMatch(t);
  if (l != null) w['volumen_l'] = _zahl(l.group(1)!)!;
  final km = RegExp(r'\bR\s?-?(32|410A|290|744|134a|407C|454B|1234yf)\b', caseSensitive: false).firstMatch(t);
  if (km != null) w['kaeltemittel'] = 'R${km.group(1)}';
  final kg = RegExp(r'(\d+(?:[.,]\d+)?)\s*kg\b').firstMatch(t);
  if (kg != null) w['gewicht_kg'] = _zahl(kg.group(1)!)!;
  return Typenschild(w);
}

/// Anfrage an die Bild-KI.
const kiTypenschildAnfrage = 'Lies dieses Typenschild. Antworte NUR mit JSON mit den Schlüsseln, die du sicher erkennst: '
    '{"hersteller","typ","seriennummer","artikelnummer","baujahr","leistung_w","spannung_v","strom_a","schutzart","druck_bar","volumen_l","kaeltemittel"}. '
    'Leistung in Watt. Erfinde nichts.';

/// Antwort der KI in ein Typenschild übersetzen.
Typenschild? kiTypenschildLesen(String antwort) {
  final m = RegExp(r'\{[\s\S]*\}').firstMatch(antwort);
  if (m == null) return null;
  try {
    final j = jsonDecode(m.group(0)!) as Map<String, dynamic>;
    final w = <String, Object>{};
    for (final k in Typenschild.felder.keys) {
      final v = j[k];
      if (v == null || '$v'.trim().isEmpty || '$v' == 'null') continue;
      w[k] = v is num ? v : '$v'.trim();
    }
    return Typenschild(w);
  } catch (_) {
    return null;
  }
}

/// Zwei Lesungen zusammenführen: [vorrang] gewinnt, fehlende Werte kommen aus [rest].
Typenschild typenschildVereinen(Typenschild vorrang, Typenschild rest) => Typenschild({...rest.werte, ...vorrang.werte});
