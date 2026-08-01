import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/models/farmer_market_rate_model.dart';
import '../../../data/repositories/farmer_market_rates_repository.dart';
import '../../widgets/shared_widgets.dart';

class MarketRateDetailsScreen extends StatefulWidget {
  final FarmerMarketRateModel? rate;

  const MarketRateDetailsScreen({super.key, required this.rate});

  @override
  State<MarketRateDetailsScreen> createState() =>
      _MarketRateDetailsScreenState();
}

class _MarketRateDetailsScreenState extends State<MarketRateDetailsScreen> {
  final _ratesRepo = FarmerMarketRatesRepository();
  List<FarmerMarketRateModel> _otherRates = [];

  @override
  void initState() {
    super.initState();
    if (widget.rate != null) _loadOtherRates(widget.rate!);
  }

  Future<void> _loadOtherRates(FarmerMarketRateModel rate) async {
    final rows = await _ratesRepo.fetchMarketRates(cropId: rate.cropId);
    if (!mounted) return;
    setState(() {
      _otherRates =
          rows.where((r) => r.priceType != rate.priceType).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.rate;
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          if (rate != null) _buildHeroBackground(context) else const SizedBox(),
          Column(
            children: [
              SizedBox(height: 64 + MediaQuery.of(context).padding.top),
              Expanded(
                child: rate == null
                    ? _buildMissingState(context)
                    : _buildDetails(context, rate),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              overlay: rate != null,
              title: rate?.cropName ?? 'Market Rate Details',
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }

  // Fixed gradient block behind the top of the screen — the floating
  // hero card overlaps its bottom edge, same visual relationship as the
  // reference. Height is tuned so the card's overlap looks intentional,
  // not clipped.
  Widget _buildHeroBackground(BuildContext context) {
    return Container(
      height: 200 + MediaQuery.of(context).padding.top,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppConstants.primaryGreen,
            AppConstants.primaryGreen.withValues(alpha: 0.85),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined,
                size: 40, color: AppConstants.outline),
            const SizedBox(height: 16),
            Text(
              'This market rate could not be loaded.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, FarmerMarketRateModel rate) {
    final color = MarketTypeDisplay.color(context, rate.priceType);
    final icon = FarmerCropModel.iconForCategory(rate.cropCategory);

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ─── Floating hero card ─────────────────────────────────
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(icon, color: color, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  MarketTypeDisplay.label(rate.priceType),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                rate.cropName,
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppConstants.charcoal,
                                ),
                              ),
                              Text(
                                rate.cropCategory,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppConstants.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '₱${rate.priceValue.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: AppConstants.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/${rate.unit}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppConstants.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (rate.price.previousPrice != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            rate.isUp
                                ? Icons.arrow_upward_rounded
                                : rate.isDown
                                    ? Icons.arrow_downward_rounded
                                    : Icons.remove_rounded,
                            size: 14,
                            color: rate.isUp
                                ? AppConstants.primaryGreen
                                : rate.isDown
                                    ? AppConstants.errorRed
                                    : AppConstants.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '₱${rate.price.priceDifference!.abs().toStringAsFixed(2)} vs. previous entry',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppConstants.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ─── Combined Details card, icon tiles ─────────────────
              GlassCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Effective Date',
                      value: AppUtils.formatDate(rate.recordedAt),
                    ),
                    Divider(
                      height: 1,
                      color: AppConstants.outline.withValues(alpha: 0.15),
                    ),
                    _DetailRow(
                      icon: Icons.description_outlined,
                      label: 'Source / Reference',
                      value: rate.source?.trim().isNotEmpty == true
                          ? rate.source!
                          : 'Not specified',
                    ),
                  ],
                ),
              ),

              if (_otherRates.isNotEmpty) ...[
                const SizedBox(height: 20),
                _SectionLabel(
                  text: 'OTHER PRICES FOR ${rate.cropName.toUpperCase()}',
                ),
                const SizedBox(height: 8),
                ..._otherRates.map((other) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OtherPriceRow(rate: other),
                    )),
              ],

              const SizedBox(height: 20),
              _SectionLabel(text: 'ABOUT ${rate.cropName.toUpperCase()}'),
              const SizedBox(height: 8),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Text(
                  rate.cropDescription?.trim().isNotEmpty == true
                      ? rate.cropDescription!
                      : 'No additional information available for this crop yet.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.5,
                    color: AppConstants.charcoal,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  border: Border.all(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppConstants.primaryGreen, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Prices are set and updated by the cooperative to '
                        'guide fair trading among local producers and buyers.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppConstants.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 14, color: AppConstants.outline),
                    const SizedBox(width: 6),
                    Text(
                      'Updated ${AppUtils.formatRelativeTime(rate.recordedAt)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppConstants.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 100), // clears the wave below
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: 90,
                color: AppConstants.primaryGreen.withValues(alpha: 0.08),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppConstants.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppConstants.outline,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: AppConstants.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.charcoal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherPriceRow extends StatelessWidget {
  final FarmerMarketRateModel rate;
  const _OtherPriceRow({required this.rate});

  @override
  Widget build(BuildContext context) {
    final color = MarketTypeDisplay.color(context, rate.priceType);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              MarketTypeDisplay.label(rate.priceType),
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const Spacer(),
          Text(
            rate.formattedPrice,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppConstants.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}

// Native Flutter equivalent of the reference's SVG wave — no new package
// dependency required.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.5);
    path.quadraticBezierTo(
      size.width * 0.3, size.height * 1.1,
      size.width * 0.55, size.height * 0.5,
    );
    path.quadraticBezierTo(
      size.width * 0.8, size.height * -0.1,
      size.width, size.height * 0.5,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}