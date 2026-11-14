import 'package:flutter/gestures.dart';

/// Touch-Bedienung für die Zeichenflächen (iPad): zwei Finger verschieben und
/// zoomen, ein Finger tippt oder zieht wie die Maus. Der erste Fingerdruck
/// wird kurz zurückgehalten, damit beim Aufsetzen des zweiten Fingers nichts
/// gesetzt oder gezeichnet wird. Maus und Stift (Apple Pencil) gehen sofort durch.
/// Sobald ein Stift benutzt wurde, zeichnet nur noch der Stift; ein Finger
/// verschiebt dann die Ansicht (Handballen setzt nichts mehr).
class ZweiFinger {
  final _p = <int, Offset>{};
  PointerDownEvent? _wartend;
  bool _geste = false;

  /// Ein Stift wurde benutzt: Finger zeichnen nicht mehr.
  bool stiftGesehen = false;

  bool get aktiv => _p.length >= 2;

  /// true = Ereignis übernommen (Touch); sonst normal behandeln.
  bool runter(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) stiftGesehen = true;
    if (e.kind != PointerDeviceKind.touch) return false;
    _p[e.pointer] = e.localPosition;
    if (stiftGesehen) {
      _wartend = null;
      _geste = true;
    } else if (_p.length == 1) {
      _wartend = e;
      _geste = false;
    } else {
      _wartend = null;
      _geste = true;
    }
    return true;
  }

  /// Einzelner Finger bewegt sich deutlich: zurückgehaltenen Druck jetzt auslösen.
  PointerDownEvent? ausloesenBeiBewegung(PointerMoveEvent e) {
    final w = _wartend;
    if (w == null || w.pointer != e.pointer || _p.length != 1) return null;
    if ((e.localPosition - w.localPosition).distance < 8) return null;
    _wartend = null;
    return w;
  }

  /// Zwei Finger: Verschiebung, Zoomfaktor und Mitte; sonst null.
  ({Offset verschiebung, double faktor, Offset mitte})? zweiFinger(PointerMoveEvent e) {
    if (!_p.containsKey(e.pointer)) return null;
    if (!aktiv) {
      final alt = _p[e.pointer]!;
      _p[e.pointer] = e.localPosition;
      // Stiftbetrieb: ein Finger verschiebt die Ansicht
      if (stiftGesehen && _geste) return (verschiebung: e.localPosition - alt, faktor: 1.0, mitte: e.localPosition);
      return null;
    }
    final ids = _p.keys.take(2).toList();
    final a0 = _p[ids[0]]!, b0 = _p[ids[1]]!;
    _p[e.pointer] = e.localPosition;
    final a1 = _p[ids[0]]!, b1 = _p[ids[1]]!;
    final m0 = (a0 + b0) / 2, m1 = (a1 + b1) / 2;
    final d0 = (a0 - b0).distance, d1 = (a1 - b1).distance;
    return (verschiebung: m1 - m0, faktor: d0 < 1 ? 1.0 : d1 / d0, mitte: m1);
  }

  /// Finger hoch: zurückgehaltener Druck (Tippen) und ob eine Zwei-Finger-Geste lief.
  ({PointerDownEvent? wartend, bool geste}) hoch(PointerEvent e) {
    if (!_p.containsKey(e.pointer)) return (wartend: null, geste: false);
    _p.remove(e.pointer);
    final w = _wartend?.pointer == e.pointer ? _wartend : null;
    _wartend = null;
    final g = _geste;
    if (_p.isEmpty) _geste = false;
    return (wartend: w, geste: g);
  }
}
