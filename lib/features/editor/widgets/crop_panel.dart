import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/models/crop_ratio_preset.dart';
import '../../../core/theme/app_colors.dart';

class CropPanel extends StatefulWidget {
  final CropRatioPreset activePreset;
  final double? currentCustomRatio; // Current aspect ratio of the crop box
  final double? lockedCustomRatio; // Current active locked custom ratio
  final ValueChanged<CropRatioPreset> onPresetSelected;
  final ValueChanged<double?> onCustomRatioSelected;

  const CropPanel({
    super.key,
    required this.activePreset,
    this.currentCustomRatio,
    this.lockedCustomRatio,
    required this.onPresetSelected,
    required this.onCustomRatioSelected,
  });

  @override
  State<CropPanel> createState() => _CropPanelState();
}

class _CropPanelState extends State<CropPanel> {
  List<double> _customRatios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomPresets();
  }

  Future<void> _loadCustomPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('custom_crop_ratios') ?? [];
      debugPrint('LOADED CUSTOM CROP RATIOS: $saved');
      final parsed =
          saved.map((s) => double.tryParse(s)).whereType<double>().toList();
      setState(() {
        _customRatios = parsed;
        _loading = false;
      });
    } catch (e, stack) {
      debugPrint('ERROR LOADING CUSTOM CROP RATIOS: $e\n$stack');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _saveCustomPreset(double ratio) async {
    if (ratio <= 0) return;
    // Format to 2 decimal places to avoid duplicates of slightly different ratios
    final roundedRatio = double.parse(ratio.toStringAsFixed(2));
    if (_customRatios.contains(roundedRatio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 존재하는 비율입니다.')),
      );
      return;
    }

    setState(() {
      _customRatios.add(roundedRatio);
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = _customRatios.map((r) => r.toString()).toList();
      await prefs.setStringList('custom_crop_ratios', stringList);
    } catch (_) {}
  }

  Future<void> _deleteCustomPreset(double ratio) async {
    setState(() {
      _customRatios.remove(ratio);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = _customRatios.map((r) => r.toString()).toList();
      await prefs.setStringList('custom_crop_ratios', stringList);
    } catch (_) {}

    if (widget.lockedCustomRatio == ratio) {
      widget.onCustomRatioSelected(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.oceanFoam),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Horizontal scrollable list
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // Standard preset buttons
              ...CropRatioPreset.values.map((preset) {
                final isSelected = widget.activePreset == preset &&
                    widget.lockedCustomRatio == null;
                return _buildPresetItem(
                  label: preset.label,
                  isSelected: isSelected,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onPresetSelected(preset);
                    widget.onCustomRatioSelected(null);
                  },
                );
              }),

              // Custom user-saved preset buttons
              ..._customRatios.map((ratio) {
                final isSelected =
                    widget.activePreset == CropRatioPreset.free &&
                        widget.lockedCustomRatio == ratio;
                final label = '${ratio.toStringAsFixed(2)}:1';
                debugPrint('CROP PANEL CUSTOM PRESET MAPPED LABEL: $label');
                return _buildCustomPresetItem(
                  label: label,
                  ratio: ratio,
                  isSelected: isSelected,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onPresetSelected(CropRatioPreset.free);
                    widget.onCustomRatioSelected(ratio);
                  },
                  onDelete: () => _deleteCustomPreset(ratio),
                );
              }),
            ],
          ),
        ),

        // Action panel (Save custom ratio)
        if (widget.activePreset == CropRatioPreset.free &&
            widget.currentCustomRatio != null) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.oceanTeal,
              foregroundColor: AppColors.cloudWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            icon: const Icon(Icons.bookmark_add_outlined, size: 16),
            label: Text(
              '현재 비율 저장 (${widget.currentCustomRatio!.toStringAsFixed(2)}:1)',
              style: const TextStyle(fontFamily: 'NotoSerif', fontSize: 12),
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              _saveCustomPreset(widget.currentCustomRatio!);
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPresetItem({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.oceanTeal : AppColors.oceanNavy,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppColors.oceanFoam
                    : AppColors.oceanFoam.withOpacity(0.18),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    isSelected ? AppColors.cloudWhite : AppColors.textOnDarkSub,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomPresetItem({
    required String label,
    required double ratio,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.oceanTeal : AppColors.oceanNavy,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppColors.oceanFoam
                    : AppColors.oceanFoam.withOpacity(0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bookmark_outline,
                  size: 12,
                  color: AppColors.oceanFoam,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'NotoSerif',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppColors.cloudWhite
                        : AppColors.textOnDarkSub,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    // Prevent trigger onTap for selection
                    onDelete();
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4.0),
                    child: Icon(
                      Icons.cancel,
                      size: 14,
                      color: isSelected
                          ? AppColors.cloudWhite.withOpacity(0.7)
                          : AppColors.textOnDarkSub.withOpacity(0.5),
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
}
