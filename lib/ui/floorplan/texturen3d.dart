import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/drei_d_szene.dart';

/// Prozedurale Texturen für die 3D-Ansicht: einmal gezeichnet, dann im
/// Speicher. Jede Textur kennt ihre Größe in mm (wie oft sie sich wiederholt).
class Textur3d {
  const Textur3d(this.bild, this.mmB, this.mmH);
  final ui.Image bild;
  final double mmB, mmH;
}

final _cache = <String, Textur3d?>{};

/// Textur für eine Oberfläche oder null (dann einfarbig).
Textur3d? textur3d(Oberflaeche3d o) {
  final key = o.art == 'fliesen' ? 'fliesen_${o.kachelB}x${o.kachelH}' : o.art;
  if (_cache.containsKey(key)) return _cache[key];
  Textur3d? t;
  try {
    t = _zeichnen(o);
  } catch (_) {
    t = null;
  }
  _cache[key] = t;
  return t;
}

Textur3d? _zeichnen(Oberflaeche3d o) {
  final (double mmB, double mmH) = switch (o.art) {
    'ziegel' || 'klinker' => (500.0, 500.0),
    'ks' => (1000.0, 500.0),
    'porenbeton' => (1200.0, 500.0),
    'gipskarton' => (1250.0, 1250.0),
    'holz' => (600.0, 600.0),
    'fliesen' => ((o.kachelB * (o.kachelB < 100 ? 8 : 2)).toDouble(), (o.kachelH * (o.kachelH < 100 ? 8 : 2)).toDouble()),
    'parkett' => (1200.0, 720.0),
    'dielen' => (2400.0, 800.0),
    'pflaster' => (800.0, 800.0),
    'stein' => (1200.0, 1200.0),
    'daemmung' => (1000.0, 500.0),
    'dachziegel' => (600.0, 600.0),
    _ => (1000.0, 1000.0),
  };
  const px = 256;
  final w = px, h = (px * mmH / mmB).round().clamp(32, 512);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final r = math.Random(o.art.hashCode);
  final sx = w / mmB, sy = h / mmH; // px je mm
  void flaeche(Color f) => c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = f);
  void rauschen(int n, double hell, double groesse) {
    for (var i = 0; i < n; i++) {
      final v = r.nextDouble();
      c.drawCircle(Offset(r.nextDouble() * w, r.nextDouble() * h), groesse * (0.4 + r.nextDouble()),
          Paint()..color = (v > 0.5 ? Colors.white : Colors.black).withValues(alpha: hell * r.nextDouble()));
    }
  }

  // Steine im Verband: Breite/Höhe in mm inkl. Fuge
  void verband(double sb, double sh, double fuge, List<Color> farben, Color fugeFarbe, {double versatz = 0.5}) {
    flaeche(fugeFarbe);
    var reihe = 0;
    for (var y = 0.0; y < mmH - 0.1; y += sh, reihe++) {
      final off = (reihe.isOdd ? versatz : 0) * sb;
      for (var x = -sb; x < mmB + sb; x += sb) {
        final f = farben[r.nextInt(farben.length)];
        final hell = (r.nextDouble() - 0.5) * 0.12;
        final col = Color.lerp(f, hell > 0 ? Colors.white : Colors.black, hell.abs())!;
        final rect = Rect.fromLTWH((x + off) * sx, y * sy, (sb - fuge) * sx, (sh - fuge) * sy);
        c.drawRect(rect, Paint()..color = col);
        // links/rechts nahtlos wiederholen
        c.drawRect(rect.shift(Offset(w.toDouble(), 0)), Paint()..color = col);
        c.drawRect(rect.shift(Offset(-w.toDouble(), 0)), Paint()..color = col);
      }
    }
  }

  switch (o.art) {
    case 'farbe':
      flaeche(Colors.white);
      rauschen(900, 0.035, 1.2);
    case 'putz':
      flaeche(Colors.white);
      rauschen(2600, 0.09, 1.4);
    case 'beton':
      flaeche(const Color(0xFFF2F2F0));
      rauschen(2200, 0.10, 1.6);
      for (var i = 0; i < 40; i++) {
        c.drawCircle(Offset(r.nextDouble() * w, r.nextDouble() * h), 1 + r.nextDouble() * 1.5, Paint()..color = Colors.black.withValues(alpha: 0.18));
      }
      c.drawLine(Offset(0, h / 2), Offset(w.toDouble(), h / 2), Paint()..color = Colors.black.withValues(alpha: 0.06)..strokeWidth = 1);
    case 'estrich':
      flaeche(Colors.white);
      rauschen(3000, 0.10, 1.2);
    case 'ziegel':
      verband(250, 83.3, 12, const [Color(0xFFB5523B), Color(0xFFA9472F), Color(0xFFC0634A), Color(0xFF9E4430)], const Color(0xFFD9D2C5));
    case 'klinker':
      verband(250, 83.3, 11, const [Color(0xFF7A3B2A), Color(0xFF6B3324), Color(0xFF8C4A35), Color(0xFF5A2D22)], const Color(0xFF8F8A80));
    case 'ks':
      verband(500, 250, 4, const [Color(0xFFEEEDE8), Color(0xFFE6E5DF), Color(0xFFF3F2EE)], const Color(0xFFC9C7BF));
    case 'porenbeton':
      verband(600, 250, 3, const [Color(0xFFF0EFEC), Color(0xFFEAE9E5)], const Color(0xFFD5D3CC));
      rauschen(1500, 0.06, 1);
    case 'gipskarton':
      flaeche(const Color(0xFFF1F1EF));
      rauschen(500, 0.03, 1);
      final f = Paint()..color = const Color(0xFFDADAD6)..strokeWidth = 2;
      c.drawLine(const Offset(1, 0), Offset(1, h.toDouble()), f);
      for (var y = 0.0; y < mmH; y += 250) {
        c.drawCircle(Offset(625 * sx, y * sy + 6), 1.2, Paint()..color = const Color(0xFFB8B8B2));
      }
    case 'holz':
      final farben = [const Color(0xFFC89B6A), const Color(0xFFBF8F5E), const Color(0xFFD2A877)];
      for (var x = 0.0; x < mmB; x += 120) {
        c.drawRect(Rect.fromLTWH(x * sx, 0, 118 * sx, h.toDouble()), Paint()..color = farben[r.nextInt(3)]);
        for (var k = 0; k < 6; k++) {
          final gx = (x + r.nextDouble() * 110) * sx;
          c.drawLine(Offset(gx, 0), Offset(gx + r.nextDouble() * 4 - 2, h.toDouble()), Paint()..color = Colors.black.withValues(alpha: 0.07)..strokeWidth = 1);
        }
      }
    case 'fliesen':
      flaeche(const Color(0xFFBDBAB2));
      final fu = o.kachelB < 100 ? 2.0 : 3.0;
      for (var y = 0.0; y < mmH - 0.1; y += o.kachelH) {
        for (var x = 0.0; x < mmB - 0.1; x += o.kachelB) {
          final v = (r.nextDouble() - 0.5) * (o.kachelB < 100 ? 0.25 : 0.05);
          final col = Color.lerp(Colors.white, v > 0 ? Colors.white : Colors.black, v.abs())!;
          c.drawRect(Rect.fromLTWH(x * sx + fu / 2, y * sy + fu / 2, o.kachelB * sx - fu, o.kachelH * sy - fu), Paint()..color = col);
        }
      }
      rauschen(400, 0.025, 1);
    case 'parkett' || 'dielen':
      final lang = o.art == 'parkett' ? 1200.0 : 2400.0, breit = o.art == 'parkett' ? 180.0 : 200.0;
      final farben = o.art == 'parkett'
          ? [const Color(0xFFD6B48A), const Color(0xFFCBA77B), const Color(0xFFDDBD95), const Color(0xFFC79F72)]
          : [const Color(0xFFC9A57C), const Color(0xFFBE9970), const Color(0xFFD1AF87)];
      var reihe = 0;
      for (var y = 0.0; y < mmH - 0.1; y += breit, reihe++) {
        final off = ((reihe * 0.37) % 1) * lang;
        for (var x = -lang; x < mmB + lang; x += lang) {
          final col = farben[r.nextInt(farben.length)];
          for (final dx in [0.0, w.toDouble(), -w.toDouble()]) {
            final rect = Rect.fromLTWH((x + off) * sx + dx, y * sy, lang * sx - 1.2, breit * sy - 1.2);
            c.drawRect(rect, Paint()..color = col);
          }
          for (var k = 0; k < 5; k++) {
            final gy = (y + 10 + r.nextDouble() * (breit - 20)) * sy;
            c.drawLine(Offset((x + off) * sx, gy), Offset((x + off + lang) * sx, gy + r.nextDouble() * 3 - 1.5),
                Paint()..color = const Color(0xFF6B4A2B).withValues(alpha: 0.10)..strokeWidth = 0.8);
          }
        }
      }
    case 'vinyl':
      flaeche(const Color(0xFFD9CDBB));
      for (var y = 0.0; y < mmH; y += 220) {
        c.drawLine(Offset(0, y * sy), Offset(w.toDouble(), y * sy), Paint()..color = const Color(0xFFB8AB97)..strokeWidth = 1);
      }
      rauschen(1200, 0.05, 1);
    case 'teppich':
      flaeche(const Color(0xFF8D8A84));
      rauschen(6000, 0.14, 0.9);
    case 'stein':
      final farben = [const Color(0xFFB9B3A8), const Color(0xFFA8A296), const Color(0xFFC6C0B4), const Color(0xFF9C968B)];
      flaeche(const Color(0xFF8B867D));
      for (var y = 0.0; y < mmH - 0.1; y += 400) {
        for (var x = 0.0; x < mmB - 0.1; x += 600) {
          c.drawRect(Rect.fromLTWH(x * sx + 1.5, y * sy + 1.5, 600 * sx - 3, 400 * sy - 3), Paint()..color = farben[r.nextInt(4)]);
        }
      }
      rauschen(2500, 0.09, 1.3);
    case 'pflaster':
      verband(200, 100, 6, const [Color(0xFF9A958C), Color(0xFF8C877E), Color(0xFFA7A298)], const Color(0xFF6F6B64));
    case 'rasen':
      flaeche(const Color(0xFF7FA05A));
      for (var i = 0; i < 2200; i++) {
        final x = r.nextDouble() * w, y = r.nextDouble() * h;
        c.drawLine(Offset(x, y), Offset(x + r.nextDouble() * 2 - 1, y - 2 - r.nextDouble() * 3),
            Paint()..color = (r.nextBool() ? const Color(0xFF94B86A) : const Color(0xFF5E7F3E)).withValues(alpha: 0.7)..strokeWidth = 1);
      }
    case 'dachziegel':
      verband(300, 200, 8, const [Color(0xFFB4442E), Color(0xFFA53D29), Color(0xFFC0533A), Color(0xFF9B3A27)], const Color(0xFF6E2A1D));
      for (var y = 0.0; y < mmH; y += 200) {
        c.drawLine(Offset(0, (y + 190) * sy), Offset(w.toDouble(), (y + 190) * sy), Paint()..color = Colors.black.withValues(alpha: 0.25)..strokeWidth = 2);
      }
    case 'daemmung':
      flaeche(const Color(0xFFF2E9C2));
      verband(1000, 500, 4, const [Color(0xFFF4ECC8), Color(0xFFEFE5BB)], const Color(0xFFD9CE9E));
      rauschen(1500, 0.05, 1);
    default:
      flaeche(Colors.white);
  }
  final bild = rec.endRecording().toImageSync(w, h);
  return Textur3d(bild, mmB, mmH);
}
