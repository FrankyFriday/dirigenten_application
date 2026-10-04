import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color midnight = Color(0xFF14233B);
  static const Color canvas = Color(0xFFF3F6FA);
  static const Color teal = Color(0xFF167D83);
  static const Color amber = Color(0xFFF0B44D);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFF72D0C5) : midnight,
      onPrimary: isDark ? const Color(0xFF08201F) : Colors.white,
      secondary: isDark ? const Color(0xFF72D0C5) : teal,
      onSecondary: isDark ? const Color(0xFF08201F) : Colors.white,
      tertiary: amber,
      surface: isDark ? const Color(0xFF17263D) : Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0D1727) : canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF0D1727) : canvas,
        foregroundColor: isDark ? Colors.white : midnight,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : midnight,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: isDark ? Colors.white10 : const Color(0xFFE6EBF2),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1D2D45) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : const Color(0xFFE1E7EF),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : const Color(0xFFE1E7EF),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.secondary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.secondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
