use strict;
use warnings;

my %hits;
while (my $line = <STDIN>) {
    next unless $line =~ /(lib\\S+?\.dart):(\d+):(\d+) - unnecessary_const/;
    my $file = $1;
    my $ln = $2;
    my $col = $3;
    $file =~ s{\}{/}g;
    push @{ $hits{$file} }, [ $ln, $col ];
}

for my $file (sort(keys(%hits))) {
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $text = do { local $/; <$in> };
    close($in);

    my @lines = split(/(?<=\n)/, $text);
    my @sorted = sort { $b->[0] <=> $a->[0] || $b->[1] <=> $a->[1] } @{ $hits{$file} };
    for my $hit (@sorted) {
        my ($ln, $col) = @{$hit};
        my $t = $lines[$ln - 1];
        if (substr($t, $col - 1, 6) eq 'const ') {
            substr($t, $col - 1, 6) = '';
            $lines[$ln - 1] = $t;
            print "fixed $file:$ln\n";
        } else {
            print "skip $file:$ln:$col\n";
        }
    }

    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} join('', @lines);
    close($out);
}
