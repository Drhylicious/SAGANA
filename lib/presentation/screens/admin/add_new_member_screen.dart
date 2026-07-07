import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/add_member_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/shared_widgets.dart';

// SP3's real 5 primary crops, consistent with the rest of the app
const _kSp3PrimaryCrops = ['Peanut', 'Ginger', 'Banana', 'Palay', 'Copra'];

class AddNewMemberScreen extends StatefulWidget {
  const AddNewMemberScreen({super.key});

  @override
  State<AddNewMemberScreen> createState() => _AddNewMemberScreenState();
}

class _AddNewMemberScreenState extends State<AddNewMemberScreen> {
  final _repo    = AddMemberRepository();
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ────────────────────────────────────────────────────────────
  final _emailCtrl       = TextEditingController();
  final _passwordCtrl    = TextEditingController();
  final _fullNameCtrl    = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _memberIdCtrl    = TextEditingController();
  final _capitalSharesCtrl = TextEditingController(text: '100');
  final _shareValueCtrl    = TextEditingController(text: '1000');

  // ── Form state ─────────────────────────────────────────────────────────────
  String? _selectedSitio;
  bool    _obscurePassword = true;
  final List<String> _selectedCrops = [];

  bool _isSaving  = false;
  bool _isOnline  = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadSuggestedMemberId();
  }

  Future<void> _loadSuggestedMemberId() async {
    final suggested = await _repo.suggestNextMemberId();
    if (mounted) _memberIdCtrl.text = suggested;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _memberIdCtrl.dispose();
    _capitalSharesCtrl.dispose();
    _shareValueCtrl.dispose();
    super.dispose();
  }

  // ── Password generation ─────────────────────────────────────────────────────

  void _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final rand  = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    for (int i = 0; i < 10; i++) {
      buffer.write(chars[(rand + i * 17) % chars.length]);
    }
    setState(() {
      _passwordCtrl.text = buffer.toString();
      _obscurePassword   = false;
    });
  }

  // ── Crop selection ────────────────────────────────────────────────────────

  void _showCropDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          ),
          title: Text(
            'Select Crop',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: cs.primary),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.4,
              children: _kSp3PrimaryCrops
                  .where((c) => !_selectedCrops.contains(c))
                  .map((crop) => GestureDetector(
                        onTap: () {
                          setState(() => _selectedCrops.add(crop));
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: cs.outline.withValues(alpha: 0.20)),
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd),
                          ),
                          child: Text(
                            crop,
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSitio == null) {
      _showSnack('Please select a sitio/purok.');
      return;
    }

    final capitalShares = int.tryParse(_capitalSharesCtrl.text.trim()) ?? 0;
    final shareValue    = double.tryParse(_shareValueCtrl.text.trim()) ?? 0;

    setState(() => _isSaving = true);

    final result = await _repo.createMember(
      email:             _emailCtrl.text.trim(),
      password:          _passwordCtrl.text.trim(),
      fullName:          _fullNameCtrl.text.trim(),
      phoneNumber:       _phoneCtrl.text.trim(),
      sitio:             _selectedSitio!,
      memberId:          _memberIdCtrl.text.trim(),
      capitalShares:     capitalShares,
      shareValuePerUnit: shareValue,
      initialCrops:      _selectedCrops,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.isSuccess) {
      _showSnack(
        '${_fullNameCtrl.text.trim()} was added successfully.',
        isSuccess: true,
      );
      context.pop(true);
    } else if (result.isPartial) {
      _showSnack(
        '${result.failedStep} step had an issue: ${result.message}',
      );
      // Member account exists — still pop back so admin sees them in the list
      context.pop(true);
    } else {
      _showSnack(result.message ?? 'Failed to create member. Please try again.');
    }
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor:
            isSuccess ? AppConstants.successGreen : AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                    children: [

                      // ── Admin notice ────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.06),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusLg),
                          border: Border(
                            left: BorderSide(color: cs.primary, width: 4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                color: cs.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Admin Notice',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'The member will be created with active status and can log in immediately using the credentials below.',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Account Credentials ─────────────────────────────
                      _FormSection(
                        icon: Icons.lock_person_rounded,
                        title: 'Account Credentials',
                        cs: cs,
                        sagana: sagana,
                        children: [
                          _FieldLabel(label: 'Email Address', cs: cs),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              hintText: 'farmer@coop.com',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Email is required';
                              }
                              if (!v.contains('@') || !v.contains('.')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          _FieldLabel(label: 'Temporary Password', cs: cs),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                      color: cs.outline,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        right: 8),
                                    child: GestureDetector(
                                      onTap: _generatePassword,
                                      child: Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: cs.primary
                                                .withValues(alpha: 0.30),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(
                                                  AppConstants.radiusSm),
                                        ),
                                        child: Text(
                                          'AUTO',
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Password is required';
                              }
                              if (v.length < 8) {
                                return 'Minimum 8 characters';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Personal Information ─────────────────────────────
                      _FormSection(
                        icon: Icons.person_rounded,
                        title: 'Personal Information',
                        cs: cs,
                        sagana: sagana,
                        children: [
                          _FieldLabel(label: 'Full Name', cs: cs),
                          TextFormField(
                            controller: _fullNameCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Juan Dela Cruz',
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Full name is required'
                                    : null,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                        label: 'Phone Number', cs: cs),
                                    TextFormField(
                                      controller: _phoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(
                                        hintText: '09XX XXX XXXX',
                                      ),
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? 'Required'
                                              : null,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                        label: 'Sitio / Purok', cs: cs),
                                    DropdownButtonFormField<String>(
                                      initialValue: _selectedSitio,
                                      isExpanded: true,
                                      hint: Text(
                                        'Select',
                                        style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: cs.outline),
                                      ),
                                      items: AppConstants.payanasSitios
                                          .map((s) => DropdownMenuItem(
                                                value: s,
                                                child: Text(
                                                  s,
                                                  style: GoogleFonts.inter(
                                                      fontSize: 13),
                                                  overflow: TextOverflow
                                                      .ellipsis,
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (v) => setState(
                                          () => _selectedSitio = v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Cooperative Membership ────────────────────────────
                      _FormSection(
                        icon: Icons.badge_rounded,
                        title: 'Cooperative Membership',
                        cs: cs,
                        sagana: sagana,
                        children: [
                          _FieldLabel(label: 'Member ID', cs: cs),
                          TextFormField(
                            controller: _memberIdCtrl,
                            decoration: const InputDecoration(
                              hintText: 'SP3-2026-001',
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                        label: 'Capital Shares', cs: cs),
                                    TextFormField(
                                      controller: _capitalSharesCtrl,
                                      keyboardType:
                                          TextInputType.number,
                                      validator: (v) {
                                        if (v != null &&
                                            v.isNotEmpty &&
                                            int.tryParse(v) == null) {
                                          return 'Whole number';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                        label: 'Share Value (₱)', cs: cs),
                                    TextFormField(
                                      controller: _shareValueCtrl,
                                      keyboardType: const TextInputType
                                          .numberWithOptions(
                                              decimal: true),
                                      validator: (v) {
                                        if (v != null &&
                                            v.isNotEmpty &&
                                            double.tryParse(v) == null) {
                                          return 'Invalid number';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Initial Crops ──────────────────────────────────────
                      _FormSection(
                        icon: Icons.eco_rounded,
                        title: 'Initial Crops',
                        cs: cs,
                        sagana: sagana,
                        trailing: GestureDetector(
                          onTap: _showCropDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded,
                                    size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Add Crop',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        children: [
                          Container(
                            width: double.infinity,
                            constraints:
                                const BoxConstraints(minHeight: 50),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: cs.outline.withValues(alpha: 0.20),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMd),
                            ),
                            child: _selectedCrops.isEmpty
                                ? Center(
                                    child: Text(
                                      'No crops added yet',
                                      style: GoogleFonts.inter(
                                          fontSize: 12, color: cs.outline),
                                    ),
                                  )
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _selectedCrops
                                        .map((crop) => Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                horizontal: 12,
                                                vertical: 7,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppConstants
                                                    .primaryContainer
                                                    .withValues(alpha: 0.20),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppConstants
                                                            .radiusFull),
                                              ),
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    crop,
                                                    style: GoogleFonts
                                                        .inter(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: cs.primary,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  GestureDetector(
                                                    onTap: () => setState(
                                                        () =>
                                                            _selectedCrops
                                                                .remove(
                                                                    crop)),
                                                    child: Icon(
                                                      Icons.close_rounded,
                                                      size: 14,
                                                      color: cs.primary
                                                          .withValues(
                                                              alpha: 0.60),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ))
                                        .toList(),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ─────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              onBack: () => context.pop(),
              onSave: _isSaving ? null : _save,
              cs: cs,
              sagana: sagana,
            ),
          ),

          // ── Bottom action ────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .scaffoldBackgroundColor
                    .withValues(alpha: 0.95),
                border: Border(
                  top: BorderSide(
                      color: cs.outline.withValues(alpha: 0.10)),
                ),
              ),
              child: PrimaryButton(
                label: !_isOnline
                    ? 'Offline — Cannot Create Account'
                    : (_isSaving
                        ? 'Creating Account...'
                        : 'Create Farmer Account'),
                isLoading: _isSaving,
                onPressed: (!_isOnline || _isSaving) ? null : _save,
                icon: Icons.person_add_alt_1_rounded,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _TopAppBar({
    required this.onBack,
    required this.onSave,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  'Add New Member',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSave,
                child: Text(
                  'Save',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: onSave != null
                        ? cs.primary
                        : cs.outline.withValues(alpha: 0.50),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form Section Card
// ─────────────────────────────────────────────────────────────────────────────

class _FormSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final ColorScheme cs;
  final SaganaColors sagana;
  final Widget? trailing;

  const _FormSection({
    required this.icon,
    required this.title,
    required this.children,
    required this.cs,
    required this.sagana,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;

  const _FieldLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
