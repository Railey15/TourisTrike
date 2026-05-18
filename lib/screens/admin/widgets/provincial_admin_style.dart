import 'package:flutter/material.dart';

class ProvincialAdminColors {
  const ProvincialAdminColors._();

  static const background = Color(0xFFF4F8FF);
  static const backgroundAlt = Color(0xFFEAF5FF);
  static const card = Colors.white;
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const lightMuted = Color(0xFF94A3B8);
  static const blue = Color(0xFF2A86FF);
  static const deepBlue = Color(0xFF1E63E9);
  static const cyan = Color(0xFF0EA5E9);
  static const green = Color(0xFF16A34A);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFDC2626);
  static const purple = Color(0xFF7C3AED);
  static const line = Color(0xFFE4ECF7);
  static const shadow = Color(0x12000000);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5DB4FF), Color(0xFF2A86FF), Color(0xFF1E63E9)],
  );
}

BoxShadow provincialAdminShadow({double alpha = 0.055}) {
  return BoxShadow(
    color: Colors.black.withValues(alpha: alpha),
    blurRadius: 24,
    offset: const Offset(0, 14),
  );
}
