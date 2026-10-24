use strict;
use warnings;

my %hits;
my $report;
open($report, '<', '.claude-scratch/an2.txt') or die "report: $!";
while (my $line = <$report>) {
    next unless $line =~ /prefer_const_constructors/;
    next unless $line =~ /(lib\\\S+?\.dart):(\d+):(\d+)/;
    my $file = $1;
    my $ln = $2;
    my $col = $3;
    $file =~ s{\\}{/}g;
    push @{ $hits{$file} }, [ $ln, $col ];
}
close($report);

for my $file (sort(keys(%hits))) {
    my $fh;
    open($fh, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my @lines = <$fh>;
    close($fh);

    my $changed = 0;
    for my $hit (sort { $b->[0] <=> $a->[0] || $b->[1] <=> $a->[1] } @{ $hits{$file} }) {
        my ($ln, $col) = @{$hit};
        my $t = $lines[$ln - 1];
        next unless substr($t, $col - 1, 16) eq 'AdminLogMessage(';
        substr($t, $col - 1, 0) = 'const ';
        $lines[$ln - 1] = $t;
        $changed++;
    }

    if ($changed) {
        my $out;
        open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
        print {$out} @lines;
        close($out);
        print "$file: $changed\n";
    }
}
