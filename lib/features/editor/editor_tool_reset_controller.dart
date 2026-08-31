import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/portrait_engine.dart';
import 'package:memoria/features/editor/editor_edit_state.dart';

class EditorToolResetResult {
  final bool invalidatePresetSelection;
  final bool clearLutBytes;

  const EditorToolResetResult({
    this.invalidatePresetSelection = false,
    this.clearLutBytes = false,
  });
}

/// Pure reset policy for every production editor tool.
class EditorToolResetController {
  const EditorToolResetController();

  EditorToolResetResult reset(String? toolId, EditorEditState state) {
    switch (toolId) {
      case 'filter':
        state
          ..selectedPreset = null
          ..intensity = 1
          ..params = AdjustParams.zero
          ..syncCurvesFromParams();
        return const EditorToolResetResult(
          invalidatePresetSelection: true,
          clearLutBytes: true,
        );
      case 'tune':
        state.params = state.params.copyWith(
          exposure: 0,
          contrast: 0,
          saturation: 0,
          temperature: 0,
          tint: 0,
          highlights: 0,
          shadows: 0,
          sharpen: 0,
          vignette: 0,
          structure: 0,
          clarity: 0,
          tonalShadows: 0,
          tonalMidtones: 0,
          tonalHighlights: 0,
          bnwEnabled: false,
          bnwRed: 0,
          bnwGreen: 0,
          bnwBlue: 0,
          bnwYellow: 0,
        );
        break;
      case 'details':
        state.params = state.params.copyWith(
          sharpen: 0,
          structure: 0,
          clarity: 0,
        );
        break;
      case 'curves':
        final json = Map<String, dynamic>.from(state.params.toJson())
          ..remove('luminanceCurve')
          ..remove('rgbCurve')
          ..remove('redCurve')
          ..remove('greenCurve')
          ..remove('blueCurve');
        state
          ..params = AdjustParams.fromJson(json)
          ..curves.clear();
        break;
      case 'white_balance':
        state.params = state.params.copyWith(temperature: 0, tint: 0);
        break;
      case 'crop':
        state
          ..cropRatio = CropRatioPreset.free
          ..cropCenterX = 0.5
          ..cropCenterY = 0.5
          ..cropLeft = 0
          ..cropTop = 0
          ..cropRight = 1
          ..cropBottom = 1;
        break;
      case 'rotate':
        state
          ..rotation = 0
          ..flipH = false
          ..flipV = false;
        break;
      case 'perspective':
        state
          ..perspectiveH = 0
          ..perspectiveV = 0;
        break;
      case 'expand':
        state
          ..expandTop = 0
          ..expandBottom = 0
          ..expandLeft = 0
          ..expandRight = 0
          ..expandMode = 'black';
        break;
      case 'hsl':
        state.params = state.params.copyWith(
          hsl: {for (final band in HslBand.values) band: HslBandParams.zero},
        );
        break;
      case 'selective':
        state
          ..selectiveActive = false
          ..selectiveX = 0.5
          ..selectiveY = 0.5
          ..selectiveBrightness = 0
          ..selectiveContrast = 0
          ..selectiveSaturation = 0
          ..selectiveRadius = 0.3;
        break;
      case 'brush':
        state
          ..dodgeBurnActive = false
          ..brushMode = 'dodge'
          ..dodgeY = 0.25
          ..dodgeRadius = 0.25
          ..dodgeStrength = 0.3
          ..burnY = 0.75
          ..burnRadius = 0.25
          ..burnStrength = 0.3
          ..brushStrokes.clear();
        break;
      case 'tilt_shift':
        state
          ..tiltActive = false
          ..tiltFocusCenter = 0.5
          ..tiltBandWidth = 0.3
          ..tiltMaxBlur = 0;
        break;
      case 'lens_blur':
        state
          ..lensActive = false
          ..lensFocusDepth = 0
          ..lensMaxRadius = 0;
        break;
      case 'vignette':
        state.params = state.params.copyWith(vignette: 0);
        break;
      case 'grain':
        state.params = state.params.copyWith(
          grainStrength: 0,
          grainSize: 1,
          grainSeed: 0,
        );
        break;
      case 'split_toning':
        state.params = state.params.copyWith(
          splitShadowHue: 0,
          splitShadowSat: 0,
          splitHighHue: 0,
          splitHighSat: 0,
          splitBalance: 0,
        );
        break;
      case 'noise':
        state.params = state.params.copyWith(
          luminanceNR: 0,
          colourNR: 0,
          nrDetail: 0,
        );
        break;
      case 'glow':
        state.params = state.params.copyWith(
          glowStrength: 0,
          glowSaturation: 0,
          glowWarmth: 0,
        );
        break;
      case 'portrait':
        state
          ..portraitSmooth = 0
          ..portraitSpotlight = 0
          ..skinTone = SkinTone.none
          ..skinToneStrength = 50;
        break;
      case 'double_exposure':
        state
          ..blendImagePath = null
          ..blendOpacity = 0.5
          ..blendMode = bm.BlendMode.lighten;
        break;
      case 'frame':
        state.frameIndex = -1;
        break;
      case 'text':
        state
          ..overlayText = ''
          ..textSize = 32
          ..textColorValue = 0xFFFFFFFF
          ..textFontFamily = 'Montserrat'
          ..textX = 0.5
          ..textY = 0.82
          ..textRotation = 0;
        break;
      case 'light_leak':
        state.params = state.params.copyWith(
          lightLeakStrength: 0,
          lightLeakAngle: 35,
          lightLeakWarmth: 55,
        );
        break;
      case 'halation':
        state.params = state.params.copyWith(
          halationStrength: 0,
          halationThreshold: 70,
          halationWarmth: 70,
        );
        break;
      case 'drama':
      case 'hdr_scape':
        state
          ..effect = ArtisticEffect.none
          ..effectStrength = 1;
        break;
    }
    return const EditorToolResetResult();
  }
}
