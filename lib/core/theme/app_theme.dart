import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get dark => _buildDark();
  static ThemeData get light => _buildLight();

  static ThemeData _buildDark() {
    const base = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.oceanFoam,
      onPrimary: AppColors.oceanAbyss,
      secondary: AppColors.oceanMist,
      onSecondary: AppColors.oceanAbyss,
      surface: AppColors.oceanMid,
      onSurface: AppColors.textOnDark,
      error: AppColors.accentError,
      onError: AppColors.cloudWhite,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.oceanDeep,
      fontFamily: 'NotoSerif',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: IconThemeData(color: AppColors.textOnDark),
        titleTextStyle: TextStyle(
          fontFamily: 'Domine',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textOnDark,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.oceanMid,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.oceanMid,
        selectedItemColor: AppColors.oceanFoam,
        unselectedItemColor: AppColors.textOnDarkTert,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.oceanMid,
        indicatorColor: AppColors.oceanTeal.withOpacity(0.3),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.oceanFoam);
          }
          return const IconThemeData(color: AppColors.textOnDarkTert);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: 'NotoSerif',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.oceanFoam,
            );
          }
          return const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppColors.textOnDarkTert,
          );
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.oceanFoam,
        inactiveTrackColor: AppColors.oceanNavy,
        thumbColor: AppColors.cloudWhite,
        overlayColor: AppColors.oceanFoam.withOpacity(0.2),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.oceanNavy,
        thickness: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.oceanMid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentPrimary,
          foregroundColor: AppColors.cloudWhite,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.oceanFoam,
          side: const BorderSide(color: AppColors.oceanNavy),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.oceanFoam,
          textStyle: const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.oceanNavy,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(
          color: AppColors.textOnDarkTert,
          fontFamily: 'NotoSerif',
          fontSize: 15,
        ),
      ),
    );
  }

  static ThemeData _buildLight() {
    const base = ColorScheme.light(
      brightness: Brightness.light,
      primary: AppColors.oceanFoam,
      onPrimary: AppColors.cloudWhite,
      secondary: AppColors.oceanMist,
      onSecondary: AppColors.cloudWhite,
      surface: AppColors.cloudWhite,
      onSurface: AppColors.textPrimary,
      error: AppColors.accentError,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.cloudPure,
      fontFamily: 'NotoSerif',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cloudPure,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: AppColors.cloudMist,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          fontFamily: 'Domine',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.oceanFoam,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cloudWhite,
        elevation: 0,
        shadowColor: AppColors.cloudMist,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.oceanFoam,
        inactiveTrackColor: AppColors.oceanNavy,
        thumbColor: AppColors.cloudWhite,
        overlayColor: AppColors.oceanFoam.withOpacity(0.12),
        trackHeight: 12,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentPrimary,
          foregroundColor: AppColors.cloudWhite,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(
            fontFamily: 'NotoSerif',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cloudWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cloudMist),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cloudMist),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.oceanFoam, width: 1.2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.oceanFoam,
        ),
      ),
    );
  }
}
