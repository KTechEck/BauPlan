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

/// [touch]: Tablet mit Finger/Stift – größere Bedienelemente (mind. 44 pt).
ThemeData bauSpurTheme({bool touch = false}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: BsFarben.akzent,
    primary: BsFarben.akzent,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: BsFarben.flaeche,
    visualDensity: touch ? VisualDensity.comfortable : VisualDensity.standard,
    materialTapTargetSize: touch ? MaterialTapTargetSize.padded : null,
    iconButtonTheme: touch ? IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(44, 44))) : null,
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
        minimumSize: Size(touch ? 44 : 36, touch ? 44 : 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        iconSize: 18,
      ),
    ),
    // Schlanke Knöpfe: weniger Fläche, klare Kante, kleine Schrift
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF343A40),
        minimumSize: Size(touch ? 44 : 32, touch ? 44 : 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: touch ? null : VisualDensity.compact,
        side: const BorderSide(color: BsFarben.rand),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        iconSize: 17,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: Size(touch ? 44 : 32, touch ? 44 : 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: touch ? null : VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        iconSize: 17,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: touch ? null : VisualDensity.compact,
        side: const WidgetStatePropertyAll(BorderSide(color: BsFarben.rand)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: BsFarben.akzentHell,
      side: const BorderSide(color: BsFarben.rand),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF343A40)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: BsFarben.rand)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titleTextStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF212529)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: BsFarben.rand)),
      textStyle: const TextStyle(fontSize: 13, color: Color(0xFF212529)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(color: BsFarben.leiste, borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
    ),
    listTileTheme: ListTileThemeData(
      dense: !touch,
      iconColor: BsFarben.akzentDunkel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Color(0xFF212529),
      elevation: 0,
      scrolledUnderElevation: 1,
      shape: Border(bottom: BorderSide(color: BsFarben.rand)),
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF212529)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: BsFarben.akzentHell,
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? BsFarben.akzentDunkel : BsFarben.textLeise)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? BsFarben.akzentDunkel : BsFarben.textLeise,
          )),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: BsFarben.leiste,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? BsFarben.akzent : null),
    ),
    dividerTheme: const DividerThemeData(color: BsFarben.rand, thickness: 1, space: 1),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
  );
}
