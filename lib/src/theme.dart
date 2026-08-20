import 'package:flutter/material.dart';

abstract final class VoxoraColors {
  static const background = Color(0xFF0C0C0B);
  static const surface = Color(0xFF1A1A18);
  static const surfaceRaised = Color(0xFF20201D);
  static const surfaceSoft = Color(0xFF141412);
  static const border = Color(0xFF2F2F2B);
  static const borderStrong = Color(0xFF45453F);
  static const accent = Color(0xFFEF4444);
  static const toggle = Color(0xFF10B981);
  static const cyan = Color(0xFFEAEAEA);
  static const text = Color(0xFFEAEAEA);
  static const muted = Color(0xFF8C8C8A);
  static const mutedStrong = Color(0xFFC2C2C0);
  static const ink = Color(0xFF111110);
  static const danger = Color(0xFFEF4444);
}

abstract final class VoxoraTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: VoxoraColors.text,
      onPrimary: VoxoraColors.ink,
      secondary: VoxoraColors.accent,
      onSecondary: Colors.white,
      surface: VoxoraColors.surface,
      onSurface: VoxoraColors.text,
      error: VoxoraColors.danger,
      outline: VoxoraColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: VoxoraColors.background,
      canvasColor: VoxoraColors.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: VoxoraColors.text,
          fontSize: 30,
          height: 1.08,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
        headlineSmall: TextStyle(
          color: VoxoraColors.text,
          fontSize: 22,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.45,
        ),
        titleLarge: TextStyle(
          color: VoxoraColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
        titleMedium: TextStyle(
          color: VoxoraColors.text,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: VoxoraColors.text,
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: VoxoraColors.mutedStrong,
          fontSize: 14,
          height: 1.45,
        ),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VoxoraColors.surfaceSoft,
        hintStyle: const TextStyle(color: VoxoraColors.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: VoxoraColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: VoxoraColors.text, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: VoxoraColors.danger),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VoxoraColors.surfaceRaised,
        contentTextStyle: const TextStyle(color: VoxoraColors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: VoxoraColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: VoxoraColors.border,
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: VoxoraColors.text,
        linearTrackColor: VoxoraColors.border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VoxoraColors.toggle;
          }
          return VoxoraColors.mutedStrong;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VoxoraColors.toggle.withValues(alpha: 0.42);
          }
          return VoxoraColors.borderStrong;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return VoxoraColors.border;
        }),
      ),
    );
  }
}
