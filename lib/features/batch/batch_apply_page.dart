import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:memoria/core/error/error_handler.dart';
import 'package:memoria/core/services/media_permission_service.dart';
import 'package:memoria/core/theme/app_colors.dart';
import 'package:memoria/data/repositories/custom_adjustment_repository.dart';
import 'package:memoria/data/repositories/filter_repository_impl.dart';
import 'package:memoria/domain/models/custom_adjustment.dart';
import 'package:memoria/domain/models/editor_look.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/features/batch/batch_apply_service.dart';
import 'package:memoria/features/editor/editor_look_clipboard.dart';

/// 복사한 보정이나 저장한 조정을 여러 장에 한 번에 적용해 갤러리에 저장한다.
class BatchApplyPage extends StatefulWidget {
  final BatchApplyService? service;
  final Future<List<String>> Function()? pickPhotos;

  const BatchApplyPage({super.key, this.service, this.pickPhotos});

  @override
  State<BatchApplyPage> createState() => _BatchApplyPageState();
}

class _BatchApplyPageState extends State<BatchApplyPage> {
  late final BatchApplyService _service = widget.service ?? BatchApplyService();
  List<CustomAdjustment> _saved = [];
  List<FilterPreset> _presets = [];
  List<String> _paths = [];
  List<BatchItemResult> _results = [];
  EditorLook? _copied;
  String _sourceKey = 'copied';
  bool _running = false;
  bool _finished = false;
  double _itemProgress = 0;
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _copied = EditorLookClipboard.value;
    if (_copied == null) _sourceKey = '';
    _loadSources();
  }

  Future<void> _loadSources() async {
    try {
      final saved = await CustomAdjustmentRepository().getAll();
      final custom = await FilterRepositoryImpl().getCustomPresets();
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _presets = [...custom, ...BuiltinPresets.all];
        if (_sourceKey.isEmpty && saved.isNotEmpty) {
          _sourceKey = 'saved:${saved.first.id}';
        }
      });
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Batch apply sources unavailable',
        error.runtimeType,
        stackTrace,
      );
    }
  }

  EditorLook? _selectedLook() {
    if (_sourceKey == 'copied') return _copied;
    if (_sourceKey.startsWith('saved:')) {
      final id = _sourceKey.substring(6);
      for (final adj in _saved) {
        if (adj.id == id) return adj.look ?? EditorLook(params: adj.params);
      }
    }
    return null;
  }

  FilterPreset? _presetOf(EditorLook look) {
    final id = look.presetId;
    if (id == null) return null;
    for (final preset in _presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  Future<void> _pick() async {
    if (_running) return;
    List<String> picked;
    if (widget.pickPhotos != null) {
      picked = await widget.pickPhotos!();
    } else {
      if (!await MediaPermissionService.ensurePhotoAccess()) {
        _message('사진 접근 권한이 필요해요.');
        return;
      }
      final files = await ImagePicker().pickMultiImage();
      picked = files.map((f) => f.path).toList();
    }
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _paths = picked;
      _results = [
        for (final path in picked) BatchItemResult(path, BatchItemStatus.pending)
      ];
      _finished = false;
    });
  }

  Future<void> _start() async {
    final look = _selectedLook();
    if (look == null || _paths.isEmpty || _running) return;
    setState(() {
      _running = true;
      _finished = false;
      _currentIndex = 0;
      _itemProgress = 0;
      _results = [
        for (final path in _paths) BatchItemResult(path, BatchItemStatus.pending)
      ];
    });
    final results = await _service.run(
      paths: _paths,
      look: look,
      preset: _presetOf(look),
      onItem: (index, result) {
        if (!mounted) return;
        setState(() {
          _currentIndex = index;
          _itemProgress = 0;
          _results[index] = result;
        });
      },
      onProgress: (index, value) {
        if (!mounted) return;
        setState(() => _itemProgress = value);
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _finished = true;
      _results = results;
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  int _count(BatchItemStatus status) =>
      _results.where((r) => r.status == status).length;

  @override
  Widget build(BuildContext context) {
    final look = _selectedLook();
    final canStart = look != null && _paths.isNotEmpty && !_running;
    final completed = _count(BatchItemStatus.done) +
        _count(BatchItemStatus.failed) +
        _count(BatchItemStatus.cancelled);
    final overall = _paths.isEmpty
        ? 0.0
        : (completed + (_running ? _itemProgress : 0)) / _paths.length;

    return Scaffold(
      appBar: AppBar(title: const Text('여러 장에 보정 적용')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionTitle('1. 적용할 보정'),
          if (_copied == null && _saved.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '편집 화면에서 보정을 복사하거나 조정을 저장하면 여기에서 고를 수 있어요.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          RadioGroup<String>(
            groupValue: _sourceKey,
            onChanged: (value) {
              if (_running || value == null) return;
              setState(() => _sourceKey = value);
            },
            child: Column(
              children: [
                if (_copied != null)
                  const RadioListTile<String>(
                    value: 'copied',
                    title: Text('방금 복사한 보정'),
                    subtitle: Text('기본 보정·필터·효과'),
                  ),
                for (final adj in _saved)
                  RadioListTile<String>(
                    value: 'saved:${adj.id}',
                    title: Text(adj.name),
                    subtitle: Text(adj.look == null
                        ? '기본 보정값만 저장된 프리셋'
                        : '기본 보정·필터·효과'),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              '크롭, 부분 보정 위치, 지우개, 텍스트, 인물 보정은 사진마다 달라서 일괄 적용에서 제외돼요.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          const _SectionTitle('2. 사진'),
          OutlinedButton.icon(
            onPressed: _running ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_paths.isEmpty ? '사진 여러 장 고르기' : '${_paths.length}장 선택됨 · 다시 고르기'),
          ),
          for (var i = 0; i < _results.length; i++)
            _ResultTile(
              result: _results[i],
              active: _running && i == _currentIndex,
            ),
          const SizedBox(height: 16),
          if (_running || _finished) ...[
            LinearProgressIndicator(value: overall.clamp(0.0, 1.0)),
            const SizedBox(height: 8),
            Text(
              _running
                  ? '$completed/${_paths.length}장 처리 중'
                  : '완료 ${_count(BatchItemStatus.done)}장 · 실패 ${_count(BatchItemStatus.failed)}장'
                      '${_count(BatchItemStatus.cancelled) > 0 ? ' · 취소 ${_count(BatchItemStatus.cancelled)}장' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
          ],
          if (_running)
            OutlinedButton(
              onPressed: _service.cancel,
              child: const Text('중단'),
            )
          else
            FilledButton(
              onPressed: canStart ? _start : null,
              child: Text(_finished ? '다시 적용' : '적용하고 갤러리에 저장'),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      );
}

class _ResultTile extends StatelessWidget {
  final BatchItemResult result;
  final bool active;

  const _ResultTile({required this.result, required this.active});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (result.status) {
      BatchItemStatus.pending => (Icons.schedule_rounded, Colors.grey, '대기'),
      BatchItemStatus.running => (Icons.autorenew_rounded, Colors.blue, '처리 중'),
      BatchItemStatus.done => (Icons.check_circle_rounded, Colors.green, '저장됨'),
      BatchItemStatus.failed => (Icons.error_rounded, Colors.red, '실패'),
      BatchItemStatus.cancelled => (Icons.block_rounded, Colors.grey, '취소'),
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Image.file(
            File(result.path),
            fit: BoxFit.cover,
            cacheWidth: 120,
            errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined),
          ),
        ),
      ),
      title: Text(
        result.path.split(RegExp(r'[\\/]')).last,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: result.message == null
          ? null
          : Text(result.message!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
