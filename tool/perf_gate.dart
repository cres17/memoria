import 'dart:convert';
import 'dart:io';

/// Validates a profile/release-device editor performance report.
///
/// Usage:
///   dart run tool/perf_gate.dart --report build/perf/editor_perf.json
///   dart run tool/perf_gate.dart --report build/perf/editor_perf.json --scope preview
///   dart run tool/perf_gate.dart --report build/perf/editor_perf.json --scope export-cancel
///
/// The report is deliberately portable JSON: the integration-test runner writes
/// raw samples while this host-side tool calculates percentiles and returns a
/// non-zero exit code when an approval gate is missed.
void main(List<String> args) {
  final reportPath = _option(args, '--report');
  if (reportPath == null) {
    stderr
        .writeln('Usage: dart run tool/perf_gate.dart --report <report.json>');
    exitCode = 64;
    return;
  }
  final scope = _option(args, '--scope') ?? 'full';
  if (scope != 'full' && scope != 'preview' && scope != 'export-cancel') {
    stderr.writeln('--scope must be full, preview, or export-cancel.');
    exitCode = 64;
    return;
  }

  final file = File(reportPath);
  if (!file.existsSync()) {
    stderr.writeln('Performance report not found: $reportPath');
    exitCode = 66;
    return;
  }

  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('Performance report must be a JSON object.');
    exitCode = 65;
    return;
  }

  final failures = <String>[];
  final buildMode = decoded['buildMode'];
  if (buildMode != 'profile' && buildMode != 'release') {
    failures.add('buildMode must be profile or release (was $buildMode)');
  }
  final device = decoded['device'];
  if (device is! Map || (device['name'] as String? ?? '').isEmpty) {
    failures.add('device.name is required');
  }

  final samples = decoded['samples'];
  if (samples is! Map<String, dynamic>) {
    failures.add('samples object is required');
  } else if (scope != 'export-cancel') {
    _checkP95(
      failures,
      samples,
      key: 'frameTotalMs',
      maxMs: 16,
      minimumSamples: 30,
    );
    _checkP95(
      failures,
      samples,
      key: 'previewWarmMs',
      maxMs: 80,
      minimumSamples: 30,
    );
  }

  final metrics = decoded['metrics'];
  if (metrics is! Map<String, dynamic>) {
    failures.add('metrics object is required');
  } else {
    if (scope != 'export-cancel') {
      _checkMax(failures, metrics, 'previewColdMs', 250);
    }
    if (scope == 'full') {
      _checkMax(failures, metrics, 'exportProgressIntervalMs', 500);
    }
    if (scope == 'export-cancel') {
      _checkMax(failures, metrics, 'exportFirstProgressMs', 500);
      _checkMax(failures, metrics, 'exportCancelMs', 500);
      if (metrics['exportCompleted'] != false) {
        failures.add('exportCompleted must be false for the cancel scenario');
      }
    }
  }

  if (failures.isEmpty) {
    stdout.writeln(
        'PASS: $scope editor performance gates passed for $reportPath');
    if (scope == 'preview') {
      stdout.writeln('NOTE: export/memory gates were not evaluated.');
    } else if (scope == 'export-cancel') {
      stdout.writeln(
          'NOTE: full export completion and memory gates were not evaluated.');
    }
    return;
  }

  stderr.writeln('FAIL: editor performance gates failed:');
  for (final failure in failures) {
    stderr.writeln('- $failure');
  }
  exitCode = 1;
}

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

void _checkP95(
  List<String> failures,
  Map<String, dynamic> samples, {
  required String key,
  required double maxMs,
  required int minimumSamples,
}) {
  final values = _numbers(samples[key]);
  if (values.length < minimumSamples) {
    failures.add(
        '$key needs at least $minimumSamples samples (got ${values.length})');
    return;
  }
  final p95 = _percentile(values, 0.95);
  if (p95 > maxMs) {
    failures.add('$key p95 ${p95.toStringAsFixed(2)}ms exceeds ${maxMs}ms');
  }
}

void _checkMax(
  List<String> failures,
  Map<String, dynamic> metrics,
  String key,
  double max,
) {
  final value = (metrics[key] as num?)?.toDouble();
  if (value == null) {
    failures.add('$key is required');
  } else if (value > max) {
    failures.add('$key ${value.toStringAsFixed(2)}ms exceeds ${max}ms');
  }
}

List<double> _numbers(Object? value) {
  if (value is! List) return const [];
  return value.whereType<num>().map((number) => number.toDouble()).toList();
}

double _percentile(List<double> values, double percentile) {
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * percentile).ceil();
  return sorted[index];
}
