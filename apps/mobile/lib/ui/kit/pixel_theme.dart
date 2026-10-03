import 'package:flutter/material.dart';

/// The mockups' palette and type (style guide board): flat colour, one dark
/// outline pixel, chunky bevels.
abstract final class Px {
  static const ink = Color(0xFF0D1120);
  static const night = Color(0xFF1E2230);
  static const panel = Color(0xFF2A2F45);
  static const edge = Color(0xFF3B4A6B);
  static const paper = Color(0xFFF3F1E6);
  static const fuse = Color(0xFFFFD23F);
  static const fuseDark = Color(0xFFC98F1C);
  static const blast = Color(0xFFFF7A1A);
  static const grass = Color(0xFF62B060);
  static const brick = Color(0xFFB45A2C);
  static const stone = Color(0xFF6F7890);
  static const muted = Color(0xFF9AA3B8);
  static const danger = Color(0xFFFF4B4B);
  static const ok = Color(0xFF3FC062);

  /// Titles, timers and room codes.
  static const display = 'PressStart2P';

  /// Buttons, labels and body copy.
  static const body = 'Silkscreen';

  static TextStyle title(double size, {Color color = paper}) =>
      TextStyle(fontFamily: display, fontSize: size, color: color, height: 1.3);

  static TextStyle label(
    double size, {
    Color color = paper,
    bool bold = true,
  }) => TextStyle(
    fontFamily: body,
    fontSize: size,
    color: color,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
  );

  static ThemeData theme() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: body,
      colorScheme: const ColorScheme.dark(
        primary: fuse,
        onPrimary: night,
        secondary: edge,
        onSecondary: paper,
        surface: night,
        onSurface: paper,
        error: danger,
      ),
      scaffoldBackgroundColor: ink,
    );
    const square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
    return base.copyWith(
      cardTheme: const CardThemeData(
        color: night,
        shape: RoundedRectangleBorder(side: BorderSide(color: edge, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: fuse,
          foregroundColor: night,
          shape: square,
          side: const BorderSide(color: night, width: 3),
          textStyle: label(14),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: panel,
          foregroundColor: paper,
          shape: square,
          side: const BorderSide(color: edge, width: 3),
          textStyle: label(14),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: fuse,
          shape: square,
          textStyle: label(13),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: ink,
        side: const BorderSide(color: edge, width: 2),
        shape: square,
        labelStyle: label(12),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: ink,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: edge, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: edge, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: fuse, width: 2),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: night,
        shape: RoundedRectangleBorder(side: BorderSide(color: edge, width: 3)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: night,
        contentTextStyle: label(13),
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: danger, width: 2),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// An opaque bevelled panel, the mockups' menu surface.
class PxPanel extends StatelessWidget {
  const PxPanel({
    super.key,
    required this.child,
    this.border = Px.edge,
    this.color = Px.night,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color border;
  final Color color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: border, width: 3),
      boxShadow: const [BoxShadow(color: Px.ink, offset: Offset(4, 4))],
    ),
    child: child,
  );
}
