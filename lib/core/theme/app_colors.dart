import 'package:flutter/material.dart';

/// Cloud Dancer × Deep Ocean palette
/// Cloud Dancer: soft white/sky tones (surface, background)
/// Deep Ocean: dark navy/teal depths (primary, accents)
abstract class AppColors {
  // ── Deep Ocean depths ──────────────────────────────────────────
  static const Color oceanAbyss   = Color(0xFF080F1C); // darkest
  static const Color oceanDeep    = Color(0xFF0D1F35); // main dark bg
  static const Color oceanMid     = Color(0xFF142B49); // card dark
  static const Color oceanNavy    = Color(0xFF1A3A5C); // elevated dark
  static const Color oceanBlue    = Color(0xFF1E5082); // ocean blue
  static const Color oceanTeal    = Color(0xFF1B6CA8); // mid teal
  static const Color oceanSky     = Color(0xFF2E87C8); // sky blue
  static const Color oceanFoam    = Color(0xFF4B9CD3); // foam accent
  static const Color oceanMist    = Color(0xFF7BB8E0); // light mist

  // ── Cloud Dancer lights ────────────────────────────────────────
  static const Color cloudWhite   = Color(0xFFFFFFFF);
  static const Color cloudPure    = Color(0xFFF8FBFF); // near white
  static const Color cloudSilk    = Color(0xFFF0F5FC); // background
  static const Color cloudVeil    = Color(0xFFE4EDF8); // surface
  static const Color cloudMist    = Color(0xFFD0DCF0); // divider light
  static const Color cloudShadow  = Color(0xFFB8CCE8); // light border

  // ── Accent / Interactive ───────────────────────────────────────
  static const Color accentPrimary  = Color(0xFF2E87C8); // main CTA
  static const Color accentSecondary= Color(0xFF4B9CD3); // secondary
  static const Color accentGlow     = Color(0xFF89C4E1); // glow/highlight
  static const Color accentSuccess  = Color(0xFF3ABBA0); // success teal
  static const Color accentWarning  = Color(0xFFF5A623); // warning
  static const Color accentError    = Color(0xFFE8526A); // error

  // ── Text ───────────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFF0D1F35); // on light
  static const Color textSecondary  = Color(0xFF4A6480); // secondary on light
  static const Color textTertiary   = Color(0xFF8CA7C0); // tertiary on light
  static const Color textOnDark     = Color(0xFFF0F5FC); // on dark
  static const Color textOnDarkSub  = Color(0xFFADC6DE); // secondary on dark
  static const Color textOnDarkTert = Color(0xFF6A93B5); // tertiary on dark

  // ── Gradients ─────────────────────────────────────────────────
  static const LinearGradient oceanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [oceanDeep, oceanBlue],
  );

  static const LinearGradient depthGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [oceanAbyss, oceanMid],
  );

  static const LinearGradient foamGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [oceanFoam, oceanSky],
  );

  static const LinearGradient cloudGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cloudPure, cloudSilk],
  );

  // ── Overlays ───────────────────────────────────────────────────
  static const Color overlay20  = Color(0x330D1F35);
  static const Color overlay40  = Color(0x660D1F35);
  static const Color overlayLight = Color(0x1AFFFFFF);
}
