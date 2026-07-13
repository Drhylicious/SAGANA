import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/presentation/navigation/app_router.dart';
import 'package:sagana/presentation/screens/admin/farmer_details_screen.dart';
import 'package:sagana/routes/app_routes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigating to farmer details opens the implemented screen', (
    tester,
  ) async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'fake-anon-key',
    );

    final router = AppRouter.create();

    router.go(AppRoutes.farmerDetails, extra: 'farmer-123');

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(FarmerDetailsScreen), findsOneWidget);
  });
}
