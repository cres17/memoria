import 'package:flutter/material.dart';

/// Evergreen Heritage palette.
///
/// The legacy ocean/cloud token names are preserved so the existing screens can
/// adopt the new example UI direction without a broad rename pass.
abstract class AppColors {
  static const Color oceanAbyss = Color(0xFF032111);
  static const Color oceanDeep = Color(0xFFFAF9F7);
  static const Color oceanMid = Color(0xFFFFFFFF);
  static const Color oceanNavy = Color(0xFFE3E2E0);
  static const Color oceanBlue = Color(0xFFD8E6DA);
  static const Color oceanTeal = Color(0xFF203D2B);
  static const Color oceanSky = Color(0xFFADCFB6);
  static const Color oceanFoam = Color(0xFF092717);
  static const Color oceanMist = Color(0xFF556158);

  static const Color cloudWhite = Color(0xFFFFFFFF);
  static const Color cloudPure = Color(0xFFFAF9F7);
  static const Color cloudSilk = Color(0xFFF4F4F1);
  static const Color cloudVeil = Color(0xFFEEEEEB);
  static const Color cloudMist = Color(0xFFC2C8C1);
  static const Color cloudShadow = Color(0xFF727972);

  static const Color accentPrimary = Color(0xFF092717);
  static const Color accentSecondary = Color(0xFF203D2B);
  static const Color accentGlow = Color(0xFFC9EBD2);
  static const Color accentSuccess = Color(0xFF476551);
  static const Color accentWarning = Color(0xFFF5A623);
  static const Color accentError = Color(0xFFBA1A1A);

  static const Color textPrimary = Color(0xFF1A1C1B);
  static const Color textSecondary = Color(0xFF424843);
  static const Color textTertiary = Color(0xFF727972);
  static const Color textOnDark = Color(0xFF1A1C1B);
  static const Color textOnDarkSub = Color(0xFF424843);
  static const Color textOnDarkTert = Color(0xFF727972);

  static const LinearGradient oceanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cloudPure, cloudVeil],
  );

  static const LinearGradient depthGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cloudPure, cloudSilk],
  );

  static const LinearGradient foamGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [oceanFoam, oceanTeal],
  );

  static const LinearGradient cloudGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cloudPure, cloudSilk],
  );

  static const Color overlay20 = Color(0x33032111);
  static const Color overlay40 = Color(0x66032111);
  static const Color overlayLight = Color(0x1AFFFFFF);
}
