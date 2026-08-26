import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/features/editor/editor_history_controller.dart';

EditOperation operation(String id) => EditOperation(
      id: id,
      tool: EditToolType.globalAdjust,
      schemaVersion: 2,
      appliedAt: DateTime(2026),
    );

void main() {
  test('apply, undo, and redo have one authoritative cursor', () {
    final controller = EditorHistoryController('photo');
    controller.apply(operation('one'));
    controller.apply(operation('two'));

    expect(controller.activeOperation!.id, 'two');
    expect(controller.undo()!.id, 'one');
    expect(controller.undo(), isNull);
    expect(controller.canRedo, isTrue);
    expect(controller.redo()!.id, 'one');
    expect(controller.redo()!.id, 'two');
  });

  test('apply after undo discards the stale redo branch', () {
    final controller = EditorHistoryController('photo');
    controller.apply(operation('one'));
    controller.apply(operation('two'));
    controller.undo();
    controller.apply(operation('three'));

    expect(controller.operations.map((op) => op.id), ['one', 'three']);
    expect(controller.canRedo, isFalse);
  });
}
