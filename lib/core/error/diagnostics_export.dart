import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'error_handler.dart';

/// 기기에만 저장된 진단 기록을 사용자가 직접 골라 내보낸다(문의·오류 신고용).
///
/// 자동 전송은 하지 않는다. 사용자가 공유 시트에서 보낼 곳을 직접 선택한다.
class DiagnosticsExport {
  DiagnosticsExport({
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function(String path)? share,
    List<String> Function()? readLogs,
    DateTime Function()? now,
  })  : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _share = share ?? ((path) => Share.shareXFiles([XFile(path)])),
        _readLogs = readLogs ?? (() => ErrorLogger.logs),
        _now = now ?? DateTime.now;

  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(String path) _share;
  final List<String> Function() _readLogs;
  final DateTime Function() _now;

  /// 보고서 파일을 만들고 공유 시트를 연다. 기록이 없으면 false.
  Future<bool> exportAndShare() async {
    await ErrorLogger.flush();
    final logs = _readLogs();
    if (logs.isEmpty) return false;
    final dir = await _temporaryDirectory();
    final file = File(
        '${dir.path}/memoria_diagnostics_${_now().millisecondsSinceEpoch}.txt');
    await file.writeAsString(buildReport(logs), flush: true);
    await _share(file.path);
    return true;
  }

  String buildReport(List<String> logs) {
    final header = StringBuffer()
      ..writeln('Memoria diagnostics')
      ..writeln('created: ${_now().toIso8601String()}')
      ..writeln(
          'platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('entries: ${logs.length}')
      ..writeln('---');
    return '$header${logs.join('\n')}\n';
  }
}
