import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class C {
  // light-mode values, kept for older code
  static const bg = Color(0xFFF1F1F3);
  static const ink = Color(0xFF16161A);
  static const muted = Color(0xFF8A8A92);
  // pastel blocks (same in light and dark)
  static const blue = Color(0xFFBFE4EE);
  static const green = Color(0xFFD0E8B5);
  static const yellow = Color(0xFFF8E58F);
  static const coral = Color(0xFFF0A48C);
  static const lilac = Color(0xFFD9CCF2);
  static const grey = Color(0xFFE4E4E8);
  static const dark = Color(0xFF16161A); // text that sits on pastel blocks
}

extension Cx on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get ink => isDark ? const Color(0xFFF2F2F5) : const Color(0xFF16161A);
  Color get bg => isDark ? const Color(0xFF121214) : const Color(0xFFF1F1F3);
  Color get cardBg => isDark ? const Color(0xFF1F1F24) : Colors.white;
  Color get muted => isDark ? const Color(0xFF9A9AA3) : const Color(0xFF8A8A92);
}

class ThemeController {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.light);

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      mode.value = p.getString('theme') == 'dark' ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {}
  }

  static Future<void> toggle(BuildContext c) async {
    final dark = Theme.of(c).brightness == Brightness.dark;
    mode.value = dark ? ThemeMode.light : ThemeMode.dark;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme', dark ? 'light' : 'dark');
    } catch (_) {}
  }
}

ThemeData buildTheme(bool dark) {
  const r26 = BorderRadius.all(Radius.circular(26));
  final bg = dark ? const Color(0xFF121214) : const Color(0xFFF1F1F3);
  final card = dark ? const Color(0xFF1F1F24) : Colors.white;
  final ink = dark ? const Color(0xFFF2F2F5) : const Color(0xFF16161A);
  final onInk = dark ? const Color(0xFF121214) : Colors.white;
  final base = dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
          seedColor: C.blue, brightness: dark ? Brightness.dark : Brightness.light)
      .copyWith(
    primary: ink,
    onPrimary: onInk,
    secondary: C.blue,
    onSecondary: C.dark,
    primaryContainer: dark ? const Color(0xFF33422B) : C.green,
    onPrimaryContainer: ink,
    surface: bg,
    onSurface: ink,
    error: const Color(0xFFD64545),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: const RoundedRectangleBorder(borderRadius: r26),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: onInk,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: card,
        side: BorderSide(color: ink, width: 1.2),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: ink)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: ink,
      foregroundColor: onInk,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const CircleBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: ink, width: 1.2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: card,
      shape: const RoundedRectangleBorder(borderRadius: r26),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor:
            WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? ink : card),
        foregroundColor:
            WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? onInk : ink),
        side: const WidgetStatePropertyAll(BorderSide.none),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: C.blue,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: C.dark, fontWeight: FontWeight.w600),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : Colors.transparent),
      checkColor: WidgetStatePropertyAll(onInk),
      side: BorderSide(color: ink, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: bg, surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: ink.withAlpha(20)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: TextStyle(color: onInk),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: ink),
  );
}
