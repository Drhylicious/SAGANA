import 'package:flutter/material.dart';

class AdminRoutePlaceholderScreen extends StatelessWidget {
  const AdminRoutePlaceholderScreen({
    super.key,
    this.title,
    this.description,
    this.routeName,
    this.label,
  });

  final String? title;
  final String? description;
  final String? routeName;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedTitle = title ?? label ?? routeName ?? 'Coming Soon';
    final resolvedDescription =
        description ?? 'This route is not implemented yet.';

    return Scaffold(
      appBar: AppBar(
        title: Text(resolvedTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                resolvedTitle,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                resolvedDescription,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
