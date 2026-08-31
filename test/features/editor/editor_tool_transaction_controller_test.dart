import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/features/editor/editor_state_adapter.dart';
import 'package:memoria/features/editor/editor_tool_transaction_controller.dart';

void main() {
  test('cancel returns the exact entry snapshot and clears the transaction',
      () {
    final controller = EditorToolTransactionController();
    final snapshot = EditorStateSnapshot.initial(localSubTabName: 'selective');
    final lutBytes = Uint8List.fromList([1, 2, 3]);

    controller.begin(
      toolId: 'filter',
      toolName: 'Filter',
      snapshot: snapshot,
      lutBytes: lutBytes,
    );

    expect(controller.isActive, isTrue);
    expect(controller.isActiveTool('filter'), isTrue);
    expect(controller.activeToolName, 'Filter');

    final restored = controller.cancel();
    expect(restored?.snapshot, same(snapshot));
    expect(restored?.lutBytes, same(lutBytes));
    expect(controller.isActive, isFalse);
    expect(controller.activeToolId, isNull);
  });

  test('complete discards the backup and a nested begin is rejected', () {
    final controller = EditorToolTransactionController();
    final snapshot = EditorStateSnapshot.initial();

    controller.begin(
      toolId: 'crop',
      toolName: 'Crop',
      snapshot: snapshot,
      lutBytes: null,
    );

    expect(
      () => controller.begin(
        toolId: 'rotate',
        toolName: 'Rotate',
        snapshot: snapshot,
        lutBytes: null,
      ),
      throwsStateError,
    );

    controller.complete();
    expect(controller.isActive, isFalse);
    expect(controller.cancel(), isNull);
  });
}
