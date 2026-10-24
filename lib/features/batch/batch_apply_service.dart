import 'dart:typed_data';

import 'package:memoria/core/error/error_handler.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/editor_look.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/engine/lut_engine.dart';
import 'package:memoria/features/editor/editor_edit_state.dart';
import 'package:memoria/features/editor/editor_export_service.dart';
import 'package:memoria/features/editor/editor_media_export_coordinator.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';

enum BatchItemStatus { pending, running, done, failed, cancelled }

class BatchItemResult {
  final String path;
  final BatchItemStatus status;
  final String? message;

  const BatchItemResult(this.path, this.status, [this.message]);
}

/// 같은 보정 룩을 여러 장에 적용해 순서대로 내보낸다.
///
/// 인물 보정은 사진마다 사람 영역을 새로 찾아야 해서 일괄 적용에서는 제외한다.
/// (잘못된 영역에 적용되는 것보다 적용하지 않는 쪽을 택했다.)
class BatchApplyService {
  final EditorMediaExportCoordinator Function() _newCoordinator;
  final Future<Uint8List?> Function(String? lutPath) _loadLut;
  bool _cancelled = false;
  EditorMediaExportCoordinator? _active;

  BatchApplyService({
    EditorMediaExportCoordinator Function()? coordinatorFactory,
    Future<Uint8List?> Function(String? lutPath)? loadLut,
  })  : _newCoordinator = coordinatorFactory ?? EditorMediaExportCoordinator.new,
        _loadLut = loadLut ?? loadLutBytes;

  /// 일괄 적용 대상에서 사진마다 달라지는 값을 뺀 룩.
  static EditorLook withoutPortrait(EditorLook look) => EditorLook(
        params: look.params,
        presetId: look.presetId,
        intensity: look.intensity,
        artisticEffect: look.artisticEffect,
        effectStrength: look.effectStrength,
        grainVariant: look.grainVariant,
        portrait: PortraitParams.zero,
      );

  static EditorRenderRecipe buildRecipe(
    EditorLook look,
    FilterPreset? preset,
    Uint8List? lutBytes,
  ) {
    final state = EditorEditState()
      ..applyLook(withoutPortrait(look), resolvedPreset: preset);
    return state
        .toSnapshot(localSubTabName: 'tiltShift')
        .toRenderRecipe(lutBytes: lutBytes, cropAspectRatio: null);
  }

  Future<void> cancel() async {
    _cancelled = true;
    await _active?.cancel();
  }

  Future<List<BatchItemResult>> run({
    required List<String> paths,
    required EditorLook look,
    required FilterPreset? preset,
    required void Function(int index, BatchItemResult result) onItem,
    void Function(int index, double progress)? onProgress,
  }) async {
    _cancelled = false;
    final lut = preset == null ? null : await _loadLut(preset.lutPath);
    final recipe = buildRecipe(look, preset, lut);
    final results = <BatchItemResult>[];

    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      if (_cancelled) {
        final cancelled = BatchItemResult(path, BatchItemStatus.cancelled);
        results.add(cancelled);
        onItem(i, cancelled);
        continue;
      }
      onItem(i, BatchItemResult(path, BatchItemStatus.running));
      final coordinator = _newCoordinator();
      _active = coordinator;
      BatchItemResult result;
      try {
        final exported = await coordinator.export(
          share: false,
          onProgress: (value) => onProgress?.call(i, value),
          buildRequest: (attempt) async => EditorExportRequest(
            imagePath: path,
            outputPath: attempt.outputPath,
            format: attempt.renderFormat,
            quality: attempt.quality,
            maxDimension: attempt.maxDimension,
            recipe: recipe,
          ),
        );
        result = exported.cancelled
            ? BatchItemResult(path, BatchItemStatus.cancelled)
            : BatchItemResult(path, BatchItemStatus.done);
      } catch (error, stackTrace) {
        ErrorLogger.log(
          'Batch apply failed for one photo',
          error.runtimeType,
          stackTrace,
        );
        result = BatchItemResult(path, BatchItemStatus.failed, '$error');
      } finally {
        _active = null;
      }
      results.add(result);
      onItem(i, result);
    }
    return results;
  }
}
