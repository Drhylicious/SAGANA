import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'data/services/admin_profile_state_service.dart';
import 'data/services/app_settings_service.dart';
import 'data/services/auth_service.dart';
import 'data/services/connectivity_service.dart';
import 'data/services/hive_service.dart';
import 'data/services/profile_state_service.dart';
import 'data/services/sync_service.dart';
import 'presentation/navigation/app_router.dart';
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
    await FarmerProfileStateService.instance.refresh();
    await AdminProfileStateService.instance.refresh();
  }

  SyncService.startAutoSync();

  runApp(const SAGANAApp());
}

class SAGANAApp extends StatefulWidget {
  const SAGANAApp({super.key});

  @override
  State<SAGANAApp> createState() => _SAGANAAppState();
}

class _SAGANAAppState extends State<SAGANAApp> {
  late final GoRouter _router = AppRouter.create();

  @override
  void initState() {
    super.initState();
    AppSettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    AppSettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
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