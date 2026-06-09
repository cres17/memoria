import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'app.dart';
import 'core/l10n/app_locale.dart';
import 'engine/gpu_image_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  // Initialize AdMob
  await MobileAds.instance.initialize();

  runApp(const ProviderScope(child: MemoriaApp()));
}
