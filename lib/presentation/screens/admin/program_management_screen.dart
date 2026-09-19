import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../data/models/program_model.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/material_list_tile.dart';
import '../../widgets/report_summary_widgets.dart' show ReportIconStatCard, ReportSectionCard;

// ── Screen ───────────────────────────────────────────────────────────────────

class ProgramManagementScreen extends StatefulWidget {
  const ProgramManagementScreen({super.key});

  @override
  State<ProgramManagementScreen> createState() =>
      _ProgramManagementScreenState();
}

class _ProgramManagementScreenState extends State<ProgramManagementScreen> {
  final _repo = ProgramRepository();
  final _categoryRepo = CategoryRepository();

  List<CooperativeProgram> _programs = [];
  List<String> _inventoryCategories = [];
  int _pendingPurchaseCount = 0;
  bool _isLoading = true;
  bool _isOnline = true;

  static const _statusOptions = ['active', 'completed', 'suspended'];

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen(
        (v) { if (mounted) setState(() => _isOnline = v); });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchPrograms(),
      _categoryRepo.fetchInventoryCategories(),
      _repo.fetchPurchasesByStatus('pending'),
    ]);
    if (!mounted) return;
    setState(() {
      _programs = results[0] as List<CooperativeProgram>;
      _inventoryCategories = results[1] as List<String>;
      _pendingPurchaseCount = (results[2] as List<ProgramPurchase>).length;
      _isLoading = false;
    });
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'crop':       return AppConstants.primaryGreen;
      case 'peanut':     return AppConstants.warningAmber;
      case 'production': return AppConstants.buyerBlue;
      case 'livestock':  return const Color(0xFF8D6E63);
      default:           return AppConstants.programPurple;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'crop':       return Icons.grass_rounded;
      case 'peanut':     return Icons.eco_rounded;
      case 'production': return Icons.factory_rounded;
      case 'livestock':  return Icons.pets_rounded;
      default:           return Icons.star_rounded;
    }
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'active':    return l10n.programMgmtStatusActive;
      case 'completed': return l10n.programMgmtStatusCompleted;
      case 'suspended': return l10n.programMgmtStatusSuspended;
      default:          return status.toUpperCase();
    }
  }

  String _statusLabelTitleCase(AppLocalizations l10n, String status) {
    switch (status) {
      case 'active':    return l10n.programMgmtStatusActiveTc;
      case 'completed': return l10n.programMgmtStatusCompletedTc;
      case 'suspended': return l10n.programMgmtStatusSuspendedTc;
      default:          return status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);
    }
  }

  String _memberCountLabel(AppLocalizations l10n, int count) {
    return count == 1
        ? l10n.programMgmtMemberCountOne(count)
        : l10n.programMgmtMemberCountOther(count);
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'active':    return AppConstants.successGreen;
      case 'completed': return AppConstants.buyerBlue;
      case 'suspended': return AppConstants.errorRed;
      default:          return cs.outline;
    }
  }

  // ─── Delete program ─────────────────────────────────────────────────────

  void _confirmDeleteProgram(CooperativeProgram program) async {
    final l10n = AppLocalizations.of(context);
    final impact = await _repo.fetchProgramDeleteImpact(program.id);
    if (!mounted) return;

    final impactMessage = impact.checkFailed
        ? l10n.programMgmtDeleteImpactUnknown
        : impact.memberCount == 0
            ? l10n.programMgmtDeleteImpactSafe
            : '${_memberCountLabel(l10n, impact.memberCount)}'
                '${impact.distributedCount > 0 ? l10n.programMgmtDistributedCountClause(impact.distributedCount) : ''}'
                '${l10n.programMgmtDeleteImpactSuffix}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.programMgmtDeleteTitle(program.programName),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(impactMessage, style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.commonDelete, style: const TextStyle(color: AppConstants.errorRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await _repo.deleteProgram(program.id);
    if (!mounted) return;
    if (ok) _load();
    AppToast.show(
      context,
      ok ? l10n.programMgmtDeleted : l10n.programMgmtDeleteFailed,
      isError: !ok,
    );
  }

  void _showProgramSheet(CooperativeProgram? existing) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.programName ?? '');
    final typeCtrl = TextEditingController(text: existing?.programType ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final budgetCtrl = TextEditingController(
        text: existing?.budget != null ? existing!.budget!.toStringAsFixed(2) : '');
    final returnPercentCtrl = TextEditingController(
        text: existing?.expectedReturnPercent?.toString() ?? '');
    String selectedStatus = existing?.status ?? 'active';
    String selectedBenefitType = existing?.benefitType ?? 'grant';
    String? selectedDistributionCategory = existing?.distributionCategory;
    String selectedPurpose = existing?.programPurpose ?? 'distribution';
    bool isSaving = false;
    Uint8List? pickedImageBytes;
    String? pickedImageExt;
    String? existingImageUrl = existing?.imageUrl;
    var categoryOptions = List<String>.of(_inventoryCategories);

    showManagementModal(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return StatefulBuilder(builder: (ctx, setSheet) {
          // Upload-only — no camera capture, a program isn't a physical item.
          Future<void> pickImage() async {
            final picked = await ImagePicker()
                .pickImage(source: ImageSource.gallery, imageQuality: 80);
            if (picked == null) return;
            final bytes = await picked.readAsBytes();
            setSheet(() {
              pickedImageBytes = bytes;
              pickedImageExt = picked.name.contains('.')
                  ? picked.name.split('.').last.toLowerCase()
                  : 'jpg';
            });
          }

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            final budget = double.tryParse(budgetCtrl.text);
            setSheet(() => isSaving = true);
            String? imageUrl = existingImageUrl;
            if (pickedImageBytes != null) {
              imageUrl = await _repo.uploadProgramImage(
                  pickedImageBytes!, pickedImageExt ?? 'jpg');
            }
            bool ok;
            if (existing == null) {
              try {
                ok = await _repo.createProgram(
                  name: nameCtrl.text,
                  type: typeCtrl.text.trim(),
                  benefitType: selectedBenefitType,
                  expectedReturnPercent: double.tryParse(returnPercentCtrl.text),
                  description: descCtrl.text.isEmpty ? null : descCtrl.text,
                  budget: budget,
                  distributionCategory: selectedDistributionCategory,
                  programPurpose: selectedPurpose,
                  imageUrl: imageUrl,
                );
              } on ProgramDuplicateNameException catch (e) {
                setSheet(() => isSaving = false);
                if (!ctx.mounted) return;
                AppToast.show(ctx, 'A program named "${e.programName}" already exists.', isError: true);
                return;
              }
            } else {
              ok = await _repo.updateProgram(
                id: existing.id,
                name: nameCtrl.text,
                type: typeCtrl.text.trim(),
                benefitType: selectedBenefitType,
                expectedReturnPercent: double.tryParse(returnPercentCtrl.text),
                description: descCtrl.text.isEmpty ? null : descCtrl.text,
                budget: budget,
                status: selectedStatus,
                distributionCategory: selectedDistributionCategory,
                programPurpose: existing.programPurpose,
                imageUrl: imageUrl,
              );
            }
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            if (!mounted) return;
            AppToast.show(
              context,
              ok
                  ? existing == null
                      ? l10n.programMgmtCreated
                      : l10n.programMgmtUpdated
                  : l10n.adminInvFailedTryAgain,
              isError: !ok,
            );
          }

          return ManagementModalShell(
            title: existing == null ? l10n.programMgmtNewTitle : l10n.programMgmtEditTitle,
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.programMgmtNameLabel,
                      hintText: l10n.programMgmtNameHint,
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return l10n.programMgmtNameRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: typeCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.programMgmtTypeLabel,
                      hintText: l10n.programMgmtTypeHint,
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return l10n.programMgmtTypeRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Program Photo (optional)',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: pickImage,
                    child: Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                        border: Border.all(
                            color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.2)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: pickedImageBytes != null
                          ? Image.memory(pickedImageBytes!, fit: BoxFit.cover)
                          : (existingImageUrl != null && existingImageUrl!.isNotEmpty
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(existingImageUrl!, fit: BoxFit.cover),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: GestureDetector(
                                        onTap: () => setSheet(() {
                                          existingImageUrl = null;
                                          pickedImageBytes = null;
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close_rounded,
                                              size: 16, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate_outlined,
                                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                                    const SizedBox(height: 4),
                                    Text('Tap to upload a photo',
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                                  ],
                                )),
                    ),
                  ),
                  // Purpose is fixed once a program exists — switching an
                  // existing distribution program (which may already have
                  // members/distributions recorded) into a sales program,
                  // or vice versa, is a data-integrity question this
                  // screen deliberately doesn't try to handle.
                  if (existing == null) ...[
                    const SizedBox(height: 12),
                    AppDropdownField<String>(
                      value: selectedPurpose,
                      hintText: 'Select a purpose',
                      labelText: 'Program Purpose *',
                      helperText: 'Distribution: the existing benefit/loan '
                          'workflow. Sales: the cooperative sells its own '
                          'products to enrolled members.',
                      items: const ['distribution', 'sales'],
                      itemLabel: (v) => v == 'sales'
                          ? 'Product Sales'
                          : 'Distribution (benefit/loan)',
                      onChanged: (v) => setSheet(() => selectedPurpose = v ?? selectedPurpose),
                      validator: (v) => v == null ? 'Purpose is required' : null,
                    ),
                  ],
                  if (selectedPurpose == 'distribution') ...[
                    const SizedBox(height: 12),
                    AppDropdownField<String>(
                      value: selectedDistributionCategory,
                      hintText: l10n.programMgmtSelectCategoryHint,
                      labelText: l10n.programMgmtDistributesFromLabel,
                      helperText: l10n.programMgmtDistributesFromHelper,
                      items: categoryOptions,
                      itemLabel: (c) => c,
                      onChanged: (v) => setSheet(() => selectedDistributionCategory = v),
                      validator: (v) => v == null ? l10n.programMgmtCategoryRequired : null,
                    ),
                    const SizedBox(height: 12),
                    AppDropdownField<String>(
                      value: selectedBenefitType,
                      hintText: l10n.programMgmtSelectBenefitTypeHint,
                      labelText: l10n.programMgmtBenefitTypeLabel,
                      items: const ['grant', 'revenue_share'],
                      itemLabel: (v) => v == 'grant'
                          ? l10n.programMgmtBenefitGrant
                          : l10n.programMgmtBenefitRevenueShare,
                      onChanged: (v) => setSheet(() => selectedBenefitType = v ?? selectedBenefitType),
                      validator: (v) => v == null ? l10n.programMgmtBenefitTypeRequired : null,
                    ),
                  ],
                  if (selectedPurpose == 'distribution' && selectedBenefitType == 'revenue_share') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: returnPercentCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.programMgmtExpectedReturnLabel,
                        hintText: l10n.programMgmtExpectedReturnHint,
                        suffixText: '%',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                    ),
                  ],
                  if (existing != null) ...[
                    const SizedBox(height: 12),
                    AppDropdownField<String>(
                      value: selectedStatus,
                      hintText: l10n.programMgmtStatusLabel,
                      labelText: l10n.programMgmtStatusLabel,
                      items: _statusOptions,
                      itemLabel: (s) => _statusLabelTitleCase(l10n, s),
                      onChanged: (v) => setSheet(() => selectedStatus = v ?? selectedStatus),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: budgetCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.programMgmtBudgetLabel,
                      hintText: '0.00',
                      prefixText: '₱ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) return null;
                      if (!isValidCurrencyValue(value)) return l10n.adminInvEnterValidAmount;
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.programMgmtDescOptionalLabel,
                      hintText: l10n.programMgmtDescHint,
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving
                  ? l10n.saving
                  : existing == null
                      ? l10n.programMgmtCreateAction
                      : l10n.saveChanges,
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  void _showMembersSheet(CooperativeProgram program) {
    showManagementModal(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return DefaultTabController(
          length: 2,
          child: ManagementModalShell(
            title: program.programName,
            bodyIsScrollable: true,
            body: Column(
              children: [
                TabBar(
                  tabs: [
                    Tab(text: l10n.programMgmtTabMembers),
                    Tab(text: l10n.programMgmtTabActivities),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ProgramMembersModalBody(program: program, repo: _repo),
                      _ProgramActivitiesTab(program: program, repo: _repo),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showProductsSheet(CooperativeProgram program) {
    showManagementModal(
      context: context,
      builder: (ctx) => ManagementModalShell(
        title: program.programName,
        subtitle: 'Products available for purchase in this program',
        bodyIsScrollable: true,
        body: _ProgramProductsModalBody(program: program, repo: _repo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _isOnline
          ? FloatingActionButton(
              onPressed: () => _showProgramSheet(null),
              backgroundColor: AppConstants.primaryGreen,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
      body: Column(
        children: [
          // Top bar
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64 + MediaQuery.of(context).padding.top,
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                    left: 8, right: 8),
                decoration: BoxDecoration(
                  color: sagana.glassBackground,
                  border: Border(
                      bottom: BorderSide(color: sagana.glassBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: cs.onSurface),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        l10n.programMgmtTitle,
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface),
                      ),
                    ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: Icon(Icons.receipt_long_rounded, color: cs.onSurface),
                          tooltip: 'Purchase Requests',
                          onPressed: () => context
                              .push(AppRoutes.programPurchaseReview)
                              .then((_) => _load()),
                        ),
                        if (_pendingPurchaseCount > 0)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppConstants.errorRed,
                                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                              ),
                              child: Text(
                                '$_pendingPurchaseCount',
                                style: GoogleFonts.inter(
                                    fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (!_isOnline)
            Container(
              color: AppConstants.warningAmber,
              padding: const EdgeInsets.symmetric(
                  vertical: 6, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 14, color: AppConstants.charcoal),
                  const SizedBox(width: 6),
                  Text(l10n.cropMgmtOfflineNotice,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.charcoal)),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryGreen,
                        strokeWidth: 2))
                : RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: _load,
                    // Single outer scrollable so the KPI cards scroll away
                    // with the list below them, instead of staying pinned
                    // as static siblings above it (per your Item B request
                    // — matches Crop Management / Price Management's own
                    // KPI-inside-the-list pattern).
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        // KPI cards (dashboard.md section 5) — a
                        // responsively-laid-out set (2/4 cards → 2x2 grid,
                        // 3/5 cards → horizontal scroll row) since Total
                        // Programs + Active + Product Sales + Enrollment +
                        // Distribution Benefit/Loans is an odd count of 5.
                        if (_programs.isNotEmpty) ...[
                          ReportSectionCard(
                            title: 'Program Overview',
                            icon: Icons.star_rounded,
                            accent: AppConstants.programPurple,
                            child: _buildKpiSection([
                            ReportIconStatCard(
                              icon: Icons.star_rounded,
                              accent: AppConstants.programPurple,
                              label: 'Total Programs',
                              value: '${_programs.length}',
                            ),
                            ReportIconStatCard(
                              icon: Icons.play_circle_fill_rounded,
                              accent: AppConstants.successGreen,
                              label: 'Active',
                              value:
                                  '${_programs.where((p) => p.status == 'active').length}',
                            ),
                            ReportIconStatCard(
                              icon: Icons.storefront_rounded,
                              accent: AppConstants.successGreen,
                              label: 'Product Sales',
                              value:
                                  '${_programs.where((p) => p.isSalesProgram).length}',
                            ),
                            ReportIconStatCard(
                              icon: Icons.request_quote_rounded,
                              accent: AppConstants.buyerBlue,
                              label: 'Distribution Benefit/Loans',
                              value:
                                  '${_programs.where((p) => p.programPurpose == 'distribution').length}',
                            ),
                            ReportIconStatCard(
                              icon: Icons.groups_rounded,
                              accent: AppConstants.primaryGreen,
                              label: l10n.marketLinkKpiEnrolled,
                              value:
                                  // Enrollment across every program purpose —
                                  // memberCount is already purpose-agnostic (it's
                                  // just each program's active program_members
                                  // count), so Distribution and Product Sales
                                  // enrollments are summed together here, not
                                  // hardcoded to one purpose.
                                  '${_programs.fold<int>(0, (sum, p) => sum + p.memberCount)}',
                            ),
                          ]),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_programs.isEmpty)
                          Column(children: [
                            const SizedBox(height: 60),
                            Center(
                              child: Column(children: [
                                Icon(Icons.people_alt_rounded,
                                    size: 48,
                                    color: cs.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(l10n.programMgmtNoProgramsYet,
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant)),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () =>
                                      _showProgramSheet(null),
                                  child: Text(l10n.programMgmtCreateFirst),
                                ),
                              ]),
                            ),
                          ])
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: _programs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) {
                              final p = _programs[i];
                              final color = _typeColor(p.programType);
                              final icon = _typeIcon(p.programType);
                              final statusColor =
                                  _statusColor(p.status, cs);

                              return Container(
                                decoration: BoxDecoration(
                                  color: sagana.cardBackground,
                                  borderRadius:
                                      BorderRadius.circular(AppConstants.radiusLg),
                                  border: Border.all(
                                      color: cs.outline.withValues(alpha: 0.10)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        width: 4,
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(AppConstants.radiusLg),
                                            bottomLeft: Radius.circular(AppConstants.radiusLg),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                Container(
                                                  // Matches Loan Item Catalog's approved 68x68
                                                  // rounded-square presentation — was 40x40, too
                                                  // small to actually see the photo.
                                                  width: 68,
                                                  height: 68,
                                                  decoration: BoxDecoration(
                                                    color: color.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: (p.imageUrl != null && p.imageUrl!.isNotEmpty)
                                                      ? Image.network(
                                                          p.imageUrl!,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) =>
                                                              Icon(icon, color: color, size: 28),
                                                        )
                                                      : Icon(icon, color: color, size: 28),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        p.programName,
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w700,
                                                          color: cs.onSurface,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${p.programType.isEmpty ? l10n.programMgmtCustomProgram : p.programType} · ${p.seasonYear}',
                                                        style: GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: cs.onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: statusColor.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                                                  ),
                                                  child: Text(
                                                    _statusLabel(l10n, p.status),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w700,
                                                      color: statusColor,
                                                      letterSpacing: 0.4,
                                                    ),
                                                  ),
                                                ),
                                              ]),
                                              if (p.description != null) ...[
                                                const SizedBox(height: 10),
                                                Text(
                                                  p.description!,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                              const SizedBox(height: 12),
                                              Row(children: [
                                                Icon(Icons.people_rounded, size: 14, color: cs.onSurfaceVariant),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    _memberCountLabel(l10n, p.memberCount),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                                if (p.budget != null) ...[
                                                  const SizedBox(width: 14),
                                                  Icon(Icons.account_balance_rounded, size: 14, color: cs.onSurfaceVariant),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      l10n.programMgmtBudgetSuffix(p.budget!.toStringAsFixed(0)),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: GoogleFonts.inter(
                                                        fontSize: 12,
                                                        color: cs.onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ]),
                                              const SizedBox(height: 12),
                                              // Action row
                                              Row(children: [
                                                Expanded(
                                                  child: GestureDetector(
                                                    onTap: () => _showMembersSheet(p),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(vertical: 9),
                                                      decoration: BoxDecoration(
                                                        color: cs.primary.withValues(alpha: 0.08),
                                                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          Icon(Icons.group_rounded, size: 16, color: cs.primary),
                                                          const SizedBox(width: 6),
                                                          // Flexible + ellipsis: "Pamahalaan ang
                                                          // Miyembro" is noticeably longer than
                                                          // "Manage Members" and this Row has no
                                                          // Expanded/scroll fallback of its own —
                                                          // on a narrow card it can overflow past
                                                          // the button's own bounds.
                                                          Flexible(
                                                            child: Text(
                                                              l10n.programMgmtManageMembersAction,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: GoogleFonts.poppins(
                                                                fontSize: 12,
                                                                fontWeight: FontWeight.w600,
                                                                color: cs.primary,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                GestureDetector(
                                                  onTap: () => _showProgramSheet(p),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                                    decoration: BoxDecoration(
                                                      color: cs.surfaceContainerHighest,
                                                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                                    ),
                                                    child: Row(children: [
                                                      Icon(Icons.edit_rounded, size: 16, color: cs.onSurfaceVariant),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        l10n.programMgmtEditAction,
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: cs.onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ]),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                GestureDetector(
                                                  onTap: () => _confirmDeleteProgram(p),
                                                  child: Container(
                                                    padding: const EdgeInsets.all(9),
                                                    decoration: BoxDecoration(
                                                      color: AppConstants.errorRed.withValues(alpha: 0.08),
                                                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                                    ),
                                                    child: const Icon(Icons.delete_outline_rounded,
                                                        size: 16, color: AppConstants.errorRed),
                                                  ),
                                                ),
                                              ]),
                                              if (p.isSalesProgram) ...[
                                                const SizedBox(height: 10),
                                                GestureDetector(
                                                  onTap: () => _showProductsSheet(p),
                                                  child: Container(
                                                    width: double.infinity,
                                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                                    decoration: BoxDecoration(
                                                      color: AppConstants.successGreen.withValues(alpha: 0.08),
                                                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        const Icon(Icons.storefront_rounded,
                                                            size: 16, color: AppConstants.successGreen),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          'Manage Products',
                                                          style: GoogleFonts.poppins(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                            color: AppConstants.successGreen,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // Responsive KPI layout: an even card count (2 or 4) lays out as a 2x2
  // grid; an odd count (3 or 5) scrolls horizontally in one row instead —
  // this module's card count isn't fixed at 4 anymore now that Distribution
  // Benefit/Loans joined Total Programs/Active/Product Sales/Enrollment.
  Widget _buildKpiSection(List<Widget> cards) {
    if (cards.length.isEven) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppConstants.spacingSm,
        crossAxisSpacing: AppConstants.spacingSm,
        childAspectRatio: 1.9,
        children: cards,
      );
    }
    return SizedBox(
      // 150w/98h overflowed by 4px for the "Distribution Benefit/Loans"
      // card — ReportIconStatCard's label has no maxLines cap, so that
      // longer label wrapped to 2 lines inside the narrower card. Widened
      // instead of touching the shared card widget (used elsewhere with
      // short single-line labels that already fit fine).
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppConstants.spacingSm),
        itemBuilder: (_, i) => SizedBox(width: 180, child: cards[i]),
      ),
    );
  }
}

// ── Program Products Modal Body (Cooperative Product Sales Program) ──────────
// Admin-side product management for a 'sales'-purpose program — add/remove
// inventory items, set price, toggle availability. See program_products
// in supabase_schema_program_product_sales.sql.

class _ProgramProductsModalBody extends StatefulWidget {
  final CooperativeProgram program;
  final ProgramRepository repo;

  const _ProgramProductsModalBody({
    required this.program,
    required this.repo,
  });

  @override
  State<_ProgramProductsModalBody> createState() => _ProgramProductsModalBodyState();
}

class _ProgramProductsModalBodyState extends State<_ProgramProductsModalBody> {
  List<ProgramProduct> _products = [];
  List<DistributionItem> _eligibleItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      widget.repo.fetchProgramProducts(widget.program.id),
      widget.repo.fetchEligibleInventoryForSaleProgram(),
    ]);
    if (!mounted) return;
    setState(() {
      _products = results[0] as List<ProgramProduct>;
      _eligibleItems = results[1] as List<DistributionItem>;
      _isLoading = false;
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    AppToast.show(context, message, isError: isError);
  }

  void _showAddProductSheet() {
    // Excludes items already added to this program — fetchEligibleInventoryForSaleProgram()
    // already excludes anything in the Loan Item Catalog.
    final addedIds = _products.map((p) => p.inventoryItemId).toSet();
    final available = _eligibleItems.where((i) => !addedIds.contains(i.id)).toList();
    if (available.isEmpty) {
      _showSnack(
        'No eligible inventory items — either none are active, or they\'re '
        'already in this program or the Loan Item Catalog.',
        isError: true,
      );
      return;
    }
    String? selectedItemId = available.first.id;
    final priceCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          bool isSaving = false;

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            final price = double.tryParse(priceCtrl.text.trim());
            if (price == null || price < 0) return;
            setSheet(() => isSaving = true);
            final ok = await widget.repo.addProgramProduct(
              programId: widget.program.id,
              inventoryItemId: selectedItemId!,
              unitPrice: price,
            );
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            _showSnack(ok ? 'Product added' : 'Could not add product.', isError: !ok);
          }

          return ManagementModalShell(
            title: 'Add Product',
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppDropdownField<String>(
                    value: selectedItemId,
                    hintText: 'Select an item',
                    labelText: 'Inventory Item *',
                    items: available.map((i) => i.id).toList(),
                    itemLabel: (id) {
                      final item = available.firstWhere((i) => i.id == id);
                      return '${item.itemName} (${item.category})';
                    },
                    onChanged: (v) => setSheet(() => selectedItemId = v),
                    validator: (v) => v == null ? 'Select an item' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Unit Price *',
                      prefixText: '₱ ',
                      hintText: '0.00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (v) {
                      if ((v ?? '').trim().isEmpty) return 'Price is required';
                      if (!isValidCurrencyValue(v)) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? 'Saving…' : 'Add Product',
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  Future<void> _toggleAvailability(ProgramProduct product) async {
    final ok = await widget.repo.updateProgramProduct(
      productId: product.id,
      unitPrice: product.unitPrice,
      isAvailable: !product.isAvailable,
    );
    if (ok) _load();
  }

  Future<void> _remove(ProgramProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Remove "${product.itemName}"?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          'This removes it from the sales program — it will no longer be '
          'available for purchase. Past purchases of it are not affected.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Remove', style: TextStyle(color: AppConstants.errorRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await widget.repo.removeProgramProduct(product.id);
    if (ok) {
      _load();
    } else {
      _showSnack('Could not remove product.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen)),
      );
    }

    // ManagementModalShell was given bodyIsScrollable: true (this list can
    // grow unboundedly as products are added), which means it hands this
    // body a plain fixed-height SizedBox with none of the 20px horizontal
    // inset it normally applies itself — hence the content sitting flush
    // against the modal edge instead of lining up with the title/footer
    // above and below it. Providing both the scroll behavior and that same
    // 20px inset here is what actually fixes the alignment, and also
    // prevents this list from ever overflowing once there are enough
    // products to exceed the modal's fixed height.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _showAddProductSheet,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_circle_outline_rounded,
                    size: 16, color: AppConstants.primaryGreen),
                const SizedBox(width: 6),
                Text('Add Product',
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_products.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No products yet. Add one from inventory.',
                  style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
            ),
          )
        else
          for (final product in _products) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: product.isAvailable
                    ? AppConstants.successGreen.withValues(alpha: 0.05)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // The item's Inventory Management photo — same
                  // 68x68 rounded-square presentation as Loan Item
                  // Catalog, generic for any product (never hardcoded to
                  // a specific item), fetched through the existing
                  // program_products -> cooperative_inventory join.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                          ? Image.network(
                              product.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: cs.surfaceContainerHighest,
                                child: Icon(Icons.storefront_rounded,
                                    size: 28, color: cs.outline.withValues(alpha: 0.4)),
                              ),
                            )
                          : Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.storefront_rounded,
                                  size: 28, color: cs.outline.withValues(alpha: 0.4)),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.itemName,
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '₱${product.unitPrice.toStringAsFixed(2)} / ${product.unit} · '
                          '${product.quantityOnHand.toStringAsFixed(0)} in stock',
                          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  // Switch's own default footprint (~59x38) was crowding
                  // the name column — FittedBox actually shrinks the space
                  // it occupies (unlike Transform.scale, which only
                  // shrinks its paint, not its layout size). Delete gets a
                  // matching compact footprint instead of its default
                  // 48x48 tap target, so the two read as one same-sized
                  // pair of controls rather than one large and one small.
                  SizedBox(
                    width: 36,
                    height: 24,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Switch(
                        value: product.isAvailable,
                        activeThumbColor: AppConstants.successGreen,
                        onChanged: (_) => _toggleAvailability(product),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppConstants.errorRed),
                    onPressed: () => _remove(product),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
          ],
      ],
      ),
    );
  }
}

// ── Program Members Modal Body ────────────────────────────────────────────────

class _ProgramMembersModalBody extends StatefulWidget {
  final CooperativeProgram program;
  final ProgramRepository repo;

  const _ProgramMembersModalBody({
    required this.program,
    required this.repo,
  });

  @override
  State<_ProgramMembersModalBody> createState() => _ProgramMembersModalBodyState();
}

class _ProgramMembersModalBodyState extends State<_ProgramMembersModalBody> {
  List<ProgramMember> _members = [];
  List<Map<String, String>> _unenrolled = [];
  List<DistributionItem> _items = [];
  bool _isLoading = true;
  String? _selectedFarmerId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Map<String, DistributionItem> get _itemsById => {
        for (final i in _items) i.id: i,
      };

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      widget.repo.fetchProgramMembers(widget.program.id),
      widget.repo.fetchUnenrolledFarmers(widget.program.id),
      widget.repo.fetchDistributionItems(),
    ]);
    if (!mounted) return;
    setState(() {
      _members = results[0] as List<ProgramMember>;
      _unenrolled = results[1] as List<Map<String, String>>;
      _items = results[2] as List<DistributionItem>;
      _isLoading = false;
    });
  }

  Future<void> _enroll() async {
    if (_selectedFarmerId == null) return;
    final ok = await widget.repo.enrollFarmer(widget.program.id, _selectedFarmerId!);
    if (ok) {
      setState(() => _selectedFarmerId = null);
      _loadMembers();
    }
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // Uses the root-overlay toast rather than ScaffoldMessenger — a plain
  // SnackBar renders behind any still-open management modal (they're
  // showGeneralDialog routes, which sit above the Scaffold), so an action
  // taken inside a modal (e.g. distributing a benefit while the Members
  // list stays open) would show its confirmation behind that modal instead
  // of on top of it. See app_toast.dart.
  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    AppToast.show(context, message, isError: isError);
  }

  // ─── Distribute benefit ─────────────────────────────────────────────────

  void _showDistributeSheet(ProgramMember member) {
    // Phase 4: limit the picker to the program's distribution category (set
    // via the "Distributes From" field on the program), so e.g. a Seeds
    // program only offers seed items rather than every active inventory
    // item. Programs with no category set (legacy, or intentionally
    // cross-category) still see everything.
    final l10nOuter = AppLocalizations.of(context);
    final category = widget.program.distributionCategory;
    final eligibleItems = category == null
        ? _items
        : _items.where((i) => i.category == category).toList();
    if (eligibleItems.isEmpty) {
      _showSnack(
        category == null
            ? l10nOuter.programMgmtNoActiveInventoryItems
            : l10nOuter.programMgmtNoActiveCategoryItems(category),
        isError: true,
      );
      return;
    }
    String? selectedItemId = eligibleItems.first.id;
    final qtyCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showManagementModal(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return StatefulBuilder(builder: (ctx, setSheet) {
          bool isSaving = false;

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            final qty = double.parse(qtyCtrl.text);
            setSheet(() => isSaving = true);
            try {
              await widget.repo.distributeBenefit(
                programMemberId: member.id,
                inventoryItemId: selectedItemId!,
                quantity: qty,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _showSnack(l10n.programMgmtBenefitDistributed(member.farmerName));
              _loadMembers();
            } catch (_) {
              setSheet(() => isSaving = false);
              _showSnack(l10n.programMgmtDistributeFailed, isError: true);
            }
          }

          final selected = _itemsById[selectedItemId];

          return ManagementModalShell(
            title: l10n.programMgmtDistributeTitle,
            subtitle: member.farmerName,
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppDropdownField<String>(
                    value: selectedItemId,
                    hintText: l10n.programMgmtItemLabel,
                    labelText: l10n.programMgmtItemLabel,
                    items: eligibleItems.map((i) => i.id).toList(),
                    itemLabel: (id) {
                      final i = eligibleItems.firstWhere((e) => e.id == id);
                      return l10n.programMgmtItemOnHand(
                          i.itemName, i.quantityOnHand.toStringAsFixed(1), i.unit);
                    },
                    onChanged: (v) => setSheet(() => selectedItemId = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qtyCtrl,
                    decoration: InputDecoration(
                      labelText: selected != null
                          ? l10n.programMgmtQuantityWithUnitLabel(selected.unit)
                          : l10n.programMgmtQuantityLabel,
                      hintText: '0.00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      final v = double.tryParse(value ?? '');
                      if (v == null || v <= 0) return l10n.programMgmtInvalidQuantity;
                      if (selected != null && v > selected.quantityOnHand) {
                        return l10n.programMgmtOnlyAvailable(
                            selected.quantityOnHand.toStringAsFixed(1), selected.unit);
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? l10n.programMgmtDistributingAction : l10n.programMgmtDistributeAction,
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  // ─── Record a revenue-share return ──────────────────────────────────────

  void _showRecordReturnSheet(ProgramMember member) {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showManagementModal(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return StatefulBuilder(builder: (ctx, setSheet) {
          bool isSaving = false;

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            final amount = double.parse(amountCtrl.text);
            setSheet(() => isSaving = true);
            try {
              await widget.repo.confirmProgramReturn(
                programMemberId: member.id,
                amountReturned: amount,
                adminNotes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _showSnack(l10n.programMgmtReturnRecorded(member.farmerName));
              _loadMembers();
            } catch (_) {
              setSheet(() => isSaving = false);
              _showSnack(l10n.programMgmtRecordReturnFailed, isError: true);
            }
          }

          return ManagementModalShell(
            title: l10n.programMgmtRecordReturnTitle,
            subtitle: member.farmerName,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.program.expectedReturnPercent != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                    child: Text(
                      l10n.programMgmtCoopPolicy('${widget.program.expectedReturnPercent}'),
                      style: GoogleFonts.inter(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  TextFormField(
                    controller: amountCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.programMgmtAmountReturnedLabel,
                      hintText: '0.00',
                      prefixText: '₱ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (!isValidCurrencyValue(value)) return l10n.adminInvEnterValidAmount;
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.paymentNotes,
                      hintText: l10n.programMgmtReturnNotesHint,
                    ),
                    maxLines: 2,
                  ),
                    ],
                  ),
                ),
              ],
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? l10n.saving : l10n.programMgmtConfirmReturnAction,
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  // ─── Distribution outcome (Phase 8 / Issue 3's Loan/ROI workflow) ───────
  // "Thriving" (lumago) is a one-tap status update — for Revenue Share
  // programs it then unlocks the existing Record Return action above; for
  // Grant programs it just closes the item out. "Failed" (hindi lumago)
  // walks into a second sheet collecting the two fields issue_loan()
  // requires (monthly payment, next payment date) before converting.

  void _showRecordOutcomeSheet(ProgramMember member) {
    showManagementModal(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return ManagementModalShell(
          title: l10n.programMgmtRecordOutcomeTitle,
          subtitle: member.farmerName,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.programMgmtOutcomeQuestion,
                style: GoogleFonts.inter(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.trending_up_rounded),
                  label: Text(l10n.programMgmtThriving),
                  style: ElevatedButton.styleFrom(backgroundColor: AppConstants.successGreen),
                  onPressed: () async {
                    final ok = await widget.repo.recordThrivingOutcome(member.id);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (ok) {
                      _showSnack(l10n.programMgmtOutcomeThrivingRecorded);
                      _loadMembers();
                    } else {
                      _showSnack(l10n.programMgmtRecordOutcomeFailed, isError: true);
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.trending_down_rounded, color: AppConstants.errorRed),
                  label: Text(l10n.programMgmtFailedConvertToLoan, style: const TextStyle(color: AppConstants.errorRed)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppConstants.errorRed)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showConvertToLoanSheet(member);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showConvertToLoanSheet(ProgramMember member) {
    final monthlyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime nextPaymentDate = DateTime.now().add(const Duration(days: 30));

    showManagementModal(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return StatefulBuilder(builder: (ctx, setSheet) {
          bool isSaving = false;

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            final monthly = double.parse(monthlyCtrl.text);
            setSheet(() => isSaving = true);
            final ok = await widget.repo.convertDistributionToLoan(
              programMemberId: member.id,
              monthlyPayment: monthly,
              nextPaymentDate: nextPaymentDate,
              notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
            );
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) {
              _showSnack(l10n.programMgmtLoanCreated(member.farmerName));
              _loadMembers();
            } else {
              _showSnack(l10n.programMgmtConvertFailed, isError: true);
            }
          }

          return ManagementModalShell(
            title: l10n.programMgmtConvertToLoanTitle,
            subtitle: member.farmerName,
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.programMgmtConvertExplainer,
                    style: GoogleFonts.inter(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: monthlyCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.programMgmtMonthlyPaymentLabel,
                      hintText: '0.00',
                      prefixText: '₱ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (!isValidCurrencyValue(value)) return l10n.adminInvEnterValidAmount;
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.programMgmtNextPaymentDateLabel,
                      style: GoogleFonts.inter(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: nextPaymentDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setSheet(() => nextPaymentDate = picked);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                      ),
                      child: Text(_formatDate(nextPaymentDate)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.paymentNotes,
                      hintText: l10n.programMgmtConvertNotesHint,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? l10n.programMgmtCreatingAction : l10n.programMgmtCreateLoanAction,
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            _isLoading
                ? l10n.programMgmtLoadingMembers
                : (_members.length == 1
                    ? l10n.programMgmtMembersEnrolledCountOne(_members.length)
                    : l10n.programMgmtMembersEnrolledCountOther(_members.length)),
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        if (_unenrolled.isNotEmpty)
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              // end, not the Row default (center) — AppDropdownField
              // renders its label above the field box, so centering
              // against its full height (label + box) put the button
              // visibly above the box instead of level with it.
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                  child: AppDropdownField<String>(
                    value: _selectedFarmerId,
                    hintText: l10n.programMgmtEnrollMemberLabel,
                    labelText: l10n.programMgmtEnrollMemberLabel,
                    items: _unenrolled.map((f) => f['id']!).toList(),
                    itemLabel: (id) {
                      final f = _unenrolled.firstWhere((e) => e['id'] == id);
                      return f['name'] ?? l10n.programMgmtUnknownFarmer;
                    },
                    onChanged: (v) => setState(() => _selectedFarmerId = v),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _selectedFarmerId != null ? _enroll : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedFarmerId != null
                          ? AppConstants.primaryGreen
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Text(
                      l10n.programMgmtEnrollAction,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selectedFarmerId != null ? Colors.white : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppConstants.primaryGreen, strokeWidth: 2))
                : _members.isEmpty
                    ? Center(
                        child: Text(l10n.programMgmtNoMembersYet,
                            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        itemCount: _members.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
                        itemBuilder: (_, i) {
                          final m = _members[i];
                          final initials = m.farmerName
                              .trim()
                              .split(' ')
                              .where((p) => p.isNotEmpty)
                              .map((p) => p[0])
                              .take(2)
                              .join()
                              .toUpperCase();
                          final item = m.inventoryItemId != null ? _itemsById[m.inventoryItemId] : null;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppConstants.primaryContainer,
                                  child: Text(initials,
                                      style: GoogleFonts.poppins(
                                          fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(m.farmerName,
                                          style: GoogleFonts.inter(
                                              fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
                                      const SizedBox(height: 2),
                                      Text(l10n.programMgmtEnrolledOn(_formatDate(m.enrolledAt)),
                                          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                                      if (m.isDistributed) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          l10n.programMgmtDistributedLine(
                                            '${m.quantityGiven?.toStringAsFixed(1)}'
                                                '${item != null ? ' ${item.unit} ${item.itemName}' : ''}',
                                            _formatDate(m.distributedAt!),
                                          ),
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppConstants.primaryGreen),
                                        ),
                                      ],
                                      if (m.isSettled) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          l10n.programMgmtSettledLine(
                                            m.amountReturned?.toStringAsFixed(2) ?? '',
                                            _formatDate(m.settledAt!),
                                          ),
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppConstants.successGreen),
                                        ),
                                      ],
                                      if (m.isOutcomeRecorded) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          m.isFailed
                                              ? l10n.programMgmtOutcomeFailedLine(_formatDate(m.outcomeRecordedAt!))
                                              : l10n.programMgmtOutcomeThrivingLine(_formatDate(m.outcomeRecordedAt!)),
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: m.isFailed
                                                  ? AppConstants.errorRed
                                                  : AppConstants.successGreen),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: widget.program.isSalesProgram
                                            // Sales-purpose programs never go
                                            // through distribution/outcome/
                                            // revenue-share settlement at
                                            // all — a member's actual
                                            // purchases live in
                                            // program_products /
                                            // program_product_purchases
                                            // (Manage Products + Purchase
                                            // Requests), not here. Enrollment
                                            // management is still valid for
                                            // a sales program (it's what
                                            // gates who can buy), so Remove
                                            // stays.
                                            ? [
                                                _ActionChip(
                                                  label: l10n.programMgmtRemoveAction,
                                                  color: AppConstants.errorRed,
                                                  filled: false,
                                                  onTap: () async {
                                                    final ok = await widget.repo.removeMember(m.id);
                                                    if (ok) _loadMembers();
                                                  },
                                                ),
                                              ]
                                            : [
                                          if (!m.isDistributed)
                                            _ActionChip(
                                              label: l10n.programMgmtDistributeAction,
                                              color: AppConstants.primaryGreen,
                                              filled: true,
                                              onTap: () => _showDistributeSheet(m),
                                            )
                                          else if (!m.isOutcomeRecorded)
                                            _ActionChip(
                                              label: l10n.programMgmtRecordOutcomeAction,
                                              color: AppConstants.buyerBlue,
                                              filled: true,
                                              onTap: () => _showRecordOutcomeSheet(m),
                                            )
                                          else if (m.isThriving && widget.program.isRevenueShare && !m.isSettled)
                                            _ActionChip(
                                              label: l10n.programMgmtRecordReturnAction,
                                              color: AppConstants.warningAmber,
                                              filled: true,
                                              onTap: () => _showRecordReturnSheet(m),
                                            )
                                          else if (m.isFailed)
                                            _ActionChip(
                                              label: l10n.programMgmtConvertedToLoanLabel,
                                              color: AppConstants.programPurple,
                                              filled: false,
                                              onTap: null,
                                              icon: Icons.request_quote_outlined,
                                            )
                                          else
                                            _ActionChip(
                                              label: widget.program.isRevenueShare
                                                  ? l10n.programMgmtSettledLabel
                                                  : l10n.programMgmtThriving,
                                              color: AppConstants.successGreen,
                                              filled: false,
                                              onTap: null,
                                              icon: Icons.check_circle_rounded,
                                            ),
                                          // Once distributed, the historical
                                          // distribution must stay intact —
                                          // removal is only for members who
                                          // haven't received anything yet.
                                          if (!m.isDistributed)
                                            _ActionChip(
                                              label: l10n.programMgmtRemoveAction,
                                              color: AppConstants.errorRed,
                                              filled: false,
                                              onTap: () async {
                                                final ok = await widget.repo.removeMember(m.id);
                                                if (ok) _loadMembers();
                                              },
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Program Activities tab — scheduled events/meetings for a program, shown
// alongside Members inside the tabbed Program Details modal.
// ─────────────────────────────────────────────────────────────────────────────

class _ProgramActivitiesTab extends StatefulWidget {
  final CooperativeProgram program;
  final ProgramRepository repo;
  const _ProgramActivitiesTab({required this.program, required this.repo});

  @override
  State<_ProgramActivitiesTab> createState() => _ProgramActivitiesTabState();
}

class _ProgramActivitiesTabState extends State<_ProgramActivitiesTab> {
  List<ProgramActivity> _activities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final activities = await widget.repo.fetchActivities(widget.program.id);
    if (!mounted) return;
    setState(() {
      _activities = activities;
      _isLoading = false;
    });
  }

  void _showAddActivitySheet() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    showManagementModal(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return StatefulBuilder(builder: (ctx, setSheet) {
          bool isSaving = false;

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            setSheet(() => isSaving = true);
            final ok = await widget.repo.createActivity(
              programId: widget.program.id,
              title: titleCtrl.text,
              description: descCtrl.text.isEmpty ? null : descCtrl.text,
              activityDate: selectedDate,
              location: locationCtrl.text.isEmpty ? null : locationCtrl.text,
            );
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
          }

          return ManagementModalShell(
            title: l10n.programMgmtNewActivityTitle,
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleCtrl,
                    decoration: InputDecoration(labelText: l10n.programMgmtActivityTitleLabel),
                    validator: (v) => (v ?? '').trim().isEmpty ? l10n.programMgmtActivityTitleRequired : null,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.programMgmtActivityDateLabel(
                        '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}')),
                    trailing: const Icon(Icons.calendar_today_rounded, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSheet(() => selectedDate = picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: locationCtrl,
                    decoration: InputDecoration(labelText: l10n.programMgmtLocationLabel),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    decoration: InputDecoration(labelText: l10n.programMgmtDescOptionalLabel),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? l10n.saving : l10n.programMgmtAddActivityAction,
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _showAddActivitySheet,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.programMgmtAddActivityAction),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen, strokeWidth: 2))
              : _activities.isEmpty
                  ? Center(
                      child: Text(l10n.programMgmtNoActivitiesYet,
                          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: _activities.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
                      itemBuilder: (_, i) {
                        final a = _activities[i];
                        return MaterialListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(a.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: Text(
                            '${_formatDate(a.activityDate)}${a.location != null ? ' · ${a.location}' : ''}',
                            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppConstants.errorRed),
                            onPressed: () async {
                              final ok = await widget.repo.deleteActivity(a.id);
                              if (ok) _load();
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small pill-style action chip, shared by the primary contextual action
// and the secondary Remove action on each enrolled member row.
// ─────────────────────────────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;
  final IconData? icon;

  const _ActionChip({
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: filled ? Colors.white : color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}