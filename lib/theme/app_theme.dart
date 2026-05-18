import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color _textPrimary = Color(0xFF0F172A);
  static const Color _textSecondary = Color(0xFF64748B);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2A86FF),
        brightness: Brightness.light,
      ),
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .copyWith(
          displayLarge: GoogleFonts.plusJakartaSans(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            height: 1.05,
            letterSpacing: -0.8,
            color: _textPrimary,
          ),
          headlineLarge: GoogleFonts.plusJakartaSans(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1.08,
            letterSpacing: -0.5,
            color: _textPrimary,
          ),
          headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.12,
            letterSpacing: -0.3,
            color: _textPrimary,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: _textPrimary,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.25,
            color: _textPrimary,
          ),
          titleSmall: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.25,
            color: _textPrimary,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: _textPrimary,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: _textPrimary,
          ),
          bodySmall: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: _textSecondary,
          ),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: Colors.white,
            letterSpacing: 0.2,
          ),
          labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.25,
            color: _textPrimary,
          ),
          labelSmall: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: 1.0,
            color: _textSecondary,
          ),
        )
        .apply(
          bodyColor: _textPrimary,
          displayColor: _textPrimary,
        );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}

class AppTextStyles {
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color linkBlue = Color(0xFF2A86FF);

  static TextStyle hero(BuildContext context) {
    return Theme.of(context).textTheme.headlineLarge!;
  }

  static TextStyle subtitle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: textSecondary,
          fontWeight: FontWeight.w500,
        );
  }

  static TextStyle sectionLabel(BuildContext context) {
    return Theme.of(context).textTheme.labelSmall!.copyWith(
          color: textPrimary.withValues(alpha: 0.55),
          letterSpacing: 1.1,
        );
  }

  static TextStyle fieldLabel(BuildContext context) {
    return Theme.of(context).textTheme.titleSmall!.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        );
  }

  static TextStyle tab(
    BuildContext context, {
    required bool selected,
  }) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
          color: selected ? textPrimary : textMuted,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        );
  }

  static TextStyle input(BuildContext context) {
    return Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontWeight: FontWeight.w500,
        );
  }

  static TextStyle hint(BuildContext context) {
    return Theme.of(context).textTheme.bodyLarge!.copyWith(
          color: textMuted,
          fontWeight: FontWeight.w500,
        );
  }

  static TextStyle roleChip(
    BuildContext context, {
    required Color color,
  }) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        );
  }

  static TextStyle button(BuildContext context) {
    return Theme.of(context).textTheme.labelLarge!;
  }

  static TextStyle helper(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall!.copyWith(
          color: textSecondary.withValues(alpha: 0.95),
        );
  }

  static TextStyle link(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall!.copyWith(
          color: linkBlue,
          fontWeight: FontWeight.w700,
        );
  }

  static TextStyle status(
    BuildContext context, {
    required Color color,
  }) {
    return Theme.of(context).textTheme.labelMedium!.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        );
  }
}
