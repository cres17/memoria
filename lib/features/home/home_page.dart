import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/l10n/app_locale.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/platform_utils.dart';
import '../../monetization/banner_ad_widget.dart';
import '../../monetization/feature_flags_service.dart';
import '../create_filter/create_filter_page.dart' show kPhotoFilterGenerationEnabled;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  FeatureFlagsService? _flags;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    try {
      final flags = await FeatureFlagsService.create();
      if (mounted) setState(() => _flags = flags);
    } catch (_) {
      // 플래그 로드 실패 시 기본값(광고 비활성) 유지
    }
  }

  Future<void> _pickImage() async {
    hapticMedium();
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.get('permission.photos_denied')), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xFile != null && mounted) {
      context.pushNamed('editor', extra: xFile.path);
    }
  }

  Future<void> _takePhoto() async {
    hapticMedium();
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.get('permission.camera_denied')), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final xFile = await ImagePicker().pickImage(source: ImageSource.camera);
    if (xFile != null && mounted) {
      context.pushNamed('editor', extra: xFile.path);
    }
  }

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
                _buildAppBar(),
                SliverToBoxAdapter(child: _buildHero()),
                SliverToBoxAdapter(child: _buildFeatureImage()),
                SliverToBoxAdapter(child: _buildQuickCards()),
                SliverToBoxAdapter(child: SizedBox(height: safeBottom(context) + 100)),
              ],
            ),
          ),
          if (_flags != null) BannerAdWidget(flags: _flags!),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.cloudPure.withOpacity(0.94),
      surfaceTintColor: Colors.transparent,
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded,
              color: AppColors.oceanFoam, size: 26),
          SizedBox(width: 10),
          Text(
            'Memoria',
            style: TextStyle(
              fontFamily: 'Domine',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.oceanFoam,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: AppColors.cloudVeil,
              foregroundColor: AppColors.oceanFoam,
            ),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.pushNamed('settings'),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.oceanBlue.withOpacity(0.72),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.oceanMist, size: 15),
                const SizedBox(width: 8),
                Text(
                  S.get('app.tagline'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.oceanMist,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            S.get('home.headline'),
            style: const TextStyle(
              fontFamily: 'Domine',
              fontSize: 34,
              height: 1.12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 26),
          Text(
            S.get('home.subtitle'),
            style: TextStyle(
              fontSize: 17,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 34),
          FilledButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(S.get('home.cta')),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureImage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _pickImage,
        child: Container(
          height: 328,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFC17A55), Color(0xFF3A1D14)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A032111),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 168,
                  height: 238,
                  decoration: BoxDecoration(
                    color: AppColors.cloudVeil,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/frames/hp_frame_04_medium.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.photo_outlined,
                        size: 48,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 26,
                bottom: 26,
                right: 80,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Pill(
                      icon: Icons.circle,
                      label: S.get('home.location'),
                      light: true,
                    ),
                    SizedBox(height: 12),
                    Text(
                      S.get('home.photo_title'),
                      style: TextStyle(
                        fontFamily: 'Domine',
                        fontSize: 25,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cloudWhite,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 24,
                bottom: 36,
                child: _CircleButton(
                  icon: Icons.favorite_border_rounded,
                  onTap: _takePhoto,
                  light: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        children: [
          _InfoCard(
            icon: Icons.filter_vintage_rounded,
            title: S.get('home.card_tones'),
            body: S.get('home.card_tones_body'),
            onTap: () => context.go('/filters'),
          ),
          if (kPhotoFilterGenerationEnabled) ...[
            const SizedBox(height: 16),
            _InfoCard(
              icon: Icons.auto_awesome_rounded,
              title: S.get('home.card_ai'),
              body: S.get('home.card_ai_body'),
              tinted: true,
              onTap: () => context.pushNamed('createFilter'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool tinted;
  final VoidCallback onTap;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: tinted ? AppColors.oceanBlue : AppColors.cloudWhite,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.cloudVeil),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F032111),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                  color: AppColors.oceanFoam.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.oceanFoam, size: 26),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Domine',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              style: const TextStyle(
                fontSize: 16,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool light;

  const _Pill({required this.icon, required this.label, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: light
            ? AppColors.cloudWhite.withOpacity(0.22)
            : AppColors.oceanBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 9,
              color: light ? AppColors.accentGlow : AppColors.oceanFoam),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: light ? AppColors.cloudWhite : AppColors.oceanFoam,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool light;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: light
              ? AppColors.cloudWhite.withOpacity(0.18)
              : AppColors.cloudVeil,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: light ? AppColors.cloudWhite : AppColors.oceanFoam,
        ),
      ),
    );
  }
}
