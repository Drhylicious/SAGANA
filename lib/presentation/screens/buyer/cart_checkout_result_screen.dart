import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

class CartCheckoutResultScreen extends StatelessWidget {
  final List<CartItemModel> succeeded;
  final List<(CartItemModel, String)> failed;

  const CartCheckoutResultScreen({super.key, required this.succeeded, required this.failed});

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final allSucceeded = failed.isEmpty;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH),
          child: Column(
            children: [
              const Spacer(),
              Icon(
                allSucceeded ? Icons.check_circle_rounded : Icons.info_rounded,
                size: 72,
                color: allSucceeded ? AppConstants.successGreen : AppConstants.warningAmber,
              ),
              const SizedBox(height: 20),
              Text(
                allSucceeded ? 'Order Placed!' : '${succeeded.length} of ${succeeded.length + failed.length} Items Ordered',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen),
              ),
              const SizedBox(height: 8),
              Text(
                allSucceeded
                    ? '${AppConstants.cooperativeName} will review your order shortly.'
                    : 'Some items couldn\'t be ordered — see details below.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (succeeded.isNotEmpty) ...[
                Align(alignment: Alignment.centerLeft,
                    child: Text('ORDERED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.successGreen, letterSpacing: 0.5))),
                const SizedBox(height: 6),
                ...succeeded.map((item) => _resultRow(item.displayName, '${item.quantityKg.toStringAsFixed(0)} kg', AppConstants.successGreen, Icons.check_circle_outline_rounded)),
              ],
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft,
                    child: Text('COULDN\'T BE ORDERED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.errorRed, letterSpacing: 0.5))),
                const SizedBox(height: 6),
                ...failed.map((f) => _resultRow(f.$1.displayName, f.$2, AppConstants.errorRed, Icons.error_outline_rounded)),
              ],
              const Spacer(),
              SizedBox(width: double.infinity, child: PrimaryButton(label: 'View My Orders', onPressed: () => context.go(AppRoutes.myOrders))),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go(AppRoutes.marketplaceBrowse),
                child: Text('Continue Shopping', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultRow(String title, String subtitle, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 13))),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
