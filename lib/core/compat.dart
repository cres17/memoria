import 'package:flutter/material.dart';

extension ColorCompat on Color {
  /// Backwards-compatible replacement for the newer `withValues(alpha: ...)` API.
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    return withOpacity(alpha);
  }

  /// Provide a legacy `toARGB32()` method used in older codepaths.
  int toARGB32() => value;
}
