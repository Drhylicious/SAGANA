use strict;
use warnings;

my $file = 'lib/presentation/widgets/admin_bottom_nav.dart';
my $in;
open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
my $t = do { local $/; <$in> };
close($in);
my $crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;

my @swaps = (
  [ "                        padding: const EdgeInsets.symmetric(vertical: 6),\n",
    "                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),\n" ],
  [ "                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
",
    "                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                ),
                              ),
" ],
);
for my $s (@swaps) {
    my ($from, $to) = @$s;
    my $n = () = $t =~ /\Q$from\E/g;
    die "expected 1 match, got $n for: " . substr($from, 0, 60) . "\n" unless $n == 1;
    $t =~ s/\Q$from\E/$to/;
}
$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $t;
close($out);
print "applied nav label changes\n";
