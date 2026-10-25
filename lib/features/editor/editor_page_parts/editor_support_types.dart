part of '../editor_page.dart';

class _PreviewParams {
  final int width;
  final int height;
  final Uint8List imageBytes;
  final EditorRenderRecipe recipe;
  final EditorRenderResources resources;
  final String? overlayTextOverride;

  const _PreviewParams({
    required this.width,
    required this.height,
    required this.imageBytes,
    required this.recipe,
    required this.resources,
    this.overlayTextOverride,
  });
}

Future<Uint8List> _previewWorker(_PreviewParams p) async {
  return EditorRenderer.renderPreviewBytes(
    EditorPreviewRenderRequest(
      width: p.width,
      height: p.height,
      imageBytes: p.imageBytes,
      recipe: p.recipe,
      resources: EditorRenderResources(
        segmentMask: p.resources.segmentMask,
        segmentMaskWidth: p.resources.segmentMaskWidth,
        segmentMaskHeight: p.resources.segmentMaskHeight,
        skyMask: p.resources.skyMask,
        skyMaskWidth: p.resources.skyMaskWidth,
        skyMaskHeight: p.resources.skyMaskHeight,
        blendImageBytes: p.resources.blendImageBytes,
        frameBytes: p.resources.frameBytes,
        overlayTextOverride: p.overlayTextOverride,
        textOverlayBytes: p.resources.textOverlayBytes,
      ),
    ),
  );
}

class _SplitClipper extends CustomClipper<Rect> {
  final double position;

  const _SplitClipper(this.position);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * position, size.height);

  @override
  bool shouldReclip(_SplitClipper oldClipper) =>
      oldClipper.position != position;
}

class _SplitLabel extends StatelessWidget {
  final String text;

  const _SplitLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ToolItem {
  final String id;
  final String label;
  final IconData icon;

  const _ToolItem({
    required this.id,
    required this.label,
    required this.icon,
  });
}

/// 도구 격자의 묶음. 순서가 화면 표시 순서다.
const List<_ToolGroup> _toolGroups = [
  _ToolGroup('보정', [
    'tune',
    'details',
    'curves',
    'white_balance',
    'hsl',
    'split_toning',
    'noise',
  ]),
  _ToolGroup('구성', ['crop', 'rotate', 'perspective', 'expand']),
  _ToolGroup('부분·인물', [
    'selective',
    'brush',
    'heal',
    'sky',
    'tilt_shift',
    'lens_blur',
    'portrait',
  ]),
  _ToolGroup('효과', [
    'vignette',
    'grain',
    'glow',
    'light_leak',
    'halation',
    'drama',
    'hdr_scape',
  ]),
  _ToolGroup('합성', ['double_exposure', 'frame', 'text']),
];

class _ToolGroup {
  final String label;
  final List<String> toolIds;

  const _ToolGroup(this.label, this.toolIds);
}
