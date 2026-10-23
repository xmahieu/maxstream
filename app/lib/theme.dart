import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0B1220);
  static const panel = Color(0xFF121C2E);
  static const card = Color(0xFF16213A);
  static const cardFocus = Color(0xFF1D2A44);
  static const sel = Color(0xFF2A3A5C);
  static const accent = Color(0xFF29B6F6);
  static const text = Color(0xFFEAF1FB);
  static const muted = Color(0xFFA9B8D0);
  static const dim = Color(0xFF6F7E98);
  static const track = Color(0xFF26324A);
  static const live = Color(0xFFE5484D);
  static const star = Color(0xFFFF9F43);
  static const gold = Color(0xFFFFD58A);
  static const teal = Color(0xFF0E7C6E);
  static const liveTile = Color(0xFFB3283A);
  static const movieTile = Color(0xFF5B32A8);
  static const seriesTile = Color(0xFF1C62C0);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: base.colorScheme.copyWith(primary: C.accent, secondary: C.accent, surface: C.panel),
    focusColor: C.accent.withValues(alpha: 0.25),
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: C.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: C.accent, width: 2)),
      labelStyle: TextStyle(color: C.muted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused) ? C.accent : C.card),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused) ? C.bg : C.text),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: C.panel),
    snackBarTheme: const SnackBarThemeData(backgroundColor: C.cardFocus, contentTextStyle: TextStyle(color: C.text)),
  );
}
