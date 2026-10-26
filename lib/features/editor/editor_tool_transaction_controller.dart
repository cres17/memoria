import 'dart:typed_data';

import 'package:memoria/features/editor/editor_state_adapter.dart';

/// Immutable state captured when an editor tool is opened.
class EditorToolEntryState {
  final EditorStateSnapshot snapshot;
  final Uint8List? lutBytes;

  const EditorToolEntryState({
    required this.snapshot,
    required this.lutBytes,
  });
}

/// Owns the lifecycle of one temporary editor-tool transaction.
///
/// The widget remains responsible for rendering and applying snapshots, while
/// this controller guarantees that a tool entry is either cancelled back to
/// its captured state or completed explicitly. A second tool cannot silently
/// overwrite an unfinished transaction.
class EditorToolTransactionController {
  String? _activeToolId;
  String? _activeToolName;
  EditorToolEntryState? _entryState;

  bool get isActive => _entryState != null;
  String? get activeToolId => _activeToolId;
  String? get activeToolName => _activeToolName;

  bool isActiveTool(String toolId) => isActive && _activeToolId == toolId;

  void begin({
    required String toolId,
    required String toolName,
    required EditorStateSnapshot snapshot,
    required Uint8List? lutBytes,
  }) {
    if (isActive) {
      throw StateError(
        'Cancel or complete the active tool before beginning another one.',
      );
    }
    _activeToolId = toolId;
    _activeToolName = toolName;
    _entryState = EditorToolEntryState(
      snapshot: snapshot,
      lutBytes: lutBytes,
    );
  }

  /// Ends the transaction and returns the exact state captured at entry.
  EditorToolEntryState? cancel() {
    final entryState = _entryState;
    _clear();
    return entryState;
  }

  /// Ends the transaction without restoring its entry state.
  void complete() => _clear();

  void _clear() {
    _entryState = null;
    _activeToolId = null;
    _activeToolName = null;
  }
}
