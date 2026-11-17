import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/services/app_update_service.dart';
import 'app_dialog.dart';
import 'app_toast.dart';

/// The "update available" / "update required" notice.
///
/// Optional: can be dismissed with Later (it comes back after a day).
/// Required: cannot be dismissed (no Later, no tap outside, no Back); the only
/// way forward is to open the download page and install the new version.
Future<void> showAppUpdateDialog(BuildContext context, AppUpdateStatus status) {
  final release = status.release!;
  final isRequired = status.kind == AppUpdateKind.required;

  return AppDialog.show<void>(
    context: context,
    barrierDismissible: false,
    child: PopScope(
      canPop: !isRequired,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Builder(
              builder: (ctx) {
                final l10n = AppLocalizations.of(ctx);
                final cs = Theme.of(ctx).colorScheme;
                final notes = release.notesFor(l10n.localeName);

                Future<void> openDownloadPage() async {
                  var opened = false;
                  try {
                    opened = await launchUrl(
                      Uri.parse(release.landingUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {
                    opened = false;
                  }
                  if (!ctx.mounted) return;
                  if (!opened) {
                    AppToast.show(ctx, l10n.appUpdateOpenFailed, isError: true);
                  } else if (!isRequired) {
                    Navigator.of(ctx).pop();
                  }
                }

                return Container(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isRequired
                                  ? AppConstants.gold.withValues(alpha: 0.2)
                                  : cs.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.system_update_rounded,
                              color: isRequired
                                  ? AppConstants.warningAmber
                                  : cs.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isRequired
                                  ? l10n.appUpdateRequiredTitle
                                  : l10n.appUpdateTitle,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isRequired
                            ? l10n.appUpdateRequiredBody(release.versionName)
                            : l10n.appUpdateBody(
                                release.versionName,
                                status.installedVersion,
                              ),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          height: 1.45,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (notes != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.appUpdateNotesTitle,
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                notes,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: openDownloadPage,
                          icon: const Icon(Icons.download_rounded),
                          label: Text(l10n.appUpdateNow),
                        ),
                      ),
                      if (!isRequired) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () {
                              AppUpdateService.instance.remindLater(release);
                              Navigator.of(ctx).pop();
                            },
                            child: Text(l10n.appUpdateLater),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
