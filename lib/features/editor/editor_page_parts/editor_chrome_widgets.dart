part of '../editor_page.dart';

class _EditorOverlayIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  const _EditorOverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(15),
            child: Ink(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: enabled
                    ? Colors.black.withValues(alpha: 0.36)
                    : Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: enabled
                      ? Colors.white.withValues(alpha: 0.76)
                      : Colors.white.withValues(alpha: 0.24),
                  width: 1.5,
                ),
                boxShadow: enabled
                    ? const [
                        BoxShadow(
                          color: Color(0x52000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: enabled ? Colors.white : Colors.white38,
                size: 21,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorApplyButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EditorApplyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '적용',
      child: Semantics(
        button: true,
        label: '적용',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(15),
            child: Ink(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.oceanFoam,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59032111),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, size: 20, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    '적용',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
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

// ── White Balance 프리셋 버튼 행 ──────────────────────────

class _WbPresetRow extends StatelessWidget {
  final ValueChanged<WhiteBalancePreset> onSelect;
  const _WbPresetRow({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 0, right: 8),
        children: WhiteBalancePreset.values.map((preset) {
          return GestureDetector(
            onTap: () {
              hapticLight();
              onSelect(preset);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.oceanFoam.withOpacity(0.2),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                preset.label,
                style: const TextStyle(
                  fontFamily: 'NotoSerif',
                  fontSize: 12,
                  color: AppColors.textOnDarkSub,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── B&W 토글 ────────────────────────────────────────────

class _BnwToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const _BnwToggle({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Text(
            'B&W',
            style: TextStyle(
              fontFamily: 'NotoSerif',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textOnDarkSub,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              hapticLight();
              onToggle(!enabled);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 22,
              decoration: BoxDecoration(
                color: enabled ? AppColors.oceanTeal : AppColors.oceanNavy,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Align(
                alignment:
                    enabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(
                    color: AppColors.cloudWhite,
                    shape: BoxShape.circle,
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

class _SubTabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SubTabBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.oceanTeal : AppColors.oceanNavy,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 14,
                color:
                    selected ? AppColors.cloudWhite : AppColors.textOnDarkTert),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSerif',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    selected ? AppColors.cloudWhite : AppColors.textOnDarkTert,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Phase 4: 아티스틱 이펙트 패널 ────────────────────────
