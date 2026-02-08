import 'package:flutter/material.dart';

/// Shared studio color tokens for the BrushLoop UI.
class StudioPalette {
  /// Main workspace background.
  static const Color workspace = Color(0xFF161616);

  /// Secondary chrome background.
  static const Color chrome = Color(0xFF202020);

  /// Elevated panel background.
  static const Color panel = Color(0xFF2A2A2A);

  /// Subtle accent panel background.
  static const Color panelSoft = Color(0xFF323232);

  /// Primary border color used across chrome surfaces.
  static const Color border = Color(0xFF444444);

  /// Muted foreground text color.
  static const Color textMuted = Color(0xFFB8B8B8);

  /// High-contrast foreground text color.
  static const Color textStrong = Color(0xFFF1F1F1);

  /// Primary action color.
  static const Color accent = Color(0xFF2C8DFF);

  /// Positive action color.
  static const Color success = Color(0xFF3CB179);

  /// Destructive action color.
  static const Color danger = Color(0xFFC45353);
}

/// Application-wide theme that approximates desktop creative tools.
ThemeData buildStudioTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: false,
    scaffoldBackgroundColor: StudioPalette.workspace,
    colorScheme: const ColorScheme.dark(
      surface: StudioPalette.chrome,
      primary: StudioPalette.accent,
      secondary: StudioPalette.accent,
    ),
  );

  return base.copyWith(
    dividerColor: StudioPalette.border,
    textTheme: base.textTheme.apply(
      bodyColor: StudioPalette.textStrong,
      displayColor: StudioPalette.textStrong,
      fontFamily: 'Avenir Next',
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF0F0F0F),
      contentTextStyle: TextStyle(color: StudioPalette.textStrong),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: StudioPalette.panel,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: StudioPalette.border),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1C1C1C),
      hintStyle: const TextStyle(color: StudioPalette.textMuted),
      labelStyle: const TextStyle(color: StudioPalette.textMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: StudioPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: StudioPalette.accent),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: StudioPalette.border),
      ),
    ),
  );
}

/// Gradient-backed background used by major screens.
class StudioBackdrop extends StatelessWidget {
  /// Creates the studio backdrop.
  const StudioBackdrop({super.key, required this.child});

  /// Foreground screen content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF1D1D1D), Color(0xFF111111)],
        ),
      ),
      child: child,
    );
  }
}

/// Reusable boxed panel with studio chrome styling.
class StudioPanel extends StatelessWidget {
  /// Creates a studio panel.
  const StudioPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color = StudioPalette.panel,
  });

  /// Panel contents.
  final Widget child;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  /// Panel background color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: StudioPalette.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Primary rectangular button with studio styling.
class StudioButton extends StatelessWidget {
  /// Creates a studio button.
  const StudioButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.danger = false,
  });

  /// Button label.
  final String label;

  /// Tap handler.
  final VoidCallback? onPressed;

  /// Optional icon.
  final IconData? icon;

  /// Whether to render using a destructive palette.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bgColor = danger ? StudioPalette.danger : StudioPalette.accent;
    final disabled = onPressed == null;
    return Material(
      color: disabled ? StudioPalette.panelSoft : bgColor,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 16, color: StudioPalette.textStrong),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: StudioPalette.textStrong,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact square icon button used for toolbars.
class StudioIconButton extends StatelessWidget {
  /// Creates a compact icon button.
  const StudioIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.active = false,
    this.tooltip,
  });

  /// Icon glyph.
  final IconData icon;

  /// Tap handler.
  final VoidCallback? onPressed;

  /// Indicates selected state.
  final bool active;

  /// Optional tooltip label.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final widget = Material(
      color: active ? StudioPalette.accent : StudioPalette.panelSoft,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 16,
            color: StudioPalette.textStrong,
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return widget;
    }

    return Tooltip(message: tooltip!, child: widget);
  }
}

/// Small title used at panel boundaries.
class StudioSectionLabel extends StatelessWidget {
  /// Creates a section label.
  const StudioSectionLabel(this.text, {super.key});

  /// Label value.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: StudioPalette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}
