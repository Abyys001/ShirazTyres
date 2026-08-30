import 'package:flutter/material.dart';

/// ShirazTyres palette, shared with the web apps' design tokens.
///
/// Sourced from the brand swatches: gold #FFD700 on the near-black #0B1315,
/// over a cool slate neutral ramp.
abstract final class Brand {
  static const gold = Color(0xFFFFD700);
  static const goldStrong = Color(0xFFFBBF24);
  static const goldDim = Color(0xFF3F2E00);

  static const canvas = Color(0xFF0B1315);
  static const surface = Color(0xFF0F172A);
  static const surfaceRaised = Color(0xFF1E293B);
  static const line = Color(0xFF334155);

  static const ink = Color(0xFFF8FAFC);
  static const inkMuted = Color(0xFFCBD5E1);
  static const inkSubtle = Color(0xFF94A3B8);
  static const onGold = Color(0xFF0B1315);

  static const accent = Color(0xFF0078A8);
  static const info = Color(0xFF3B82F6);
  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFFACC15);
  static const danger = Color(0xFFDC2626);
}

/// High-contrast, big-target theme: this app gets used at night, on a hard
/// shoulder, one-handed. Dark by default — a white screen at 2am is hostile.
ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Brand.gold,
    onPrimary: Brand.onGold,
    primaryContainer: Brand.goldDim,
    onPrimaryContainer: Brand.gold,
    secondary: Brand.accent,
    onSecondary: Brand.ink,
    error: Brand.danger,
    onError: Brand.ink,
    surface: Brand.surface,
    onSurface: Brand.ink,
    surfaceContainerHighest: Brand.surfaceRaised,
    onSurfaceVariant: Brand.inkMuted,
    outline: Brand.line,
    outlineVariant: Brand.line,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.canvas,
    dividerColor: Brand.line,
    textTheme: _textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.canvas,
      foregroundColor: Brand.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: Brand.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.gold,
        foregroundColor: Brand.onGold,
        disabledBackgroundColor: Brand.surfaceRaised,
        disabledForegroundColor: Brand.inkSubtle,
        minimumSize: const Size.fromHeight(54),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.ink,
        side: const BorderSide(color: Brand.line),
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Brand.gold),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      hintStyle: const TextStyle(color: Brand.inkSubtle),
      labelStyle: const TextStyle(color: Brand.inkMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Brand.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Brand.gold, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    cardTheme: CardThemeData(
      color: Brand.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Brand.line),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Brand.surfaceRaised,
      side: BorderSide(color: Brand.line),
      labelStyle: TextStyle(color: Brand.inkMuted, fontWeight: FontWeight.w600, fontSize: 12),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: Brand.ink,
      iconColor: Brand.inkSubtle,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Brand.surfaceRaised,
      contentTextStyle: TextStyle(color: Brand.ink),
      actionTextColor: Brand.gold,
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.gold),
  );
}

/// Tight, heavy headings; comfortable body. Registrations and money use the
/// tabular figures the platform monospace gives us.
const _textTheme = TextTheme(
  displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: Brand.ink),
  headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Brand.ink),
  titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Brand.ink),
  titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Brand.ink),
  bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: Brand.ink),
  bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: Brand.inkMuted),
  bodySmall: TextStyle(fontSize: 12, height: 1.4, color: Brand.inkSubtle),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.ink),
  labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Brand.inkSubtle),
);

/// Registration plates and invoice totals read as data, not prose.
const plateStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['RobotoMono', 'Menlo', 'Courier New'],
  fontSize: 18,
  fontWeight: FontWeight.w700,
  letterSpacing: 3,
  color: Brand.ink,
);

/// Status colours are shared by the chip and the timeline.
Color statusColour(String status) {
  switch (status) {
    case 'submitted':
    case 'dispatching':
    case 'unclaimed':
      return Brand.warning;
    case 'assigned':
    case 'accepted':
      return Brand.info;
    case 'en_route':
    case 'arrived':
      return Brand.accent;
    case 'in_progress':
      return Brand.gold;
    case 'completed':
      return Brand.success;
    case 'cancelled':
      return Brand.inkSubtle;
    default:
      return Brand.inkMuted;
  }
}
