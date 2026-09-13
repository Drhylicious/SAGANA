import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

      if (role == AppConstants.roleFarmer) {
        // Every pre-active farmer state routes to the Pending Applicant
        // screen (Issue 5): draft / pending / rejected, plus approved-
        // but-not-yet-acknowledged (Decision D7).
        try {
          final userId = AuthService.currentUser?.id;
          if (userId != null) {
            final row = await Supabase.instance.client
                .from('user_roles')
                .select('status, pending_acknowledgement')
                .eq('user_id', userId)
                .single();
            final status = row['status'] as String? ?? 'active';
            final pendingAck =
                row['pending_acknowledgement'] as bool? ?? false;
            await HiveService.saveMemberStatus(status);
            await HiveService.savePendingAcknowledgement(pendingAck);
            targetRoute = _farmerHome(status, pendingAck);
          } else {
            targetRoute = AppRoutes.farmerDashboard;
          }
        } catch (_) {
          // Offline fallback
          targetRoute = _farmerHome(
            HiveService.getMemberStatus(),
            HiveService.getPendingAcknowledgement(),
          );
        }
      } else {
        switch (role) {
          case AppConstants.roleAdmin:
          case 'officer':
            targetRoute = AppRoutes.adminDashboard;
            break;
          case AppConstants.roleBuyer:
            targetRoute = AppRoutes.marketplaceBrowse;
            break;
          default:
            targetRoute = AppRoutes.login;
        }
      }
    } else {
      // Offline fallback: check Hive cache
      final cachedRole = HiveService.getUserRole();
      final isLoggedIn = HiveService.isLoggedIn();
      if (isLoggedIn && cachedRole != null) {
        if (cachedRole == AppConstants.roleFarmer) {
          targetRoute = _farmerHome(
            HiveService.getMemberStatus(),
            HiveService.getPendingAcknowledgement(),
          );
        } else {
          switch (cachedRole) {
            case AppConstants.roleAdmin:
            case 'officer':
              targetRoute = AppRoutes.adminDashboard;
              break;
            case AppConstants.roleBuyer:
              targetRoute = AppRoutes.marketplaceBrowse;
              break;
            default:
              targetRoute = AppRoutes.login;
          }
        }
      } else {
        targetRoute = AppRoutes.login;
      }
    }

    if (!mounted) return;
    context.go(targetRoute);
  }

  /// Where a farmer lands based on their membership state. Every pre-active
  /// state (and approved-but-unacknowledged) goes to the Pending Applicant
  /// screen; a fully-active member goes to the dashboard.
  static String _farmerHome(String? status, bool pendingAck) {
    const held = {'draft', 'pending', 'rejected'};
    if (held.contains(status) || (status == 'active' && pendingAck)) {
      return AppRoutes.pendingHome;
    }
    return AppRoutes.farmerDashboard;
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
                color: AppConstants.primaryGreen.withValues(alpha: 0.4),
              ),
            ),
            Positioned(
              top: -96,
              right: -96,
              child: _BlurOrb(
                size: 256,
                color: AppConstants.tertiaryContainer.withValues(alpha: 0.3),
              ),
            ),

            // ── Center content ────────────────────────────────────────────────
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      child: Column(
              children: [
                // Logo cluster — nudged above dead-center so it doesn't
                // read as sitting in a well of empty space above it.
                Expanded(
                  child: Align(
                    alignment: const Alignment(0, -0.3),
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

                        const SizedBox(height: 40),

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
                      // Loading bar — fixed line with a looping shimmer
                      // sweep, matching the mockup's footer divider (not
                      // a growing progress fill).
                      AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (_, __) => _LoadingBar(
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
                          color: AppConstants.onPrimaryContainer.withValues(alpha: 0.6),
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
                                      .withValues(alpha: 0.8),
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
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
                    ),
                  ),
                  ),
                ),
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
                  AppConstants.harvestGold.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Icon badge — gold medallion, matching the mockup's brushed-gold
          // circle instead of a flat white sticker. The icon's own dark
          // green tones read clearly against the gold.
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Color(0xFFF3E2A9),
                  Color(0xFFC4A14D),
                  Color(0xFF8C6D1F),
                ],
                stops: [0.0, 0.6, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Image.asset(
              'assets/images/sagana_icon.png',
              fit: BoxFit.contain,
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
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF3E2A9),
              Color(0xFFC4A14D),
              Color(0xFF8C6D1F),
            ],
            stops: [0.0, 0.5, 1.0],
          ).createShader(bounds),
          child: Text(
            AppConstants.appName,
            style: GoogleFonts.poppins(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              letterSpacing: 10,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppConstants.appSubtitle.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 3,
            color: AppConstants.onTertiaryContainer.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '"${AppConstants.appTagline}"',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.8),
            ),
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
  final double shimmerValue;

  const _LoadingBar({required this.shimmerValue});

  static const double _trackWidth = 192;
  static const double _shimmerWidth = 64; // ~1/3 of track, matches mockup's w-1/3

  @override
  Widget build(BuildContext context) {
    // Shimmer highlight sweeps from fully off-screen left to fully
    // off-screen right, looping continuously — mirrors the mockup's fixed
    // divider line with a moving highlight, not a growing progress fill.
    final left = -_shimmerWidth + shimmerValue * (_trackWidth + _shimmerWidth);

    return SizedBox(
      width: _trackWidth,
      height: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            // Fixed base track — translucent gold line
            Container(
              decoration: BoxDecoration(
                color: AppConstants.gold.withValues(alpha: 0.3),
              ),
            ),
            // Shimmer highlight sweeping across
            Positioned(
              left: left,
              top: 0,
              bottom: 0,
              width: _shimmerWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: AppConstants.gold,
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.gold.withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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