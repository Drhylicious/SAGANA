import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/input_validation_utils.dart';
import '../../data/services/auth_service.dart';

/// A username field that checks, as the person types, whether the username is
/// free. Used by Farmer and Buyer registration and by the Manager's Add Member
/// and Add Officer forms, so every role follows the same rules:
///
///  * required, 3-30 characters (letters, numbers, dots, underscores, hyphens);
///  * unique across ALL accounts, case-insensitively;
///  * the check is debounced, shows a spinner while it runs, and shows
///    "Username is available." / "This username is already taken." inline.
///
/// The answer comes from the database (check_username_available). It is a
/// convenience only: the database enforces uniqueness again when the account
/// is created, so a check that cannot run ([UsernameStatus.error]) never
/// blocks the form.
class UsernameAvailabilityField extends StatefulWidget {
  const UsernameAvailabilityField({
    super.key,
    required this.controller,
    required this.decorationBuilder,
    required this.onStatusChanged,
    this.textInputAction = TextInputAction.next,
    this.debounce = const Duration(milliseconds: 600),
    this.checker,
  });

  final TextEditingController controller;

  /// Builds the field's decoration around the live status [suffix] (a spinner,
  /// a check or a cross). Lets each screen keep its own field styling.
  final InputDecoration Function(Widget? suffix) decorationBuilder;

  /// Reports the latest verdict. [status] is null while unchecked; [checking]
  /// is true while a request is in flight.
  final void Function(UsernameStatus? status, bool checking) onStatusChanged;

  final TextInputAction textInputAction;
  final Duration debounce;

  /// Overrides the database check. For tests.
  final Future<UsernameStatus> Function(String username)? checker;

  @override
  State<UsernameAvailabilityField> createState() =>
      _UsernameAvailabilityFieldState();
}

class _UsernameAvailabilityFieldState extends State<UsernameAvailabilityField> {
  Timer? _timer;
  UsernameStatus? _status;
  bool _checking = false;
  // Value the in-flight check was started for, so a slow answer for an old
  // value is discarded.
  String _checkedFor = '';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _report() => widget.onStatusChanged(_status, _checking);

  void _onChanged(String raw) {
    _timer?.cancel();
    final value = normalizeUsername(raw);

    // Nothing to ask the database about yet.
    if (value.isEmpty) {
      _setState(null, false);
      return;
    }
    if (!isValidUsernameFormat(value)) {
      _setState(
        value.length < 3 ? null : UsernameStatus.invalid,
        false,
      );
      return;
    }

    _setState(null, true);
    _timer = Timer(widget.debounce, () => _check(value));
  }

  Future<void> _check(String value) async {
    _checkedFor = value;
    final check = widget.checker ?? AuthService.checkUsernameAvailability;
    final result = await check(value);
    if (!mounted || normalizeUsername(widget.controller.text) != _checkedFor) {
      return; // the text changed while the request was running
    }
    _setState(result, false);
  }

  void _setState(UsernameStatus? status, bool checking) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _checking = checking;
    });
    _report();
  }

  String? _validate(String? raw, AppLocalizations l10n) {
    final value = normalizeUsername(raw ?? '');
    if (value.isEmpty) return l10n.registerUsernameRequired;
    if (value.length < 3) return l10n.registerUsernameTooShort;
    if (!isValidUsernameFormat(value) || _status == UsernameStatus.invalid) {
      return l10n.registerUsernameInvalid;
    }
    if (_status == UsernameStatus.taken) return l10n.registerUsernameTaken;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    Widget? suffix;
    if (_checking) {
      suffix = Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        ),
      );
    } else if (_status == UsernameStatus.available) {
      suffix = const Icon(
        Icons.check_circle_rounded,
        color: AppConstants.successGreen,
      );
    } else if (_status == UsernameStatus.taken ||
        _status == UsernameStatus.invalid) {
      suffix = const Icon(Icons.cancel_rounded, color: AppConstants.errorRed);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: widget.textInputAction,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: _onChanged,
          decoration: widget.decorationBuilder(suffix),
          validator: (v) => _validate(v, l10n),
        ),
        if (_status == UsernameStatus.available)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              l10n.registerUsernameAvailable,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppConstants.successGreen,
              ),
            ),
          ),
      ],
    );
  }
}
