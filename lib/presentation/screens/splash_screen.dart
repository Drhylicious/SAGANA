import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/hive_service.dart';
import '../../routes/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ─── Animation Controllers ──────────────────────────────────────────────────
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final AnimationController _barController;
  late final AnimationController _shimmerController;

  // ─── Animations ─────────────────────────────────────────────────────────────
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textOpacity;
  late final Animation<double> _barProgress;

  @override
  void initState() {
    super.initState();
    _setupSystemUI();
    _initAnimations();
    _startSequence();
  }

  void _setupSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppConstants.primaryContainer,
    ));
  }

  void _initAnimations() {
    // Logo: scale + fade in
    _logoController = AnimationController(
      vsync: this,
      duration: AppConstants.splashLogoDuration,
    );
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );

    // Text: slide up + fade in
    _textController = AnimationController(
      vsync: this,
      duration: AppConstants.splashTextDuration,
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );

    // Loading bar
    _barController = AnimationController(
      vsync: this,
      duration: AppConstants.splashBarDuration,
    );
    _barProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _barController, curve: Curves.easeInOut),
    );

    // Shimmer on loading bar
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  Future<void> _startSequence() async {
    // Logo appears
    await Future.delayed(AppConstants.splashLogoDelay);
    if (!mounted) return;
    _logoController.forward();

    // Text slides up
    await Future.delayed(AppConstants.splashTextDelay);
    if (!mounted) return;
    _textController.forward();
    _barController.forward();

    // Navigate after bar completes
    await Future.delayed(AppConstants.splashNavDelay);
    if (!mounted) return;
    await _navigate();
  }

  Future<void> _navigate() async {
    String targetRoute;

    if (AuthService.isLoggedIn) {
      final role = await AuthService.getCurrentUserRole();
      switch (role) {
        case AppConstants.roleAdmin:
          targetRoute = AppRoutes.adminDashboard;
          break;
        case AppConstants.roleFarmer:
          targetRoute = AppRoutes.farmerDashboard;
          break;
        case AppConstants.roleBuyer:
          targetRoute = AppRoutes.marketplaceBrowse;
          break;
        default:
          targetRoute = AppRoutes.login;
      }
    } else {
      // Offline fallback: check Hive cache
      final cachedRole = HiveService.getUserRole();
      final isLoggedIn = HiveService.isLoggedIn();
      if (isLoggedIn && cachedRole != null) {
        switch (cachedRole) {
          case AppConstants.roleAdmin:
            targetRoute = AppRoutes.adminDashboard;
            break;
          case AppConstants.roleFarmer:
            targetRoute = AppRoutes.farmerDashboard;
            break;
          case AppConstants.roleBuyer:
            targetRoute = AppRoutes.marketplaceBrowse;
            break;
          default:
            targetRoute = AppRoutes.login;
        }
      } else {
        targetRoute = AppRoutes.login;
      }
    }

    if (!mounted) return;
    context.go(targetRoute);
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _barController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppConstants.splashGradient,
        ),
        child: Stack(
          children: [
            // ── Decorative blurred orbs (depth effect) ───────────────────────
            Positioned(
              bottom: -96,
              left: -96,
              child: _BlurOrb(
                size: 256,
                color: AppConstants.primaryGreen.withOpacity(0.4),
              ),
            ),
            Positioned(
              top: -96,
              right: -96,
              child: _BlurOrb(
                size: 256,
                color: AppConstants.tertiaryContainer.withOpacity(0.3),
              ),
            ),

            // ── Center content ────────────────────────────────────────────────
            Column(
              children: [
                // Logo cluster — centered in available space
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Glowing logo circle
                        AnimatedBuilder(
                          animation: _logoController,
                          builder: (_, __) => Opacity(
                            opacity: _logoOpacity.value,
                            child: Transform.scale(
                              scale: _logoScale.value,
                              child: _LogoCircle(),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Brand typography
                        AnimatedBuilder(
                          animation: _textController,
                          builder: (_, __) => Opacity(
                            opacity: _textOpacity.value,
                            child: SlideTransition(
                              position: _textSlide,
                              child: _BrandText(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom metadata + loading bar
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: Column(
                    children: [
                      // Loading bar
                      AnimatedBuilder(
                        animation: Listenable.merge(
                            [_barController, _shimmerController]),
                        builder: (_, __) => _LoadingBar(
                          progress: _barProgress.value,
                          shimmerValue: _shimmerController.value,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Cooperative name
                      Text(
                        AppConstants.cooperativeName.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 2.0,
                          color: AppConstants.onPrimaryContainer.withOpacity(0.6),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Secure gateway indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppConstants.successGreen,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppConstants.successGreen
                                      .withOpacity(0.8),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Secure Gateway Active',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppConstants.onPrimaryContainer
                                  .withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logo Circle Widget
// ─────────────────────────────────────────────────────────────────────────────

class _LogoCircle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 192,
      height: 192,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          Container(
            width: 192,
            height: 192,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppConstants.harvestGold.withOpacity(0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Glass circle
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.05),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(
              Icons.agriculture_rounded,
              size: 64,
              color: AppConstants.harvestGold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Brand Text Widget
// ─────────────────────────────────────────────────────────────────────────────

class _BrandText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          AppConstants.appName,
          style: GoogleFonts.poppins(
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: 10,
            color: AppConstants.onPrimaryContainer,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 16,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppConstants.appSubtitle.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 3,
            color: AppConstants.onTertiaryContainer.withOpacity(0.9),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading Bar Widget
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingBar extends StatelessWidget {
  final double progress;
  final double shimmerValue;

  const _LoadingBar({required this.progress, required this.shimmerValue});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 192,
      height: 2,
      child: Stack(
        children: [
          // Track
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Progress fill with shimmer
          FractionallySizedBox(
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    AppConstants.onTertiaryContainer.withOpacity(0),
                    AppConstants.onTertiaryContainer
                        .withOpacity(0.4 * math.sin(shimmerValue * math.pi)),
                    AppConstants.onTertiaryContainer.withOpacity(0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Blur Orb (decorative)
// ─────────────────────────────────────────────────────────────────────────────

class _BlurOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _BlurOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
        child: const SizedBox.expand(),
      ),
    );
  }
}
