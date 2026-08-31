part of 'editor_page.dart';

extension _EditorHistoryActions on _EditorPageState {
  void _activateTool(String toolId, String toolName) {
    if (_toolTransaction.isActiveTool(toolId)) return;
    if (_isToolActive) {
      // A tool switch is a cancellation, never an implicit commit. Keep this
      // synchronous so the new tool snapshots the restored state.
      _cancelActiveTool();
    }
    _captureComparePreview();
    if (toolId == 'rotate' || toolId == 'perspective') {
      _spatialBaseBytes = _previewBytes;
    }
    _mutate(() {
      _toolTransaction.begin(
        toolId: toolId,
        toolName: toolName,
        snapshot: _currentEditorState(),
        lutBytes: _lutBytes,
      );
    });
    if (toolId == 'portrait') {
      // Portrait is the only editor tool that needs this network model. Start
      // preparing it on entry so launch and ordinary editing stay contention
      // free, while the status panel can report download progress.
      unawaited(AiManager.instance.preload(kModelSelfie));
    }
    if (toolId == 'text') {
      // Keep text editable as a live widget while this tool is open instead
      // of waiting for a full image raster on every keystroke.
      _renderPreview();
    }
  }

  void _cancelActiveTool() {
    // Ignore an in-flight LUT selection after the state has been restored.
    _presetSelectToken++;
    final entryState = _toolTransaction.cancel();
    _mutate(() {
      if (entryState != null) {
        _applyEditorState(entryState.snapshot);
        _lutBytes = entryState.lutBytes;
      }
      _spatialBaseBytes = null;
      _showComparePreview = false;
    });
    _renderPreview();
  }

  /// Resets only the active tool to its neutral state and keeps the tool open.
  /// Previously Reset restored the entry snapshot, which meant a filter or
  /// slider that already had a non-zero value could not actually be reset.
  void _resetActiveTool() {
    if (!_isToolActive) return;
    _mutate(() {
      final result = _toolResetController.reset(_activeToolId, _editState);
      if (result.invalidatePresetSelection) _presetSelectToken++;
      if (result.clearLutBytes) _lutBytes = null;
      _showComparePreview = false;
    });
    _liveParamsNotifier.value = _params;
    _liveIntensityNotifier.value = _intensity;
    _renderPreview();
  }

  void _applyActiveTool() {
    _mutate(() {
      _saveToHistory();
      _toolTransaction.complete();
      _spatialBaseBytes = null;
      _showComparePreview = false;
    });
    _renderPreview();
  }

  EditorStateSnapshot _currentEditorState() =>
      _editState.toSnapshot(localSubTabName: _localSubTab.name);

  EditorRenderRecipe _currentRenderRecipe({
    AdjustParams? adjustParams,
    Uint8List? lutBytes,
    bool overrideLutBytes = false,
    double? intensity,
  }) =>
      _currentEditorState().toRenderRecipe(
        lutBytes: _lutBytes,
        cropAspectRatio: _currentCropRect(),
        adjustParamsOverride: adjustParams,
        lutBytesOverride: lutBytes,
        overrideLutBytes: overrideLutBytes,
        intensityOverride: intensity,
      );

  void _saveToHistory() {
    _toolApplyController.apply(
      toolId: _activeToolId,
      snapshot: _currentEditorState(),
    );
  }

  void _undo() {
    if (!_history.canUndo) return;
    final op = _history.undo();

    if (op != null) {
      _mutate(() {
        _applyHistorySnapshot(op);
      });
    } else {
      _mutate(() {
        _resetCommittedState();
      });
    }
    _liveParamsNotifier.value = _params;
    _liveIntensityNotifier.value = _intensity;
    _reloadSelectedPresetLut();
    _renderPreview();
  }

  void _redo() {
    if (!_history.canRedo) return;
    final op = _history.redo();
    if (op == null) return;

    _mutate(() {
      _applyHistorySnapshot(op);
    });
    _liveParamsNotifier.value = _params;
    _liveIntensityNotifier.value = _intensity;
    _reloadSelectedPresetLut();
    _renderPreview();
  }

  FilterPreset? _presetForId(String? id) {
    if (id == null) return null;
    for (final preset in _allPresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  void _applyHistorySnapshot(EditOperation op) {
    _applyEditorState(EditorStateSnapshot.fromOperation(op));
  }

  void _applyEditorState(EditorStateSnapshot state) {
    _editState.restore(
      state,
      resolvedPreset: _presetForId(state.presetId),
    );
    _lutBytes = null;
  }

  void _resetCommittedState() {
    _applyEditorState(
      EditorStateSnapshot.initial(localSubTabName: _localSubTab.name),
    );
  }

  void _reloadSelectedPresetLut() {
    final preset = _selectedPreset;
    final token = ++_presetSelectToken;
    if (preset == null) return;
    unawaited(() async {
      final bytes = await _loadLutBytesCached(preset.lutPath);
      if (!mounted ||
          token != _presetSelectToken ||
          _selectedPreset != preset) {
        return;
      }
      _mutate(() => _lutBytes = bytes);
      await _renderPreview();
    }());
  }
}
