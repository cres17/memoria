import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/edit_session_repository.dart';
import '../../domain/models/edit_operation.dart';
import '../../domain/models/edit_session.dart';

final editSessionRepositoryProvider = Provider<EditSessionRepository>(
  (ref) => EditSessionRepository(),
);

final editSessionProvider =
    StateNotifierProvider.family<EditSessionNotifier, EditSession, String>(
        (ref, imageUri) {
  return EditSessionNotifier(
    imageUri: imageUri,
    repository: ref.watch(editSessionRepositoryProvider),
  );
});

class EditSessionNotifier extends StateNotifier<EditSession> {
  final EditSessionRepository? _repository;
  Timer? _saveDebounce;

  EditSessionNotifier({
    required String imageUri,
    EditSessionRepository? repository,
    EditSession? initialSession,
  })  : _repository = repository,
        super(initialSession ?? EditSession.forImage(imageUri));

  bool get canUndo => state.canUndo;
  bool get canRedo => state.canRedo;

  Future<void> loadSaved() async {
    final repository = _repository;
    if (repository == null) return;
    state = await repository.load(state.imageUri);
  }

  void pushOp(EditOperation op) {
    state = state.pushOp(op);
    _schedulePersist();
  }

  void undo() {
    if (!state.canUndo) return;
    state = state.undo();
    _schedulePersist(flush: true);
  }

  void redo() {
    if (!state.canRedo) return;
    state = state.redo();
    _schedulePersist(flush: true);
  }

  void resetOps() {
    state = state.resetOps();
    _schedulePersist(flush: true);
  }

  void _schedulePersist({bool flush = false}) {
    final repository = _repository;
    if (repository == null) return;
    _saveDebounce?.cancel();
    if (flush) {
      unawaited(_persist());
      return;
    }
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final repository = _repository;
    if (repository == null) return;
    await repository.save(state);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    unawaited(_persist());
    super.dispose();
  }
}
