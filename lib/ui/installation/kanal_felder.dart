import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../../core/kanal_montage.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../bauteile/bauelement_wahl.dart';
import '../widgets.dart';

/// Maße eines Kabelkanal-Objekts aus Bibliothek bzw. eigenen Angaben.
KanalMasse kanalMasse(AppState s, Objekt o) {
  final e = o.eigenschaften;
  final bel = s.bibliothek.fuerProjekt(s.store!, e['kanal'] as String?);
  double z(String k, String bk, double v) => (e[k] as num?)?.toDouble() ?? bel?.zahl(bk)?.toDouble() ?? v;
  return KanalMasse(z('kanal_b', 'breite', 40), z('kanal_t', 'tiefe', 40),
      kammern: ((e['kammern'] as num?) ?? bel?.zahl('kammern') ?? 1).round(), stange: z('stange_mm', 'stange', 2000));
}

/// Außendurchmesser aller Kabel/Rohre im Kanal: eigene Kabelliste plus
/// Leitungen, die dem Kanal zugeordnet sind.
List<double> kanalBelegung(AppState s, Objekt kanal, List<Objekt> alle) {
  final store = s.store!;
  double d(String? id) => s.bibliothek.fuerProjekt(store, id)?.zahl('aussendurchmesser')?.toDouble() ?? 0;
  final aus = <double>[for (final k in (kanal.eigenschaften['kabel_liste'] as List? ?? const [])) d('$k')];
  for (final o in alle) {
    if (o.eigenschaften['kanal'] != kanal.id || o.id == kanal.id) continue;
    final rohr = d(o.eigenschaften['rohr'] as String?);
    if (rohr > 0) {
      aus.add(rohr);
    } else {
      aus.addAll([for (final k in (o.eigenschaften['kabel_liste'] as List? ?? const [])) d('$k')]);
      if ((o.eigenschaften['kabel_liste'] as List? ?? const []).isEmpty && (o.eigenschaften['breite_mm'] as num? ?? 0) > 0) aus.add((o.eigenschaften['breite_mm'] as num).toDouble());
    }
  }
  return [for (final x in aus) if (x > 0) x];
}

/// Formteile eines Kanals (Ecken, Flachwinkel, Endkappen, Abzweige, Stoßstellen).
Map<String, int> kanalFormteileVon(AppState s, Objekt o, List<Objekt> alle, List<Raum> raeume, Map<String, Objekttyp> typen) {
  final m = kanalMasse(s, o);
  // Abzweige: ein anderer Kanal endet auf diesem
  var abzweige = 0, enden = 2;
  for (final x in alle) {
    if (x.id == o.id || typen[x.typId]?.kuerzel != 'KK' || x.punkte.length < 2) continue;
    for (final p in [x.punkte.first, x.punkte.last]) {
      for (var i = 0; i + 1 < o.punkte.length; i++) {
        final a = o.punkte[i], b = o.punkte[i + 1];
        final d = b - a;
        final l2 = d.skalar(d);
        if (l2 < 1) continue;
        final t = ((p - a).skalar(d) / l2).clamp(0.0, 1.0);
        if ((a + d * t - p).laenge < 30) {
          if (t > 0.01 && t < 0.99) abzweige++;
        }
      }
    }
    // eigene Enden, die an einen anderen Kanal stoßen, brauchen keine Endkappe
    for (final p in [o.punkte.first, o.punkte.last]) {
      if ((p - x.punkte.first).laenge < 30 || (p - x.punkte.last).laenge < 30) enden--;
    }
  }
  return kanalFormteile(o.punkte, z: o.zPunkte, raeume: [for (final r in raeume) if (r.umriss != null) r.umriss!], enden: enden.clamp(0, 2), abzweige: abzweige, stange: m.stange);
}

/// Felder für einen Kabelkanal im Eigenschaftenbereich.
List<Widget> kanalFelder(BuildContext context, AppState s, Objekt o, List<Objekt> alle, List<Raum> raeume, Map<String, Objekttyp> typen,
    void Function(Map<String, Object?>) setzen) {
  final e = o.eigenschaften;
  final m = kanalMasse(s, o);
  final montage = KanalMontage.aus(e['kanal_montage']);
  final belegung = kanalBelegung(s, o, alle);
  final fuell = kanalFuellgrad(m, belegung);
  final hinweis = fuellgradHinweis(fuell);
  final formteile = kanalFormteileVon(s, o, alle, raeume, typen);
  final leitungen = [for (final x in alle) if (x.eigenschaften['kanal'] == o.id) x];
  /// Kanalmaße als Breite/Tiefe für Wandansicht, Bohr-Check und Schlitz.
  Map<String, Object?> lage(KanalMontage mo, double b, double t) => {
        'kanal_montage': mo.name,
        'breite_mm': b,
        'breite_hand': true,
        if (mo.inWand) ...{'verlegung': 'schlitz', 'tiefe_mm': 0, 'schlitz_b': (b + 10).round(), 'schlitz_t': (t + 5).round()} else ...{
          'verlegung': mo == KanalMontage.aufputz || mo == KanalMontage.bruestung || mo == KanalMontage.sockel ? 'kanal' : 'aufputz',
          'tiefe_mm': null,
          'schlitz_b': null,
          'schlitz_t': null,
        },
      };
  int? zahl(String v) => int.tryParse(v.trim());
  return [
    const SizedBox(height: 10),
    Text('Kabelkanal', style: Theme.of(context).textTheme.titleSmall),
    BauelementWahl(
      state: s,
      label: 'Kanal aus der Bibliothek',
      wert: e['kanal'] as String?,
      kategorien: const [BauelementKategorie.kabelkanal],
      nurKategorien: true,
      onChanged: (b) {
        final bb = b?.zahl('breite')?.toDouble() ?? m.breite, tt = b?.zahl('tiefe')?.toDouble() ?? m.tiefe;
        setzen({'kanal': b?.id, 'kanal_b': null, 'kanal_t': null, 'kammern': null, ...lage(montage, bb, tt)});
      },
    ),
    const SizedBox(height: 6),
    DropdownButtonFormField<KanalMontage>(
      key: ValueKey('km-${o.id}-${montage.name}'),
      initialValue: montage,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Montage', isDense: true),
      items: [for (final x in KanalMontage.values) DropdownMenuItem(value: x, child: Text(x.label, overflow: TextOverflow.ellipsis))],
      onChanged: (x) => x == null ? null : setzen(lage(x, m.breite, m.tiefe)),
    ),
    const SizedBox(height: 6),
    Row(children: [
      for (final (k, label, wert) in [('kanal_b', 'Breite', m.breite), ('kanal_t', 'Tiefe', m.tiefe)]) ...[
        Expanded(
          child: SpeicherFeld(
            key: ValueKey('$k-${o.id}-$wert'),
            initialValue: wert.round().toString(),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, suffixText: 'mm', isDense: true),
            onFieldSubmitted: (v) {
              final n = zahl(v);
              if (n == null || n <= 0) return;
              final b = k == 'kanal_b' ? n.toDouble() : m.breite, t = k == 'kanal_t' ? n.toDouble() : m.tiefe;
              setzen({k: n, ...lage(montage, b, t)});
            },
          ),
        ),
        const SizedBox(width: 6),
      ],
      SizedBox(
        width: 70,
        child: SpeicherFeld(
          key: ValueKey('kam-${o.id}-${m.kammern}'),
          initialValue: '${m.kammern}',
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Kammern', isDense: true),
          onFieldSubmitted: (v) => setzen({'kammern': zahl(v)}),
        ),
      ),
    ]),
    const SizedBox(height: 6),
    Text(
      'Belegung: ${belegung.length} Kabel/Rohre · Füllgrad ${(fuell * 100).round()} % von ${(m.nutzquerschnitt / 100).round()} cm²'
      '${leitungen.isEmpty ? '' : ' · Leitungen: ${leitungen.map((x) => x.kennung).join(', ')}'}',
      style: const TextStyle(fontSize: 12),
    ),
    if (hinweis != null) Text(hinweis, style: const TextStyle(fontSize: 11, color: Color(0xFFB45309))),
    if (montage.inWand)
      const Text('Eingelassen: Schlitz und Richtwertprüfung unter „Lage im Bauteil“ (in der Wandansicht). Bohr-Check: dort nicht bohren.',
          style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
    const SizedBox(height: 6),
    Text('Formteile (aus dem Verlauf)', style: Theme.of(context).textTheme.labelLarge),
    Wrap(spacing: 6, runSpacing: 4, children: [
      Chip(visualDensity: VisualDensity.compact, label: Text('${(o.laenge / 1000).toStringAsFixed(1).replaceAll('.', ',')} m Kanal')),
      for (final f in formteile.entries) Chip(visualDensity: VisualDensity.compact, label: Text('${f.value}× ${f.key}')),
    ]),
    const Text('Leitungen ordnest du dem Kanal bei der Leitung zu („liegt im Kabelkanal“). Kabel direkt im Kanal: unten unter Material.',
        style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
  ];
}

/// Felder für eine Montageschiene: Schiene, Halterabstand, Halter, Rohre darauf.
List<Widget> schienenFelder(BuildContext context, AppState s, Objekt o, List<Objekt> alle, void Function(Map<String, Object?>) setzen) {
  final e = o.eigenschaften;
  final bel = s.bibliothek.fuerProjekt(s.store!, e['schiene'] as String?);
  final abstand = (e['halterabstand'] as num?)?.toDouble() ?? bel?.zahl('halterabstand')?.toDouble() ?? 1000;
  final drauf = [for (final x in alle) if (x.eigenschaften['schiene'] == o.id) x];
  return [
    const SizedBox(height: 10),
    Text('Montageschiene', style: Theme.of(context).textTheme.titleSmall),
    BauelementWahl(
      state: s,
      label: 'Schiene aus der Bibliothek',
      wert: e['schiene'] as String?,
      kategorien: const [BauelementKategorie.montage],
      nurKategorien: true,
      onChanged: (b) => setzen({'schiene': b?.id}),
    ),
    const SizedBox(height: 6),
    SpeicherFeld(
      key: ValueKey('ha-${o.id}-$abstand'),
      initialValue: abstand.round().toString(),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(labelText: 'Abstand der Konsolen/Halter', suffixText: 'mm', isDense: true),
      onFieldSubmitted: (v) => setzen({'halterabstand': int.tryParse(v)}),
    ),
    const SizedBox(height: 4),
    Text('${(o.laenge / 1000).toStringAsFixed(2).replaceAll('.', ',')} m Schiene · ${schienenHalter(o.laenge, halterAbstand: abstand)} Konsolen/Halter'
        '${drauf.isEmpty ? '' : ' · darauf: ${drauf.map((x) => x.kennung).join(', ')}'}', style: const TextStyle(fontSize: 12)),
    const Text('Rohre und Leitungen legst du bei der Leitung auf die Schiene („befestigt an Montageschiene“). Die Schellen zählen dann auf der Schiene.',
        style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
  ];
}

/// Bei einer Leitung: in welchem Kanal sie liegt, an welcher Schiene sie hängt, wie viele Schellen.
List<Widget> leitungMontageFelder(BuildContext context, AppState s, Objekt o, List<Objekt> alle, Map<String, Objekttyp> typen, void Function(Map<String, Object?>) setzen) {
  final kanaele = [for (final x in alle) if (typen[x.typId]?.kuerzel == 'KK' && x.id != o.id) x];
  final schienen = [for (final x in alle) if (typen[x.typId]?.kuerzel == 'MS' && x.id != o.id) x];
  final e = o.eigenschaften;
  final store = s.store!;
  final rohr = s.bibliothek.fuerProjekt(store, e['rohr'] as String?);
  final aussen = rohr?.zahl('aussendurchmesser')?.toDouble() ?? (e['breite_mm'] as num?)?.toDouble() ?? 10;
  final art = rohr?.daten['rohrart'] as String?;
  final imKanal = e['kanal'] != null;
  final n = imKanal ? 0 : schellenAnzahl(o.punkte, befestigungsabstand(art, aussen), befestigungsabstand(art, aussen, senkrecht: true), z: o.zPunkte);
  return [
    const SizedBox(height: 10),
    Text('Führung und Befestigung', style: Theme.of(context).textTheme.titleSmall),
    if (kanaele.isNotEmpty)
      DropdownButtonFormField<String?>(
        key: ValueKey('ka-${o.id}-${e['kanal']}'),
        initialValue: kanaele.any((k) => k.id == e['kanal']) ? e['kanal'] as String : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'liegt im Kabelkanal', isDense: true),
        items: [
          const DropdownMenuItem(value: null, child: Text('– nein –')),
          for (final k in kanaele) DropdownMenuItem(value: k.id, child: Text(k.kennung)),
        ],
        onChanged: (v) => setzen({'kanal': v, if (v != null) 'schiene': null}),
      ),
    if (schienen.isNotEmpty)
      DropdownButtonFormField<String?>(
        key: ValueKey('sch-${o.id}-${e['schiene']}'),
        initialValue: schienen.any((k) => k.id == e['schiene']) ? e['schiene'] as String : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'befestigt an Montageschiene', isDense: true),
        items: [
          const DropdownMenuItem(value: null, child: Text('– nein –')),
          for (final k in schienen) DropdownMenuItem(value: k.id, child: Text(k.kennung)),
        ],
        onChanged: (v) => setzen({'schiene': v, if (v != null) 'kanal': null}),
      ),
    Text(
      imKanal
          ? 'Im Kanal – keine Schellen nötig.'
          : 'Befestigung: etwa $n Schellen (Richtwert ${befestigungsabstand(art, aussen).round()} mm waagerecht, ${befestigungsabstand(art, aussen, senkrecht: true).round()} mm senkrecht${art == null ? '' : ', $art'}).',
      style: const TextStyle(fontSize: 11, color: BsFarben.textLeise),
    ),
  ];
}

/// Punkt im Plan → Bildschirm wird hier nicht gebraucht; Hilfe für Tests.
double kanalLaenge(List<Punkt> p) {
  var l = 0.0;
  for (var i = 0; i + 1 < p.length; i++) {
    l += (p[i + 1] - p[i]).laenge;
  }
  return l;
}
