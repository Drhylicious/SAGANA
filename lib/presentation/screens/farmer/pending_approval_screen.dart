import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../../core/constants/app_constants.dart';
import '../../../../../../../core/theme/app_theme.dart';
import '../../../../../../../data/services/auth_service.dart';
import '../../../../../../../routes/app_routes.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  final _supabase = Supabase.instance.client;

  String _fullName = '';
  String _username = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final userId = AuthService.currentUser?.id;
      if (userId == null) return;
      final row = await _supabase
          .from('user_information')
          .select('full_name, username')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _fullName = row?['full_name'] as String? ?? 'Farmer';
        _username = row?['username'] as String? ?? '';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Sign Out',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to sign out?',
            style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign Out',
                  style:
                      TextStyle(color: AppConstants.errorRed))),
        ],
      ),
    );
    if (confirm == true) {
      await AuthService.logout();
      if (!mounted) return;
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    color: AppConstants.primaryGreen, strokeWidth: 2))
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Illustration
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: AppConstants.warningAmber.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        size: 48,
                        color: AppConstants.warningAmber,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Heading
                    Text(
                      'Membership Pending',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Message
                    Text(
                      'Hello, $_fullName!\n\n'
                      'Your account has been created successfully. '
                      'Your membership is currently awaiting verification '
                      'and approval by the SP3 Agriculture Cooperative.\n\n'
                      'You will receive an in-app notification as soon as '
                      'your membership has been approved.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Username card
                    if (_username.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMd),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.badge_outlined,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Your SAGANA Username',
                                    style: GoogleFonts.inter(
                                        fontSize: 10,
                                        color: cs.onSurfaceVariant)),
                                Text(
                                  _username.toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 40),

                    // Contact info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryGreen.withValues(alpha: 0.06),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusLg),
                        border: Border.all(
                          color: AppConstants.primaryGreen
                              .withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppConstants.primaryGreen,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'If you have questions, please contact the '
                              'SP3 Cooperative office in Barangay Payanas, '
                              'Torrijos, Marinduque.',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: cs.onSurface,
                                  height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(flex: 3),

                    // Sign out button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: Text('Sign Out',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}