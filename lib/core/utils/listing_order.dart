import '../../data/models/marketplace_listing_model.dart';
import '../../data/repositories/admin_listing_repository.dart';

/// Display order for the Manager's listing screens. Both keep the order the
/// listings arrive in (newest first) within each group and only move whole
/// groups, so a filter or a search never changes how listings compare.
///
/// Dart's [List.sort] is not stable (equal items may swap), so this sorts by
/// (group, original position) instead.
/// Oldest first, and equal times keep their original order (first in, first out).
/// Used for the queues of work staff have to get through, so what has waited longest is
/// handled first; every other list is newest first.
List<T> oldestFirst<T>(Iterable<T> items, DateTime Function(T) at) {
  final indexed = [for (final (i, item) in items.indexed) (i, item)];
  indexed.sort((a, b) {
    final byTime = at(a.$2).compareTo(at(b.$2));
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

List<T> stableGroupSort<T>(Iterable<T> items, int Function(T) group) {
  final indexed = <(int, int, T)>[
    for (final (i, item) in items.indexed) (group(item), i, item),
  ];
  indexed.sort((a, b) {
    final byGroup = a.$1.compareTo(b.$1);
    return byGroup != 0 ? byGroup : a.$2.compareTo(b.$2);
  });
  return [for (final e in indexed) e.$3];
}

/// All Listings: every listing that can still be bought comes first, Sold Out
/// listings go to the very bottom. Pending, Available and Disapproved listings
/// keep their normal (newest-first) order among themselves.
int allListingsGroup(AdminListingModel listing) => listing.isSoldOut ? 1 : 0;

List<AdminListingModel> orderForAllListings(
  Iterable<AdminListingModel> listings,
) => stableGroupSort(listings, allListingsGroup);

/// Listing Approvals: Pending first, then Approved, Disapproved last. A Sold
/// Out listing was approved, so it sits with the Approved ones.
int approvalGroup(AdminListingModel listing) {
  if (listing.isPending) return 0;
  if (listing.isRejected) return 2;
  return 1; // approved, or sold (approved earlier)
}

/// Pending ones first, and among them the OLDEST first (first in, first out: what has waited
/// longest is decided first); then Approved and Disapproved, newest first as they arrive.
List<AdminListingModel> orderForApprovals(
  Iterable<AdminListingModel> listings,
) {
  final grouped = stableGroupSort(listings, approvalGroup);
  final firstDecided = grouped.indexWhere((l) => approvalGroup(l) != 0);
  final end = firstDecided < 0 ? grouped.length : firstDecided;
  return [
    ...oldestFirst(grouped.sublist(0, end), (l) => l.createdAt),
    ...grouped.sublist(end),
  ];
}

/// Farmer > Listing: listings that are still live (Pending Approval and
/// Available) come first; Sold Out, Disapproved and Withdrawn go to the bottom.
/// The newest-first order is kept inside each group.
int farmerListingGroup(MarketplaceListingModel listing) =>
    (listing.isSoldOut || listing.isRejected || listing.isWithdrawn) ? 1 : 0;

List<MarketplaceListingModel> orderForFarmerListings(
  Iterable<MarketplaceListingModel> listings,
) => stableGroupSort(listings, farmerListingGroup);
