import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/program_model.dart';
import '../../../data/models/program_enrollment_request_model.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/app_toast.dart';

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

  @override
  void initState() {
    super.initState();
    _existingRequest = widget.existingRequest;
  }

  bool get _isEnrolled => widget.entry != null;

  String get _programName =>
      widget.entry?.programName ?? widget.program?.programName ?? 'Program';
  String? get _description =>
      widget.entry?.programDescription ?? widget.program?.description;
  String? get _imageUrl =>
      widget.entry?.programImageUrl ?? widget.program?.imageUrl;
  bool get _isSalesProgram =>
      widget.entry?.isSalesProgram ?? widget.program?.isSalesProgram ?? false;
  bool get _isRevenueShare =>
      widget.entry?.isRevenueShare ?? widget.program?.isRevenueShare ?? false;
  String get _programType =>
      widget.entry?.programType ?? widget.program?.programType ?? 'other';
  String? get _distributionCategory =>
      widget.entry?.distributionCategory ?? widget.program?.distributionCategory;

  String get _programTypeLabel {
    final t = _programType;
    if (t.isEmpty) return 'Other';
    return t[0].toUpperCase() + t.substring(1);
  }

  String get _programPurposeLabel => _isSalesProgram ? 'Sales' : 'Distribution';
  String get _benefitTypeLabel => _isRevenueShare ? 'Revenue Share' : 'Grant';

  Future<void> _requestEnrollment() async {
    final programId = widget.program?.id;
    if (programId == null) return;
    setState(() => _isRequesting = true);
    try {
      await _repo.requestEnrollment(programId);
      if (!mounted) return;
      AppToast.show(context, 'Enrollment request submitted.');
      setState(() {
        _existingRequest = ProgramEnrollmentRequest(
          id: 'pending-local',
          programId: programId,
          programName: _programName,
          status: 'pending',
          submittedAt: DateTime.now(),
        );
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
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
                      title: 'Program Details',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoRow(
                            icon: Icons.category_outlined,
                            label: 'Program Type',
                            value: _programTypeLabel,
                          ),
                          _InfoRow(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Program Purpose',
                            value: _programPurposeLabel,
                            isLast: _isSalesProgram,
                          ),
                          if (!_isSalesProgram) ...[
                            _InfoRow(
                              icon: Icons.inventory_2_outlined,
                              label: 'Distribution Category',
                              value: _distributionCategory ?? 'Not specified',
                            ),
                            _InfoRow(
                              icon: Icons.card_giftcard_rounded,
                              label: 'Benefit Type',
                              value: _benefitTypeLabel,
                              isLast: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    _SectionCard(
                      icon: Icons.description_outlined,
                      title: 'About This Program',
                      child: Text(
                        (_description != null && _description!.isNotEmpty)
                            ? _description!
                            : 'No description provided.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppConstants.onSurfaceVariant,
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
              title: 'Program Details',
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
        title: 'Enrollment Status',
        child: Row(
          children: [
            _StatusChip(label: _enrollmentStatusLabel(entry.enrollmentStatus)),
            const SizedBox(width: 8),
            Text(
              'Enrolled ${_formatDate(entry.enrolledAt)}',
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),

      if (_isSalesProgram)
        _SectionCard(
          icon: Icons.storefront_rounded,
          title: 'Product Sales Program',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This program lets you purchase cooperative-stocked products.',
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
              ),
              if (entry.enrollmentStatus == 'active') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'View Available Products',
                    icon: Icons.storefront_rounded,
                    onPressed: () => context.push(
                      AppRoutes.programProductCatalog,
                      extra: {'programId': entry.programId, 'programName': entry.programName},
                    ),
                  ),
                ),
              ],
            ],
          ),
        )
      else ...[
        _SectionCard(
          icon: Icons.local_shipping_outlined,
          title: 'Distribution',
          child: !entry.isDistributed
              ? Text(
                  'Awaiting distribution.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Received ${entry.quantityGiven?.toStringAsFixed(1)}'
                      '${entry.itemUnit != null ? ' ${entry.itemUnit}' : ''}'
                      '${entry.itemName != null ? ' ${entry.itemName}' : ''} '
                      'on ${_formatDate(entry.distributedAt!)}',
                      style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurface),
                    ),
                    if (_isRevenueShare) ...[
                      const SizedBox(height: 8),
                      if (entry.isSettled)
                        Text(
                          'Returned ₱${entry.amountReturned?.toStringAsFixed(2)} on ${_formatDate(entry.settledAt!)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.successGreen,
                          ),
                        )
                      else
                        Text(
                          entry.expectedReturnPercent != null
                              ? 'A ${entry.expectedReturnPercent}% return is due to the cooperative once sold.'
                              : 'A return is due to the cooperative once sold.',
                          style: GoogleFonts.inter(fontSize: 13, color: AppConstants.warningAmber),
                        ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),

        if (entry.distributionOutcome != null) ...[
          _SectionCard(
            icon: Icons.insights_rounded,
            title: 'Outcome',
            child: _OutcomeBody(entry: entry),
          ),
          const SizedBox(height: 16),
        ],
      ],
    ];
  }

  List<Widget> _buildNotEnrolledSections(BuildContext context) {
    final request = _existingRequest;
    return [
      _SectionCard(
        icon: Icons.assignment_turned_in_outlined,
        title: 'Enrollment',
        child: request == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You are not enrolled in this program yet.',
                    style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: _isRequesting ? 'Submitting...' : 'Request Enrollment',
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
                      const Icon(Icons.hourglass_top_rounded,
                          size: 18, color: AppConstants.warningAmber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your enrollment request is pending admin review.',
                          style: GoogleFonts.inter(fontSize: 13, color: AppConstants.warningAmber),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cancel_outlined,
                              size: 18, color: AppConstants.errorRed),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your last request was declined'
                              '${request.adminNotes != null && request.adminNotes!.isNotEmpty ? ': ${request.adminNotes}' : '.'}',
                              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.errorRed),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryButton(
                          label: _isRequesting ? 'Submitting...' : 'Request Again',
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
      case 'withdrawn': return 'Withdrawn';
      case 'completed': return 'Completed';
      default: return 'Active';
    }
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _OutcomeBody extends StatelessWidget {
  final MyProgramEntry entry;
  const _OutcomeBody({required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry.isOutcomeFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This distribution did not succeed and was converted into a loan obligation.',
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.errorRed),
          ),
          if (entry.hasConvertedLoan) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.pushRoute(AppRoutes.myLoans),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text('View in My Loans'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.primaryGreen,
                  side: const BorderSide(color: AppConstants.primaryGreen),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      );
    }
    if (entry.isOutcomeThriving) {
      return Text(
        'This distribution is thriving — a return is expected once sold.',
        style: GoogleFonts.inter(fontSize: 13, color: AppConstants.successGreen),
      );
    }
    return Text(
      'Outcome not yet recorded.',
      style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool isSalesProgram;
  const _HeaderCard({required this.name, this.imageUrl, required this.isSalesProgram});

  @override
  Widget build(BuildContext context) {
    // A purpose-tinted hero band (green for Sales, purple for Distribution)
    // rather than a bare Row on the page's own off-white background —
    // gives the top of the screen some color instead of white-on-white.
    final accent = isSalesProgram ? AppConstants.successGreen : AppConstants.programPurple;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.05)],
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: accent.withValues(alpha: 0.25), width: 1.5),
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: (imageUrl != null && imageUrl!.isNotEmpty)
                ? Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      isSalesProgram ? Icons.storefront_rounded : Icons.volunteer_activism_rounded,
                      color: accent,
                      size: 30,
                    ),
                  )
                : Icon(
                    isSalesProgram ? Icons.storefront_rounded : Icons.volunteer_activism_rounded,
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
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    isSalesProgram ? 'Sales Program' : 'Distribution Program',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: accent),
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
            : Border(bottom: BorderSide(color: AppConstants.outline.withValues(alpha: 0.10))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: AppConstants.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.onSurface),
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
  const _SectionCard({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF455A64).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 2)),
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
                child: Icon(icon, size: 14, color: AppConstants.primaryGreen),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.charcoal),
              ),
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
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.programPurple),
      ),
    );
  }
}
