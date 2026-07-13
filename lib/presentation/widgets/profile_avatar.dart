import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';

/// Shared avatar for both Admin and Farmer profiles — shows the uploaded
/// photo when present, falling back to initials-on-color when there is
/// none or the URL fails to load. Extracted as a standalone widget since
/// "photo, else initials" has no role-specific behavior at all.
///
/// Uses CachedNetworkImage (already a pubspec dependency, previously
/// unused anywhere I've built) rather than a raw Image.network with a
/// manual errorBuilder — this is exactly the caching/placeholder use case
/// that package exists for, and an avatar is re-rendered often enough
/// across screens that caching genuinely matters here.
class ProfileAvatar extends StatelessWidget {
  final String? photoUrl;
  final String displayName;
  final double radius;
  final VoidCallback? onTap;
  final Widget? badge;

  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.displayName,
    this.radius = 40,
    this.onTap,
    this.badge,
  });

  String get _initials {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    final avatar = ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: hasPhoto
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _initialsFallback(),
                errorWidget: (_, __, ___) => _initialsFallback(),
              )
            : _initialsFallback(),
      ),
    );

    final wrapped = badge == null
        ? avatar
        : Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(bottom: -2, right: -2, child: badge!),
            ],
          );

    if (onTap == null) return wrapped;
    return GestureDetector(onTap: onTap, child: wrapped);
  }

  Widget _initialsFallback() {
    return Container(
      color: AppConstants.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.55,
        ),
      ),
    );
  }
}