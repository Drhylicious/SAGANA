use strict;
use warnings;

my @keys = (
  [ 'marketLinkCelebrationTitle', 'Congratulations!', 'Maligayang bati!' ],
  [ 'marketLinkCelebrationBody',
    'Your enrollment in the DA-AMAD Ginger Market Linking program has been approved. You may now submit your Ginger harvest for sale through Market Linking.',
    'Naaprubahan ang iyong enrollment sa DA-AMAD Ginger Market Linking program. Maaari ka nang magsumite ng iyong ani ng luya para ibenta sa pamamagitan ng Market Linking.' ],
  [ 'marketLinkCelebrationContinue', 'Continue', 'Magpatuloy' ],
);

sub json_str {
    my ($s) = @_;
    $s =~ s/\\/\\\\/g;
    $s =~ s/\x22/\\\x22/g;
    return "\x22$s\x22";
}

for my $pair ([ 'app_en.arb', 1 ], [ 'app_tl.arb', 2 ]) {
    my $file = 'lib/core/l10n/' . $pair->[0];
    my $idx = $pair->[1];
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $t = do { local $/; <$in> };
    close($in);
    $t =~ s/\r\n/\n/g;
    $t =~ s/\s*\}\s*\z//;
    my @lines = map { '  ' . json_str($_->[0]) . ': ' . json_str($_->[$idx]) } @keys;
    $t .= ",\n" . join(",\n", @lines) . "\n}\n";
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $t;
    close($out);
    print "appended to $file\n";
}
