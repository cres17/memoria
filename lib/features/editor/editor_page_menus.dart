part of 'editor_page.dart';

extension _EditorPageMenus on _EditorPageState {
  Widget _buildActiveToolBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.05),
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48),
          Expanded(
            child: Text(
              _activeToolName ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          IconButton(
            tooltip: S.get('editor.reset'),
            icon: const Icon(Icons.refresh_rounded, color: Colors.black87),
            onPressed: () {
              hapticLight();
              _resetActiveTool();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompareHoldIcon() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        hapticLight();
        _setComparePreviewVisible(true);
      },
      onTapUp: (_) => _setComparePreviewVisible(false),
      onTapCancel: () => _setComparePreviewVisible(false),
      child: Semantics(
        button: true,
        label: S.get('editor.compare'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _showComparePreview
                ? AppColors.oceanFoam
                : Colors.black.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: _showComparePreview
                  ? Colors.white.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.76),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x52000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_outlined,
                  color: Colors.white, size: 19),
              const SizedBox(width: 6),
              Text(
                S.get('editor.before'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteToolsDock() {
    final favTools = editorToolCatalog
        .where((t) => _favoriteToolIds.contains(t.id))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                S.get('editor.favorite_tools'),
                style: const TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              GestureDetector(
                onTap: _showCustomizeFavoritesSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0EE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.settings_outlined,
                          size: 12, color: Colors.black54),
                      const SizedBox(width: 4),
                      Text(
                        S.get('editor.customize'),
                        style: TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 85,
          child: favTools.isEmpty
              ? Center(
                  child: Text(
                    S.get('editor.favorite_tools_empty'),
                    style: const TextStyle(
                        fontFamily: 'NotoSerif',
                        fontSize: 11,
                        color: Colors.black54),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: favTools.length,
                  itemBuilder: (context, index) {
                    final tool = favTools[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () {
                          hapticLight();
                          _activateTool(tool.id, tool.label);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.04),
                                ),
                              ),
                              child: Icon(
                                tool.icon,
                                size: 24,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              tool.label,
                              style: const TextStyle(
                                fontFamily: 'NotoSerif',
                                fontSize: 10,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showCustomizeFavoritesSheet() {
    hapticLight();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF7F7F5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            S.get('editor.customize_favorites'),
                            style: const TextStyle(
                              fontFamily: 'NotoSerif',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              _saveFavoriteTools();
                              Navigator.pop(context);
                              _mutate(() {}); // Refresh parent state
                            },
                            child: Text(
                              S.get('editor.done'),
                              style: const TextStyle(
                                fontFamily: 'NotoSerif',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFC400),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      child: Text(
                        S.get('editor.customize_favorites_help'),
                        style: const TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.15,
                        ),
                        itemCount: editorToolCatalog.length,
                        itemBuilder: (context, index) {
                          final tool = editorToolCatalog[index];
                          final isFav = _favoriteToolIds.contains(tool.id);
                          return GestureDetector(
                            onTap: () {
                              hapticLight();
                              setSheetState(() {
                                if (isFav) {
                                  _favoriteToolIds.remove(tool.id);
                                } else {
                                  _favoriteToolIds.add(tool.id);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: isFav
                                    ? Colors.white
                                    : const Color(0xFFECECE9),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isFav
                                      ? const Color(0xFFFFC400)
                                      : Colors.transparent,
                                  width: 2.0,
                                ),
                                boxShadow: isFav
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFFFC400)
                                              .withValues(alpha: 0.15),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          tool.icon,
                                          size: 24,
                                          color: isFav
                                              ? Colors.black87
                                              : Colors.black54,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          tool.label,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontFamily: 'NotoSerif',
                                            fontSize: 11,
                                            fontWeight: isFav
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isFav
                                                ? Colors.black87
                                                : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isFav)
                                    const Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: Color(0xFFFFC400),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildToolsGridView() {
    return Container(
      height: 255,
      padding: const EdgeInsets.only(left: 12, right: 12, top: 2, bottom: 8),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.1,
        ),
        itemCount: editorToolCatalog.length,
        itemBuilder: (context, index) {
          final tool = editorToolCatalog[index];
          return GestureDetector(
            onTap: () {
              hapticLight();
              _activateTool(tool.id, tool.label);
            },
            child: Container(
              key: ValueKey('editor-tool-${tool.id}'),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.04),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    tool.icon,
                    size: 22,
                    color: Colors.black87,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tool.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainBottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.05),
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavTabItem(
              _MainNavTab.style, S.get('editor.style'), Icons.style_outlined),
          _buildNavTabItem(_MainNavTab.tools, S.get('editor.tools'),
              Icons.grid_view_rounded),
          _buildNavTabItem(_MainNavTab.export, S.get('editor.export'),
              Icons.ios_share_rounded),
        ],
      ),
    );
  }

  Widget _buildNavTabItem(_MainNavTab tab, String label, IconData icon) {
    final active = _mainNavTab == tab;
    return GestureDetector(
      onTap: () {
        hapticLight();
        _mutate(() {
          if (_mainNavTab == tab) {
            _mainNavTab = null;
          } else {
            _mainNavTab = tab;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFC400) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? Colors.black : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.black : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportMenu() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          _buildCompareHoldTile(),
          const SizedBox(height: 12),
          _buildExportTile(
            title: S.get('editor.save_to_photos'),
            subtitle: S.get('editor.save_to_photos_sub'),
            icon: Icons.save_alt_rounded,
            onTap: () {
              hapticLight();
              _export();
            },
          ),
          const SizedBox(height: 12),
          _buildExportTile(
            title: S.get('editor.share'),
            subtitle: S.get('editor.share_sub'),
            icon: Icons.share_rounded,
            onTap: () {
              hapticLight();
              _export(share: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompareHoldTile() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        hapticLight();
        _setComparePreviewVisible(true);
      },
      onTapUp: (_) => _setComparePreviewVisible(false),
      onTapCancel: () => _setComparePreviewVisible(false),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined,
                color: Colors.white, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.get('editor.compare'),
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    S.get('editor.compare_sub'),
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.04),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC400).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.black87,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanelContent() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          if (_isToolActive) ...[
            _buildActiveToolControls(),
            const SizedBox(height: 12),
            _buildActiveToolBottomBar(),
          ] else ...[
            if (_mainNavTab == null) ...[
              _buildFavoriteToolsDock(),
            ] else if (_mainNavTab == _MainNavTab.style) ...[
              FilterStrip(
                presets: _allPresets,
                selectedId: _selectedPreset?.id,
                favoriteIds: _favoriteFilterIds,
                onSelect: _selectPresetForPreview,
                onFavoriteToggle: _toggleFavorite,
              ),
              const SizedBox(height: 2),
              if (_selectedPreset != null)
                IntensitySlider(
                  value: _intensity,
                  onChangeStart: (_) {
                    _captureComparePreview();
                    unawaited(_startLiveSliding());
                  },
                  onChanged: (v) {
                    _mutate(() => _intensity = v);
                    _liveIntensityNotifier.value = v;
                    if (!_isSliding) _debouncedPreview();
                  },
                  onChangeEnd: (_) =>
                      _isSliding ? _endLiveSliding() : _renderPreview(),
                ),
              if (_showFavoriteTip)
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBE6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFE58F)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded,
                          color: Color(0xFFFAAD14), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          S.get('editor.favorite_tip'),
                          style: const TextStyle(
                            fontFamily: 'NotoSerif',
                            fontSize: 11,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _mutate(() => _showFavoriteTip = false);
                          _saveFavoriteTipDismissed();
                        },
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          S.get('editor.got_it'),
                          style: const TextStyle(
                            fontFamily: 'NotoSerif',
                            fontSize: 11,
                            color: AppColors.oceanFoam,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ] else if (_mainNavTab == _MainNavTab.tools) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    S.get('editor.all_tools'),
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              _buildToolsGridView(),
            ] else if (_mainNavTab == _MainNavTab.export) ...[
              _buildExportMenu(),
            ],
            const SizedBox(height: 8),
            _buildMainBottomNavigation(),
          ],
        ],
      ),
    );
  }

  Widget _buildExportOverlay() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
        child: Container(
          color: AppColors.overlay40,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(
                    0xE6092717), // Premium dark theme matching oceanFoam
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _exportForShare
                          ? Icons.ios_share_rounded
                          : Icons.save_alt_rounded,
                      color: const Color(0xFFFFC400),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _exportForShare
                        ? S.get('editor.sharing')
                        : S.get('editor.exporting'),
                    style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _exportForShare
                        ? S.get('editor.sharing_sub')
                        : S.get('editor.exporting_sub'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: _exportProgress,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFFFC400)),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${(_exportProgress * 100).round()}%',
                        style: const TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: _cancelExport,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        S.get('editor.cancel_export'),
                        style: const TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
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
