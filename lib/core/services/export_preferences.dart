import 'package:shared_preferences/shared_preferences.dart';

enum ExportFormat { jpeg, png, webp, tiff }

extension ExportFormatContract on ExportFormat {
  String get storageKey => name;

  String get extension => switch (this) {
        ExportFormat.jpeg => 'jpg',
        ExportFormat.png => 'png',
        ExportFormat.webp => 'webp',
        ExportFormat.tiff => 'tif',
      };

  String get mimeType => switch (this) {
        ExportFormat.jpeg => 'image/jpeg',
        ExportFormat.png => 'image/png',
        ExportFormat.webp => 'image/webp',
        ExportFormat.tiff => 'image/tiff',
      };

  bool get hasAdjustableQuality =>
      this == ExportFormat.jpeg || this == ExportFormat.webp;

  static ExportFormat parse(String? raw, {required bool allowWebp}) {
    final parsed = ExportFormat.values.firstWhere(
      (value) => value.storageKey == raw,
      orElse: () => ExportFormat.jpeg,
    );
    return parsed == ExportFormat.webp && !allowWebp
        ? ExportFormat.jpeg
        : parsed;
  }
}

class ExportSettings {
  final ExportFormat format;
  final int quality;

  const ExportSettings({
    this.format = ExportFormat.jpeg,
    this.quality = 95,
  });

  ExportSettings normalized({required bool allowWebp}) => ExportSettings(
        format: format == ExportFormat.webp && !allowWebp
            ? ExportFormat.jpeg
            : format,
        quality: quality.clamp(70, 100),
      );
}

class ExportPreferences {
  static const _formatKey = 'settings_export_format';
  static const _qualityKey = 'settings_export_quality';

  static Future<ExportSettings> load({required bool allowWebp}) async {
    final prefs = await SharedPreferences.getInstance();
    return ExportSettings(
      format: ExportFormatContract.parse(
        prefs.getString(_formatKey),
        allowWebp: allowWebp,
      ),
      quality: prefs.getInt(_qualityKey) ?? 95,
    ).normalized(allowWebp: allowWebp);
  }

  static Future<void> saveFormat(ExportFormat format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_formatKey, format.storageKey);
  }

  static Future<void> saveQuality(int quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_qualityKey, quality.clamp(70, 100));
  }
}
