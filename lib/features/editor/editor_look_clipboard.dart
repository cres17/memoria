import 'package:memoria/domain/models/editor_look.dart';

/// 앱이 켜져 있는 동안 편집 화면과 일괄 적용 화면이 함께 쓰는 보정 복사본.
class EditorLookClipboard {
  EditorLookClipboard._();

  static EditorLook? value;
}
