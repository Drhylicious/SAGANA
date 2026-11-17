import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_release_model.dart';
import 'connectivity_service.dart';
import 'hive_service.dart';

enum AppUpdateKind { none, optional, required }

/// What the update check found. [release] is null only when [kind] is none.
class AppUpdateStatus {
  final AppUpdateKind kind;
  final AppRelease? release;
  final String installedVersion;
  final int installedBuild;

  const AppUpdateStatus({
    required this.kind,
    required this.release,
    required this.installedVersion,
    required this.installedBuild,
  });
}

/// Asks Supabase for the newest SAGANA build (`latest_app_release()`) and
/// compares its build number with the installed one.
///
/// Best effort and offline-first: with no connection, or on any failure, it
/// reports nothing and never blocks the app. A *required* update is therefore
/// only shown after a successful online check. Release rows are written by the
/// developer (supabase_schema_app_release_02_publish_release.sql).
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// How long "Later" silences the optional prompt for the same build.
  static const reminderDelay = Duration(hours: 24);

  /// Minimum gap between automatic checks (resume from background).
  static const _checkInterval = Duration(hours: 1);

  DateTime? _lastCheck;
  AppUpdateStatus? _lastStatus;

  /// The decision, from numbers only (kept separate so it can be tested).
  static AppUpdateKind evaluate({
    required int installedBuild,
    required AppRelease release,
  }) {
    if (installedBuild >= release.buildNumber) return AppUpdateKind.none;
    if (installedBuild < release.minSupportedBuild) {
      return AppUpdateKind.required;
    }
    return AppUpdateKind.optional;
  }

  /// Whether the optional prompt should be shown now (not snoozed with "Later").
  static bool shouldShowOptional({DateTime? remindAt, required DateTime now}) {
    return remindAt == null || !remindAt.isAfter(now);
  }

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Runs the check when due. Returns the status to show, or null for
  /// "nothing to show" (up to date, snoozed, offline, not due, or failed).
  /// [force] skips the once-an-hour limit (used at start-up).
  Future<AppUpdateStatus?> checkIfDue({bool force = false}) async {
    if (!_supported) return null;

    // A required update stays on screen until installed, so it is re-offered
    // from the last answer without asking the server again.
    final last = _lastStatus;
    if (last != null && last.kind == AppUpdateKind.required) return last;

    final now = DateTime.now();
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < _checkInterval) {
      return null;
    }
    if (!ConnectivityService.instance.isOnline) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(info.buildNumber) ?? 0;
      final raw = await Supabase.instance.client
          .rpc('latest_app_release')
          .timeout(const Duration(seconds: 10));
      _lastCheck = now;

      final release = AppRelease.tryParse(raw);
      if (release == null) {
        _lastStatus = null;
        return null;
      }
      final kind = evaluate(installedBuild: installedBuild, release: release);
      final status = AppUpdateStatus(
        kind: kind,
        release: release,
        installedVersion: info.version,
        installedBuild: installedBuild,
      );
      _lastStatus = status;

      if (kind == AppUpdateKind.none) return null;
      if (kind == AppUpdateKind.optional &&
          !shouldShowOptional(
            remindAt: HiveService.getUpdateReminderAt(release.buildNumber),
            now: now,
          )) {
        return null;
      }
      return status;
    } catch (e) {
      debugPrint('Update check skipped: $e');
      return null;
    }
  }

  /// "Later": do not show the optional prompt for this build for a day.
  Future<void> remindLater(AppRelease release) =>
      HiveService.setUpdateReminderAt(
        release.buildNumber,
        DateTime.now().add(reminderDelay),
      );
}
