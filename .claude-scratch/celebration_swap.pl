use strict;
use warnings;

my $file = 'lib/presentation/screens/farmer/my_market_linking_screen.dart';
my $in;
open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
my $t = do { local $/; <$in> };
close($in);
my $crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;

my @swaps = (
  [ "'Congratulations!',", "AppLocalizations.of(context).marketLinkCelebrationTitle," ],
  [ "'Your enrollment in the DA-AMAD Ginger Market Linking program has been approved. '\n                'You may now submit your Ginger harvest for sale through Market Linking.',",
    "AppLocalizations.of(context).marketLinkCelebrationBody," ],
  [ "'Continue',", "AppLocalizations.of(context).marketLinkCelebrationContinue," ],
);
for my $s (@swaps) {
    my ($from, $to) = @$s;
    my $n = () = $t =~ /\Q$from\E/g;
    die "expected 1 match, got $n for: $from\n" unless $n == 1;
    $t =~ s/\Q$from\E/$to/;
}
$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $t;
close($out);
print "swapped celebration strings\n";
