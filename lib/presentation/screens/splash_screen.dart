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
  late final AnimationController _exitController;
  late final AnimationController _pulseController;
  late final AnimationController _orbController;

  // ─── Animations ─────────────────────────────────────────────────────────────
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textOpacity;
  late final Animation<double> _exitOpacity;
  late final Animation<double> _exitScale;
  late final Animation<double> _pulseScale;
  late final Animation<double> _glowStrength;
  late final Animation<double> _orbDrift;

  @override
  void initState() {
    super.initState();
    _setupSystemUI();
    _initAnimations();
    _startSequence();
  }

  void _setupSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppConstants.primaryContainer,
      ),
    );
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
    _logoOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeIn));

    // Text: slide up + fade in
    _textController = AnimationController(
      vsync: this,
      duration: AppConstants.splashTextDuration,
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));
    _textOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeIn));

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

    // Exit: gentle fade + settle-forward scale, played just before handing
    // off to the route transition — without this, the splash content was
    // simply there one frame and gone the next (the incoming page's own
    // fade-in masked it most of the time, but nothing here ever
    // acknowledged the handoff, which is what read as abrupt rather than
    // smooth). Kept short and subtle: this is a handoff, not a new beat.
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );
    _exitScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );

    // Continuous "breathing" pulse on the logo medallion once it has
    // settled in — this is the difference between a logo that merely
    // appeared and one that feels alive while the app loads behind it.
    // Started only after the entrance finishes, so it never competes with
    // the easeOutBack entrance scale.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.045).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _glowStrength = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Slow, continuous drift on the two background orbs — static blurred
    // circles read as a placeholder background; a slow scale/opacity
    // breathing cycle (offset between the two, via the reversed curve on
    // the second orb) gives the backdrop the same sense of life as the
    // logo, without ever drawing attention away from the foreground.
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat(reverse: true);
    _orbDrift = CurvedAnimation(
      parent: _orbController,
      curve: Curves.easeInOut,
    );
  }

  Future<void> _startSequence() async {
    // Logo appears, then settles into a continuous gentle pulse once its
    // entrance has finished — the "alive, not static" difference this
    // revision is specifically about.
    await Future.delayed(AppConstants.splashLogoDelay);
    if (!mounted) return;
    _logoController.forward().then((_) {
      if (mounted) _pulseController.repeat(reverse: true);
    });

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
            final pendingAck = row['pending_acknowledgement'] as bool? ?? false;
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
    // Play the exit fade before handing off — the route-level fadeThrough
    // transition still runs on top of this, but the splash content no
    // longer just vanishes underneath it; it visibly lets go first.
    await _exitController.forward();
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
    _exitController.dispose();
    _pulseController.dispose();
    _orbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _exitController,
        builder: (_, child) => Opacity(
          opacity: _exitOpacity.value,
          child: Transform.scale(scale: _exitScale.value, child: child),
        ),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppConstants.splashGradient,
          ),
          child: Stack(
            children: [
              // ── Decorative blurred orbs (depth effect) ───────────────────────
              // Drift is phase-offset between the two (one reads the
              // animation directly, the other inverted) so they breathe out
              // of sync — a static pair pulsing in lockstep reads as
              // mechanical; offset, it reads as ambient.
              Positioned(
                bottom: -96,
                left: -96,
                child: _BlurOrb(
                  size: 256,
                  color: AppConstants.primaryGreen.withValues(alpha: 0.4),
                  drift: _orbDrift,
                ),
              ),
              Positioned(
                top: -96,
                right: -96,
                child: _BlurOrb(
                  size: 256,
                  color: AppConstants.tertiaryContainer.withValues(alpha: 0.3),
                  drift: _orbDrift,
                  inverted: true,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 24,
                        ),
                        child: Column(
                          children: [
                            // Logo cluster — nudged above dead-center so it doesn't
                            // read as sitting in a well of empty space above it.
                            Expanded(
                              child: Align(
                                alignment: const Alignment(0, -0.3),
                                // FittedBox(scaleDown) — same pattern already used for
                                // the Navigation Drawer's non-scrolling body: the logo
                                // cluster renders at its natural size on any normally
                                // sized screen, but scales down instead of overflowing
                                // when the available height is unusually constrained
                                // (e.g. a very short viewport).
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Glowing logo circle — entrance (scale + fade)
                                      // composed with the continuous breathing pulse
                                      // that takes over once the entrance settles.
                                      AnimatedBuilder(
                                        animation: Listenable.merge([
                                          _logoController,
                                          _pulseController,
                                        ]),
                                        builder: (_, __) => Opacity(
                                          opacity: _logoOpacity.value,
                                          child: Transform.scale(
                                            scale:
                                                _logoScale.value *
                                                _pulseScale.value,
                                            child: _LogoCircle(
                                              glowStrength: _glowStrength.value,
                                            ),
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
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 2.0,
                                      color: AppConstants.onPrimaryContainer
                                          .withValues(alpha: 0.6),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logo Circle Widget
// ─────────────────────────────────────────────────────────────────────────────

class _LogoCircle extends StatelessWidget {
  // 0.0-1.0 — drives the outer glow's intensity, in lockstep with the
  // medallion's own breathing pulse so the glow visibly "brightens" as
  // the medallion grows, rather than the two feeling like separate effects.
  final double glowStrength;
  const _LogoCircle({this.glowStrength = 1.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 208,
      height: 208,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          Container(
            width: 192 + 16 * glowStrength,
            height: 192 + 16 * glowStrength,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppConstants.harvestGold.withValues(
                    alpha: 0.10 + 0.10 * glowStrength,
                  ),
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
            colors: [Color(0xFFF3E2A9), Color(0xFFC4A14D), Color(0xFF8C6D1F)],
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
  static const double _shimmerWidth =
      64; // ~1/3 of track, matches mockup's w-1/3

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
  // Optional slow breathing drift (0.0-1.0, typically a repeating
  // CurvedAnimation) — omitted entirely, the orb is simply static, which
  // is still a valid, cheaper default for any future caller that doesn't
  // want the effect.
  final Animation<double>? drift;
  final bool inverted;

  const _BlurOrb({
    required this.size,
    required this.color,
    this.drift,
    this.inverted = false,
  });

  @override
  Widget build(BuildContext context) {
    final orb = Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
        child: const SizedBox.expand(),
      ),
    );

    if (drift == null) {
      return SizedBox(width: size, height: size, child: orb);
    }

    return AnimatedBuilder(
      animation: drift!,
      builder: (_, child) {
        final t = inverted ? 1.0 - drift!.value : drift!.value;
        final scale = 1.0 + t * 0.16;
        final opacity = 0.75 + t * 0.25;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: SizedBox(width: size, height: size, child: child),
          ),
        );
      },
      child: orb,
    );
  }
}
