import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/bauelemente.dart';
import '../widgets.dart';
import 'profil_editor.dart';

/// Art der Skizze je Kategorie.
enum _Skizze { fenster, sonnenschutz, fensterbank, leuchte, kasten, heizkoerper, dose, rohr, fitting, armatur, reihengeraet, schalter, sanitaer, platte, fuge, teil }

_Skizze? _skizzeFuer(BauelementKategorie k) => switch (k) {
      BauelementKategorie.fenster || BauelementKategorie.balkontuer || BauelementKategorie.tuer => _Skizze.fenster,
      BauelementKategorie.sonnenschutz => _Skizze.sonnenschutz,
      BauelementKategorie.fensterbank => _Skizze.fensterbank,
      BauelementKategorie.leuchte || BauelementKategorie.sensor || BauelementKategorie.brandschutz => _Skizze.leuchte,
      BauelementKategorie.heizkoerper => _Skizze.heizkoerper,
      BauelementKategorie.dose => _Skizze.dose,
      BauelementKategorie.rohr || BauelementKategorie.kabel => _Skizze.rohr,
      BauelementKategorie.verbinder => _Skizze.fitting,
      BauelementKategorie.armatur => _Skizze.armatur,
      BauelementKategorie.schrankgeraet => _Skizze.reihengeraet,
      BauelementKategorie.elektro => _Skizze.schalter,
      BauelementKategorie.sanitaer => _Skizze.sanitaer,
      BauelementKategorie.daemmstoff || BauelementKategorie.baustoff => _Skizze.platte,
      BauelementKategorie.dichtstoff => _Skizze.fuge,
      BauelementKategorie.technik => _Skizze.kasten,
      _ => null,
    };

/// Skizze für jede Kategorie: eigene oder Kasten (mit B/H/T) bzw. allgemeines Teil.
_Skizze _skizze(BauelementKategorie k) => _skizzeFuer(k) ?? (k.felder.any((f) => f.schluessel == 'breite') ? _Skizze.kasten : _Skizze.teil);

/// Maßfelder an ihrer Stelle in der Skizze (Zeichenfläche 560 × 300).
List<(String, Offset)> _platz(_Skizze s) => switch (s) {
      _Skizze.fenster => const [
          ('breite', Offset(95, 268)),
          ('hoehe', Offset(0, 130)),
          ('ansichtsbreite', Offset(205, 30)),
          ('bautiefe', Offset(355, 8)),
          ('glasdicke', Offset(450, 150)),
          ('blattdicke', Offset(450, 210)),
        ],
      _Skizze.sonnenschutz => const [
          ('kastenhoehe', Offset(0, 40)),
          ('kastentiefe', Offset(95, 0)),
          ('fuehrung_tiefe', Offset(95, 268)),
          ('fuehrung_breite', Offset(400, 268)),
          ('fliegengitter_tiefe', Offset(220, 200)),
          ('breite', Offset(330, 8)),
          ('max_hoehe', Offset(470, 130)),
        ],
      _Skizze.fensterbank => const [
          ('ausladung', Offset(170, 40)),
          ('dicke', Offset(420, 130)),
          ('ueberstand', Offset(330, 220)),
          ('breite', Offset(60, 240)),
        ],
      _Skizze.leuchte => const [
          ('einbaudurchmesser', Offset(205, 20)),
          ('einbautiefe', Offset(420, 140)),
          ('breite', Offset(60, 250)),
          ('hoehe', Offset(0, 140)),
          ('erfassung', Offset(200, 250)),
          ('montagehoehe', Offset(0, 40)),
          ('ip', Offset(420, 40)),
        ],
      _Skizze.kasten => const [
          ('breite', Offset(120, 268)),
          ('hoehe', Offset(0, 140)),
          ('tiefe', Offset(330, 230)),
          ('freiraum_oben', Offset(120, 0)),
          ('freiraum_seite', Offset(400, 120)),
          ('freiraum_vorne', Offset(400, 268)),
        ],
      _Skizze.heizkoerper => const [
          ('baulaenge', Offset(140, 268)),
          ('bauhoehe', Offset(0, 120)),
          ('bautiefe', Offset(400, 20)),
          ('anschluss_hoehe', Offset(440, 200)),
        ],
      _Skizze.dose => const [
          ('durchmesser', Offset(120, 8)),
          ('bohrung', Offset(120, 268)),
          ('tiefe', Offset(400, 140)),
        ],
      _Skizze.rohr => const [
          ('aussendurchmesser', Offset(60, 268)),
          ('innendurchmesser', Offset(240, 268)),
          ('biegeradius', Offset(400, 268)),
          ('adern', Offset(400, 20)),
          ('querschnitt', Offset(400, 80)),
        ],
      _Skizze.fitting => const [
          ('dimension', Offset(0, 230)),
          ('dimension2', Offset(330, 10)),
          ('pn', Offset(400, 150)),
          ('temperatur', Offset(400, 210)),
        ],
      _Skizze.armatur => const [
          ('dimension', Offset(0, 230)),
          ('kvs', Offset(400, 40)),
          ('voreinstellung', Offset(400, 110)),
          ('pn', Offset(400, 180)),
        ],
      _Skizze.reihengeraet => const [
          ('te', Offset(110, 268)),
          ('pole', Offset(300, 10)),
          ('nennstrom', Offset(300, 70)),
          ('fehlerstrom', Offset(300, 130)),
          ('schaltvermoegen', Offset(300, 190)),
          ('kanaele', Offset(430, 10)),
          ('strom_kanal', Offset(430, 70)),
          ('verlust', Offset(430, 130)),
        ],
      _Skizze.schalter => const [
          ('breite', Offset(90, 268)),
          ('hoehe', Offset(0, 130)),
          ('fach', Offset(90, 0)),
          ('dosentiefe', Offset(400, 230)),
          ('nennstrom', Offset(400, 20)),
          ('leistung', Offset(400, 80)),
          ('ip', Offset(400, 140)),
        ],
      _Skizze.sanitaer => const [
          ('breite', Offset(110, 268)),
          ('hoehe', Offset(0, 120)),
          ('tiefe', Offset(330, 230)),
          ('anschluss_hoehe', Offset(430, 120)),
          ('abfluss_dn', Offset(430, 30)),
        ],
      _Skizze.platte => const [
          ('dicke', Offset(420, 150)),
          ('format', Offset(140, 0)),
          ('lambda', Offset(140, 268)),
          ('rho', Offset(280, 268)),
        ],
      _Skizze.fuge => const [
          ('fuge_von', Offset(150, 20)),
          ('fuge_bis', Offset(290, 20)),
          ('lambda', Offset(150, 268)),
          ('schlagregen', Offset(290, 268)),
        ],
      _Skizze.teil => const [
          ('art', Offset(330, 30)),
          ('groesse', Offset(330, 100)),
          ('beschreibung', Offset(330, 30)),
          ('akku', Offset(330, 30)),
          ('seriennummer', Offset(330, 100)),
          ('breite', Offset(110, 268)),
          ('hoehe', Offset(0, 130)),
        ],
    };

/// Schlüssel, die in der Skizze stehen (im Formular darunter ausgelassen).
Set<String> skizzenFelder(BauelementKategorie k) {
  final s = _skizze(k);
  final da = {for (final f in k.felder) f.schluessel};
  return {for (final (key, _) in _platz(s)) if (da.contains(key)) key};
}

/// Bemaßungsskizze mit Eingabefeldern an den Maßen, darunter eigene Maße.
class BauelementSkizze extends StatelessWidget {
  const BauelementSkizze({super.key, required this.element, required this.setzen});
  final Bauelement element;
  final void Function(Map<String, dynamic> daten) setzen;

  @override
  Widget build(BuildContext context) {
    final k = element.kategorie;
    final s = _skizze(k);
    final eigene = Map<String, dynamic>.from(element.daten['eigene_masse'] as Map? ?? const {});
    final felder = skizzenFelder(k);
    String label(String key) => k.felder.where((f) => f.schluessel == key).firstOrNull?.label ?? key;

    FeldDef? def(String key) => k.felder.where((f) => f.schluessel == key).firstOrNull;

    void wert(String key, String text) {
      final d = {...element.daten};
      if (def(key)?.typ == FeldTyp.text) {
        if (text.trim().isEmpty) {
          d.remove(key);
        } else {
          d[key] = text.trim();
        }
        setzen(d);
        return;
      }
      final z = num.tryParse(text.trim().replaceAll(',', '.'));
      if (z == null) {
        d.remove(key);
      } else {
        d[key] = z == z.roundToDouble() ? z.toInt() : z;
      }
      setzen(d);
    }

    Widget feld(String key, {String? text, void Function(String)? speichern}) {
      final f = def(key);
      final istText = f?.typ == FeldTyp.text;
      return SizedBox(
        width: istText ? 140 : 128,
        child: SpeicherFeld(
          key: ValueKey('${element.id}-sk-$key-${element.daten[key]}-${eigene[key]}'),
          initialValue: istText ? '${text ?? element.daten[key] ?? ''}' : '${text ?? element.daten[key] ?? ''}'.replaceAll('.', ','),
          inputFormatters: istText ? null : [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.92),
            labelText: label(key),
            suffixText: istText ? null : (f?.einheit ?? 'mm'),
            hintText: f?.hilfe.isEmpty ?? true ? null : f!.hilfe,
            labelStyle: const TextStyle(fontSize: 12),
          ),
          onFieldSubmitted: speichern ?? (v) => wert(key, v),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (true)
        Container(
          decoration: BoxDecoration(color: BsFarben.flaeche, borderRadius: BorderRadius.circular(8), border: Border.all(color: BsFarben.rand)),
          padding: const EdgeInsets.all(8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 560,
              height: 310,
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _SkizzePainter(s, k, element.daten))),
                for (final (key, pos) in _platz(s))
                  if (felder.contains(key)) Positioned(left: pos.dx, top: pos.dy, child: feld(key)),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final e in eigene.entries)
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 150,
              child: SpeicherFeld(
                key: ValueKey('${element.id}-eig-${e.key}-${e.value}'),
                initialValue: '${e.value}'.replaceAll('.', ','),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                decoration: InputDecoration(isDense: true, labelText: e.key, suffixText: 'mm'),
                onFieldSubmitted: (v) {
                  final z = num.tryParse(v.replaceAll(',', '.'));
                  setzen({...element.daten, 'eigene_masse': {...eigene, e.key: z ?? 0}});
                },
              ),
            ),
            IconButton(
              tooltip: 'Maß entfernen',
              visualDensity: VisualDensity.compact,
              onPressed: () => setzen({...element.daten, 'eigene_masse': {...eigene}..remove(e.key)}),
              icon: const Icon(Icons.close, size: 16),
            ),
          ]),
        OutlinedButton.icon(
          onPressed: () async {
            final c = TextEditingController();
            final name = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Eigenes Maß'),
                content: TextField(
                  controller: c,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Bezeichnung', hintText: 'z. B. Abstand Befestigungslöcher'),
                  onSubmitted: (v) => Navigator.pop(ctx, v),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Hinzufügen')),
                ],
              ),
            );
            if (name != null && name.trim().isNotEmpty) setzen({...element.daten, 'eigene_masse': {...eigene, name.trim(): 0}});
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Eigenes Maß'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final p = await profilZeichnen(context, profilLesen(element.daten['profil']), titel: 'Profil: ${element.anzeige}');
            if (p != null) setzen({...element.daten, 'profil': p.isEmpty ? null : profilSchreiben(p)}..removeWhere((_, v) => v == null));
          },
          icon: const Icon(Icons.draw_outlined, size: 18),
          label: Text(element.daten['profil'] == null ? 'Eigenes Profil zeichnen …' : 'Profil bearbeiten …'),
        ),
      ]),
      if (element.daten['profil'] != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(width: 220, height: 120, child: CustomPaint(painter: ProfilVorschau(profilLesen(element.daten['profil'])))),
        ),
    ]);
  }
}

class _SkizzePainter extends CustomPainter {
  _SkizzePainter(this.s, this.k, this.daten);
  final _Skizze s;
  final BauelementKategorie k;
  final Map<String, dynamic> daten;

  static final _linie = Paint()
    ..color = const Color(0xFF495057)
    ..strokeWidth = 1.6
    ..style = PaintingStyle.stroke;
  static final _fein = Paint()
    ..color = const Color(0xFF868E96)
    ..strokeWidth = 0.8
    ..style = PaintingStyle.stroke;
  static final _mass = Paint()
    ..color = BsFarben.akzent
    ..strokeWidth = 1;
  static final _glas = Paint()..color = const Color(0x332F80ED);
  static final _flaeche = Paint()..color = Colors.white;

  void _masslinie(Canvas c, Offset a, Offset b) {
    c.drawLine(a, b, _mass);
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / d.distance * 5;
    for (final p in [a, b]) {
      c.drawLine(p - n, p + n, _mass);
    }
  }

  void _text(Canvas c, String t, Offset p) {
    final tp = TextPainter(text: TextSpan(text: t, style: const TextStyle(fontSize: 11, color: Color(0xFF868E96))), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, p);
  }

  @override
  void paint(Canvas c, Size size) {
    switch (s) {
      case _Skizze.fenster:
        // Ansicht
        const r = Rect.fromLTRB(70, 40, 250, 255);
        c.drawRect(r, _flaeche);
        c.drawRect(r, _linie);
        c.drawRect(r.deflate(14), _fein);
        c.drawRect(r.deflate(20), _glas);
        if (k == BauelementKategorie.tuer || k == BauelementKategorie.balkontuer) c.drawLine(Offset(r.right - 30, 150), Offset(r.right - 30, 170), _linie);
        _masslinie(c, Offset(r.left, 262), Offset(r.right, 262));
        _masslinie(c, const Offset(60, 40), const Offset(60, 255));
        _masslinie(c, Offset(r.left, 34), Offset(r.left + 14, 34));
        _text(c, 'Ansicht', const Offset(130, 285));
        // Schnitt
        const sx = 360.0;
        c.drawRect(const Rect.fromLTRB(sx, 60, sx + 60, 90), _linie);
        c.drawRect(const Rect.fromLTRB(sx, 205, sx + 60, 235), _linie);
        c.drawRect(const Rect.fromLTRB(sx + 22, 90, sx + 38, 205), _glas);
        c.drawRect(const Rect.fromLTRB(sx + 22, 90, sx + 38, 205), _fein);
        _masslinie(c, const Offset(sx, 54), const Offset(sx + 60, 54));
        _masslinie(c, const Offset(sx + 22, 140), const Offset(sx + 38, 140));
        _text(c, 'außen', const Offset(sx - 40, 140));
        _text(c, 'innen', const Offset(sx + 66, 112));
        _text(c, 'Schnitt', const Offset(sx + 10, 285));
      case _Skizze.sonnenschutz:
        // Schnitt: Kasten oben, Schiene mit zwei Kammern (Rollladen außen, Fliegengitter innen)
        const kasten = Rect.fromLTRB(110, 40, 220, 110);
        c.drawRect(kasten, _flaeche);
        c.drawRect(kasten, _linie);
        c.drawCircle(kasten.center, 26, _fein);
        _masslinie(c, const Offset(100, 40), const Offset(100, 110));
        _masslinie(c, const Offset(110, 34), const Offset(220, 34));
        const schiene = Rect.fromLTRB(130, 110, 200, 250);
        c.drawRect(schiene, _flaeche);
        c.drawRect(schiene, _linie);
        c.drawLine(const Offset(165, 110), const Offset(165, 250), _fein); // Trennsteg
        c.drawLine(const Offset(147, 112), const Offset(147, 248), _linie..strokeWidth = 3);
        _linie.strokeWidth = 1.6;
        c.drawLine(const Offset(183, 112), const Offset(183, 248), Paint()
          ..color = const Color(0xFF868E96)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke);
        _masslinie(c, const Offset(130, 262), const Offset(200, 262));
        _masslinie(c, const Offset(165, 196), const Offset(200, 196));
        _text(c, 'Panzer', const Offset(60, 170));
        _text(c, 'Fliegengitter', const Offset(205, 170));
        _text(c, 'Schnitt', const Offset(140, 285));
        // Ansicht Schiene
        const a = Rect.fromLTRB(380, 40, 470, 250);
        c.drawRect(a, _flaeche);
        c.drawRect(a, _fein);
        c.drawRect(const Rect.fromLTRB(380, 40, 392, 250), _linie);
        c.drawRect(const Rect.fromLTRB(458, 40, 470, 250), _linie);
        _masslinie(c, const Offset(380, 262), const Offset(392, 262));
        _masslinie(c, const Offset(380, 34), const Offset(470, 34));
        _masslinie(c, const Offset(476, 40), const Offset(476, 250));
        _text(c, 'Ansicht', const Offset(400, 285));
      case _Skizze.fensterbank:
        final p = Path()
          ..moveTo(120, 120)
          ..lineTo(400, 120)
          ..lineTo(400, 160)
          ..lineTo(385, 160)
          ..lineTo(385, 135)
          ..lineTo(120, 135)
          ..close();
        c.drawPath(p, _flaeche);
        c.drawPath(p, _linie);
        c.drawRect(const Rect.fromLTRB(60, 60, 120, 200), _fein);
        _text(c, 'Wand', const Offset(70, 205));
        c.drawLine(const Offset(330, 60), const Offset(330, 210), _fein);
        _text(c, 'Fassade', const Offset(310, 212));
        _masslinie(c, const Offset(120, 100), const Offset(400, 100));
        _masslinie(c, const Offset(412, 120), const Offset(412, 160));
        _masslinie(c, const Offset(330, 180), const Offset(400, 180));
        _text(c, 'Schnitt', const Offset(240, 285));
      case _Skizze.leuchte:
        c.drawLine(const Offset(80, 100), const Offset(420, 100), _linie);
        _text(c, 'Decke', const Offset(80, 82));
        final p = Path()
          ..moveTo(190, 100)
          ..lineTo(200, 170)
          ..lineTo(310, 170)
          ..lineTo(320, 100);
        c.drawPath(p, _linie);
        c.drawRect(const Rect.fromLTRB(180, 96, 330, 104), _flaeche);
        c.drawRect(const Rect.fromLTRB(180, 96, 330, 104), _linie);
        _masslinie(c, const Offset(190, 70), const Offset(320, 70));
        _masslinie(c, const Offset(340, 100), const Offset(340, 170));
        _text(c, 'Schnitt', const Offset(230, 285));
      case _Skizze.kasten:
        const r = Rect.fromLTRB(110, 50, 290, 255);
        c.drawRect(r, _flaeche);
        c.drawRect(r, _linie);
        final t = Path()
          ..moveTo(r.right, r.top)
          ..lineTo(r.right + 50, r.top - 30)
          ..lineTo(r.right + 50, r.bottom - 30)
          ..lineTo(r.right, r.bottom);
        c.drawPath(t, _linie);
        c.drawLine(Offset(r.left, r.top), Offset(r.left + 50, r.top - 30), _linie);
        c.drawLine(Offset(r.left + 50, r.top - 30), Offset(r.right + 50, r.top - 30), _linie);
        c.drawRect(r.inflate(18), _fein..color = const Color(0x55868E96));
        _fein.color = const Color(0xFF868E96);
        _masslinie(c, Offset(r.left, 262), Offset(r.right, 262));
        _masslinie(c, Offset(r.left - 14, r.top), Offset(r.left - 14, r.bottom));
        _masslinie(c, Offset(r.right + 4, r.bottom + 4), Offset(r.right + 54, r.bottom - 26));
        _text(c, 'gestrichelt: Freiräume', const Offset(110, 290));
      case _Skizze.heizkoerper:
        const r = Rect.fromLTRB(80, 60, 380, 220);
        c.drawRect(r, _flaeche);
        c.drawRect(r, _linie);
        for (var x = r.left + 15; x < r.right; x += 15) {
          c.drawLine(Offset(x, r.top + 6), Offset(x, r.bottom - 6), _fein);
        }
        c.drawLine(const Offset(110, 220), const Offset(110, 250), _linie);
        c.drawLine(const Offset(140, 220), const Offset(140, 250), _linie);
        _masslinie(c, Offset(r.left, 262), Offset(r.right, 262));
        _masslinie(c, Offset(r.left - 10, r.top), Offset(r.left - 10, r.bottom));
        _masslinie(c, const Offset(400, 60), const Offset(430, 60));
        _masslinie(c, const Offset(430, 250), const Offset(430, 220));
        c.drawLine(const Offset(80, 250), const Offset(440, 250), _fein);
        _text(c, 'FFB', const Offset(445, 243));
      case _Skizze.dose:
        c.drawCircle(const Offset(180, 140), 70, _flaeche);
        c.drawCircle(const Offset(180, 140), 70, _linie);
        c.drawCircle(const Offset(180, 140), 82, _fein);
        _masslinie(c, const Offset(110, 40), const Offset(250, 40));
        _masslinie(c, const Offset(98, 245), const Offset(262, 245));
        c.drawRect(const Rect.fromLTRB(340, 70, 390, 210), _flaeche);
        c.drawRect(const Rect.fromLTRB(340, 70, 390, 210), _linie);
        c.drawLine(const Offset(340, 50), const Offset(340, 230), _fein);
        _text(c, 'Wand', const Offset(300, 232));
        _masslinie(c, const Offset(340, 220), const Offset(390, 220));
        _text(c, 'Ansicht', const Offset(150, 285));
        _text(c, 'Schnitt', const Offset(340, 285));
      case _Skizze.rohr:
        c.drawCircle(const Offset(120, 140), 70, _flaeche);
        c.drawCircle(const Offset(120, 140), 70, _linie);
        c.drawCircle(const Offset(120, 140), 50, _linie);
        _masslinie(c, const Offset(50, 240), const Offset(190, 240));
        _masslinie(c, const Offset(250, 240), const Offset(350, 240));
        c.drawCircle(const Offset(300, 140), 50, _fein);
        c.drawArc(Rect.fromCircle(center: const Offset(460, 220), radius: 70), 3.14159, 1.5708, false, _linie);
        _masslinie(c, const Offset(390, 240), const Offset(460, 240));
      case _Skizze.fitting:
        // Winkel/T-Stück mit Anschlussmaßen
        final pfad = Path()
          ..moveTo(60, 200)
          ..lineTo(200, 200)
          ..arcToPoint(const Offset(260, 140), radius: const Radius.circular(60), clockwise: false)
          ..lineTo(260, 60);
        c.drawPath(pfad, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 34
          ..color = const Color(0xFFDEE2E6));
        c.drawPath(pfad, _linie);
        for (final r in [const Rect.fromLTWH(40, 180, 30, 40), const Rect.fromLTWH(240, 40, 40, 30)]) {
          c.drawRect(r, _flaeche);
          c.drawRect(r, _linie);
        }
        _masslinie(c, const Offset(40, 228), const Offset(40, 172));
        _masslinie(c, const Offset(240, 34), const Offset(280, 34));
        _text(c, 'Anschluss 1', const Offset(80, 212));
        _text(c, 'Anschluss 2 / Abgang', const Offset(285, 70));
      case _Skizze.armatur:
        c.drawLine(const Offset(40, 160), const Offset(330, 160), Paint()
          ..strokeWidth = 24
          ..color = const Color(0xFFDEE2E6));
        final ventil = Path()
          ..moveTo(150, 130)
          ..lineTo(220, 190)
          ..lineTo(220, 130)
          ..lineTo(150, 190)
          ..close();
        c.drawPath(ventil, _flaeche);
        c.drawPath(ventil, _linie);
        c.drawLine(const Offset(185, 160), const Offset(185, 90), _linie);
        c.drawRect(const Rect.fromLTWH(165, 70, 40, 20), _linie);
        _masslinie(c, const Offset(40, 140), const Offset(40, 180));
        _text(c, 'Durchfluss →', const Offset(230, 200));
      case _Skizze.reihengeraet:
        const r = Rect.fromLTWH(110, 40, 120, 210);
        c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), _flaeche);
        c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), _linie);
        c.drawRect(const Rect.fromLTWH(90, 135, 160, 20), _fein);
        _text(c, 'Hutschiene', const Offset(20, 138));
        c.drawRect(const Rect.fromLTWH(155, 120, 30, 50), Paint()..color = const Color(0xFF495057));
        for (var i = 0; i < 3; i++) {
          c.drawCircle(Offset(135 + i * 35, 60), 7, _fein);
          c.drawCircle(Offset(135 + i * 35, 230), 7, _fein);
        }
        _masslinie(c, const Offset(110, 262), const Offset(230, 262));
        _text(c, '1 TE = 17,5 mm', const Offset(235, 255));
      case _Skizze.schalter:
        const r = Rect.fromLTWH(60, 40, 200, 200);
        c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), _flaeche);
        c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), _linie);
        c.drawCircle(r.center, 55, _fein);
        c.drawCircle(r.center + const Offset(-20, 0), 7, _linie);
        c.drawCircle(r.center + const Offset(20, 0), 7, _linie);
        _masslinie(c, Offset(r.left, 262), Offset(r.right, 262));
        _masslinie(c, Offset(r.left - 10, r.top), Offset(r.left - 10, r.bottom));
        c.drawRect(const Rect.fromLTWH(330, 100, 50, 130), _fein);
        c.drawLine(const Offset(330, 80), const Offset(330, 250), _linie);
        _masslinie(c, const Offset(330, 240), const Offset(380, 240));
        _text(c, 'Dose', const Offset(340, 160));
      case _Skizze.sanitaer:
        final wt = Path()
          ..moveTo(110, 100)
          ..lineTo(290, 100)
          ..lineTo(270, 170)
          ..quadraticBezierTo(200, 200, 130, 170)
          ..close();
        c.drawPath(wt, _flaeche);
        c.drawPath(wt, _linie);
        c.drawLine(const Offset(200, 170), const Offset(200, 250), _linie);
        c.drawLine(const Offset(60, 255), const Offset(420, 255), _fein);
        _text(c, 'FFB', const Offset(425, 248));
        _masslinie(c, const Offset(110, 262), const Offset(290, 262));
        _masslinie(c, const Offset(100, 100), const Offset(100, 255));
        _masslinie(c, const Offset(420, 200), const Offset(420, 255));
      case _Skizze.platte:
        final p = Path()
          ..moveTo(80, 120)
          ..lineTo(340, 120)
          ..lineTo(400, 70)
          ..lineTo(140, 70)
          ..close();
        c.drawPath(p, _flaeche);
        c.drawPath(p, _linie);
        c.drawRect(const Rect.fromLTRB(80, 120, 340, 160), Paint()..color = const Color(0xFFFFD8A8));
        c.drawRect(const Rect.fromLTRB(80, 120, 340, 160), _linie);
        c.drawLine(const Offset(340, 160), const Offset(400, 110), _linie);
        c.drawLine(const Offset(400, 70), const Offset(400, 110), _linie);
        _masslinie(c, const Offset(410, 120), const Offset(410, 160));
        _masslinie(c, const Offset(140, 60), const Offset(400, 60));
      case _Skizze.fuge:
        c.drawRect(const Rect.fromLTRB(60, 80, 220, 240), Paint()..color = const Color(0xFFCED4DA));
        c.drawRect(const Rect.fromLTRB(260, 80, 420, 240), Paint()..color = const Color(0xFFE9ECEF));
        c.drawRect(const Rect.fromLTRB(220, 100, 260, 220), Paint()..color = const Color(0xFFFFEC99));
        c.drawRect(const Rect.fromLTRB(220, 100, 260, 220), _linie);
        _masslinie(c, const Offset(220, 70), const Offset(260, 70));
        _text(c, 'Wand', const Offset(110, 245));
        _text(c, 'Rahmen', const Offset(310, 245));
      case _Skizze.teil:
        final r = RRect.fromRectAndRadius(const Rect.fromLTWH(110, 60, 180, 180), const Radius.circular(18));
        c.drawRRect(r, _flaeche);
        c.drawRRect(r, _linie);
        c.drawLine(const Offset(130, 150), const Offset(270, 150), _fein);
        c.drawLine(const Offset(200, 80), const Offset(200, 220), _fein);
        _masslinie(c, const Offset(110, 262), const Offset(290, 262));
        _masslinie(c, const Offset(100, 60), const Offset(100, 240));
        _text(c, 'eigenes Profil zeichnen: Knopf unten', const Offset(110, 285));
    }
  }

  @override
  bool shouldRepaint(_SkizzePainter old) => old.s != s || old.daten != daten;
}

/// Kleine Vorschau eines gezeichneten Profils, eingepasst.
class ProfilVorschau extends CustomPainter {
  ProfilVorschau(this.profil);
  final Profil profil;

  @override
  void paint(Canvas canvas, Size size) {
    final alle = profil.expand((k) => k).toList();
    if (alle.isEmpty) return;
    var x0 = alle.first.dx, y0 = alle.first.dy, x1 = x0, y1 = y0;
    for (final p in alle) {
      x0 = p.dx < x0 ? p.dx : x0;
      y0 = p.dy < y0 ? p.dy : y0;
      x1 = p.dx > x1 ? p.dx : x1;
      y1 = p.dy > y1 ? p.dy : y1;
    }
    final k = [(size.width - 8) / (x1 - x0 + 1e-6), (size.height - 8) / (y1 - y0 + 1e-6)].reduce((a, b) => a < b ? a : b);
    for (final kontur in profil) {
      final pfad = Path()..addPolygon([for (final p in kontur) Offset(4 + (p.dx - x0) * k, 4 + (p.dy - y0) * k)], true);
      canvas.drawPath(pfad, Paint()..color = const Color(0x33868E96));
      canvas.drawPath(pfad, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF343A40));
    }
  }

  @override
  bool shouldRepaint(ProfilVorschau old) => true;
}
