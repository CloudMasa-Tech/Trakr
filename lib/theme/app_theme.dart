import 'package:flutter/material.dart';

import 'app_theme_colors.dart';

/// Builds the single source of truth [ThemeData] for the entire application.
///
/// Both the tenant-facing app ([WhiteLabelProvider]) and the Super Admin
/// portal (`portalTheme`) derive their themes from this builder so every
/// Material component, dialog, table, form field, button and sidebar gets the
/// same theme-aware treatment in light and dark mode.
///
/// Components should read colors from `Theme.of(context).colorScheme` or
/// [AppColors.of] / [AppThemeColors.of], never from hardcoded literals.
abstract final class AppTheme {
  /// Computes a readable `onColor` for an arbitrary brand [primary].
  static Color _contrasting(Color primary) {
    return primary.computeLuminance() > 0.5
        ? const Color(0xFF10233F)
        : const Color(0xFFFFFFFF);
  }

  /// Builds the complete theme. Pass [primary] to override the brand color
  /// (used by tenant white-labeling); it defaults to the token color.
  static ThemeData build({
    required Brightness brightness,
    Color? primary,
  }) {
    final isDark = brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;
    final primaryColor = primary ?? colors.primary;
    final onPrimaryColor = _contrasting(primaryColor);

    const radius = 12.0;
    const inputRadius = 12.0;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(inputRadius),
      borderSide: BorderSide(color: colors.border),
    );
    const dialogRadius = 18.0;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primaryColor,
      onPrimary: onPrimaryColor,
      primaryContainer: colors.primaryContainer,
      onPrimaryContainer: colors.onPrimaryContainer,
      secondary: colors.secondary,
      onSecondary: colors.onSecondary,
      secondaryContainer:
          isDark ? const Color(0xFF34264A) : const Color(0xFFEFE7FB),
      onSecondaryContainer:
          isDark ? const Color(0xFFE4D8FF) : const Color(0xFF2A2040),
      tertiary: isDark ? const Color(0xFF22D3EE) : const Color(0xFF0F766E),
      onTertiary: isDark ? const Color(0xFF04211F) : const Color(0xFFFFFFFF),
      tertiaryContainer: colors.primaryContainer,
      onTertiaryContainer: colors.onPrimaryContainer,
      error: colors.error,
      onError: colors.onError,
      errorContainer:
          isDark ? const Color(0xFF5C1E2E) : const Color(0xFFFDE3E9),
      onErrorContainer:
          isDark ? const Color(0xFFFFDAD6) : const Color(0xFF3B0D16),
      surface: colors.surface,
      onSurface: colors.textPrimary,
      surfaceContainerLowest: isDark ? colors.background : colors.tableRowAlt,
      surfaceContainerLow: isDark ? colors.background : colors.tableHeader,
      surfaceContainer: isDark ? colors.surface : colors.tableRowAlt,
      surfaceContainerHigh: isDark ? colors.surfaceRaised : colors.surface,
      surfaceContainerHighest:
          isDark ? colors.surfaceRaised : colors.tableHeader,
      onSurfaceVariant: colors.textSecondary,
      outline: colors.border,
      outlineVariant: colors.divider,
      shadow: isDark ? const Color(0xFF000000) : const Color(0x33000000),
      scrim: const Color(0xFF000000),
      inverseSurface:
          isDark ? const Color(0xFFE4ECF1) : const Color(0xFF1C2430),
      onInverseSurface:
          isDark ? const Color(0xFF0B1B26) : const Color(0xFFFFFFFF),
      inversePrimary: isDark ? colors.primaryContainer : colors.primary,
      surfaceTint: Colors.transparent,
    );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme.apply(
          bodyColor: colors.textPrimary,
          displayColor: colors.textPrimary,
          fontFamily: 'Poppins',
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Poppins',
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      cardColor: colors.surface,
      dividerColor: colors.divider,
      disabledColor: colors.disabled,
      hintColor: colors.textMuted,
      splashColor: colors.hover.withValues(alpha: 0.35),
      highlightColor: Colors.transparent,
      hoverColor: colors.hover.withValues(alpha: 0.55),
      focusColor: colors.focus.withValues(alpha: 0.12),
      extensions: [colors],
      textTheme: baseTextTheme,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.focus,
        selectionColor: colors.selected.withValues(alpha: 0.6),
        selectionHandleColor: colors.focus,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.appBar,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontFamily: 'Poppins',
        ),
        iconTheme: IconThemeData(color: colors.iconSecondary),
        actionsIconTheme: IconThemeData(color: colors.iconSecondary),
      ),
      iconTheme: IconThemeData(color: colors.iconSecondary),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        hintStyle: TextStyle(color: colors.textMuted, fontSize: 13.5),
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13.5),
        floatingLabelStyle:
            TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
        helperStyle: TextStyle(color: colors.textMuted, fontSize: 12),
        helperMaxLines: 2,
        errorStyle: TextStyle(color: colors.error, fontSize: 12),
        prefixIconColor: colors.iconSecondary,
        suffixIconColor: colors.iconSecondary,
        counterStyle: TextStyle(color: colors.textMuted, fontSize: 11),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colors.focus, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colors.error, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimaryColor,
          disabledBackgroundColor: primaryColor.withValues(alpha: 0.45),
          disabledForegroundColor: colors.disabled,
          elevation: 0,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimaryColor,
          disabledBackgroundColor: primaryColor.withValues(alpha: 0.45),
          disabledForegroundColor: colors.disabled,
          minimumSize: const Size(0, 44),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? colors.focus : colors.primary,
          disabledForegroundColor: colors.disabled,
          minimumSize: const Size(0, 44),
          side: BorderSide(color: colors.border),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? colors.focus : colors.primary,
          disabledForegroundColor: colors.disabled,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.iconSecondary,
          disabledForegroundColor: colors.disabled,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? colors.surfaceRaised : colors.tableHeader,
        selectedColor: colors.primaryContainer,
        disabledColor: colors.surfaceRaised,
        side: BorderSide(color: colors.border),
        labelStyle: TextStyle(color: colors.textPrimary, fontSize: 12.5),
        secondaryLabelStyle:
            TextStyle(color: colors.textPrimary, fontSize: 12.5),
        brightness: brightness,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? colors.surfaceRaised : colors.surface,
        contentTextStyle: TextStyle(color: colors.textPrimary, fontSize: 14),
        actionTextColor: colors.focus,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? colors.surfaceRaised : colors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontFamily: 'Poppins',
        ),
        contentTextStyle:
            TextStyle(color: colors.textSecondary, fontSize: 14, height: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogRadius),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? colors.surfaceRaised : colors.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: colors.textPrimary, fontSize: 13.5),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border.withValues(alpha: 0.6)),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          fontFamily: 'Poppins',
        ),
        dataTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontFamily: 'Poppins',
        ),
        headingRowColor: WidgetStatePropertyAll(colors.tableHeader),
        dataRowColor: WidgetStatePropertyAll(colors.tableRow),
        dividerThickness: 1,
        headingRowHeight: 48,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 56,
        horizontalMargin: 20,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            isDark ? colors.surfaceRaised : colors.surface,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.border),
            ),
          ),
        ),
        textStyle: TextStyle(color: colors.textPrimary, fontSize: 13.5),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colors.surface,
          hintStyle: TextStyle(color: colors.textMuted),
          labelStyle: TextStyle(color: colors.textSecondary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(inputRadius),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(inputRadius),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(inputRadius),
            borderSide: BorderSide(color: colors.focus, width: 1.6),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: isDark ? colors.surfaceRaised : colors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: colors.primary,
        headerForegroundColor: onPrimaryColor,
        dayForegroundColor: WidgetStatePropertyAll(colors.textPrimary),
        dayStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontFamily: 'Poppins',
        ),
        dayOverlayColor:
            WidgetStatePropertyAll(colors.hover.withValues(alpha: 0.5)),
        weekdayStyle: TextStyle(
          color: colors.textSecondary,
          fontSize: 12,
          fontFamily: 'Poppins',
        ),
        yearForegroundColor: WidgetStatePropertyAll(colors.textPrimary),
        rangeSelectionBackgroundColor: colors.selected,
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: isDark ? colors.focus : colors.primary,
        ),
        confirmButtonStyle: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimaryColor,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogRadius),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: isDark ? colors.surfaceRaised : colors.surface,
        hourMinuteColor: colors.surfaceRaised,
        hourMinuteTextColor: colors.textPrimary,
        dayPeriodColor: colors.surfaceRaised,
        dayPeriodTextColor: colors.textPrimary,
        dialHandColor: colors.primary,
        dialBackgroundColor: isDark ? colors.surface : colors.tableHeader,
        entryModeIconColor: colors.iconSecondary,
        helpTextStyle: TextStyle(color: colors.textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogRadius),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 12,
          fontFamily: 'Poppins',
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.focus,
        dividerColor: colors.divider,
        labelStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          fontFamily: 'Poppins',
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? colors.surfaceRaised : colors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: isDark ? colors.surfaceRaised : colors.surface,
        modalBarrierColor: colors.overlay,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? colors.surfaceRaised : colors.surface,
        selectedItemColor: colors.primary,
        unselectedItemColor: colors.iconSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? colors.surfaceRaised : colors.surface,
        indicatorColor: colors.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.iconSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? colors.textPrimary
                : colors.textSecondary,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            fontFamily: 'Poppins',
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.sidebar,
        indicatorColor: colors.primaryContainer,
        selectedIconTheme: IconThemeData(color: colors.primary, size: 22),
        unselectedIconTheme:
            IconThemeData(color: colors.iconSecondary, size: 22),
        selectedLabelTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colors.textSecondary,
          fontSize: 11,
          fontFamily: 'Poppins',
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: colors.textPrimary,
        iconColor: colors.iconSecondary,
        subtitleTextStyle:
            TextStyle(color: colors.textSecondary, fontSize: 12.5),
        tileColor: Colors.transparent,
        selectedTileColor: colors.selected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        checkColor: WidgetStatePropertyAll(onPrimaryColor),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return Colors.transparent;
        }),
        side: BorderSide(color: colors.border, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return colors.iconSecondary;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return onPrimaryColor;
          return colors.iconSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return colors.surfaceRaised;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return colors.border;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: colors.surfaceRaised,
        thumbColor: primaryColor,
        overlayColor: primaryColor.withValues(alpha: 0.12),
        valueIndicatorColor: primaryColor,
        valueIndicatorTextStyle:
            TextStyle(color: onPrimaryColor, fontWeight: FontWeight.w700),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceRaised,
        circularTrackColor: colors.surfaceRaised,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.primaryContainer;
            }
            return colors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.onPrimaryContainer;
            }
            return colors.textSecondary;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: colors.error,
        textColor: colors.onError,
        textStyle: TextStyle(
          color: colors.onError,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: 'Poppins',
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => colors.iconMuted.withValues(alpha: 0.5),
        ),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: onPrimaryColor,
        elevation: 2,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            isDark ? colors.surfaceRaised : colors.surface,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.border),
            ),
          ),
        ),
      ),
    );
  }
}
