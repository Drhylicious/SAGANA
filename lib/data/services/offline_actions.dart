import 'connectivity_service.dart';
import 'hive_service.dart';

/// What happened to a user-owned write.
enum SaveOutcome {
  /// Sent to the server now.
  saved,

  /// Kept on this device. It is sent by the next manual Sync.
  queued,
}

/// Result of a photo change. A queued photo has no URL until it syncs.
class PhotoSaveResult {
  final SaveOutcome? outcome;
  final String? url;

  const PhotoSaveResult({required this.outcome, this.url});

  const PhotoSaveResult.failed() : outcome = null, url = null;

  bool get failed => outcome == null;
  bool get queued => outcome == SaveOutcome.queued;
}

/// Runs a user-owned write now when the server is reachable, otherwise keeps
/// it on this device to be sent by the next manual Sync.
///
/// [kind] selects the replay handler in offline_action_replay.dart, and
/// [payload] must hold everything that handler needs (plain values only, so
/// it can be stored). [online] is the same write the handler runs later.
/// Thrown for an action that needs a connection (buyer side) when the device is offline.
class OfflineActionBlocked implements Exception {
  const OfflineActionBlocked();
}

class OfflineActions {
  OfflineActions._();

  static Future<SaveOutcome> run({
    required String kind,
    required Map<String, dynamic> payload,
    required Future<void> Function() online,
    bool queueWhenOffline = true,
  }) async {
    if (await ConnectivityService.instance.checkConnectivity()) {
      await online();
      return SaveOutcome.saved;
    }
    if (!queueWhenOffline) throw const OfflineActionBlocked();
    await HiveService.saveOfflineAction(kind, payload);
    return SaveOutcome.queued;
  }
}

/// Date values are stored as ISO-8601 text so the payload holds plain values.
String? encodeDate(DateTime? value) => value?.toIso8601String();

DateTime? decodeDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
