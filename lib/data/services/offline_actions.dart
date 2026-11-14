import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;
import 'connectivity_service.dart';
import 'hive_service.dart';
import 'offline_read_client.dart';

/// What happened to a user-owned write.
enum SaveOutcome {
  /// Sent to the server now.
  saved,

  /// Kept on this device for automatic sync or Sync Now.
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
/// it on this device for automatic sync or Sync Now.
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
    final owner = HiveService.getUserId();
    if (owner == null) throw const OfflineActionBlocked();
    if (await ConnectivityService.instance.checkConnectivity()) {
      try {
        await OfflineReadClient.runForUser(owner, online);
        return SaveOutcome.saved;
      } catch (error) {
        final connectionFailure = isOfflineConnectionFailure(error);
        // The connection can drop after the probe. Keep the same payload and
        // retry identity; a server validation failure must still reach the form.
        if (!connectionFailure ||
            !queueWhenOffline ||
            HiveService.getUserRole() == 'buyer' ||
            HiveService.getUserId() != owner) {
          rethrow;
        }
        await HiveService.saveOfflineAction(kind, payload);
        return SaveOutcome.queued;
      }
    }
    if (!queueWhenOffline || HiveService.getUserRole() == 'buyer') {
      throw const OfflineActionBlocked();
    }
    if (HiveService.getUserId() != owner) throw const OfflineActionBlocked();
    await HiveService.saveOfflineAction(kind, payload);
    return SaveOutcome.queued;
  }
}

/// Date values are stored as ISO-8601 text so the payload holds plain values.
String? encodeDate(DateTime? value) => value?.toIso8601String();

DateTime? decodeDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

/// A transport failure can occur after a successful reachability check.
bool isOfflineConnectionFailure(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is http.ClientException ||
    error is StorageException &&
        ((int.tryParse(error.statusCode ?? '') ?? 0) >= 500 ||
            RegExp(
              r'(Socket|Client|Handshake|Timeout)Exception',
            ).hasMatch(error.statusCode ?? ''));
