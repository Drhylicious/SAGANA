import '../../data/repositories/admin_listing_repository.dart';

/// Display order for the Manager's listing screens. Both keep the order the
/// listings arrive in (newest first) within each group and only move whole
/// groups, so a filter or a search never changes how listings compare.
///
/// Dart's [List.sort] is not stable (equal items may swap), so this sorts by
/// (group, original position) instead.
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

List<AdminListingModel> orderForAllListings(Iterable<AdminListingModel> listings) =>
    stableGroupSort(listings, allListingsGroup);

/// Listing Approvals: Pending first, then Approved, Disapproved last. A Sold
/// Out listing was approved, so it sits with the Approved ones.
int approvalGroup(AdminListingModel listing) {
  if (listing.isPending) return 0;
  if (listing.isRejected) return 2;
  return 1; // approved, or sold (approved earlier)
}

List<AdminListingModel> orderForApprovals(Iterable<AdminListingModel> listings) =>
    stableGroupSort(listings, approvalGroup);
