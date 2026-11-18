import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Central design tokens for the RCZ Kanyama app.
///
/// The palette is built around the church identity: a deep Reformed navy,
/// warm brass gold and calm, paper-like neutrals. Every colour used by the
/// interface should come from here so light and dark themes stay readable.
abstract final class AppColors {
  // Brand
  static const navy = Color(0xFF182759);
  static const navyDeep = Color(0xFF0D1638);
  static const navyMid = Color(0xFF243B82);
  static const blue = Color(0xFF3350B4);
  static const gold = Color(0xFFC19A3F);
  static const goldLight = Color(0xFFE7CB86);
  static const sage = Color(0xFF3F6B5B);

  // Light neutrals
  static const lightBackground = Color(0xFFF4F5F9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceSunken = Color(0xFFEDF0F6);
  static const lightOutline = Color(0xFFE2E6EF);
  static const lightInk = Color(0xFF101828);
  static const lightMuted = Color(0xFF5A6478);

  // Dark neutrals
  static const darkBackground = Color(0xFF090E1B);
  static const darkSurface = Color(0xFF111726);
  static const darkSurfaceRaised = Color(0xFF161E31);
  static const darkSurfaceSunken = Color(0xFF0C1222);
  static const darkOutline = Color(0xFF28324B);
  static const darkInk = Color(0xFFE9EDF8);
  static const darkMuted = Color(0xFFA2ADC4);
}

abstract final class AppRadii {
  static const card = 20.0;
  static const field = 14.0;
  static const pill = 999.0;
  static const sheet = 28.0;
  static const dialog = 24.0;
}

abstract final class AppSpacing {
  static const page = 20.0;
  static const section = 28.0;
  static const gap = 12.0;
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = _scheme(isDark);
    final textTheme = _textTheme(colors);
    final horizon = BorderSide(
      color: isDark ? AppColors.darkOutline : AppColors.lightOutline,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      canvasColor: colors.surface,
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: horizon,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: colors.onSurface, size: 22),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        modalBackgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
        dragHandleColor: colors.outlineVariant,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
          height: 1.55,
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? colors.surfaceContainerHighest
            : AppColors.navyDeep,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? colors.onSurface : Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        elevation: 6,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 14.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.field),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 14),
          side: BorderSide(
            color: isDark ? colors.outline : colors.outlineVariant,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.field),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.onSurfaceVariant,
          highlightColor: colors.primary.withValues(alpha: .08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 3,
        focusElevation: 4,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant.withValues(alpha: .75),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.labelLarge?.copyWith(
          color: colors.primary,
        ),
        prefixIconColor: colors.onSurfaceVariant,
        suffixIconColor: colors.onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide(
            color: isDark ? colors.outlineVariant : Colors.transparent,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide(color: colors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide(color: colors.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide(color: colors.error, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        selectedColor: colors.primaryContainer,
        disabledColor: colors.surfaceContainerHigh,
        side: BorderSide(color: colors.outlineVariant),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
        checkmarkColor: colors.primary,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
          height: 1.45,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 24,
      ),
      switchTheme: SwitchThemeData(
        // The inactive thumb must contrast with the track. Mapping both to
        // surfaceContainerHighest made the light-theme switch disappear.
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return (isDark ? AppColors.darkMuted : AppColors.lightMuted)
                .withValues(alpha: .55);
          }
          if (states.contains(WidgetState.selected)) return colors.onPrimary;
          return isDark ? AppColors.darkInk : AppColors.lightMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.surfaceContainerHighest.withValues(alpha: .55);
          }
          if (states.contains(WidgetState.selected)) return colors.primary;
          return isDark
              ? AppColors.darkSurfaceSunken
              : AppColors.lightSurfaceSunken;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected) ||
              states.contains(WidgetState.disabled)) {
            return Colors.transparent;
          }
          return isDark ? AppColors.darkOutline : AppColors.lightMuted;
        }),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => colors.primary.withValues(alpha: .12),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.surfaceContainerHighest,
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: .12),
        valueIndicatorColor: colors.primary,
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: colors.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: colors.error,
        textColor: colors.onError,
        textStyle: textTheme.labelSmall?.copyWith(
          color: colors.onError,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: colors.onSurfaceVariant,
        collapsedIconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
        collapsedTextColor: colors.onSurface,
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(color: colors.onSurface),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ColorScheme _scheme(bool isDark) {
    if (!isDark) {
      return const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF1B2B65),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFE4E8F7),
        onPrimaryContainer: Color(0xFF131F4A),
        secondary: Color(0xFF8A6922),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFF5EBD2),
        onSecondaryContainer: Color(0xFF4A3909),
        tertiary: Color(0xFF356253),
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFDDEDE7),
        onTertiaryContainer: Color(0xFF143229),
        error: Color(0xFFB3261E),
        onError: Colors.white,
        errorContainer: Color(0xFFF9DEDC),
        onErrorContainer: Color(0xFF410E0B),
        surface: Color(0xFFFFFFFF),
        onSurface: AppColors.lightInk,
        onSurfaceVariant: AppColors.lightMuted,
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFFAFBFE),
        surfaceContainer: Color(0xFFF3F5FA),
        surfaceContainerHigh: Color(0xFFEDF0F6),
        surfaceContainerHighest: Color(0xFFE6EAF3),
        outline: Color(0xFF8B93A6),
        outlineVariant: AppColors.lightOutline,
        shadow: Color(0xFF0B1220),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFF1B2437),
        onInverseSurface: Color(0xFFF1F4FB),
        inversePrimary: Color(0xFFB8C5FF),
      );
    }
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFB9C6FF),
      onPrimary: Color(0xFF0B1743),
      primaryContainer: Color(0xFF1D2C5E),
      onPrimaryContainer: Color(0xFFDCE3FF),
      secondary: Color(0xFFE3C57F),
      onSecondary: Color(0xFF3A2C07),
      secondaryContainer: Color(0xFF3A3018),
      onSecondaryContainer: Color(0xFFF4DFAC),
      tertiary: Color(0xFFA6D1BF),
      onTertiary: Color(0xFF0D3227),
      tertiaryContainer: Color(0xFF234A3E),
      onTertiaryContainer: Color(0xFFD5EFE4),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkInk,
      onSurfaceVariant: AppColors.darkMuted,
      surfaceContainerLowest: AppColors.darkBackground,
      surfaceContainerLow: AppColors.darkSurface,
      surfaceContainer: Color(0xFF141B2D),
      surfaceContainerHigh: Color(0xFF1A2237),
      surfaceContainerHighest: Color(0xFF212B44),
      outline: Color(0xFF556181),
      outlineVariant: AppColors.darkOutline,
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE9EDF8),
      onInverseSurface: Color(0xFF10182B),
      inversePrimary: Color(0xFF1B2B65),
    );
  }

  static TextTheme _textTheme(ColorScheme colors) {
    final base = ThemeData(brightness: colors.brightness).textTheme;
    final themed = base.apply(
      fontFamily: 'Manrope',
      bodyColor: colors.onSurface,
      displayColor: colors.onSurface,
    );
    return themed.copyWith(
      displayLarge: themed.displayLarge?.copyWith(
        fontSize: 54,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.6,
        height: 1.05,
      ),
      displayMedium: themed.displayMedium?.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        height: 1.08,
      ),
      displaySmall: themed.displaySmall?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.12,
      ),
      headlineLarge: themed.headlineLarge?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        height: 1.15,
      ),
      headlineMedium: themed.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.18,
      ),
      headlineSmall: themed.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        height: 1.22,
      ),
      titleLarge: themed.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
        height: 1.3,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.05,
        height: 1.35,
      ),
      titleSmall: themed.titleSmall?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      bodyLarge: themed.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
      bodyMedium: themed.bodyMedium?.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
      bodySmall: themed.bodySmall?.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      labelLarge: themed.labelLarge?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        height: 1.25,
      ),
      labelMedium: themed.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        height: 1.25,
      ),
      labelSmall: themed.labelSmall?.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        height: 1.3,
      ),
    );
  }
}

/// Reusable decorative surfaces used across the app.
abstract final class AppDecor {
  static LinearGradient heroGradient(BuildContext context) {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1B2A5E), Color(0xFF22377C), Color(0xFF16224C)],
      stops: [0, .55, 1],
    );
  }

  static LinearGradient goldGradient(BuildContext context) {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD9B966), Color(0xFFBE963C)],
    );
  }

  static List<BoxShadow> softShadow(BuildContext context) {
    final dark = AppTheme.isDark(context);
    return [
      BoxShadow(
        color: (dark ? Colors.black : AppColors.navy).withValues(
          alpha: dark ? .28 : .07,
        ),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static BoxDecoration cardSurface(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      border: Border.all(color: colors.outlineVariant),
    );
  }
}
