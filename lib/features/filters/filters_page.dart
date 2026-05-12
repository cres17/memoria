import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';
import '../../data/repositories/filter_repository_impl.dart';
import '../../domain/models/filter_preset.dart';
import '../../monetization/banner_ad_widget.dart';
import '../../monetization/feature_flags_service.dart';
import '../create_filter/create_filter_page.dart' show kPhotoFilterGenerationEnabled;

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
    setState(() { _loading = true; _loadError = false; });
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
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadError = true; });
    }
  }

  List<FilterPreset> get _items => [
        ..._customPresets,
        ...BuiltinPresets.all.where((p) => p.id != 'original'),
      ];

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
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_loadError)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.textSecondary),
                          const SizedBox(height: 16),
                          Text(S.get('filters.load_error'), style: const TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _load,
                            child: Text(S.get('filters.retry')),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                  padding: EdgeInsets.fromLTRB(28, 22, 28, safeBottom(context) + 100),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 22,
                      childAspectRatio: 1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (kPhotoFilterGenerationEnabled) {
                          if (index == 0) return _CreateFilterCard(onTap: _openCreateFilter);
                          final preset = _items[index - 1];
                          return _FilterCard(
                            preset: preset,
                            index: index - 1,
                            onTap: () => _openFilter(preset),
                            onDelete: preset.isCustom ? () => _deletePreset(preset.id) : null,
                          );
                        } else {
                          final preset = _items[index];
                          return _FilterCard(
                            preset: preset,
                            index: index,
                            onTap: () => _openFilter(preset),
                            onDelete: preset.isCustom ? () => _deletePreset(preset.id) : null,
                          );
                        }
                      },
                      childCount: _items.length + (kPhotoFilterGenerationEnabled ? 1 : 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_flags != null) BannerAdWidget(flags: _flags!),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 204,
      backgroundColor: AppColors.cloudPure,
      surfaceTintColor: Colors.transparent,
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: AppColors.oceanFoam),
          SizedBox(width: 10),
          Text(
            'Memoria',
            style: TextStyle(
              fontFamily: 'Domine',
              fontSize: 25,
              fontWeight: FontWeight.w700,
              color: AppColors.oceanFoam,
            ),
          ),
        ],
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: const EdgeInsets.fromLTRB(28, 104, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.get('filters.title'),
                style: const TextStyle(
                  fontFamily: 'Domine',
                  fontSize: 43,
                  fontWeight: FontWeight.w700,
                  color: AppColors.oceanFoam,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _loading ? S.get('filters.loading') : S.get('filters.subtitle'),
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
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
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.get('permission.photos_denied')), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;
    context.pushNamed('editor', extra: {
      'imagePath': xFile.path,
      'presetId': preset.id,
    });
  }

  Future<void> _deletePreset(String id) async {
    await FilterRepositoryImpl().deletePreset(id);
    await _load();
  }
}

class _CreateFilterCard extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateFilterCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cloudWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cloudVeil),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F032111),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 42,
              backgroundColor: AppColors.oceanTeal,
              child: Icon(Icons.add_rounded,
                  color: AppColors.accentGlow, size: 42),
            ),
            const SizedBox(height: 26),
            Text(
              S.get('filters.new'),
              style: const TextStyle(
                fontFamily: 'Domine',
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: AppColors.oceanFoam,
                letterSpacing: 1.8,
              ),
            ),
          ],
        ),
      ),
    );
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
                      preset.isCustom ? 'CUSTOM' : _tagFor(preset.name),
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

  String _tagFor(String name) {
    switch (name.toLowerCase()) {
      case 'noir':
        return 'B&W';
      case 'warm':
      case 'golden':
        return 'WARM';
      case 'cool':
        return 'COOL';
      case 'fade':
      case 'pastel':
        return 'VINTAGE';
      default:
        return 'TONE';
    }
  }
}
