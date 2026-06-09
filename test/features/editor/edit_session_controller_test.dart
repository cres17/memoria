import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/edit_session.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/features/editor/edit_session_controller.dart';

void main() {
  group('EditSessionNotifier', () {
    test('pushOp appends after the active cursor and clears redo history', () {
      final notifier = EditSessionNotifier(
        imageUri: 'memory://one',
        initialSession: EditSession.forImage('memory://one')
            .pushOp(_adjust('a', exposure: 0.1))
            .pushOp(_adjust('b', exposure: 0.2))
            .undo(),
      );

      notifier.pushOp(_adjust('c', exposure: 0.3));

      expect(notifier.state.ops.map((op) => op.id), ['a', 'c']);
      expect(notifier.state.undoCursor, 2);
      expect(notifier.canRedo, isFalse);
    });

    test('undo and redo only move the cursor', () {
      final notifier = EditSessionNotifier(
        imageUri: 'memory://two',
        initialSession: EditSession.forImage('memory://two')
            .pushOp(_adjust('a', exposure: 0.1))
            .pushOp(_adjust('b', exposure: 0.2)),
      );

      notifier.undo();
      expect(notifier.state.activeOps.map((op) => op.id), ['a']);
      expect(notifier.canRedo, isTrue);

      notifier.redo();
      expect(notifier.state.activeOps.map((op) => op.id), ['a', 'b']);
      expect(notifier.canRedo, isFalse);
    });

    test('resetOps returns to an empty session for the same image', () {
      final notifier = EditSessionNotifier(
        imageUri: 'memory://three',
        initialSession: EditSession.forImage('memory://three')
            .pushOp(_adjust('a', exposure: 0.1)),
      );

      notifier.resetOps();

      expect(notifier.state.imageUri, 'memory://three');
      expect(notifier.state.ops, isEmpty);
      expect(notifier.state.undoCursor, 0);
    });

    test('keeps at most 100 operations while preserving active cursor', () {
      final notifier = EditSessionNotifier(imageUri: 'memory://cap');

      for (var i = 0; i < 120; i++) {
        notifier.pushOp(_adjust('op-$i', exposure: i / 100));
      }

      expect(notifier.state.ops.length, 100);
      expect(notifier.state.ops.first.id, 'op-20');
      expect(notifier.state.ops.last.id, 'op-119');
      expect(notifier.state.undoCursor, 100);
    });

    test('live state follows undo and redo for editor-owned tool ops', () {
      const brush = BrushMaskData(
        localParams: AdjustParams(exposure: 0.55),
        toolName: 'exposure+',
        strokes: [BrushStroke(x: 0.4, y: 0.5, radius: 0.1)],
      );
      const portrait = PortraitParams(smooth: 20, spotlight: 10);
      final session = EditSession.forImage('memory://live')
          .pushOp(_adjust('a', exposure: 0.1))
          .pushOp(EditOperation(
            id: 'brush',
            tool: EditToolType.brush,
            appliedAt: DateTime(2026, 6, 2),
            brushMask: brush,
          ))
          .pushOp(EditOperation(
            id: 'portrait',
            tool: EditToolType.portrait,
            appliedAt: DateTime(2026, 6, 2),
            portrait: portrait,
          ));
      final notifier = EditSessionNotifier(
        imageUri: 'memory://live',
        initialSession: session,
      );

      expect(notifier.state.liveBrushMask, brush);
      expect(notifier.state.livePortrait, portrait);

      notifier.undo();
      expect(notifier.state.liveBrushMask, brush);
      expect(notifier.state.livePortrait, PortraitParams.zero);

      notifier.redo();
      expect(notifier.state.livePortrait, portrait);
    });

    test('curves, crop, filter, and creative follow undo and redo correctly',
        () {
      final curveMap = {
        CurveChannel.rgb: const CurveData(
          channel: CurveChannel.rgb,
          points: [CurvePoint(0, 0), CurvePoint(1, 1)],
        ),
      };
      const crop = CropState(
        ratio: CropRatioPreset.r1x1,
        centerX: 0.4,
        centerY: 0.6,
      );
      const creative = CreativeParams(
        blendOpacity: 0.7,
        overlayText: 'Hello',
      );

      final session = EditSession.forImage('memory://all_tools')
          .pushOp(EditOperation(
            id: 'filter-op',
            tool: EditToolType.filter,
            appliedAt: DateTime(2026, 6, 2),
            presetId: 'vintage',
            lutPath: '/filters/vintage/lut.bin',
            intensity: 0.8,
          ))
          .pushOp(EditOperation(
            id: 'curve-op',
            tool: EditToolType.curve,
            appliedAt: DateTime(2026, 6, 2),
            curves: curveMap,
          ))
          .pushOp(EditOperation(
            id: 'crop-op',
            tool: EditToolType.crop,
            appliedAt: DateTime(2026, 6, 2),
            cropState: crop,
          ))
          .pushOp(EditOperation(
            id: 'creative-op',
            tool: EditToolType.creative,
            appliedAt: DateTime(2026, 6, 2),
            creative: creative,
          ));

      final notifier = EditSessionNotifier(
        imageUri: 'memory://all_tools',
        initialSession: session,
      );

      // Verify initial live state
      expect(notifier.state.liveFilter.presetId, 'vintage');
      expect(notifier.state.liveFilter.lutPath, '/filters/vintage/lut.bin');
      expect(notifier.state.liveFilter.intensity, 0.8);
      expect(notifier.state.liveCurves[CurveChannel.rgb],
          curveMap[CurveChannel.rgb]);
      expect(notifier.state.liveCropState, crop);
      expect(notifier.state.liveCreative, creative);

      // Undo creative
      notifier.undo();
      expect(notifier.state.liveCreative, CreativeParams.zero);
      expect(notifier.state.liveCropState, crop);

      // Undo crop
      notifier.undo();
      expect(notifier.state.liveCropState, CropState.identity);
      expect(notifier.state.liveCurves[CurveChannel.rgb],
          curveMap[CurveChannel.rgb]);

      // Undo curves
      notifier.undo();
      expect(notifier.state.liveCurves, isEmpty);
      expect(notifier.state.liveFilter.presetId, 'vintage');

      // Undo filter
      notifier.undo();
      expect(notifier.state.liveFilter.presetId, isNull);
      expect(notifier.state.liveFilter.lutPath, isNull);

      // Redo filter
      notifier.redo();
      expect(notifier.state.liveFilter.presetId, 'vintage');
      expect(notifier.state.liveFilter.lutPath, '/filters/vintage/lut.bin');

      // Redo curves
      notifier.redo();
      expect(notifier.state.liveCurves[CurveChannel.rgb],
          curveMap[CurveChannel.rgb]);

      // Redo crop
      notifier.redo();
      expect(notifier.state.liveCropState, crop);

      // Redo creative
      notifier.redo();
      expect(notifier.state.liveCreative, creative);
    });
  });
}

EditOperation _adjust(String id, {required double exposure}) => EditOperation(
      id: id,
      tool: EditToolType.globalAdjust,
      appliedAt: DateTime(2026, 6, 2),
      params: AdjustParams(exposure: exposure),
    );
