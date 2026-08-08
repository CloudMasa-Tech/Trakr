import 'dart:ui';

import 'package:flutter/material.dart';

/// Semantic color tokens used across the entire application.
///
/// Every screen, component, dialog, table, card, form, sidebar, navbar,
/// button, badge, chart and data grid should read its colors from
/// [AppColors.of] (or `Theme.of(context).colorScheme`), never from hardcoded
/// `Color(...)` literals or `Colors.*` constants.
///
/// Dark and light presets are designed to be WCAG-compliant: primary text is
/// near-white on dark surfaces and near-black on light surfaces, secondary /
/// muted text keeps a contrast ratio above ~4.5:1, and borders stay subtle but
/// visible in both modes.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  // ---- Backgrounds & surfaces -------------------------------------------
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color overlay;
  final Color appBar;
  final Color sidebar;
  final Color sidebarSelected;
  final Color sidebarHover;

  // ---- Borders ------------------------------------------------------------
  final Color border;
  final Color divider;

  // ---- Brand --------------------------------------------------------------
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;

  // ---- Status --------------------------------------------------------------
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color error;
  final Color onError;

  // ---- Text ----------------------------------------------------------------
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textInverse;
  final Color disabled;

  // ---- Icons ---------------------------------------------------------------
  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconMuted;

  // ---- Tables --------------------------------------------------------------
  final Color tableHeader;
  final Color tableRow;
  final Color tableRowAlt;

  // ---- States --------------------------------------------------------------
  final Color hover;
  final Color selected;
  final Color focus;

  // ---- Charts --------------------------------------------------------------
  final List<Color> chartSeries;
  final Color chartGrid;
  final Color chartLabel;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.overlay,
    required this.appBar,
    required this.sidebar,
    required this.sidebarSelected,
    required this.sidebarHover,
    required this.border,
    required this.divider,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.error,
    required this.onError,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textInverse,
    required this.disabled,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.iconMuted,
    required this.tableHeader,
    required this.tableRow,
    required this.tableRowAlt,
    required this.hover,
    required this.selected,
    required this.focus,
    required this.chartSeries,
    required this.chartGrid,
    required this.chartLabel,
  });

  static const AppColors dark = AppColors(
    background: Color(0xFF07151D),
    surface: Color(0xFF0E2633),
    surfaceRaised: Color(0xFF13303F),
    overlay: Color(0xCC07151D),
    appBar: Color(0xFF081923),
    sidebar: Color(0xFF081923),
    sidebarSelected: Color(0xFF14404F),
    sidebarHover: Color(0xFF103041),
    border: Color(0xFF2A5568),
    divider: Color(0xFF1C3F50),
    primary: Color(0xFF0F766E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF16A3A0),
    onPrimaryContainer: Color(0xFF04211F),
    secondary: Color(0xFFFF9F45),
    onSecondary: Color(0xFF2B1402),
    success: Color(0xFF34D399),
    onSuccess: Color(0xFF04281E),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF3B2A05),
    error: Color(0xFFF87171),
    onError: Color(0xFF450F0F),
    textPrimary: Color(0xFFF2F7FA),
    textSecondary: Color(0xFFB7C7D3),
    textMuted: Color(0xFF93A9B9),
    textInverse: Color(0xFF0B1B26),
    disabled: Color(0xFF6E8B9C),
    iconPrimary: Color(0xFFF2F7FA),
    iconSecondary: Color(0xFFB7C7D3),
    iconMuted: Color(0xFF93A9B9),
    tableHeader: Color(0xFF0A1D28),
    tableRow: Color(0xFF0E2633),
    tableRowAlt: Color(0xFF0B2130),
    hover: Color(0xFF16404F),
    selected: Color(0xFF14404F),
    focus: Color(0xFF22D3EE),
    chartSeries: [
      Color(0xFF22D3EE),
      Color(0xFF34D399),
      Color(0xFFA78BFA),
      Color(0xFFFBBF24),
      Color(0xFFF87171),
      Color(0xFF60A5FA),
      Color(0xFFF472B6),
    ],
    chartGrid: Color(0xFF244F61),
    chartLabel: Color(0xFF93A9B9),
  );

  static const AppColors light = AppColors(
    background: Color(0xFFF6FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    overlay: Color(0x66000000),
    appBar: Color(0xFFFFFFFF),
    sidebar: Color(0xFFFFFFFF),
    sidebarSelected: Color(0xFFE6FAFB),
    sidebarHover: Color(0xFFF0F7F8),
    border: Color(0xFFD7E5EA),
    divider: Color(0xFFE2ECF0),
    primary: Color(0xFF0F766E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE6FAFB),
    onPrimaryContainer: Color(0xFF0B4A44),
    secondary: Color(0xFFEF4444),
    onSecondary: Color(0xFFFFFFFF),
    success: Color(0xFF059669),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFFB45309),
    onWarning: Color(0xFFFFFFFF),
    error: Color(0xFFDC2626),
    onError: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF10233F),
    textSecondary: Color(0xFF52647A),
    textMuted: Color(0xFF77889C),
    textInverse: Color(0xFFFFFFFF),
    disabled: Color(0xFF9AA9B8),
    iconPrimary: Color(0xFF1F2937),
    iconSecondary: Color(0xFF52647A),
    iconMuted: Color(0xFF8A9AAE),
    tableHeader: Color(0xFFF1F6F9),
    tableRow: Color(0xFFFFFFFF),
    tableRowAlt: Color(0xFFF8FBFD),
    hover: Color(0xFFEAF3F5),
    selected: Color(0xFFE6FAFB),
    focus: Color(0xFF0F766E),
    chartSeries: [
      Color(0xFF0F766E),
      Color(0xFF22D3EE),
      Color(0xFF7C6FF0),
      Color(0xFFF59E0B),
      Color(0xFFDC2626),
      Color(0xFF10B981),
      Color(0xFFF472B6),
    ],
    chartGrid: Color(0xFFE2ECF0),
    chartLabel: Color(0xFF52647A),
  );

  static AppColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppColors>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
  }

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? overlay,
    Color? appBar,
    Color? sidebar,
    Color? sidebarSelected,
    Color? sidebarHover,
    Color? border,
    Color? divider,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? secondary,
    Color? onSecondary,
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? error,
    Color? onError,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textInverse,
    Color? disabled,
    Color? iconPrimary,
    Color? iconSecondary,
    Color? iconMuted,
    Color? tableHeader,
    Color? tableRow,
    Color? tableRowAlt,
    Color? hover,
    Color? selected,
    Color? focus,
    List<Color>? chartSeries,
    Color? chartGrid,
    Color? chartLabel,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      overlay: overlay ?? this.overlay,
      appBar: appBar ?? this.appBar,
      sidebar: sidebar ?? this.sidebar,
      sidebarSelected: sidebarSelected ?? this.sidebarSelected,
      sidebarHover: sidebarHover ?? this.sidebarHover,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textInverse: textInverse ?? this.textInverse,
      disabled: disabled ?? this.disabled,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconSecondary: iconSecondary ?? this.iconSecondary,
      iconMuted: iconMuted ?? this.iconMuted,
      tableHeader: tableHeader ?? this.tableHeader,
      tableRow: tableRow ?? this.tableRow,
      tableRowAlt: tableRowAlt ?? this.tableRowAlt,
      hover: hover ?? this.hover,
      selected: selected ?? this.selected,
      focus: focus ?? this.focus,
      chartSeries: chartSeries ?? this.chartSeries,
      chartGrid: chartGrid ?? this.chartGrid,
      chartLabel: chartLabel ?? this.chartLabel,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      appBar: Color.lerp(appBar, other.appBar, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarSelected: Color.lerp(sidebarSelected, other.sidebarSelected, t)!,
      sidebarHover: Color.lerp(sidebarHover, other.sidebarHover, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer:
          Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      onSecondary: Color.lerp(onSecondary, other.onSecondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconSecondary: Color.lerp(iconSecondary, other.iconSecondary, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      tableHeader: Color.lerp(tableHeader, other.tableHeader, t)!,
      tableRow: Color.lerp(tableRow, other.tableRow, t)!,
      tableRowAlt: Color.lerp(tableRowAlt, other.tableRowAlt, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      chartSeries: t < 0.5 ? chartSeries : other.chartSeries,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      chartLabel: Color.lerp(chartLabel, other.chartLabel, t)!,
    );
  }
}

/// Legacy brand constants kept for gradient/branding use and backward
/// compatibility. New code should prefer [AppColors.of] / ThemeData tokens.
class AppThemeColors {
  const AppThemeColors._();

  /// Resolves the active [AppColors] semantic tokens for [context].
  ///
  /// Provided as a convenience alias so callers can use
  /// `AppThemeColors.of(context).textPrimary` — same result as
  /// `AppColors.of(context)`.
  static AppColors of(BuildContext context) => AppColors.of(context);

  static const headingStart = Color(0xFFEF4444);
  static const headingEnd = Color(0xFFF97316);

  static const actionStart = Color(0xFF0F766E);
  static const actionMiddle = Color(0xFF155E75);
  static const actionEnd = Color(0xFF1E3A8A);

  static const lightText = Color(0xFF10233F);
  static const lightMuted = Color(0xFF607089);
  static const lightScaffold = Color(0xFFF6FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceTint = Color(0xFFE6FAFB);
  static const lightBorder = Color(0xFFD7E5EA);

  static const darkText = Color(0xFFF8FBFC);
  static const darkMuted = Color(0xFFB7C7D3);
  static const darkScaffold = Color(0xFF07151D);
  static const darkCanvas = Color(0xFF0A1D28);
  static const darkSurface = Color(0xFF0E2633);
  static const darkAppBar = Color(0xFF081923);
  static const darkBorder = Color(0xFF183A48);
  static const backgroundLight = Color(0xFFF8FBFF);
  static const backgroundDark = Color(0xFF07151D);

  static const LinearGradient headingGradient = LinearGradient(
    colors: [headingStart, headingEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient actionGradient = LinearGradient(
    colors: [actionStart, actionMiddle, actionEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static Color headingAccent(bool isDark) =>
      isDark ? const Color(0xFFFF9F45) : headingStart;

  static Color actionAccent(bool isDark) =>
      isDark ? const Color(0xFF22D3EE) : actionStart;

  // ── Brand splash art (launch screen) ───────────────────────────────────
  // The launch screen is a fixed, brand-owned animation and deliberately does
  // not follow the active theme. These constants keep its colors centralized.
  static const launchBackground = Color(0xFF001F3F);
  static const launchOrbitFlame = Color(0xFFFFC857);
  static const launchOrbitCore = Color(0xFFFFF4C7);
  static const launchOrbitCyan = Color(0xFF71D8FF);
  static const launchStarWhite = Colors.white;

  // ── Work-anniversary celebration dialog ────────────────────────────────
  // The anniversary "Congratulations" card is a fixed brand celebration
  // overlay (dark navy card + gold accents) that reads clearly over either
  // theme, so its colors are centralized constants rather than theme tokens.
  static const celebrationBackground = Color(0xFF082A44);
  static const celebrationBorder = Color(0x33FFFFFF);
  static const celebrationTitle = Color(0xFFFFFFFF);
  static const celebrationSubtitle = Color(0xFFE7F6FF);
  static const celebrationGold = Color(0xFFFFD166);
  static const celebrationFlame = Color(0xFFFF7A18);
  static const celebrationGoldStart = Color(0xFFFFC857);

  // ── Google "G" logo (Google Sign-In button glyph) ───────────────────────
  // Fixed brand colors for the Google logo; not theme tokens.
  static const googleBlue = Color(0xFF4285F4);
  static const googleRed = Color(0xFFEA4335);
  static const googleYellow = Color(0xFFFBBC05);
  static const googleGreen = Color(0xFF34A853);
  static const googleGreenDark = Color(0xFF0F9D58);
}

class AppBackground extends StatelessWidget {
  final Widget child;
  final bool followDarkMode;
  final bool forceDark;

  const AppBackground({
    super.key,
    required this.child,
    this.followDarkMode = false,
    this.forceDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = forceDark ||
        (followDarkMode && Theme.of(context).brightness == Brightness.dark);
    final colors = isDark ? AppColors.dark : AppColors.light;
    final background = colors.background;
    final circleOpacity = isDark ? 0.12 : 0.08;

    return ColoredBox(
      color: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned(
                          top: constraints.maxHeight * 0.25,
                          left: -128,
                          child: _BlurCircle(
                            color: colors.focus,
                            opacity: circleOpacity,
                          ),
                        ),
                        Positioned(
                          right: -128,
                          bottom: constraints.maxHeight * 0.25,
                          child: _BlurCircle(
                            color: const Color(0xFFA855F7),
                            opacity: circleOpacity,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: child),
            ],
          );
        },
      ),
    );
  }
}

class AppScaffoldBackground extends StatelessWidget {
  final Widget child;

  const AppScaffoldBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: child,
      ),
    );
  }
}

class _BlurCircle extends StatelessWidget {
  final Color color;
  final double opacity;

  const _BlurCircle({
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 72, sigmaY: 72),
      child: Container(
        width: 384,
        height: 384,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
        ),
      ),
    );
  }
}

class AppGradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AppGradientText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          AppThemeColors.headingGradient.createShader(bounds),
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        style: style,
      ),
    );
  }
}
