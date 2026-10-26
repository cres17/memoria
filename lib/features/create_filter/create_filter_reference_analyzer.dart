import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/style_analyzer.dart';

class CreateFilterReferenceAnalysis {
  final List<Color> palette;
  final List<String> tags;

  const CreateFilterReferenceAnalysis({
    required this.palette,
    required this.tags,
  });
}

abstract interface class CreateFilterReferenceAnalyzer {
  Future<CreateFilterReferenceAnalysis> analyze(List<String> paths);
}

/// File-backed production analyzer kept outside the page container.
class FileCreateFilterReferenceAnalyzer
    implements CreateFilterReferenceAnalyzer {
  const FileCreateFilterReferenceAnalyzer();

  @override
  Future<CreateFilterReferenceAnalysis> analyze(List<String> paths) async {
    final images = <img.Image>[];
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null) images.add(image);
    }
    if (images.isEmpty) {
      return const CreateFilterReferenceAnalysis(palette: [], tags: []);
    }

    final profiles = images.map(StyleAnalyzer.analyze).toList();
    return CreateFilterReferenceAnalysis(
      palette: extractPalette(images.first),
      tags: deriveStyleTags(StyleAnalyzer.fuseProfiles(profiles)),
    );
  }
}
