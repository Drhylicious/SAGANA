import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/guest/guest_farmer_sample_data.dart';
import 'package:sagana/data/services/guest_mode_service.dart';
import 'package:sagana/presentation/navigation/app_router.dart';
import 'package:sagana/presentation/screens/auth/welcome_screen.dart';
import 'package:sagana/presentation/screens/shared/guest_screens.dart';
import 'package:sagana/presentation/widgets/guest_navigation_drawer.dart';
import 'package:sagana/presentation/widgets/guest_prompt.dart';
import 'package:sagana/routes/app_routes.dart';

import 'support/ignore_font_errors.dart';

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  home: home,
);

void main() {
  setUp(() => GuestModeService.instance.exit());
  tearDown(() => GuestModeService.instance.exit());

  group('GuestModeService', () {
    test('starts signed out and not exploring', () {
      expect(GuestModeService.active, isFalse);
      expect(GuestModeService.instance.role, isNull);
    });

    test('enter / switch / exit', () {
      GuestModeService.instance.enter(GuestRole.buyer);
      expect(GuestModeService.instance.isGuestBuyer, isTrue);
      expect(GuestModeService.instance.isGuestFarmer, isFalse);

      GuestModeService.instance.enter(GuestRole.farmer);
      expect(GuestModeService.instance.isGuestFarmer, isTrue);
      expect(GuestModeService.active, isTrue);

      GuestModeService.instance.exit();
      expect(GuestModeService.active, isFalse);
    });
  });

  group('router guard (signed out)', () {
    test('public screens are always open', () {
      for (final p in [
        AppRoutes.welcome,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.aboutSagana,
      ]) {
        expect(AppRouter.isGuestAllowed(p), isTrue, reason: p);
      }
    });

    test('staff and private screens are closed with no guest mode', () {
      for (final p in [
        AppRoutes.adminDashboard,
        AppRoutes.farmerManagement,
        AppRoutes.marketplaceBrowse,
        AppRoutes.farmerDashboard,
        AppRoutes.checkout,
      ]) {
        expect(AppRouter.isGuestAllowed(p), isFalse, reason: p);
      }
    });

    test('guest buyer reaches only the four Buyer tabs and listing details', () {
      GuestModeService.instance.enter(GuestRole.buyer);
      for (final p in [
        AppRoutes.marketplaceBrowse,
        AppRoutes.myOrders,
        AppRoutes.priceMonitoring,
        AppRoutes.buyerAccount,
        AppRoutes.listingDetails,
      ]) {
        expect(AppRouter.isGuestAllowed(p), isTrue, reason: p);
      }
      for (final p in [
        AppRoutes.buyerCart,
        AppRoutes.checkout,
        AppRoutes.orderDetail,
        AppRoutes.buyerEditProfile,
        AppRoutes.farmerDashboard,
        AppRoutes.adminDashboard,
      ]) {
        expect(AppRouter.isGuestAllowed(p), isFalse, reason: p);
      }
    });

    test('guest farmer reaches only the five Farmer tabs', () {
      GuestModeService.instance.enter(GuestRole.farmer);
      for (final p in [
        AppRoutes.farmerDashboard,
        AppRoutes.harvestHub,
        AppRoutes.myListings,
        AppRoutes.farmerAnalytics,
        AppRoutes.farmerProfile,
        AppRoutes.farmerMarketplaceListingDetail,
      ]) {
        expect(AppRouter.isGuestAllowed(p), isTrue, reason: p);
      }
      for (final p in [
        AppRoutes.harvestEntryForm,
        AppRoutes.createListing,
        AppRoutes.myTransactionHistory,
        AppRoutes.myLoans,
        AppRoutes.farmerSettings,
        AppRoutes.marketplaceBrowse,
        AppRoutes.adminDashboard,
        AppRoutes.loanDashboard,
      ]) {
        expect(AppRouter.isGuestAllowed(p), isFalse, reason: p);
      }
    });
  });

  group('sample data', () {
    test('every sample id is clearly marked as sample', () {
      final ids = [
        ...GuestFarmerSampleData.harvests.map((h) => h.id),
        ...GuestFarmerSampleData.listings.map((l) => l.id),
        ...GuestFarmerSampleData.activity.map((a) => a.id),
        ...GuestFarmerSampleData.transactions.map((t) => t.id),
      ];
      expect(ids, isNotEmpty);
      expect(
        ids.every((id) => id.startsWith(GuestFarmerSampleData.idPrefix)),
        isTrue,
      );
    });
  });

  group('screens', () {
    testWidgets('Welcome shows the three entry points', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(_app(const WelcomeScreen()));
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Welcome to SAGANA!'), findsOneWidget);
        expect(find.text('How would you like to explore?'), findsOneWidget);
        expect(find.text('Explore as Buyer'), findsOneWidget);
        expect(find.text('Explore as Farmer'), findsOneWidget);
        expect(find.text('Already have an account?'), findsOneWidget);
        expect(find.text('Login'), findsOneWidget);
      });
    });

    testWidgets('Explore as Buyer / Farmer starts the matching guest mode', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, __) => const WelcomeScreen()),
            GoRoute(
              path: AppRoutes.marketplaceBrowse,
              builder: (_, __) => const Text('buyer-home'),
            ),
            GoRoute(
              path: AppRoutes.farmerDashboard,
              builder: (_, __) => const Text('farmer-home'),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.text('Explore as Farmer'));
        await tester.pumpAndSettle();
        expect(find.text('farmer-home'), findsOneWidget);
        expect(GuestModeService.instance.role, GuestRole.farmer);
      });
    });

    testWidgets('Guest Orders is an empty state, not a popup', (tester) async {
      await runIgnoringFontErrors(() async {
        GuestModeService.instance.enter(GuestRole.buyer);
        await tester.pumpWidget(_app(const GuestOrdersScreen()));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Ready to place your first order?'), findsOneWidget);
        expect(
          find.text(
            'Log in or create an account to start ordering agricultural '
            'products and track your purchases.',
          ),
          findsOneWidget,
        );
        expect(find.text('Login'), findsOneWidget);
        expect(find.text('Register'), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
      });
    });

    testWidgets('Guest Profile offers Login, Register and the other mode', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        GuestModeService.instance.enter(GuestRole.buyer);
        await tester.pumpWidget(
          _app(const GuestProfileScreen(role: GuestRole.buyer)),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Welcome to SAGANA!'), findsOneWidget);
        expect(find.text('Login'), findsOneWidget);
        expect(find.text('Register'), findsOneWidget);
        expect(find.text('Switch to Explore as Farmer'), findsOneWidget);

        // The Farmer variant's top bar needs an initialised Supabase client,
        // so the Farmer-side switch label is checked on the guest drawer.
        await tester.pumpWidget(
          _app(
            const Scaffold(
              body: GuestNavigationDrawer(role: GuestRole.farmer),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Switch to Explore as Buyer'), findsOneWidget);
        expect(find.text('Back to Welcome'), findsOneWidget);
      });
    });

    testWidgets('Add to Cart and Buy Now prompts are separate', (tester) async {
      await runIgnoringFontErrors(() async {
        GuestModeService.instance.enter(GuestRole.buyer);
        late BuildContext ctx;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (c) {
                ctx = c;
                return const Scaffold();
              },
            ),
          ),
        );

        ctx.promptBuyer((l) => l.guestCartTitle, (l) => l.guestCartMessage);
        await tester.pumpAndSettle();
        expect(find.text('Ready to add to your cart?'), findsOneWidget);
        expect(
          find.text(
            'Log in or create an account to save products to your cart and '
            'continue shopping.',
          ),
          findsOneWidget,
        );
        expect(find.text('Login'), findsOneWidget);
        expect(find.text('Register'), findsOneWidget);
        expect(find.text('Continue Browsing'), findsOneWidget);
        await tester.tap(find.text('Continue Browsing'));
        await tester.pumpAndSettle();
        expect(find.text('Ready to add to your cart?'), findsNothing);

        ctx.promptBuyer((l) => l.guestBuyNowTitle, (l) => l.guestBuyNowMessage);
        await tester.pumpAndSettle();
        expect(find.text('Ready to place an order?'), findsOneWidget);
        expect(
          find.text('Log in or create an account to purchase this product.'),
          findsOneWidget,
        );
      });
    });

    testWidgets('Farmer prompts say Continue Exploring', (tester) async {
      await runIgnoringFontErrors(() async {
        GuestModeService.instance.enter(GuestRole.farmer);
        late BuildContext ctx;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (c) {
                ctx = c;
                return const Scaffold();
              },
            ),
          ),
        );
        ctx.promptGuest(
          (l) => l.guestRecordHarvestTitle,
          (l) => l.guestRecordHarvestMessage,
        );
        await tester.pumpAndSettle();
        expect(find.text('Ready to record your harvest?'), findsOneWidget);
        expect(find.text('Continue Exploring'), findsOneWidget);
      });
    });
  });
}
