import 'dart:typed_data';

import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/local_adjust.dart';

/// Immutable, transport-safe description of the visual editor state.
///
/// Preview and export must receive the same recipe. Source-specific data
/// (decoded pixels, output path, segmentation and text raster) deliberately
/// lives outside this type so a recipe stays a single source of truth for the
/// user's edit decisions and can cross an isolate boundary unchanged.
class EditorRenderRecipe {
  final AdjustParams adjustParams;
  final Uint8List? lutBytes;
  final double intensity;
  final CropState crop;
  final double? cropAspectRatio;
  final ArtisticEffect effect;
  final double effectStrength;
  final int grainVariant;
  final bool selectiveActive;
  final double selectiveX;
  final double selectiveY;
  final double selectiveBrightness;
  final double selectiveContrast;
  final double selectiveSaturation;
  final double selectiveRadius;
  final bool dodgeBurnActive;
  final double dodgeStrength;
  final double dodgeY;
  final double dodgeRadius;
  final double burnStrength;
  final double burnY;
  final double burnRadius;
  final bool tiltActive;
  final double tiltFocusCenter;
  final double tiltBandWidth;
  final double tiltMaxBlur;
  final bool lensActive;
  final double lensFocusDepth;
  final double lensMaxRadius;
  final PortraitParams portrait;
  final CreativeParams creative;
  final List<DodgeBurnStroke> brushStrokes;

  EditorRenderRecipe({
    required this.adjustParams,
    required this.lutBytes,
    required this.intensity,
    required this.crop,
    required this.cropAspectRatio,
    required this.effect,
    required this.effectStrength,
    required this.grainVariant,
    required this.selectiveActive,
    required this.selectiveX,
    required this.selectiveY,
    required this.selectiveBrightness,
    required this.selectiveContrast,
    required this.selectiveSaturation,
    required this.selectiveRadius,
    required this.dodgeBurnActive,
    required this.dodgeStrength,
    required this.dodgeY,
    required this.dodgeRadius,
    required this.burnStrength,
    required this.burnY,
    required this.burnRadius,
    required this.tiltActive,
    required this.tiltFocusCenter,
    required this.tiltBandWidth,
    required this.tiltMaxBlur,
    required this.lensActive,
    required this.lensFocusDepth,
    required this.lensMaxRadius,
    required this.portrait,
    required this.creative,
    required List<DodgeBurnStroke> brushStrokes,
  }) : brushStrokes = List.unmodifiable(brushStrokes);
}
