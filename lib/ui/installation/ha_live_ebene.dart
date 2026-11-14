import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ha_live.dart';
import '../../data/models.dart';

/// Entitäten eines Objekts: `ha_entity` und die Entitäten eigener Sensoren (`ha_entities`).
List<String> haEntitaetenVon(Objekt o) => [
      if ('${o.eigenschaften['ha_entity'] ?? ''}'.trim().isNotEmpty) '${o.eigenschaften['ha_entity']}'.trim(),
      for (final v in (o.eigenschaften['ha_entities'] as Map? ?? const {}).values)
        if ('$v'.trim().isNotEmpty) '$v'.trim(),
    ];

/// Live-Zustände aus Home Assistant (nur lesend), alle 10 s neu.
class HaLiveQuelle extends ChangeNotifier {
  HaLiveQuelle(this.einstellung);
  final HaEinstellung einstellung;
  HaVerbindung? _v;
  Timer? _t;
  Map<String, HaEntitaet> zustand = const {};
  String? fehler;
  DateTime? stand;

  bool get laeuft => _t != null;

  void starten() {
    if (_t != null) return;
    _t = Timer.periodic(const Duration(seconds: 10), (_) => _holen());
    _holen();
  }

  void stoppen() {
    _t?.cancel();
    _t = null;
    _v?.schliessen();
    _v = null;
    notifyListeners();
  }

  Future<void> _holen() async {
    if (einstellung.sperre != null) {
      fehler = einstellung.sperre;
      notifyListeners();
      return;
    }
    try {
      _v ??= HaVerbindung(einstellung);
      final l = await _v!.zustaende();
      zustand = {for (final e in l) e.id: e};
      fehler = null;
      stand = DateTime.now();
    } catch (e) {
      fehler = '$e'.replaceFirst(RegExp(r'^(Bad state|HttpException|SocketException): '), '');
    }
    if (_t != null) notifyListeners();
  }

  @override
  void dispose() {
    _t?.cancel();
    _v?.schliessen();
    super.dispose();
  }
}

/// Zeichnet die Live-Zustände als kleine Schilder neben die Objekte im Plan:
/// gelb = an/offen, grau = aus, rot = nicht erreichbar, sonst der Messwert.
class HaLivePainter extends CustomPainter {
  HaLivePainter({required this.objekte, required this.zustand, required this.massstab, required this.verschiebung});
  final List<Objekt> objekte;
  final Map<String, HaEntitaet> zustand;
  final double massstab;
  final Offset verschiebung;

  @override
  void paint(Canvas canvas, Size size) {
    for (final o in objekte) {
      if (o.punkte.isEmpty) continue;
      final ids = haEntitaetenVon(o);
      if (ids.isEmpty) continue;
      var x = 0.0, y = 0.0;
      for (final p in o.punkte) {
        x += p.x;
        y += p.y;
      }
      final mitte = Offset(x / o.punkte.length, y / o.punkte.length) * massstab + verschiebung;
      var dy = 0.0;
      for (final id in ids.take(3)) {
        final e = zustand[id];
        final (text, farbe) = e == null
            ? ('fehlt in HA', const Color(0xFFB91C1C))
            : !e.erreichbar
                ? (e.zustandText, const Color(0xFFB91C1C))
                : switch (e.zustand) {
                    'on' || 'open' || 'heat' || 'playing' => (e.zustandText, const Color(0xFFF59E0B)),
                    'off' || 'closed' || 'idle' => (e.zustandText, const Color(0xFF6B7280)),
                    _ => (e.zustandText, const Color(0xFF0E7490)),
                  };
        final tp = TextPainter(
          text: TextSpan(text: text, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 140);
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(mitte.dx + 10, mitte.dy - 22 + dy, tp.width + 10, tp.height + 4), const Radius.circular(4));
        canvas.drawRRect(r, Paint()..color = farbe);
        if (e?.zustand == 'on') canvas.drawCircle(mitte, 11, Paint()..color = const Color(0x55F59E0B));
        tp.paint(canvas, Offset(r.left + 5, r.top + 2));
        dy += tp.height + 6;
      }
    }
  }

  @override
  bool shouldRepaint(covariant HaLivePainter alt) => true;
}
