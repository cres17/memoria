import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../monetization/banner_ad_widget.dart';
import '../../monetization/feature_flags_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late AnimationController _waveCtrl;
  late FeatureFlagsService? _flags;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final f = await FeatureFlagsService.create();
    if (mounted) setState(() => _flags = f);
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    HapticFeedback.mediumImpact();
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile != null && mounted) {
      context.pushNamed('editor', extra: xFile.path);
    }
  }

  Future<void> _takePhoto() async {
    HapticFeedback.mediumImpact();
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.camera);
    if (xFile != null && mounted) {
      context.pushNamed('editor', extra: xFile.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.oceanDeep,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                _buildAppBar(),
                SliverToBoxAdapter(child: _buildHero()),
                SliverToBoxAdapter(child: _buildQuickActions()),
                SliverToBoxAdapter(child: _buildRecentSection()),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
          if (_flags != null)
            BannerAdWidget(flags: _flags!),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 0,
      backgroundColor: AppColors.oceanDeep,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppColors.foamGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.water_drop_rounded,
                color: AppColors.cloudWhite, size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            'Memoria',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textOnDark,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_rounded,
              color: AppColors.textOnDarkSub, size: 22),
          onPressed: () => context.pushNamed('settings'),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D2137),
            Color(0xFF1A4A80),
            Color(0xFF0F3560),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.oceanBlue.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Animated wave circles
          AnimatedBuilder(
            animation: _waveCtrl,
            builder: (_, __) => CustomPaint(
              painter: _WavePainter(_waveCtrl.value),
              size: const Size(double.infinity, 220),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.oceanFoam.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.oceanFoam.withOpacity(0.3),
                    ),
                  ),
                  child: const Text(
                    'AI 필터 생성',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.oceanFoam,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '사진 한 장으로\n나만의 필터를',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnDark,
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '스타일 이미지를 업로드하면 AI가 커스텀 LUT 필터를 생성합니다',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textOnDark.withOpacity(0.6),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '시작하기',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textOnDark,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.photo_library_rounded,
                  title: '갤러리에서\n사진 선택',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B6CA8), Color(0xFF2E87C8)],
                  ),
                  onTap: _pickImage,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.camera_alt_rounded,
                  title: '카메라로\n촬영',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D3A6B), Color(0xFF1E5082)],
                  ),
                  onTap: _takePhoto,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.auto_awesome_rounded,
                  title: '필터\n만들기',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2C5F8A), Color(0xFF4B9CD3)],
                  ),
                  onTap: () => context.pushNamed('createFilter'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '최근 편집',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textOnDark,
                  letterSpacing: -0.3,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('전체보기',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      color: AppColors.oceanFoam,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildEmptyRecent(),
        ],
      ),
    );
  }

  Widget _buildEmptyRecent() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.oceanMid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.oceanNavy),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_album_outlined,
                color: AppColors.textOnDarkTert, size: 32),
            const SizedBox(height: 8),
            Text(
              '아직 편집한 사진이 없어요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: AppColors.textOnDarkTert,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.oceanBlue.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.cloudWhite, size: 26),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.cloudWhite,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double t;
  _WavePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.oceanFoam.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < 3; i++) {
      final r = 60.0 + 50.0 * i + (t * 30) % 50;
      canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.25),
        r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t;
}
