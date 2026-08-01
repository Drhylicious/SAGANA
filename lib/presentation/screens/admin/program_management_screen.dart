import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../data/models/program_model.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/management_modal.dart';

// ── Screen ───────────────────────────────────────────────────────────────────

class ProgramManagementScreen extends StatefulWidget {
  const ProgramManagementScreen({super.key});

  @override
  State<ProgramManagementScreen> createState() =>
      _ProgramManagementScreenState();
}

class _ProgramManagementScreenState extends State<ProgramManagementScreen> {
  final _repo = ProgramRepository();

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
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            final budget = double.tryParse(budgetCtrl.text);
            setSheet(() => isSaving = true);
            bool ok;
            if (existing == null) {
              ok = await _repo.createProgram(
                name: nameCtrl.text,
                type: typeCtrl.text.trim(),
                benefitType: selectedBenefitType,
                expectedReturnPercent: double.tryParse(returnPercentCtrl.text),
                description: descCtrl.text.isEmpty ? null : descCtrl.text,
                budget: budget,
              );
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
              );
            }
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
              content: Text(ok
                  ? existing == null
                      ? 'Program created'
                      : 'Program updated'
                  : 'Failed. Try again.'),
              backgroundColor:
                  ok ? AppConstants.successGreen : AppConstants.errorRed,
              behavior: SnackBarBehavior.floating,
            ));
          }

          return ManagementModalShell(
            title: existing == null ? 'New Program' : 'Edit Program',
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Program Name *',
                      hintText: 'e.g. Palay Production Program 2025',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Program name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: typeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Program Type / Category (optional)',
                      hintText: 'e.g. Crop Production, Livestock, DA-AMAD',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBenefitType,
                    decoration: const InputDecoration(labelText: 'Benefit Type *'),
                    items: const [
                      DropdownMenuItem(value: 'grant', child: Text('Grant — no return expected')),
                      DropdownMenuItem(value: 'revenue_share', child: Text('Revenue Share — farmer returns a % later')),
                    ],
                    onChanged: (v) => setSheet(() => selectedBenefitType = v!),
                  ),
                  if (selectedBenefitType == 'revenue_share') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: returnPercentCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Expected Return % (cooperative-wide) — optional',
                        hintText: 'e.g. 20',
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
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(labelText: 'Status *'),
                      items: _statusOptions
                          .map((s) => DropdownMenuItem(
                              value: s, child: Text(s[0].toUpperCase() + s.substring(1))))
                          .toList(),
                      onChanged: (v) => setSheet(() => selectedStatus = v!),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: budgetCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Budget (₱) — optional',
                      hintText: '0.00',
                      prefixText: '₱ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) return null;
                      if (!isValidCurrencyValue(value)) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'Goals, target crops, or beneficiaries',
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving
                  ? 'Saving…'
                  : existing == null
                      ? 'Create Program'
                      : 'Save Changes',
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
        return DefaultTabController(
          length: 2,
          child: ManagementModalShell(
            title: program.programName,
            bodyIsScrollable: true,
            body: Column(
              children: [
                const TabBar(
                  tabs: [Tab(text: 'Members'), Tab(text: 'Activities')],
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

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppConstants.errorRed : AppConstants.successGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─── Distribute benefit ─────────────────────────────────────────────────

  void _showDistributeSheet(ProgramMember member) {
    if (_items.isEmpty) {
      _showSnack('No active cooperative inventory items available.', isError: true);
      return;
    }
    String? selectedItemId = _items.first.id;
    final qtyCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showManagementModal(
      context: context,
      builder: (ctx) {
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
              _showSnack('Benefit distributed to ${member.farmerName}');
              _loadMembers();
            } catch (_) {
              setSheet(() => isSaving = false);
              _showSnack('Failed to distribute. Try again.', isError: true);
            }
          }

          final selected = _itemsById[selectedItemId];

          return ManagementModalShell(
            title: 'Distribute Benefit',
            subtitle: member.farmerName,
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedItemId,
                    decoration: const InputDecoration(labelText: 'Item *'),
                    items: _items
                        .map((i) => DropdownMenuItem(
                              value: i.id,
                              child: Text(
                                '${i.itemName} (${i.quantityOnHand.toStringAsFixed(1)} ${i.unit} on hand)',
                                style: GoogleFonts.inter(fontSize: 13),
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setSheet(() => selectedItemId = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qtyCtrl,
                    decoration: InputDecoration(
                      labelText: 'Quantity${selected != null ? ' (${selected.unit})' : ''} *',
                      hintText: '0.00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      final v = double.tryParse(value ?? '');
                      if (v == null || v <= 0) return 'Enter a valid quantity';
                      if (selected != null && v > selected.quantityOnHand) {
                        return 'Only ${selected.quantityOnHand.toStringAsFixed(1)} ${selected.unit} available';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? 'Distributing…' : 'Distribute',
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
              _showSnack('Return recorded for ${member.farmerName}');
              _loadMembers();
            } catch (_) {
              setSheet(() => isSaving = false);
              _showSnack('Failed to record return. Try again.', isError: true);
            }
          }

          return ManagementModalShell(
            title: 'Record Return',
            subtitle: member.farmerName,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.program.expectedReturnPercent != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                    child: Text(
                      'Cooperative policy: ${widget.program.expectedReturnPercent}% expected return',
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
                    decoration: const InputDecoration(
                      labelText: 'Amount Returned (₱) *',
                      hintText: '0.00',
                      prefixText: '₱ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (!isValidCurrencyValue(value)) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'e.g. sold to local buyer, 2 heads',
                    ),
                    maxLines: 2,
                  ),
                    ],
                  ),
                ),
              ],
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? 'Saving…' : 'Confirm Return',
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            _isLoading
                ? 'Loading members…'
                : '${_members.length} member${_members.length == 1 ? '' : 's'} enrolled',
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        if (_unenrolled.isNotEmpty)
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                            child: Text(f['name'] ?? 'Unknown', style: GoogleFonts.inter(fontSize: 13))))
                        .toList(),
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
                      'Enroll',
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
                        child: Text('No members enrolled yet',
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
                                      Text('Enrolled ${_formatDate(m.enrolledAt)}',
                                          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                                      if (m.isDistributed) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Distributed ${m.quantityGiven?.toStringAsFixed(1)}'
                                          '${item != null ? ' ${item.unit} ${item.itemName}' : ''}'
                                          ' on ${_formatDate(m.distributedAt!)}',
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppConstants.primaryGreen),
                                        ),
                                      ],
                                      if (m.isSettled) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Settled ₱${m.amountReturned?.toStringAsFixed(2)} on ${_formatDate(m.settledAt!)}',
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppConstants.successGreen),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          if (!m.isDistributed)
                                            _ActionChip(
                                              label: 'Distribute',
                                              color: AppConstants.primaryGreen,
                                              filled: true,
                                              onTap: () => _showDistributeSheet(m),
                                            )
                                          else if (widget.program.isRevenueShare && !m.isSettled)
                                            _ActionChip(
                                              label: 'Record Return',
                                              color: AppConstants.warningAmber,
                                              filled: true,
                                              onTap: () => _showRecordReturnSheet(m),
                                            )
                                          else
                                            _ActionChip(
                                              label: widget.program.isRevenueShare ? 'Settled' : 'Distributed',
                                              color: AppConstants.successGreen,
                                              filled: false,
                                              onTap: null,
                                              icon: Icons.check_circle_rounded,
                                            ),
                                          _ActionChip(
                                            label: 'Remove',
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
            title: 'New Activity',
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title *'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Date: ${selectedDate.month}/${selectedDate.day}/${selectedDate.year}'),
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
                    decoration: const InputDecoration(labelText: 'Location (optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? 'Saving…' : 'Add Activity',
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _showAddActivitySheet,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Activity'),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen, strokeWidth: 2))
              : _activities.isEmpty
                  ? Center(
                      child: Text('No activities scheduled yet',
                          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: _activities.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
                      itemBuilder: (_, i) {
                        final a = _activities[i];
                        return ListTile(
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