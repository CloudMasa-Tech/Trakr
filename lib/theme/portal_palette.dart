import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_theme_colors.dart';

/// Centralized color tokens for the Super Admin portal.
///
/// Components read their colors from [PortalPalette.of] so the portal can be
/// rendered in dark or light mode without scattering color literals. Values
/// are derived from the global [AppColors] semantic tokens so the portal and
/// the tenant app share a single source of truth.
class PortalPalette extends ThemeExtension<PortalPalette> {
  final Color accent;
  final Color hero;
  final Color border;
  final Color label;
  final Color subtle;
  final Color surface;
  final Color canvas;
  final Color appBar;
  final Color scaffold;
  final Color danger;
  final Color success;

  const PortalPalette({
    required this.accent,
    required this.hero,
    required this.border,
    required this.label,
    required this.subtle,
    required this.surface,
    required this.canvas,
    required this.appBar,
    required this.scaffold,
    required this.danger,
    required this.success,
  });

  static final PortalPalette dark = PortalPalette(
    accent: AppColors.dark.primary,
    hero: AppColors.dark.focus,
    border: AppColors.dark.border,
    label: AppColors.dark.textPrimary,
    subtle: AppColors.dark.textSecondary,
    surface: AppColors.dark.surface,
    canvas: AppColors.dark.tableHeader,
    appBar: AppColors.dark.appBar,
    scaffold: AppColors.dark.background,
    danger: AppColors.dark.error,
    success: AppColors.dark.success,
  );

  static final PortalPalette light = PortalPalette(
    accent: AppColors.light.primary,
    hero: AppColors.light.focus,
    border: AppColors.light.border,
    label: AppColors.light.textPrimary,
    subtle: AppColors.light.textSecondary,
    surface: AppColors.light.surface,
    canvas: AppColors.light.tableHeader,
    appBar: AppColors.light.appBar,
    scaffold: AppColors.light.background,
    danger: AppColors.light.error,
    success: AppColors.light.success,
  );

  static PortalPalette of(BuildContext context) =>
      Theme.of(context).extension<PortalPalette>() ?? dark;

  @override
  PortalPalette copyWith({
    Color? accent,
    Color? hero,
    Color? border,
    Color? label,
    Color? subtle,
    Color? surface,
    Color? canvas,
    Color? appBar,
    Color? scaffold,
    Color? danger,
    Color? success,
  }) {
    return PortalPalette(
      accent: accent ?? this.accent,
      hero: hero ?? this.hero,
      border: border ?? this.border,
      label: label ?? this.label,
      subtle: subtle ?? this.subtle,
      surface: surface ?? this.surface,
      canvas: canvas ?? this.canvas,
      appBar: appBar ?? this.appBar,
      scaffold: scaffold ?? this.scaffold,
      danger: danger ?? this.danger,
      success: success ?? this.success,
    );
  }

  @override
  PortalPalette lerp(ThemeExtension<PortalPalette>? other, double t) {
    if (other is! PortalPalette) return this;
    return PortalPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      hero: Color.lerp(hero, other.hero, t)!,
      border: Color.lerp(border, other.border, t)!,
      label: Color.lerp(label, other.label, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      appBar: Color.lerp(appBar, other.appBar, t)!,
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

/// Builds the `ThemeData` used by the Super Admin portal.
///
/// The portal has its own bespoke look (independent of tenant white-labeling),
/// so it carries its own [PortalPalette] extension plus the global [AppColors]
/// tokens. Material widgets inside the portal pick up the brightness
/// automatically; bespoke components read the palette via
/// [PortalPalette.of] / [AppColors.of].
ThemeData portalTheme({required bool isDark}) {
  final palette = isDark ? PortalPalette.dark : PortalPalette.light;
  final colors = isDark ? AppColors.dark : AppColors.light;
  final base =
      AppTheme.build(brightness: isDark ? Brightness.dark : Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: palette.scaffold,
    canvasColor: palette.surface,
    cardColor: palette.surface,
    dividerColor: palette.border,
    extensions: [palette, colors],
    colorScheme: base.colorScheme.copyWith(
      surface: palette.surface,
      onSurface: colors.textPrimary,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: palette.appBar,
      foregroundColor: colors.textPrimary,
      iconTheme: IconThemeData(color: colors.iconSecondary),
      elevation: 0,
    ),
    iconTheme: IconThemeData(color: colors.iconSecondary),
    disabledColor: colors.disabled,
    hintColor: colors.textMuted,
    dividerTheme: DividerThemeData(color: palette.border),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: isDark ? colors.surfaceRaised : colors.surface,
      hintStyle: TextStyle(color: colors.textMuted),
      labelStyle: TextStyle(color: colors.textSecondary),
      helperStyle: TextStyle(color: colors.textMuted),
      errorStyle: TextStyle(color: colors.error),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.focus, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error, width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? colors.surfaceRaised : colors.surface,
      contentTextStyle: TextStyle(color: colors.textPrimary),
      actionTextColor: colors.focus,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? colors.surfaceRaised : colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? colors.surfaceRaised : colors.surface,
      textStyle: TextStyle(color: colors.textPrimary),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: TextStyle(
        color: colors.textSecondary,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      dataTextStyle: TextStyle(color: colors.textPrimary, fontSize: 13),
      headingRowColor: WidgetStatePropertyAll(colors.tableHeader),
      dataRowColor: WidgetStatePropertyAll(colors.tableRow),
    ),
  );
}
