import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/edit_session.dart';

void main() {
  group('EditOperation round-trip coverage', () {
    test('selective operation preserves points and local params', () {
      final op = _op(
        EditToolType.selective,
        selectivePoints: const [
          SelectivePoint(
            x: 0.25,
            y: 0.75,
            radius: 0.18,
            mode: SelectiveMode.colorAuto,
            localParams: AdjustParams(exposure: 0.4, saturation: -20),
          ),
        ],
      );

      final rt = EditOperation.fromJsonString(op.toJsonString());

      expect(rt.tool, EditToolType.selective);
      expect(rt.selectivePoints, hasLength(1));
      expect(rt.selectivePoints!.single.mode, SelectiveMode.colorAuto);
      expect(rt.selectivePoints!.single.localParams.exposure, 0.4);
      expect(rt.selectivePoints!.single.localParams.saturation, -20);
    });

    test('heal operation preserves stroke geometry', () {
      final op = _op(
        EditToolType.heal,
        healStrokes: const [
          HealStroke(
            radius: 0.04,
            path: [
              {'x': 0.2, 'y': 0.3},
              {'x': 0.6, 'y': 0.7},
            ],
          ),
        ],
      );

      final rt = EditOperation.fromJsonString(op.toJsonString());

      expect(rt.tool, EditToolType.heal);
      expect(rt.healStrokes, hasLength(1));
      expect(rt.healStrokes!.single.radius, 0.04);
      expect(rt.healStrokes!.single.path.last['x'], 0.6);
      expect(rt.healStrokes!.single.path.last['y'], 0.7);
    });

    test('rawDevelop operation preserves noise parameters', () {
      final op = _op(
        EditToolType.rawDevelop,
        params: const AdjustParams(luminanceNR: 35, colourNR: 20, nrDetail: 12),
      );

      final rt = EditOperation.fromJsonString(op.toJsonString());

      expect(rt.tool, EditToolType.rawDevelop);
      expect(rt.params!.luminanceNR, 35);
      expect(rt.params!.colourNR, 20);
      expect(rt.params!.nrDetail, 12);
    });

    test('portrait operation preserves head pose parameters', () {
      final op = _op(
        EditToolType.portrait,
        portrait: const PortraitParams(
          smooth: 12,
          spotlight: 8,
          headYaw: 35,
          headPitch: -20,
        ),
      );

      final rt = EditOperation.fromJsonString(op.toJsonString());

      expect(rt.tool, EditToolType.portrait);
      expect(rt.portrait!.headYaw, 35);
      expect(rt.portrait!.headPitch, -20);
      expect(rt.portrait!.isZero, isFalse);
    });

    test('filter operation preserves preset id, LUT path, and intensity', () {
      final op = EditOperation(
        id: 'rt-filter',
        tool: EditToolType.filter,
        appliedAt: DateTime.utc(2026, 6, 2),
        presetId: 'custom-film',
        lutPath: '/local/filters/custom-film/lut.bin',
        intensity: 0.62,
        params: const AdjustParams(saturation: 12),
      );

      final rt = EditOperation.fromJsonString(op.toJsonString());

      expect(rt.tool, EditToolType.filter);
      expect(rt.presetId, 'custom-film');
      expect(rt.lutPath, '/local/filters/custom-film/lut.bin');
      expect(rt.intensity, 0.62);
      expect(rt.params!.saturation, 12);
    });

    test('schema v2 preserves artistic and every local effect state', () {
      final op = EditOperation(
        id: 'rt-effects',
        tool: EditToolType.brush,
        schemaVersion: 2,
        appliedAt: DateTime.utc(2026, 8, 20),
        effectState: const EditorEffectState(
          artisticEffect: 'drama',
          effectStrength: 0.72,
          grainVariant: 5,
          selectiveActive: true,
          selectiveX: 0.2,
          selectiveY: 0.8,
          selectiveBrightness: 0.3,
          selectiveContrast: -0.2,
          selectiveSaturation: 0.4,
          selectiveRadius: 0.18,
          dodgeBurnActive: true,
          brushMode: 'burn',
          dodgeY: 0.24,
          dodgeRadius: 0.15,
          dodgeStrength: 0.45,
          burnY: 0.76,
          burnRadius: 0.2,
          burnStrength: 0.55,
          brushStrokes: [
            DodgeBurnHistoryStroke(
              x: 0.12,
              y: 0.34,
              radius: 0.08,
              strength: 0.67,
              isDodge: false,
            ),
          ],
          tiltActive: true,
          tiltFocusCenter: 0.42,
          tiltBandWidth: 0.21,
          tiltMaxBlur: 7.5,
          lensActive: true,
          lensFocusDepth: 0.63,
          lensMaxRadius: 9.25,
        ),
      );

      final rt = EditOperation.fromJsonString(op.toJsonString());
      final state = rt.effectState!;

      expect(rt.schemaVersion, 2);
      expect(state.artisticEffect, 'drama');
      expect(state.effectStrength, 0.72);
      expect(state.grainVariant, 5);
      expect(state.selectiveActive, isTrue);
      expect(state.selectiveX, 0.2);
      expect(state.selectiveY, 0.8);
      expect(state.selectiveBrightness, 0.3);
      expect(state.selectiveContrast, -0.2);
      expect(state.selectiveSaturation, 0.4);
      expect(state.selectiveRadius, 0.18);
      expect(state.dodgeBurnActive, isTrue);
      expect(state.brushMode, 'burn');
      expect(state.dodgeStrength, 0.45);
      expect(state.burnStrength, 0.55);
      expect(state.brushStrokes, hasLength(1));
      expect(state.brushStrokes.single.x, 0.12);
      expect(state.brushStrokes.single.y, 0.34);
      expect(state.brushStrokes.single.radius, 0.08);
      expect(state.brushStrokes.single.strength, 0.67);
      expect(state.brushStrokes.single.isDodge, isFalse);
      expect(state.tiltActive, isTrue);
      expect(state.tiltFocusCenter, 0.42);
      expect(state.tiltBandWidth, 0.21);
      expect(state.tiltMaxBlur, 7.5);
      expect(state.lensActive, isTrue);
      expect(state.lensFocusDepth, 0.63);
      expect(state.lensMaxRadius, 9.25);
    });

    test('schema v1 operation without effect state remains compatible', () {
      final legacy = EditOperation.fromJson({
        'id': 'legacy',
        'tool': 'globalAdjust',
        'v': 1,
        'at': '2026-01-01T00:00:00.000Z',
        'params': const AdjustParams(exposure: 0.2).toJson(),
      });

      expect(legacy.schemaVersion, 1);
      expect(legacy.effectState, isNull);
      expect(legacy.params!.exposure, 0.2);
    });
  });

  group('EditSession round-trip coverage', () {
    test('active cursor and future redo branch survive serialization', () {
      final session = EditSession.forImage('memory://roundtrip')
          .pushOp(_op(EditToolType.globalAdjust,
              params: const AdjustParams(exposure: 0.2)))
          .pushOp(_op(EditToolType.rawDevelop,
              params: const AdjustParams(luminanceNR: 25)))
          .undo();

      final rt = EditSession.fromJsonString(session.toJsonString());

      expect(rt.imageUri, session.imageUri);
      expect(rt.ops, hasLength(2));
      expect(rt.undoCursor, 1);
      expect(rt.activeOps, hasLength(1));
      expect(rt.canRedo, isTrue);
    });
  });
}

EditOperation _op(
  EditToolType tool, {
  AdjustParams? params,
  List<SelectivePoint>? selectivePoints,
  List<HealStroke>? healStrokes,
  PortraitParams? portrait,
  EditorEffectState? effectState,
}) =>
    EditOperation(
      id: 'rt-${tool.name}',
      tool: tool,
      appliedAt: DateTime.utc(2026, 6, 2),
      params: params,
      selectivePoints: selectivePoints,
      healStrokes: healStrokes,
      portrait: portrait,
      effectState: effectState,
    );
