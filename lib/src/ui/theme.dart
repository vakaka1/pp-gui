import 'package:flutter/material.dart';

/// GitHub Dark Default color palette.
abstract final class PpColors {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const card = Color(0xFF21262D);
  static const border = Color(0xFF30363D);
  static const accent = Color(0xFF58A6FF);
  static const green = Color(0xFF3FB950);
  static const red = Color(0xFFF85149);
  static const orange = Color(0xFFD29922);
  static const text = Color(0xFFE6EDF3);
  static const textDim = Color(0xFF8B949E);
}

ThemeData ppDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: PpColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: PpColors.accent,
      secondary: PpColors.accent,
      secondaryContainer: PpColors.border,
      onSecondaryContainer: PpColors.text,
      surface: PpColors.surface,
      surfaceContainerHighest: PpColors.card,
      error: PpColors.red,
      onPrimary: Colors.white,
      onSurface: PpColors.text,
      onError: Colors.white,
      outline: PpColors.border,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PpColors.bg,
      foregroundColor: PpColors.text,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: PpColors.surface,
      indicatorColor: PpColors.accent.withValues(alpha: 0.18),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: PpColors.accent);
        }
        return const IconThemeData(color: PpColors.textDim);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
              color: PpColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600);
        }
        return const TextStyle(color: PpColors.textDim, fontSize: 12);
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: PpColors.border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: PpColors.accent),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: PpColors.textDim),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: PpColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: PpColors.accent),
      ),
      isDense: true,
      filled: true,
      fillColor: PpColors.surface,
      labelStyle: const TextStyle(color: PpColors.textDim),
      hintStyle: const TextStyle(color: PpColors.textDim),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return PpColors.accent;
        return PpColors.textDim;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return PpColors.accent.withValues(alpha: 0.3);
        }
        return PpColors.border;
      }),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: PpColors.card,
      contentTextStyle: TextStyle(color: PpColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PpColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PpColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: PpColors.border,
    ),
    listTileTheme: const ListTileThemeData(
      textColor: PpColors.text,
      iconColor: PpColors.textDim,
    ),
    dividerTheme: const DividerThemeData(color: PpColors.border),
    visualDensity: VisualDensity.compact,
  );
}
