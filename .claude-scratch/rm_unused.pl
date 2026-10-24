use strict;
use warnings;

# Reads analyzer output on STDIN and removes flagged unused locals and imports
# when the flagged line is a single-line declaration or import.
my %hits;
while (my $line = <STDIN>) {
    next unless $line =~ /^\s*warning - .*(unused_local_variable|unused_import)/;
    next unless $line =~ /(lib\\\S+?\.dart):(\d+):\d+ - /;
    my $file = $1;
    my $ln = $2;
    $file =~ s{\\}{/}g;
    push @{ $hits{$file} }, $ln;
}

for my $file (sort(keys(%hits))) {
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my @lines = <$in>;
    close($in);

    my $removed = 0;
    for my $ln (sort { $b <=> $a } @{ $hits{$file} }) {
        my $t = $lines[$ln - 1];
        if ($t =~ /^\s*(final|var|const)\s+\w+\s*=.*;\s*$/ || $t =~ /^\s*import\s+'[^']+';\s*$/) {
            splice(@lines, $ln - 1, 1);
            $removed++;
        } else {
            print "manual: $file:$ln: $t";
        }
    }

    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} @lines;
    close($out);
    print "$file: removed $removed\n";
}
