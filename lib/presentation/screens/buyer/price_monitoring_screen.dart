import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/price_record_model.dart';
import '../../../data/repositories/price_management_repository.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/buyer_top_bar.dart';
import '../../widgets/shared_widgets.dart';

class PriceMonitoringScreen extends StatefulWidget {
  const PriceMonitoringScreen({super.key});

  @override
  State<PriceMonitoringScreen> createState() => _PriceMonitoringScreenState();
}

class _PriceMonitoringScreenState extends State<PriceMonitoringScreen> {
  final _priceRepo = PriceManagementRepository();
  final _marketRepo = BuyerMarketplaceRepository();
  final _notificationRepo = NotificationRepository();

  bool _isLoading = true;
  List<PriceRecordModel> _latestPrices = [];
  Set<String> _listedCrops = {};
  String? _selectedCropId;
  List<PriceRecordModel> _trend = [];
  bool _isTrendLoading = false;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _priceRepo.fetchLatestPricePerCrop(),
      _marketRepo.fetchListedCropNames(),
      _notificationRepo.fetchUnreadCount(),
    ]);
    if (!mounted) return;
    final prices = results[0] as List<PriceRecordModel>;
    setState(() {
      _latestPrices = prices;
      _listedCrops = results[1] as Set<String>;
      _unreadCount = results[2] as int;
      _isLoading = false;
    });
    if (prices.isNotEmpty) _selectCrop(prices.first.cropId);
  }

  Future<void> _selectCrop(String cropId) async {
    setState(() {
      _selectedCropId = cropId;
      _isTrendLoading = true;
    });
    final trend = await _priceRepo.fetchTrendForCrop(cropId);
    if (!mounted) return;
    setState(() {
      _trend = trend;
      _isTrendLoading = false;
    });
  }

  PriceRecordModel? get _selectedPrice =>
      _latestPrices.where((p) => p.cropId == _selectedCropId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _latestPrices.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 16, AppConstants.spacingSafeH, 100),
                                children: [
                                  _buildCropChips(),
                                  const SizedBox(height: 16),
                                  if (_selectedPrice != null) _buildTrendCard(_selectedPrice!),
                                  const SizedBox(height: 20),
                                  Text('All Crops', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                                  const SizedBox(height: 10),
                                  ..._latestPrices.map((p) => _buildPriceCard(p)),
                                ],
                              ),
                            ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: BuyerTopBar(
              title: 'Market Prices',
              unreadCount: _unreadCount,
              onNotificationTap: () => context.push(AppRoutes.buyerNotifications),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up_rounded, size: 56, color: AppConstants.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No price data yet', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Price data will appear here once SP3 Cooperative records market rates for a crop.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCropChips() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _latestPrices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = _latestPrices[i];
          final isSelected = p.cropId == _selectedCropId;
          final hasDuplicateName =
              _latestPrices.where((x) => x.cropName == p.cropName).length > 1;
          final label = hasDuplicateName
              ? '${p.cropName} · ${_shortType(p.priceType)}'
              : p.cropName;
          return GestureDetector(
            onTap: () => _selectCrop(p.cropId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppConstants.primaryGreen : Colors.white,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                border: Border.all(color: isSelected ? AppConstants.primaryGreen : AppConstants.outline.withValues(alpha: 0.25)),
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppConstants.onSurfaceVariant)),
            ),
          );
        },
      ),
    );
  }

  String _shortType(String type) {
    switch (type) {
      case 'sp3_cooperative': return 'SP3';
      case 'da_amad_market':  return 'DA-AMAD';
      default:                return 'Market Avg';
    }
  }

  Widget _buildTrendCard(PriceRecordModel current) {
    final prices = _trend.map((p) => p.price).toList();
    final high = prices.isEmpty ? current.price : prices.reduce((a, b) => a > b ? a : b);
    final low = prices.isEmpty ? current.price : prices.reduce((a, b) => a < b ? a : b);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(current.cropName, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(current.priceTypeLabel, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(current.formattedPrice,
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
                  if (current.previousPrice != null)
                    Row(
                      children: [
                        Icon(
                          current.isUp ? Icons.arrow_upward_rounded : current.isDown ? Icons.arrow_downward_rounded : Icons.remove_rounded,
                          size: 12,
                          color: current.isUp ? AppConstants.successGreen : current.isDown ? AppConstants.errorRed : AppConstants.outline,
                        ),
                        Text('₱${current.priceDifference!.abs().toStringAsFixed(2)}',
                            style: GoogleFonts.inter(fontSize: 11,
                                color: current.isUp ? AppConstants.successGreen : current.isDown ? AppConstants.errorRed : AppConstants.outline)),
                      ],
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_listedCrops.contains(current.cropName.toLowerCase()))
            _statusTag('Currently available on marketplace', AppConstants.successGreen)
          else
            _statusTag('Not currently listed', AppConstants.outline),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: _isTrendLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : prices.length < 2
                    ? Center(
                        child: Text('Not enough history for a trend chart yet',
                            style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)))
                    : CustomPaint(
                        painter: _SparklinePainter(prices: prices, color: AppConstants.primaryGreen),
                        size: Size.infinite,
                      ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statColumn('High', '₱${high.toStringAsFixed(2)}', AppConstants.successGreen),
              _statColumn('Low', '₱${low.toStringAsFixed(2)}', AppConstants.errorRed),
              _statColumn('Current', current.formattedPrice, AppConstants.primaryGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _statColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
        Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  Widget _buildPriceCard(PriceRecordModel p) {
    final isSelected = p.cropId == _selectedCropId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _selectCrop(p.cropId),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: isSelected ? Border.all(color: AppConstants.primaryGreen, width: 1.5) : null,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.cropName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(p.priceTypeLabel, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                ],
              ),
              Row(
                children: [
                  if (p.previousPrice != null)
                    Icon(
                      p.isUp ? Icons.arrow_upward_rounded : p.isDown ? Icons.arrow_downward_rounded : Icons.remove_rounded,
                      size: 14,
                      color: p.isUp ? AppConstants.successGreen : p.isDown ? AppConstants.errorRed : AppConstants.outline,
                    ),
                  const SizedBox(width: 4),
                  Text(p.formattedPrice, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimal local sparkline — see the note above about trend_chart_painter.dart.
class _SparklinePainter extends CustomPainter {
  final List<double> prices;
  final Color color;
  const _SparklinePainter({required this.prices, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final min = prices.reduce((a, b) => a < b ? a : b);
    final max = prices.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 0.01 ? 1.0 : max - min;

    final path = Path();
    final stepX = size.width / (prices.length - 1);
    for (int i = 0; i < prices.length; i++) {
      final x = i * stepX;
      final y = size.height - ((prices[i] - min) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.prices != prices || oldDelegate.color != color;
}