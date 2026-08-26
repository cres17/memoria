import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small persistence boundary for an editor draft.
///
/// It owns the storage key and compatibility checks, while `EditorPage` owns
/// the mapping between its UI state and the JSON payload. This keeps image-path
/// keyed persistence out of the screen lifecycle and makes corrupt drafts a
/// typed, recoverable condition.
class EditorDraftStore {
  final Future<SharedPreferences> Function() _preferences;

  EditorDraftStore({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  Future<void> save({
    required String imagePath,
    required Map<String, dynamic> draft,
  }) async {
    try {
      final prefs = await _preferences();
      await prefs.setString(_keyFor(imagePath), jsonEncode(draft));
    } catch (error) {
      // Storage details may include the source path. Translate to a stable,
      // privacy-safe boundary error and let EditorPage record the operation.
      throw const EditorDraftStorageException('save');
    }
  }

  Future<Map<String, dynamic>?> read({
    required String imagePath,
    required String? initialPresetId,
  }) async {
    try {
      final prefs = await _preferences();
      final raw = prefs.getString(_keyFor(imagePath));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Draft root is not a JSON object');
      }
      if (decoded['imagePath'] != imagePath ||
          decoded['initialPresetId'] != initialPresetId) {
        return null;
      }
      return decoded;
    } on EditorDraftStorageException {
      rethrow;
    } catch (error) {
      // JSON/storage failures are intentionally normalized at this boundary.
      throw const EditorDraftStorageException('read');
    }
  }

  static String _keyFor(String imagePath) =>
      'editor.draft.${base64Url.encode(utf8.encode(imagePath))}';
}

class EditorDraftStorageException implements Exception {
  final String operation;

  const EditorDraftStorageException(this.operation);

  @override
  String toString() => 'EditorDraftStorageException($operation)';
}
