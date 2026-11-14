import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';

/// Preserve the existing post/composer layouts while sharing Android appearance.
/// Light constants stay for legacy callers; pages should read colors from
/// [of] so the post routes follow the app's light or dark appearance.
abstract final class PostTheme {
  static const background = HhTelegramPalette.lightCard;
  static const surface = Color(0xFFFFFFFF);
  static const ink = HhTelegramPalette.lightInk;
  static const cardTint = HhTelegramPalette.lightCard;
  static const failure = Color(0xFFFF1646);
  static const destructive = Color(0xFFE42A22);
  static const errorInk = Color(0xFFB3261E);
  // Platform font fallback only; actual native CJK font availability is device acceptance.
  static const dialogQuestion = TextStyle(
    fontFamily: 'Roboto',
    fontFamilyFallback: ['HhNotoSansSC'],
    fontSize: 18,
    height: 1.5,
    color: ink,
  );
  static const dialogBody = TextStyle(
    fontFamily: 'Roboto',
    fontFamilyFallback: ['HhNotoSansSC'],
    fontSize: 15,
    height: 1.6,
    color: muted,
  );
  static const muted = HhTelegramPalette.lightSecondary;
  static const accent = HhTelegramPalette.lightAccent;
  static const line = HhTelegramPalette.lightLine;

  static ThemeData of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = dark ? HhTelegramPalette.dark : HhTelegramPalette.light;
    final base = HhTelegramTheme.applyAppearance(
      Theme.of(context).copyWith(
        brightness: dark ? Brightness.dark : Brightness.light,
        colorScheme: dark
            ? const ColorScheme.dark()
            : const ColorScheme.light(),
      ),
    );
    return base.copyWith(
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: colors.surface,
      colorScheme: base.colorScheme.copyWith(
        primary: colors.accent,
        onPrimary: colors.onAccent,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        surface: colors.surface,
        onSurface: colors.ink,
        surfaceDim: colors.background,
        surfaceContainerHighest: colors.background,
        onSurfaceVariant: colors.secondary,
        outlineVariant: colors.line,
        error: dark ? colors.error : errorInk,
        onError: dark ? colors.ink : surface,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: colors.ink,
        displayColor: colors.ink,
      ),
      iconTheme: IconThemeData(color: colors.secondary),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: colors.secondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.header,
        foregroundColor: colors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.ink,
        ),
        shape: Border(bottom: BorderSide(color: colors.line)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: BorderSide(color: colors.accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.line,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.action,
          foregroundColor: colors.onAccent,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
