import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'ai/ai_manager.dart';
import 'core/l10n/app_locale.dart';
import 'core/error/crash_reporter.dart';
import 'core/error/error_handler.dart';
import 'core/remote_config/remote_config.dart';
import 'engine/gpu_image_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final defaultFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    ErrorLogger.log(
      'Unhandled Flutter framework error',
      details.exception,
      details.stack,
    );
    // 사용자가 동의한 경우에만 전송된다(CrashReporter가 꺼짐 상태면 아무 일도 하지 않는다).
    unawaited(CrashReporter.instance
        .report(details.exception, details.stack, source: 'flutter'));
    if (defaultFlutterErrorHandler != null) {
      defaultFlutterErrorHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    ErrorLogger.log('Unhandled platform error', error, stackTrace);
    unawaited(CrashReporter.instance.report(error, stackTrace, source: 'platform'));
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
                  CrashReporter.instance.enabled
                      ? '앱을 다시 열어 주세요. 설정에 따라 오류 정보가 개인정보를 제외하고 전송됩니다.'
                      : '앱을 다시 열어 주세요. 진단 기록은 기기에만 저장됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.58)),
                ),
              ],
            ),
          ),
        ),
      );

  // Do not hold the native launch screen while creating renderer textures or
  // opening application storage. On iOS the engine cannot reliably produce
  // its first Flutter frame until the app is running; awaiting that work here
  // can leave the app on the native splash indefinitely.
  runApp(const MemoriaApp());
  unawaited(_initializeAfterFirstFrame());
}

Future<void> _initializeAfterFirstFrame() async {
  await WidgetsBinding.instance.endOfFrame;
  try {
    await ErrorLogger.initialize();
    await CrashReporter.instance.initialize();
    // 마지막으로 검증된 원격 설정을 먼저 적용하고, 갱신은 백그라운드로 한다.
    await RemoteConfigService.instance.loadCached();
    unawaited(RemoteConfigService.instance.refresh());
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

    // The color-transfer model ships with the app. Install and verify that
    // bundled asset after first paint so filter creation never asks users to
    // manage a model download from Settings.
    unawaited(AiManager.instance.preload(kModelColorTransfer));

    // Portrait tools are segmentation-aware. Prepare the small on-device model
    // automatically so skin smoothing never falls back to a whole-image effect.
    unawaited(AiManager.instance.preload(kModelSelfie));

    // 광고 SDK는 동의 확인(UMP/ATT)을 마친 뒤 광고가 처음 필요할 때 초기화한다
    // (AdConsentService). 광고 기능이 꺼져 있으면 SDK를 아예 시작하지 않는다.
  } catch (error, stackTrace) {
    ErrorLogger.log('Post-frame app initialization failed', error, stackTrace);
  }
}
