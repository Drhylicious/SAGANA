import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/services/connectivity_service.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class CooperativeProgram {
  final String id;
  final String programName;
  final String programType;
  final String? description;
  final int seasonYear;
  final String status;
  final double? budget;
  final int memberCount;

  const CooperativeProgram({
    required this.id,
    required this.programName,
    required this.programType,
    this.description,
    required this.seasonYear,
    required this.status,
    this.budget,
    required this.memberCount,
  });

  factory CooperativeProgram.fromMap(Map<String, dynamic> m) =>
      CooperativeProgram(
        id: m['id'] as String,
        programName: m['program_name'] as String,
        programType: m['program_type'] as String? ?? 'other',
        description: m['description'] as String?,
        seasonYear: m['season_year'] as int? ?? DateTime.now().year,
        status: m['status'] as String? ?? 'active',
        budget: m['budget'] != null ? (m['budget'] as num).toDouble() : null,
        memberCount: m['member_count'] as int? ?? 0,
      );

  bool get isActive => status == 'active';
}

class ProgramMember {
  final String id;
  final String programId;
  final String farmerId;
  final String farmerName;
  final String status;
  final DateTime enrolledAt;

  const ProgramMember({
    required this.id,
    required this.programId,
    required this.farmerId,
    required this.farmerName,
    required this.status,
    required this.enrolledAt,
  });

  factory ProgramMember.fromMap(Map<String, dynamic> m) => ProgramMember(
        id: m['id'] as String,
        programId: m['program_id'] as String,
        farmerId: m['farmer_id'] as String,
        farmerName: m['user_information']?['full_name'] as String? ?? 'Unknown',
        status: m['status'] as String? ?? 'active',
        enrolledAt: DateTime.parse(m['enrolled_at'] as String),
      );
}

// ── Repository ───────────────────────────────────────────────────────────────

class _ProgramRepository {
  final _client = Supabase.instance.client;

  Future<List<CooperativeProgram>> fetchPrograms() async {
    try {
      // Fetch programs with member count
      final rows = await _client
          .from('cooperative_programs')
          .select('*, program_members(count)')
          .order('season_year', ascending: false)
          .order('program_name');
      return rows.map((r) {
        final countList = r['program_members'] as List?;
        final count = countList?.isNotEmpty == true
            ? (countList!.first['count'] as int? ?? 0)
            : 0;
        return CooperativeProgram.fromMap({...r, 'member_count': count});
      }).toList();
    } catch (_) { return []; }
  }

  Future<List<ProgramMember>> fetchProgramMembers(String programId) async {
    try {
      final rows = await _client
          .from('program_members')
          .select('id, program_id, farmer_id, status, enrolled_at')
          .eq('program_id', programId)
          .eq('status', 'active')
          .order('enrolled_at', ascending: false);

      if (rows.isEmpty) return [];

      final farmerIds = rows.map((r) => r['farmer_id'] as String).toList();
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds);
      final nameMap = {
        for (final r in infoRows)
          r['user_id'] as String: r['full_name'] as String? ?? 'Unknown'
      };

      return rows.map((r) => ProgramMember(
        id: r['id'] as String,
        programId: r['program_id'] as String,
        farmerId: r['farmer_id'] as String,
        farmerName: nameMap[r['farmer_id'] as String] ?? 'Unknown',
        status: r['status'] as String? ?? 'active',
        enrolledAt: DateTime.parse(r['enrolled_at'] as String),
      )).toList();
    } catch (_) { return []; }
  }

  /// Returns farmers not yet enrolled in a given program
  Future<List<Map<String, String>>> fetchUnenrolledFarmers(
      String programId) async {
    try {
      final enrolled = await _client
          .from('program_members')
          .select('farmer_id')
          .eq('program_id', programId)
          .eq('status', 'active');
      final enrolledIds =
          enrolled.map((r) => r['farmer_id'] as String).toSet();

      final allRoles = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'active');

      final unenrolledIds = allRoles
          .map((r) => r['user_id'] as String)
          .where((id) => !enrolledIds.contains(id))
          .toList();

      if (unenrolledIds.isEmpty) return [];

      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', unenrolledIds);

      return infoRows.map((r) => {
        'id': r['user_id'] as String,
        'name': r['full_name'] as String? ?? 'Unknown',
      }).toList();
    } catch (_) { return []; }
  }

  Future<bool> createProgram({
    required String name,
    required String type,
    String? description,
    double? budget,
  }) async {
    try {
      await _client.from('cooperative_programs').insert({
        'program_name': name.trim(),
        'program_type': type,
        'description': description?.trim(),
        'budget': budget,
        'season_year': DateTime.now().year,
        'created_by': _client.auth.currentUser?.id,
      });
      return true;
    } catch (_) { return false; }
  }

  Future<bool> updateProgram({
    required String id,
    required String name,
    required String type,
    String? description,
    double? budget,
    required String status,
  }) async {
    try {
      await _client.from('cooperative_programs').update({
        'program_name': name.trim(),
        'program_type': type.trim(),
        'description': description?.trim(),
        'budget': budget,
        'status': status,
      }).eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  Future<bool> enrollFarmer(String programId, String farmerId) async {
    try {
      await _client.from('program_members').upsert({
        'program_id': programId,
        'farmer_id': farmerId,
        'status': 'active',
      }, onConflict: 'program_id,farmer_id');
      return true;
    } catch (_) { return false; }
  }

  Future<bool> removeMember(String memberId) async {
    try {
      await _client
          .from('program_members')
          .update({'status': 'withdrawn'}).eq('id', memberId);
      return true;
    } catch (_) { return false; }
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class ProgramManagementScreen extends StatefulWidget {
  const ProgramManagementScreen({super.key});

  @override
  State<ProgramManagementScreen> createState() =>
      _ProgramManagementScreenState();
}

class _ProgramManagementScreenState extends State<ProgramManagementScreen> {
  final _repo = _ProgramRepository();

  List<CooperativeProgram> _programs = [];
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
    final result = await _repo.fetchPrograms();
    if (!mounted) return;
    setState(() { _programs = result; _isLoading = false; });
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

  String _statusLabel(String status) {
    switch (status) {
      case 'active':    return 'ACTIVE';
      case 'completed': return 'COMPLETED';
      case 'suspended': return 'SUSPENDED';
      default:          return status.toUpperCase();
    }
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'active':    return AppConstants.successGreen;
      case 'completed': return AppConstants.buyerBlue;
      case 'suspended': return AppConstants.errorRed;
      default:          return cs.outline;
    }
  }

  void _showProgramSheet(CooperativeProgram? existing) {
    final nameCtrl =
        TextEditingController(text: existing?.programName ?? '');
    final typeCtrl =
        TextEditingController(text: existing?.programType ?? '');
    final descCtrl =
        TextEditingController(text: existing?.description ?? '');
    final budgetCtrl = TextEditingController(
        text: existing?.budget != null
            ? existing!.budget!.toStringAsFixed(2)
            : '');
    String selectedStatus = existing?.status ?? 'active';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sagana = ctx.saganaColors;
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppConstants.radiusXl)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: cs.outline.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      existing == null ? 'New Program' : 'Edit Program',
                      style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Program Name *',
                        hintText: 'e.g. Palay Production Program 2025',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Program Type / Category (optional)',
                        hintText: 'e.g. Crop Production, Livestock, DA-AMAD',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    if (existing != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration:
                            const InputDecoration(labelText: 'Status *'),
                        items: _statusOptions
                            .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                    s[0].toUpperCase() + s.substring(1))))
                            .toList(),
                        onChanged: (v) =>
                            setSheet(() => selectedStatus = v!),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: budgetCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Budget (₱) — optional',
                        hintText: '0.00',
                        prefixText: '₱ ',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'Goals, target crops, or beneficiaries',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (nameCtrl.text.trim().isEmpty) return;
                                final budget =
                                    double.tryParse(budgetCtrl.text);
                                setSheet(() => isSaving = true);
                                bool ok;
                                if (existing == null) {
                                  ok = await _repo.createProgram(
                                    name: nameCtrl.text,
                                    type: typeCtrl.text.trim(),
                                    description: descCtrl.text.isEmpty
                                        ? null
                                        : descCtrl.text,
                                    budget: budget,
                                  );
                                } else {
                                  ok = await _repo.updateProgram(
                                    id: existing.id,
                                    name: nameCtrl.text,
                                    type: typeCtrl.text.trim(),
                                    description: descCtrl.text.isEmpty
                                        ? null
                                        : descCtrl.text,
                                    budget: budget,
                                    status: selectedStatus,
                                  );
                                }
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                if (ok) _load();
                                ScaffoldMessenger.of(ctx)
                                    .showSnackBar(SnackBar(
                                  content: Text(ok
                                      ? existing == null
                                          ? 'Program created'
                                          : 'Program updated'
                                      : 'Failed. Try again.'),
                                  backgroundColor: ok
                                      ? AppConstants.successGreen
                                      : AppConstants.errorRed,
                                  behavior: SnackBarBehavior.floating,
                                ));
                              },
                        child: Text(
                          isSaving
                              ? 'Saving…'
                              : existing == null
                                  ? 'Create Program'
                                  : 'Save Changes',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  void _showMembersSheet(CooperativeProgram program) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sagana = ctx.saganaColors;
        return DraggableScrollableSheet(
          initialChildSize: 0.70,
          minChildSize: 0.40,
          maxChildSize: 0.92,
          builder: (ctx, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppConstants.radiusXl)),
              ),
              child: _ProgramMembersSheet(
                program: program,
                repo: _repo,
                scrollController: scrollCtrl,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

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
                        'Program Management',
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface),
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
                    child: _programs.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Column(children: [
                                Icon(Icons.people_alt_rounded,
                                    size: 48,
                                    color: cs.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text('No programs yet',
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant)),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () =>
                                      _showProgramSheet(null),
                                  child: const Text('Create First Program'),
                                ),
                              ]),
                            ),
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                                20, 16, 20, 40),
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
                                              Row(children: [
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: color.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                                  ),
                                                  child: Icon(icon, color: color, size: 22),
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
                                                        '${p.programType.isEmpty ? 'Custom program' : p.programType} · ${p.seasonYear}',
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
                                                    _statusLabel(p.status),
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
                                                Text(
                                                  '${p.memberCount} enrolled member${p.memberCount == 1 ? '' : 's'}',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                                if (p.budget != null) ...[
                                                  const SizedBox(width: 14),
                                                  Icon(Icons.account_balance_rounded, size: 14, color: cs.onSurfaceVariant),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '₱${p.budget!.toStringAsFixed(0)} budget',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12,
                                                      color: cs.onSurfaceVariant,
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
                                                          Text(
                                                            'Manage Members',
                                                            style: GoogleFonts.poppins(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w600,
                                                              color: cs.primary,
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
                                                        'Edit',
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: cs.onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ]),
                                                  ),
                                                ),
                                              ]),
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
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Program Members Sheet ─────────────────────────────────────────────────────

class _ProgramMembersSheet extends StatefulWidget {
  final CooperativeProgram program;
  final _ProgramRepository repo;
  final ScrollController scrollController;

  const _ProgramMembersSheet({
    required this.program,
    required this.repo,
    required this.scrollController,
  });

  @override
  State<_ProgramMembersSheet> createState() =>
      _ProgramMembersSheetState();
}

class _ProgramMembersSheetState extends State<_ProgramMembersSheet> {
  List<ProgramMember> _members = [];
  List<Map<String, String>> _unenrolled = [];
  bool _isLoading = true;
  String? _selectedFarmerId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      widget.repo.fetchProgramMembers(widget.program.id),
      widget.repo.fetchUnenrolledFarmers(widget.program.id),
    ]);
    if (!mounted) return;
    setState(() {
      _members = results[0] as List<ProgramMember>;
      _unenrolled = results[1] as List<Map<String, String>>;
      _isLoading = false;
    });
  }

  Future<void> _enroll() async {
    if (_selectedFarmerId == null) return;
    final ok = await widget.repo.enrollFarmer(
        widget.program.id, _selectedFarmerId!);
    if (ok) {
      setState(() => _selectedFarmerId = null);
      _loadMembers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Sheet handle + title
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.program.programName,
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.10),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      '${_members.length} member${_members.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),

        // Enroll new member row
        if (_unenrolled.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedFarmerId,
                  decoration: const InputDecoration(
                    labelText: 'Enroll a member',
                    isDense: true,
                  ),
                  items: _unenrolled
                      .map((f) => DropdownMenuItem(
                          value: f['id'],
                          child: Text(f['name'] ?? 'Unknown',
                              style: GoogleFonts.inter(fontSize: 13))))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedFarmerId = v),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _selectedFarmerId != null ? _enroll : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _selectedFarmerId != null
                        ? AppConstants.primaryGreen
                        : cs.surfaceContainerHighest,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Text(
                    'Enroll',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _selectedFarmerId != null
                          ? Colors.white
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ]),
          ),

        const SizedBox(height: 8),

        // Member list
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppConstants.primaryGreen, strokeWidth: 2))
              : _members.isEmpty
                  ? Center(
                      child: Text('No members enrolled yet',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: cs.onSurfaceVariant)))
                  : ListView.separated(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: _members.length,
                      separatorBuilder: (_, __) =>
                          Divider(
                              height: 1,
                              color: cs.outline.withValues(alpha: 0.08)),
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
                        return ListTile(
                          tileColor: Colors.transparent,
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                AppConstants.primaryContainer,
                            child: Text(initials,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                          title: Text(m.farmerName,
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface)),
                          subtitle: Text(
                            'Enrolled ${_formatDate(m.enrolledAt)}',
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurfaceVariant),
                          ),
                          trailing: GestureDetector(
                            onTap: () async {
                              final ok = await widget.repo
                                  .removeMember(m.id);
                              if (ok) _loadMembers();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppConstants.errorRed
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull),
                              ),
                              child: Text(
                                'Remove',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.errorRed,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}