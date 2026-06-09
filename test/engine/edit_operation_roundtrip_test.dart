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
}) =>
    EditOperation(
      id: 'rt-${tool.name}',
      tool: tool,
      appliedAt: DateTime.utc(2026, 6, 2),
      params: params,
      selectivePoints: selectivePoints,
      healStrokes: healStrokes,
      portrait: portrait,
    );
