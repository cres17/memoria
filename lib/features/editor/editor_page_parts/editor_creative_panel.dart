part of '../editor_page.dart';

enum _CreativeSubTab { doubleExposure, frame, text }

class _CreativePanel extends StatefulWidget {
  final _CreativeSubTab? forceTab;
  final String? blendImagePath;
  final bm.BlendMode blendMode;
  final double blendOpacity;
  final int frameIndex;
  final String overlayText;
  final double textSize;
  final Color textColor;
  final String textFontFamily;
  final VoidCallback onPickBlend;
  final ValueChanged<bm.BlendMode> onBlendMode;
  final ValueChanged<double> onBlendOpacity;
  final ValueChanged<int> onFrameIndex;
  final ValueChanged<String> onText;
  final ValueChanged<double> onTextSize;
  final ValueChanged<Color> onTextColor;
  final ValueChanged<String> onTextFontFamily;

  const _CreativePanel({
    this.forceTab,
    required this.blendImagePath,
    required this.blendMode,
    required this.blendOpacity,
    required this.frameIndex,
    required this.overlayText,
    required this.textSize,
    required this.textColor,
    required this.textFontFamily,
    required this.onPickBlend,
    required this.onBlendMode,
    required this.onBlendOpacity,
    required this.onFrameIndex,
    required this.onText,
    required this.onTextSize,
    required this.onTextColor,
    required this.onTextFontFamily,
  });

  @override
  State<_CreativePanel> createState() => _CreativePanelState();
}

class _CreativePanelState extends State<_CreativePanel> {
  late _CreativeSubTab _sub;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _sub = widget.forceTab ?? _CreativeSubTab.doubleExposure;
    _textController = TextEditingController(text: widget.overlayText);
  }

  @override
  void didUpdateWidget(covariant _CreativePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlayText != widget.overlayText &&
        _textController.text != widget.overlayText) {
      _textController.value = TextEditingValue(
        text: widget.overlayText,
        selection: TextSelection.collapsed(offset: widget.overlayText.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.forceTab == null) ...[
          // sub-tab row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _SubTabBtn(
                    label: '이중 노출',
                    icon: Icons.layers_rounded,
                    selected: _sub == _CreativeSubTab.doubleExposure,
                    onTap: () =>
                        setState(() => _sub = _CreativeSubTab.doubleExposure)),
                const SizedBox(width: 8),
                _SubTabBtn(
                    label: '프레임',
                    icon: Icons.photo_size_select_large_rounded,
                    selected: _sub == _CreativeSubTab.frame,
                    onTap: () => setState(() => _sub = _CreativeSubTab.frame)),
                const SizedBox(width: 8),
                _SubTabBtn(
                    label: '텍스트',
                    icon: Icons.text_fields_rounded,
                    selected: _sub == _CreativeSubTab.text,
                    onTap: () => setState(() => _sub = _CreativeSubTab.text)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_sub == _CreativeSubTab.doubleExposure)
          _buildDoubleExposure()
        else if (_sub == _CreativeSubTab.frame)
          _buildFrame()
        else
          _buildText(),
      ],
    );
  }

  Widget _buildDoubleExposure() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: widget.onPickBlend,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.oceanFoam.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_rounded,
                      size: 18, color: AppColors.oceanFoam),
                  const SizedBox(width: 8),
                  Text(
                    widget.blendImagePath != null ? '이미지 변경' : '이미지 선택',
                    style: const TextStyle(
                        fontFamily: 'NotoSerif',
                        fontSize: 13,
                        color: AppColors.oceanFoam),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.blendImagePath != null) ...[
          const SizedBox(height: 8),
          // Blend mode chips
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: bm.BlendMode.values.map((m) {
                final sel = m == widget.blendMode;
                return GestureDetector(
                  onTap: () {
                    hapticLight();
                    widget.onBlendMode(m);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(m.label,
                        style: TextStyle(
                            fontFamily: 'NotoSerif',
                            fontSize: 12,
                            color: sel
                                ? AppColors.cloudWhite
                                : AppColors.textOnDarkSub)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          _opacityRow(),
        ],
      ],
    );
  }

  Widget _opacityRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          const SizedBox(
              width: 56,
              child: Text('불투명도',
                  style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      color: AppColors.textOnDarkSub))),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppColors.oceanFoam,
                inactiveTrackColor: AppColors.oceanNavy,
                thumbColor: AppColors.cloudWhite,
                trackHeight: 2.5,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                  value: widget.blendOpacity,
                  min: 0,
                  max: 1,
                  onChanged: widget.onBlendOpacity),
            ),
          ),
          SizedBox(
              width: 32,
              child: Text('${(widget.blendOpacity * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      color: AppColors.textOnDarkTert))),
        ],
      ),
    );
  }

  Widget _buildFrame() {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _frameAssets.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            // "없음" option
            final sel = widget.frameIndex == -1;
            return GestureDetector(
              onTap: () {
                hapticLight();
                widget.onFrameIndex(-1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 64,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: sel
                          ? AppColors.oceanFoam
                          : AppColors.oceanFoam.withOpacity(0.15)),
                ),
                child: const Center(
                    child: Text('없음',
                        style: TextStyle(
                            fontFamily: 'NotoSerif',
                            fontSize: 12,
                            color: AppColors.textOnDarkSub))),
              ),
            );
          }
          final idx = i - 1;
          final sel = widget.frameIndex == idx;
          return GestureDetector(
            onTap: () {
              hapticLight();
              widget.onFrameIndex(idx);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 64,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? AppColors.oceanFoam : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(_frameAssets[idx],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: AppColors.oceanNavy)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _textController,
            onChanged: widget.onText,
            style: const TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 14,
                color: AppColors.textOnDark),
            decoration: InputDecoration(
              hintText: '텍스트 입력…',
              hintStyle: const TextStyle(
                  fontFamily: 'NotoSerif', color: AppColors.textOnDarkTert),
              filled: true,
              fillColor: AppColors.oceanNavy,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text(
              '사진 위 텍스트를 드래그해 옮기고, 두 손가락으로 크기와 회전을 조절하세요.',
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 12,
                color: AppColors.textOnDarkTert,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                  width: 48,
                  child: Text('크기',
                      style: TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 12,
                          color: AppColors.textOnDarkSub))),
              Expanded(
                child: SliderTheme(
                  data: const SliderThemeData(
                    activeTrackColor: AppColors.oceanFoam,
                    inactiveTrackColor: AppColors.oceanNavy,
                    thumbColor: AppColors.cloudWhite,
                    trackHeight: 2.5,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                      value: widget.textSize,
                      min: 12,
                      max: 96,
                      onChanged: widget.onTextSize),
                ),
              ),
              SizedBox(
                  width: 36,
                  child: Text(widget.textSize.round().toString(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 12,
                          color: AppColors.textOnDarkTert))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                  width: 48,
                  child: Text('폰트',
                      style: TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 12,
                          color: AppColors.textOnDarkSub))),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: TextRasterizer.presetFonts.map((font) {
                      final sel = widget.textFontFamily == font;
                      return GestureDetector(
                        onTap: () {
                          hapticLight();
                          widget.onTextFontFamily(font);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                sel ? AppColors.oceanTeal : AppColors.oceanNavy,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: sel
                                  ? AppColors.oceanFoam
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            font,
                            style: TextStyle(
                              fontFamily: font,
                              fontSize: 12,
                              color: sel
                                  ? AppColors.cloudWhite
                                  : AppColors.textOnDarkSub,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('색상',
                  style: TextStyle(
                      fontFamily: 'NotoSerif',
                      fontSize: 12,
                      color: AppColors.textOnDarkSub)),
              const SizedBox(width: 12),
              ...[
                Colors.white,
                Colors.black,
                Colors.yellow,
                Colors.red,
                Colors.blue,
                Colors.green
              ].map((c) {
                final sel = widget.textColor == c;
                return GestureDetector(
                  onTap: () {
                    hapticLight();
                    widget.onTextColor(c);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? AppColors.oceanFoam : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Preview Isolate ───────────────────────────────────────────
