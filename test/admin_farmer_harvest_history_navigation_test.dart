import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/presentation/navigation/app_router.dart';
import 'package:sagana/presentation/screens/admin/farmer_harvest_history_screen.dart';
import 'package:sagana/routes/app_routes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin farmer harvest history opens the admin view', (
    tester,
  ) async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'fake-anon-key',
    );

    final router = AppRouter.create();

    router.go(AppRoutes.farmerHarvestHistory, extra: 'farmer-123');

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AdminFarmerHarvestHistoryScreen), findsOneWidget);
    expect(find.text('Log New Harvest'), findsNothing);
    expect(find.text('Admin View Only'), findsOneWidget);
  });
}
