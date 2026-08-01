import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/admin_profile_model.dart';
import 'package:sagana/data/services/admin_profile_state_service.dart';
import 'package:sagana/presentation/widgets/admin_top_bar.dart';
import 'package:sagana/presentation/widgets/profile_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AdminProfileStateService.instance.clear();
  });

  testWidgets('AdminTopBar uses shared admin profile state for the avatar', (
    tester,
  ) async {
    AdminProfileStateService.instance.updateProfile(
      const AdminProfileModel(
        userId: 'admin-1',
        email: 'admin@example.com',
        fullName: 'Jane Admin',
        profilePhotoUrl: 'https://example.com/avatar.png',
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AdminTopBar(title: 'Dashboard')),
      ),
    );

    expect(find.byType(ProfileAvatar), findsOneWidget);
  });
}
