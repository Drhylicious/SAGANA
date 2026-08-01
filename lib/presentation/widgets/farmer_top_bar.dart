import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/services/profile_state_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FarmerTopBar
// Shared top bar for all Farmer-module screens. Same glass-blur treatment
// and left/center/right slot layout as Admin's top bar, tailored to the
// Farmer experience: SAGANA branding (root tabs) or a back button (pushed
// screens) on the left, an optional title centered, and notifications /
// settings / profile avatar grouped on the right.
// ─────────────────────────────────────────────────────────────────────────────

class FarmerTopBar extends StatefulWidget {
  final String? profilePhotoUrl;
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationTap;
  final VoidCallback? onSettingsTap;
  final int unreadCount;
  final List<Widget>? trailing;
  final bool hideProfileAvatar;
  final bool showNotificationButton;
  // Renders transparent, unblurred, with white/light chrome — for screens
  // with their own dark hero background (e.g. a gradient) behind the bar,
  // instead of the default opaque light bar with dark-green icons.
  final bool overlay;

  const FarmerTopBar({
    super.key,
    this.profilePhotoUrl,
    this.title,
    this.onBack,
    required this.onProfileTap,
    required this.onNotificationTap,
    this.onSettingsTap,
    this.unreadCount = 0,
    this.trailing,
    this.hideProfileAvatar = false,
    this.showNotificationButton = true,
    this.overlay = false,
  });

  @override
  State<FarmerTopBar> createState() => _FarmerTopBarState();
}

class _FarmerTopBarState extends State<FarmerTopBar> {
  final FarmerProfileStateService _profileState =
      FarmerProfileStateService.instance;

  @override
  void initState() {
    super.initState();
    _profileState.addListener(_onProfileStateChanged);
  }

  @override
  void dispose() {
    _profileState.removeListener(_onProfileStateChanged);
    super.dispose();
  }

  void _onProfileStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final sagana =
        Theme.of(context).extension<SaganaColors>() ?? SaganaColors.light;
    final cs = Theme.of(context).colorScheme;
    final effectiveProfilePhotoUrl = widget.hideProfileAvatar
        ? null
        : widget.profilePhotoUrl ?? _profileState.profilePhotoUrl;

    final iconColor = widget.overlay ? Colors.white : cs.primary;
    final titleColor = widget.overlay ? Colors.white : cs.onSurface;

    final content = Container(
      height: 64 + topPadding,
      padding: EdgeInsets.only(top: topPadding, left: 20, right: 20),
      decoration: widget.overlay
          ? const BoxDecoration(color: Colors.transparent)
          : BoxDecoration(
              color: sagana.navBarBackground,
              border: Border(
                bottom: BorderSide(color: cs.outline.withValues(alpha: 0.20)),
              ),
            ),
      child: Row(
        children: [
          // Left: Back button (pushed screens) or SAGANA branding (root tabs)
          if (widget.onBack != null)
            GestureDetector(
              onTap: widget.onBack,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.overlay
                      ? Colors.white.withValues(alpha: 0.20)
                      : sagana.cardBackground,
                  border: Border.all(
                    color: widget.overlay
                        ? Colors.white.withValues(alpha: 0.30)
                        : cs.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: Icon(Icons.arrow_back_rounded, color: iconColor),
              ),
            )
          else
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.95),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipOval(
                child: Image.asset(
                  'assets/images/sagana_icon.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),

          // Center: Title (if provided) — left-aligned next to the
          // logo/back button, matching AdminTopBar's layout, rather
          // than centered in the remaining row space.
          if (widget.title != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.title!,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),

          // Right: Custom trailing override, or default
          // Notifications (badge) → Settings (optional) → Profile
          Row(
            children: widget.trailing != null
                ? widget.trailing!
                : [
                    if (widget.showNotificationButton)
                      GestureDetector(
                        onTap: widget.onNotificationTap,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              Icons.notifications_outlined,
                              color: iconColor,
                              size: 26,
                            ),
                            if (widget.unreadCount > 0)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: AppConstants.errorRed,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (widget.onSettingsTap != null) ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: widget.onSettingsTap,
                        child: Icon(
                          Icons.settings_outlined,
                          color: iconColor,
                          size: 26,
                        ),
                      ),
                    ],
                    if (!widget.hideProfileAvatar) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: widget.onProfileTap,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.overlay
                                  ? Colors.white.withValues(alpha: 0.4)
                                  : cs.primary.withValues(alpha: 0.20),
                              width: 2,
                            ),
                            color: AppConstants.limeGreen,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: effectiveProfilePhotoUrl != null
                              ? Image.network(
                                  effectiveProfilePhotoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.person_rounded,
                                    color: cs.primary,
                                    size: 20,
                                  ),
                                )
                              : Icon(
                                  Icons.person_rounded,
                                  color: cs.primary,
                                  size: 20,
                                ),
                        ),
                      ),
                    ],
                  ],
          ),
        ],
      ),
    );

    // Blurring what's directly behind an opaque bar is the whole point of
    // the default mode — blurring a screen's own solid gradient behind a
    // transparent bar achieves nothing but wasted compute, so overlay
    // mode skips it.
    if (widget.overlay) return content;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: content,
      ),
    );
  }
}