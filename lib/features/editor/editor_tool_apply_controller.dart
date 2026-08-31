import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/features/editor/editor_history_controller.dart';
import 'package:memoria/features/editor/editor_state_adapter.dart';
import 'package:memoria/features/editor/editor_tool_catalog.dart';

typedef EditorApplyClock = DateTime Function();
typedef EditorOperationIdFactory = String Function(DateTime appliedAt);

/// The single boundary between a tool's working state and committed history.
class EditorToolApplyController {
  final EditorHistoryController history;
  final EditorApplyClock _clock;
  final EditorOperationIdFactory _idFactory;

  EditorToolApplyController({
    required this.history,
    EditorApplyClock? clock,
    EditorOperationIdFactory? idFactory,
  })  : _clock = clock ?? DateTime.now,
        _idFactory = idFactory ??
            ((appliedAt) => appliedAt.microsecondsSinceEpoch.toString());

  EditOperation apply({
    required String? toolId,
    required EditorStateSnapshot snapshot,
  }) {
    final appliedAt = _clock();
    final operation = snapshot.toOperation(
      id: _idFactory(appliedAt),
      tool: editorHistoryToolFor(toolId),
      appliedAt: appliedAt,
    );
    history.apply(operation);
    return operation;
  }
}
