import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A quarantined custom-filter index that was rebuilt automatically.
///
/// The file path stays internal to the service. UI can show only the recovery
/// decision and byte count, which avoids exposing user-created filter names or
/// local paths in a settings screen.
class FilterIndexRecoveryEntry {
  final String _path;
  final int rawByteLength;

  const FilterIndexRecoveryEntry._({
    required String path,
    required this.rawByteLength,
  }) : _path = path;
}

class FilterIndexRecoveryAttempt {
  final bool recovered;
  final int recoveredItemCount;

  const FilterIndexRecoveryAttempt({
    required this.recovered,
    required this.recoveredItemCount,
  });
}

/// User-facing lifecycle for the file quarantine created by
/// [FilterRepositoryImpl] when its index cannot be decoded.
///
/// The repository already rebuilds the active index from valid preset metadata
/// at detection time. A recovery attempt therefore merges any decodable ids
/// from the original with that rebuilt index, then archives the original. This
/// cannot erase the working rebuilt index simply because the old source was
/// stale or only partially useful.
class FilterIndexRecoveryService {
  static const _indexFileName = 'filters_index.json';
  static const _quarantinePrefix = '$_indexFileName.corrupt.';
  static const _archiveSuffix = '.recovery_archive';

  final Future<Directory> Function() _filtersDirectory;

  FilterIndexRecoveryService({
    Future<Directory> Function()? filtersDirectory,
  }) : _filtersDirectory = filtersDirectory ?? _defaultFiltersDirectory;

  static Future<Directory> _defaultFiltersDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/filters');
  }

  Future<List<FilterIndexRecoveryEntry>> pending() async {
    final directory = await _filtersDirectory();
    if (!await directory.exists()) return const [];

    final entries = <FilterIndexRecoveryEntry>[];
    await for (final entity in directory.list()) {
      final filename = entity.path.split(Platform.pathSeparator).last;
      if (entity is! File ||
          !filename.startsWith(_quarantinePrefix) ||
          filename.endsWith(_archiveSuffix)) {
        continue;
      }
      entries.add(
        FilterIndexRecoveryEntry._(
          path: entity.path,
          rawByteLength: await entity.length(),
        ),
      );
    }
    entries.sort((a, b) => a._path.compareTo(b._path));
    return entries;
  }

  Future<FilterIndexRecoveryAttempt> tryRecover(
    FilterIndexRecoveryEntry entry,
  ) async {
    final source = File(entry._path);
    if (!await source.exists()) {
      return const FilterIndexRecoveryAttempt(
        recovered: false,
        recoveredItemCount: 0,
      );
    }

    final recoveredIds = await _readIds(source);
    if (recoveredIds == null) {
      return const FilterIndexRecoveryAttempt(
        recovered: false,
        recoveredItemCount: 0,
      );
    }

    final directory = await _filtersDirectory();
    await directory.create(recursive: true);
    final index = File('${directory.path}/$_indexFileName');
    final rebuiltIds = await _readIds(index) ?? const <String>[];
    final mergedIds = {...rebuiltIds, ...recoveredIds}.toList()..sort();
    await _atomicWrite(index, jsonEncode(mergedIds));
    await _archive(source);
    return FilterIndexRecoveryAttempt(
      recovered: true,
      recoveredItemCount: recoveredIds.length,
    );
  }

  /// Marks a quarantine as handled while retaining its original contents.
  /// The already rebuilt active index is deliberately left untouched.
  Future<void> resetKeepingOriginal(FilterIndexRecoveryEntry entry) async {
    final source = File(entry._path);
    if (await source.exists()) await _archive(source);
  }

  /// Removes only the quarantined original. The active rebuilt index and all
  /// custom filter metadata remain intact.
  Future<void> discardOriginal(FilterIndexRecoveryEntry entry) async {
    final source = File(entry._path);
    if (await source.exists()) await source.delete();
  }

  Future<List<String>?> _readIds(File file) async {
    if (!await file.exists()) return const <String>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return null;
      return decoded.whereType<String>().toSet().toList()..sort();
    } on FormatException {
      return null;
    }
  }

  Future<void> _atomicWrite(File destination, String contents) async {
    final temporary = File('${destination.path}.recovery_tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(destination.path);
  }

  Future<void> _archive(File source) async {
    await source.rename('${source.path}$_archiveSuffix');
  }
}
