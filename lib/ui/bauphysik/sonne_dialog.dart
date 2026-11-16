import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/dach.dart';
import '../../core/raumerkennung.dart';
import '../../core/sonne.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../floorplan/dach_dialog.dart' show dachLesen;

/// Sonnenstand und Verschattung: Standort, Sonnenbahn an drei Stichtagen,
/// Sonnenstunden je Fenster (verschattet durch die eigenen Wände) und
/// Einstrahlung je Dachfläche für PV.
Future<void> sonneDialog(BuildContext context, AppState s) => showDialog<void>(context: context, builder: (_) => _Sonne(state: s));

class _Sonne extends StatefulWidget {
  const _Sonne({required this.state});
  final AppState state;
  @override
  State<_Sonne> createState() => _SonneState();
}

class _SonneState extends State<_Sonne> {
  AppState get _s => widget.state;
  Map<String, dynamic> get _ort => Map<String, dynamic>.from(_s.store!.einstellung<Map>('standort') ?? const {});
  double get _lat => (_ort['lat'] as num?)?.toDouble() ?? 51.0;
  double get _lon => (_ort['lon'] as num?)?.toDouble() ?? 10.0;
  double get _nord => (_s.store!.einstellung<num>('norden_grad') ?? 0).toDouble();

  void _ortSetzen(String k, num? v) {
    _s.store!.einstellungSetzen('standort', {..._ort, k: v}..removeWhere((k, v) => v == null));
    _s.geaendert();
    setState(() {});
  }

  /// Verglaste Öffnungen eines Geschosses mit Mitte, Außennormale und Höhe.
  List<({String name, double px, double py, double nx, double ny, double z, String wandId})> _fenster(String gid) {
    final store = _s.store!;
    final waende = {for (final w in store.waende(gid)) w.id: w};
    final raeume = [for (final r in store.raeume(gid)) if (r.umriss != null && r.art == RaumArt.raum) r];
    final aus = <({String name, double px, double py, double nx, double ny, double z, String wandId})>[];
    for (final o in store.oeffnungen(gid)) {
      if (!o.art.verglast) continue;
      final w = waende[o.wandId];
      if (w == null || w.laenge < 1) continue;
      final ux = (w.x2 - w.x1) / w.laenge, uy = (w.y2 - w.y1) / w.laenge;
      final t = o.abstand + o.breite / 2;
      final mx = w.x1 + ux * t, my = w.y1 + uy * t;
      final d = w.dicke / 2 + 60;
      Raum? an(double x, double y) => raeume.where((r) => punktInPolygon(Punkt(x, y), r.umriss!)).firstOrNull;
      final l = an(mx + uy * d, my - ux * d), r = an(mx - uy * d, my + ux * d);
      final innen = l ?? r;
      if (innen == null || (l != null && r != null)) continue;
      final nx = l == null ? uy : -uy, ny = l == null ? -ux : ux; // zur raumlosen Seite
      aus.add((
        name: '${o.art.label} ${innen.name} (${(o.breite / 10).round()}×${(o.hoehe / 10).round()})',
        px: mx + nx * w.dicke / 2,
        py: my + ny * w.dicke / 2,
        nx: nx,
        ny: ny,
        z: o.bruestung + o.hoehe / 2,
        wandId: w.id,
      ));
    }
    return aus;
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.store!;
    final gid = _s.geschossId;
    final jahr = DateTime.now().year;
    final tage = [(DateTime(jahr, 3, 21), '21.3.'), (DateTime(jahr, 6, 21), '21.6.'), (DateTime(jahr, 12, 21), '21.12.')];
    final fenster = gid == null ? const <({String name, double px, double py, double nx, double ny, double z, String wandId})>[] : _fenster(gid);
    final g = gid == null ? null : store.geschoss(gid);
    final hoehe = g == null ? 2600.0 : (g.hoehen.rohdecke - g.hoehen.ffb).toDouble();
    final wandListe = gid == null ? const <Wand>[] : store.waende(gid);
    // PV: Dachflächen aller Geschosse mit Dachform
    final pv = <(String, double, double)>[];
    for (final geb in store.gebaeude()) {
      for (final gs in store.geschosse(geb.id)) {
        final d = dachLesen(store, gs.id);
        if (!d.aktiv) continue;
        final seiten = switch (d.form) {
          Dachform.pult => [d.hochSeiteVorne ? (d.firstInX ? 180.0 : 90.0) : (d.firstInX ? 0.0 : 270.0)],
          Dachform.walm || Dachform.zelt => [0.0, 90.0, 180.0, 270.0],
          _ => d.firstInX ? [0.0, 180.0] : [90.0, 270.0],
        };
        for (final planWinkel in seiten) {
          // Außennormale der Dachfläche im Plan (0 = oben) → Kompass
          final richtung = ((planWinkel - _nord) % 360 + 360) % 360;
          final himmel = const ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'][((richtung + 22.5) ~/ 45) % 8];
          pv.add(('${gs.name}: Dachfläche $himmel (${d.neigung.round()}°)', d.neigung, richtung));
        }
      }
    }
    return AlertDialog(
      title: const Text('Sonne und Verschattung'),
      content: SizedBox(
        width: 1000,
        height: 620,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 420,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 10, runSpacing: 8, children: [
                for (final (k, label, wert) in [('lat', 'Breitengrad', _lat), ('lon', 'Längengrad', _lon)])
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      key: ValueKey('ort-$k'),
                      initialValue: wert.toStringAsFixed(3).replaceAll('.', ','),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]'))],
                      decoration: InputDecoration(labelText: label, suffixText: '°', isDense: true),
                      onChanged: (v) => _ortSetzen(k, double.tryParse(v.replaceAll(',', '.'))),
                    ),
                  ),
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    key: const ValueKey('nord'),
                    initialValue: '${_nord.round()}',
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))],
                    decoration: const InputDecoration(labelText: 'Norden im Plan', suffixText: '°', isDense: true, helperText: '0 = oben'),
                    onChanged: (v) {
                      store.einstellungSetzen('norden_grad', int.tryParse(v) ?? 0);
                      _s.geaendert();
                      setState(() {});
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              const Text('Standort z. B. aus Google Maps (Rechtsklick › Koordinaten). Vorgabe Mitte Deutschland.', style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
              const SizedBox(height: 8),
              Text('Sonnenbahn', style: Theme.of(context).textTheme.titleSmall),
              Expanded(child: CustomPaint(painter: _BahnPainter(_lat, _lon, [for (final t in tage) t.$1]), child: const SizedBox.expand())),
              const Text('rot 21.6. · orange 21.3./21.9. · blau 21.12. – Uhrzeiten MEZ/MESZ. In 3D: „Sonne“ einschalten zeigt Schatten zur Uhrzeit.',
                  style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ListView(children: [
              Text('Sonnenstunden je Fenster (${g?.name ?? ''}) – verschattet durch die eigenen Wände', style: Theme.of(context).textTheme.titleSmall),
              if (fenster.isEmpty) const Text('Keine Fenster mit Raum dahinter in diesem Geschoss.', style: TextStyle(fontSize: 12)),
              if (fenster.isNotEmpty)
                Table(columnWidths: const {0: FlexColumnWidth(3)}, children: [
                  TableRow(children: [
                    const Text('Fenster', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    for (final (_, n) in tage) Text(n, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  ]),
                  for (final f in fenster)
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(f.name, style: const TextStyle(fontSize: 12))),
                      for (final (tag, _) in tage)
                        Builder(builder: (_) {
                          final h = sonnenstunden(
                            breite: _lat,
                            laenge: _lon,
                            tag: tag,
                            nordGrad: _nord,
                            px: f.px,
                            py: f.py,
                            nx: f.nx,
                            ny: f.ny,
                            z: f.z,
                            hindernisse: [
                              for (final w in wandListe)
                                if (w.id != f.wandId) (ax: w.x1.toDouble(), ay: w.y1.toDouble(), bx: w.x2.toDouble(), by: w.y2.toDouble(), oben: (w.hoehe ?? hoehe).toDouble()),
                            ],
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text('${h.toStringAsFixed(1).replaceAll('.', ',')} h',
                                style: TextStyle(fontSize: 12, color: tag.month == 12 && h < 1 ? const Color(0xFFB45309) : null)),
                          );
                        }),
                    ]),
                ]),
              const Text('Wintersonne < 1 h: wenig solarer Gewinn; viel Sommersonne nach Süd/West: außenliegenden Sonnenschutz vorsehen.',
                  style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
              const Divider(height: 24),
              Text('PV: Einstrahlung je Dachfläche', style: Theme.of(context).textTheme.titleSmall),
              if (pv.isEmpty) const Text('Keine Dachform eingetragen (Grundriss › Optionen › Dachgeschoss).', style: TextStyle(fontSize: 12)),
              for (final (name, neigung, richtung) in pv)
                Builder(builder: (_) {
                  final f = pvFaktor(_lat, _lon, neigung, richtung);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(name),
                    subtitle: LinearProgressIndicator(value: f.clamp(0.0, 1.0), color: f > 0.85 ? const Color(0xFF2F9E44) : (f > 0.65 ? const Color(0xFFF59F00) : const Color(0xFFB45309))),
                    trailing: Text('${(f * 100).round()} %', style: const TextStyle(fontWeight: FontWeight.w600)),
                  );
                }),
              const Text('100 % = Süd mit 35° Neigung (bester Ertrag). Ost/West liefert meist 80–85 %, Nord deutlich weniger. Verschattung durch Bäume/Nachbarn nicht berücksichtigt.',
                  style: TextStyle(fontSize: 11, color: BsFarben.textLeise)),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
    );
  }
}

/// Sonnenbahn: x = Azimut (Ost → Süd → West), y = Höhe; Stunden als Punkte.
class _BahnPainter extends CustomPainter {
  _BahnPainter(this.lat, this.lon, this.tage);
  final double lat, lon;
  final List<DateTime> tage;

  @override
  void paint(Canvas canvas, Size size) {
    const rand = 28.0;
    final w = size.width - 2 * rand, h = size.height - 2 * rand;
    Offset p(double az, double ho) => Offset(rand + (az - 45) / 270 * w, rand + h - ho / 70 * h);
    final gitter = Paint()
      ..color = const Color(0xFFDEE2E6)
      ..strokeWidth = 1;
    for (final (az, t) in [(90.0, 'O'), (135.0, 'SO'), (180.0, 'S'), (225.0, 'SW'), (270.0, 'W')]) {
      canvas.drawLine(p(az, 0), p(az, 70), gitter);
      final tp = TextPainter(text: TextSpan(text: t, style: const TextStyle(fontSize: 10, color: BsFarben.textLeise)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, p(az, 0) + Offset(-tp.width / 2, 4));
    }
    for (final ho in [10.0, 30.0, 50.0, 70.0]) {
      canvas.drawLine(p(45, ho), p(315, ho), gitter);
      final tp = TextPainter(text: TextSpan(text: '${ho.round()}°', style: const TextStyle(fontSize: 10, color: BsFarben.textLeise)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, p(45, ho) + Offset(-tp.width - 4, -6));
    }
    const farben = [Color(0xFFF59F00), Color(0xFFE03131), Color(0xFF1C7ED6)];
    for (final (i, tag) in tage.indexed) {
      final pfad = Path();
      var erster = true;
      for (var m = 0; m <= 24 * 60; m += 10) {
        final st = sonnenstand(lat, lon, tag.add(Duration(minutes: m)));
        if (st.hoehe < 0 || st.azimut < 45 || st.azimut > 315) {
          erster = true;
          continue;
        }
        final q = p(st.azimut, st.hoehe);
        if (erster) {
          pfad.moveTo(q.dx, q.dy);
          erster = false;
        } else {
          pfad.lineTo(q.dx, q.dy);
        }
        if (m % 60 == 0) canvas.drawCircle(q, 2.5, Paint()..color = farben[i % 3]);
      }
      canvas.drawPath(pfad, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = farben[i % 3]);
    }
    final jetzt = sonnenstand(lat, lon, DateTime.now());
    if (jetzt.hoehe > 0) {
      canvas.drawCircle(p(jetzt.azimut, math.min(70, jetzt.hoehe)), 6, Paint()..color = const Color(0xFFFFD43B));
    }
  }

  @override
  bool shouldRepaint(covariant _BahnPainter old) => true;
}
