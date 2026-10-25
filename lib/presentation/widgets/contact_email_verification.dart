import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/repositories/contact_email_verification_repository.dart';
import 'shared_widgets.dart';

/// The Verified / Unverified line under an Edit Profile email field, with the
/// "Verify Email" action and the inline code entry. The same widget in the
/// Manager, Officer, Farmer and Buyer Edit Profile screens.
///
///   Email Address  [ ana@gmail.com ]
///   ⚠ Unverified                             Verify Email
///
/// Tapping Verify Email first saves the address in the field (the host's
/// [saveEmail], which validates it and shows its own errors), then asks the
/// server to e-mail a 6-digit code. The code is typed into the field that opens
/// below; the server checks it. Nothing here decides ownership: only the
/// server's "verified" answer does, and anything else leaves the address
/// Unverified.
class ContactEmailVerification extends StatefulWidget {
  /// The email field. Read for what the person has typed so far.
  final TextEditingController emailController;

  /// The address saved on the account right now, or null.
  final String? savedEmail;

  /// The saved address has been proven (see ContactEmail.isVerified).
  final bool verified;

  /// Saves the address in the field. Returns true once it is stored on the
  /// server; false when it could not be (the host has already told the person
  /// why).
  final Future<bool> Function() saveEmail;

  /// The server confirmed the code. The host refreshes its saved/verified state.
  final VoidCallback onVerified;

  final bool isOnline;

  /// Test seam; the real server calls by default.
  final ContactEmailVerifier? verifier;

  const ContactEmailVerification({
    super.key,
    required this.emailController,
    required this.savedEmail,
    required this.verified,
    required this.saveEmail,
    required this.onVerified,
    this.isOnline = true,
    this.verifier,
  });

  @override
  State<ContactEmailVerification> createState() =>
      _ContactEmailVerificationState();
}

class _ContactEmailVerificationState extends State<ContactEmailVerification> {
  late final ContactEmailVerifier _verifier =
      widget.verifier ?? SupabaseContactEmailVerifier();
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _working = false; // saving / sending / checking
  bool _codeSent = false; // the code field is open
  String _sentTo = ''; // the address the open code was sent to
  String _maskedSentTo = '';
  String? _error;
  bool _justVerified = false;
  int _cooldown = 0; // seconds until Resend is allowed
  Timer? _timer;

  String _norm(String? v) => (v ?? '').trim().toLowerCase();
  String get _typed => _norm(widget.emailController.text);

  @override
  void initState() {
    super.initState();
    widget.emailController.addListener(_onEmailTyped);
  }

  @override
  void didUpdateWidget(covariant ContactEmailVerification old) {
    super.didUpdateWidget(old);
    if (old.emailController != widget.emailController) {
      old.emailController.removeListener(_onEmailTyped);
      widget.emailController.addListener(_onEmailTyped);
    }
  }

  @override
  void dispose() {
    widget.emailController.removeListener(_onEmailTyped);
    _timer?.cancel();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // Editing the address after a code was sent: that code was for the old text,
  // so the code field closes and the new address starts out Unverified.
  void _onEmailTyped() {
    if (!mounted) return;
    setState(() {
      if (_codeSent && _typed != _sentTo) _closeCodeEntry();
      _justVerified = false;
      _error = null;
    });
  }

  void _closeCodeEntry() {
    _codeSent = false;
    _codeCtrl.clear();
    _timer?.cancel();
    _cooldown = 0;
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown <= 0) t.cancel();
    });
  }

  String _requestError(AppLocalizations l10n, EmailCodeRequestResult r) {
    switch (r.status) {
      case EmailCodeRequestStatus.cooldown:
        return l10n.emailVerifyCooldown(r.retryAfter ?? 60);
      case EmailCodeRequestStatus.limit:
        return l10n.emailVerifyLimit;
      case EmailCodeRequestStatus.noEmail:
        return l10n.emailVerifyNoEmail;
      case EmailCodeRequestStatus.unauthorized:
        return l10n.emailVerifyUnauthorized;
      case EmailCodeRequestStatus.sendFailed:
        return l10n.emailVerifySendFailed;
      case EmailCodeRequestStatus.alreadyVerified:
        return l10n.emailVerifyAlready;
      case EmailCodeRequestStatus.sent:
      case EmailCodeRequestStatus.error:
        return l10n.emailVerifyGenericError;
    }
  }

  String _checkError(AppLocalizations l10n, EmailCodeCheckResult r) {
    switch (r.status) {
      case EmailCodeCheckStatus.invalidCode:
        return r.attemptsLeft == null
            ? l10n.emailVerifyInvalidCodeNoCount
            : l10n.emailVerifyInvalidCode(r.attemptsLeft!);
      case EmailCodeCheckStatus.expired:
        return l10n.emailVerifyExpired;
      case EmailCodeCheckStatus.tooManyAttempts:
        return l10n.emailVerifyTooMany;
      case EmailCodeCheckStatus.noCode:
        return l10n.emailVerifyNoCode;
      case EmailCodeCheckStatus.emailChanged:
        return l10n.emailVerifyEmailChanged;
      case EmailCodeCheckStatus.invalidFormat:
        return l10n.emailVerifyEnterCode;
      case EmailCodeCheckStatus.verified:
      case EmailCodeCheckStatus.error:
        return l10n.emailVerifyGenericError;
    }
  }

  /// Save (if the text differs from what is saved), then send a code.
  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    if (_working) return;
    if (_typed.isEmpty) {
      setState(() => _error = l10n.emailVerifyNoEmail);
      return;
    }
    if (!widget.isOnline) {
      setState(() => _error = l10n.emailVerifyOffline);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _justVerified = false;
    });
    if (_typed != _norm(widget.savedEmail)) {
      final saved = await widget.saveEmail();
      if (!mounted) return;
      if (!saved) {
        setState(() => _working = false);
        return;
      }
    }
    await _send(l10n);
  }

  Future<void> _send(AppLocalizations l10n) async {
    setState(() {
      _working = true;
      _error = null;
    });
    final r = await _verifier.requestCode();
    if (!mounted) return;
    setState(() => _working = false);
    switch (r.status) {
      case EmailCodeRequestStatus.sent:
        setState(() {
          _codeSent = true;
          _sentTo = _typed;
          _maskedSentTo = r.maskedEmail ?? _typed;
          _codeCtrl.clear();
        });
        _startCooldown(r.retryAfter ?? 60);
        _codeFocus.requestFocus();
      case EmailCodeRequestStatus.alreadyVerified:
        setState(() {
          _closeCodeEntry();
          _justVerified = true;
        });
        widget.onVerified();
      case EmailCodeRequestStatus.cooldown:
        setState(() => _error = _requestError(l10n, r));
        _startCooldown(r.retryAfter ?? 60);
      case EmailCodeRequestStatus.limit:
      case EmailCodeRequestStatus.noEmail:
      case EmailCodeRequestStatus.unauthorized:
      case EmailCodeRequestStatus.sendFailed:
      case EmailCodeRequestStatus.error:
        setState(() => _error = _requestError(l10n, r));
    }
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    if (_working) return;
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      setState(() => _error = l10n.emailVerifyEnterCode);
      return;
    }
    if (!widget.isOnline) {
      setState(() => _error = l10n.emailVerifyOffline);
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final r = await _verifier.checkCode(code);
    if (!mounted) return;
    if (r.verified) {
      setState(() {
        _working = false;
        _closeCodeEntry();
        _justVerified = true;
      });
      widget.onVerified();
      return;
    }
    setState(() {
      _working = false;
      _error = _checkError(l10n, r);
      _codeCtrl.clear();
      // A used-up, expired or stale code cannot be retried: back to the button.
      if (r.status != EmailCodeCheckStatus.invalidCode &&
          r.status != EmailCodeCheckStatus.invalidFormat &&
          r.status != EmailCodeCheckStatus.error) {
        _closeCodeEntry();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final typed = _typed;
    if (typed.isEmpty) return const SizedBox.shrink();

    final isVerified =
        widget.verified && typed == _norm(widget.savedEmail) && !_codeSent;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(verified: isVerified),
              const Spacer(),
              if (!isVerified && !_codeSent)
                TextButton(
                  key: const ValueKey('verify-email-action'),
                  onPressed: _working ? null : _start,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: _working
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          l10n.emailVerifyAction,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.primaryGreen,
                          ),
                        ),
                ),
            ],
          ),
          if (_codeSent) ...[
            const SizedBox(height: 4),
            Text(
              l10n.emailVerifyCodeSent(_maskedSentTo),
              key: const ValueKey('verify-email-sent'),
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    key: const ValueKey('verify-email-code'),
                    controller: _codeCtrl,
                    focusNode: _codeFocus,
                    label: l10n.emailVerifyCodeLabel,
                    prefixIcon: Icons.pin_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                PrimaryButton(
                  key: const ValueKey('verify-email-confirm'),
                  label: l10n.emailVerifyConfirm,
                  height: 56,
                  expand: false,
                  isLoading: _working,
                  onPressed: _working ? null : _confirm,
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('verify-email-resend'),
                onPressed: (_working || _cooldown > 0)
                    ? null
                    : () => _send(l10n),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _cooldown > 0
                      ? l10n.emailVerifyResendIn(_cooldown)
                      : l10n.emailVerifyResend,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _cooldown > 0 ? cs.outline : AppConstants.primaryGreen,
                  ),
                ),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                key: const ValueKey('verify-email-error'),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: AppConstants.errorRed,
                ),
              ),
            ),
          if (_justVerified && isVerified)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.emailVerifySuccess,
                key: const ValueKey('verify-email-success'),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: AppConstants.successGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact Verified / Unverified pill.
class _StatusChip extends StatelessWidget {
  final bool verified;
  const _StatusChip({required this.verified});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = verified ? AppConstants.successGreen : AppConstants.warningAmber;
    return Container(
      key: ValueKey(verified ? 'email-status-verified' : 'email-status-unverified'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.error_outline_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            verified ? l10n.emailStatusVerified : l10n.emailStatusUnverified,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
