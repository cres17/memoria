import 'package:memoria/domain/models/edit_operation.dart';

/// The single production owner of an editor's committed history.
///
/// UI state remains in the screen while a tool is being adjusted. Once the
/// user applies it, this controller owns the immutable snapshot list and
/// provides the only transitions for apply, undo, redo, and draft restore.
class EditorHistoryController {
  final String imageUri;
  List<EditOperation> _operations = const [];
  int _cursor = 0;

  static const _maxOperations = 100;

  EditorHistoryController(this.imageUri);

  List<EditOperation> get operations => List.unmodifiable(_operations);
  int get cursor => _cursor;
  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _operations.length;
  EditOperation? get activeOperation =>
      _cursor == 0 ? null : _operations[_cursor - 1];

  void apply(EditOperation operation) {
    final next = [..._operations.take(_cursor), operation];
    _operations = next.length > _maxOperations
        ? List.unmodifiable(next.sublist(next.length - _maxOperations))
        : List.unmodifiable(next);
    _cursor = _operations.length;
  }

  /// Moves to the previous committed snapshot and returns it, or null when
  /// the editor returns to its pristine state.
  EditOperation? undo() {
    if (!canUndo) return activeOperation;
    _cursor--;
    return activeOperation;
  }

  /// Moves to the next committed snapshot and returns it.
  EditOperation? redo() {
    if (!canRedo) return activeOperation;
    _cursor++;
    return activeOperation;
  }

  void reset() {
    _operations = const [];
    _cursor = 0;
  }

  Map<String, dynamic> toJson() => {
        'imageUri': imageUri,
        'ops': _operations.map((operation) => operation.toJson()).toList(),
        'undoCursor': _cursor,
      };

  static EditorHistoryState? parseJson(
    Map<String, dynamic> json, {
    required String expectedImageUri,
  }) {
    if (json['imageUri'] != expectedImageUri || json['ops'] is! List) {
      return null;
    }
    final operations = (json['ops'] as List)
        .map((raw) => EditOperation.fromJson(raw as Map<String, dynamic>))
        .toList(growable: false);
    final cursor = (json['undoCursor'] as num?)?.toInt() ?? operations.length;
    if (cursor < 0 || cursor > operations.length) return null;
    return EditorHistoryState(operations: operations, cursor: cursor);
  }

  void restore(EditorHistoryState state) {
    _operations = List.unmodifiable(state.operations);
    _cursor = state.cursor;
  }
}

class EditorHistoryState {
  final List<EditOperation> operations;
  final int cursor;

  const EditorHistoryState({required this.operations, required this.cursor});
}
