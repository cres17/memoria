import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../features/create_filter/create_filter_page.dart'
    show kPhotoFilterGenerationEnabled;
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../utils/platform_utils.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final navIndex = _navIndex(location);

    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: _BottomNav(currentIndex: navIndex),
    );
  }

  int _navIndex(String location) {
    if (location.startsWith('/filters')) return 3;
    return 0;
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  const _BottomNav({required this.currentIndex});

  Future<void> _pickAndEdit(BuildContext context) async {
    hapticMedium();
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.get('permission.photos_denied')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xFile != null && context.mounted) {
      context.pushNamed('editor', extra: xFile.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = safeBottom(context);
    final navBottom = bottomPad > 0 ? bottomPad : 18.0;
    return Container(
      margin: EdgeInsets.fromLTRB(20, 0, 20, navBottom),
      decoration: const BoxDecoration(
        color: AppColors.cloudWhite,
        borderRadius: BorderRadius.all(Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14032111),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'HOME',
              selected: currentIndex == 0,
              onTap: () => context.go('/'),
            ),
            if (kPhotoFilterGenerationEnabled)
              _NavItem(
                icon: Icons.add_circle_outline_rounded,
                selectedIcon: Icons.add_circle_rounded,
                label: 'CREATE',
                selected: currentIndex == 1,
                onTap: () => context.pushNamed('createFilter'),
              ),
            _NavItem(
              icon: Icons.tune_outlined,
              selectedIcon: Icons.tune_rounded,
              label: 'EDIT',
              selected: currentIndex == 2,
              onTap: () => _pickAndEdit(context),
            ),
            _NavItem(
              icon: Icons.photo_library_outlined,
              selectedIcon: Icons.photo_library_rounded,
              label: 'GALLERY',
              selected: currentIndex == 3,
              onTap: () => context.go('/filters'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.oceanBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              color: selected ? AppColors.oceanFoam : AppColors.cloudShadow,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 1.2,
                color: selected ? AppColors.oceanFoam : AppColors.cloudShadow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
