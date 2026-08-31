import 'package:flutter/material.dart';
import 'package:memoria/core/l10n/strings.dart';
import 'package:memoria/domain/models/edit_operation.dart';

class EditorToolDefinition {
  final String id;
  final String labelKey;
  String get label => S.get(labelKey);
  final IconData icon;
  final EditToolType historyTool;

  const EditorToolDefinition({
    required this.id,
    required this.labelKey,
    required this.icon,
    required this.historyTool,
  });
}

/// Single inventory for every tool exposed by the editor grid.
const editorToolCatalog = <EditorToolDefinition>[
  EditorToolDefinition(
      id: 'tune',
      labelKey: 'tool.tune',
      icon: Icons.tune_rounded,
      historyTool: EditToolType.globalAdjust),
  EditorToolDefinition(
      id: 'details',
      labelKey: 'tool.details',
      icon: Icons.details_rounded,
      historyTool: EditToolType.details),
  EditorToolDefinition(
      id: 'curves',
      labelKey: 'tool.curves',
      icon: Icons.waves_rounded,
      historyTool: EditToolType.curve),
  EditorToolDefinition(
      id: 'white_balance',
      labelKey: 'tool.white_balance',
      icon: Icons.wb_sunny_rounded,
      historyTool: EditToolType.globalAdjust),
  EditorToolDefinition(
      id: 'crop',
      labelKey: 'tool.crop',
      icon: Icons.crop_rounded,
      historyTool: EditToolType.crop),
  EditorToolDefinition(
      id: 'rotate',
      labelKey: 'tool.rotate',
      icon: Icons.rotate_right_rounded,
      historyTool: EditToolType.crop),
  EditorToolDefinition(
      id: 'perspective',
      labelKey: 'tool.perspective',
      icon: Icons.transform_rounded,
      historyTool: EditToolType.crop),
  EditorToolDefinition(
      id: 'expand',
      labelKey: 'tool.expand',
      icon: Icons.aspect_ratio_rounded,
      historyTool: EditToolType.crop),
  EditorToolDefinition(
      id: 'hsl',
      labelKey: 'tool.hsl',
      icon: Icons.color_lens_rounded,
      historyTool: EditToolType.hslAdjust),
  EditorToolDefinition(
      id: 'selective',
      labelKey: 'tool.selective',
      icon: Icons.filter_center_focus_rounded,
      historyTool: EditToolType.selective),
  EditorToolDefinition(
      id: 'brush',
      labelKey: 'tool.brush',
      icon: Icons.brush_rounded,
      historyTool: EditToolType.brush),
  EditorToolDefinition(
      id: 'tilt_shift',
      labelKey: 'tool.tilt_shift',
      icon: Icons.blur_linear_rounded,
      historyTool: EditToolType.selective),
  EditorToolDefinition(
      id: 'lens_blur',
      labelKey: 'tool.lens_blur',
      icon: Icons.blur_circular_rounded,
      historyTool: EditToolType.selective),
  EditorToolDefinition(
      id: 'vignette',
      labelKey: 'tool.vignette',
      icon: Icons.vignette_rounded,
      historyTool: EditToolType.vignette),
  EditorToolDefinition(
      id: 'grain',
      labelKey: 'tool.grain',
      icon: Icons.grain_rounded,
      historyTool: EditToolType.grainOverlay),
  EditorToolDefinition(
      id: 'split_toning',
      labelKey: 'tool.split_toning',
      icon: Icons.looks_rounded,
      historyTool: EditToolType.splitTone),
  EditorToolDefinition(
      id: 'noise',
      labelKey: 'tool.noise',
      icon: Icons.texture_rounded,
      historyTool: EditToolType.rawDevelop),
  EditorToolDefinition(
      id: 'glow',
      labelKey: 'tool.glow',
      icon: Icons.wb_twilight_rounded,
      historyTool: EditToolType.glow),
  EditorToolDefinition(
      id: 'portrait',
      labelKey: 'tool.portrait',
      icon: Icons.face_rounded,
      historyTool: EditToolType.portrait),
  EditorToolDefinition(
      id: 'double_exposure',
      labelKey: 'tool.double_exposure',
      icon: Icons.layers_rounded,
      historyTool: EditToolType.creative),
  EditorToolDefinition(
      id: 'frame',
      labelKey: 'tool.frame',
      icon: Icons.crop_original_rounded,
      historyTool: EditToolType.creative),
  EditorToolDefinition(
      id: 'text',
      labelKey: 'tool.text',
      icon: Icons.text_fields_rounded,
      historyTool: EditToolType.creative),
  EditorToolDefinition(
      id: 'light_leak',
      labelKey: 'tool.light_leak',
      icon: Icons.flare_rounded,
      historyTool: EditToolType.lightLeak),
  EditorToolDefinition(
      id: 'halation',
      labelKey: 'tool.halation',
      icon: Icons.wb_incandescent_rounded,
      historyTool: EditToolType.halation),
  EditorToolDefinition(
      id: 'drama',
      labelKey: 'tool.drama',
      icon: Icons.theater_comedy_rounded,
      historyTool: EditToolType.drama),
  EditorToolDefinition(
      id: 'hdr_scape',
      labelKey: 'tool.hdr_scape',
      icon: Icons.hdr_on_rounded,
      historyTool: EditToolType.drama),
];

EditToolType editorHistoryToolFor(String? toolId) {
  if (toolId == 'filter') return EditToolType.filter;
  for (final tool in editorToolCatalog) {
    if (tool.id == toolId) return tool.historyTool;
  }
  return EditToolType.globalAdjust;
}
