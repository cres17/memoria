import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/filter_repository_impl.dart';
import '../../domain/models/filter_preset.dart';
import '../../domain/models/adjust_params.dart';
import '../../engine/lut_engine.dart';
import '../../monetization/feature_flags_service.dart';
import '../../monetization/fullscreen_ad_service.dart';

class CreateFilterPage extends StatefulWidget {
  const CreateFilterPage({super.key});

  @override
  State<CreateFilterPage> createState() => _CreateFilterPageState();
}

class _CreateFilterPageState extends State<CreateFilterPage> {
  String? _styleImagePath;
  String _filterName = '';
  bool _generating = false;
  double _progress = 0.0;
  String? _resultPresetId;

  final _nameCtrl = TextEditingController();
  FeatureFlagsService? _flags;
  FullScreenAdService? _adService;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    final f = await FeatureFlagsService.create();
    if (mounted) setState(() { _flags = f; _adService = FullScreenAdService(f); });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStyleImage() async {
    HapticFeedback.mediumImpact();
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile != null && mounted) {
      setState(() => _styleImagePath = xFile.path);
    }
  }

  Future<void> _generate() async {
    if (_styleImagePath == null) {
      _showSnack('스타일 이미지를 선택해주세요');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('필터 이름을 입력해주세요');
      return;
    }

    // Show ad if flag enabled (bypass on failure)
    if (_adService != null) {
      await _adService!.show(FullScreenAdTrigger.createFilter);
    }

    setState(() { _generating = true; _progress = 0.1; });
    HapticFeedback.heavyImpact();

    try {
      setState(() => _progress = 0.3);
      final result = await generateLutFromStyle(_styleImagePath!);
      setState(() => _progress = 0.8);

      final now = DateTime.now();
      final preset = FilterPreset(
        id:               result['presetId'] as String,
        name:             name,
        type:             FilterPresetType.custom,
        lutPath:          result['lutPath'] as String,
        params:           AdjustParams.zero,
        defaultIntensity: 0.8,
        thumbnailPath:    result['thumbnailPath'] as String,
        createdAt:        now,
        updatedAt:        now,
      );

      await FilterRepositoryImpl().savePreset(preset);
      setState(() { _progress = 1.0; _resultPresetId = preset.id; });

      HapticFeedback.notificationVibrate();
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        _showSuccessSheet(preset);
      }
    } catch (e) {
      _showSnack('필터 생성 중 오류가 발생했어요: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Pretendard')),
        backgroundColor: AppColors.oceanNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessSheet(FilterPreset preset) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuccessSheet(preset: preset),
    ).then((_) => context.pop());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.oceanDeep,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(child: _buildContent()),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          if (_generating) _buildGeneratingOverlay(),
          Positioned(
            left: 20, right: 20, bottom: 32,
            child: SafeArea(
              child: FilledButton(
                onPressed: _generating ? null : _generate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentPrimary,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.auto_awesome_rounded,
                        color: AppColors.cloudWhite, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'AI 필터 생성',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cloudWhite,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.oceanDeep,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: AppColors.textOnDark),
        onPressed: () => context.pop(),
      ),
      title: const Text(
        'AI 필터 만들기',
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textOnDark,
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepCard(
            step: '1',
            title: '스타일 이미지 선택',
            subtitle: '필터로 만들고 싶은 분위기의 사진을 골라주세요',
            child: _buildImagePicker(),
          ),
          const SizedBox(height: 20),
          _buildStepCard(
            step: '2',
            title: '필터 이름',
            subtitle: '나만의 필터 이름을 지어주세요',
            child: _buildNameInput(),
          ),
          const SizedBox(height: 20),
          _buildInfoCard(),
        ],
      ),
    );
  }

  Widget _buildStepCard({
    required String step,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.oceanMid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.oceanNavy),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.oceanFoam.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(step,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.oceanFoam,
                      )),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textOnDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: AppColors.textOnDarkTert,
              ),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickStyleImage,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.oceanNavy,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _styleImagePath != null
                ? AppColors.oceanFoam.withOpacity(0.4)
                : AppColors.oceanNavy,
            width: 1.5,
          ),
        ),
        child: _styleImagePath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.file(
                  File(_styleImagePath!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.oceanBlue.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: AppColors.oceanFoam,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '이미지를 선택하세요',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textOnDarkSub,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '원하는 분위기의 사진 1장',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      color: AppColors.textOnDarkTert,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildNameInput() {
    return TextField(
      controller: _nameCtrl,
      onChanged: (v) => setState(() => _filterName = v),
      style: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 15,
        color: AppColors.textOnDark,
      ),
      decoration: InputDecoration(
        hintText: '예: 골든아워, 필름느낌, 차가운여름...',
        filled: true,
        fillColor: AppColors.oceanNavy,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        prefixIcon: const Icon(Icons.edit_rounded,
            color: AppColors.textOnDarkTert, size: 18),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.oceanBlue.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.oceanFoam.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.oceanFoam, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '완전 온디바이스 처리로 서버 비용 없이\n개인 정보가 보호됩니다',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: AppColors.textOnDarkSub,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingOverlay() {
    return Container(
      color: AppColors.overlay40,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.oceanMid,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.foamGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.cloudWhite, size: 28),
              ),
              const SizedBox(height: 20),
              const Text(
                'AI가 필터를 생성하는 중...',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textOnDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '스타일을 분석하고 33³ LUT를 생성합니다',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  color: AppColors.textOnDarkTert,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: AppColors.oceanNavy,
                valueColor: const AlwaysStoppedAnimation(AppColors.oceanFoam),
                borderRadius: BorderRadius.circular(4),
                minHeight: 6,
              ),
              const SizedBox(height: 10),
              Text(
                '${(_progress * 100).round()}%',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  color: AppColors.textOnDarkSub,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessSheet extends StatelessWidget {
  final FilterPreset preset;
  const _SuccessSheet({required this.preset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: AppColors.oceanMid,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.oceanNavy,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.accentSuccess.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: AppColors.accentSuccess, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            '\'${preset.name}\' 필터 생성 완료!',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textOnDark,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            '내 필터 탭에서 사용할 수 있어요',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              color: AppColors.textOnDarkSub,
            ),
          ),
          const SizedBox(height: 28),
          SafeArea(
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentPrimary,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                '확인',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.cloudWhite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
