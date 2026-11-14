import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/app_routes.dart';
import '../repositories/notification_repository.dart';

/// Native phone notifications (lock screen, notification shade) for every role.
///
/// The notification row in the `notifications` table stays the single source of
/// truth: the database sends a push for each new row (see
/// supabase_schema_push_notifications.sql and the send-push-notification Edge
/// Function), carrying that row's id and `route_on_tap`. Tapping the phone
/// notification marks the row read and opens the same screen an in-app tap does.
///
/// Everything here is best-effort: when Firebase is not configured for the
/// build (no google-services.json), on web, or when the user has denied the
/// permission, the app keeps working with in-app notifications only.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// Must match the channel created in MainActivity and the Edge Function.
  static const androidChannelId = 'sagana_notifications';

  bool _firebaseReady = false;
  GoRouter? _router;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenSub;
  String? _registeredToken;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Call once at start-up, after Supabase is initialised.
  Future<void> init() async {
    if (!_supported) return;
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      debugPrint('Push notifications disabled (Firebase not configured): $e');
      return;
    }

    // Phone notification tapped while the app is in the background.
    FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

    // Register (or move) this phone's token whenever a user is signed in.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) unawaited(_register());
    });
    if (Supabase.instance.client.auth.currentUser != null) {
      unawaited(_register());
    }
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_saveToken(token));
    });
  }

  /// Gives the service the app's router, then opens the notification that
  /// launched the app from a closed state, if there is one.
  Future<void> attachRouter(GoRouter router) async {
    _router = router;
    if (!_firebaseReady) return;
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) await _openFromMessage(initial);
  }

  Future<void> _register() async {
    if (!_firebaseReady) return;
    try {
      // Android 13+ and iOS ask the user here; a denial is simply respected.
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('PushNotificationService.register failed: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      await Supabase.instance.client.rpc(
        'register_push_token',
        params: {'p_token': token, 'p_platform': defaultTargetPlatform.name},
      );
      _registeredToken = token;
    } catch (e) {
      debugPrint('PushNotificationService.saveToken failed: $e');
    }
  }

  /// Stops this phone receiving the signed-in user's notifications. Call before
  /// signing out, while the session can still authorise the delete.
  Future<void> unregister() async {
    final token = _registeredToken;
    if (!_firebaseReady || token == null) return;
    try {
      await Supabase.instance.client.rpc(
        'unregister_push_token',
        params: {'p_token': token},
      );
      _registeredToken = null;
    } catch (e) {
      debugPrint('PushNotificationService.unregister failed: $e');
    }
  }

  Future<void> _openFromMessage(RemoteMessage message) async {
    final data = message.data;
    final route = data['route'] as String?;
    final extra = data['route_extra'] as String?;
    final id = data['notification_id'] as String?;

    // Keep the in-app record in step with the phone notification.
    if (id != null && Supabase.instance.client.auth.currentUser != null) {
      unawaited(NotificationRepository().markAsRead(id));
    }
    if (route == null || route.isEmpty) return;

    // From a closed app the router is still on splash/login for a moment; wait
    // for it to finish before pushing the destination.
    for (var i = 0; i < 40; i++) {
      final router = _router;
      if (router != null && _signedInAndPastEntry(router)) {
        if (extra != null && extra.isNotEmpty) {
          unawaited(router.push(route, extra: extra));
        } else {
          unawaited(router.push(route));
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  bool _signedInAndPastEntry(GoRouter router) {
    if (Supabase.instance.client.auth.currentUser == null) return false;
    final path = router.routeInformationProvider.value.uri.path;
    return path != AppRoutes.splash && path != AppRoutes.login;
  }

  void dispose() {
    _authSub?.cancel();
    _tokenSub?.cancel();
  }
}
