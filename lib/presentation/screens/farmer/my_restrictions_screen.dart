import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/member_restriction.dart';
import '../../../data/services/feature_restriction_service.dart';
import '../../widgets/feature_restriction_notice.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// What the signed-in Farmer is restricted from right now, and why. Read-only.
/// A restriction only stops NEW activity of that kind; the screen says so once.
class MyRestrictionsScreen extends StatefulWidget {
  const MyRestrictionsScreen({super.key});

  @override
  State<MyRestrictionsScreen> createState() => _MyRestrictionsScreenState();
}

class _MyRestrictionsScreenState extends State<MyRestrictionsScreen> {
  final _service = FeatureRestrictionService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _service.refresh();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final items = _service.restrictions;

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.myRestrictionsTitle,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: _loading && items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : RefreshIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      children: items.isEmpty
                          ? [
                              const SizedBox(height: 60),
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 52,
                                color: AppConstants.successGreen.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                l10n.myRestrictionsEmpty,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: cs.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ]
                          : [
                              Text(
                                l10n.myRestrictionsIntro,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 14),
                              for (final r in items) ...[
                                _RestrictionCard(restriction: r),
                                const SizedBox(height: 12),
                              ],
                            ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RestrictionCard extends StatelessWidget {
  final MyRestriction restriction;
  const _RestrictionCard({required this.restriction});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: AppConstants.warningAmber.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppConstants.warningAmber.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: AppConstants.warningAmber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restriction.feature.label(l10n),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  restrictionReasonText(l10n, restriction.reason),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurface,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  restrictionUntilText(l10n, restriction.endsAt),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
