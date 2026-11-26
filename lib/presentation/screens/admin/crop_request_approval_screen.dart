import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/app_error_message.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/app_toast.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_activity_repository.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../../data/models/admin_log_message.dart';
import '../../../data/services/market_types_service.dart';
import '../../../core/l10n/localized_labels.dart';

// ─── Model ─────────────────────────────────────────────────────────────────

class CropRequestItem {
  final String id;
  final String farmerId;
  final String farmerName;
  final String requestedName;
  final String category;
  final String cropType;

  /// The shelf life (days) the Farmer gave for the crop; it becomes the crop's
  /// shelf life on approval. Null for a request made before this was asked.
  final int? shelfLifeDays;
  final String status;
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  const CropRequestItem({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.requestedName,
    required this.category,
    required this.cropType,
    this.shelfLifeDays,
    required this.status,
    this.adminNotes,
    required this.createdAt,
    this.reviewedAt,
  });
}

// ─── Repository ────────────────────────────────────────────────────────────

class _CropRequestRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<CropRequestItem>> fetchByStatus(String status) async {
    try {
      const columns =
          'id, farmer_id, requested_name, category, crop_type, status, admin_notes, created_at, reviewed_at';
      Future<List<Map<String, dynamic>>> read(String cols) => _client
          .from('crop_requests')
          .select(cols)
          .eq('status', status)
          .order('created_at', ascending: status == 'pending');
      // With the Farmer's shelf-life figure; without it on a database that
      // does not have the column yet.
      List<Map<String, dynamic>> rows;
      try {
        rows = await read('$columns, shelf_life_days');
      } on PostgrestException {
        rows = await read(columns);
      }

      if (rows.isEmpty) return [];

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();

      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds);

      final namesByUserId = <String, String>{
        for (final info in infoRows)
          info['user_id'] as String: info['full_name'] as String? ?? '',
      };

      return rows.map((r) {
        final farmerId = r['farmer_id'] as String;
        return CropRequestItem(
          id: r['id'] as String,
          farmerId: farmerId,
          farmerName: namesByUserId[farmerId] ?? '',
          requestedName: r['requested_name'] as String,
          category: r['category'] as String? ?? 'Other',
          cropType: r['crop_type'] as String? ?? '',
          shelfLifeDays: (r['shelf_life_days'] as num?)?.toInt(),
          status: r['status'] as String,
          adminNotes: r['admin_notes'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String),
          reviewedAt: r['reviewed_at'] != null
              ? DateTime.tryParse(r['reviewed_at'] as String)
              : null,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> approve(
    String requestId, {
    String? notes,
    required String cropType,
  }) async {
    try {
      await _client.rpc(
        'approve_crop_request',
        params: {
          'p_request_id': requestId,
          if (notes != null && notes.isNotEmpty) 'p_admin_notes': notes,
          'p_crop_type': cropType,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Saves the shelf life the Manager confirmed for a pending request; it
  /// becomes the crop's shelf life on approval. Returns the error on failure,
  /// null on success.
  Future<Object?> setShelfLife(String requestId, int days) async {
    try {
      await _client.rpc(
        'set_crop_request_shelf_life',
        params: {'p_request_id': requestId, 'p_days': days},
      );
      return null;
    } catch (e) {
      return e;
    }
  }

  /// Saves the Storage Life the Manager set for a pending request; it becomes
  /// the crop's Storage Life on approval. Returns the error on failure, null on
  /// success. A database that does not have the function yet is not treated
  /// as a failure: the approval then goes ahead as it did before.
  Future<Object?> setStorageLife(String requestId, int days) async {
    try {
      await _client.rpc(
        'set_crop_request_storage_life',
        params: {'p_request_id': requestId, 'p_days': days},
      );
      return null;
    } on PostgrestException catch (e) {
      return e.code == 'PGRST202' ? null : e;
    } catch (e) {
      return e;
    }
  }

  Future<bool> reject(String requestId, String notes) async {
    try {
      await _client.rpc(
        'reject_crop_request',
        params: {'p_request_id': requestId, 'p_admin_notes': notes},
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────

/// Crop Request Approval — Admin.
/// Pushed above the shell. Route: /admin/crops/requests
class CropRequestApprovalScreen extends StatefulWidget {
  const CropRequestApprovalScreen({super.key});

  @override
  State<CropRequestApprovalScreen> createState() =>
      _CropRequestApprovalScreenState();
}

class _CropRequestApprovalScreenState extends State<CropRequestApprovalScreen>
    with SingleTickerProviderStateMixin {
  final _repo = _CropRequestRepository();
  late final TabController _tabController;

  bool _isLoading = true;
  List<CropRequestItem> _pending = [];
  List<CropRequestItem> _reviewed = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchByStatus('pending'),
      _repo.fetchByStatus('approved'),
    ]);
    final rejected = await _repo.fetchByStatus('rejected');
    if (!mounted) return;
    setState(() {
      _pending = results[0];
      _reviewed = [...results[1], ...rejected]
        ..sort(
          (a, b) => (b.reviewedAt ?? b.createdAt).compareTo(
            a.reviewedAt ?? a.createdAt,
          ),
        );
      _isLoading = false;
    });
  }

  void _showReviewModal(CropRequestItem item) {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final notesCtrl = TextEditingController();
    // The Farmer's shelf-life figure, for the Manager to confirm or correct.
    // Required: a crop is not approved without a shelf life.
    final shelfCtrl = TextEditingController(
      text: item.shelfLifeDays?.toString() ?? '',
    );
    String? shelfError;
    // Storage Life of the crop's planting materials: set by the Manager here,
    // never asked from the Farmer. Required as well.
    final storageCtrl = TextEditingController();
    String? storageError;
    // The farmer's suggested market type if it is still a valid option,
    // otherwise the default one; the Manager confirms or changes it.
    final validCodes = MarketTypes.instance.activeTypes
        .map((t) => t.code)
        .toList();
    String selectedCropType = validCodes.contains(item.cropType)
        ? item.cropType
        : (MarketTypes.instance.defaultCode ?? item.cropType);
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> respond(bool approve) async {
              if (!approve && notesCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(l10n.cropRequestProvideReason),
                    backgroundColor: AppConstants.errorRed,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              if (approve) {
                final days = int.tryParse(shelfCtrl.text.trim());
                if (days == null || days < 1 || days > 3650) {
                  setSheet(
                    () => shelfError = shelfCtrl.text.trim().isEmpty
                        ? l10n.cropMgmtShelfLifeRequired
                        : l10n.cropMgmtShelfLifeInvalid,
                  );
                  return;
                }
                final storageDays = int.tryParse(storageCtrl.text.trim());
                if (storageDays == null ||
                    storageDays < 1 ||
                    storageDays > 36500) {
                  setSheet(
                    () => storageError = storageCtrl.text.trim().isEmpty
                        ? l10n.cropMgmtStorageLifeRequired
                        : l10n.cropMgmtStorageLifeInvalid,
                  );
                  return;
                }
                setSheet(() => isSaving = true);
                final storageFailure = await _repo.setStorageLife(
                  item.id,
                  storageDays,
                );
                if (storageFailure != null) {
                  if (!ctx.mounted) return;
                  setSheet(() => isSaving = false);
                  PostActionFeedback.error(
                    ctx,
                    friendlyError(l10n, storageFailure),
                  );
                  return;
                }
                // Saved only when it differs from what the request carries.
                if (days != item.shelfLifeDays) {
                  setSheet(() => isSaving = true);
                  final failure = await _repo.setShelfLife(item.id, days);
                  if (failure != null) {
                    if (!ctx.mounted) return;
                    setSheet(() => isSaving = false);
                    PostActionFeedback.error(ctx, friendlyError(l10n, failure));
                    return;
                  }
                }
              }
              setSheet(() => isSaving = true);
              final ok = approve
                  ? await _repo.approve(
                      item.id,
                      notes: notesCtrl.text.trim().isEmpty
                          ? null
                          : notesCtrl.text.trim(),
                      cropType: selectedCropType,
                    )
                  : await _repo.reject(item.id, notesCtrl.text.trim());
              if (ok) {
                AdminActivityRepository().log(
                  module: 'crops',
                  actionType: approve ? 'approved' : 'rejected',
                  message: approve
                      ? AdminLogMessage('adminLogCropRequestApproved', {
                          'farmer': item.farmerName,
                          'crop': item.requestedName,
                        })
                      : AdminLogMessage('adminLogCropRequestRejected', {
                          'farmer': item.farmerName,
                          'crop': item.requestedName,
                        }),
                  referenceId: item.id,
                );
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              if (ok) _load();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? (approve
                              ? l10n.cropRequestApprovedToast
                              : l10n.cropRequestDeclinedToast)
                        : l10n.cropRequestFailedTryAgain,
                  ),
                  backgroundColor: ok
                      ? AppConstants.midGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: item.requestedName,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item.farmerName.isEmpty ? l10n.enhUnknown : item.farmerName} · ${localizeBuiltinLabel(l10n, item.category)}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.cropRequestApprovingNote,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  AppDropdownField<String>(
                    value: selectedCropType,
                    labelText: l10n.cropRequestCropTypeLabel,
                    hintText: l10n.cropRequestCropTypeLabel,
                    helperText: l10n.cropRequestCropTypeHelper,
                    items: [
                      for (final t in MarketTypes.instance.activeTypes) t.code,
                    ],
                    itemLabel: MarketTypes.instance.label,
                    onChanged: (v) {
                      if (v != null) setSheet(() => selectedCropType = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: shelfCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onChanged: (_) {
                      if (shelfError != null) {
                        setSheet(() => shelfError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: '${l10n.shelfLifeLabel} *',
                      hintText: l10n.cropMgmtShelfLifeHint,
                      suffixText: l10n.shelfDaysUnit,
                      errorText: shelfError,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.cropMgmtShelfLifeHelp,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: storageCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    onChanged: (_) {
                      if (storageError != null) {
                        setSheet(() => storageError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: '${l10n.cropMgmtStorageLifeLabel} *',
                      hintText: l10n.cropMgmtStorageLifeHint,
                      suffixText: l10n.shelfDaysUnit,
                      errorText: storageError,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.cropMgmtStorageLifeHelp,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.cropRequestNotesLabel,
                      hintText: l10n.cropRequestNotesHint,
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              footer: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSaving ? null : () => respond(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppConstants.errorRed,
                        side: const BorderSide(color: AppConstants.errorRed),
                      ),
                      child: Text(l10n.commonReject),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : () => respond(true),
                      child: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l10n.farmerMgmtApproveAction),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            SubPageTopBar(
              title: l10n.cropRequestTitle,
              onBack: () => context.pop(),
            ),
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: [
                Tab(text: l10n.cropRequestPendingTab(_pending.length)),
                Tab(text: l10n.cropRequestReviewedTab),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SkeletonList(),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(_pending, cs, sagana, isPending: true),
                        _buildList(_reviewed, cs, sagana, isPending: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    List<CropRequestItem> items,
    ColorScheme cs,
    SaganaColors sagana, {
    required bool isPending,
  }) {
    final l10n = AppLocalizations.of(context);
    if (items.isEmpty) {
      return Center(
        child: Text(
          isPending ? l10n.cropRequestNoPending : l10n.cropRequestNoReviewed,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final item = items[i];
          final statusColor = item.status == 'approved'
              ? AppConstants.successGreen
              : item.status == 'rejected'
              ? AppConstants.errorRed
              : AppConstants.amber;
          return GestureDetector(
            onTap: isPending ? () => _showReviewModal(item) : null,
            child: Container(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border(left: BorderSide(color: statusColor, width: 4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.requestedName,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          '${item.farmerName.isEmpty ? l10n.enhUnknown : item.farmerName} · ${localizeBuiltinLabel(l10n, item.category)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (item.shelfLifeDays != null)
                          Text(
                            l10n.cropRequestShelfLifeLine(item.shelfLifeDays!),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (!isPending &&
                            item.adminNotes != null &&
                            item.adminNotes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '"${item.adminNotes}"',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isPending)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                      ),
                      child: Text(
                        item.status.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
