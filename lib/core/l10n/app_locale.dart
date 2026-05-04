import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLocaleKey = 'app_locale';

/// Global locale notifier — listen in MemoriaApp to rebuild on change.
final localeNotifier = ValueNotifier<Locale>(const Locale('ko'));

Future<void> loadSavedLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(_kLocaleKey) ?? 'ko';
  localeNotifier.value = Locale(code);
}

Future<void> setLocale(String languageCode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLocaleKey, languageCode);
  localeNotifier.value = Locale(languageCode);
}
