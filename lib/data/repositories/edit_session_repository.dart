import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/edit_session.dart';

// ─────────────────────────────────────────────────────────
//  EditSessionRepository
//  이미지별 편집 세션을 SharedPreferences에 저장합니다.
//  키: 'edit_session.${base64url(imageUri)}'
// ─────────────────────────────────────────────────────────

class EditSessionRepository {
  static String _key(String imageUri) =>
      'edit_session.${base64Url.encode(utf8.encode(imageUri))}';

  /// 저장된 세션 로드. 없으면 빈 세션 반환.
  Future<EditSession> load(String imageUri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(imageUri));
      if (raw == null) return EditSession.forImage(imageUri);
      return EditSession.fromJsonString(raw);
    } catch (_) {
      // 역직렬화 실패 시 깨끗한 세션으로 폴백
      return EditSession.forImage(imageUri);
    }
  }

  /// 세션 저장. 빈 세션이면 삭제.
  Future<void> save(EditSession session) async {
    final prefs = await SharedPreferences.getInstance();
    if (session.ops.isEmpty) {
      await prefs.remove(_key(session.imageUri));
      return;
    }
    await prefs.setString(_key(session.imageUri), session.toJsonString());
  }

  /// 특정 이미지의 세션 삭제.
  Future<void> delete(String imageUri) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(imageUri));
  }

  /// 모든 편집 세션 삭제 (캐시 초기화용).
  Future<void> deleteAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys()
        .where((k) => k.startsWith('edit_session.'))
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
