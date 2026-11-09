import 'package:flutter/material.dart';

/// Farben aus den Oberflächenentwürfen.
class BsFarben {
  static const leiste = Color(0xFF1C2024);
  static const leisteHell = Color(0xFF22272C);
  static const leisteRand = Color(0xFF3D434A);
  static const leisteText = Color(0xFFC9CDD1);
  static const akzent = Color(0xFFF97316);
  static const akzentDunkel = Color(0xFF9A3412);
  static const akzentHell = Color(0xFFFFEDD5);
  static const flaeche = Color(0xFFF4F5F2);
  static const zeichenflaeche = Color(0xFFF7F8F5);
  static const raster = Color(0xFFE6E8E2);
  static const rand = Color(0xFFD9DBD5);
  static const textLeise = Color(0xFF5B6168);
  static const wandBestand = Color(0xFF2B2F33);
  static const wandNeu = Color(0xFFC92A2A);
  static const wandAbbruch = Color(0xFFE6A700);
}

ThemeData bauSpurTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BsFarben.akzent,
    primary: BsFarben.akzent,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: BsFarben.flaeche,
    visualDensity: VisualDensity.standard,
    dividerColor: BsFarben.rand,
    // Gefüllte Felder mit Linie unten: die Beschriftung bleibt im Feld und
    // überlappt nicht mit dem Feld darüber (vorher „verzerrt“ bei engem Stapeln).
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFFF4F5F2),
      border: UnderlineInputBorder(),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFB8BCB4))),
      isDense: true,
      contentPadding: EdgeInsets.fromLTRB(10, 10, 10, 8),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BsFarben.akzent,
        foregroundColor: BsFarben.leiste,
        minimumSize: const Size(44, 44),
      ),
    ),
  );
}
