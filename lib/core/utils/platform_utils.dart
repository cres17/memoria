import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Platform-aware icon helpers
IconData backIcon() =>
    Platform.isIOS ? Icons.arrow_back_ios_new_rounded : Icons.arrow_back_rounded;

IconData shareIcon() =>
    Platform.isIOS ? Icons.ios_share_rounded : Icons.share_rounded;

/// Platform-aware scroll physics
ScrollPhysics platformScrollPhysics() =>
    Platform.isIOS
        ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
        : const ClampingScrollPhysics();

/// Haptic feedback with Android graceful fallback
Future<void> hapticLight() async {
  try { await HapticFeedback.selectionClick(); } catch (_) {}
}

Future<void> hapticMedium() async {
  try { await HapticFeedback.mediumImpact(); } catch (_) {}
}

Future<void> hapticHeavy() async {
  try { await HapticFeedback.heavyImpact(); } catch (_) {}
}

/// Status bar brightness helper — call inside initState or didChangeDependencies
void setStatusBarForDark() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
}

void setStatusBarForLight() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
}

/// Safe bottom padding accounting for gesture nav bar
double safeBottom(BuildContext context) =>
    MediaQuery.of(context).padding.bottom;
