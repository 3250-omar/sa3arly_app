import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  const AppTheme._();

  static const Color primaryColor = Color(0xFF0F4C5C);
  static const Color primaryLight = Color(0xFF1B6B80);
  static const Color accentColor = Color(0xFFE36414);
  static const Color surfaceBg = Color(0xFFF5F7F9);
  static const Color cardBorder = Color(0xFFE2E8F0);

  // Confidence semantic colors
  static const Color highConfidenceColor = Color(0xFF15803D);
  static const Color highConfidenceBg = Color(0xFFDCFCE7);
  static const Color mediumConfidenceColor = Color(0xFFB45309);
  static const Color mediumConfidenceBg = Color(0xFFFEF3C7);
  static const Color lowConfidenceColor = Color(0xFFB91C1C);
  static const Color lowConfidenceBg = Color(0xFFFEE2E2);

  static ThemeData lightTheme({bool enableRemoteFonts = true}) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: accentColor,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: surfaceBg,
    );

    final baseText = baseTheme.textTheme;
    final textTheme = enableRemoteFonts
        ? baseText.copyWith(
            displayLarge: GoogleFonts.cairo(textStyle: baseText.displayLarge),
            displayMedium: GoogleFonts.cairo(textStyle: baseText.displayMedium),
            displaySmall: GoogleFonts.cairo(textStyle: baseText.displaySmall),
            headlineLarge: GoogleFonts.cairo(textStyle: baseText.headlineLarge),
            headlineMedium:
                GoogleFonts.cairo(textStyle: baseText.headlineMedium),
            headlineSmall: GoogleFonts.cairo(textStyle: baseText.headlineSmall),
            titleLarge: GoogleFonts.cairo(textStyle: baseText.titleLarge),
            titleMedium: GoogleFonts.cairo(textStyle: baseText.titleMedium),
            titleSmall: GoogleFonts.cairo(textStyle: baseText.titleSmall),
            bodyLarge: GoogleFonts.cairo(textStyle: baseText.bodyLarge),
            bodyMedium: GoogleFonts.cairo(textStyle: baseText.bodyMedium),
            bodySmall: GoogleFonts.cairo(textStyle: baseText.bodySmall),
            labelLarge: GoogleFonts.cairo(textStyle: baseText.labelLarge),
            labelMedium: GoogleFonts.cairo(textStyle: baseText.labelMedium),
            labelSmall: GoogleFonts.cairo(textStyle: baseText.labelSmall),
          )
        : baseText;

    return baseTheme.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 19,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: primaryColor.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? primaryColor : Colors.grey.shade700,
          );
        }),
      ),
    );
  }
}
