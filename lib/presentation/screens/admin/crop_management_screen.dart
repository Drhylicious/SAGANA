import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';

// ── Model ────────────────────────────────────────────────────────────────────

class CropMasterItem {
  final String id;
  final String cropName;
  final String category;
  final String cropType;
  final String? description;
  final bool isActive;
  final int sortOrder;

  const CropMasterItem({
    required this.id,
    required this.cropName,
    required this.category,
    required this.cropType,
    this.description,
    required this.isActive,
    required this.sortOrder,
  });

  factory CropMasterItem.fromMap(Map<String, dynamic> m) => CropMasterItem(
        id: m['id'] as String,
        cropName: m['crop_name'] as String,
        category: m['category'] as String? ?? 'Other',
        cropType: m['crop_type'] as String? ?? 'open_market',
        description: m['description'] as String?,
        isActive: m['is_active'] as bool? ?? true,
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  String get cropTypeLabel {
    switch (cropType) {
      case 'sp3_cooperative': return 'Cooperative Crop';
      case 'da_amad_market':  return 'DA-AMAD Reference';
      default:                return 'Open Market';
    }
  }
}

// ── Repository ───────────────────────────────────────────────────────────────

class _CropMasterRepository {
  final _client = Supabase.instance.client;

  Future<List<CropMasterItem>> fetchAll() async {
    try {
      final rows = await _client
          .from('crop_master')
          .select()
          .order('sort_order')
          .order('crop_name');
      return rows.map((r) => CropMasterItem.fromMap(r)).toList();
    } catch (_) { return []; }
  }

  Future<bool> addCrop({
    required String name,
    required String category,
    required String cropType,
    String? description,
  }) async {
    try {
      await _client.from('crop_master').insert({
        'crop_name': name.trim(),
        'category': category,
        'crop_type': cropType,
        'description': description?.trim(),
        'created_by': _client.auth.currentUser?.id,
      });
      return true;
    } catch (_) { return false; }
  }

  Future<bool> updateCrop({
    required String id,
    required String name,
    required String category,
    required String cropType,
    String? description,
  }) async {
    try {
      await _client.from('crop_master').update({
        'crop_name': name.trim(),
        'category': category,
        'crop_type': cropType,
        'description': description?.trim(),
      }).eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  Future<bool> toggleActive(String id, bool newValue) async {
    try {
      await _client.from('crop_master')
          .update({'is_active': newValue}).eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  Future<bool> deleteCrop(String id) async {
    try {
      await _client.from('crop_master').delete().eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  Future<int> fetchPendingRequestCount() async {
    try {
      final rows = await _client
          .from('crop_requests')
          .select('id')
          .eq('status', 'pending');
      return rows.length;
    } catch (_) { return 0; }
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class CropManagementScreen extends StatefulWidget {
  const CropManagementScreen({super.key});

  @override
  State<CropManagementScreen> createState() => _CropManagementScreenState();
}

class _CropManagementScreenState extends State<CropManagementScreen> {
  final _repo = _CropMasterRepository();

  List<CropMasterItem> _crops = [];
  bool _isLoading = true;
  bool _isOnline = true;
  int _pendingRequestCount = 0;

  static const _categories = [
    'Grain', 'Legume', 'Root & Spice Crop',
    'Fruit', 'Tree Crop', 'Vegetable', 'Other',
  ];

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
    final result = await _repo.fetchAll();
    final pendingCount = await _repo.fetchPendingRequestCount();
    if (!mounted) return;
    setState(() {
      _crops = result;
      _pendingRequestCount = pendingCount;
      _isLoading = false;
    });
  }

  List<CropMasterItem> get _filtered =>
      _crops.where((c) => c.isActive).toList();

  void _showAddSheet() => _showCropSheet(null);
  void _showEditSheet(CropMasterItem crop) => _showCropSheet(crop);

  void _showCropSheet(CropMasterItem? existing) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.cropName ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    String selectedCategory = existing?.category ?? 'Other';
    String selectedCropType = existing?.cropType ?? 'open_market';
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            setSheet(() => isSaving = true);
            bool ok;
            if (existing == null) {
              ok = await _repo.addCrop(
                name: nameCtrl.text,
                category: selectedCategory,
                cropType: selectedCropType,
                description: descCtrl.text.isEmpty ? null : descCtrl.text,
              );
            } else {
              ok = await _repo.updateCrop(
                id: existing.id,
                name: nameCtrl.text,
                category: selectedCategory,
                cropType: selectedCropType,
                description: descCtrl.text.isEmpty ? null : descCtrl.text,
              );
            }
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
              content: Text(ok
                  ? existing == null
                      ? 'Crop added successfully'
                      : 'Crop updated'
                  : 'Failed. Please try again.'),
              backgroundColor:
                  ok ? AppConstants.successGreen : AppConstants.errorRed,
              behavior: SnackBarBehavior.floating,
            ));
          }

          return ManagementModalShell(
            title: existing == null ? 'Add New Crop' : 'Edit Crop',
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Crop Name *',
                      hintText: 'e.g. Ginger, Banana',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Crop name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category *'),
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setSheet(() => selectedCategory = v!),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCropType,
                    decoration: const InputDecoration(
                      labelText: 'Market Type *',
                      helperText: 'Determines which price types apply to this crop',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'sp3_cooperative', child: Text('Cooperative Market (SP3 Buying)')),
                      DropdownMenuItem(value: 'da_amad_market', child: Text('DA-AMAD Reference Market')),
                      DropdownMenuItem(value: 'open_market', child: Text('Open Market Crop')),
                    ],
                    onChanged: (v) => setSheet(() => selectedCropType = v!),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'Routing, market, or program notes',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving
                  ? 'Saving…'
                  : existing == null
                      ? 'Add Crop'
                      : 'Save Changes',
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  void _showArchivedSheet() async {
    final all = await _repo.fetchAll();
    final archived = all.where((c) => !c.isActive).toList();
    if (!mounted) return;

    showManagementModal(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ManagementModalShell(
          title: 'Archived Crops',
          subtitle: '${archived.length} archived',
          bodyIsScrollable: true,
          body: archived.isEmpty
              ? Center(
                  child: Text(
                    'No archived crops',
                    style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  itemCount: archived.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
                  itemBuilder: (_, i) {
                    final crop = archived[i];
                    return ListTile(
                      tileColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      title: Text(crop.cropName,
                          style: GoogleFonts.inter(
                              fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
                      subtitle: Text(crop.category,
                          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                      trailing: GestureDetector(
                        onTap: () async {
                          final ok = await _repo.toggleActive(crop.id, true);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (ok) _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                          ),
                          child: Text('Restore',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.primaryGreen)),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  void _confirmDelete(CropMasterItem crop) {
    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text('Delete "${crop.cropName}"?',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: Text(
            'This will permanently remove the crop from the master list. '
            'Existing farmer records using this crop will not be affected.',
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await _repo.deleteCrop(crop.id);
                if (ok) _load();
              },
              child: const Text('Delete',
                  style: TextStyle(color: AppConstants.errorRed)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;

    // Group by category
    final Map<String, List<CropMasterItem>> grouped = {};
    for (final c in filtered) {
      grouped.putIfAbsent(c.category, () => []).add(c);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _isOnline
          ? FloatingActionButton(
              onPressed: _showAddSheet,
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
                  left: 8, right: 8,
                ),
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
                        'Crop Management',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
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
                  Text('Offline — changes will not be saved',
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
                    child: filtered.isEmpty
                        ? ListView(children: [
                            if (_pendingRequestCount > 0) ...[
                              GestureDetector(
                                onTap: () => context
                                    .push(AppRoutes.cropRequestApproval)
                                    .then((_) => _load()),
                                child: Container(
                                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppConstants.amber
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(
                                        AppConstants.radiusLg),
                                    border: Border.all(
                                        color: AppConstants.amber
                                            .withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                          Icons.pending_actions_rounded,
                                          color: AppConstants.amber,
                                          size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '$_pendingRequestCount crop request${_pendingRequestCount == 1 ? '' : 's'} awaiting review',
                                          style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: cs.onSurface),
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded,
                                          color: AppConstants.amber),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 100),
                            Center(
                              child: Column(children: [
                                Icon(Icons.grass_rounded,
                                    size: 48,
                                    color: cs.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text('No crops in master list',
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant)),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _showAddSheet,
                                  child: const Text('Add First Crop'),
                                ),
                              ]),
                            ),
                          ])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(
                                20, 16, 20, 40),
                            children: [
                              // Pending crop requests banner
                              if (_pendingRequestCount > 0) ...[
                                GestureDetector(
                                  onTap: () => context
                                      .push(AppRoutes.cropRequestApproval)
                                      .then((_) => _load()),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppConstants.amber
                                          .withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(
                                          AppConstants.radiusLg),
                                      border: Border.all(
                                          color: AppConstants.amber
                                              .withValues(alpha: 0.25)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                            Icons.pending_actions_rounded,
                                            color: AppConstants.amber,
                                            size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            '$_pendingRequestCount crop request${_pendingRequestCount == 1 ? '' : 's'} awaiting review',
                                            style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: cs.onSurface),
                                          ),
                                        ),
                                        Icon(Icons.chevron_right_rounded,
                                            color: AppConstants.amber),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              // Summary pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(
                                      AppConstants.radiusMd),
                                ),
                                child: Row(children: [
                                  Icon(Icons.grass_rounded,
                                      size: 16, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${filtered.length} crop${filtered.length == 1 ? '' : 's'} in master list',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 16),

                              // Grouped by category
                              for (final category in grouped.keys) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 8, top: 4),
                                  child: Text(
                                    category.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: sagana.cardBackground,
                                    borderRadius: BorderRadius.circular(
                                        AppConstants.radiusLg),
                                    border: Border.all(
                                        color: cs.outline
                                            .withValues(alpha: 0.10)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.03),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: grouped[category]!
                                        .asMap()
                                        .entries
                                        .map((entry) {
                                      final i = entry.key;
                                      final crop = entry.value;
                                      final isLast = i ==
                                          grouped[category]!.length - 1;
                                      return Column(children: [
                                        GestureDetector(
                                          onTap: () => _showEditSheet(crop),
                                          behavior: HitTestBehavior.opaque,
                                          child: Padding(
                                          padding: const EdgeInsets
                                              .symmetric(
                                              horizontal: 14,
                                              vertical: 12),
                                          child: Row(children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start,
                                                children: [
                                                  Row(children: [
                                                    Text(
                                                      crop.cropName,
                                                      style: GoogleFonts
                                                          .poppins(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: crop.isActive
                                                            ? cs.onSurface
                                                            : cs
                                                                .onSurfaceVariant,
                                                      ),
                                                    ),
                                                    if (!crop.isActive) ...[
                                                      const SizedBox(
                                                          width: 8),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: cs.outline
                                                              .withValues(
                                                                  alpha:
                                                                      0.15),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            AppConstants
                                                                .radiusFull,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          'ARCHIVED',
                                                          style: GoogleFonts
                                                              .inter(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700,
                                                            color: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ]),
                                                  if (crop.description !=
                                                      null)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets
                                                              .only(top: 2),
                                                      child: Text(
                                                        crop.description!,
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              icon: Icon(
                                                  Icons.more_vert_rounded,
                                                  size: 20,
                                                  color:
                                                      cs.onSurfaceVariant),
                                              onSelected: (v) async {
                                                switch (v) {
                                                  case 'archive':
                                                    final ok = await _repo.toggleActive(
                                                        crop.id, false);
                                                    if (ok) _load();
                                                    break;
                                                  case 'delete':
                                                    _confirmDelete(crop);
                                                    break;
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                PopupMenuItem(
                                                  value: 'archive',
                                                  child: Row(children: [
                                                    const Icon(
                                                        Icons.archive_rounded,
                                                        size: 16),
                                                    const SizedBox(
                                                        width: 8),
                                                    Text('Archive',
                                                        style:
                                                            GoogleFonts.inter()),
                                                  ]),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(children: [
                                                    const Icon(
                                                        Icons.delete_rounded,
                                                        size: 16,
                                                        color: AppConstants
                                                            .errorRed),
                                                    const SizedBox(
                                                        width: 8),
                                                    Text('Delete',
                                                        style: GoogleFonts
                                                            .inter(
                                                          color:
                                                              AppConstants
                                                                  .errorRed,
                                                        )),
                                                  ]),
                                                ),
                                              ],
                                            ),
                                          ]),
                                          ),
                                        ),
                                        if (!isLast)
                                          Divider(
                                              height: 1,
                                              indent: 14,
                                              endIndent: 14,
                                              color: cs.outline.withValues(
                                                  alpha: 0.08)),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _showArchivedSheet,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: sagana.cardBackground,
                                    borderRadius: BorderRadius.circular(
                                        AppConstants.radiusLg),
                                    border: Border.all(
                                        color: cs.outline.withValues(alpha: 0.10)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.archive_rounded,
                                          size: 18,
                                          color: cs.onSurfaceVariant),
                                      const SizedBox(width: 8),
                                      Text(
                                        'View Archived Crops',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}