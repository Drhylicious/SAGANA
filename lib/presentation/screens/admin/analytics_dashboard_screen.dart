import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_analytics_model.dart';
import '../../../data/models/analytics_model.dart';
import '../../../data/repositories/admin_analytics_repository.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/repositories/analytics_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/planting_forecast_card.dart';
import '../../widgets/top_harvested_crops_chart.dart';
import '../../widgets/trend_chart_painter.dart';

/// Analytics Dashboard — Admin.
/// Pushed above the shell. Route: /admin/analytics
///
/// Deliberately does not duplicate the Operational Reports hub's KPI
/// summary — that surface already belongs to Reports. This screen focuses
/// on what's genuinely analytical: planting forecast trend, top harvested
/// crops, member participation, loan health, and a price snapshot linking
/// out to the full Price Management screen rather than rebuilding it.
///
/// Planting Recommendations are read-only and framed the same honest way
/// as the farmer-facing screen (supply-trend only, not demand-informed) —
/// there is no override mechanism, since crop_planting_forecast is a
/// computed SQL view, not a table.
class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  final _analyticsRepo = AnalyticsRepository();
  final _loanRepo = AdminLoanRepository();
  final _adminAnalyticsRepo = AdminAnalyticsRepository();

  bool _isLoading = true;
  bool _isSendingReminders = false;

  List<PlantingForecast> _forecasts = [];
  List<TopSellingCrop> _topCrops = [];
  List<CropPriceCard> _priceCards = [];
  dynamic _loanSummary;
  List<double> _collectionTrend = [];
  MemberParticipationSummary _participation = MemberParticipationSummary.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _analyticsRepo.fetchPlantingForecasts(),
      _analyticsRepo.fetchTopSellingCrops(),
      _analyticsRepo.fetchPriceCards(),
      _loanRepo.fetchAllTimeLoanSummary(),
      _loanRepo.fetchMonthlyCollectionTrend(),
      _adminAnalyticsRepo.fetchMemberParticipation(),
    ]);
    if (!mounted) return;
    setState(() {
      _forecasts = results[0] as List<PlantingForecast>;
      _topCrops = results[1] as List<TopSellingCrop>;
      _priceCards = results[2] as List<CropPriceCard>;
      _loanSummary = results[3];
      _collectionTrend = results[4] as List<double>;
      _participation = results[5] as MemberParticipationSummary;
      _isLoading = false;
    });
  }

  List<CropPriceCard> get _topPriceMovers {
    final withChange = _priceCards.where((c) => c.priceDiff != null).toList()
      ..sort((a, b) => b.priceDiff!.abs().compareTo(a.priceDiff!.abs()));
    return withChange.take(4).toList();
  }

  Future<void> _confirmAndSendReminders() async {
    final l10n = AppLocalizations.of(context);
    final count = _participation.inactiveCount;
    if (count == 0) return;

    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: AlertDialog(
        title: Text(l10n.analyticsSendReminderTitle, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(l10n.analyticsSendReminderMessage(count), style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.issueLoanCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.analyticsSendReminderConfirm, style: const TextStyle(color: AppConstants.primaryGreen)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSendingReminders = true);
    try {
      await _adminAnalyticsRepo.sendReminders(
        farmerIds: _participation.inactiveFarmers.map((f) => f.id).toList(),
        title: l10n.analyticsReminderNotifTitle,
        body: l10n.analyticsReminderNotifBody,
      );
      if (!mounted) return;
      _showSnack(l10n.analyticsReminderSent(count));
    } catch (_) {
      if (!mounted) return;
      _showSnack(l10n.analyticsReminderError, isError: true);
    } finally {
      if (mounted) setState(() => _isSendingReminders = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: isError ? AppConstants.errorRed : AppConstants.successGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopBar(context, l10n, cs, sagana),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        AppConstants.spacingGutter,
                        AppConstants.spacingSafeH,
                        32,
                      ),
                      children: [
                        _buildParticipationCard(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildLoanHealthCard(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildPriceSnapshot(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        const PlantingForecastSectionHeader(),
                        const SizedBox(height: AppConstants.spacingMd),
                        if (_forecasts.isEmpty)
                          _buildEmptyState(l10n.analyticsNoForecastsYet, cs)
                        else
                          ..._forecasts.map((f) => Padding(
                                padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
                                child: PlantingForecastCard(forecast: f),
                              )),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        if (_topCrops.isNotEmpty) TopHarvestedCropsChart(crops: _topCrops),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSm),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  l10n.reportsAnalyticsDashboard,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipationCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.analyticsMemberParticipation, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(child: _tierStat(l10n.analyticsActiveHarvested, _participation.activeHarvestedCount, AppConstants.successGreen)),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(child: _tierStat(l10n.analyticsActiveListed, _participation.activeListedCount, AppConstants.buyerBlue)),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(child: _tierStat(l10n.analyticsInactive, _participation.inactiveCount, AppConstants.warningAmber)),
            ],
          ),
          if (_participation.inactiveCount > 0) ...[
            const SizedBox(height: AppConstants.spacingGutter),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSendingReminders ? null : _confirmAndSendReminders,
                icon: _isSendingReminders
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.notifications_active_outlined, size: 16),
                label: Text(l10n.analyticsSendReminder(_participation.inactiveCount)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tierStat(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text('$count', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: color)),
          Text(label, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 9, color: color)),
        ],
      ),
    );
  }

  Widget _buildLoanHealthCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final summary = _loanSummary;
    final isHealthy = summary?.isHealthy ?? true;
    final repaymentRate = (summary?.repaymentRatePercent ?? 0.0) as double;
    final healthColor = isHealthy ? AppConstants.successGreen : AppConstants.warningAmber;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.analyticsLoanHealth, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
              Text(
                '${repaymentRate.toStringAsFixed(0)}% ${l10n.analyticsCollectionRate}',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: healthColor),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          SizedBox(
            height: 100,
            child: _collectionTrend.length < 2
                ? Center(
                    child: Text(l10n.reportsNotEnoughTrendData, style: GoogleFonts.inter(fontSize: 12, color: cs.outline)),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 100),
                    painter: TrendChartPainter(
                      values: _collectionTrend,
                      lineColor: cs.primary,
                      gradientColor: cs.primary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSnapshot(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final movers = _topPriceMovers;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.analyticsPriceSnapshot, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingSm),
          if (movers.isEmpty)
            Text(l10n.reportsNotEnoughTrendData, style: GoogleFonts.inter(fontSize: 12, color: cs.outline))
          else
            ...movers.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(c.cropName, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface)),
                      Row(
                        children: [
                          Icon(
                            c.isUp ? Icons.arrow_upward_rounded : c.isDown ? Icons.arrow_downward_rounded : Icons.remove_rounded,
                            size: 13,
                            color: c.isUp ? AppConstants.successGreen : c.isDown ? AppConstants.errorRed : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '₱${c.currentPrice.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: AppConstants.spacingSm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.priceManagement),
              child: Text(l10n.analyticsViewFullPrices, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Text(message, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }
}