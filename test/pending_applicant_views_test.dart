import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/buyer_address_model.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/models/notification_model.dart';
import 'package:sagana/presentation/widgets/pending_applicant_views.dart';

import 'support/ignore_font_errors.dart';

/// The Pending Applicant tabs: logo top bar, Home, Notifications and Profile.

Future<void> _pump(WidgetTester tester, Widget child, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _noop() async {}

PendingHomeView _home({
  String status = 'pending',
  bool ack = false,
  String? reason,
  Future<void> Function()? onSubmit,
  Future<void> Function()? onAck,
  Future<void> Function()? onEdit,
  String firstName = 'Jhon Drhy',
}) => PendingHomeView(
  firstName: firstName,
  username: 'jhon.d',
  isOnline: true,
  status: status,
  pendingAcknowledgement: ack,
  rejectionReason: reason,
  isBusy: false,
  onSubmit: onSubmit ?? _noop,
  onAcknowledge: onAck ?? _noop,
  onEditDetails: onEdit ?? _noop,
);

NotificationModel _n(
  String id,
  DateTime at, {
  bool read = false,
  NotificationType type = NotificationType.system,
}) => NotificationModel(
  id: id,
  userId: 'u1',
  type: type,
  title: 'Title $id',
  body: 'Body $id',
  isRead: read,
  createdAt: at,
);

PendingNotificationsView _notifs(
  List<NotificationModel> items, {
  bool loading = false,
  void Function(NotificationModel)? onTap,
  void Function(NotificationModel)? onToggle,
  void Function(NotificationModel)? onDelete,
  VoidCallback? onReadAll,
  VoidCallback? onUnreadAll,
}) => PendingNotificationsView(
  notifications: items,
  isLoading: loading,
  onRefresh: _noop,
  onTap: onTap ?? (_) {},
  onToggleRead: onToggle ?? (_) {},
  onDelete: onDelete ?? (_) {},
  onMarkAllRead: onReadAll ?? () {},
  onMarkAllUnread: onUnreadAll ?? () {},
);

BuyerAddressModel _address() => BuyerAddressModel(
  id: 'a1',
  userId: 'u1',
  label: 'Home',
  addressLine:
      '123, Barangay Hall, Payanas Road, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
  isDefault: true,
  createdAt: DateTime(2026, 10, 1),
  updatedAt: DateTime(2026, 10, 1),
  regionName: 'MIMAROPA Region',
  provinceName: 'Marinduque',
  cityMunicipalityName: 'Torrijos',
  barangayName: 'Payanas',
  postalCode: '4903',
  street: 'Payanas Road',
  building: 'Barangay Hall',
  houseNo: '123',
);

FarmerProfileModel _profile({
  String? email = 'jd@gmail.com',
  String? phone = '09171234567',
  DateTime? dob,
  String? gender = 'male',
}) => FarmerProfileModel(
  userId: 'u1',
  fullName: 'Jhon Drhy M. Salangsang',
  contactEmail: email,
  phoneNumber: phone,
  dateOfBirth: dob ?? DateTime(1990, 3, 7),
  gender: gender,
  capitalShares: 0,
  isVerified: false,
  primaryCrops: const [],
);

PendingProfileView _profileView({
  FarmerProfileModel? profile,
  BuyerAddressModel? address,
  VoidCallback? onSignOut,
  bool loading = false,
}) => PendingProfileView(
  profile: profile ?? _profile(),
  address: address,
  statusLabel: 'PENDING APPLICANT',
  statusColor: Colors.orange,
  isLoading: loading,
  onSignOut: onSignOut ?? () {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Top bar: SAGANA logo | title on all three tabs', () {
    testWidgets('Home, Notifications and Profile each show the logo and their title', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final views = <String, Widget>{
          'Home': _home(),
          'Notifications': _notifs(const []),
          'Profile': _profileView(),
        };
        for (final e in views.entries) {
          await _pump(tester, e.value);
          expect(find.byKey(const ValueKey('pending-top-bar-logo')), findsOneWidget, reason: e.key);
          final title = find.byKey(const ValueKey('pending-top-bar-title'));
          expect(tester.widget<Text>(title).data, e.key);
          // The logo is the existing app asset, not a new one.
          final image = tester.widget<Image>(
            find.descendant(
              of: find.byKey(const ValueKey('pending-top-bar-logo')),
              matching: find.byType(Image),
            ),
          );
          expect((image.image as AssetImage).assetName, 'assets/images/sagana_icon.png');
          // Logo first, then the title, on one line.
          expect(
            tester.getCenter(find.byKey(const ValueKey('pending-top-bar-logo'))).dx,
            lessThan(tester.getTopLeft(title).dx),
          );
          expect(
            tester.getCenter(find.byKey(const ValueKey('pending-top-bar-logo'))).dy,
            closeTo(tester.getCenter(title).dy, 1),
          );
        }
      });
    });

    testWidgets('the bar has the same size and position on every tab', (tester) async {
      await runIgnoringFontErrors(() async {
        final sizes = <Size>[];
        final logoSpots = <Offset>[];
        final titleSpots = <Offset>[];
        for (final view in [_home(), _notifs(const []), _profileView()]) {
          await _pump(tester, view);
          final bar = find.ancestor(
            of: find.byKey(const ValueKey('pending-top-bar-logo')),
            matching: find.byType(Container),
          );
          sizes.add(tester.getSize(bar.last));
          logoSpots.add(tester.getTopLeft(find.byKey(const ValueKey('pending-top-bar-logo'))));
          titleSpots.add(tester.getTopLeft(find.byKey(const ValueKey('pending-top-bar-title'))));
        }
        expect(sizes.toSet().length, 1, reason: '$sizes');
        expect(logoSpots.toSet().length, 1, reason: '$logoSpots');
        expect(titleSpots.toSet().length, 1, reason: '$titleSpots');
        expect(sizes.first.height, 64);
      });
    });

    testWidgets('a narrow phone does not overflow the bar', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _notifs([_n('1', DateTime.now())]), width: 320);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('Home: same purpose and workflow, in a cleaner layout', () {
    testWidgets('pending: progress tracker and no action buttons', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _home());
        expect(find.text('Application Status'), findsOneWidget);
        expect(find.byKey(const ValueKey('pending-resubmit')), findsNothing);
        expect(find.byKey(const ValueKey('pending-submit')), findsNothing);
        expect(find.byKey(const ValueKey('pending-continue')), findsNothing);
        expect(find.byKey(const ValueKey('pending-status-badge')), findsOneWidget);
      });
    });

    testWidgets('the greeting uses the whole first name', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _home(firstName: 'Jhon Drhy'));
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('pending-welcome'))).data,
          contains('Jhon Drhy'),
        );
      });
    });

    testWidgets('disapproved: the reason is shown; Edit and Resubmit still do what they did', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        var edited = 0, submitted = 0;
        await _pump(
          tester,
          _home(
            status: 'rejected',
            reason: 'Please upload a clearer ID.',
            onEdit: () async => edited++,
            onSubmit: () async => submitted++,
          ),
        );
        expect(find.text('Please upload a clearer ID.'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pending-edit-details')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('pending-resubmit')));
        await tester.pump();
        expect([edited, submitted], [1, 1]);
      });
    });

    testWidgets('draft: Submit still submits', (tester) async {
      await runIgnoringFontErrors(() async {
        var submitted = 0;
        await _pump(tester, _home(status: 'draft', onSubmit: () async => submitted++));
        await tester.tap(find.byKey(const ValueKey('pending-submit')));
        await tester.pump();
        expect(submitted, 1);
      });
    });

    testWidgets('approved: Continue still acknowledges', (tester) async {
      await runIgnoringFontErrors(() async {
        var acknowledged = 0;
        await _pump(tester, _home(status: 'active', ack: true, onAck: () async => acknowledged++));
        await tester.tap(find.byKey(const ValueKey('pending-continue')));
        await tester.pump();
        expect(acknowledged, 1);
      });
    });

    testWidgets('approved but already acknowledged is not shown as approved', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _home(status: 'active', ack: false));
        expect(find.byKey(const ValueKey('pending-continue')), findsNothing);
      });
    });

    testWidgets('no overflow on a narrow phone in any state', (tester) async {
      await runIgnoringFontErrors(() async {
        for (final v in [
          _home(),
          _home(status: 'rejected', reason: 'x' * 200),
          _home(status: 'draft'),
          _home(status: 'active', ack: true),
        ]) {
          await _pump(tester, v, width: 320);
          expect(tester.takeException(), isNull);
        }
      });
    });
  });

  group('Profile: like Manager > Members > Member Details', () {
    testWidgets('Email | Phone on one row, Date of Birth | Gender on the next, then the address, then Sign Out', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _profileView(address: _address()));
        double top(String t) => tester.getTopLeft(find.text(t).first).dy;
        double left(String t) => tester.getTopLeft(find.text(t).first).dx;

        expect(find.text('Personal Information'), findsOneWidget);
        // Row 1.
        expect(top('Email Address'), closeTo(top('Phone Number'), 1));
        expect(left('Email Address'), lessThan(left('Phone Number')));
        // Row 2, below row 1.
        expect(top('Date of Birth'), closeTo(top('Gender'), 1));
        expect(left('Date of Birth'), lessThan(left('Gender')));
        expect(top('Date of Birth'), greaterThan(top('Email Address')));

        expect(find.text('jd@gmail.com'), findsOneWidget);
        expect(find.text('09171234567'), findsOneWidget);
        expect(find.text('Male'), findsOneWidget);

        // Then Address Information, then Sign Out at the bottom.
        expect(find.text('Address Information'), findsOneWidget);
        expect(top('Address Information'), greaterThan(top('Date of Birth')));
        final signOut = find.byKey(const ValueKey('pending-sign-out'));
        expect(signOut, findsOneWidget);
        expect(
          tester.getTopLeft(signOut).dy,
          greaterThan(top('Address Information')),
        );
      });
    });

    testWidgets('the tiles are equal width and equal height in a row', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _profileView(address: _address()));
        final tiles = find.descendant(
          of: find.byType(Row),
          matching: find.byType(Container),
        );
        // The email and phone tiles: find each label's tile via its ancestor.
        Size tileOf(String label) => tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
        );
        expect(tiles, findsWidgets);
        expect(tileOf('Email Address').width, closeTo(tileOf('Phone Number').width, 1));
        expect(tileOf('Email Address').height, closeTo(tileOf('Phone Number').height, 1));
        expect(tileOf('Date of Birth').width, closeTo(tileOf('Gender').width, 1));
      });
    });

    testWidgets('the address is one complete line, not split into fields, with no map', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _profileView(address: _address()));
        final text = tester.widget<SelectableText>(
          find.byKey(const ValueKey('member-residential-address-0')),
        );
        expect(
          text.data,
          '123, Barangay Hall, Payanas Road, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
        );
        for (final label in [
          'Region',
          'Province',
          'City / Municipality',
          'Barangay',
          'Postal Code',
          'Street',
          'Building',
          'House No.',
          'Default',
        ]) {
          expect(find.text(label), findsNothing, reason: label);
        }
        expect(find.text('No map pin saved for this address.'), findsNothing);
      });
    });

    testWidgets('no address saved says so', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _profileView());
        expect(find.text('Address Information'), findsOneWidget);
        expect(find.text('No address saved yet.'), findsOneWidget);
      });
    });

    testWidgets('missing details show a dash and keep the tile size', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          PendingProfileView(
            profile: FarmerProfileModel(
              userId: 'u1',
              fullName: 'Ana Reyes',
              capitalShares: 0,
              isVerified: false,
              primaryCrops: const [],
            ),
            address: null,
            statusLabel: 'DRAFT',
            statusColor: Colors.blue,
            isLoading: false,
            onSignOut: () {},
          ),
        );
        expect(find.text('–'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('the name and status sit under the photo, once', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _profileView(address: _address()));
        expect(find.text('Jhon Drhy M. Salangsang'), findsOneWidget);
        expect(find.text('PENDING APPLICANT'), findsOneWidget);
      });
    });

    testWidgets('Sign Out asks the screen to sign out', (tester) async {
      await runIgnoringFontErrors(() async {
        var taps = 0;
        await _pump(tester, _profileView(address: _address(), onSignOut: () => taps++));
        final button = find.byKey(const ValueKey('pending-sign-out'));
        await tester.ensureVisible(button);
        await tester.pump();
        await tester.tap(button);
        expect(taps, 1);
      });
    });

    testWidgets('no overflow on a narrow phone with a long name and email', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          _profileView(
            profile: _profile(email: 'a.very.long.email.address.for.testing@example-domain.com'),
            address: _address(),
          ),
          width: 320,
        );
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('Notifications: date groups, read state, menu', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9, 0);
    final yesterday = today.subtract(const Duration(days: 1));
    final older = today.subtract(const Duration(days: 9));

    testWidgets('grouped by the real date: Today, Yesterday, Earlier', (tester) async {
      await runIgnoringFontErrors(() async {
        // Now itself, so the test cannot cross midnight.
        final justNow = DateTime.now();
        await _pump(
          tester,
          _notifs([
            _n('a', justNow),
            _n('b', yesterday),
            _n('c', older),
          ]),
        );
        double top(String t) => tester.getTopLeft(find.text(t)).dy;
        expect(find.text('TODAY'), findsOneWidget);
        expect(find.text('YESTERDAY'), findsOneWidget);
        expect(find.text('EARLIER'), findsOneWidget);
        expect(top('TODAY'), lessThan(top('Title a')));
        expect(top('Title a'), lessThan(top('YESTERDAY')));
        expect(top('YESTERDAY'), lessThan(top('Title b')));
        expect(top('Title b'), lessThan(top('EARLIER')));
        expect(top('EARLIER'), lessThan(top('Title c')));
        // Older notifications show their date.
        expect(find.text('Yesterday'), findsOneWidget);
        expect(find.text('Just now'), findsOneWidget);
      });
    });

    testWidgets('an empty group is not shown', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _notifs([_n('c', older)]));
        expect(find.text('TODAY'), findsNothing);
        expect(find.text('YESTERDAY'), findsNothing);
        expect(find.text('EARLIER'), findsOneWidget);
      });
    });

    testWidgets('no notifications: the empty message and no menu', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _notifs(const []));
        expect(find.byKey(const ValueKey('notification-menu')), findsNothing);
        expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      });
    });

    testWidgets('unread has a dot; read does not', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          _notifs([_n('a', now, read: false), _n('b', now, read: true)]),
        );
        expect(find.byKey(const ValueKey('notification-unread-dot')), findsOneWidget);
      });
    });

    testWidgets('the three-dot menu is at the top right and offers what applies', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          _notifs([_n('a', now, read: false), _n('b', now, read: true)]),
        );
        final menu = find.byKey(const ValueKey('notification-menu'));
        expect(menu, findsOneWidget);
        expect(tester.getCenter(menu).dx, greaterThan(390 - 70));
        expect(tester.getCenter(menu).dy, lessThan(80));
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Mark all as read'), findsOneWidget);
        expect(find.text('Mark all as unread'), findsOneWidget);
      });
    });

    testWidgets('all unread: only "Mark all as read"; all read: only "Mark all as unread"', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _notifs([_n('a', now, read: false)]));
        await tester.tap(find.byKey(const ValueKey('notification-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Mark all as read'), findsOneWidget);
        expect(find.text('Mark all as unread'), findsNothing);
        await tester.tapAt(const Offset(5, 500));
        await tester.pumpAndSettle();

        await _pump(tester, _notifs([_n('a', now, read: true)]));
        await tester.tap(find.byKey(const ValueKey('notification-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Mark all as read'), findsNothing);
        expect(find.text('Mark all as unread'), findsOneWidget);
      });
    });

    testWidgets('the menu actions call through', (tester) async {
      await runIgnoringFontErrors(() async {
        var read = 0, unread = 0;
        await _pump(
          tester,
          _notifs(
            [_n('a', now, read: false), _n('b', now, read: true)],
            onReadAll: () => read++,
            onUnreadAll: () => unread++,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('notification-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark all as unread'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('notification-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark all as read'));
        await tester.pumpAndSettle();
        expect([read, unread], [1, 1]);
      });
    });

    testWidgets('tapping a notification reports it; long-press offers the opposite state', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final tapped = <String>[];
        final toggled = <String>[];
        await _pump(
          tester,
          _notifs(
            [_n('a', now, read: false), _n('b', now, read: true)],
            onTap: (n) => tapped.add(n.id),
            onToggle: (n) => toggled.add(n.id),
          ),
        );
        await tester.tap(find.text('Title a'));
        expect(tapped, ['a']);

        // Unread -> the sheet offers "Mark as read".
        await tester.longPress(find.text('Title a'));
        await tester.pumpAndSettle();
        expect(find.text('Mark as read'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('notification-toggle-read')));
        await tester.pumpAndSettle();

        // Read -> the sheet offers "Mark as unread".
        await tester.longPress(find.text('Title b'));
        await tester.pumpAndSettle();
        expect(find.text('Mark as unread'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('notification-toggle-read')));
        await tester.pumpAndSettle();
        expect(toggled, ['a', 'b']);
      });
    });

    testWidgets('swiping a notification away deletes it, as on the Farmer screen', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final deleted = <String>[];
        await _pump(
          tester,
          _notifs([_n('a', now)], onDelete: (n) => deleted.add(n.id)),
        );
        await tester.drag(find.text('Title a'), const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(deleted, ['a']);
      });
    });
  });

  group('the screen wires the views to the same data and actions as before', () {
    final screen = File('lib/presentation/screens/farmer/pending_applicant_screen.dart')
        .readAsStringSync();

    test('the approval workflow code is untouched', () {
      for (final s in [
        "AuthService.submitApplication()",
        "AuthService.acknowledgeMembership()",
        "context.go(AppRoutes.farmerDashboard)",
        "table: 'user_roles'",
        "_approvalDialogShownFor",
        "context.push(AppRoutes.pendingReview)",
        "HiveService.saveMemberStatus(_status)",
      ]) {
        expect(screen, contains(s), reason: s);
      }
    });

    test('Notifications reads and changes the real rows through NotificationRepository', () {
      expect(screen, contains('_repo.fetchNotifications()'));
      expect(screen, contains('_repo.markAsRead(n.id)'));
      expect(screen, contains('_repo.markAsUnread(n.id)'));
      expect(screen, contains('_repo.markAllAsRead()'));
      expect(screen, contains('_repo.markAllAsUnread()'));
      expect(screen, contains('_repo.deleteNotification(n.id)'));
    });

    test('Profile reads the same records as before: user_information, farmer_profiles, default address', () {
      expect(screen, contains(".from('user_information')"));
      expect(screen, contains(".from('farmer_profiles')"));
      expect(screen, contains('BuyerAddressRepository().fetchDefaultAddress()'));
      expect(screen, contains("AuthService.logout()"));
    });
  });
}
