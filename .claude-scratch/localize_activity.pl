use strict;
use warnings;

my $defs = 'C:/Users/Administrator/sagana/.claude-scratch/activity_keys.txt';
my $l10n = 'C:/Users/Administrator/sagana/lib/core/l10n/';

open(my $fh, '<:encoding(UTF-8)', $defs) or die "defs: $!";
my @rows;
while (my $line = <$fh>) {
    chomp $line;
    $line =~ s/\r$//;
    next unless length $line;
    my ($key, $params, $en, $tl) = split(/\|/, $line, 4);
    my @names = grep { length } split(/,/, $params // '');
    push @rows, { key => $key, params => \@names, en => $en, tl => $tl };
}
close($fh);

sub json_str {
    my ($s) = @_;
    $s =~ s/\\/\\\\/g;
    $s =~ s/"/\\"/g;
    return "\"$s\"";
}

sub arb_block {
    my ($lang) = @_;
    my @out;
    for my $r (@rows) {
        push @out, '  ' . json_str($r->{key}) . ': ' . json_str($r->{$lang});
        if (@{ $r->{params} }) {
            my @ph = map { '"' . $_ . '": {"type": "String"}' } @{ $r->{params} };
            push @out, '  ' . json_str('@' . $r->{key}) . ': {"placeholders": {' . join(', ', @ph) . '}}';
        }
    }
    return join(",\n", @out);
}

for my $pair (['app_en.arb', 'en'], ['app_tl.arb', 'tl']) {
    my $file = $l10n . $pair->[0];
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $text = do { local $/; <$in> };
    close($in);
    $text =~ s/\s*\}\s*\z//;
    $text .= ",\n" . arb_block($pair->[1]) . "\n}\n";
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $text;
    close($out);
    print "appended " . scalar(@rows) . " keys to $pair->[0]\n";
}

# Literal -> localized getter. Each entry: exact quoted literal, replacement.
my @swaps = (
    [ q{'$cropName Harvest'}, q{_l.activityHarvestTitle(cropName)} ],
    [ q{'$cropName Listing Submitted'}, q{_l.activityListingSubmittedTitle(cropName)} ],
    [ q{'$cropName Listing Withdrawn'}, q{_l.activityListingWithdrawnTitle(cropName)} ],
    [ q{'Pending Sync'}, q{_l.activityPendingSync} ],
    [ q{'Synced'}, q{_l.activitySynced} ],
    [ q{'Pending Review'}, q{_l.activityPendingReview} ],
    [ q{'Withdrawn'}, q{_l.activityWithdrawn} ],
    [ q{'Placed an Order'}, q{_l.activityOrderPlacedTitle} ],
    [ q{'Crop Request Submitted'}, q{_l.activityCropRequestSubmitted} ],
    [ q{'Crop Added'}, q{_l.activityCropAdded} ],
    [ q{'Added'}, q{_l.activityAdded} ],
    [ q{'Informal Sale'}, q{_l.activityInformalSaleTitle} ],
    [ q{'Crop Roster'}, q{_l.activityCropRoster} ],
    [ q{'Updated'}, q{_l.activityUpdated} ],
    [ q{'Offered to Cooperative'}, q{_l.activityOfferedToCoop} ],
    [ q{'Submitted Market Linking Enrollment'}, q{_l.activityMarketLinkingSubmitted} ],
    [ q{'Ginger Market Linking (DA-AMAD)'}, q{_l.activityGingerMarketLinking} ],
    [ q{'Submitted Ginger Batch for Sale'}, q{_l.activityGingerBatchSubmitted} ],
    [ q{'Market Linking'}, q{_l.activityMarketLinking} ],
    [ q{'Account'}, q{_l.activityAccount} ],
    [ q{'Address'}, q{_l.activityAddress} ],
    [ q{'Expense Added'}, q{_l.activityExpenseAdded} ],
    [ q{'Requested Program Enrollment'}, q{_l.activityProgramEnrollmentRequested} ],
    [ q{'Requested Program Purchase'}, q{_l.activityProgramPurchaseRequested} ],
    [ q{'My Contribution'}, q{_l.activityMyContribution} ],
    [ q{'Added to Capital Share'}, q{_l.activityCapitalAdded} ],
    [ q{'Synced offline records'}, q{_l.activitySyncedOfflineRecords} ],
    [ q{'Home'}, q{_l.activityHome} ],
    [ q{'Pending'}, q{_l.activityPending} ],
    [ q{'Order Placed'}, q{_l.activityOrderPlaced} ],
    [ q{'Placed'}, q{_l.activityPlaced} ],
);

my $repo = 'C:/Users/Administrator/sagana/lib/data/repositories/';
for my $name ('dashboard_repository.dart', 'buyer_order_repository.dart') {
    my $file = $repo . $name;
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $text = do { local $/; <$in> };
    close($in);

    my $total = 0;
    for my $s (@swaps) {
        my ($from, $to) = @$s;
        my $count = 0;
        # Literal match, but only where the text is a whole Dart string literal.
        $count = ($text =~ s/\Q$from\E/$to/g);
        $total += $count;
    }

    my $uses = $text =~ /_l\./ ? 1 : 0;
    if ($uses && $text !~ /AppLocalizations get _l/) {
        my $imports = "import '../../core/l10n/app_localizations.dart';\nimport '../services/app_settings_service.dart';\n";
        my $pos = 0;
        while ($text =~ /^import [^\n]*;\r?\n/mg) { $pos = pos($text); }
        substr($text, $pos, 0, $imports);
        $text =~ s/(\n(?:[^\n]*\n)*?)\z/$1/;
        my $getter = "\n/// Localized labels for activity entries. Repositories have no BuildContext,\n/// so they resolve the user's current locale directly.\nAppLocalizations get _l => lookupAppLocalizations(AppSettingsService.instance.locale);\n";
        my $imp_end = 0;
        while ($text =~ /^import [^\n]*;\r?\n/mg) { $imp_end = pos($text); }
        substr($text, $imp_end, 0, $getter);
    }

    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $text;
    close($out);
    print "$name: $total replacements\n";
}
