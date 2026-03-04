import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/filter_repository_impl.dart';
import '../../domain/models/filter_preset.dart';
import '../../monetization/banner_ad_widget.dart';
import '../../monetization/feature_flags_service.dart';

class FiltersPage extends StatefulWidget {
  const FiltersPage({super.key});

  @override
  State<FiltersPage> createState() => _FiltersPageState();
}

class _FiltersPageState extends State<FiltersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<FilterPreset> _customPresets = [];
  FeatureFlagsService? _flags;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
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
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.oceanDeep,
      body: Column(
        children: [
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (_, __) => [_buildHeader()],
              body: TabBarView(
                controller: _tabCtrl,
                children: [
                  _BuiltinFilterGrid(),
                  _CustomFilterGrid(
                    presets: _customPresets,
                    loading: _loading,
                    onRefresh: _load,
                  ),
                ],
              ),
            ),
          ),
          if (_flags != null) BannerAdWidget(flags: _flags!),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.mediumImpact();
          context.pushNamed('createFilter').then((_) => _load());
        },
        backgroundColor: AppColors.accentPrimary,
        icon: const Icon(Icons.auto_awesome_rounded,
            color: AppColors.cloudWhite),
        label: const Text(
          'AI 필터 만들기',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w600,
            color: AppColors.cloudWhite,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.oceanDeep,
      title: const Text(
        '필터',
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textOnDark,
          letterSpacing: -0.5,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: _buildTabBar(),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.oceanMid,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabCtrl,
        indicator: BoxDecoration(
          color: AppColors.oceanTeal,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelColor: AppColors.cloudWhite,
        unselectedLabelColor: AppColors.textOnDarkTert,
        tabs: const [
          Tab(text: '기본 필터'),
          Tab(text: '내 필터'),
        ],
      ),
    );
  }
}

class _BuiltinFilterGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final presets = BuiltinPresets.all;
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: presets.length,
      itemBuilder: (ctx, i) => _FilterCard(preset: presets[i]),
    );
  }
}

class _CustomFilterGrid extends StatelessWidget {
  final List<FilterPreset> presets;
  final bool loading;
  final VoidCallback onRefresh;

  const _CustomFilterGrid({
    required this.presets,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.oceanFoam),
      );
    }

    if (presets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                color: AppColors.textOnDarkTert, size: 48),
            const SizedBox(height: 16),
            const Text(
              '아직 만든 필터가 없어요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnDarkSub,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '사진 한 장으로 나만의 AI 필터를 만들어보세요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: AppColors.textOnDarkTert,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: presets.length,
      itemBuilder: (ctx, i) => _FilterCard(
        preset: presets[i],
        showDelete: true,
        onDelete: () {
          FilterRepositoryImpl().deletePreset(presets[i].id).then((_) => onRefresh());
        },
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  final FilterPreset preset;
  final bool showDelete;
  final VoidCallback? onDelete;

  const _FilterCard({
    required this.preset,
    this.showDelete = false,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        // Navigate to editor with this preset applied
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.oceanMid,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.oceanNavy),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(19)),
                child: _thumbnail(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preset.name,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textOnDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preset.isCustom ? '커스텀' : '기본',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 11,
                            color: preset.isCustom
                                ? AppColors.oceanFoam
                                : AppColors.textOnDarkTert,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showDelete && onDelete != null)
                    GestureDetector(
                      onTap: onDelete,
                      child: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.accentError, size: 20),
                    ),
                ],
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
      return Image.asset(path, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    } else if (path.isNotEmpty) {
      return Image.file(File(path), fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.oceanNavy,
      child: const Center(
        child: Icon(Icons.filter_rounded,
            color: AppColors.textOnDarkTert, size: 32),
      ),
    );
  }
}
