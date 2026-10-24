import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'data/services/admin_profile_state_service.dart';
import 'data/services/app_settings_service.dart';
import 'data/models/suspension_notice.dart';
import 'data/services/account_status_watcher.dart';
import 'data/services/auth_service.dart';
import 'data/services/connectivity_service.dart';
import 'data/services/hive_service.dart';
import 'data/services/market_types_service.dart';
import 'data/services/profile_state_service.dart';
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

  await HiveService.init();
  await SupabaseOptions.initialize();
  // Resolves the already-logged-in user's ID (if any) so a restarted app
  // loads that specific user's preferences, not just the device default.
  await AppSettingsService.instance.init(userId: AuthService.currentUser?.id);
  await ConnectivityService.instance.init();

  if (AuthService.isLoggedIn) {
    await MarketTypes.instance.refresh();
    MarketTypes.instance.start();
    await FarmerProfileStateService.instance.refresh();
    await AdminProfileStateService.instance.refresh();
    AccountStatusWatcher.instance.start();
  }


  runApp(const SAGANAApp());
}

class SAGANAApp extends StatefulWidget {
  const SAGANAApp({super.key});

  @override
  State<SAGANAApp> createState() => _SAGANAAppState();
}

class _SAGANAAppState extends State<SAGANAApp> with WidgetsBindingObserver {
  late final GoRouter _router = AppRouter.create();
  StreamSubscription<SuspensionNotice>? _suspensionSub;

  @override
  void initState() {
    super.initState();
    AppSettingsService.instance.addListener(_onSettingsChanged);
    MarketTypes.instance.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    _suspensionSub = AccountStatusWatcher.instance.suspensions.listen(
      _onSuspended,
    );
  }

  @override
  void dispose() {
    AppSettingsService.instance.removeListener(_onSettingsChanged);
    MarketTypes.instance.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _suspensionSub?.cancel();
    super.dispose();
  }

  // Fallback to the realtime watcher: a suspension made while the app was in
  // the background is caught as soon as the app comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AccountStatusWatcher.instance.checkNow());
      if (AuthService.isLoggedIn) unawaited(MarketTypes.instance.refresh());
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
    );
  }
}