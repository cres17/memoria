import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../domain/models/adjust_params.dart';
import 'custom_lut_core.dart' show decodeCustomLut, customLutDim;

// Band order must match shader declaration order
const _kHslBandOrder = [
  HslBand.red,
  HslBand.orange,
  HslBand.yellow,
  HslBand.green,
  HslBand.cyan,
  HslBand.blue,
  HslBand.purple,
  HslBand.magenta,
];

// ── LUT atlas ────────────────────────────────────────────────────────────────
// 65³ 3D LUT → 2D atlas: width = 65*65 = 4225, height = 65
// Slice b occupies columns [b*65 .. b*65+64] on row g.
// Pixel (b*65+r, g) = LUT[r, g, b].
// Stored as RGBA8 (A = 255).

const int _dim = customLutDim; // 65
const int _atlasW = _dim * _dim; // 4225
const int _atlasH = _dim; // 65

/// Converts a decoded 65³ Float32List LUT into a [ui.Image] atlas (4225×65 RGBA8).
/// Returns null if lutBytes is empty/null (no LUT active).
Future<ui.Image?> buildLutAtlas(Uint8List? lutBytes) async {
  if (lutBytes == null || lutBytes.isEmpty) return null;

  final decoded = decodeCustomLut(lutBytes);
  final values = decoded.values; // Float32List, length = 65^3 * 3

  final pixels = Uint8List(_atlasW * _atlasH * 4);

  for (int b = 0; b < _dim; b++) {
    for (int g = 0; g < _dim; g++) {
      for (int r = 0; r < _dim; r++) {
        final srcIdx = (r + g * _dim + b * _dim * _dim) * 3;
        final dstX = b * _dim + r;
        final dstY = g;
        final dstIdx = (dstY * _atlasW + dstX) * 4;
        pixels[dstIdx] = (values[srcIdx] * 255.0).round().clamp(0, 255);
        pixels[dstIdx + 1] = (values[srcIdx + 1] * 255.0).round().clamp(0, 255);
        pixels[dstIdx + 2] = (values[srcIdx + 2] * 255.0).round().clamp(0, 255);
        pixels[dstIdx + 3] = 255;
      }
    }
  }

  final codec = await ui.ImageDescriptor.raw(
    await ui.ImmutableBuffer.fromUint8List(pixels),
    width: _atlasW,
    height: _atlasH,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  final frame = await codec.getNextFrame();
  return frame.image;
}

// ── Curve 1D texture ────────────────────────────────────────────────────────
// 256×1 RGBA8 texture.
// R = rgb master, G = red channel, B = green channel, A = blue channel.
// A linear (identity) mapping is [0,1,2,...,255] in each channel.

/// Builds a 256×1 RGBA8 [ui.Image] encoding all four curve LUTs.
/// Linear (identity) tables are used for channels with no active curve.
Future<ui.Image> buildCurve1DTexture(AdjustParams p) async {
  final List<int> rgbLut = (p.rgbCurve != null && !p.rgbCurve!.isLinear)
      ? p.rgbCurve!.toLut()
      : List.generate(256, (i) => i);
  final List<int> redLut = (p.redCurve != null && !p.redCurve!.isLinear)
      ? p.redCurve!.toLut()
      : List.generate(256, (i) => i);
  final List<int> greenLut = (p.greenCurve != null && !p.greenCurve!.isLinear)
      ? p.greenCurve!.toLut()
      : List.generate(256, (i) => i);
  final List<int> blueLut = (p.blueCurve != null && !p.blueCurve!.isLinear)
      ? p.blueCurve!.toLut()
      : List.generate(256, (i) => i);

  final pixels = Uint8List(256 * 4);
  for (int i = 0; i < 256; i++) {
    pixels[i * 4] = rgbLut[i].clamp(0, 255);
    pixels[i * 4 + 1] = redLut[i].clamp(0, 255);
    pixels[i * 4 + 2] = greenLut[i].clamp(0, 255);
    pixels[i * 4 + 3] = blueLut[i].clamp(0, 255);
  }

  final codec = await ui.ImageDescriptor.raw(
    await ui.ImmutableBuffer.fromUint8List(pixels),
    width: 256,
    height: 1,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Builds a 256×1 R8-as-RGBA8 [ui.Image] for the luminance curve delta.
/// Stored value = delta + 0.5  (so 0.5 = no change, range [0, 1]).
Future<ui.Image> buildLumCurveTexture(AdjustParams p) async {
  final pixels = Uint8List(256 * 4);
  final bool active = p.luminanceCurve != null && !p.luminanceCurve!.isLinear;

  if (active) {
    final lut = p.luminanceCurve!.toLut(); // [0..255]
    for (int i = 0; i < 256; i++) {
      // delta = remapped(i/255) - i/255, stored as (delta + 0.5) * 255
      final remapped = lut[i] / 255.0;
      final original = i / 255.0;
      final stored =
          ((remapped - original + 0.5) * 255.0).round().clamp(0, 255);
      pixels[i * 4] = stored;
      pixels[i * 4 + 1] = stored;
      pixels[i * 4 + 2] = stored;
      pixels[i * 4 + 3] = 255;
    }
  } else {
    // Identity: delta = 0 → stored = 128
    for (int i = 0; i < 256; i++) {
      pixels[i * 4] = 128;
      pixels[i * 4 + 1] = 128;
      pixels[i * 4 + 2] = 128;
      pixels[i * 4 + 3] = 255;
    }
  }

  final codec = await ui.ImageDescriptor.raw(
    await ui.ImmutableBuffer.fromUint8List(pixels),
    width: 256,
    height: 1,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  final frame = await codec.getNextFrame();
  return frame.image;
}

// ── Source image loader ──────────────────────────────────────────────────────

/// Decodes a file-path image into a [ui.Image] at full resolution.
/// The GPU shader samples it at display resolution — no CPU resize needed.
Future<ui.Image> loadUiImage(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

// ── GpuImageView ────────────────────────────────────────────────────────────

/// Renders [sourceImage] through the GPU adjust shader in real time.
/// All [AdjustParams] changes are applied by simply calling setState on the
/// parent — no isolate, no CPU pixel loop, no JPEG encoding.
///
/// Resolution: the source [ui.Image] is uploaded at full resolution to the GPU.
/// The shader samples it at display resolution (constrained by the widget size),
/// so the quality is limited only by the *display* pixel count, not the preview
/// size cap that the old CPU path imposed (960px). On a typical phone with a
/// 1080×2400 screen displaying a 800px-tall preview area, the GPU processes
/// ~864,000 pixels per frame — but in parallel across thousands of shader cores
/// instead of a single Dart thread, completing in <5 ms.
class GpuImageView extends StatefulWidget {
  final ui.Image sourceImage;
  final AdjustParams params;
  final double intensity;
  final ui.Image? lutAtlas; // null when no LUT/filter active
  final ui.Image? curve1D; // null when no RGB/channel curves active
  final ui.Image? lumCurve; // null when no luminance curve active
  final ValueNotifier<AdjustParams>? paramsNotifier;
  final ValueNotifier<double>? intensityNotifier;
  final VoidCallback? onShaderError;

  const GpuImageView({
    super.key,
    required this.sourceImage,
    required this.params,
    required this.intensity,
    this.lutAtlas,
    this.curve1D,
    this.lumCurve,
    this.paramsNotifier,
    this.intensityNotifier,
    this.onShaderError,
  });

  @override
  State<GpuImageView> createState() => _GpuImageViewState();
}

class _GpuImageViewState extends State<GpuImageView> {
  ui.FragmentShader? _shader;
  bool _shaderError = false;
  late AdjustParams _currentParams;
  late double _currentIntensity;

  @override
  void initState() {
    super.initState();
    _currentParams = widget.params;
    _currentIntensity = widget.intensity;
    _loadShader();
    widget.paramsNotifier?.addListener(_onParamsChanged);
    widget.intensityNotifier?.addListener(_onIntensityChanged);
  }

  @override
  void didUpdateWidget(GpuImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paramsNotifier != oldWidget.paramsNotifier) {
      oldWidget.paramsNotifier?.removeListener(_onParamsChanged);
      widget.paramsNotifier?.addListener(_onParamsChanged);
    }
    if (widget.intensityNotifier != oldWidget.intensityNotifier) {
      oldWidget.intensityNotifier?.removeListener(_onIntensityChanged);
      widget.intensityNotifier?.addListener(_onIntensityChanged);
    }
    if (widget.paramsNotifier == null) {
      _currentParams = widget.params;
    } else {
      _currentParams = widget.paramsNotifier!.value;
    }
    if (widget.intensityNotifier == null) {
      _currentIntensity = widget.intensity;
    } else {
      _currentIntensity = widget.intensityNotifier!.value;
    }
  }

  @override
  void dispose() {
    widget.paramsNotifier?.removeListener(_onParamsChanged);
    widget.intensityNotifier?.removeListener(_onIntensityChanged);
    super.dispose();
  }

  void _onParamsChanged() {
    if (widget.paramsNotifier != null && mounted) {
      setState(() {
        _currentParams = widget.paramsNotifier!.value;
      });
    }
  }

  void _onIntensityChanged() {
    if (widget.intensityNotifier != null && mounted) {
      setState(() {
        _currentIntensity = widget.intensityNotifier!.value;
      });
    }
  }

  Future<void> _loadShader() async {
    try {
      final program =
          await ui.FragmentProgram.fromAsset('assets/shaders/adjust.frag');
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (_) {
      if (mounted) {
        setState(() => _shaderError = true);
        widget.onShaderError?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shaderError) {
      // Shader unavailable (e.g. simulator without GPU): fall back to raw image.
      return RawImage(image: widget.sourceImage, fit: BoxFit.contain);
    }
    if (_shader == null) {
      return RawImage(image: widget.sourceImage, fit: BoxFit.contain);
    }
    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return CustomPaint(
          size: Size(w, h),
          painter: _AdjustPainter(
            shader: _shader!,
            sourceImage: widget.sourceImage,
            params: _currentParams,
            intensity: _currentIntensity,
            lutAtlas: widget.lutAtlas,
            curve1D: widget.curve1D,
            lumCurve: widget.lumCurve,
            viewSize: Size(w, h),
          ),
        );
      },
    );
  }
}

// ── CustomPainter ────────────────────────────────────────────────────────────

class _AdjustPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image sourceImage;
  final AdjustParams params;
  final double intensity;
  final ui.Image? lutAtlas;
  final ui.Image? curve1D;
  final ui.Image? lumCurve;
  final Size viewSize;

  const _AdjustPainter({
    required this.shader,
    required this.sourceImage,
    required this.params,
    required this.intensity,
    required this.lutAtlas,
    required this.curve1D,
    required this.lumCurve,
    required this.viewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Build a contain-fit rect so the image is centred with letterboxing.
    final srcW = sourceImage.width.toDouble();
    final srcH = sourceImage.height.toDouble();
    final scale = (size.width / srcW < size.height / srcH)
        ? size.width / srcW
        : size.height / srcH;
    final dstW = srcW * scale;
    final dstH = srcH * scale;
    final dstRect = Rect.fromLTWH(
      (size.width - dstW) / 2,
      (size.height - dstH) / 2,
      dstW,
      dstH,
    );

    // Source image as sampler — GPU holds it at full resolution.
    // Fallback textures when LUT/curves are inactive.
    final ui.Image lutImg = lutAtlas ?? _blank1x1;
    final ui.Image curveImg = curve1D ?? _blankCurve;
    final ui.Image lumImg = lumCurve ?? _blankLumCurve;

    final p = params;
    int si = 0;

    // setImageSampler takes ui.Image directly (Flutter 3.7+).
    shader.setImageSampler(si++, sourceImage); // uTexture
    shader.setImageSampler(si++, lutImg); // uLut
    shader.setImageSampler(si++, curveImg); // uCurve1D
    shader.setImageSampler(si++, lumImg); // uLumCurve

    int fi = 0;
    shader.setFloat(fi++, lutAtlas != null ? 1.0 : 0.0); // uLutEnabled
    shader.setFloat(fi++, _dim.toDouble()); // uLutDim
    shader.setFloat(fi++, intensity.clamp(0.0, 1.0)); // uIntensity

    final curveActive = (p.rgbCurve != null && !p.rgbCurve!.isLinear) ||
        (p.redCurve != null && !p.redCurve!.isLinear) ||
        (p.greenCurve != null && !p.greenCurve!.isLinear) ||
        (p.blueCurve != null && !p.blueCurve!.isLinear);
    shader.setFloat(fi++, curveActive ? 1.0 : 0.0); // uCurveEnabled

    final lumCurveActive =
        p.luminanceCurve != null && !p.luminanceCurve!.isLinear;
    shader.setFloat(fi++, lumCurveActive ? 1.0 : 0.0); // uLumCurveEnabled

    shader.setFloat(fi++, p.exposure); // uExposure
    shader.setFloat(fi++, p.contrast); // uContrast
    shader.setFloat(fi++, p.saturation); // uSaturation
    shader.setFloat(fi++, p.temperature); // uTemperature
    shader.setFloat(fi++, p.tint); // uTint
    shader.setFloat(fi++, p.highlights); // uHighlights
    shader.setFloat(fi++, p.shadows); // uShadows
    shader.setFloat(fi++, p.ambiance); // uAmbiance
    shader.setFloat(fi++, p.vignette); // uVignette
    shader.setFloat(fi++, p.bnwEnabled ? 1.0 : 0.0); // uBnwEnabled
    shader.setFloat(fi++, p.bnwRed); // uBnwRed
    shader.setFloat(fi++, p.bnwGreen); // uBnwGreen
    shader.setFloat(fi++, p.bnwBlue); // uBnwBlue
    shader.setFloat(fi++, p.bnwYellow); // uBnwYellow
    shader.setFloat(fi++, p.tonalShadows); // uTonalShadows
    shader.setFloat(fi++, p.tonalMidtones); // uTonalMidtones
    shader.setFloat(fi++, p.tonalHighlights); // uTonalHighlights
    // HSL per-band (8 bands × vec3)
    for (final band in _kHslBandOrder) {
      final bp = p.hsl[band] ?? HslBandParams.zero;
      shader.setFloat(fi++, bp.hue);
      shader.setFloat(fi++, bp.saturation);
      shader.setFloat(fi++, bp.luminance);
    }
    shader.setFloat(fi++, p.hasHsl ? 1.0 : 0.0); // uHslEnabled
    // Split Toning
    shader.setFloat(fi++, p.splitShadowHue); // uSplitShadow.x
    shader.setFloat(fi++, p.splitShadowSat); // uSplitShadow.y
    shader.setFloat(fi++, 0.0); // uSplitShadow.z (unused)
    shader.setFloat(fi++, p.splitHighHue); // uSplitHighlight.x
    shader.setFloat(fi++, p.splitHighSat); // uSplitHighlight.y
    shader.setFloat(fi++, 0.0); // uSplitHighlight.z (unused)
    shader.setFloat(fi++, p.splitBalance); // uSplitBalance
    shader.setFloat(fi++, p.hasSplitToning ? 1.0 : 0.0); // uSplitEnabled
    // Film Grain
    shader.setFloat(fi++, p.grainStrength); // uGrainStrength
    shader.setFloat(fi++, p.grainSize); // uGrainSize
    shader.setFloat(fi++, p.grainSeed.toDouble()); // uGrainSeed
    shader.setFloat(fi++, dstW); // uResolution.x
    shader.setFloat(fi++, dstH); // uResolution.y
    shader.setFloat(fi++, dstRect.left); // uOrigin.x
    shader.setFloat(fi++, dstRect.top); // uOrigin.y

    final paint = Paint()..shader = shader;
    canvas.drawRect(dstRect, paint);
  }

  @override
  bool shouldRepaint(_AdjustPainter old) =>
      old.params.cacheKey != params.cacheKey ||
      old.intensity != intensity ||
      old.lutAtlas != lutAtlas ||
      old.curve1D != curve1D ||
      old.lumCurve != lumCurve ||
      old.sourceImage != sourceImage ||
      old.viewSize != viewSize;
}

// ── Blank fallback textures (lazy singletons) ────────────────────────────────

ui.Image? __blank1x1;
ui.Image? __blankCurve;
ui.Image? __blankLumCurve;

ui.Image get _blank1x1 {
  assert(__blank1x1 != null,
      'GpuImageView: call GpuImageView.initFallbacks() before use');
  return __blank1x1!;
}

ui.Image get _blankCurve {
  assert(__blankCurve != null,
      'GpuImageView: call GpuImageView.initFallbacks() before use');
  return __blankCurve!;
}

ui.Image get _blankLumCurve {
  assert(__blankLumCurve != null,
      'GpuImageView: call GpuImageView.initFallbacks() before use');
  return __blankLumCurve!;
}

/// Must be called once at app startup (e.g. in main() after WidgetsFlutterBinding).
Future<void> initGpuFallbacks() async {
  __blank1x1 = await _make1x1(0, 0, 0, 0);
  __blankCurve = await _makeIdentityCurve();
  __blankLumCurve = await _makeNeutralLumCurve();
}

Future<ui.Image> _make1x1(int r, int g, int b, int a) async {
  final pixels = Uint8List(4)
    ..[0] = r
    ..[1] = g
    ..[2] = b
    ..[3] = a;
  final codec = await ui.ImageDescriptor.raw(
    await ui.ImmutableBuffer.fromUint8List(pixels),
    width: 1,
    height: 1,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  return (await codec.getNextFrame()).image;
}

Future<ui.Image> _makeIdentityCurve() async {
  final pixels = Uint8List(256 * 4);
  for (int i = 0; i < 256; i++) {
    pixels[i * 4] = i; // rgb master → identity
    pixels[i * 4 + 1] = i; // red
    pixels[i * 4 + 2] = i; // green
    pixels[i * 4 + 3] = i; // blue
  }
  final codec = await ui.ImageDescriptor.raw(
    await ui.ImmutableBuffer.fromUint8List(pixels),
    width: 256,
    height: 1,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  return (await codec.getNextFrame()).image;
}

Future<ui.Image> _makeNeutralLumCurve() async {
  final pixels = Uint8List(256 * 4);
  for (int i = 0; i < 256; i++) {
    // delta = 0 → stored as 128
    pixels[i * 4] = 128;
    pixels[i * 4 + 1] = 128;
    pixels[i * 4 + 2] = 128;
    pixels[i * 4 + 3] = 255;
  }
  final codec = await ui.ImageDescriptor.raw(
    await ui.ImmutableBuffer.fromUint8List(pixels),
    width: 256,
    height: 1,
    pixelFormat: ui.PixelFormat.rgba8888,
  ).instantiateCodec();
  return (await codec.getNextFrame()).image;
}
