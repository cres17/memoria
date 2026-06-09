import 'dart:convert';
import 'edit_operation.dart';
import 'adjust_params.dart';
import 'curve_data.dart';

// ─────────────────────────────────────────────────────────
//  EditSession — 이미지 한 장에 대한 전체 편집 세션
//  ops는 append-only 로그이며 undoCursor가 현재 활성 위치를 가리킵니다.
//  undo는 undoCursor를 감소시키고, redo는 증가시킵니다.
//  undoCursor 이후의 ops는 논리적으로 삭제된 상태입니다.
// ─────────────────────────────────────────────────────────

class EditSession {
  final String imageUri; // 절대 파일 경로
  final List<EditOperation> ops; // append-only 로그 (최대 100개)
  final int undoCursor; // ops[0..undoCursor-1]이 활성 상태

  static const _kMaxOps = 100;

  const EditSession({
    required this.imageUri,
    this.ops = const [],
    this.undoCursor = 0,
  });

  // ── 쿼리 헬퍼 ───────────────────────────────────────────

  /// 현재 활성 작업 목록 (undo된 항목 제외)
  List<EditOperation> get activeOps => ops.sublist(0, undoCursor);

  bool get canUndo => undoCursor > 0;
  bool get canRedo => undoCursor < ops.length;

  /// 마지막 활성 op
  EditOperation? get lastOp => undoCursor > 0 ? ops[undoCursor - 1] : null;

  // ── 뮤테이션 (immutable 반환) ────────────────────────────

  /// 새 op 추가. undo 이후 추가하면 미래 ops를 잘라냅니다.
  EditSession pushOp(EditOperation op) {
    // undoCursor 이후 항목 제거 (새 분기 시작)
    final trimmed = ops.sublist(0, undoCursor);
    final newOps = [...trimmed, op];
    // 최대 100개 초과 시 앞에서 제거
    final capped = newOps.length > _kMaxOps
        ? newOps.sublist(newOps.length - _kMaxOps)
        : newOps;
    return EditSession(
      imageUri: imageUri,
      ops: capped,
      undoCursor: capped.length,
    );
  }

  EditSession undo() {
    if (!canUndo) return this;
    return EditSession(
      imageUri: imageUri,
      ops: ops,
      undoCursor: undoCursor - 1,
    );
  }

  EditSession redo() {
    if (!canRedo) return this;
    return EditSession(
      imageUri: imageUri,
      ops: ops,
      undoCursor: undoCursor + 1,
    );
  }

  EditSession resetOps() => EditSession(imageUri: imageUri);

  // ── 현재 상태 집계 ───────────────────────────────────────
  // 활성 ops에서 파생된 "현재 상태"를 계산합니다.
  // EditOperationPlayer가 이를 렌더링에 활용합니다.

  /// 현재 활성 ops의 최종 AdjustParams (globalAdjust 누적)
  AdjustParams get liveParams {
    AdjustParams p = AdjustParams.zero;
    for (final op in activeOps) {
      if (op.params != null &&
          (op.tool == EditToolType.globalAdjust ||
              op.tool == EditToolType.hslAdjust ||
              op.tool == EditToolType.splitTone ||
              op.tool == EditToolType.grainOverlay ||
              op.tool == EditToolType.lightLeak ||
              op.tool == EditToolType.halation)) {
        p = op.params!;
      }
    }
    return p;
  }

  /// 현재 커브 맵 (마지막 curve op 사용)
  Map<CurveChannel, CurveData> get liveCurves {
    for (final op in activeOps.reversed) {
      if (op.tool == EditToolType.curve && op.curves != null) {
        return op.curves!;
      }
    }
    return {};
  }

  /// 현재 필터 (마지막 filter op)
  ({String? presetId, String? lutPath, double intensity}) get liveFilter {
    for (final op in activeOps.reversed) {
      if (op.tool == EditToolType.filter) {
        return (
          presetId: op.presetId,
          lutPath: op.lutPath,
          intensity: op.intensity ?? 1.0,
        );
      }
    }
    return (presetId: null, lutPath: null, intensity: 1.0);
  }

  /// 현재 크롭 상태 (마지막 crop op)
  CropState get liveCropState {
    for (final op in activeOps.reversed) {
      if (op.tool == EditToolType.crop && op.cropState != null) {
        return op.cropState!;
      }
    }
    return CropState.identity;
  }

  /// 현재 인물 파라미터 (마지막 portrait op)
  PortraitParams get livePortrait {
    for (final op in activeOps.reversed) {
      if (op.tool == EditToolType.portrait && op.portrait != null) {
        return op.portrait!;
      }
    }
    return PortraitParams.zero;
  }

  BrushMaskData? get liveBrushMask {
    for (final op in activeOps.reversed) {
      if (op.tool == EditToolType.brush) {
        return op.brushMask;
      }
    }
    return null;
  }

  /// 현재 창의 효과 (마지막 creative op)
  CreativeParams get liveCreative {
    for (final op in activeOps.reversed) {
      if (op.tool == EditToolType.creative && op.creative != null) {
        return op.creative!;
      }
    }
    return CreativeParams.zero;
  }

  /// GPU 경로만으로 렌더링 가능한지 (공간 op 없음)
  bool get isGpuCompatible {
    for (final op in activeOps) {
      switch (op.tool) {
        case EditToolType.brush:
        case EditToolType.selective:
        case EditToolType.heal:
        case EditToolType.portrait:
        case EditToolType.creative:
        case EditToolType.crop:
        case EditToolType.lightLeak:
        case EditToolType.halation:
          return false;
        default:
          break;
      }
    }
    return true;
  }

  // ── 직렬화 ───────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'imageUri': imageUri,
        'ops': ops.map((o) => o.toJson()).toList(),
        'cursor': undoCursor,
      };

  factory EditSession.fromJson(Map<String, dynamic> j) => EditSession(
        imageUri: j['imageUri'] as String,
        ops: (j['ops'] as List<dynamic>? ?? [])
            .map((o) => EditOperation.fromJson(o as Map<String, dynamic>))
            .toList(),
        undoCursor: j['cursor'] as int? ?? 0,
      );

  String toJsonString() => jsonEncode(toJson());

  factory EditSession.fromJsonString(String s) =>
      EditSession.fromJson(jsonDecode(s) as Map<String, dynamic>);

  factory EditSession.forImage(String imageUri) =>
      EditSession(imageUri: imageUri);
}
