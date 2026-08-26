import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import '../../core/error/error_handler.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';
import '../../core/services/media_permission_service.dart';
import '../../data/repositories/filter_repository_impl.dart';
import '../../domain/models/adjust_params.dart';
import '../../domain/models/filter_preset.dart';
import '../../domain/models/filter_recipe.dart';
import '../../domain/repositories/filter_repository.dart';
import '../../engine/style_analyzer.dart';
import '../../monetization/feature_flags_service.dart';
import '../../monetization/fullscreen_ad_service.dart';
import 'create_filter_services.dart';

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
    'pair_loading': 'before/after를 불러오는 중...',
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
    'pair_loading': 'before/after 불러오는 중...',
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
  final bool loadAdServices;

  const CreateFilterPage({
    super.key,
    this.generator,
    this.recentPhotoSource,
    this.repository,
    this.previewRenderer,
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
  late final CreateFilterCommitTransaction _commitTransaction;
  bool _cancelRequested = false;
  int _generationRunId = 0;

  @override
  void initState() {
    super.initState();
    _generator = widget.generator ?? IsolateCreateFilterGenerator();
    _recentPhotoSource =
        widget.recentPhotoSource ?? PhotoManagerRecentPhotoSource();
    _repository = widget.repository ?? FilterRepositoryImpl();
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
    _nameCtrl.dispose();
    unawaited(_generator.cancel());
    super.dispose();
  }

  void _setMode(_CreateFilterMode mode) {
    if (_mode == mode) return;
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
    if (!await MediaPermissionService.ensurePhotoAccess()) {
      _showSnack(S.get('permission.photos_denied'));
      return;
    }

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
    if (paths.isEmpty) return;
    try {
      final images = <img.Image>[];
      for (final path in paths) {
        final bytes = await File(path).readAsBytes();
        final image = img.decodeImage(bytes);
        if (image != null) {
          images.add(image);
        }
      }
      if (images.isEmpty || !mounted) return;

      final palette = extractPalette(images.first);

      final profiles =
          images.map((image) => StyleAnalyzer.analyze(image)).toList();
      final fusedProfile = StyleAnalyzer.fuseProfiles(profiles);
      final tags = deriveStyleTags(fusedProfile);

      if (mounted) {
        setState(() {
          _palette = palette;
          _tags = tags;
        });
        if (_nameCtrl.text.isEmpty) {
          final lang = localeNotifier.value.languageCode;
          final suggestion = _suggestName(tags, lang);
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
        : 'Before/After 쌍이 거칠게만 맞아서 필터가 보수적으로 만들어졌어요. 더 비슷한 구도, 더 적은 로컬 보정, 비슷한 노출의 사진으로 다시 시도해 보세요.';
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
          if (!await MediaPermissionService.ensurePhotoAccess()) {
            _showSnack(S.get('permission.photos_denied'));
            return;
          }
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
              const _Header(),
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

// ─────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              key: const ValueKey('create-filter-glass-header'),
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.78),
                    const Color(0xFFDDF1E3).withValues(alpha: 0.66),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.88),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16032111),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.pop(),
                    icon: Icon(backIcon(), size: 21),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.52),
                      foregroundColor: AppColors.oceanFoam,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.oceanFoam,
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Memoria',
                    style: TextStyle(
                      fontFamily: 'Domine',
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: AppColors.oceanFoam,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFBDE3C7).withValues(alpha: 0.52),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      kPhotoFilterGenerationIsBeta ? 'CREATE · BETA' : 'CREATE',
                      style: TextStyle(
                        color: AppColors.oceanFoam,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final _CreateFilterMode mode;
  final ValueChanged<_CreateFilterMode> onChanged;

  const _ModeToggle({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isPair = mode == _CreateFilterMode.pair;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          key: const ValueKey('create-filter-glass-mode-toggle'),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ToggleChip(
                  icon: Icons.auto_awesome_rounded,
                  label: S.get('create.mode_style'),
                  caption: S.get('create.mode_style_hint'),
                  selected: !isPair,
                  onTap: () => onChanged(_CreateFilterMode.style),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ToggleChip(
                  icon: Icons.compare_rounded,
                  label: S.get('create.mode_pair'),
                  caption: S.get('create.mode_pair_hint'),
                  selected: isPair,
                  onTap: () => onChanged(_CreateFilterMode.pair),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.icon,
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.oceanFoam : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.oceanFoam : AppColors.cloudMist,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.16)
                      : AppColors.oceanFoam.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : AppColors.oceanFoam,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.72)
                            : AppColors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PairImageStage extends StatelessWidget {
  final String? beforePath;
  final String? afterPath;
  final _PairSlot activeSlot;
  final bool generating;
  final ValueChanged<_PairSlot> onSelectSlot;
  final ValueChanged<_PairSlot> onClearSlot;
  final VoidCallback onPickImage;

  const _PairImageStage({
    required this.beforePath,
    required this.afterPath,
    required this.activeSlot,
    required this.generating,
    required this.onSelectSlot,
    required this.onClearSlot,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: _PairImageSlot(
                  key: const ValueKey('pair-slot-before'),
                  label: S.get('create.before'),
                  imagePath: beforePath,
                  selected: activeSlot == _PairSlot.before,
                  enabled: !generating,
                  onTap: () {
                    onSelectSlot(_PairSlot.before);
                    onPickImage();
                  },
                  onClear: () => onClearSlot(_PairSlot.before),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PairImageSlot(
                  key: const ValueKey('pair-slot-after'),
                  label: S.get('create.after'),
                  imagePath: afterPath,
                  selected: activeSlot == _PairSlot.after,
                  enabled: !generating,
                  onTap: () {
                    onSelectSlot(_PairSlot.after);
                    onPickImage();
                  },
                  onClear: () => onClearSlot(_PairSlot.after),
                ),
              ),
            ],
          ),
          if (!generating)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: FilledButton.icon(
                  key: const ValueKey('pair-stage-picker'),
                  onPressed: onPickImage,
                  icon:
                      const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: Text(S.get('create.btn_image')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.oceanFoam,
                    foregroundColor: Colors.white,
                    elevation: 5,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PairImageSlot extends StatelessWidget {
  final String label;
  final String? imagePath;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _PairImageSlot({
    super.key,
    required this.label,
    required this.imagePath,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cloudVeil,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? AppColors.oceanFoam : AppColors.cloudMist,
              width: selected ? 3 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imagePath != null)
                Image.file(
                  File(imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined),
                  ),
                )
              else
                const Center(
                  child: Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 42,
                    color: AppColors.textTertiary,
                  ),
                ),
              Positioned(
                left: 10,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.oceanFoam
                        : AppColors.cloudWhite.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.white : AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              if (imagePath != null && enabled)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    key: ValueKey('pair-slot-clear-${label.toLowerCase()}'),
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.overlay40,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageStage extends StatelessWidget {
  final List<String> imagePaths;
  final List<RecentPhotoItem> recentPhotos;
  final bool generating;
  final bool pairMode;
  final VoidCallback onTap;

  const _ImageStage({
    required this.imagePaths,
    required this.recentPhotos,
    required this.generating,
    required this.pairMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.cloudVeil,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F032111),
                blurRadius: 30,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imagePaths.isNotEmpty)
                  _buildCollage(imagePaths)
                else
                  _RecentPhotoStageBackground(items: recentPhotos),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x55000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                        color: generating
                            ? AppColors.cloudWhite.withValues(alpha: 0.96)
                            : AppColors.cloudWhite.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.cloudMist),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (generating) ...[
                            Text(
                              S.get('create.analyzing'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ] else ...[
                            Icon(
                              imagePaths.isEmpty
                                  ? Icons.add_photo_alternate_outlined
                                  : Icons.compare_rounded,
                              color: AppColors.oceanFoam,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              pairMode
                                  ? (imagePaths.isEmpty
                                      ? S.get('create.pair_select')
                                      : imagePaths.length == 1
                                          ? S.get('create.before')
                                          : S.get('create.pair_ready'))
                                  : (imagePaths.isEmpty
                                      ? S.get('create.select')
                                      : '${S.get('create.ready')} (${imagePaths.length})'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2.0,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (!generating && imagePaths.isEmpty)
                  Positioned.fill(
                    child: Center(
                      child: FilledButton.icon(
                        key: const ValueKey('style-stage-picker'),
                        onPressed: onTap,
                        icon: const Icon(Icons.add_photo_alternate_outlined,
                            size: 19),
                        label: Text(S.get('create.btn_image')),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.oceanFoam,
                          foregroundColor: Colors.white,
                          elevation: 5,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 17, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                            side: const BorderSide(
                                color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollage(List<String> paths) {
    if (paths.length == 1) {
      return Image.file(File(paths.first), fit: BoxFit.cover);
    }
    if (paths.length == 2) {
      return Row(
        children: [
          Expanded(child: Image.file(File(paths[0]), fit: BoxFit.cover)),
          const VerticalDivider(width: 2, color: AppColors.cloudWhite),
          Expanded(child: Image.file(File(paths[1]), fit: BoxFit.cover)),
        ],
      );
    }
    if (paths.length == 3) {
      return Row(
        children: [
          Expanded(child: Image.file(File(paths[0]), fit: BoxFit.cover)),
          const VerticalDivider(width: 2, color: AppColors.cloudWhite),
          Expanded(
            child: Column(
              children: [
                Expanded(child: Image.file(File(paths[1]), fit: BoxFit.cover)),
                const Divider(height: 2, color: AppColors.cloudWhite),
                Expanded(child: Image.file(File(paths[2]), fit: BoxFit.cover)),
              ],
            ),
          ),
        ],
      );
    }
    if (paths.length == 4) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: Image.file(File(paths[0]), fit: BoxFit.cover)),
                const VerticalDivider(width: 2, color: AppColors.cloudWhite),
                Expanded(child: Image.file(File(paths[1]), fit: BoxFit.cover)),
              ],
            ),
          ),
          const Divider(height: 2, color: AppColors.cloudWhite),
          Expanded(
            child: Row(
              children: [
                Expanded(child: Image.file(File(paths[2]), fit: BoxFit.cover)),
                const VerticalDivider(width: 2, color: AppColors.cloudWhite),
                Expanded(child: Image.file(File(paths[3]), fit: BoxFit.cover)),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: Image.file(File(paths[0]), fit: BoxFit.cover)),
        const VerticalDivider(width: 2, color: AppColors.cloudWhite),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: Image.file(File(paths[1]), fit: BoxFit.cover)),
                    const VerticalDivider(
                        width: 2, color: AppColors.cloudWhite),
                    Expanded(
                        child: Image.file(File(paths[2]), fit: BoxFit.cover)),
                  ],
                ),
              ),
              const Divider(height: 2, color: AppColors.cloudWhite),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: Image.file(File(paths[3]), fit: BoxFit.cover)),
                    const VerticalDivider(
                        width: 2, color: AppColors.cloudWhite),
                    Expanded(
                        child: Image.file(File(paths[4]), fit: BoxFit.cover)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentPhotoStageBackground extends StatelessWidget {
  final List<RecentPhotoItem> items;

  const _RecentPhotoStageBackground({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFCBEBD5),
              const Color(0xFFF9E9D2),
              Colors.white.withValues(alpha: 0.86),
            ],
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.photo_library_outlined,
            size: 58,
            color: AppColors.oceanFoam,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          items.first.thumbnailBytes,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
        if (items.length > 1)
          Positioned(
            right: 14,
            top: 18,
            child: Transform.rotate(
              angle: 0.08,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  items[1].thumbnailBytes,
                  width: 96,
                  height: 126,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        if (items.length > 2)
          Positioned(
            left: 14,
            bottom: 18,
            child: Transform.rotate(
              angle: -0.07,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  items[2].thumbnailBytes,
                  width: 88,
                  height: 112,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentPhotoStrip extends StatelessWidget {
  final List<RecentPhotoItem> items;
  final bool loading;
  final bool loadingMore;
  final RecentPhotoLoadState state;
  final bool hasMore;
  final int unavailableCount;
  final List<String> selectedAssetIds;
  final Set<String> resolvingAssetIds;
  final ValueChanged<RecentPhotoItem> onSelect;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onOpenPicker;

  const _RecentPhotoStrip({
    required this.items,
    required this.loading,
    required this.loadingMore,
    required this.state,
    required this.hasMore,
    required this.unavailableCount,
    required this.selectedAssetIds,
    required this.resolvingAssetIds,
    required this.onSelect,
    required this.onRetry,
    required this.onLoadMore,
    required this.onOpenPicker,
  });

  @override
  Widget build(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    if (loading) {
      return const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (items.isEmpty) {
      final (icon, message, actionLabel, action) = switch (state) {
        RecentPhotoLoadState.denied => (
            Icons.photo_library_outlined,
            isEnglish
                ? 'Photo access is needed to show recent photos.'
                : '최근 사진을 보려면 사진 접근 권한이 필요해요.',
            isEnglish ? 'Choose photo' : '사진 선택',
            onOpenPicker,
          ),
        RecentPhotoLoadState.empty => (
            Icons.photo_outlined,
            isEnglish
                ? 'There are no recent photos to show.'
                : '표시할 최근 사진이 없어요.',
            isEnglish ? 'Choose photo' : '사진 선택',
            onOpenPicker,
          ),
        RecentPhotoLoadState.unavailable => (
            Icons.cloud_off_outlined,
            isEnglish
                ? 'Photo thumbnails are unavailable. Check iCloud and try again.'
                : '사진 미리보기를 불러올 수 없어요. iCloud 상태를 확인해 주세요.',
            isEnglish ? 'Try again' : '다시 시도',
            onRetry,
          ),
        _ => (
            Icons.refresh_rounded,
            isEnglish
                ? 'Recent photos could not be loaded.'
                : '최근 사진을 불러오지 못했어요.',
            isEnglish ? 'Try again' : '다시 시도',
            onRetry,
          ),
      };
      return Container(
        key: const ValueKey('recent-photo-state'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cloudSilk,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cloudVeil),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('recent-photo-state-action'),
              onPressed: action,
              child: Text(actionLabel),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              isEnglish ? 'Recent photos' : '최근 사진',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            if (state == RecentPhotoLoadState.limited) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  isEnglish ? 'Showing photos you allowed' : '허용한 사진만 표시 중',
                  key: const ValueKey('recent-photo-limited-label'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
            if (unavailableCount > 0) ...[
              const SizedBox(width: 8),
              Text(
                isEnglish
                    ? '$unavailableCount unavailable'
                    : '$unavailableCount장 불러오기 실패',
                key: const ValueKey('recent-photo-partial-unavailable'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.accentWarning,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length + (hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              if (index == items.length) {
                return SizedBox(
                  width: 88,
                  child: OutlinedButton(
                    key: const ValueKey('recent-photo-load-more'),
                    onPressed: loadingMore ? null : onLoadMore,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: loadingMore
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isEnglish ? 'More' : '더 보기'),
                  ),
                );
              }
              final item = items[index];
              final selectedIndex = selectedAssetIds.indexOf(item.assetId);
              final selected = selectedIndex >= 0;
              final resolving = resolvingAssetIds.contains(item.assetId);
              return GestureDetector(
                key: ValueKey('recent-photo-$index'),
                onTap: resolving ? null : () => onSelect(item),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        item.thumbnailBytes,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: AppColors.cloudVeil,
                          child: SizedBox.square(
                            dimension: 88,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (resolving)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: AppColors.overlay40,
                          child: Center(
                            child: SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (selected)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.oceanFoam.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.oceanFoam, width: 3),
                          ),
                        ),
                      ),
                    if (selected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          key: ValueKey(
                            'recent-photo-selection-${selectedIndex + 1}',
                          ),
                          width: 25,
                          height: 25,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.oceanFoam,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${selectedIndex + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ControlPanel extends StatelessWidget {
  final TextEditingController nameCtrl;
  final bool generating;
  final double progress;
  final String stageMsg;
  final List<Color> palette;
  final List<String> tags;
  final String pickLabel;
  final VoidCallback onPick;
  final VoidCallback onGenerate;
  final VoidCallback onCancel;

  const _ControlPanel({
    required this.nameCtrl,
    required this.generating,
    required this.progress,
    required this.stageMsg,
    required this.palette,
    required this.tags,
    required this.pickLabel,
    required this.onPick,
    required this.onGenerate,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          key: const ValueKey('create-filter-glass-controls'),
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.86),
                const Color(0xFFDDF2E4).withValues(alpha: 0.76),
                const Color(0xFFFFF5E8).withValues(alpha: 0.72),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.92)),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26032111),
                blurRadius: 38,
                offset: Offset(0, -12),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.cloudVeil,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Analysis summary
                if (!generating && palette.isNotEmpty)
                  _AnalysisSummary(
                    palette: palette,
                    tags: tags,
                  ),
                if (!generating) const SizedBox(height: 18),

                // Progress block (stage label + animated bar)
                if (generating) ...[
                  _StageProgressBar(progress: progress, stageMsg: stageMsg),
                  const SizedBox(height: 18),
                ],

                // Name field
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: S.get('create.name_label'),
                    hintText: S.get('create.name_hint'),
                    prefixIcon: const Icon(Icons.edit_rounded),
                  ),
                ),
                const SizedBox(height: 14),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: generating ? onCancel : onPick,
                        icon: Icon(generating
                            ? Icons.close_rounded
                            : Icons.photo_library_outlined),
                        label: Text(generating
                            ? (localeNotifier.value.languageCode == 'en'
                                ? 'Cancel'
                                : '취소')
                            : pickLabel),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.oceanFoam,
                          side: const BorderSide(color: AppColors.cloudMist),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: generating ? null : onGenerate,
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(generating
                            ? '${(progress * 100).round()}%'
                            : S.get('create.btn_save')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageProgressBar extends StatelessWidget {
  final double progress;
  final String stageMsg;

  const _StageProgressBar({required this.progress, required this.stageMsg});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stageMsg,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.oceanFoam,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            tween: Tween(begin: 0.0, end: progress),
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: AppColors.cloudVeil,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.oceanFoam),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalysisSummary extends StatelessWidget {
  final List<Color> palette;
  final List<String> tags;

  const _AnalysisSummary({required this.palette, required this.tags});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('create-filter-analysis-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10032111),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppColors.oceanFoam),
              const SizedBox(width: 7),
              Text(S.get('create.analysis_done'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  )),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.oceanFoam,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AnalysisGroup(
                  key: const ValueKey('create-filter-palette-group'),
                  label: S.get('create.palette'),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: palette
                        .map((color) => _ColorDot(color: color))
                        .toList(),
                  ),
                ),
              ),
              if (tags.isNotEmpty) ...[
                Container(
                  width: 1,
                  height: 54,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: AppColors.cloudVeil,
                ),
                Expanded(
                  flex: 2,
                  child: _AnalysisGroup(
                    key: const ValueKey('create-filter-style-group'),
                    label: S.get('create.detected'),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: tags.map((tag) => _TagChip(tag)).toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalysisGroup extends StatelessWidget {
  final String label;
  final Widget child;

  const _AnalysisGroup({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x19000000), blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.oceanFoam.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.oceanFoam.withValues(alpha: 0.16),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.oceanFoam,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Success Sheet — A1 + A3
// ─────────────────────────────────────────────────────────

class _SuccessSheet extends StatelessWidget {
  final FilterPreset preset;
  final String? sourcePath;
  final String? sampleAfterPath;
  final String? referenceGuidance;
  final VoidCallback? onReselect;
  final Future<void> Function() onEditNow;

  const _SuccessSheet({
    required this.preset,
    required this.sourcePath,
    required this.sampleAfterPath,
    this.referenceGuidance,
    this.onReselect,
    required this.onEditNow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: const BoxDecoration(
        color: AppColors.cloudWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 52,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.cloudVeil,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 20),

            // Before / After preview
            _BeforeAfterPreview(
              beforePath: sourcePath,
              afterPath: sampleAfterPath,
            ),
            const SizedBox(height: 20),

            // Success label
            const Icon(Icons.check_circle_outline_rounded,
                color: AppColors.oceanFoam, size: 40),
            const SizedBox(height: 10),
            Text(
              '\'${preset.name}\' ${S.get('create.success')}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Domine',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              S.get('create.success_sub'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            if (referenceGuidance != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cloudPure,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.oceanFoam, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        referenceGuidance!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // CTA: edit now
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onEditNow,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(S.get('create.btn_edit_now')),
              ),
            ),
            if (onReselect != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onReselect,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(localeNotifier.value.languageCode == 'en'
                      ? 'Choose reference photos again'
                      : '참조 사진 다시 선택'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.oceanFoam,
                    side: const BorderSide(color: AppColors.cloudMist),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.cloudMist),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: Text(S.get('create.done')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeforeAfterPreview extends StatelessWidget {
  final String? beforePath;
  final String? afterPath;

  const _BeforeAfterPreview({
    required this.beforePath,
    required this.afterPath,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PreviewCard(
            imagePath: beforePath,
            label: S.get('create.before'),
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.arrow_forward_rounded,
            color: AppColors.oceanFoam, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: _PreviewCard(
            imagePath: afterPath,
            label: S.get('create.after'),
            isAfter: true,
          ),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String? imagePath;
  final String label;
  final bool isAfter;

  const _PreviewCard({
    this.imagePath,
    required this.label,
    this.isAfter = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: isAfter ? AppColors.oceanFoam : AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: imagePath != null
                ? Image.file(File(imagePath!), fit: BoxFit.cover)
                : Container(color: AppColors.cloudVeil),
          ),
        ),
      ],
    );
  }
}
