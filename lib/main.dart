import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, Supabase;
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'data/services/admin_profile_state_service.dart';
import 'data/services/app_settings_service.dart';
import 'data/services/app_update_service.dart';
import 'data/models/suspension_notice.dart';
import 'data/services/account_status_watcher.dart';
import 'data/services/auth_service.dart';
import 'data/services/connectivity_service.dart';
import 'data/services/feature_restriction_service.dart';
import 'data/services/hive_service.dart';
import 'data/services/market_types_service.dart';
import 'data/services/notification_badge_service.dart';
import 'data/services/profile_state_service.dart';
import 'data/services/push_notification_service.dart';
import 'data/services/staff_permission_service.dart';
import 'data/services/sync_service.dart';
import 'presentation/widgets/app_update_dialog.dart';
import 'presentation/widgets/connectivity_overlay.dart';
import 'presentation/navigation/app_router.dart';
import 'presentation/widgets/suspension_dialogs.dart';
import 'routes/app_routes.dart';
import 'supabase_options.dart';

Future<void> main() async {
  // Removes the '#' from web URLs (e.g. /reset-password instead of
  // /#/reset-password). Without this, the Supabase password-reset
  // redirect lands on a URL GoRouter can't cleanly match against the
  // registered path. No-op on non-web platforms, safe to always call.
  usePathUrlStrategy();

  WidgetsFlutterBinding.ensureInitialized();

  // A map that is closed or panned while its tiles are still downloading makes
  // flutter_map cancel those requests ("Request aborted by abortTrigger"). That is
  // the intended cancellation, not a failure, but it is reported as an image error
  // after the tile is gone, where no tile handler can catch it. Only that one message
  // is dropped; every other error is reported as usual.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'image resource service' &&
        details.exception.toString().contains('abortTrigger')) {
      return;
    }
    (previousOnError ?? FlutterError.presentError)(details);
  };

  await HiveService.init();
  await SupabaseOptions.initialize();
  await ConnectivityService.instance.init();
  // The identity saved on this device must belong to the account Supabase has signed
  // in: a mismatch (a password-reset session, a session the server ended, data left
  // by another account) is ended here, before anything reads a saved role.
  await AuthService.reconcileLocalSession();
  // Resolves the already-logged-in user's ID (if any) so a restarted app
  // loads that specific user's preferences, not just the device default.
  await AppSettingsService.instance.init(userId: AuthService.currentUser?.id);
  // Native phone notifications; a no-op until Firebase is configured.
  await PushNotificationService.instance.init();
  // The red dot on the notification icon, shared by every primary screen.
  NotificationBadgeService.instance.start();

  if (AuthService.isLoggedIn) {
    await MarketTypes.instance.refresh();
    MarketTypes.instance.start();
    await FarmerProfileStateService.instance.refresh();
    await AdminProfileStateService.instance.refresh();
    await StaffPermissions.instance.refresh();
    StaffPermissions.instance.start();
    AccountStatusWatcher.instance.start();
    // A saved session never goes through sign-in, so record the activity here.
    AuthService.touchLastActive();
  }

  runApp(const SAGANAApp());
  SyncService.start();
}

class SAGANAApp extends StatefulWidget {
  const SAGANAApp({super.key});

  @override
  State<SAGANAApp> createState() => _SAGANAAppState();
}

class _SAGANAAppState extends State<SAGANAApp> with WidgetsBindingObserver {
  late final GoRouter _router = AppRouter.create();
  StreamSubscription<SuspensionNotice>? _suspensionSub;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // The server ended the session (its refresh failed or was revoked): the saved
    // sign-in goes with it, so no screen keeps acting as a signed-in account while
    // its requests go out unauthenticated.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut &&
          !AuthService.endingSession &&
          HiveService.isLoggedIn()) {
        unawaited(_onSessionLost());
      }
    });
    AppSettingsService.instance.addListener(_onSettingsChanged);
    MarketTypes.instance.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    _suspensionSub = AccountStatusWatcher.instance.suspensions.listen(
      _onSuspended,
    );
    // Lets a tapped phone notification open its screen, even from a closed app.
    unawaited(PushNotificationService.instance.attachRouter(_router));
    // Offer a newer SAGANA build once the first screen is up (best effort).
    Future<void>.delayed(
      const Duration(seconds: 3),
      () => _checkForUpdate(force: true),
    );
  }

  bool _updateDialogOpen = false;

  // Asks the server for the newest build and, when this one is older, shows the
  // optional or required update notice. Silent when offline or up to date.
  Future<void> _checkForUpdate({bool force = false}) async {
    if (_updateDialogOpen || !mounted) return;
    final status = await AppUpdateService.instance.checkIfDue(force: force);
    if (status == null || !mounted || _updateDialogOpen) return;
    final overlayContext =
        AppRouter.rootNavigatorKey.currentState?.overlay?.context;
    if (overlayContext == null || !overlayContext.mounted) return;
    _updateDialogOpen = true;
    try {
      await showAppUpdateDialog(overlayContext, status);
    } finally {
      _updateDialogOpen = false;
    }
  }

  @override
  void dispose() {
    AppSettingsService.instance.removeListener(_onSettingsChanged);
    MarketTypes.instance.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _suspensionSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  // Fallback to the realtime watcher: a suspension made while the app was in
  // the background is caught as soon as the app comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ConnectivityService.instance.checkConnectivity().then((online) {
          if (online) unawaited(SyncService.syncPending());
        }),
      );
      unawaited(AccountStatusWatcher.instance.checkNow());
      unawaited(NotificationBadgeService.instance.refresh());
      unawaited(_checkForUpdate());
      if (AuthService.isLoggedIn) {
        unawaited(MarketTypes.instance.refresh());
        unawaited(StaffPermissions.instance.refresh());
      }
      AuthService.touchLastActive();
    }
  }

  // Forced logout: the red notice is shown over the locked screen, the
  // session is ended, and the user is returned to login. The notice cannot be
  // dismissed by tapping outside it.
  Future<void> _onSuspended(SuspensionNotice notice) async {
    final overlayContext =
        AppRouter.rootNavigatorKey.currentState?.overlay?.context;
    if (overlayContext != null && overlayContext.mounted) {
      await showSuspensionNotice(
        context: overlayContext,
        notice: notice,
        signedOut: true,
      );
    }
    await AuthService.logout();
    _router.go(AppRoutes.login);
  }

  Future<void> _onSessionLost() async {
    AccountStatusWatcher.instance.stop();
    StaffPermissions.instance.clear();
    FeatureRestrictionService.instance.clear();
    await HiveService.clearUserSession();
    _router.go(AppRoutes.login);
  }

  void _onSettingsChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsService.instance;

    return MaterialApp.router(
      title: 'SAGANA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
      builder: (context, child) => ConnectivityOverlay(
        router: _router,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
