import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/services/profile_state_service.dart';
import 'animated_pressable.dart';
import '../../core/constants/app_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GlassCard
// ─────────────────────────────────────────────────────────────────────────────

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? backgroundColor;
  final double blurSigma;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = AppConstants.radiusLg,
    this.backgroundColor,
    this.blurSigma = 20,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding ?? const EdgeInsets.all(AppConstants.spacingGutter),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FarmerTopBar
// ─────────────────────────────────────────────────────────────────────────────

class FarmerTopBar extends StatefulWidget {
  final String? profilePhotoUrl;
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationTap;
  final VoidCallback? onSettingsTap;
  final List<Widget>? trailing;
  final bool hideProfileAvatar;

  const FarmerTopBar({
    super.key,
    this.profilePhotoUrl,
    this.title,
    this.onBack,
    required this.onProfileTap,
    required this.onNotificationTap,
    this.onSettingsTap,
    this.trailing,
    this.hideProfileAvatar = false,
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
    final effectiveProfilePhotoUrl = widget.hideProfileAvatar
        ? null
        : widget.profilePhotoUrl ?? _profileState.profilePhotoUrl;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64 + topPadding,
          padding: EdgeInsets.only(top: topPadding, left: 20, right: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.70),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.20)),
            ),
          ),
          child: Row(
            children: [
              // Left: Back button, profile, or empty placeholder
              if (widget.onBack != null)
                GestureDetector(
                  onTap: widget.onBack,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.90),
                      border: Border.all(
                        color: AppConstants.primaryGreen.withOpacity(0.15),
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppConstants.primaryGreen,
                    ),
                  ),
                )
              else if (widget.hideProfileAvatar)
                const SizedBox(width: 40, height: 40)
              else
                GestureDetector(
                  onTap: widget.onProfileTap,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppConstants.primaryGreen.withOpacity(0.20),
                        width: 2,
                      ),
                      color: AppConstants.limeGreen,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: effectiveProfilePhotoUrl != null
                        ? Image.network(
                            effectiveProfilePhotoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.person_rounded,
                              color: AppConstants.primaryGreen,
                              size: 22,
                            ),
                          )
                        : const Icon(
                            Icons.person_rounded,
                            color: AppConstants.primaryGreen,
                            size: 22,
                          ),
                  ),
                ),

              // Center: Title (if provided)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: widget.title != null
                      ? Text(
                          widget.title!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppConstants.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      : const SizedBox.shrink(),
                ),
              ),

              // Right: Custom trailing widgets or default Notifications + Settings
              Row(
                children: widget.trailing != null
                    ? widget.trailing!
                    : [
                        GestureDetector(
                          onTap: widget.onNotificationTap,
                          child: const Icon(
                            Icons.notifications_outlined,
                            color: AppConstants.primaryGreen,
                            size: 26,
                          ),
                        ),
                        if (widget.onSettingsTap != null) ...[
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: widget.onSettingsTap,
                            child: const Icon(
                              Icons.settings_outlined,
                              color: AppConstants.primaryGreen,
                              size: 26,
                            ),
                          ),
                        ],
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PrimaryButton
// ─────────────────────────────────────────────────────────────────────────────

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool useGradient;
  final IconData? icon;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.useGradient = true,
    this.icon,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPressable(
      onTap: isLoading ? null : onPressed,
      scaleDown: 0.97,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: useGradient && onPressed != null
                ? AppConstants.primaryButtonGradient
                : null,
            color: useGradient ? null : AppConstants.primaryGreen,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            boxShadow: onPressed != null
                ? [
                    BoxShadow(
                      color: AppConstants.primaryGreen.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppTextField
// ─────────────────────────────────────────────────────────────────────────────

class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final bool isPassword;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextCapitalization textCapitalization;
  final int maxLines;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.onChanged,
    this.readOnly = false,
    this.onTap,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: widget.isPassword && _obscureText,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      onChanged: widget.onChanged,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      textCapitalization: widget.textCapitalization,
      maxLines: widget.isPassword ? 1 : widget.maxLines,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon != null
            ? Icon(widget.prefixIcon, size: 20, color: AppConstants.outline)
            : null,
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppConstants.outline,
                ),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              )
            : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OfflineBanner
// ─────────────────────────────────────────────────────────────────────────────

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingGutter,
        vertical: AppConstants.spacingSm,
      ),
      color: AppConstants.warningAmber,
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You\'re offline — changes will sync when connected',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
