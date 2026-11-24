import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFFF1F1F3);
  static const ink = Color(0xFF16161A);
  static const blue = Color(0xFFBFE4EE);
  static const green = Color(0xFFD0E8B5);
  static const yellow = Color(0xFFF8E58F);
  static const coral = Color(0xFFF0A48C);
  static const yellowSoft = Color(0xFFD0E8B5);
  static const card = Colors.white;
  static const muted = Color(0xFF8A8A92);
}

ThemeData buildTheme() {
  const r20 = BorderRadius.all(Radius.circular(26));
  final base = ThemeData.light(useMaterial3: true);
  final scheme = ColorScheme.fromSeed(seedColor: C.yellow).copyWith(
    primary: C.ink,
    onPrimary: Colors.white,
    secondary: C.yellow,
    onSecondary: C.ink,
    primaryContainer: C.yellowSoft,
    onPrimaryContainer: C.ink,
    surface: C.bg,
    onSurface: C.ink,
    error: const Color(0xFFD64545),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(color: C.ink, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: const CardThemeData(
      color: C.card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: r20),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.ink,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink,
        backgroundColor: Colors.white,
        side: const BorderSide(color: C.ink, width: 1.2),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.ink),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: C.ink,
      foregroundColor: Colors.white,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: CircleBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: C.ink, width: 1.2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: r20),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? C.ink : Colors.white),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : C.ink),
        side: const WidgetStatePropertyAll(BorderSide.none),
        iconColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : C.ink),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: C.yellow,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: C.ink, fontWeight: FontWeight.w600),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? C.ink : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: const BorderSide(color: C.ink, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: C.bg, surfaceTintColor: Colors.transparent),
    dividerTheme: const DividerThemeData(color: Color(0x14000000)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.ink),
  );
}
