use strict;
use warnings;

my $file = q{C:/Users/Administrator/sagana/lib/presentation/screens/farmer/farmer_recent_activity_screen.dart};
my $fh;
open($fh, '<:encoding(UTF-8)', $file) or die "$file: $!";
my @lines = <$fh>;
s/\r$// for @lines;
s/$// for @lines;
close($fh);

# Drop the private card/search/chip/group/empty widgets (search bar through
# the empty state). _chipLabel stays.
my ($start, $end);
for my $i (0 .. $#lines) {
    $start = $i if !defined $start && $lines[$i] =~ /^\/\/ Search Bar$/;
    $end = $i if $lines[$i] =~ /^String _chipLabel\(/;
}
die "markers not found" unless defined $start && defined $end;
# $start points at the "Search Bar" title; step back to its ─── rule line.
$start--;
splice(@lines, $start, $end - $start);

my $text = join('', @lines);
$text =~ s{
}{
}g;

my @subs = (
    [ q{                                    _SearchBar(controller: _searchController),}, q{                                    RecentActivitySearchBar(
                                      controller: _searchController,
                                      hint: AppLocalizations.of(context).activitySearchHint,
                                    ),} ],
    [ q{                                    _FilterChips(
                                      active: _activeFilter,
                                      onSelected: _setFilter,
                                    ),}, q{                                    RecentActivityFilterChips<ActivityFilter>(
                                      options: _filterOptions(context),
                                      active: _activeFilter,
                                      onSelected: _setFilter,
                                    ),} ],
    [ q{                                child: _EmptyState(
                                  hasSearch:
                                      _searchQuery.isNotEmpty ||
                                      _activeFilter != ActivityFilter.all,
                                ),}, q{                                child: recentActivityEmptyState(
                                  context,
                                  hasSearch:
                                      _searchQuery.isNotEmpty ||
                                      _activeFilter != ActivityFilter.all,
                                ),} ],
    [ q{                                    return _DateGroup(
                                      label: label,
                                      items: group,
                                    );}, q{                                    return RecentActivityDateGroup(
                                      label: label,
                                      cards: [
                                        for (final item in group)
                                          _farmerActivityCard(context, item),
                                      ],
                                    );} ],
);

for my $s (@subs) {
    my ($from, $to) = @$s;
    my $from_text = $from;
    $from_text =~ s/\n/\n/g;
    my $to_text = $to;
    $to_text =~ s/\n/\n/g;
    my $n = () = $text =~ /\Q$from_text\E/g;
    die "no match for: " . substr($from_text, 0, 60) . "\n" if $n == 0;
    $text =~ s/\Q$from_text\E/$to_text/;
}

my $helpers = <<'HELPERS';

List<RecentActivityFilterOption<ActivityFilter>> _filterOptions(
  BuildContext context,
) => [
  for (final filter in ActivityFilter.values)
    RecentActivityFilterOption(value: filter, label: _chipLabel(context, filter)),
];

RecentActivityCard _farmerActivityCard(BuildContext context, ActivityItem item) {
  final l10n = AppLocalizations.of(context);
  final (icon, tone) = _farmerActivityIcon(item);
  return RecentActivityCard(
    icon: icon,
    iconTone: tone,
    title: item.title,
    subtitle: item.subtitle,
    timestamp: item.timestamp,
    valueLabel: item.valueLabel,
    statusLabel: item.statusLabel,
    statusTone: _farmerStatusTone(l10n, item),
    isAlert: item.isAlert,
  );
}

(IconData, RecentActivityIconTone) _farmerActivityIcon(ActivityItem item) =>
    switch (item.type) {
      ActivityType.harvest => (Icons.agriculture_rounded, RecentActivityIconTone.primary),
      ActivityType.listing => (Icons.verified_outlined, RecentActivityIconTone.primary),
      ActivityType.orderPlaced => (Icons.shopping_cart_outlined, RecentActivityIconTone.accent),
      ActivityType.cropRequest => (
          Icons.local_florist_outlined,
          item.isAlert ? RecentActivityIconTone.alert : RecentActivityIconTone.primary,
        ),
      ActivityType.cropAdded => (Icons.grass_rounded, RecentActivityIconTone.primary),
      ActivityType.informalSale => (Icons.sell_outlined, RecentActivityIconTone.accent),
      ActivityType.cropPhotoUpdated => (Icons.photo_camera_outlined, RecentActivityIconTone.primary),
      ActivityType.cooperativeOffer => (Icons.groups_outlined, RecentActivityIconTone.accent),
      ActivityType.marketLinkingEnrollment => (Icons.handshake_outlined, RecentActivityIconTone.primary),
      ActivityType.gingerBatchSubmission => (Icons.outbox_outlined, RecentActivityIconTone.accent),
      ActivityType.profile => (Icons.person_outline_rounded, RecentActivityIconTone.neutral),
      ActivityType.addressUpdated => (Icons.location_on_outlined, RecentActivityIconTone.neutral),
      ActivityType.expenseAdded => (Icons.receipt_long_outlined, RecentActivityIconTone.neutral),
      ActivityType.programEnrollment => (Icons.assignment_turned_in_outlined, RecentActivityIconTone.primary),
      ActivityType.programPurchase => (Icons.shopping_bag_outlined, RecentActivityIconTone.accent),
      ActivityType.capitalReinvestment => (Icons.savings_outlined, RecentActivityIconTone.primary),
      ActivityType.syncCompleted => (Icons.sync_rounded, RecentActivityIconTone.neutral),
    };

// Status colour is decided from the status kind, not the label text, so it
// stays correct when the labels are translated.
RecentActivityTone _farmerStatusTone(AppLocalizations l10n, ActivityItem item) {
  if (item.isAlert) return RecentActivityTone.alert;
  final label = item.statusLabel;
  if (label == null) return RecentActivityTone.neutral;
  if (label == l10n.activityPendingSync ||
      label == l10n.activityPendingReview ||
      label == l10n.activityPending) {
    return RecentActivityTone.warning;
  }
  if (label == l10n.activitySynced) return RecentActivityTone.success;
  return RecentActivityTone.neutral;
}
HELPERS

$text =~ s/\s*\z/\n/;
$text .= $helpers;

# Shared imports replace the old private-widget dependencies.
my $imports = "import '../../widgets/recent_activity_widgets.dart';\n";
$text =~ s/(import '\.\.\/\.\.\/widgets\/skeleton\.dart';\n)/$1$imports/ or die "skeleton import not found";

my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $text;
close($out);
print "refactored $file\n";
