import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/input_validation_utils.dart';
import '../../data/repositories/unit_repository.dart';

/// The one "add a unit" flow, used by both Inventory Management and Price
/// Management so they validate and save identically.
///
/// Checks the name (required, at most [kUnitMaxLength] characters, letters /
/// digits / space . / -), refuses a unit already in [existing] (ignoring case
/// and spacing), then saves it through [UnitRepository]. Every problem is
/// shown inside the dialog, under the field, so it is never hidden behind it.
///
/// Returns the saved unit name, or null if the dialog was cancelled.
Future<String?> promptAddUnit(
  BuildContext context, {
  required UnitRepository repo,
  required List<String> existing,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _AddUnitDialog(repo: repo, existing: existing),
  );
}

class _AddUnitDialog extends StatefulWidget {
  final UnitRepository repo;
  final List<String> existing;
  const _AddUnitDialog({required this.repo, required this.existing});

  @override
  State<_AddUnitDialog> createState() => _AddUnitDialogState();
}

class _AddUnitDialogState extends State<_AddUnitDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _validate(AppLocalizations l10n, String text) {
    switch (checkUnitName(text)) {
      case UnitIssue.empty:
        return l10n.unitErrorRequired;
      case UnitIssue.tooLong:
        return l10n.unitErrorTooLong(kUnitMaxLength);
      case UnitIssue.invalidCharacters:
        return l10n.unitErrorInvalid;
      case null:
        break;
    }
    final name = normalizeUnitName(text);
    if (widget.existing.any((u) => normalizeUnitName(u) == name)) {
      return l10n.unitErrorDuplicate(name);
    }
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final problem = _validate(l10n, _ctrl.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final result = await widget.repo.addUnit(_ctrl.text);
    if (!mounted) return;
    switch (result.outcome) {
      case AddUnitOutcome.added:
        Navigator.pop(context, result.name);
      case AddUnitOutcome.duplicate:
        setState(() {
          _saving = false;
          _error = l10n.unitErrorDuplicate(result.name ?? _ctrl.text.trim());
        });
      case AddUnitOutcome.invalid:
        setState(() {
          _saving = false;
          _error = l10n.unitErrorInvalid;
        });
      case AddUnitOutcome.failed:
        setState(() {
          _saving = false;
          _error = l10n.unitAddFailed;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        l10n.unitAddTitle,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        enabled: !_saving,
        maxLength: kUnitMaxLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          hintText: l10n.unitNameHint,
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.issueLoanCancel),
        ),
        TextButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.genericAdd),
        ),
      ],
    );
  }
}
