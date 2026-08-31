import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/local_adjust.dart';
import 'package:memoria/engine/portrait_engine.dart';
import 'package:memoria/features/editor/editor_edit_state.dart';
import 'package:memoria/features/editor/editor_tool_catalog.dart';
import 'package:memoria/features/editor/editor_tool_reset_controller.dart';

void main() {
  const controller = EditorToolResetController();

  for (final tool in editorToolCatalog) {
    test('WB-TOOL-RESET-${tool.id} resets only its neutral contract', () {
      final state = EditorEditState();
      _makeNonNeutral(tool.id, state);

      controller.reset(tool.id, state);

      _expectNeutral(tool.id, state);
    });
  }

  test('WB-TOOL-RESET-tune preserves parameters owned by other tools', () {
    const curve = CurveData(
      channel: CurveChannel.rgb,
      points: [CurvePoint(0, 0.2), CurvePoint(1, 0.8)],
    );
    final state = EditorEditState()
      ..params = const AdjustParams(
        exposure: 1,
        rgbCurve: curve,
        grainStrength: 35,
        luminanceNR: 20,
        lightLeakStrength: 15,
      )
      ..syncCurvesFromParams();

    controller.reset('tune', state);

    expect(state.params.exposure, 0);
    expect(state.params.rgbCurve, curve);
    expect(state.params.grainStrength, 35);
    expect(state.params.luminanceNR, 20);
    expect(state.params.lightLeakStrength, 15);
    expect(state.curves[CurveChannel.rgb], curve);
  });
}

void _makeNonNeutral(String toolId, EditorEditState state) {
  switch (toolId) {
    case 'tune':
      state.params = const AdjustParams(
        exposure: 1,
        contrast: 10,
        saturation: 10,
        temperature: 10,
        tint: 10,
        highlights: 10,
        shadows: 10,
        sharpen: 10,
        vignette: 10,
        structure: 10,
        clarity: 10,
        tonalShadows: 10,
        tonalMidtones: 10,
        tonalHighlights: 10,
        bnwEnabled: true,
        bnwRed: 10,
        bnwGreen: 10,
        bnwBlue: 10,
        bnwYellow: 10,
      );
      return;
    case 'details':
      state.params = state.params.copyWith(
        sharpen: 10,
        structure: 10,
        clarity: 10,
      );
      return;
    case 'curves':
      const curve = CurveData(
        channel: CurveChannel.rgb,
        points: [CurvePoint(0, 0.2), CurvePoint(1, 0.8)],
      );
      state
        ..params = state.params.copyWith(rgbCurve: curve)
        ..syncCurvesFromParams();
      return;
    case 'white_balance':
      state.params = state.params.copyWith(temperature: 20, tint: -20);
      return;
    case 'crop':
      state
        ..cropRatio = CropRatioPreset.r1x1
        ..cropCenterX = 0.2
        ..cropCenterY = 0.7
        ..cropLeft = 0.1
        ..cropTop = 0.2
        ..cropRight = 0.8
        ..cropBottom = 0.9;
      return;
    case 'rotate':
      state
        ..rotation = 15
        ..flipH = true
        ..flipV = true;
      return;
    case 'perspective':
      state
        ..perspectiveH = 4
        ..perspectiveV = -3;
      return;
    case 'expand':
      state
        ..expandTop = 0.1
        ..expandBottom = 0.2
        ..expandLeft = 0.3
        ..expandRight = 0.4
        ..expandMode = 'white';
      return;
    case 'hsl':
      state.params = state.params.copyWith(
        hsl: {
          for (final band in HslBand.values)
            band: const HslBandParams(hue: 10, saturation: 20, luminance: 30),
        },
      );
      return;
    case 'selective':
      state
        ..selectiveActive = true
        ..selectiveX = 0.2
        ..selectiveY = 0.8
        ..selectiveBrightness = 12
        ..selectiveContrast = 13
        ..selectiveSaturation = 14
        ..selectiveRadius = 0.6;
      return;
    case 'brush':
      state
        ..dodgeBurnActive = true
        ..brushMode = 'burn'
        ..dodgeY = 0.1
        ..dodgeRadius = 0.4
        ..dodgeStrength = 0.8
        ..burnY = 0.2
        ..burnRadius = 0.5
        ..burnStrength = 0.9
        ..brushStrokes.add(
          const DodgeBurnStroke(
            x: 0.2,
            y: 0.3,
            radius: 0.1,
            strength: 0.5,
            isDodge: true,
          ),
        );
      return;
    case 'tilt_shift':
      state
        ..tiltActive = true
        ..tiltFocusCenter = 0.2
        ..tiltBandWidth = 0.7
        ..tiltMaxBlur = 20;
      return;
    case 'lens_blur':
      state
        ..lensActive = true
        ..lensFocusDepth = 0.4
        ..lensMaxRadius = 15;
      return;
    case 'vignette':
      state.params = state.params.copyWith(vignette: 40);
      return;
    case 'grain':
      state.params = state.params.copyWith(
        grainStrength: 30,
        grainSize: 3,
        grainSeed: 9,
      );
      return;
    case 'split_toning':
      state.params = state.params.copyWith(
        splitShadowHue: 10,
        splitShadowSat: 20,
        splitHighHue: 30,
        splitHighSat: 40,
        splitBalance: 50,
      );
      return;
    case 'noise':
      state.params = state.params.copyWith(
        luminanceNR: 10,
        colourNR: 20,
        nrDetail: 30,
      );
      return;
    case 'glow':
      state.params = state.params.copyWith(
        glowStrength: 10,
        glowSaturation: 20,
        glowWarmth: 30,
      );
      return;
    case 'portrait':
      state
        ..portraitSmooth = 20
        ..portraitSpotlight = 30
        ..skinTone = SkinTone.medium
        ..skinToneStrength = 80;
      return;
    case 'double_exposure':
      state
        ..blendImagePath = '/blend.jpg'
        ..blendOpacity = 0.9
        ..blendMode = bm.BlendMode.overlay;
      return;
    case 'frame':
      state.frameIndex = 3;
      return;
    case 'text':
      state
        ..overlayText = 'dirty'
        ..textSize = 60
        ..textColorValue = 0xFF123456
        ..textFontFamily = 'NotoSerif'
        ..textX = 0.2
        ..textY = 0.3
        ..textRotation = 20;
      return;
    case 'light_leak':
      state.params = state.params.copyWith(
        lightLeakStrength: 30,
        lightLeakAngle: 80,
        lightLeakWarmth: 10,
      );
      return;
    case 'halation':
      state.params = state.params.copyWith(
        halationStrength: 30,
        halationThreshold: 20,
        halationWarmth: 10,
      );
      return;
    case 'drama':
    case 'hdr_scape':
      state
        ..effect = ArtisticEffect.dramaBright1
        ..effectStrength = 0.4;
      return;
  }
}

void _expectNeutral(String toolId, EditorEditState state) {
  switch (toolId) {
    case 'tune':
      expect(
        [
          state.params.exposure,
          state.params.contrast,
          state.params.saturation,
          state.params.temperature,
          state.params.tint,
          state.params.highlights,
          state.params.shadows,
          state.params.sharpen,
          state.params.vignette,
          state.params.structure,
          state.params.clarity,
          state.params.tonalShadows,
          state.params.tonalMidtones,
          state.params.tonalHighlights,
          state.params.bnwRed,
          state.params.bnwGreen,
          state.params.bnwBlue,
          state.params.bnwYellow,
        ],
        everyElement(0),
      );
      expect(state.params.bnwEnabled, isFalse);
      return;
    case 'details':
      expect(
          [state.params.sharpen, state.params.structure, state.params.clarity],
          everyElement(0));
      return;
    case 'curves':
      expect(state.params.hasCurves, isFalse);
      expect(state.curves, isEmpty);
      return;
    case 'white_balance':
      expect([state.params.temperature, state.params.tint], everyElement(0));
      return;
    case 'crop':
      expect(state.cropRatio, CropRatioPreset.free);
      expect([state.cropCenterX, state.cropCenterY], everyElement(0.5));
      expect([state.cropLeft, state.cropTop], everyElement(0));
      expect([state.cropRight, state.cropBottom], everyElement(1));
      return;
    case 'rotate':
      expect(state.rotation, 0);
      expect(state.flipH, isFalse);
      expect(state.flipV, isFalse);
      return;
    case 'perspective':
      expect([state.perspectiveH, state.perspectiveV], everyElement(0));
      return;
    case 'expand':
      expect(
        [
          state.expandTop,
          state.expandBottom,
          state.expandLeft,
          state.expandRight
        ],
        everyElement(0),
      );
      expect(state.expandMode, 'black');
      return;
    case 'hsl':
      expect(state.params.hsl.values.every((value) => value.isZero), isTrue);
      return;
    case 'selective':
      expect(state.selectiveActive, isFalse);
      expect([state.selectiveX, state.selectiveY], everyElement(0.5));
      expect(
        [
          state.selectiveBrightness,
          state.selectiveContrast,
          state.selectiveSaturation
        ],
        everyElement(0),
      );
      expect(state.selectiveRadius, 0.3);
      return;
    case 'brush':
      expect(state.dodgeBurnActive, isFalse);
      expect(state.brushMode, 'dodge');
      expect(state.brushStrokes, isEmpty);
      expect([state.dodgeY, state.dodgeRadius], everyElement(0.25));
      expect(state.dodgeStrength, 0.3);
      expect(state.burnY, 0.75);
      expect(state.burnRadius, 0.25);
      expect(state.burnStrength, 0.3);
      return;
    case 'tilt_shift':
      expect(state.tiltActive, isFalse);
      expect(state.tiltFocusCenter, 0.5);
      expect(state.tiltBandWidth, 0.3);
      expect(state.tiltMaxBlur, 0);
      return;
    case 'lens_blur':
      expect(state.lensActive, isFalse);
      expect([state.lensFocusDepth, state.lensMaxRadius], everyElement(0));
      return;
    case 'vignette':
      expect(state.params.vignette, 0);
      return;
    case 'grain':
      expect(state.params.grainStrength, 0);
      expect(state.params.grainSize, 1);
      expect(state.params.grainSeed, 0);
      return;
    case 'split_toning':
      expect(
        [
          state.params.splitShadowHue,
          state.params.splitShadowSat,
          state.params.splitHighHue,
          state.params.splitHighSat,
          state.params.splitBalance,
        ],
        everyElement(0),
      );
      return;
    case 'noise':
      expect(
        [
          state.params.luminanceNR,
          state.params.colourNR,
          state.params.nrDetail
        ],
        everyElement(0),
      );
      return;
    case 'glow':
      expect(
        [
          state.params.glowStrength,
          state.params.glowSaturation,
          state.params.glowWarmth
        ],
        everyElement(0),
      );
      return;
    case 'portrait':
      expect([state.portraitSmooth, state.portraitSpotlight], everyElement(0));
      expect(state.skinTone, SkinTone.none);
      expect(state.skinToneStrength, 50);
      return;
    case 'double_exposure':
      expect(state.blendImagePath, isNull);
      expect(state.blendOpacity, 0.5);
      expect(state.blendMode, bm.BlendMode.lighten);
      return;
    case 'frame':
      expect(state.frameIndex, -1);
      return;
    case 'text':
      expect(state.overlayText, isEmpty);
      expect(state.textSize, 32);
      expect(state.textColorValue, 0xFFFFFFFF);
      expect(state.textFontFamily, 'Montserrat');
      expect(state.textX, 0.5);
      expect(state.textY, 0.82);
      expect(state.textRotation, 0);
      return;
    case 'light_leak':
      expect(state.params.lightLeakStrength, 0);
      expect(state.params.lightLeakAngle, 35);
      expect(state.params.lightLeakWarmth, 55);
      return;
    case 'halation':
      expect(state.params.halationStrength, 0);
      expect(state.params.halationThreshold, 70);
      expect(state.params.halationWarmth, 70);
      return;
    case 'drama':
    case 'hdr_scape':
      expect(state.effect, ArtisticEffect.none);
      expect(state.effectStrength, 1);
      return;
  }
}
