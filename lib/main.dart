import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'app.dart';
import 'ai/ai_manager.dart';
import 'core/l10n/app_locale.dart';
import 'core/error/error_handler.dart';
import 'engine/gpu_image_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ErrorLogger.initialize();
  final defaultFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    ErrorLogger.log(
      'Unhandled Flutter framework error',
      details.exception,
      details.stack,
    );
    if (defaultFlutterErrorHandler != null) {
      defaultFlutterErrorHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    ErrorLogger.log('Unhandled platform error', error, stackTrace);
    return true;
  };
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFFF4FAF5),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 36),
                const SizedBox(height: 12),
                const Text(
                  '화면을 표시하지 못했습니다.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '앱을 다시 열어 주세요. 진단 기록은 기기에만 저장됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.58)),
                ),
              ],
            ),
          ),
        ),
      );
  await initGpuFallbacks();
  await loadSavedLocale();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status/nav bar (immersive)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const ProviderScope(child: MemoriaApp()));

  // The color-transfer model ships with the app. Install and verify that
  // bundled asset after first paint so filter creation never asks users to
  // manage a model download from Settings.
  unawaited(AiManager.instance.preload(kModelColorTransfer));

  // Portrait tools are segmentation-aware. Prepare the small on-device model
  // automatically so skin smoothing never falls back to a whole-image effect.
  unawaited(AiManager.instance.preload(kModelSelfie));

  // AdMob initialization can be slow on device; do it after the first frame.
  unawaited(MobileAds.instance.initialize());
}
