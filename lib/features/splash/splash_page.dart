import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _fadeIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );

    _progress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.3, 0.92, curve: Curves.easeInOut),
    );

    _ctrl.forward();

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        context.go('/');
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloudPure,
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo mark
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.oceanFoam,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.accentGlow,
                  size: 38,
                ),
              ),
              const SizedBox(height: 28),
              // App name
              const Text(
                'Memoria',
                style: TextStyle(
                  fontFamily: 'Domine',
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: AppColors.oceanFoam,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your Digital Sanctuary',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 52),
              // Progress bar
              SizedBox(
                width: 180,
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (context, _) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: _progress.value,
                        minHeight: 3,
                        backgroundColor: AppColors.cloudVeil,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.oceanFoam,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
