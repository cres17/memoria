import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import '../../core/error/error_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';
import '../../data/repositories/filter_repository_impl.dart';
import '../../domain/models/filter_preset.dart';
import '../../monetization/banner_ad_widget.dart';
import '../../monetization/feature_flags_service.dart';
import '../create_filter/create_filter_page.dart'
    show kPhotoFilterGenerationEnabled, kPhotoFilterGenerationIsBeta;

class FiltersPage extends StatefulWidget {
  const FiltersPage({super.key});

  @override
  State<FiltersPage> createState() => _FiltersPageState();
}

class _FiltersPageState extends State<FiltersPage> {
  List<FilterPreset> _customPresets = [];
  FeatureFlagsService? _flags;
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final repo = FilterRepositoryImpl();
      final presets = await repo.getCustomPresets();
      final flags = await FeatureFlagsService.create();
      if (mounted) {
        setState(() {
          _customPresets = presets;
          _flags = flags;
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'Filter gallery initialization failed',
        error.runtimeType,
        stackTrace,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  List<FilterPreset> get _builtinPresets =>
      BuiltinPresets.all.where((p) => p.id != 'original').toList();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (_, __, ___) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloudPure,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                _buildHeader(),
                if (_loading)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        S.get('filters.loading'),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else if (_loadError)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 48, color: AppColors.textSecondary),
                          const SizedBox(height: 16),
                          Text(S.get('filters.load_error'),
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _load,
                            child: Text(S.get('filters.retry')),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  _buildSectionTitle(
                    S.get('filters.custom'),
                    top: 0,
                  ),
                  if (_customPresets.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
                        child: Text(
                          S.get('filters.custom_empty'),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  else
                    _buildCustomGrid(),
                  _buildSectionTitle(S.get('filters.builtin'), top: 16),
                  _buildPresetGrid(
                    presets: _builtinPresets,
                    startIndex: 0,
                    addBottomPadding: true,
                  ),
                ],
              ],
            ),
          ),
          if (_flags != null) BannerAdWidget(flags: _flags!),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Container(
            key: const ValueKey('filters-hero'),
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE4F3E8), Color(0xFFF8F5ED)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16032111),
                  blurRadius: 26,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: AppColors.oceanFoam, size: 19),
                    const SizedBox(width: 8),
                    const Text(
                      'Memoria',
                      style: TextStyle(
                        fontFamily: 'Domine',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.oceanFoam,
                      ),
                    ),
                    const Spacer(),
                    if (kPhotoFilterGenerationEnabled)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (kPhotoFilterGenerationIsBeta) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDDF1E3),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text(
                                'BETA',
                                style: TextStyle(
                                  color: AppColors.oceanFoam,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                          SizedBox(
                            key: const ValueKey('create-filter-plus'),
                            width: 42,
                            height: 42,
                            child: IconButton.filled(
                              tooltip: kPhotoFilterGenerationIsBeta
                                  ? '${S.get('filters.new')} · BETA'
                                  : S.get('filters.new'),
                              onPressed: _openCreateFilter,
                              icon: const Icon(Icons.add_rounded, size: 23),
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.oceanFoam,
                                foregroundColor: Colors.white,
                                shadowColor: const Color(0x33032111),
                                elevation: 5,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  S.get('filters.title'),
                  key: const ValueKey('filters-collection-title'),
                  style: const TextStyle(
                    fontFamily: 'Domine',
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: AppColors.oceanFoam,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _loading
                      ? S.get('filters.loading')
                      : S.get('filters.subtitle'),
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildSectionTitle(String title, {double top = 2}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(28, top, 28, 12),
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Domine',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  SliverPadding _buildPresetGrid({
    required List<FilterPreset> presets,
    required int startIndex,
    bool addBottomPadding = false,
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        28,
        0,
        28,
        addBottomPadding ? safeBottom(context) + 116 : 0,
      ),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 18,
          crossAxisSpacing: 22,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final preset = presets[index];
            return _FilterCard(
              preset: preset,
              index: startIndex + index,
              onTap: () => _openFilter(preset),
              onDelete: preset.isCustom ? () => _deletePreset(preset.id) : null,
            );
          },
          childCount: presets.length,
        ),
      ),
    );
  }

  SliverPadding _buildCustomGrid() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 18,
          crossAxisSpacing: 22,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final preset = _customPresets[index];
            return _FilterCard(
              preset: preset,
              index: _builtinPresets.length + index,
              onTap: () => _openFilter(preset),
              onDelete: () => _deletePreset(preset.id),
            );
          },
          childCount: _customPresets.length,
        ),
      ),
    );
  }

  void _openCreateFilter() {
    hapticMedium();
    context.pushNamed('createFilter').then((_) => _load());
  }

  Future<void> _openFilter(FilterPreset preset) async {
    hapticLight();
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;
    context.pushNamed('editor', extra: {
      'imagePath': xFile.path,
      'presetId': preset.id,
    });
  }

  Future<void> _deletePreset(String id) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.get('filters.delete_title')),
        content: Text(S.get('filters.delete_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.get('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(S.get('common.delete')),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    await FilterRepositoryImpl().deletePreset(id);
    await _load();
  }
}

class _FilterCard extends StatelessWidget {
  final FilterPreset preset;
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _FilterCard({
    required this.preset,
    required this.index,
    required this.onTap,
    this.onDelete,
  });

  static const _fallbackFrames = [
    'assets/frames/hp_frame_00_medium.jpg',
    'assets/frames/hp_frame_04_medium.jpg',
    'assets/frames/hp_frame_07_medium.jpg',
    'assets/frames/hp_frame_10_medium.jpg',
    'assets/frames/hp_frame_02_medium.jpg',
    'assets/frames/hp_frame_11_medium.jpg',
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _thumbnail(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.cloudWhite.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.cloudWhite.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      preset.isCustom
                          ? 'CUSTOM'
                          : (preset.brand?.wordmark ?? 'TONE'),
                      style: const TextStyle(
                        color: AppColors.cloudWhite,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preset.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Domine',
                      color: AppColors.cloudWhite,
                      fontSize: 23,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.28),
                    foregroundColor: AppColors.cloudWhite,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: onDelete,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail() {
    final path = preset.thumbnailPath;
    if (path.startsWith('assets/')) {
      return Image.asset(path, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
        return _fallback();
      });
    }
    if (path.isNotEmpty && !path.startsWith('assets/')) {
      return Image.file(File(path), fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
        return _fallback();
      });
    }
    return _fallback();
  }

  Widget _fallback() {
    return Image.asset(
      _fallbackFrames[index % _fallbackFrames.length],
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: AppColors.oceanNavy),
    );
  }
}
