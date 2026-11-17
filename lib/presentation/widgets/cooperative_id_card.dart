import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/buyer_profile_model.dart' show buyerGenderLabel;
import '../../data/repositories/account_management_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/hive_service.dart';
import '../../data/services/staff_permission_service.dart';
import 'account_card.dart' show accountStatusColor, accountStatusLabel;
import 'app_dialog.dart';
import 'officer_access_sheet.dart';
import 'profile_avatar.dart';
import 'staff_access_matrix.dart' show staffModuleLabel;

/// Opens the SAGANA Cooperative ID Card for one account in Manage Accounts: the
/// front shows who the person is, tapping the card turns it over to the details.
/// The Manager also edits an Officer's module access from the back of that
/// Officer's card; nobody else does (the database refuses it too).
Future<void> showCooperativeIdCard(BuildContext context, AccountEntry account) {
  return AppDialog.show<void>(
    context: context,
    child: _IdCardDialog(account: account),
  );
}

String _roleLabel(AppLocalizations l10n, String role) {
  switch (role) {
    case 'admin':
      return l10n.staffRoleManager;
    case 'officer':
      return l10n.staffRoleOfficer;
    default:
      return l10n.idCardRoleFarmer;
  }
}

class _IdCardDialog extends StatefulWidget {
  const _IdCardDialog({required this.account});

  final AccountEntry account;

  @override
  State<_IdCardDialog> createState() => _IdCardDialogState();
}

class _IdCardDialogState extends State<_IdCardDialog> with SingleTickerProviderStateMixin {
  final _repo = AccountManagementRepository();
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<double> _turn = CurvedAnimation(parent: _flip, curve: Curves.easeInOutCubic);

  AccountCardDetails? _details;
  Map<StaffModule, StaffAccess>? _access;
  bool _accessFailed = false;

  AccountEntry get _a => widget.account;
  bool get _viewerIsManager => HiveService.getUserRole() == 'admin';
  bool get _isSelf => AuthService.currentUser?.id == _a.userId;

  /// The module chips: the Manager sees every Officer's, an Officer only their own.
  bool get _showsAccess => _a.role == 'officer' && (_viewerIsManager || _isSelf);

  /// Only the Manager edits, and never their own or a Farmer's.
  bool get _canEditAccess => _a.role == 'officer' && _viewerIsManager && !_isSelf;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    if (_showsAccess) _loadAccess();
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    final d = await _repo.fetchCardDetails(_a);
    if (mounted) setState(() => _details = d);
  }

  Future<void> _loadAccess() async {
    try {
      final access = await _repo.fetchOfficerAccess(_a.userId);
      if (!mounted) return;
      setState(() {
        _access = {for (final m in StaffModule.values) m: access[m] ?? StaffAccess.view};
        _accessFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _accessFailed = true);
    }
  }

  void _toggle() {
    if (_flip.isAnimating) return;
    _flip.status == AnimationStatus.completed ? _flip.reverse() : _flip.forward();
  }

  Future<void> _editAccess() async {
    final saved = await showOfficerAccessSheet(
      context: context,
      userId: _a.userId,
      officerName: _a.name,
    );
    if (saved == true) _loadAccess();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = math.min(size.width - 40, 360.0);
    final height = math.min(size.height - 150, 560.0);

    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: width,
              height: height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: AnimatedBuilder(
                  animation: _turn,
                  builder: (context, _) {
                    final angle = _turn.value * math.pi;
                    final showFront = angle <= math.pi / 2;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(angle),
                      child: showFront
                          ? _front(context)
                          // The back is turned half-way round again so it reads the right way.
                          : Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(math.pi),
                              child: _back(context),
                            ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: Icon(
                  Icons.close_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared pieces ─────────────────────────────────────────────────────────

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(26),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 12)),
    ],
  );

  Widget _brandBar(AppLocalizations l10n, {required double height, Widget? trailing}) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        gradient: AppConstants.splashGradient,
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Image.asset('assets/images/sagana_icon.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SAGANA',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  color: Colors.white,
                ),
              ),
              Text(
                l10n.idCardSubtitle,
                style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.82)),
              ),
            ],
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _pill(String text, {required Color color, Color? textColor, bool filled = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor ?? (filled ? Colors.white : color),
        ),
      ),
    );
  }

  String _date(AppLocalizations l10n, DateTime d, {bool full = true}) {
    try {
      return (full ? DateFormat.yMMMMd(l10n.localeName) : DateFormat.yMMM(l10n.localeName)).format(d);
    } catch (_) {
      final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return full ? iso : iso.substring(0, 7);
    }
  }

  /// "Prefer not to say", never the stored code ("prefer_not_to_say").
  String _gender(AppLocalizations l10n, String value) {
    final label = buyerGenderLabel(l10n, value.toLowerCase().trim());
    if (label != null) return label;
    final words = value.replaceAll('_', ' ').trim();
    return words.isEmpty ? value : '${words[0].toUpperCase()}${words.substring(1).toLowerCase()}';
  }

  // ── Front ─────────────────────────────────────────────────────────────────

  Widget _front(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final d = _details;
    final statusColor = accountStatusColor(cs, _a.effectiveStatus);

    // Under the name: a staff member's position. A Farmer's card shows nothing here.
    final String? line = (_a.role != 'farmer' && (d?.position ?? '').isNotEmpty) ? d!.position : null;

    return Container(
      decoration: _cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _brandBar(
            l10n,
            height: 118,
            trailing: _pill(_roleLabel(l10n, _a.role), color: AppConstants.amber, textColor: AppConstants.primaryGreen),
          ),
          Transform.translate(
            offset: const Offset(0, -46),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 12)],
              ),
              child: ProfileAvatar(photoUrl: _a.profilePhotoUrl, displayName: _a.name, radius: 52),
            ),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(
                      _a.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _pill(accountStatusLabel(l10n, _a), color: statusColor, filled: false),
                    if (line != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        line,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.flip_rounded, size: 16, color: cs.outline),
                        const SizedBox(width: 6),
                        Flexible(child: Text(
                          l10n.idCardTapToFlip,
                          style: GoogleFonts.inter(fontSize: 11.5, color: cs.outline),
                        )),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Back ──────────────────────────────────────────────────────────────────

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    final cs = Theme.of(context).colorScheme;
    final shown = rows.where((r) => r is! SizedBox).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Divider(height: 8, color: cs.outline.withValues(alpha: 0.18)),
          ...shown,
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String? value, {Widget? trailing, bool showWhenEmpty = false}) {
    if ((value == null || value.isEmpty) && !showWhenEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  (value == null || value.isEmpty) ? AppLocalizations.of(context).idCardNotSet : value,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: (value == null || value.isEmpty) ? cs.outline : cs.onSurface,
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _back(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final d = _details;

    Widget body;
    if (d == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    } else {
      final hectares = d.farmHectares;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(context, _a.role == 'farmer' ? l10n.idCardContactInfo : l10n.idCardContact, [
            _row(context, l10n.idCardPhone, _a.phone, showWhenEmpty: true),
            _row(
              context,
              l10n.idCardEmail,
              _a.email,
              showWhenEmpty: true,
              trailing: _a.email == null
                  ? null
                  : _pill(
                      d.emailVerified ? l10n.idCardVerified : l10n.idCardNotVerified,
                      color: d.emailVerified ? AppConstants.successGreen : cs.outline,
                      filled: false,
                    ),
            ),
          ]),
          _section(context, _a.role == 'farmer' ? l10n.idCardPersonalInfo : l10n.idCardPersonal, [
            _row(
              context,
              l10n.idCardBirthDate,
              d.dateOfBirth == null ? null : _date(l10n, d.dateOfBirth!),
              showWhenEmpty: _a.role != 'admin' || _viewerIsManager,
            ),
            _row(
              context,
              l10n.idCardGender,
              d.gender == null ? null : _gender(l10n, d.gender!),
              showWhenEmpty: _a.role != 'admin' || _viewerIsManager,
            ),
          ]),
          _section(context, l10n.idCardAddress, [
            if (_a.role == 'farmer')
              _row(context, l10n.idCardFullAddress, d.address, showWhenEmpty: true)
            else
              _row(context, l10n.idCardAddress, d.address),
          ]),
          if (_a.role == 'farmer')
            _section(context, l10n.idCardFarm, [
              _row(context, l10n.idCardFarmAddress, d.farmAddress, showWhenEmpty: true),
              _row(context, l10n.idCardFarmName, d.farmName, showWhenEmpty: true),
              _row(
                context,
                l10n.idCardFarmSize,
                hectares == null ? null : l10n.idCardFarmSizeValue(hectares.toStringAsFixed(hectares % 1 == 0 ? 0 : 2)),
                showWhenEmpty: true,
              ),
              _row(
                context,
                l10n.idCardYearsFarming,
                d.yearsFarming == null ? null : l10n.farmerDetailsYearsValue(d.yearsFarming!),
                showWhenEmpty: true,
              ),
              _row(context, l10n.idCardCrops, d.crops.isEmpty ? null : d.crops.join(', '), showWhenEmpty: true),
            ]),
          _section(context, _a.role == 'farmer' ? l10n.idCardAccountInfo : l10n.idCardAccount, [
            _row(
              context,
              l10n.idCardDateJoined,
              d.memberSince == null ? null : _date(l10n, d.memberSince!),
              showWhenEmpty: true,
            ),
            _row(
              context,
              l10n.idCardLastActive,
              _a.lastActiveAt == null ? null : _date(l10n, _a.lastActiveAt!.toLocal()),
              showWhenEmpty: true,
            ),
          ]),
          if (_showsAccess) _accessSection(context, l10n, cs),
          if (d.failedParts > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.idCardLoadError,
                style: GoogleFonts.inter(fontSize: 11, color: cs.outline, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      );
    }

    return Container(
      decoration: _cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _brandBar(
            l10n,
            height: 62,
            trailing: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _pill(_roleLabel(l10n, _a.role), color: AppConstants.amber, textColor: AppConstants.primaryGreen),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: body,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flip_rounded, size: 16, color: cs.outline),
                const SizedBox(width: 6),
                Flexible(child: Text(l10n.idCardTapToFlipBack, style: GoogleFonts.inter(fontSize: 11.5, color: cs.outline))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accessSection(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final access = _access;
    Widget content;
    if (_accessFailed) {
      content = Text(l10n.staffAccessLoadError, style: GoogleFonts.inter(fontSize: 12, color: cs.outline));
    } else if (access == null) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else {
      content = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in StaffModule.values)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (access[m] == StaffAccess.manage ? AppConstants.primaryGreen : cs.outline).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                border: Border.all(
                  color: (access[m] == StaffAccess.manage ? AppConstants.primaryGreen : cs.outline).withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                '${staffModuleLabel(l10n, m)} · ${access[m] == StaffAccess.manage ? l10n.staffAccessManage : l10n.staffAccessView}',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: access[m] == StaffAccess.manage
                      ? Theme.of(context).colorScheme.primary
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.staffAccessSectionTitle.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Divider(height: 8, color: cs.outline.withValues(alpha: 0.18)),
          const SizedBox(height: 4),
          content,
          if (_canEditAccess) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: access == null ? null : _editAccess,
                icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                label: Text(l10n.staffAccessEdit, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
