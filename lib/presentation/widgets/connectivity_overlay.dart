import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/services/connectivity_service.dart';
import '../../data/services/guest_mode_service.dart';
import '../../data/services/hive_service.dart';

/// The only connectivity notice, above all Navigators, pages and dialogs.
/// The page keeps its original constraints; the notice can be dismissed.
class ConnectivityOverlay extends StatefulWidget {
  final Widget child;
  final GoRouter router;

  const ConnectivityOverlay({
    super.key,
    required this.child,
    required this.router,
  });

  @override
  State<ConnectivityOverlay> createState() => _ConnectivityOverlayState();
}

class _ConnectivityOverlayState extends State<ConnectivityOverlay> {
  StreamSubscription<bool>? _subscription;
  Timer? _dismiss;
  late bool _online;
  late bool _visible;

  @override
  void initState() {
    super.initState();
    _online = ConnectivityService.instance.isOnline;
    _visible = !_online;
    _subscription = ConnectivityService.instance.onConnectivityChanged.listen((
      online,
    ) {
      // Repeated probes must not restart the notice or add another timer.
      if (!mounted || online == _online) return;
      _dismiss?.cancel();
      setState(() {
        _online = online;
        _visible = true;
      });
      if (online) {
        _dismiss = Timer(const Duration(seconds: 12), () {
          if (mounted) setState(() => _visible = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dismiss?.cancel();
    super.dispose();
  }

  void _hide() {
    _dismiss?.cancel();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // MaterialApp.builder is above the Navigator's Overlay. The close button's
    // Tooltip needs an Overlay ancestor, not the sibling Navigator below it.
    return Overlay.wrap(
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_visible)
            Positioned(
              top: media.padding.top + 68,
              left: media.padding.left + 24,
              right: media.padding.right + 24,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  widget.router.routerDelegate,
                  GuestModeService.instance,
                ]),
                builder: (context, _) {
                  final l10n = AppLocalizations.of(context);
                  final supportsRecords =
                      HiveService.isLoggedIn() &&
                      !GuestModeService.active &&
                      const [
                        'admin',
                        'officer',
                        'farmer',
                      ].contains(HiveService.getUserRole());
                  final message = _online
                      ? supportsRecords
                            ? l10n.connectivityOnlineRecords
                            : l10n.connectivityOnlineBuyer
                      : supportsRecords
                      ? l10n.connectivityOfflineRecords
                      : l10n.connectivityOfflineBuyer;
                  return Center(
                    child: SizedBox(
                      width:
                          ((media.size.width - media.padding.horizontal) * 0.84)
                              .clamp(0.0, 340.0)
                              .toDouble(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 340,
                          maxHeight:
                              (media.size.height - media.padding.vertical - 92)
                                  .clamp(0.0, media.size.height * 0.4)
                                  .toDouble(),
                        ),
                        child: _ConnectivityNotice(
                          online: _online,
                          title: _online
                              ? l10n.connectivityOnlineTitle
                              : l10n.connectivityOfflineTitle,
                          message: message,
                          onDismiss: _hide,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Both states share the same layout, spacing, typography and shape.
class _ConnectivityNotice extends StatelessWidget {
  final bool online;
  final String title;
  final String message;
  final VoidCallback onDismiss;

  const _ConnectivityNotice({
    required this.online,
    required this.title,
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = online
        ? dark
              ? const Color(0xFF173E29)
              : const Color(0xFFDCFCE7)
        : theme.colorScheme.errorContainer;
    final foreground = online
        ? dark
              ? const Color(0xFFC9F1D6)
              : const Color(0xFF14532D)
        : theme.colorScheme.onErrorContainer;
    final border = online
        ? dark
              ? const Color(0xFF477D59)
              : const Color(0xFFA7DDB6)
        : theme.colorScheme.error.withValues(alpha: 0.25);
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: foreground,
      fontSize: 12,
      height: 1.35,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: Colors.transparent,
        elevation: 4,
        shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: foreground,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: onDismiss,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: foreground,
                      ),
                      visualDensity: VisualDensity.standard,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 28, right: 4),
                  child: Text(message, style: bodyStyle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
