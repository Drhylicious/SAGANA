import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/program_model.dart';
import '../../../data/models/program_enrollment_request_model.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/feature_restriction_notice.dart';
import '../../../data/models/member_restriction.dart';

/// Shown for every row in My Programs (not just sales-purpose ones — Full
/// Workflow closes the gap where tapping a distribution/benefit program
/// used to do nothing at all) and from Browse Programs for a program the
/// farmer isn't enrolled in yet. Exactly one of [entry] (already
/// enrolled) or [program] (not yet enrolled) is provided by the caller.
class ProgramDetailsScreen extends StatefulWidget {
  final MyProgramEntry? entry;
  final CooperativeProgram? program;
  final ProgramEnrollmentRequest? existingRequest;

  const ProgramDetailsScreen({
    super.key,
    this.entry,
    this.program,
    this.existingRequest,
  });

  @override
  State<ProgramDetailsScreen> createState() => _ProgramDetailsScreenState();
}

class _ProgramDetailsScreenState extends State<ProgramDetailsScreen> {
  final _repo = FarmerProgramRepository();
  bool _isRequesting = false;
  ProgramEnrollmentRequest? _existingRequest;

  // The program's member discount (Product Sales only), for the benefit card.
  double _memberDiscount = 0;

  @override
  void initState() {
    super.initState();
    _existingRequest = widget.existingRequest;
    _loadDiscount();
  }

  Future<void> _loadDiscount() async {
    if (!_isSalesProgram) return;
    final id = widget.entry?.programId ?? widget.program?.id;
    if (id == null) return;
    try {
      final info = await _repo.fetchPricingInfo(id);
      if (mounted) setState(() => _memberDiscount = info.discountPercent);
    } catch (_) {
      // The card is a nicety; the page works without it.
    }
  }

  bool get _isEnrolled => widget.entry != null;

  String get _programName =>
      widget.entry?.programName ??
      widget.program?.programName ??
      AppLocalizations.of(context).adminCalEventProgram;
  String? get _description =>
      widget.entry?.programDescription ?? widget.program?.description;
  String? get _imageUrl =>
      widget.entry?.programImageUrl ?? widget.program?.imageUrl;
  bool get _isSalesProgram =>
      widget.entry?.isSalesProgram ?? widget.program?.isSalesProgram ?? false;
  String get _programType =>
      widget.entry?.programType ?? widget.program?.programType ?? 'other';
  String? get _distributionCategory =>
      widget.entry?.distributionCategory ??
      widget.program?.distributionCategory;

  String get _programTypeLabel {
    final t = _programType;
    if (t.isEmpty) return AppLocalizations.of(context).suspendReasonOther;
    return t[0].toUpperCase() + t.substring(1);
  }

  String get _programPurposeLabel => _isSalesProgram
      ? AppLocalizations.of(context).adminDashStatSalesAllTime
      : AppLocalizations.of(context).balikTangkilikDistributionTab;

  Future<void> _requestEnrollment() async {
    final programId = widget.program?.id;
    if (programId == null) return;
    // A restricted Farmer cannot join a new program; programs already joined carry on.
    if (!await ensureFeatureAvailable(context, RestrictableFeature.programJoin)) return;
    if (!mounted) return;
    setState(() => _isRequesting = true);
    try {
      await _repo.requestEnrollment(programId);
      if (!mounted) return;
      AppToast.show(context, AppLocalizations.of(context).joinRequestSent);
      setState(() {
        _existingRequest = ProgramEnrollmentRequest(
          id: 'pending-local',
          programId: programId,
          programName: _programName,
          status: 'pending',
          submittedAt: DateTime.now(),
        );
      });
    } catch (e, st) {
      if (!mounted) return;
      // The database's own sentence (for example: you already have a request), not the raw exception.
      AppToast.show(
        context,
        friendlyError(
          AppLocalizations.of(context),
          e,
          st,
          AppLocalizations.of(context).adminInvFailedTryAgain,
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  children: [
                    _HeaderCard(
                      name: _programName,
                      imageUrl: _imageUrl,
                      isSalesProgram: _isSalesProgram,
                    ),
                    const SizedBox(height: 16),

                    // Fields already present on the Admin create/edit form
                    // but previously missing here — Program Type and
                    // Purpose always shown; Distribution Category/Benefit
                    // Type only for Distribution-purpose programs (Sales
                    // programs have neither field on the create form
                    // either). Budget is intentionally excluded — it's an
                    // internal cooperative figure, not farmer-facing.
                    _SectionCard(
                      icon: Icons.info_outline_rounded,
                      title: AppLocalizations.of(context).enhProgramDetails,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoRow(
                            icon: Icons.category_outlined,
                            label: AppLocalizations.of(context).enhProgramType,
                            value: _programTypeLabel,
                          ),
                          _InfoRow(
                            icon: Icons.swap_horiz_rounded,
                            label: AppLocalizations.of(
                              context,
                            ).enhProgramPurpose459,
                            value: _programPurposeLabel,
                            isLast: _isSalesProgram,
                          ),
                          if (!_isSalesProgram)
                            _InfoRow(
                              icon: Icons.inventory_2_outlined,
                              label: AppLocalizations.of(
                                context,
                              ).enhDistributionCategory,
                              value:
                                  _distributionCategory ??
                                  AppLocalizations.of(
                                    context,
                                  ).commonNotSpecified,
                              isLast: true,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_isSalesProgram && _memberDiscount > 0) ...[
                      _SectionCard(
                        icon: Icons.local_offer_outlined,
                        title: AppLocalizations.of(
                          context,
                        ).catMemberBenefitTitle,
                        child: Text(
                          _isEnrolled
                              ? AppLocalizations.of(
                                  context,
                                ).catMemberBenefitEnrolled(
                                  _memberDiscount ==
                                          _memberDiscount.roundToDouble()
                                      ? _memberDiscount.toStringAsFixed(0)
                                      : _memberDiscount.toStringAsFixed(1),
                                )
                              : AppLocalizations.of(
                                  context,
                                ).catMemberBenefitNotEnrolled(
                                  _memberDiscount ==
                                          _memberDiscount.roundToDouble()
                                      ? _memberDiscount.toStringAsFixed(0)
                                      : _memberDiscount.toStringAsFixed(1),
                                ),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppConstants.successGreen,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    _SectionCard(
                      icon: Icons.description_outlined,
                      title: AppLocalizations.of(context).enhAboutThisProgram,
                      child: Text(
                        (_description != null && _description!.isNotEmpty)
                            ? _description!
                            : AppLocalizations.of(
                                context,
                              ).enhNoDescriptionProvided,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_isEnrolled) ..._buildEnrolledSections(context),
                    if (!_isEnrolled) ..._buildNotEnrolledSections(context),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: AppLocalizations.of(context).enhProgramDetails,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEnrolledSections(BuildContext context) {
    final entry = widget.entry!;
    return [
      _SectionCard(
        icon: Icons.how_to_reg_rounded,
        title: AppLocalizations.of(context).joinStatusTitle,
        child: Row(
          children: [
            _StatusChip(label: _enrollmentStatusLabel(entry.enrollmentStatus)),
            const SizedBox(width: 8),
            Flexible(child: Text(
              AppLocalizations.of(
                context,
              ).farmerProgEnrolledOn(_formatDate(entry.enrolledAt)),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )),
          ],
        ),
      ),
      const SizedBox(height: 16),

      if (_isSalesProgram)
        _SectionCard(
          icon: Icons.storefront_rounded,
          title: AppLocalizations.of(context).reportsYearSettingsProgram,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(
                  context,
                ).enhThisProgramLetsYouPurchaseCooperativeStockedProducts,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).uoProductsInMarketplace,
                key: const Key('productsInMarketplace'),
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        )
      else ...[
        _SectionCard(
          icon: Icons.local_shipping_outlined,
          title: AppLocalizations.of(context).balikTangkilikDistributionTab,
          child: !entry.isDistributed
              ? Text(
                  AppLocalizations.of(context).enhAwaitingDistribution,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // The unit is the Inventory item's, the same everywhere it is shown.
                      AppLocalizations.of(context).farmerProgReceivedLine(
                        '${entry.quantityGiven != null ? formatQuantity(entry.quantityGiven!) : ''}'
                                '${entry.itemUnit != null ? ' ${entry.itemUnit}' : ''}'
                                '${entry.itemName != null ? ' ${entry.itemName}' : ''}'
                            .trim(),
                        _formatDate(entry.distributedAt!),
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  // Every Farmer can open a Product Sales program's products, enrolled or not;
  // enrollment only decides the price.
  Widget _productsCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SectionCard(
      icon: Icons.storefront_rounded,
      title: l10n.catProductsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.catShopNote,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.uoProductsInMarketplace,
            key: const Key('productsInMarketplace'),
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNotEnrolledSections(BuildContext context) {
    final request = _existingRequest;
    return [
      if (_isSalesProgram) ...[
        _productsCard(context),
        const SizedBox(height: 16),
      ],
      _SectionCard(
        icon: Icons.assignment_turned_in_outlined,
        title: AppLocalizations.of(context).joinSectionTitle,
        child: request == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).joinNotYet,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: _isRequesting
                          ? AppLocalizations.of(context).joinSending
                          : AppLocalizations.of(context).joinRequestAction,
                      isLoading: _isRequesting,
                      icon: Icons.send_rounded,
                      onPressed: _isRequesting ? null : _requestEnrollment,
                    ),
                  ),
                ],
              )
            : request.isPending
            ? Row(
                children: [
                  const Icon(
                    Icons.hourglass_top_rounded,
                    size: 18,
                    color: AppConstants.warningAmber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).joinRequestPending,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppConstants.warningAmber,
                      ),
                    ),
                  ),
                ],
              )
            : request.isApproved
            ? Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppConstants.successGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).joinRequestApproved,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppConstants.successGreen,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cancel_outlined,
                        size: 18,
                        color: AppConstants.errorRed,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          request.adminNotes != null &&
                                  request.adminNotes!.isNotEmpty
                              ? AppLocalizations.of(
                                  context,
                                ).joinLastClosedWhy(request.adminNotes!)
                              : AppLocalizations.of(context).joinLastClosed,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppConstants.errorRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: _isRequesting
                          ? AppLocalizations.of(context).joinSending
                          : AppLocalizations.of(context).joinRequestAgain,
                      isLoading: _isRequesting,
                      icon: Icons.send_rounded,
                      onPressed: _isRequesting ? null : _requestEnrollment,
                    ),
                  ),
                ],
              ),
      ),
    ];
  }

  String _enrollmentStatusLabel(String status) {
    switch (status) {
      case 'withdrawn':
        return AppLocalizations.of(context).listingStateWithdrawn;
      case 'completed':
        return AppLocalizations.of(context).statCompleted;
      default:
        return AppLocalizations.of(context).farmerDetailsProgStatusActive;
    }
  }

  String _formatDate(DateTime dt) {
    final months = [
      AppLocalizations.of(context).enhJan,
      AppLocalizations.of(context).enhFeb,
      AppLocalizations.of(context).enhMar,
      AppLocalizations.of(context).enhApr,
      AppLocalizations.of(context).adminCalMonthMay,
      AppLocalizations.of(context).enhJun,
      AppLocalizations.of(context).enhJul,
      AppLocalizations.of(context).enhAug,
      AppLocalizations.of(context).enhSep,
      AppLocalizations.of(context).enhOct,
      AppLocalizations.of(context).enhNov,
      AppLocalizations.of(context).enhDec,
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _HeaderCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool isSalesProgram;
  const _HeaderCard({
    required this.name,
    this.imageUrl,
    required this.isSalesProgram,
  });

  @override
  Widget build(BuildContext context) {
    // A purpose-tinted hero band (green for Sales, purple for Distribution)
    // rather than a bare Row on the page's own off-white background —
    // gives the top of the screen some color instead of white-on-white.
    final accent = isSalesProgram
        ? AppConstants.successGreen
        : AppConstants.programPurple;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.saganaColors.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(
                color: accent.withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: (imageUrl != null && imageUrl!.isNotEmpty)
                ? Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      isSalesProgram
                          ? Icons.storefront_rounded
                          : Icons.volunteer_activism_rounded,
                      color: accent,
                      size: 30,
                    ),
                  )
                : Icon(
                    isSalesProgram
                        ? Icons.storefront_rounded
                        : Icons.volunteer_activism_rounded,
                    color: accent,
                    size: 30,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                  child: Text(
                    isSalesProgram
                        ? AppLocalizations.of(
                            context,
                          ).farmerDetailsProgSalesPurpose
                        : AppLocalizations.of(
                            context,
                          ).farmerDetailsProgDistributionPurpose,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.10),
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(
                  icon,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              )),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.programPurple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppConstants.programPurple,
        ),
      ),
    );
  }
}
