import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/db_error_utils.dart';
import '../../data/repositories/account_management_repository.dart';
import '../../data/services/staff_permission_service.dart';
import 'app_toast.dart';
import 'management_modal.dart';
import 'staff_access_matrix.dart';

/// Opens the Module Access editor for one Officer. Whoever manages Members can
/// change any module; there is no ceiling on what they may grant. Nobody edits
/// their own access (the database refuses it, and the entry is not offered).
///
/// Returns true when the access was saved. The change takes effect for the
/// target Officer at once: their app listens to their own permission rows.
Future<bool?> showOfficerAccessSheet({
  required BuildContext context,
  required String userId,
  required String officerName,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (_) => _OfficerAccessSheet(userId: userId, officerName: officerName),
  );
}

class _OfficerAccessSheet extends StatefulWidget {
  const _OfficerAccessSheet({required this.userId, required this.officerName});

  final String userId;
  final String officerName;

  @override
  State<_OfficerAccessSheet> createState() => _OfficerAccessSheetState();
}

class _OfficerAccessSheetState extends State<_OfficerAccessSheet> {
  final _repo = AccountManagementRepository();
  Map<StaffModule, StaffAccess>? _access;
  bool _loadFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final access = await _repo.fetchOfficerAccess(widget.userId);
      if (!mounted) return;
      setState(() {
        _access = {
          for (final m in StaffModule.values) m: access[m] ?? StaffAccess.view,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _save() async {
    final access = _access;
    if (access == null || _saving) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await _repo.saveOfficerAccess(widget.userId, access);
      if (!mounted) return;
      AppToast.show(context, l10n.staffAccessSaved);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, friendlyErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final access = _access;

    final Widget body;
    if (_loadFailed) {
      body = Text(l10n.staffAccessLoadError);
    } else if (access == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      body = StaffAccessMatrix(
        value: access,
        enabled: !_saving,
        onChanged: (module, level) => setState(() => access[module] = level),
      );
    }

    return ManagementModalShell(
      title: l10n.staffAccessEditTitle(widget.officerName),
      body: body,
      footer: ManagementModalActions(
        primaryLabel: _saving ? l10n.staffAccessSaving : l10n.staffAccessSave,
        isLoading: _saving,
        onPrimary: access == null ? null : _save,
      ),
    );
  }
}
