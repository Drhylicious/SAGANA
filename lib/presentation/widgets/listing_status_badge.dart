import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/marketplace_listing_model.dart';

/// What a Marketplace listing is, in the words Farmers and Managers read.
///
/// The stored `marketplace_listings.status` values do not change
/// (`pending_review`, `approved`, `sold`, `rejected`, `withdrawn`). This enum
/// is the one place that turns a stored status plus the stock left on the
/// listing into the label, colour and greyed-out rule every Marketplace
/// screen shares:
///
///   pending_review                      -> Pending Approval
///   approved with kg still for sale     -> Available
///   sold, or approved with 0 kg left    -> Sold Out
///   rejected                            -> Disapproved
///   withdrawn                           -> Withdrawn (Farmer only)
enum ListingState { pendingApproval, available, soldOut, disapproved, withdrawn }

/// The three outcomes of the Manager's approval decision. A Sold Out listing
/// was approved, so it counts as Approved here.
enum ListingApproval { pending, approved, disapproved }

/// Maps a stored status and the kg still open for purchase to a [ListingState].
/// Returns null for a status this app does not know (the badge then shows the
/// raw value rather than guessing).
///
/// An approved listing with nothing left is Sold Out even before the order
/// that took the last kg is completed: it can no longer be bought, which is
/// what the label tells people. If that order is cancelled the kg come back
/// and the listing is Available again.
ListingState? listingStateOf({
  required String status,
  required double remainingKg,
}) {
  switch (status) {
    case 'pending_review':
      return ListingState.pendingApproval;
    case 'approved':
      return remainingKg <= 0 ? ListingState.soldOut : ListingState.available;
    case 'sold':
      return ListingState.soldOut;
    case 'rejected':
      return ListingState.disapproved;
    case 'withdrawn':
      return ListingState.withdrawn;
    default:
      return null;
  }
}

/// The approval outcome for a stored status, or null when the Manager never
/// decided on it (a withdrawn listing).
ListingApproval? listingApprovalOf(String status) {
  switch (status) {
    case 'pending_review':
      return ListingApproval.pending;
    case 'approved':
    case 'sold':
      return ListingApproval.approved;
    case 'rejected':
      return ListingApproval.disapproved;
    default:
      return null;
  }
}

String listingStateLabel(AppLocalizations l10n, ListingState state) {
  switch (state) {
    case ListingState.pendingApproval:
      return l10n.listingStatePendingApproval;
    case ListingState.available:
      return l10n.listingStateAvailable;
    case ListingState.soldOut:
      return l10n.listingStateSoldOut;
    case ListingState.disapproved:
      return l10n.listingStateDisapproved;
    case ListingState.withdrawn:
      return l10n.listingStateWithdrawn;
  }
}

String listingApprovalLabel(AppLocalizations l10n, ListingApproval approval) {
  switch (approval) {
    case ListingApproval.pending:
      return l10n.listingStatePendingApproval;
    case ListingApproval.approved:
      return l10n.listingStateApproved;
    case ListingApproval.disapproved:
      return l10n.listingStateDisapproved;
  }
}

Color listingStateColor(BuildContext context, ListingState state) {
  final cs = Theme.of(context).colorScheme;
  switch (state) {
    case ListingState.pendingApproval:
      return AppConstants.warningAmber;
    case ListingState.available:
      return AppConstants.successGreen;
    case ListingState.soldOut:
      return cs.onSurfaceVariant;
    case ListingState.disapproved:
      return cs.error;
    case ListingState.withdrawn:
      return AppConstants.mutedSlate;
  }
}

Color listingApprovalColor(BuildContext context, ListingApproval approval) {
  final cs = Theme.of(context).colorScheme;
  switch (approval) {
    case ListingApproval.pending:
      return AppConstants.warningAmber;
    case ListingApproval.approved:
      return AppConstants.successGreen;
    case ListingApproval.disapproved:
      return cs.error;
  }
}

/// Localized chip text for the Farmer's My Listings filter row.
String listingFilterLabel(AppLocalizations l10n, ListingFilter filter) {
  switch (filter) {
    case ListingFilter.all:
      return l10n.farmerMgmtAllFilter;
    case ListingFilter.pending:
      return l10n.listingStatePendingApproval;
    case ListingFilter.available:
      return l10n.listingStateAvailable;
    case ListingFilter.soldOut:
      return l10n.listingStateSoldOut;
    case ListingFilter.disapproved:
      return l10n.listingStateDisapproved;
    case ListingFilter.withdrawn:
      return l10n.listingStateWithdrawn;
  }
}

Color listingFilterColor(BuildContext context, ListingFilter filter) {
  switch (filter) {
    case ListingFilter.all:
      return Theme.of(context).colorScheme.primary;
    case ListingFilter.pending:
      return listingStateColor(context, ListingState.pendingApproval);
    case ListingFilter.available:
      return listingStateColor(context, ListingState.available);
    case ListingFilter.soldOut:
      return listingStateColor(context, ListingState.soldOut);
    case ListingFilter.disapproved:
      return listingStateColor(context, ListingState.disapproved);
    case ListingFilter.withdrawn:
      return listingStateColor(context, ListingState.withdrawn);
  }
}

/// The thin accent bar on a listing card. Only the two states that call for
/// attention get one: Pending Approval (amber) and Disapproved (red). Available
/// and Sold Out cards have none, so the colour always means the same thing.
/// Same colours as the badge, so a card can never contradict its own pill.
Color? listingAccentColor(BuildContext context, ListingState? state) {
  switch (state) {
    case ListingState.pendingApproval:
    case ListingState.disapproved:
      return listingStateColor(context, state!);
    default:
      return null;
  }
}

/// Status pill used on every Marketplace listing card, Manager and Farmer.
class ListingStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const ListingStatusBadge({super.key, required this.label, required this.color});

  /// Availability view: Pending Approval / Available / Sold Out / Disapproved
  /// / Withdrawn. Used on All Listings and on the Farmer's My Listings.
  factory ListingStatusBadge.forListing(
    BuildContext context, {
    required String status,
    required double remainingKg,
  }) {
    final l10n = AppLocalizations.of(context);
    final state = listingStateOf(status: status, remainingKg: remainingKg);
    if (state == null) {
      return ListingStatusBadge(
        label: status,
        color: Theme.of(context).colorScheme.outline,
      );
    }
    return ListingStatusBadge(
      label: listingStateLabel(l10n, state),
      color: listingStateColor(context, state),
    );
  }

  /// Approval view: Pending Approval / Approved / Disapproved. Used on the
  /// Manager's Listing Approvals screen, which is about the decision rather
  /// than the stock.
  factory ListingStatusBadge.forApproval(
    BuildContext context, {
    required String status,
  }) {
    final l10n = AppLocalizations.of(context);
    final approval = listingApprovalOf(status);
    if (approval == null) {
      return ListingStatusBadge(
        label: status,
        color: Theme.of(context).colorScheme.outline,
      );
    }
    return ListingStatusBadge(
      label: listingApprovalLabel(l10n, approval),
      color: listingApprovalColor(context, approval),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}

/// Greys out a listing card once it is Sold Out, so it reads as no longer
/// buyable. The card stays tappable; only its look changes.
class SoldOutGrey extends StatelessWidget {
  final bool active;
  final Widget child;

  const SoldOutGrey({super.key, required this.active, required this.child});

  static const ColorFilter _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Opacity(
      opacity: 0.6,
      child: ColorFiltered(colorFilter: _grayscale, child: child),
    );
  }
}

/// A listing's state as a banner: the same badge as every listing card, with
/// the quantity behind it. Used at the top of the Manager's Listing Review so
/// that screen can never disagree with All Listings: both decide the state
/// from the stored status and the quantity actually left ([listingStateOf]).
class ListingStatusHeader extends StatelessWidget {
  final String status;
  final double remainingKg;
  final double volumeKg;

  /// The unit remainingKg and volumeKg are measured in.
  final String unit;

  const ListingStatusHeader({
    super.key,
    required this.status,
    required this.remainingKg,
    required this.volumeKg,
    this.unit = kDefaultUnit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final state = listingStateOf(status: status, remainingKg: remainingKg);
    final color = state == null ? cs.outline : listingStateColor(context, state);

    // Stock left only means something once the listing has been approved.
    final showLeft =
        state == ListingState.available || state == ListingState.soldOut;
    final detail = showLeft
        ? l10n.listingReviewKgLeft(
            formatQuantity(remainingKg),
            formatQuantityUnit(volumeKg, unit),
          )
        : l10n.listingReviewKgListed(formatQuantityUnit(volumeKg, unit));


    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Flexible(
            child: ListingStatusBadge.forListing(
              context,
              status: status,
              remainingKg: remainingKg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              detail,
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
