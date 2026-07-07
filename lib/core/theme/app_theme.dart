import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_constants.dart';
import 'sagana_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        colorScheme: _lightColorScheme,
        saganaColors: SaganaColors.light,
        overlayStyle: SystemUiOverlayStyle.dark,
      );

  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        colorScheme: _darkColorScheme,
        saganaColors: SaganaColors.dark,
        overlayStyle: SystemUiOverlayStyle.light,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required SaganaColors saganaColors,
    required SystemUiOverlayStyle overlayStyle,
  }) {
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: saganaColors.scaffoldBackground,
      extensions: [saganaColors],
      textTheme: _textTheme(onSurface, onSurfaceVariant),
      appBarTheme: _appBarTheme(colorScheme, overlayStyle, onSurface),
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      inputDecorationTheme: _inputDecorationTheme(colorScheme, saganaColors),
      cardTheme: _cardTheme(saganaColors, colorScheme),
      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withValues(alpha: 0.15),
        thickness: 1,
      ),
      snackBarTheme: _snackBarTheme,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppConstants.white;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppConstants.primaryGreen;
          }
          return colorScheme.outline.withValues(alpha: 0.3);
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: saganaColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static const ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppConstants.primaryGreen,
    onPrimary: AppConstants.white,
    primaryContainer: AppConstants.primaryContainer,
    onPrimaryContainer: AppConstants.onPrimaryContainer,
    secondary: AppConstants.secondaryContainer,
    onSecondary: AppConstants.white,
    secondaryContainer: AppConstants.secondaryContainer,
    onSecondaryContainer: Color(0xFF694300),
    tertiary: AppConstants.lightGreen,
    onTertiary: AppConstants.white,
    tertiaryContainer: AppConstants.tertiaryContainer,
    onTertiaryContainer: AppConstants.onTertiaryContainer,
    error: AppConstants.errorRed,
    onError: AppConstants.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    surface: AppConstants.surface,
    onSurface: AppConstants.onSurface,
    surfaceContainerHighest: Color(0xFFCFE6F2),
    onSurfaceVariant: AppConstants.onSurfaceVariant,
    outline: AppConstants.outline,
    outlineVariant: Color(0xFFC0C9BB),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFF1E333C),
    onInverseSurface: Color(0xFFDFF4FF),
    inversePrimary: Color(0xFF91D78A),
  );

  static const ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppConstants.lightGreen,
    onPrimary: AppConstants.primaryGreen,
    primaryContainer: Color(0xFF1B5E20),
    onPrimaryContainer: AppConstants.onPrimaryContainer,
    secondary: AppConstants.amber,
    onSecondary: Color(0xFF3E2E00),
    secondaryContainer: Color(0xFF5D4200),
    onSecondaryContainer: Color(0xFFFFE082),
    tertiary: AppConstants.lightGreen,
    onTertiary: Color(0xFF003910),
    tertiaryContainer: AppConstants.tertiaryContainer,
    onTertiaryContainer: AppConstants.onTertiaryContainer,
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF121F16),
    onSurface: Color(0xFFE8F0EA),
    surfaceContainerHighest: Color(0xFF2A3D30),
    onSurfaceVariant: Color(0xFFB8C4BA),
    outline: Color(0xFF889688),
    outlineVariant: Color(0xFF3D4F42),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFE8F0EA),
    onInverseSurface: Color(0xFF1A281E),
    inversePrimary: AppConstants.primaryGreen,
  );

  static TextTheme _textTheme(Color onSurface, Color onSurfaceVariant) {
    return TextTheme(
      displayLarge: GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.25,
        color: onSurface,
      ),
      displayMedium: GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      displaySmall: GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.01,
        color: onSurface,
      ),
      headlineLarge: GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      headlineMedium: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      headlineSmall: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleLarge: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      titleMedium: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      titleSmall: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      labelMedium: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.15,
        color: onSurfaceVariant,
      ),
    );
  }

  static AppBarTheme _appBarTheme(
    ColorScheme scheme,
    SystemUiOverlayStyle overlayStyle,
    Color onSurface,
  ) =>
      AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        systemOverlayStyle: overlayStyle.copyWith(
          statusBarColor: Colors.transparent,
        ),
      );

  static ElevatedButtonThemeData get _elevatedButtonTheme =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryGreen,
          foregroundColor: AppConstants.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          elevation: 0,
        ),
      );

  static OutlinedButtonThemeData get _outlinedButtonTheme =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppConstants.primaryGreen,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: AppConstants.primaryGreen, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  static InputDecorationTheme _inputDecorationTheme(
    ColorScheme scheme,
    SaganaColors sagana,
  ) =>
      InputDecorationTheme(
        filled: true,
        fillColor: sagana.cardBackground,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide(color: scheme.outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide:
              BorderSide(color: scheme.outline.withValues(alpha: 0.5), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide:
              const BorderSide(color: AppConstants.primaryGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide:
              const BorderSide(color: AppConstants.errorRed, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide:
              const BorderSide(color: AppConstants.errorRed, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: scheme.onSurfaceVariant,
        ),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: scheme.outline),
        errorStyle:
            GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed),
      );

  static CardThemeData _cardTheme(SaganaColors sagana, ColorScheme scheme) =>
      CardThemeData(
        color: sagana.cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          side: BorderSide(
            color: scheme.outline.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      );

  static SnackBarThemeData get _snackBarTheme => SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        contentTextStyle: GoogleFonts.inter(fontSize: 14),
      );

  /// Applies status bar style based on current theme brightness.
  static void applySystemOverlay(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      final brightness = Theme.of(context).brightness;
      SystemChrome.setSystemUIOverlayStyle(
        (brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent),
      );
    });
  }
}
