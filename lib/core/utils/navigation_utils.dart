import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../routes/app_routes.dart';

/// Navigation helpers for consistent go_router usage.
extension SaganaNavigation on BuildContext {
  void goTab(String route) => GoRouter.of(this).go(route);

  Future<T?> pushRoute<T extends Object?>(String route, {Object? extra}) =>
      GoRouter.of(this).push<T>(route, extra: extra);

  void popRoute([Object? result]) => GoRouter.of(this).pop(result);

  void goLogin() => go(AppRoutes.login);
}
