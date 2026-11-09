import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

/// Dunkle Kopfleiste mit Logo.
class Kopfleiste extends StatelessWidget {
  const Kopfleiste({super.key, required this.titel, this.rechts = const []});

  final String titel;
  final List<Widget> rechts;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: BsFarben.leiste,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const BauSpurLogo(),
          const SizedBox(width: 10),
          const Text('BauSpur',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(titel,
                overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9AA0A6))),
          ),
          ...rechts,
        ],
      ),
    );
  }
}

/// Logo: Rahmen mit orangefarbener Spur.
class BauSpurLogo extends StatelessWidget {
  const BauSpurLogo({super.key, this.groesse = 28});
  final double groesse;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(groesse), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 28;
    final rahmen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..color = Colors.white;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(s, s, 26 * s, 26 * s), Radius.circular(6 * s)),
        rahmen);
    final spur = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = BsFarben.akzent;
    final path = Path()
      ..moveTo(7 * s, 20 * s)
      ..lineTo(7 * s, 12 * s)
      ..lineTo(14 * s, 12 * s)
      ..lineTo(14 * s, 8 * s)
      ..lineTo(21 * s, 8 * s);
    canvas.drawPath(path, spur);
    canvas.drawCircle(Offset(21 * s, 8 * s), 2.5 * s, Paint()..color = BsFarben.akzent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Meldungen erscheinen als kleines Fenster unten rechts und verdecken die Arbeitsfläche nicht.
SnackBar _meldung(BuildContext context, Widget inhalt, {Color? farbe, SnackBarAction? aktion, IconData symbol = Icons.info_outline}) {
  final breite = MediaQuery.maybeOf(context)?.size.width ?? 1200;
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.only(left: breite > 900 ? breite - 460 : 16, right: 16, bottom: 16),
    backgroundColor: farbe,
    showCloseIcon: true,
    action: aktion,
    content: Row(children: [Icon(symbol, color: Colors.white, size: 18), const SizedBox(width: 10), Expanded(child: inhalt)]),
  );
}

void zeigeFehler(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(_meldung(context, Text(text), farbe: const Color(0xFFB91C1C), symbol: Icons.error_outline));
}

void zeigeWarnung(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(_meldung(context, Text(text), farbe: const Color(0xFFB35C00), symbol: Icons.warning_amber));
}

void zeigeHinweis(BuildContext context, String text, {SnackBarAction? aktion}) {
  ScaffoldMessenger.of(context).showSnackBar(_meldung(context, Text(text), aktion: aktion));
}

Future<bool> frage(
  BuildContext context, {
  required String titel,
  required String text,
  String ja = 'OK',
  String nein = 'Abbrechen',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titel),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(nein)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ja)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> texteingabe(
  BuildContext context, {
  required String titel,
  required String feld,
  String vorschlag = '',
}) {
  final ctrl = TextEditingController(text: vorschlag);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titel),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: feld),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('OK')),
      ],
    ),
  );
}

/// Eingabefeld für ganze Millimeter (auch negativ).
class MmFeld extends StatelessWidget {
  const MmFeld({super.key, required this.label, required this.controller, this.hinweis});

  final String label;
  final TextEditingController controller;
  final String? hinweis;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
      decoration: InputDecoration(labelText: label, suffixText: 'mm', helperText: hinweis),
    );
  }
}

int? mmWert(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

/// 2135 → „2 135“
String mmText(num mm) {
  final s = mm.round().abs().toString();
  final buf = StringBuffer(mm < 0 ? '−' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// 12345678 mm² → „12,35 m²“
String flaecheText(num mm2) => '${(mm2 / 1e6).toStringAsFixed(2).replaceAll('.', ',')} m²';

/// 14020 mm → „14,02 m“
String meterText(num mm) => '${(mm / 1000).toStringAsFixed(2).replaceAll('.', ',')} m';

/// Eingabefeld für Eigenschaften: übernimmt den Wert mit Enter UND beim
/// Verlassen des Feldes (Klick woanders, Tab) – nicht nur mit Enter.
class SpeicherFeld extends StatefulWidget {
  const SpeicherFeld({
    super.key,
    this.initialValue,
    this.controller,
    this.decoration = const InputDecoration(),
    this.inputFormatters,
    this.keyboardType,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.minLines,
    this.enabled,
    this.autofocus = false,
    this.onChanged,
    this.pruefen,
    required this.onFieldSubmitted,
  });

  /// Eingabe prüfen: Fehlertext erscheint direkt am Feld, übernommen wird nur bei null.
  final String? Function(String)? pruefen;

  final String? initialValue;
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final int? minLines;
  final bool? enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String> onFieldSubmitted;

  @override
  State<SpeicherFeld> createState() => _SpeicherFeldState();
}

class _SpeicherFeldState extends State<SpeicherFeld> {
  late final _ctrl = widget.controller ?? TextEditingController(text: widget.initialValue ?? '');
  final _fokus = FocusNode();
  late String _uebernommen = _ctrl.text;

  @override
  void initState() {
    super.initState();
    _fokus.addListener(() {
      if (!_fokus.hasFocus) _uebernehmen();
    });
  }

  String? _fehler;

  bool _gueltig(String v) {
    final f = widget.pruefen?.call(v);
    if (f != _fehler) setState(() => _fehler = f);
    return f == null;
  }

  void _uebernehmen() {
    if (_ctrl.text == _uebernommen) return;
    if (!_gueltig(_ctrl.text)) return;
    _uebernommen = _ctrl.text;
    widget.onFieldSubmitted(_ctrl.text);
  }

  @override
  void dispose() {
    if (_fokus.hasFocus && _ctrl.text != _uebernommen) {
      // Beim Wegklicken auf ein anderes Objekt den Wert nicht verlieren.
      final t = _ctrl.text;
      _uebernommen = t;
      final f = widget.onFieldSubmitted;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          f(t);
        } catch (_) {
          // Ansicht ist schon weg – Wert wurde trotzdem gespeichert, soweit möglich.
        }
      });
    }
    _fokus.dispose();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: _ctrl,
        focusNode: _fokus,
        decoration: (widget.decoration ?? const InputDecoration()).copyWith(errorText: _fehler),
        inputFormatters: widget.inputFormatters,
        keyboardType: widget.keyboardType,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onFieldSubmitted: (v) {
          if (!_gueltig(v)) return;
          _uebernommen = v;
          widget.onFieldSubmitted(v);
        },
      );
}

/// Erkennt einen Doppelklick aus zwei schnellen Klicks an fast gleicher Stelle
/// (für Zeichenflächen, die Klicks selbst über einen Listener auswerten).
class Doppelklick {
  DateTime? _zeit;
  Offset? _ort;

  bool erkannt(Offset ort) {
    final jetzt = DateTime.now();
    final ja = _zeit != null && jetzt.difference(_zeit!) < const Duration(milliseconds: 400) && (ort - _ort!).distance < 8;
    _zeit = ja ? null : jetzt;
    _ort = ort;
    return ja;
  }
}

/// Eigenschaften der Auswahl als eigenes Fenster (Doppelklick). Die Seite setzt
/// bei jedem Aufbau [bauen] und [auswahl]; der Dialog baut sich mit ihr neu.
class EigenschaftenFenster {
  final _takt = ValueNotifier<int>(0);
  Widget Function()? bauen;
  bool auswahl = false;
  bool _offen = false;

  /// Aus dem build() der Seite aufrufen.
  void setzen({required bool auswahl, required Widget Function() bauen}) {
    this.auswahl = auswahl;
    this.bauen = bauen;
    if (_offen) WidgetsBinding.instance.addPostFrameCallback((_) => _takt.value++);
  }

  /// Nach einem Klick: öffnet nach dem nächsten Bild, falls etwas gewählt ist.
  bool get offen => _offen;

  /// Ersatz für die Seitenleiste, solange das Fenster offen ist (dieselben
  /// Eingabefelder dürfen nicht zweimal gleichzeitig angezeigt werden).
  Widget seitenleiste(Widget Function() inhalt) => _offen
      ? const Center(child: Text('Eigenschaften sind im eigenen Fenster geöffnet.', style: TextStyle(color: Colors.black54)))
      : inhalt();

  void nachKlickOeffnen(BuildContext context, {String titel = 'Eigenschaften', bool Function()? sperre}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (auswahl && !_offen && context.mounted && !(sperre?.call() ?? false)) zeigen(context, titel);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> zeigen(BuildContext context, String titel) async {
    _offen = true;
    (context as Element).markNeedsBuild();
    try {
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          child: SizedBox(
            width: 440,
            height: math.min(720, MediaQuery.of(c).size.height - 80),
            child: Material(
              color: Colors.white,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                  child: Row(children: [
                    Expanded(child: Text(titel, style: Theme.of(c).textTheme.titleMedium)),
                    IconButton(tooltip: 'Schließen (Esc)', onPressed: () => Navigator.of(c).pop(), icon: const Icon(Icons.close)),
                  ]),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _takt,
                      builder: (_, __, ___) => auswahl && bauen != null ? bauen!() : const Center(child: Text('Nichts mehr gewählt.')),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    } finally {
      _offen = false;
      if (context.mounted) context.markNeedsBuild();
    }
  }
}

/// Auswahlliste mit Gruppenüberschriften (z. B. Gewerk → Geräte).
class GruppenAuswahl<T> extends StatelessWidget {
  const GruppenAuswahl({
    super.key,
    required this.gruppen,
    required this.wert,
    required this.onChanged,
    this.hinweis = 'Auswählen',
    this.breite = 280,
  });

  /// Gruppen: Überschrift und Einträge (Wert, Text, optionale Farbe).
  final List<(String, List<(T, String, Color?)>)> gruppen;
  final T? wert;
  final ValueChanged<T?> onChanged;
  final String hinweis;
  final double breite;

  @override
  Widget build(BuildContext context) {
    final alle = [for (final g in gruppen) ...g.$2];
    return SizedBox(
      width: breite,
      child: DropdownButton<T>(
        value: alle.any((e) => e.$1 == wert) ? wert : null,
        isDense: true,
        isExpanded: true,
        hint: Text(hinweis),
        underline: const SizedBox.shrink(),
        menuMaxHeight: 560,
        selectedItemBuilder: (_) => [
          for (final g in gruppen) ...[
            if (g.$1.isNotEmpty) const SizedBox.shrink(),
            for (final e in g.$2) Align(alignment: Alignment.centerLeft, child: Text(e.$2, overflow: TextOverflow.ellipsis)),
          ],
        ],
        items: [
          for (final g in gruppen) ...[
            if (g.$1.isNotEmpty)
              DropdownMenuItem<T>(
                enabled: false,
                child: Text(g.$1.toUpperCase(),
                    style: const TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: BsFarben.textLeise)),
              ),
            for (final e in g.$2)
              DropdownMenuItem<T>(
                value: e.$1,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(children: [
                    if (e.$3 != null) ...[Container(width: 10, height: 10, color: e.$3), const SizedBox(width: 8)],
                    Expanded(child: Text(e.$2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
          ],
        ],
        onChanged: onChanged,
      ),
    );
  }
}
