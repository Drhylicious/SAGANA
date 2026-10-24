import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/services/market_types_service.dart';

/// "DA-AMAD Market Linking Only" — shown on a crop or batch that is reserved
/// for one selling channel (crop_master.exclusive_channel; Ginger → DA-AMAD).
///
/// It is separate from the market-type badge on purpose: the market type says
/// WHO can see a listing (Public / Cooperative); this says HOW the crop can be
/// sold. The channel name comes from the selling_channels table, so nothing
/// here names a crop. Renders nothing for an ordinary crop.
class ChannelOnlyBadge extends StatelessWidget {
  final String? channel;

  const ChannelOnlyBadge({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    if (channel == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    const color = AppConstants.snackbarWarning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppConstants.amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_shipping_outlined, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              l10n.channelOnlyBadge(MarketTypes.instance.channelLabel(channel)),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
