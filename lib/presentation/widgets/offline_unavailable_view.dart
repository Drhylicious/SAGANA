import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';

/// Shown in place of a screen's content when the device is offline and that
/// content was never saved on it. It says the data needs a connection; it never
/// says the data does not exist. One wording for every role.
class OfflineUnavailableView extends StatelessWidget {
  final VoidCallback? onRetry;

  const OfflineUnavailableView({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingGutter * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 40,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.offlineNeedsInternetTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.offlineNeedsInternet,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
