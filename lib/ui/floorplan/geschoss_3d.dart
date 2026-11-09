import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/drei_d.dart';
import '../../core/height.dart';
import '../../core/raumerkennung.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../haustechnik/technik_3d.dart';

/// Ganzes Geschoss in 3D: Wände, Geräte (mit realen Maßen, sonst Dose/Klein-
/// gerät), Leitungen mit ihrer Höhe bzw. der Höhe ihrer Verlegeebene,
/// eigene Verlegeebenen als Flächen. Kollisionen wie im Technikraum.
Future<void> geschoss3dZeigen(BuildContext context, AppState state) async {
  final store = state.store;
  final gid = state.geschossId;
  if (store == null || gid == null) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: Text('3D – ${store.geschoss(gid)?.name ?? 'Geschoss'}')),
      body: Geschoss3d(state: state, geschossId: gid),
    ),
  ));
}

class Geschoss3d extends StatelessWidget {
  const Geschoss3d({super.key, required this.state, required this.geschossId});
  final AppState state;
  final String geschossId;

  @override
  Widget build(BuildContext context) {
    final store = state.store!;
    final g = store.geschoss(geschossId);
    final waende = store.waende(geschossId);
    if (g == null || waende.isEmpty) return const Center(child: Text('Noch keine Wände in diesem Geschoss.'));
    final h = g.hoehen;
    final hoehe = (h.rohdecke - h.ffb).toDouble();
    var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    final wq = <Quader>[];
    for (final w in waende) {
      x0 = math.min(x0, math.min(w.x1, w.x2) - w.dicke / 2);
      y0 = math.min(y0, math.min(w.y1, w.y2) - w.dicke / 2);
      x1 = math.max(x1, math.max(w.x1, w.x2) + w.dicke / 2);
      y1 = math.max(y1, math.max(w.y1, w.y2) + w.dicke / 2);
      final dx = (w.x2 - w.x1).toDouble(), dy = (w.y2 - w.y1).toDouble();
      final l = math.sqrt(dx * dx + dy * dy);
      if (l < 1) continue;
      wq.add(Quader(
        id: 'wand-${w.id}',
        name: '',
        x: (w.x1 + w.x2) / 2,
        y: (w.y1 + w.y2) / 2,
        z: 0,
        b: l + w.dicke,
        t: w.dicke.toDouble(),
        h: hoehe,
        drehung: (math.atan2(dy, dx) * 180 / math.pi).round(),
      ));
    }
    final typen = {for (final t in store.objekttypen()) t.id: t};
    final gewerke = {for (final x in store.gewerke()) x.id: x};
    // eigene Verlegeebenen: Höhe über FFB (Mitte von–bis, Bezug über Rohdecke bzw. unter FFB)
    final ebenen = <String, (double, Color)>{};
    for (final e in (store.einstellung<List>('verlegeebenen') ?? const [])) {
      final m = Map<String, dynamic>.from(e as Map);
      final von = (m['von_mm'] as num?)?.toDouble(), bis = (m['bis_mm'] as num?)?.toDouble();
      if (von == null && bis == null) continue;
      final mitte = ((von ?? bis!) + (bis ?? von!)) / 2;
      final z = switch (m['bezug']) {
        'unter FFB' => -mitte,
        'unter Decke' => hoehe - mitte,
        _ => mitte - (h.ffb - h.rfb),
      };
      ebenen['${m['name']}'] = (z, Color((m['farbe'] as num?)?.toInt() ?? 0xFF1098AD));
    }
    // Standardebenen grob nach Lage
    double zLage(String? lage) => switch (lage) {
          'im Estrich' => -40,
          'unter Estrich' => -(h.ffb - h.rfb) + 20,
          'auf RFB' => -(h.ffb - h.rfb) + 10,
          'an Decke' || 'in Decke' => hoehe - 30,
          _ => ebenen[lage]?.$1 ?? 0,
        };
    double zUeberFfb(Objekt o, double vorgabe) => o.z == null || o.zBezug == null ? vorgabe : (absolut(o.z!, o.zBezug!, h) - h.ffb).toDouble();

    final farben = <String, Color>{};
    final geraete = <Quader>[];
    final leitungen = <Leitung3d>[];
    for (final o in store.objekte(geschossId)) {
      final t = typen[o.typId];
      if (t == null || o.punkte.isEmpty) continue;
      final farbe = Color(gewerke[t.gewerkId]?.farbe ?? 0xFF868E96);
      farben[o.id] = farbe;
      switch (t.geometrie) {
        case Geometrieart.linie:
          if (o.punkte.length < 2) continue;
          final zs = o.zPunkte;
          final z0 = zUeberFfb(o, zLage(o.lage));
          leitungen.add(Leitung3d(
            id: o.id,
            name: o.kennung,
            durchmesser: (o.eigenschaften['breite_mm'] as num?)?.toDouble() ?? 20,
            punkte: [
              for (var i = 0; i < o.punkte.length; i++) V3(o.punkte[i].x, o.punkte[i].y, zs != null && i < zs.length ? zs[i] - h.ffb.toDouble() : z0),
            ],
          ));
        case Geometrieart.punkt:
          final m = o.eigenschaften['masse'];
          final masse = m is List && m.length >= 3 ? [for (final x in m) (x as num).toDouble()] : [80.0, 60.0, 80.0];
          geraete.add(Quader(
            id: o.id,
            name: o.kennung,
            x: o.punkte.first.x,
            y: o.punkte.first.y,
            z: zUeberFfb(o, m is List ? 0 : 300),
            b: masse[0],
            t: masse[1],
            h: masse[2],
            drehung: (o.eigenschaften['drehung'] as num?)?.toInt() ?? 0,
          ));
        case Geometrieart.flaeche:
          break;
      }
    }
    return Raum3dAnsicht(
      key: ValueKey('g3d-$geschossId-${state.revision}'),
      umriss: [Punkt(x0, y0), Punkt(x1, y0), Punkt(x1, y1), Punkt(x0, y1)],
      raumhoehe: hoehe,
      geraete: geraete,
      leitungen: leitungen,
      farben: farben,
      waende: wq,
      ebenen: [for (final e in ebenen.entries) (e.key, e.value.$1, e.value.$2)],
    );
  }
}
