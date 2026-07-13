import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

class AdminFarmerHarvestHistoryScreen extends StatelessWidget {
  const AdminFarmerHarvestHistoryScreen({super.key, this.farmerId});

  final String? farmerId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Harvest History'),
        backgroundColor: AppConstants.primaryGreen,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppConstants.offWhite,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingGutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.eco_rounded,
                size: 64,
                color: AppConstants.primaryGreen,
              ),
              const SizedBox(height: AppConstants.spacingMd),
              Text(
                'Admin View Only',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: AppConstants.spacingSm),
              Text(
                farmerId == null
                    ? 'Viewing harvest history for the selected farmer.'
                    : 'Viewing harvest history for farmer $farmerId.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
