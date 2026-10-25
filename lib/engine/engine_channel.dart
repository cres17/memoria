import 'package:flutter/services.dart';

/// Flutter ↔ Native MethodChannel interface
/// Channel: com.memoria/lut_engine
class EngineChannel {
  static const _channel = MethodChannel('com.memoria/lut_engine');

  /// Generate a 3D LUT from a style image (native implementation).
  /// Falls back to Dart implementation when unavailable.
  static Future<Map<String, dynamic>> generateLut(String styleImagePath) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'generateLut',
        {'styleImagePath': styleImagePath},
      );
      return result ?? {};
    } on MissingPluginException {
      // Native not available — use Dart engine
      return {};
    }
  }

  /// Render a preview (native GPU pipeline).
  static Future<Map<String, dynamic>> renderPreview(
    String imagePath,
    Map<String, dynamic> editOps,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'renderPreview',
        {'imagePath': imagePath, 'editOps': editOps},
      );
      return result ?? {};
    } on MissingPluginException {
      return {};
    }
  }

  /// Export with full resolution.
  static Future<Map<String, dynamic>> export(
    String imagePath,
    Map<String, dynamic> editOps,
    String outPath,
    String format,
    int quality,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'export',
        {
          'imagePath': imagePath,
          'editOps': editOps,
          'outPath': outPath,
          'format': format,
          'quality': quality,
        },
      );
      return result ?? {};
    } on MissingPluginException {
      return {};
    }
  }

  /// Converts a rendered PNG/JPEG into a genuine WebP file on platforms whose
  /// native ImageIO codec advertises WebP support. Returning false means the
  /// caller must not publish a misleading `.webp` file.
  static Future<bool> encodeWebP({
    required String inputPath,
    required String outputPath,
    required int quality,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('encodeWebP', {
            'inputPath': inputPath,
            'outputPath': outputPath,
            'quality': quality,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Develops a camera RAW file into a JPEG (iOS 15+ Core Image).
  /// Returns null when the platform has no native RAW support.
  static Future<Map<String, dynamic>?> decodeRaw({
    required String inputPath,
    required String outputPath,
  }) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('decodeRaw', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> supportsWebPEncoding() async {
    try {
      return await _channel.invokeMethod<bool>('supportsWebPEncoding') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
