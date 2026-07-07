import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/routes/app_router.dart';
import 'package:sagana/routes/app_routes.dart';

void main() {
  test('supply chain map route is navigable', () {
    final router = AppRouter.create();

    expect(() => router.go(AppRoutes.supplyChainMap), returnsNormally);
  });
}
