import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../data/models/program_model.dart';
import '../../../data/models/program_enrollment_request_model.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/item_type_utils.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/admin_program_card.dart';
import '../../widgets/app_multi_select_field.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/record_details_sheet.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/program_history_sheet.dart';
import '../../widgets/program_member_details.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/report_summary_widgets.dart'
    show ReportIconStatCard, ReportSectionCard;

// â”€â”€ Screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class ProgramManagementScreen extends StatefulWidget {
  const ProgramManagementScreen({super.key});

  @override
  State<ProgramManagementScreen> createState() =>
      _ProgramManagementScreenState();
}

class _ProgramManagementScreenState extends State<ProgramManagementScreen> {
  final _repo = ProgramRepository();

  List<CooperativeProgram> _programs = [];
  // Pickers for the program form: the Inventory Management items a program can
  // distribute, and the configured crop list / units for a Harvest Return.
  // The inventory categories a Product Sales program can distribute from.
  List<String> _inventoryCategories = [];
  // Crop, Livestock, Processed Products and any type added since.
  List<String> _programTypes = [];
  int _pendingEnrollmentRequestCount = 0;
  Map<String, ProgramCompletionStatus> _completion = {};
  bool _isLoading = true;
  bool _isOnline = true;
  String? _purposeFilter;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Only two statuses: Active (open to enrollment, distribution, purchases)
  // and Completed (ended â€” existing members can still be processed).

  // program_purpose is a DB-constrained 2-value column
  // (distribution/sales) â€” the right, stable basis for these chips.
  // program_type (the separate free-text field used for each card's
  // icon/color) is intentionally not touched here.
  List<CooperativeProgram> get _displayedPrograms {
    return _programs.where((p) {
      final matchesPurpose =
          _purposeFilter == null || p.programPurpose == _purposeFilter;
      final matchesSearch =
          _searchQuery.isEmpty ||
          p.programName.toLowerCase().contains(_searchQuery);
      return matchesPurpose && matchesSearch;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchPrograms(),
      _repo.fetchPendingEnrollmentRequests(),
      _repo.fetchCompletionStatuses(),
      CategoryRepository().fetchInventoryCategories(),
      CategoryRepository().fetchProgramTypes(),
    ]);
    if (!mounted) return;
    setState(() {
      _programs = results[0] as List<CooperativeProgram>;
      _completion = results[2] as Map<String, ProgramCompletionStatus>;
      _inventoryCategories = results[3] as List<String>;
      _programTypes = results[4] as List<String>;
      _pendingEnrollmentRequestCount =
          (results[1] as List<ProgramEnrollmentRequest>).length;
      _isLoading = false;
    });
  }

  Color _typeColor(String type) {
    switch (type.trim().toLowerCase()) {
      case 'crop':
        return AppConstants.primaryGreen;
      case 'peanut':
        return AppConstants.warningAmber;
      case 'production':
        return AppConstants.buyerBlue;
      case 'livestock':
        return const Color(0xFF8D6E63);
      case 'processed products':
        return AppConstants.warningAmber;
      default:
        return AppConstants.programPurple;
    }
  }

  IconData _typeIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'crop':
        return Icons.grass_rounded;
      case 'peanut':
        return Icons.eco_rounded;
      case 'production':
        return Icons.factory_rounded;
      case 'livestock':
        return Icons.pets_rounded;
      case 'processed products':
        return Icons.bakery_dining_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'active':
        return l10n.programMgmtStatusActive;
      case 'completed':
        return l10n.programMgmtStatusCompleted;
      default:
        return status.toUpperCase();
    }
  }

  String _memberCountLabel(AppLocalizations l10n, int count) {
    return count == 1
        ? l10n.programMgmtMemberCountOne(count)
        : l10n.programMgmtMemberCountOther(count);
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'active':
        return AppConstants.successGreen;
      case 'completed':
        return cs.outline;
      default:
        return cs.outline;
    }
  }

  // â”€â”€â”€ Mark as Completed â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // The only way to close a program (there is no delete, and the status is not
  // editable). It is allowed only when nothing is left to process; the
  // database enforces the same rule, so this checklist is not the only guard.

  Future<void> _completeProgram(CooperativeProgram program) async {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    var status = _completion[program.id];
    if (status == null || !status.isReady) {
      // Look again: it may have been finished since the list loaded.
      final fresh = await _repo.fetchCompletionStatuses();
      if (!mounted) return;
      _completion = fresh;
      status = fresh[program.id];
    }

    if (status == null || !status.isReady) {
      final reasons = <String>[
        if ((status?.openOrders ?? 0) > 0)
          l10n.programMgmtBlockedOpenOrders(status!.openOrders),
        if ((status?.allocatedStock ?? 0) > 0)
          l10n.programMgmtBlockedAllocated(status!.allocatedStock),
        if (status == null) l10n.programMgmtBlockedUnknown,
      ];
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text(
            l10n.programMgmtCompleteBlockedTitle,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.programMgmtCompleteBlockedIntro,
                style: GoogleFonts.inter(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 10),
              for (final r in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.radio_button_unchecked,
                        size: 14,
                        color: AppConstants.warningAmber,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r, style: GoogleFonts.inter(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(l10n.programMgmtDeleteBlockedClose),
            ),
          ],
        ),
      );
      return;
    }

    // Allowed, but staff must confirm: referred Farmers with no approved loan request, and members still waiting
    // for their item.
    final warnings = await _repo.fetchCompletionWarnings(program.id);
    if (!mounted) return;
    final unapproved = warnings.unapprovedReferrals;
    final waiting = warnings.waitingMembers;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          l10n.programMgmtCompleteTitle(program.programName),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (key, text) in [
              if (waiting > 0)
                ('completeWaitingWarning', l10n.programMgmtCompleteWaiting(waiting)),
              if (unapproved > 0)
                (
                  'completeUnapprovedWarning',
                  l10n.programMgmtCompleteUnapproved(unapproved),
                ),
            ]) ...[
              Container(
                key: Key(key),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.warningAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                    color: AppConstants.warningAmber.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppConstants.warningAmber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: GoogleFonts.inter(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (unapproved > 0 || waiting > 0) ...[
              Text(
                l10n.programMgmtCompleteAreYouSure,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              l10n.programMgmtCompleteBody,
              style: GoogleFonts.inter(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              l10n.programMgmtMarkCompletedAction,
              style: const TextStyle(color: AppConstants.successGreen),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final declined = await _repo.completeProgram(
        program.id,
        confirmedReferrals: unapproved,
        confirmedWaiting: waiting,
      );
      if (!mounted) return;
      _load();
      AppToast.show(
        context,
        declined > 0
            ? l10n.programMgmtCompletedDeclined(declined)
            : l10n.programMgmtMarkedCompleted,
      );
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
      _load();
    }
  }

  /// Scrolls the first form field that is showing an error into view.
  void _scrollToFirstError(BuildContext? formContext) {
    if (formContext == null) return;
    FormFieldState<dynamic>? first;
    void visit(Element e) {
      if (first != null) return;
      if (e is StatefulElement &&
          e.state is FormFieldState &&
          (e.state as FormFieldState).hasError) {
        first = e.state as FormFieldState;
        return;
      }
      e.visitChildren(visit);
    }

    (formContext as Element).visitChildren(visit);
    final target = first?.context;
    if (target != null && target.mounted) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        alignment: 0.1,
      );
    }
  }

  // The create / edit form. Create and edit follow the SAME rules: every
  // required field must be filled before the program can be saved (a legacy
  // Incomplete program must be completed to be saved).
  Future<void> _showProgramSheet(CooperativeProgram? existing) async {
    if (!requireManage(context, StaffModule.dashboard)) return;
    // Read the Inventory categories again, so one added since this screen loaded
    // is offered under "Distribute from" without any manual update.
    final freshCategories = await CategoryRepository()
        .fetchInventoryCategories();
    if (!mounted) return;
    if (freshCategories.isNotEmpty) _inventoryCategories = freshCategories;
    // The types too, so one added a moment ago is offered.
    final freshTypes = await CategoryRepository().fetchProgramTypes();
    if (!mounted) return;
    if (freshTypes.isNotEmpty) _programTypes = freshTypes;
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.programName ?? '');
    // The chosen Program Type. An older program's value ("crop") is matched to the list
    // ignoring case; a value not in the list at all (an older custom label) is kept as
    // its own option so editing never forces a change.
    final typeOptions = <String>[..._programTypes];
    String? selectedType;
    {
      final current = existing?.programType.trim() ?? '';
      if (current.isNotEmpty && current.toLowerCase() != 'other') {
        final match = typeOptions
            .where((t) => t.toLowerCase() == current.toLowerCase())
            .firstOrNull;
        if (match != null) {
          selectedType = match;
        } else {
          typeOptions.add(current);
          selectedType = current;
        }
      }
    }
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final budgetCtrl = TextEditingController(
      text: existing?.budget != null
          ? existing!.budget!.toStringAsFixed(2)
          : '',
    );
    final discountCtrl = TextEditingController(
      text: existing != null && existing.isSalesProgram
          ? _trimQty(existing.memberDiscountPercent)
          : '',
    );
    String selectedPurpose = existing?.programPurpose ?? 'distribution';
    // The inventory categories this program distributes from (both program types).
    final selectedSources = <String>[...?existing?.sourceCategories];
    bool isSaving = false;
    bool photoError = false;
    Uint8List? pickedImageBytes;
    String? pickedImageExt;
    String? existingImageUrl = existing?.imageUrl;
    // A legacy program that is missing details: don't force them all at once.
    final lenient = existing != null && existing.isIncomplete;

    showManagementModal(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final isDistribution = selectedPurpose == 'distribution';
            // Create and edit need the same required fields for every program type.
            String label(String s) => s;

            Future<void> pickImage() async {
              final picked = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                imageQuality: 80,
              );
              if (picked == null) return;
              final bytes = await picked.readAsBytes();
              setSheet(() {
                pickedImageBytes = bytes;
                pickedImageExt = picked.name.contains('.')
                    ? picked.name.split('.').last.toLowerCase()
                    : 'jpg';
                photoError = false;
              });
            }

            bool hasPhoto() =>
                pickedImageBytes != null ||
                (existingImageUrl != null && existingImageUrl.isNotEmpty);

            Future<void> submit() async {
              if (isSaving) return;
              final formOk = formKey.currentState!.validate();
              final photoOk = hasPhoto();
              if (!photoOk) setSheet(() => photoError = true);
              if (!formOk || !photoOk) {
                AppToast.show(ctx, l10n.programMgmtFillRequired, isError: true);
                // The form does not scroll by itself: bring the first field that is
                // in error into view, so the red outline and its message are seen.
                if (!formOk) _scrollToFirstError(formKey.currentContext);
                return;
              }

              final budget = double.tryParse(budgetCtrl.text);
              // Product Sales only. Sent when there is a discount, or when an
              // existing discount is being changed (including back to none).
              final discount = double.tryParse(discountCtrl.text.trim()) ?? 0;
              final double? discountToSave =
                  selectedPurpose == 'sales' &&
                      (discount > 0 ||
                          (existing != null &&
                              existing.memberDiscountPercent != discount))
                  ? discount
                  : null;
              setSheet(() => isSaving = true);

              String? imageUrl = existingImageUrl;
              if (pickedImageBytes != null) {
                imageUrl = await _repo.uploadProgramImage(
                  pickedImageBytes!,
                  pickedImageExt ?? 'jpg',
                );
                if (imageUrl == null) {
                  setSheet(() => isSaving = false);
                  if (!ctx.mounted) return;
                  AppToast.show(
                    ctx,
                    l10n.programMgmtPhotoUploadFailed,
                    isError: true,
                  );
                  return;
                }
              }

              // distribution_category stays in step with the chosen categories so
              // the Farmer-side display and older screens keep working.
              final category = isDistribution && selectedSources.isNotEmpty
                  ? selectedSources.join(', ')
                  : existing?.distributionCategory;

              bool ok;
              String? createdId;
              if (existing == null) {
                try {
                  createdId = await _repo.createProgram(
                    name: nameCtrl.text,
                    type: selectedType!,
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text,
                    budget: budget,
                    distributionCategory: category,
                    distributionItemId: null,
                    programPurpose: selectedPurpose,
                    imageUrl: imageUrl,
                    memberDiscountPercent: discountToSave,
                    sourceCategories: selectedSources,
                  );
                  ok = createdId != null;
                } on ProgramDuplicateNameException catch (e) {
                  setSheet(() => isSaving = false);
                  if (!ctx.mounted) return;
                  AppToast.show(
                    ctx,
                    l10n.programMgmtDuplicateName(e.programName),
                    isError: true,
                  );
                  return;
                } catch (e, st) {
                  setSheet(() => isSaving = false);
                  if (!ctx.mounted) return;
                  AppToast.show(
                    ctx,
                    friendlyError(l10n, e, st, l10n.adminInvFailedTryAgain),
                    isError: true,
                  );
                  return;
                }
              } else {
                try {
                  ok = await _repo.updateProgram(
                    id: existing.id,
                    name: nameCtrl.text,
                    type: selectedType!,
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text,
                    budget: budget,
                    distributionCategory: category,
                    // Where it distributes from is now the categories; the single
                    // configured item of an older program is no longer used.
                    distributionItemId: null,
                    imageUrl: imageUrl,
                    memberDiscountPercent: discountToSave,
                    sourceCategories: selectedSources,
                  );
                } catch (e, st) {
                  // Stay open so nothing the user typed is lost, and say why.
                  setSheet(() => isSaving = false);
                  if (!ctx.mounted) return;
                  AppToast.show(
                    ctx,
                    friendlyError(l10n, e, st, l10n.adminInvFailedTryAgain),
                    isError: true,
                  );
                  return;
                }
              }
              if (!ctx.mounted) return;
              if (!ok) {
                // Stay open so nothing the user typed is lost.
                setSheet(() => isSaving = false);
                AppToast.show(ctx, l10n.adminInvFailedTryAgain, isError: true);
                return;
              }
              Navigator.pop(ctx);
              _load();
              if (!mounted) return;
              // A new Product Sales program goes straight to adding its products.
              if (existing == null &&
                  selectedPurpose == 'sales' &&
                  createdId != null) {
                context
                    .push(
                      AppRoutes.programProducts,
                      extra: {
                        'programId': createdId,
                        'programName': nameCtrl.text.trim(),
                        'discount': discount,
                        'justCreated': true,
                      },
                    )
                    .then((_) => _load());
              }
              AppToast.show(
                context,
                existing == null
                    ? l10n.programMgmtCreated
                    : l10n.programMgmtUpdated,
              );
            }

            String? requiredText(String? v, String message) =>
                (v ?? '').trim().isEmpty ? message : null;

            // Where it distributes from: one or more inventory categories, picked from
            // a dropdown. The options are the live Inventory categories, read again each
            // time this form opens, so a new category appears without any update.
            // Used by BOTH Product Sales and Distribution programs, on Create and Edit.
            Widget sourcesField() => FormField<List<String>>(
              initialValue: selectedSources,
              validator: (_) => selectedSources.isEmpty
                  ? l10n.programMgmtSourcesRequired
                  : null,
              builder: (field) => AppMultiSelectField(
                values: selectedSources,
                options: {
                  ..._inventoryCategories,
                  // A category already chosen stays listed even if it was later
                  // switched off in Inventory.
                  ...selectedSources,
                }.toList(),
                hintText: l10n.programMgmtSourcesHint,
                labelText: l10n.programMgmtSourcesLabel,
                errorText: field.errorText,
                onChanged: (v) {
                  setSheet(() {
                    selectedSources
                      ..clear()
                      ..addAll(v);
                  });
                  field.didChange(selectedSources);
                },
              ),
            );

            return ManagementModalShell(
              title: existing == null
                  ? l10n.programMgmtNewTitle
                  : l10n.programMgmtEditTitle,
              body: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (lenient) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppConstants.warningAmber.withValues(
                            alpha: 0.10,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                        child: Text(
                          '${l10n.programMgmtIncompleteFormNote}\n'
                          '${l10n.programMgmtMissingList(existing.missingFields.map((k) => AdminProgramCard.fieldLabel(l10n, k)).join(', '))}',
                          style: GoogleFonts.inter(fontSize: 12, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      label(l10n.programMgmtPhotoLabel),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: pickImage,
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.3,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                          border: Border.all(
                            color: photoError
                                ? AppConstants.errorRed
                                : cs.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: pickedImageBytes != null
                            ? Image.memory(pickedImageBytes!, fit: BoxFit.cover)
                            : (existingImageUrl != null &&
                                      existingImageUrl.isNotEmpty
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          existingImageUrl,
                                          fit: BoxFit.cover,
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_photo_alternate_outlined,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          l10n.programMgmtPhotoTap,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    )),
                      ),
                    ),
                    if (photoError)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 4),
                        child: Text(
                          l10n.programMgmtPhotoRequired,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.errorRed,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      controller: nameCtrl,
                      label: l10n.programMgmtNameLabel,
                      hint: l10n.programMgmtNameHint,
                      textCapitalization: TextCapitalization.words,
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? l10n.programMgmtNameRequired
                          : null,
                    ),
                    const SizedBox(height: 12),
                    // What kind of item or product the program is about. A dropdown, with
                    // "+ Add New Program Type" at the bottom; a type added there is saved and
                    // offered in every program form from then on.
                    AppDropdownField<String>(
                      value: selectedType,
                      hintText: l10n.programTypeSelectHint,
                      labelText: l10n.programMgmtTypeLabel,
                      items: typeOptions,
                      itemLabel: (t) => t,
                      onChanged: (v) => setSheet(() => selectedType = v),
                      validator: (v) =>
                          v == null ? l10n.programMgmtTypeRequired : null,
                      addNewLabel: l10n.programTypeAddNew,
                      onAddNew: () async {
                        final name = await promptForNewOptionName(
                          ctx,
                          title: l10n.programTypeAddTitle,
                          hintText: l10n.programTypeAddHint,
                        );
                        if (name == null) return null;
                        final added = await CategoryRepository().addProgramType(
                          name,
                        );
                        if (added == null) return null;
                        setSheet(() {
                          if (!typeOptions.any(
                            (t) => t.toLowerCase() == added.toLowerCase(),
                          )) {
                            typeOptions.add(added);
                          }
                        });
                        if (mounted &&
                            !_programTypes.any(
                              (t) => t.toLowerCase() == added.toLowerCase(),
                            )) {
                          setState(
                            () => _programTypes = [..._programTypes, added],
                          );
                        }
                        return typeOptions.firstWhere(
                          (t) => t.toLowerCase() == added.toLowerCase(),
                        );
                      },
                    ),
                    // Purpose is fixed once a program exists â€” switching an
                    // existing program (which may already have members and
                    // distributions) between purposes is a data-integrity
                    // question this screen deliberately does not handle.
                    if (existing == null) ...[
                      const SizedBox(height: 12),
                      AppDropdownField<String>(
                        value: selectedPurpose,
                        hintText: AppLocalizations.of(
                          context,
                        ).enhSelectAPurpose,
                        labelText: AppLocalizations.of(
                          context,
                        ).enhProgramPurpose,
                        items: const ['distribution', 'sales'],
                        itemLabel: (v) => v == 'sales'
                            ? AppLocalizations.of(
                                context,
                              ).reportsProductSalesShort
                            : AppLocalizations.of(
                                context,
                              ).balikTangkilikDistributionTab,
                        onChanged: (v) => setSheet(
                          () => selectedPurpose = v ?? selectedPurpose,
                        ),
                        validator: (v) => v == null
                            ? AppLocalizations.of(context).enhPurposeIsRequired
                            : null,
                      ),
                    ],
                    if (isDistribution) ...[
                      const SizedBox(height: 12),
                      sourcesField(),
                    ],
                    if (selectedPurpose == 'sales') ...[
                      const SizedBox(height: 12),
                      sourcesField(),
                      const SizedBox(height: 12),
                      LabeledTextField(
                        controller: discountCtrl,
                        label: l10n.programMgmtMemberDiscountLabel,
                        hint: '0',
                        suffixText: '%',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) {
                            return l10n.programMgmtMemberDiscountRequired;
                          }
                          final n = double.tryParse(t);
                          return (n == null || n < 0 || n > 100)
                              ? l10n.programMgmtMemberDiscountInvalid
                              : null;
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    LabeledTextField(
                      controller: budgetCtrl,
                      label: label(l10n.programMgmtBudgetLabel),
                      hint: '0.00',
                      prefixText: 'â‚± ',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return requiredText(
                            value,
                            l10n.programMgmtBudgetRequired,
                          );
                        }
                        if (!isValidCurrencyValue(value)) {
                          return l10n.adminInvEnterValidAmount;
                        }
                        if ((double.tryParse(value!) ?? 0) <= 0) {
                          return l10n.programMgmtBudgetRequired;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      controller: descCtrl,
                      label: label(l10n.programMgmtDescriptionLabel),
                      hint: l10n.programMgmtDescHint,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 3,
                      validator: (v) =>
                          requiredText(v, l10n.programMgmtDescRequired),
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
          },
        );
      },
    );
  }

  static String _trimQty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // Members is a full page (not a modal stacked on a modal): the member list,
  // the item distribution and the outcome status all work inline there.
  // Read-only details of a program, with its members (tap the card). Editing
  // and managing members stay on the card's own buttons.
  void _showProgramDetails(CooperativeProgram p) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final members = _repo.fetchProgramMembers(p.id);
    showRecordDetails(
      context,
      title: p.programName,
      subtitle: _statusLabel(l10n, p.status),
      imageUrl: p.imageUrl,
      placeholderIcon: _typeIcon(p.programType),
      sections: [
        DetailSection(
          title: l10n.detailsSectionInfo,
          rows: [
            DetailRow(
              l10n.detailsPurpose,
              p.isSalesProgram
                  ? l10n.programMgmtFilterSales
                  : l10n.programMgmtFilterDistribution,
            ),
            DetailRow(l10n.detailsStatus, _statusLabel(l10n, p.status)),
            DetailRow(l10n.detailsSeason, '${p.seasonYear}'),
            if (p.budget != null)
              DetailRow(
                l10n.detailsBudget,
                'â‚±${p.budget!.toStringAsFixed(2)}',
              ),
            if ((p.distributionItemName ?? '').isNotEmpty)
              DetailRow(l10n.detailsItemGiven, p.distributionItemName!),
            if (p.isSalesProgram)
              DetailRow(
                l10n.detailsMemberDiscount,
                '${formatQuantity(p.memberDiscountPercent)}%',
              ),
            if (p.createdAt != null)
              DetailRow(l10n.detailsCreated, detailDate(p.createdAt!)),
            if ((p.description ?? '').trim().isNotEmpty)
              DetailRow(l10n.detailsDescription, p.description!.trim()),
          ],
        ),
        // Members: tap the header to open or close; the list scrolls inside
        // its own fixed height however many members there are.
        DetailSection(
          child: CollapsibleDetailSection(
            title: l10n.detailsMembers(p.memberCount),
            child: FutureBuilder<List<ProgramMember>>(
            future: members,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final list = snap.data ?? const <ProgramMember>[];
              if (list.isEmpty) {
                return Text(
                  l10n.detailsNoMembers,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < list.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: cs.outline.withValues(alpha: 0.10),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                list[i].farmerName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              list[i].distributedAt != null
                                  ? l10n.detailsMemberReceived(
                                      detailDate(list[i].distributedAt!),
                                    )
                                  : l10n.detailsMemberEnrolled(
                                      detailDate(list[i].enrolledAt),
                                    ),
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          ),
        ),
      ],
    );
  }

  void _showMembersSheet(CooperativeProgram program) {
    context
        .push(AppRoutes.programMembers, extra: {"program": program})
        .then((_) => _load());
  }

  void _showProductsSheet(CooperativeProgram program) {
    context
        .push(
          AppRoutes.programProducts,
          extra: {
            'programId': program.id,
            'programName': program.programName,
            'discount': program.memberDiscountPercent,
          },
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final displayedPrograms = _displayedPrograms;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _isOnline
          ? FloatingActionButton(
              heroTag: null, onPressed: () => _showProgramSheet(null),
              backgroundColor: AppConstants.primaryGreen,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.programMgmtTitle,
            onBack: () => context.pop(),
            trailing: _requestsMenu(l10n, cs),
          ),

          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : RefreshIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    onRefresh: _load,
                    // Single outer scrollable so the KPI cards scroll away
                    // with the list below them, instead of staying pinned
                    // as static siblings above it (per your Item B request
                    // â€” matches Crop Management / Price Management's own
                    // KPI-inside-the-list pattern).
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        // KPI cards (dashboard.md section 5) â€” a
                        // responsively-laid-out set (2/4 cards â†’ 2x2 grid,
                        // 3/5 cards â†’ horizontal scroll row) since Total
                        // Programs + Active + Product Sales + Enrollment +
                        // Distribution Benefit/Loans is an odd count of 5.
                        if (_programs.isNotEmpty) ...[
                          ReportSectionCard(
                            title: AppLocalizations.of(
                              context,
                            ).enhProgramOverview,
                            icon: Icons.star_rounded,
                            accent: AppConstants.programPurple,
                            child: _buildKpiSection([
                              ReportIconStatCard(
                                icon: Icons.star_rounded,
                                accent: AppConstants.programPurple,
                                label: AppLocalizations.of(
                                  context,
                                ).enhTotalPrograms,
                                value: '${_programs.length}',
                              ),
                              ReportIconStatCard(
                                icon: Icons.play_circle_fill_rounded,
                                accent: AppConstants.successGreen,
                                label: AppLocalizations.of(
                                  context,
                                ).farmerDetailsProgStatusActive,
                                value:
                                    '${_programs.where((p) => p.status == 'active').length}',
                              ),
                              ReportIconStatCard(
                                icon: Icons.storefront_rounded,
                                accent: AppConstants.successGreen,
                                label: AppLocalizations.of(
                                  context,
                                ).reportsProductSalesShort,
                                value:
                                    '${_programs.where((p) => p.isSalesProgram).length}',
                              ),
                              ReportIconStatCard(
                                icon: Icons.request_quote_rounded,
                                accent: AppConstants.buyerBlue,
                                label: AppLocalizations.of(
                                  context,
                                ).enhDistributionBenefitLoans,
                                value:
                                    '${_programs.where((p) => p.programPurpose == 'distribution').length}',
                              ),
                              ReportIconStatCard(
                                icon: Icons.groups_rounded,
                                accent: AppConstants.primaryGreen,
                                label: l10n.marketLinkKpiEnrolled,
                                value:
                                    // Enrollment across every program purpose â€”
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
                        if (_programs.isNotEmpty) ...[
                          // Search bar
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: l10n.programMgmtSearchHint,
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              fillColor: sagana.cardBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusLg,
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Filter chips â€” All | Distribution | Sales,
                          // backed by the DB-constrained program_purpose
                          // column (exactly 2 values, locked once a program
                          // is created).
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
                            child: Row(
                              children: [
                                _PurposeChip(
                                  label:
                                      '${l10n.reportsAll} (${_programs.length})',
                                  isSelected: _purposeFilter == null,
                                  onTap: () =>
                                      setState(() => _purposeFilter = null),
                                  cs: cs,
                                  sagana: sagana,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: _PurposeChip(
                                    label:
                                        '${l10n.programMgmtFilterDistribution} (${_programs.where((p) => p.programPurpose == 'distribution').length})',
                                    isSelected:
                                        _purposeFilter == 'distribution',
                                    onTap: () => setState(
                                      () => _purposeFilter = 'distribution',
                                    ),
                                    cs: cs,
                                    sagana: sagana,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: _PurposeChip(
                                    label:
                                        '${l10n.programMgmtFilterSales} (${_programs.where((p) => p.programPurpose == 'sales').length})',
                                    isSelected: _purposeFilter == 'sales',
                                    onTap: () => setState(
                                      () => _purposeFilter = 'sales',
                                    ),
                                    cs: cs,
                                    sagana: sagana,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_programs.isEmpty)
                          Column(
                            children: [
                              const SizedBox(height: 60),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.people_alt_rounded,
                                      size: 48,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.programMgmtNoProgramsYet,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () => _showProgramSheet(null),
                                      child: Text(l10n.programMgmtCreateFirst),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else if (displayedPrograms.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Center(
                              child: Text(
                                l10n.programMgmtNoProgramsMatchFilter,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          // Active programs first; Completed ones sit in their
                          // own section below, greyed out.
                          ..._programCards(
                            displayedPrograms
                                .where((p) => p.status != 'completed')
                                .toList(),
                            cs,
                            l10n,
                          ),
                          if (displayedPrograms.any(
                            (p) => p.status == 'completed',
                          )) ...[
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Icon(
                                  Icons.task_alt_rounded,
                                  size: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Flexible(child: Text(
                                  l10n.programMgmtCompletedSection
                                      .toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: cs.onSurfaceVariant,
                                  ),
                                )),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ..._programCards(
                              displayedPrograms
                                  .where((p) => p.status == 'completed')
                                  .toList(),
                              cs,
                              l10n,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _programCards(
    List<CooperativeProgram> programs,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    return [
      for (final p in programs)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          // Completed programs are visibly set apart: greyed out, but every
          // action (Members, History, Edit) stays available.
          child: Opacity(
            opacity: p.status == 'completed' ? 0.6 : 1,
            child: AdminProgramCard(
              program: p,
              accent: p.status == 'completed'
                  ? cs.outline
                  : _typeColor(p.programType),
              icon: _typeIcon(p.programType),
              statusLabel: _statusLabel(l10n, p.status),
              statusColor: _statusColor(p.status, cs),
              memberCountLabel: _memberCountLabel(l10n, p.memberCount),
              onTap: () => _showProgramDetails(p),
              onMembers: () => _showMembersSheet(p),
              onHistory: () =>
                  showProgramHistory(context, program: p, repo: _repo),
              onEdit: () => _showProgramSheet(p),
              onComplete: () => _completeProgram(p),
              completion: _completion[p.id],
              onProducts: p.isSalesProgram ? () => _showProductsSheet(p) : null,
            ),
          ),
        ),
    ];
  }

  // Direct button for Join Requests (the three-dot menu and Outcome Reviews were removed).
  Widget _requestsMenu(AppLocalizations l10n, ColorScheme cs) {
    final count = _pendingEnrollmentRequestCount;
    return IconButton(
      tooltip: l10n.reqEnrollTitle,
      onPressed: () {
        context
            .push(AppRoutes.programEnrollmentRequests)
            .then((_) => _load());
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.how_to_reg_rounded, color: cs.onSurface),
          if (count > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppConstants.errorRed,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Responsive KPI layout: an even card count (2 or 4) lays out as a 2x2
  // grid; an odd count (3 or 5) scrolls horizontally in one row instead â€”
  // this module's card count isn't fixed at 4 anymore now that Distribution
  // Benefit/Loans joined Total Programs/Active/Product Sales/Enrollment.
  Widget _buildKpiSection(List<Widget> cards) {
    if (cards.length.isEven) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        // No automatic status-bar padding: this list sits inside a bigger scroll view.
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppConstants.spacingSm,
        crossAxisSpacing: AppConstants.spacingSm,
        childAspectRatio: 1.9,
        children: cards,
      );
    }
    return SizedBox(
      // 150w/98h overflowed by 4px for the "Distribution Benefit/Loans"
      // card â€” ReportIconStatCard's label has no maxLines cap, so that
      // longer label wrapped to 2 lines inside the narrower card. Widened
      // instead of touching the shared card widget (used elsewhere with
      // short single-line labels that already fit fine).
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AppConstants.spacingSm),
        itemBuilder: (_, i) => SizedBox(width: 180, child: cards[i]),
      ),
    );
  }
}

// â”€â”€ Program Members page â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// The members of one program as a full page (route /admin/programs/members).
class ProgramMembersScreen extends StatelessWidget {
  final CooperativeProgram program;
  const ProgramMembersScreen({super.key, required this.program});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            SubPageTopBar(
              title: program.programName,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: _ProgramMembersModalBody(
                program: program,
                repo: ProgramRepository(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Program Members Modal Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ProgramMembersModalBody extends StatefulWidget {
  final CooperativeProgram program;
  final ProgramRepository repo;

  const _ProgramMembersModalBody({required this.program, required this.repo});

  @override
  State<_ProgramMembersModalBody> createState() =>
      _ProgramMembersModalBodyState();
}

class _ProgramMembersModalBodyState extends State<_ProgramMembersModalBody> {
  List<ProgramMember> _members = [];
  List<DistributionItem> _items = [];
  // Product Sales: each member's orders, spent, saved and pending (one read for all).
  Map<String, MemberPurchaseSummary> _purchaseSummaries = {};
  bool _isLoading = true;

  // Distribution happens inline on the member's own card (no extra modal).
  String? _distributingId;
  // The item chosen for this distribution (from the program's categories).
  String? _distItemId;
  final _qtyCtrl = TextEditingController();
  bool _distSaving = false;
  String? _distError;
  // Product Sales: the member search (by Farmer name).
  String _memberQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  /// What this program may give: in-stock-or-not items in its categories, plus the
  /// single configured item of an older program.
  List<DistributionItem> get _eligibleItems {
    final p = widget.program;
    final fromCategories = itemsInSources(_items, p.sourceCategories);
    final legacy = p.distributionItemId == null
        ? null
        : _items.where((i) => i.id == p.distributionItemId).firstOrNull;
    return [
      if (legacy != null && !fromCategories.any((i) => i.id == legacy.id))
        legacy,
      ...fromCategories,
    ];
  }

  Map<String, DistributionItem> get _itemsById => {
    for (final i in _items) i.id: i,
  };

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      widget.repo.fetchProgramMembers(widget.program.id),
      widget.repo.fetchDistributionItems(),
      widget.program.isSalesProgram
          ? widget.repo.fetchPurchaseSummaries(widget.program.id)
          : Future<Map<String, MemberPurchaseSummary>>.value(const {}),
    ]);
    if (!mounted) return;
    setState(() {
      _members = results[0] as List<ProgramMember>;
      _items = results[1] as List<DistributionItem>;
      _purchaseSummaries = results[2] as Map<String, MemberPurchaseSummary>;
      _isLoading = false;
    });
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

  // Uses the root-overlay toast rather than ScaffoldMessenger â€” a plain
  // SnackBar renders behind any still-open management modal (they're
  // showGeneralDialog routes, which sit above the Scaffold), so an action
  // taken inside a modal (e.g. distributing a benefit while the Members
  // list stays open) would show its confirmation behind that modal instead
  // of on top of it. See app_toast.dart.
  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    AppToast.show(context, message, isError: isError);
  }

  // â”€â”€â”€ Distribute benefit (inline on the member's card) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _startDistribute(ProgramMember member) {
    if (!requireManage(context, StaffModule.dashboard)) return;
    // The program fixes WHAT is distributed (Distributes From). A program
    // without that item is Incomplete and cannot distribute â€” the database
    // enforces this too (distribute_program_benefit()).
    final l10n = AppLocalizations.of(context);
    // A Completed program no longer distributes (the database refuses too).
    if (widget.program.status != 'active') {
      _showSnack(l10n.programMgmtCompletedNoDistribution, isError: true);
      return;
    }
    if (!widget.program.canDistribute) {
      _showSnack(l10n.programMgmtItemNotSetForDistribute, isError: true);
      return;
    }
    final eligible = _eligibleItems;
    if (eligible.isEmpty) {
      // Nothing active in those categories (archived, removed or not stocked yet).
      _showSnack(
        l10n.programMgmtNoItemsInCategories(
          widget.program.sourceCategories.join(', '),
        ),
        isError: true,
      );
      return;
    }
    setState(() {
      _distributingId = member.id;
      _distItemId = eligible.length == 1 ? eligible.first.id : null;
      _qtyCtrl.clear();
      _distError = null;
    });
  }

  Future<void> _submitDistribute(ProgramMember member) async {
    if (_distSaving) return;
    final l10n = AppLocalizations.of(context);
    final selected = _itemsById[_distItemId];
    if (selected == null) {
      setState(() => _distError = l10n.programMgmtChooseItemToGiveHint);
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _distError = l10n.programMgmtInvalidQuantity);
      return;
    }
    if (qty > selected.quantityOnHand) {
      setState(
        () => _distError = l10n.programMgmtOnlyAvailable(
          formatQuantity(selected.quantityOnHand),
          selected.unit,
        ),
      );
      return;
    }
    setState(() {
      _distSaving = true;
      _distError = null;
    });
    try {
      await widget.repo.distributeBenefit(
        programMemberId: member.id,
        inventoryItemId: selected.id,
        quantity: qty,
      );
      if (!mounted) return;
      setState(() {
        _distSaving = false;
        _distributingId = null;
      });
      _showSnack(l10n.programMgmtBenefitDistributed(member.farmerName));
      _loadMembers();
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _distSaving = false);
      // Say the real reason in plain words (no stock, no return quantity, crop not available...).
      _showSnack(
        friendlyError(l10n, e, st, l10n.programMgmtDistributeFailed),
        isError: true,
      );
    }
  }

  Widget _distributePanel(ProgramMember m, AppLocalizations l10n) {
    final eligible = _eligibleItems;
    final names = itemPickerNames(
      eligible,
      typeLabel: (t) => itemTypeLabel(l10n, t),
    );
    final selected = _itemsById[_distItemId];
    if (eligible.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppConstants.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Any item in the program's categories; just its name, stock and unit.
          AppDropdownField<String>(
            value: _distItemId,
            hintText: l10n.programMgmtChooseItemToGiveHint,
            labelText: l10n.programMgmtChooseItemToGive,
            wrapText: true, // a long item name is shown in full, never cut off
            items: eligible.map((i) => i.id).toList(),
            itemLabel: (id) {
              final i = eligible.firstWhere((e) => e.id == id);
              return l10n.programMgmtItemOnHand(
                names[id] ?? i.displayName,
                formatQuantity(i.quantityOnHand),
                i.unit,
              );
            },
            onChanged: (v) => setState(() {
              _distItemId = v;
              _distError = null;
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _qtyCtrl,
            autofocus: true,
            enabled: !_distSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            decoration: InputDecoration(
              isDense: true,
              labelText: selected == null
                  ? l10n.programMgmtQuantityLabel
                  : l10n.programMgmtQuantityWithUnitLabel(selected.unit),
              hintText: '0.00',
              errorText: _distError,
            ),
            onSubmitted: (_) => _submitDistribute(m),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _distSaving
                    ? null
                    : () => setState(() {
                        _distributingId = null;
                        _distError = null;
                      }),
                child: Text(l10n.cancel),
              ),
              const Spacer(),
              ElevatedButton(
                // The theme's buttons fill the width; inside a Row that is unbounded.
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _distSaving ? null : () => _submitDistribute(m),
                child: _distSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.programMgmtDistributeAction),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // To Distribute: how long since they joined, counted live with no limit and kept neutral.
  Widget _waitingToReceive(ProgramMember m, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final days = daysSinceReceived(m.enrolledAt);
    return Padding(
      key: Key('waitingToReceive_${m.id}'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.hourglass_empty_rounded,
            size: 14,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.memWaitingToReceive(days),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Product Sales: orders, spent and saved at a glance, and a chip for purchases waiting.
  Widget _salesStats(ProgramMember m, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final s = _purchaseSummaries[m.farmerId] ?? const MemberPurchaseSummary();
    String peso(double v) => 'â‚±${formatQuantityGrouped(v)}';
    // Each figure may be as wide as the card and no wider, so a long one wraps instead of
    // running past the edge (big amounts, Tagalog, large text sizes).
    Widget stat(IconData icon, String text, {Color? color}) => LayoutBuilder(
      builder: (context, box) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: box.maxWidth.isFinite ? box.maxWidth : double.infinity,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 14, color: color ?? cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: color ?? cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      key: Key('salesStats_${m.id}'),
      padding: const EdgeInsets.only(top: 10),
      child: s.orders == 0
          ? Text(
              l10n.memDetailsNoPurchases,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            )
          : Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                stat(Icons.receipt_long_outlined, l10n.memStatOrders(s.orders)),
                stat(Icons.payments_outlined, l10n.memStatSpent(peso(s.spent))),
                stat(
                  Icons.savings_outlined,
                  l10n.memStatSaved(peso(s.saved)),
                  color: AppConstants.successGreen,
                ),
                if (s.pending > 0)
                  Container(
                    key: Key('pendingChip_${m.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.warningAmber.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      l10n.memStatPending(s.pending),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.warningAmber,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // â”€â”€â”€ The members, as swipeable sections â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _infoLine(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: color),
          ),
        ),
      ],
    ),
  );

  Widget _memberCard(
    ProgramMember m,
    AppLocalizations l10n, {
    required bool toDistribute,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSales = widget.program.isSalesProgram;
    final item = m.inventoryItemId != null
        ? _itemsById[m.inventoryItemId]
        : null;
    final initials = m.farmerName
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .take(2)
        .join()
        .toUpperCase();
    // What was given, in the Inventory item's unit (kept with the distribution, so a
    // later edit of the item does not rewrite this record).
    final receivedUnit = (m.distributedUnit ?? item?.unit)?.trim();
    final receivedName = m.distributedItemName ?? item?.displayName;
    final received = m.isDistributed
        ? '${m.quantityGiven != null ? formatQuantityGrouped(m.quantityGiven!) : ''}'
              '${receivedUnit != null && receivedUnit.isNotEmpty ? ' $receivedUnit' : ''}'
              '${receivedName != null ? ' $receivedName' : ''}'
        : '';

    // Tapping the card opens that Farmer's details for this program.
    return GestureDetector(
      key: Key('memberCard_${m.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showProgramMemberDetails(
        context,
        program: widget.program,
        member: m,
        itemUnit: receivedUnit,
        itemName: receivedName,
        repo: widget.repo,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppConstants.primaryContainer,
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.farmerName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        l10n.programMgmtEnrolledOn(_formatDate(m.enrolledAt)),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
            if (!isSales && m.isDistributed)
              _infoLine(
                Icons.inventory_2_outlined,
                l10n.memGivenLine(
                  received.trim(),
                  _formatDate(m.distributedAt!),
                ),
                AppConstants.primaryGreen,
              ),
            if (isSales) _salesStats(m, l10n),
            if (!isSales && toDistribute && !m.isDistributed)
              _waitingToReceive(m, l10n),
            if (!isSales && toDistribute) ...[
              const SizedBox(height: 12),
              if (_distributingId == m.id)
                _distributePanel(m, l10n)
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _startDistribute(m),
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text(l10n.programMgmtDistributeAction),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _list(
    List<ProgramMember> items,
    String empty, {
    bool toDistribute = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadMembers,
        child: ListView(
          children: [
            const SizedBox(height: 70),
            Icon(Icons.groups_outlined, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                empty,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMembers,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _memberCard(
          items[i],
          AppLocalizations.of(context),
          toDistribute: toDistribute,
        ),
      ),
    );
  }

  Widget _notice(String text, IconData icon, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 11, height: 1.35),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final program = widget.program;

    if (_isLoading) {
      return const Padding(padding: EdgeInsets.all(16), child: SkeletonList());
    }

    final notices = <Widget>[
      if (program.status == 'completed')
        _notice(
          l10n.programMgmtCompletedMembersNote,
          Icons.lock_outline_rounded,
          cs.outline,
        ),
      // New distributions are blocked until the program has its item
      // (the database refuses them too).
      if (!program.isSalesProgram &&
          program.status == 'active' &&
          !program.canDistribute)
        _notice(
          l10n.programMgmtDistributionPaused,
          Icons.pause_circle_outline_rounded,
          AppConstants.warningAmber,
        ),
    ];

    // Product Sales: just who is enrolled. No sections, no counters.
    if (program.isSalesProgram) {
      return Column(
        children: [
          ...notices,
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              onChanged: (v) => setState(() => _memberQuery = v),
              decoration: InputDecoration(
                hintText: l10n.farmerMgmtSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: _list(
              _memberQuery.trim().isEmpty
                  ? _members
                  : _members
                        .where(
                          (m) => m.farmerName.toLowerCase().contains(
                            _memberQuery.trim().toLowerCase(),
                          ),
                        )
                        .toList(),
              _memberQuery.trim().isEmpty
                  ? l10n.memEmptySales
                  : l10n.farmerMgmtNoFarmersFiltered,
            ),
          ),
        ],
      );
    }

    final toDistribute = _members.where((m) => !m.isDistributed).toList();
    final handedOut = _members.where((m) => m.isDistributed).toList();

    // Free Distribution has no outcome process: once an item is handed out it belongs to the Farmer.
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          ...notices,
          // Two sections only: the tabs share the width equally, each label centered.
          TabBar(
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: cs.outline.withValues(alpha: 0.15),
            labelStyle: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(text: l10n.memTabToDistribute(toDistribute.length)),
              Tab(text: l10n.memTabDistributed(handedOut.length)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _list(
                  toDistribute,
                  l10n.memEmptyToDistribute,
                  toDistribute: true,
                ),
                _list(handedOut, l10n.memEmptyDistributed),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Same filter-chip style already established for Inventory Management,
// Loan Item Catalog, and Crop Management â€” a separate local copy here
// rather than a shared extraction, matching that same convention.
class _PurposeChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _PurposeChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.20),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
