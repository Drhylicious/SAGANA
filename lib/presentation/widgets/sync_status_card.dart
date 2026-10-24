import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/app_utils.dart';
import '../../data/services/app_event_service.dart';
import '../../data/services/app_settings_service.dart';
import '../../data/services/connectivity_service.dart';
import '../../data/services/hive_service.dart';
import '../../data/services/sync_service.dart';
import 'app_toast.dart';
import 'shared_widgets.dart';

/// Connectivity, queued-record count, last sync time, a manual Sync action,
/// and the records the server rejected, each with its own Retry. Used by the
/// Farmer, Admin, and Officer screens. Queues are limited to the signed-in
/// user, so the card shows only that user's records.
class SyncStatusCard extends StatefulWidget {
  /// Called after a manual Sync with the number of records that were queued
  /// before it ran, so the screen can record its own follow-up.
  final void Function(int queuedBefore)? onSyncCompleted;

  const SyncStatusCard({super.key, this.onSyncCompleted});

  @override
  State<SyncStatusCard> createState() => _SyncStatusCardState();
}

class _SyncStatusCardState extends State<SyncStatusCard> {
  late bool _online;
  StreamSubscription<bool>? _connectionSub;

  int _queued = 0;
  List<FailedSyncRecord> _failed = const [];
  DateTime? _lastSynced;

  bool _syncing = false;
  String? _retryingId;

  @override
  void initState() {
    super.initState();
    _online = ConnectivityService.instance.isOnline;
    _connectionSub = ConnectivityService.instance.onConnectivityChanged.listen((
      online,
    ) {
      if (mounted) setState(() => _online = online);
    });
    AppEventService.instance.addListener(_refresh);
    _readQueue();
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    AppEventService.instance.removeListener(_refresh);
    super.dispose();
  }

  void _readQueue() {
    _queued = SyncService.queuedCount;
    _failed = SyncService.failedRecords();
    _lastSynced = HiveService.getLastSyncTime(
      userId: AppSettingsService.instance.currentUserId,
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(_readQueue);
  }

  Future<void> _syncNow() async {
    final l10n = AppLocalizations.of(context);
    final queuedBefore = _queued;
    setState(() => _syncing = true);
    await SyncService.syncPending();
    if (!mounted) return;
    widget.onSyncCompleted?.call(queuedBefore);
    setState(() {
      _syncing = false;
      _readQueue();
    });
    if (_failed.isNotEmpty) {
      PostActionFeedback.error(context, l10n.syncRecordsFailed(_failed.length));
    }
  }

  Future<void> _retry(FailedSyncRecord record) async {
    final l10n = AppLocalizations.of(context);
    if (!_online) {
      PostActionFeedback.error(context, l10n.syncNeedsConnection);
      return;
    }
    setState(() => _retryingId = record.localId);
    final ok = await SyncService.retry(record);
    if (!mounted) return;
    setState(() {
      _retryingId = null;
      _readQueue();
    });
    if (ok) {
      PostActionFeedback.success(context, l10n.syncRetrySucceeded);
    } else {
      PostActionFeedback.error(context, l10n.syncRetryStillFailing);
    }
  }

  String _kindLabel(AppLocalizations l10n, FailedSyncRecord record) {
    return switch (record.kind) {
      SyncRecordKind.harvest => l10n.syncKindHarvest,
      SyncRecordKind.expense => l10n.syncKindExpense,
      SyncRecordKind.loanIssue => l10n.syncKindLoanIssue,
      SyncRecordKind.loanPayment => l10n.syncKindLoanPayment,
      SyncRecordKind.action => _actionLabel(l10n, record.actionKind!),
    };
  }

  String _actionLabel(AppLocalizations l10n, String actionKind) {
    if (actionKind.startsWith('address_')) return l10n.syncActionAddress;
    if (actionKind.startsWith('notification_')) {
      return l10n.syncActionNotification;
    }
    if (actionKind == 'capital_record') return l10n.syncActionCapital;
    if (actionKind == 'crop_photo') return l10n.syncActionCropPhoto;
    if (actionKind.endsWith('_photo') || actionKind == 'admin_photo_remove') {
      return l10n.syncActionPhoto;
    }
    return l10n.syncActionProfile;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final busy = _syncing || _retryingId != null;
    final canSync = _online && !busy;

    final statusText = _online ? l10n.syncStatusOnline : l10n.syncStatusOffline;
    final statusColor = _online ? AppConstants.successGreen : cs.outline;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: flatCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.syncCardTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _queued == 0
                ? l10n.syncAllSynced
                : l10n.syncQueuedCount(_queued),
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _lastSynced != null
                ? l10n.syncLastSyncedAt(
                    AppUtils.formatRelativeTime(_lastSynced!, l10n),
                  )
                : l10n.syncNeverSynced,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canSync ? _syncNow : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
              ),
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(
                _syncing ? l10n.syncInProgress : l10n.syncNowButton,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (_failed.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
            const SizedBox(height: 10),
            Text(
              l10n.syncFailedHeading(_failed.length),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            for (final record in _failed) ...[
              const SizedBox(height: 10),
              _FailedRecordRow(
                kindLabel: _kindLabel(l10n, record),
                error: record.error,
                failedAt: record.failedAt,
                l10n: l10n,
                retrying: _retryingId == record.localId,
                enabled: canSync,
                onRetry: () => _retry(record),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _FailedRecordRow extends StatelessWidget {
  final String kindLabel;
  final String error;
  final DateTime? failedAt;
  final AppLocalizations l10n;
  final bool retrying;
  final bool enabled;
  final VoidCallback onRetry;

  const _FailedRecordRow({
    required this.kindLabel,
    required this.error,
    required this.failedAt,
    required this.l10n,
    required this.retrying,
    required this.enabled,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.sync_problem_rounded,
            color: AppConstants.warningAmber,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kindLabel,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (failedAt != null)
                Text(
                  l10n.syncLastAttempted(
                    DateFormat('MMM d, h:mm a').format(failedAt!),
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        retrying
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: enabled ? onRetry : null,
                child: Text(l10n.syncRetryButton),
              ),
      ],
    );
  }
}
