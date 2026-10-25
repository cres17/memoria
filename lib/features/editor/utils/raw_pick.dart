import 'package:flutter/material.dart';
import 'package:memoria/core/remote_config/remote_config.dart';
import 'package:memoria/engine/raw_import.dart';

/// 고른 사진이 RAW면 편집 가능한 JPEG로 바꿔 경로를 돌려준다.
/// RAW가 아니면 경로를 그대로 돌려주고, 열 수 없으면 안내 후 null을 돌려준다.
Future<String?> resolvePickedPhotoPath(
  BuildContext context,
  String path,
) async {
  if (!RawImport.isRawPath(path)) return path;
  final messenger = ScaffoldMessenger.of(context);
  if (RemoteConfigService.instance.current.rawDisabled) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('RAW 열기를 일시적으로 사용할 수 없어요. JPEG/HEIC 사진을 선택해 주세요.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return null;
  }
  try {
    final result = await RawImport.prepare(path);
    if (result.isPreviewOnly) {
      final size = result.width != null && result.height != null
          ? ' (${result.width}×${result.height})'
          : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text('이 기기에서는 RAW를 현상할 수 없어 파일 안의 미리보기 이미지$size로 열었어요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return result.path;
  } on RawImportException catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(error.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return null;
  }
}
