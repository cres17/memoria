part of 'create_filter_page.dart';

class _Header extends StatelessWidget {
  final VoidCallback onBack;

  const _Header({required this.onBack});

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
                  Semantics(
                    button: true,
                    label: S.get('editor.go_back'),
                    excludeSemantics: true,
                    child: IconButton(
                      tooltip: S.get('editor.go_back'),
                      onPressed: onBack,
                      icon: Icon(backIcon(), size: 21),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.52),
                        foregroundColor: AppColors.oceanFoam,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.oceanFoam,
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Memoria',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: 'Domine',
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: AppColors.oceanFoam,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 88),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFBDE3C7).withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          S.get(
                            kPhotoFilterGenerationIsBeta
                                ? 'create.header_beta'
                                : 'create.header',
                          ),
                          maxLines: 1,
                          style: const TextStyle(
                            color: AppColors.oceanFoam,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3,
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
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      hint: caption,
      excludeSemantics: true,
      child: Material(
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
                          color:
                              selected ? Colors.white : AppColors.textPrimary,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const ValueKey('recent-photo-state-action'),
                onPressed: action,
                child: Text(actionLabel),
              ),
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
