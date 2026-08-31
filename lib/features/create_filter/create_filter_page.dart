import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import '../../core/error/error_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';
import '../../data/repositories/filter_repository_impl.dart';
import '../../domain/models/adjust_params.dart';
import '../../domain/models/filter_preset.dart';
import '../../domain/models/filter_recipe.dart';
import '../../domain/repositories/filter_repository.dart';
import '../../engine/reference_coverage_router.dart';
import '../../monetization/feature_flags_service.dart';
import '../../monetization/fullscreen_ad_service.dart';
import 'create_filter_reference_analyzer.dart';
import 'create_filter_services.dart';

part 'create_filter_result_widgets.dart';
part 'create_filter_stage_widgets.dart';

const bool kPhotoFilterGenerationEnabled = true;
const bool kPhotoFilterGenerationIsBeta = true;

enum _CreateFilterMode { style, pair }

enum _PairSlot { before, after }

// ── Stage label helper ────────────────────────────────────

String _stageLabel(String stage, String lang) {
  const cleanKo = {
    'style_loading': '이미지를 불러오는 중...',
    'style_analyze': '스타일을 분석하는 중...',
    'lab_analyze': '색 공간을 분석하는 중...',
    'lut_build': 'LUT를 생성하는 중...',
    'model_inference': 'AI 모델을 실행하는 중...',
    'pair_loading': '보정 전·후 사진을 불러오는 중...',
    'pair_analyze': '편집 차이를 분석하는 중...',
    'global_fit': '전역 변환을 맞추는 중...',
    'residual_fit': '잔차 LUT를 맞추는 중...',
    'lut_encode': 'LUT를 인코딩하는 중...',
    'thumbnail': '썸네일을 생성하는 중...',
    'saving': '저장하는 중...',
  };
  const cleanEn = {
    'style_loading': 'Loading image...',
    'style_analyze': 'Analyzing style...',
    'lab_analyze': 'Analyzing colors...',
    'lut_build': 'Building LUT...',
    'model_inference': 'Running AI model...',
    'pair_loading': 'Loading before/after...',
    'pair_analyze': 'Analyzing edit pair...',
    'global_fit': 'Fitting global transform...',
    'residual_fit': 'Fitting residual LUT...',
    'lut_encode': 'Encoding LUT...',
    'thumbnail': 'Generating thumbnail...',
    'saving': 'Saving...',
  };
  final clean = lang == 'en' ? cleanEn[stage] : cleanKo[stage];
  if (clean != null) return clean;

  const ko = {
    'style_loading': '이미지 불러오는 중...',
    'style_analyze': '스타일 분석 중...',
    'lab_analyze': '색공간 분석 중...',
    'lut_build': 'LUT 생성 중...',
    'model_inference': 'AI 추론 중...',
    'pair_loading': '보정 전·후 사진 불러오는 중...',
    'pair_analyze': '편집 쌍 분석 중...',
    'global_fit': '전역 변환 맞추는 중...',
    'residual_fit': '잔차 LUT 맞추는 중...',
    'lut_encode': 'LUT 인코딩 중...',
    'thumbnail': '썸네일 생성 중...',
    'saving': '저장 중...',
  };
  const en = {
    'style_loading': 'Loading image...',
    'style_analyze': 'Analyzing style...',
    'lab_analyze': 'Analyzing colors...',
    'lut_build': 'Building LUT...',
    'model_inference': 'Running AI model...',
    'pair_loading': 'Loading before/after...',
    'pair_analyze': 'Analyzing edit pair...',
    'global_fit': 'Fitting global transform...',
    'residual_fit': 'Fitting residual LUT...',
    'lut_encode': 'Encoding LUT...',
    'thumbnail': 'Generating thumbnail...',
    'saving': 'Saving...',
  };
  return (lang == 'en' ? en[stage] : ko[stage]) ?? stage;
}

// ── Style-tag → suggested name ────────────────────────────

String _suggestName(List<String> tags, String lang) {
  if (tags.isEmpty) return '';
  final key = tags.take(2).join(' ');
  const cleanKo = {
    'Dark': '딥 무드',
    'Bright': '라이트 톤',
    'Natural': '내추럴 톤',
    'Warm': '웜 필름',
    'Cool': '쿨 브리즈',
    'Ocean': '오션 블루',
    'Blue': '블루 톤',
    'Green': '그린 무드',
    'Vintage': '빈티지 필름',
    'Moody': '무디 톤',
    'Dark Moody': '다크 무드',
    'Dark Cool': '딥 블루',
    'Dark Warm': '앤틱 브라운',
    'Dark Ocean': '딥 오션',
    'Bright Warm': '선셋 골드',
    'Bright Cool': '클리어 스카이',
    'Bright Ocean': '서머 시안',
    'Warm Vintage': '필름 빈티지',
    'Warm Moody': '트와일라잇',
    'Cool Ocean': '아쿠아 드림',
    'Ocean Green': '포레스트 톤',
    'Vintage Warm': '레트로 앰버',
  };
  const cleanEn = {
    'Dark': 'Deep Mood',
    'Bright': 'Light Tone',
    'Natural': 'Natural Tone',
    'Warm': 'Warm Film',
    'Cool': 'Cool Breeze',
    'Ocean': 'Ocean Blue',
    'Blue': 'Blue Tone',
    'Green': 'Green Mood',
    'Vintage': 'Vintage Film',
    'Moody': 'Moody Tone',
    'Dark Moody': 'Dark Mood',
    'Dark Cool': 'Deep Blue',
    'Dark Warm': 'Antique Brown',
    'Dark Ocean': 'Deep Ocean',
    'Bright Warm': 'Sunset Gold',
    'Bright Cool': 'Clear Sky',
    'Bright Ocean': 'Summer Cyan',
    'Warm Vintage': 'Film Vignette',
    'Warm Moody': 'Twilight',
    'Cool Ocean': 'Aqua Dream',
    'Ocean Green': 'Forest Tone',
    'Vintage Warm': 'Retro Amber',
  };
  final cleanMap = lang == 'en' ? cleanEn : cleanKo;
  final cleanName = cleanMap[key] ?? cleanMap[tags.first];
  if (cleanName != null) return cleanName;

  const ko = {
    'Dark Moody': '다크 무드',
    'Dark Cool': '딥 블루',
    'Dark Warm': '앤틱 브라운',
    'Dark Ocean': '딥 오션',
    'Bright Warm': '선셋 골드',
    'Bright Cool': '클리어 스카이',
    'Bright Ocean': '서머 시안',
    'Warm Vintage': '필름 비네트',
    'Warm Moody': '황혼의 빛',
    'Cool Ocean': '아쿠아 드림',
    'Ocean Green': '포레스트 토닝',
    'Vintage Warm': '레트로 앰버',
  };
  const en = {
    'Dark Moody': 'Dark Mood',
    'Dark Cool': 'Deep Blue',
    'Dark Warm': 'Antique Brown',
    'Dark Ocean': 'Deep Ocean',
    'Bright Warm': 'Sunset Gold',
    'Bright Cool': 'Clear Sky',
    'Bright Ocean': 'Summer Cyan',
    'Warm Vintage': 'Film Vignette',
    'Warm Moody': 'Twilight',
    'Cool Ocean': 'Aqua Dream',
    'Ocean Green': 'Forest Tone',
    'Vintage Warm': 'Retro Amber',
  };
  final map = lang == 'en' ? en : ko;
  return map[key] ?? map[tags.first] ?? '';
}

// ─────────────────────────────────────────────────────────

class CreateFilterPage extends StatefulWidget {
  final CreateFilterGenerator? generator;
  final RecentPhotoSource? recentPhotoSource;
  final FilterRepository? repository;
  final CreateFilterPreviewRenderer? previewRenderer;
  final CreateFilterReferenceAnalyzer? referenceAnalyzer;
  final bool loadAdServices;

  const CreateFilterPage({
    super.key,
    this.generator,
    this.recentPhotoSource,
    this.repository,
    this.previewRenderer,
    this.referenceAnalyzer,
    this.loadAdServices = true,
  });

  @override
  State<CreateFilterPage> createState() => _CreateFilterPageState();
}

class _CreateFilterPageState extends State<CreateFilterPage> {
  _CreateFilterMode _mode = _CreateFilterMode.style;
  List<String> _styleImagePaths = [];
  List<RecentPhotoItem> _recentPhotos = [];
  final Map<String, String> _resolvedRecentPhotoPaths = {};
  final Set<String> _resolvingRecentPhotoIds = {};
  bool _loadingRecentPhotos = true;
  bool _loadingMoreRecentPhotos = false;
  RecentPhotoLoadState _recentPhotoState = RecentPhotoLoadState.ready;
  bool _hasMoreRecentPhotos = false;
  int _recentPhotoPage = 0;
  int _unavailableRecentPhotoCount = 0;
  String? _beforeImagePath;
  String? _afterImagePath;
  _PairSlot _activePairSlot = _PairSlot.before;
  bool _generating = false;
  double _progress = 0.0;
  String _stageMsg = '';
  List<Color> _palette = [];
  List<String> _tags = [];

  final _nameCtrl = TextEditingController();
  FullScreenAdService? _adService;
  late final CreateFilterGenerator _generator;
  late final RecentPhotoSource _recentPhotoSource;
  late final FilterRepository _repository;
  late final CreateFilterReferenceAnalyzer _referenceAnalyzer;
  late final CreateFilterCommitTransaction _commitTransaction;
  bool _cancelRequested = false;
  int _generationRunId = 0;
  int _analysisRunId = 0;

  @override
  void initState() {
    super.initState();
    _generator = widget.generator ?? IsolateCreateFilterGenerator();
    _recentPhotoSource =
        widget.recentPhotoSource ?? PhotoManagerRecentPhotoSource();
    _repository = widget.repository ?? FilterRepositoryImpl();
    _referenceAnalyzer =
        widget.referenceAnalyzer ?? const FileCreateFilterReferenceAnalyzer();
    _commitTransaction = CreateFilterCommitTransaction(
      repository: _repository,
      previewRenderer:
          widget.previewRenderer ?? FileCreateFilterPreviewRenderer(),
    );
    if (widget.loadAdServices) _loadServices();
    _loadRecentPhotos();
  }

  Future<void> _loadServices() async {
    final flags = await FeatureFlagsService.create();
    if (mounted) setState(() => _adService = FullScreenAdService(flags));
  }

  @override
  void dispose() {
    _analysisRunId++;
    _nameCtrl.dispose();
    unawaited(_generator.cancel());
    super.dispose();
  }

  void _setMode(_CreateFilterMode mode) {
    if (_mode == mode) return;
    _analysisRunId++;
    setState(() {
      _mode = mode;
      _styleImagePaths = [];
      _beforeImagePath = null;
      _afterImagePath = null;
      _activePairSlot = _PairSlot.before;
      _resolvedRecentPhotoPaths.clear();
      _palette = [];
      _tags = [];
    });
  }

  Future<void> _loadRecentPhotos({bool reset = true}) async {
    if (reset) {
      setState(() {
        _loadingRecentPhotos = true;
        _loadingMoreRecentPhotos = false;
        _recentPhotoPage = 0;
      });
    } else {
      if (_loadingRecentPhotos ||
          _loadingMoreRecentPhotos ||
          !_hasMoreRecentPhotos) {
        return;
      }
      setState(() => _loadingMoreRecentPhotos = true);
    }

    final requestedPage = reset ? 0 : _recentPhotoPage + 1;
    RecentPhotoPage result;
    try {
      result = await _recentPhotoSource.loadRecent(page: requestedPage);
    } catch (error) {
      result = RecentPhotoPage(
        state: RecentPhotoLoadState.error,
        page: requestedPage,
        errorMessage: error.toString(),
      );
    }
    if (!mounted) return;

    setState(() {
      if (reset) {
        _recentPhotos = result.items;
      } else if (result.state != RecentPhotoLoadState.error) {
        final itemsById = {
          for (final item in _recentPhotos) item.assetId: item,
          for (final item in result.items) item.assetId: item,
        };
        _recentPhotos = itemsById.values.toList(growable: false);
      }
      if (reset || result.state != RecentPhotoLoadState.error) {
        _recentPhotoState = result.state;
        _hasMoreRecentPhotos = result.hasMore;
        _recentPhotoPage = result.page;
        _unavailableRecentPhotoCount = result.unavailableCount;
      }
      _loadingRecentPhotos = false;
      _loadingMoreRecentPhotos = false;
    });

    if (!reset && result.state == RecentPhotoLoadState.error) {
      _showSnack('최근 사진을 더 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _selectRecentPhoto(RecentPhotoItem item) async {
    if (_generating || _resolvingRecentPhotoIds.contains(item.assetId)) return;
    var path = _resolvedRecentPhotoPaths[item.assetId];
    if (path == null) {
      setState(() => _resolvingRecentPhotoIds.add(item.assetId));
      try {
        path = await _recentPhotoSource.resolveOriginalPath(item.assetId);
      } catch (error, stackTrace) {
        ErrorLogger.log(
          'Recent photo original could not be resolved',
          error.runtimeType,
          stackTrace,
        );
        path = null;
      } finally {
        if (mounted) {
          setState(() => _resolvingRecentPhotoIds.remove(item.assetId));
        }
      }
      if (!mounted) return;
      if (path == null) {
        _showSnack('이 사진의 원본을 불러오지 못했어요. iCloud 다운로드 상태를 확인해 주세요.');
        return;
      }
      _resolvedRecentPhotoPaths[item.assetId] = path;
    }
    _selectRecentPhotoPath(path);
  }

  void _selectRecentPhotoPath(String path) {
    if (_generating) return;
    hapticLight();
    if (_mode == _CreateFilterMode.style) {
      final selected = List<String>.from(_styleImagePaths);
      if (selected.contains(path)) {
        selected.remove(path);
      } else if (selected.length < 5) {
        selected.add(path);
      } else {
        _showSnack('참조 사진은 최대 5장까지 선택할 수 있어요.');
        return;
      }
      setState(() {
        _styleImagePaths = selected;
        _palette = [];
        _tags = [];
      });
      if (selected.isNotEmpty) _analyzeStyles(selected);
      return;
    }

    setState(() {
      if (_activePairSlot == _PairSlot.before) {
        _beforeImagePath = path;
        _activePairSlot = _PairSlot.after;
      } else {
        _afterImagePath = path;
      }
      _palette = [];
      _tags = [];
    });
    _analyzeStyles([_afterImagePath ?? _beforeImagePath!]);
  }

  Future<void> _pickReferenceImage() async {
    hapticMedium();
    if (_mode == _CreateFilterMode.style) {
      final xFiles = await ImagePicker().pickMultiImage();
      if (xFiles.isEmpty || !mounted) return;

      final selectedPaths = xFiles.take(5).map((x) => x.path).toList();
      setState(() {
        _styleImagePaths = selectedPaths;
        _resolvedRecentPhotoPaths.clear();
        _palette = [];
        _tags = [];
      });
      _analyzeStyles(selectedPaths);
      return;
    }

    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;

    setState(() {
      _resolvedRecentPhotoPaths.clear();
      if (_activePairSlot == _PairSlot.before) {
        _beforeImagePath = xFile.path;
        _activePairSlot = _PairSlot.after;
      } else {
        _afterImagePath = xFile.path;
      }
      _palette = [];
      _tags = [];
    });
    _analyzeStyles([
      _afterImagePath ?? _beforeImagePath ?? xFile.path,
    ]);
  }

  void _selectPairSlot(_PairSlot slot) {
    if (_generating) return;
    setState(() => _activePairSlot = slot);
  }

  void _clearPairSlot(_PairSlot slot) {
    if (_generating) return;
    _analysisRunId++;
    setState(() {
      final removedPath =
          slot == _PairSlot.before ? _beforeImagePath : _afterImagePath;
      if (slot == _PairSlot.before) {
        _beforeImagePath = null;
      } else {
        _afterImagePath = null;
      }
      _activePairSlot = slot;
      if (removedPath != null) {
        _resolvedRecentPhotoPaths.removeWhere(
          (_, path) => path == removedPath,
        );
      }
      _palette = [];
      _tags = [];
    });
  }

  Future<void> _analyzeStyles(List<String> paths) async {
    final runId = ++_analysisRunId;
    if (paths.isEmpty) return;
    try {
      final analysis =
          await _referenceAnalyzer.analyze(List.unmodifiable(paths));
      if (mounted && runId == _analysisRunId) {
        setState(() {
          _palette = analysis.palette;
          _tags = analysis.tags;
        });
        if (_nameCtrl.text.isEmpty) {
          final lang = localeNotifier.value.languageCode;
          final suggestion = _suggestName(analysis.tags, lang);
          if (suggestion.isNotEmpty) {
            _nameCtrl.text = suggestion;
          }
        }
      }
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Filter reference analysis failed; keeping manual naming available',
        error.runtimeType,
        stackTrace,
      );
    }
  }

  Future<void> _generate() async {
    if (_mode == _CreateFilterMode.style && _styleImagePaths.isEmpty) {
      _showSnack(S.get('create.need_image'));
      return;
    }
    if (_mode == _CreateFilterMode.pair &&
        (_beforeImagePath == null || _afterImagePath == null)) {
      _showSnack(S.get('create.need_pair'));
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack(S.get('create.need_name'));
      return;
    }
    if (!kPhotoFilterGenerationEnabled) {
      _showSnack(S.get('create.deferred'));
      return;
    }

    if (_adService != null) {
      await _adService!.show(FullScreenAdTrigger.createFilter);
    }

    setState(() {
      _generating = true;
      _cancelRequested = false;
      _progress = 0.05;
      _stageMsg = _stageLabel(
        _mode == _CreateFilterMode.style ? 'style_loading' : 'pair_loading',
        localeNotifier.value.languageCode,
      );
    });
    hapticHeavy();

    final runId = ++_generationRunId;
    Map<String, dynamic>? generatedResult;
    FilterPreset? pendingPreset;
    var committed = false;
    var commitTransactionStarted = false;

    try {
      final base = await getApplicationDocumentsDirectory();
      void onProgress(String stage, double progress) {
        if (!mounted || runId != _generationRunId || _cancelRequested) return;
        setState(() {
          _progress = progress;
          _stageMsg = _stageLabel(
            stage,
            localeNotifier.value.languageCode,
          );
        });
      }

      final result = _mode == _CreateFilterMode.style
          ? await _generator.generateStyle(
              List<String>.from(_styleImagePaths),
              basePath: base.path,
              onProgress: onProgress,
            )
          : await _generator.generatePair(
              _beforeImagePath!,
              _afterImagePath!,
              basePath: base.path,
              onProgress: onProgress,
            );
      generatedResult = result;
      if (!mounted || _cancelRequested || runId != _generationRunId) {
        throw const CreateFilterCancelledException();
      }

      setState(() => _progress = 1.0);

      final fusion = result['referenceFusion'];
      final fusionInfo = fusion is Map
          ? Map<String, dynamic>.from(fusion)
          : const <String, dynamic>{};
      final fusionConfidence =
          (fusionInfo['confidence'] as num?)?.toDouble() ?? 1.0;
      final excludedReferenceCount =
          (fusionInfo['excludedReferenceCount'] as num?)?.toInt() ?? 0;
      final fitReport = result['fitReport'];
      final fitInfo = fitReport is Map
          ? Map<String, dynamic>.from(fitReport)
          : const <String, dynamic>{};
      final referenceGuidance = _buildReferenceGuidance(
        fitInfo: fitInfo,
        mode: _mode,
        excludedReferenceCount: excludedReferenceCount,
        fusionConfidence: fusionConfidence,
      );

      final now = DateTime.now();
      final defaultParamsMap = result['defaultParams'] as Map<String, dynamic>;
      final recipeJson = result['filterRecipe'];
      final recipe = recipeJson is Map
          ? FilterRecipe.fromJson(Map<String, dynamic>.from(recipeJson))
          : FilterRecipe.legacy(hasLut: true, presetType: 'custom');
      final preset = FilterPreset(
        id: result['presetId'] as String,
        name: name,
        type: FilterPresetType.custom,
        lutPath: result['lutPath'] as String,
        params: AdjustParams.fromJson(defaultParamsMap),
        defaultIntensity: 0.8,
        thumbnailPath: result['thumbnailPath'] as String,
        createdAt: now,
        updatedAt: now,
        recipe: recipe,
      );
      pendingPreset = preset;

      final previewSourcePath = _mode == _CreateFilterMode.pair
          ? _beforeImagePath
          : (_styleImagePaths.isEmpty ? null : _styleImagePaths.first);
      commitTransactionStarted = true;
      final committedResult = await _commitTransaction.commit(
        preset: preset,
        sourcePath: previewSourcePath,
        isCancelled: () =>
            !mounted || _cancelRequested || runId != _generationRunId,
      );
      committed = true;
      hapticMedium();

      if (mounted) {
        _showSuccessSheet(
          preset,
          sourcePath: previewSourcePath,
          sampleAfterPath: committedResult.previewPath,
          referenceGuidance: referenceGuidance,
        );
      }
    } catch (e) {
      if (!committed && pendingPreset != null && !commitTransactionStarted) {
        await _commitTransaction.rollback(pendingPreset);
      } else if (!committed && generatedResult != null) {
        await _cleanupUncommittedResult(generatedResult);
      }
      if (mounted) {
        if (e is CreateFilterCancelledException || _cancelRequested) {
          _showSnack(localeNotifier.value.languageCode == 'en'
              ? 'Filter creation cancelled.'
              : '필터 생성을 취소했어요.');
        } else if (e is CreateFilterPreviewException) {
          _showSnack(localeNotifier.value.languageCode == 'en'
              ? 'The preview failed, so the filter was not saved.'
              : '미리보기를 만들지 못해 필터를 저장하지 않았어요.');
        } else if (e is LowReferenceCoverageException) {
          _showLowCoverageSnack();
        } else {
          _showSnack(S.get('create.error'));
        }
      }
    } finally {
      if (mounted && runId == _generationRunId) {
        setState(() => _generating = false);
      }
    }
  }

  Future<void> _cancelGeneration() async {
    if (!_generating || _cancelRequested) return;
    setState(() {
      _cancelRequested = true;
      _stageMsg = localeNotifier.value.languageCode == 'en'
          ? 'Cancelling...'
          : '취소하는 중...';
    });
    await _generator.cancel();
  }

  Future<void> _cleanupUncommittedResult(Map<String, dynamic> result) async {
    final lutPath = result['lutPath'] as String?;
    if (lutPath == null) return;
    try {
      final directory = File(lutPath).parent;
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Uncommitted generated-filter cleanup failed',
        error.runtimeType,
        stackTrace,
      );
    }
  }

  String? _buildReferenceGuidance({
    required Map<String, dynamic> fitInfo,
    required _CreateFilterMode mode,
    required int excludedReferenceCount,
    required double fusionConfidence,
  }) {
    final isEnglish = localeNotifier.value.languageCode == 'en';
    if (mode == _CreateFilterMode.style) {
      final needsReferenceGuidance =
          excludedReferenceCount > 0 || fusionConfidence < 0.70;
      if (!needsReferenceGuidance) return null;
      return isEnglish
          ? 'Some reference photos had different color looks, so the filter was softened. Choose photos with similar lighting and colors for a closer match.'
          : '참조 사진의 색감 차이가 커서 필터 강도를 낮췄어요. 비슷한 조명과 색감의 사진으로 다시 선택하면 더 정확해집니다.';
    }

    final fitMetrics = fitInfo['fitMetrics'];
    final fitInfoMap = fitMetrics is Map
        ? Map<String, dynamic>.from(fitMetrics)
        : const <String, dynamic>{};
    final lutRmse = (fitInfoMap['lutRMSE'] as num?)?.toDouble() ?? 0.0;
    final fallbackReason = fitInfo['fallbackReason'] as String?;
    final needsGuidance = fallbackReason != null || lutRmse > 0.04;
    if (!needsGuidance) return null;
    return isEnglish
        ? 'The before/after pair was only a rough fit. Try a closer crop, fewer local edits, or more consistent exposure.'
        : '보정 전·후 사진의 차이가 거칠게만 맞아서 필터를 보수적으로 만들었어요. 더 비슷한 구도, 더 적은 부분 보정, 비슷한 노출의 사진으로 다시 시도해 보세요.';
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.oceanFoam,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showLowCoverageSnack() {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(S.get('create.low_coverage')),
        backgroundColor: AppColors.oceanFoam,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: S.get('create.choose_another'),
          onPressed: _pickReferenceImage,
        ),
      ),
    );
  }

  void _showSuccessSheet(
    FilterPreset preset, {
    String? sourcePath,
    String? sampleAfterPath,
    String? referenceGuidance,
  }) {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuccessSheet(
        preset: preset,
        sourcePath: sourcePath,
        sampleAfterPath: sampleAfterPath,
        referenceGuidance: referenceGuidance,
        onReselect: referenceGuidance == null
            ? null
            : () => Navigator.of(context).pop('reselect'),
        onEditNow: () async {
          Navigator.of(context).pop('apply');
        },
      ),
    ).then((action) async {
      try {
        if (!mounted) return;
        if (action == 'reselect') return;
        if (action == 'apply') {
          final xFile =
              await ImagePicker().pickImage(source: ImageSource.gallery);
          if (!mounted || xFile == null) return;
          context.pushNamed('editor', extra: {
            'imagePath': xFile.path,
            'presetId': preset.id,
          });
          return;
        }
        context.pop();
      } finally {
        await CreateFilterCommitTransaction.deleteFileIfPresent(
          sampleAfterPath,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (_, __, ___) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final isPairMode = _mode == _CreateFilterMode.pair;
    final stagePaths = isPairMode
        ? [
            if (_beforeImagePath != null) _beforeImagePath!,
            if (_afterImagePath != null) _afterImagePath!,
          ]
        : _styleImagePaths;
    final selectedRecentAssetIds = <String>[];
    for (final path in stagePaths) {
      for (final entry in _resolvedRecentPhotoPaths.entries) {
        if (entry.value == path) {
          selectedRecentAssetIds.add(entry.key);
          break;
        }
      }
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF5),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF7FFF9),
                    Color(0xFFE8F5EC),
                    Color(0xFFF7F1E8),
                  ],
                  stops: [0, 0.58, 1],
                ),
              ),
            ),
          ),
          Positioned(
            top: 80,
            right: -90,
            child: IgnorePointer(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF92D5A7).withValues(alpha: 0.22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x3392D5A7),
                      blurRadius: 80,
                      spreadRadius: 25,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 420,
            left: -110,
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFD9A8).withValues(alpha: 0.2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33FFD9A8),
                      blurRadius: 70,
                      spreadRadius: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Column(
            children: [
              _Header(onBack: context.pop),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    _palette.isNotEmpty ? 390 : 280,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ModeToggle(
                        mode: _mode,
                        onChanged: _setMode,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isPairMode
                            ? S.get('create.heading_pair')
                            : S.get('create.heading'),
                        style: const TextStyle(
                          fontFamily: 'Domine',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPairMode
                            ? S.get('create.subheading_pair')
                            : S.get('create.subheading'),
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (isPairMode)
                        _PairImageStage(
                          beforePath: _beforeImagePath,
                          afterPath: _afterImagePath,
                          activeSlot: _activePairSlot,
                          generating: _generating,
                          onSelectSlot: _selectPairSlot,
                          onClearSlot: _clearPairSlot,
                          onPickImage: _pickReferenceImage,
                        )
                      else
                        _ImageStage(
                          imagePaths: stagePaths,
                          recentPhotos: _recentPhotos,
                          generating: _generating,
                          pairMode: false,
                          onTap: _pickReferenceImage,
                        ),
                      const SizedBox(height: 18),
                      _RecentPhotoStrip(
                        items: _recentPhotos,
                        loading: _loadingRecentPhotos,
                        loadingMore: _loadingMoreRecentPhotos,
                        state: _recentPhotoState,
                        hasMore: _hasMoreRecentPhotos,
                        unavailableCount: _unavailableRecentPhotoCount,
                        selectedAssetIds: selectedRecentAssetIds,
                        resolvingAssetIds: _resolvingRecentPhotoIds,
                        onSelect: _selectRecentPhoto,
                        onRetry: _loadRecentPhotos,
                        onLoadMore: () => _loadRecentPhotos(reset: false),
                        onOpenPicker: _pickReferenceImage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ControlPanel(
              nameCtrl: _nameCtrl,
              generating: _generating,
              progress: _progress,
              stageMsg: _stageMsg,
              palette: _palette,
              tags: _tags,
              pickLabel: isPairMode
                  ? S.get('create.btn_select')
                  : S.get('create.btn_image'),
              onPick: _pickReferenceImage,
              onGenerate: _generate,
              onCancel: _cancelGeneration,
            ),
          ),
        ],
      ),
    );
  }
}
