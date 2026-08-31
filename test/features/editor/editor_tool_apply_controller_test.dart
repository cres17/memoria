import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/features/editor/editor_history_controller.dart';
import 'package:memoria/features/editor/editor_state_adapter.dart';
import 'package:memoria/features/editor/editor_tool_apply_controller.dart';
import 'package:memoria/features/editor/editor_tool_catalog.dart';

void main() {
  final appliedAt = DateTime.utc(2026, 8, 26, 1, 2, 3);
  final tools = <({String id, EditToolType historyTool})>[
    for (final tool in editorToolCatalog)
      (id: tool.id, historyTool: tool.historyTool),
    (id: 'filter', historyTool: EditToolType.filter),
  ];

  for (final tool in tools) {
    test('WB-TOOL-APPLY-${tool.id} appends exactly one typed operation', () {
      final history = EditorHistoryController('/fixture.jpg');
      final controller = EditorToolApplyController(
        history: history,
        clock: () => appliedAt,
        idFactory: (_) => 'operation-${tool.id}',
      );

      final operation = controller.apply(
        toolId: tool.id,
        snapshot: EditorStateSnapshot.initial(),
      );

      expect(history.operations, hasLength(1));
      expect(history.cursor, 1);
      expect(history.operations.single, same(operation));
      expect(operation.id, 'operation-${tool.id}');
      expect(operation.tool, tool.historyTool);
      expect(operation.appliedAt, appliedAt);
    });
  }
}
