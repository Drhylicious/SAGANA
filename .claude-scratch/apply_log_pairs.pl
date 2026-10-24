use strict;
use warnings;

my $pairs = 'C:/Users/Administrator/sagana/.claude-scratch/log_call_pairs.txt';
my $root = 'C:/Users/Administrator/sagana/lib/';

open(my $ph, '<:encoding(UTF-8)', $pairs) or die "pairs: $!";
my @blocks;
my $cur;
my $mode = '';
while (my $line = <$ph>) {
    $line =~ s/\r?\n\z//;
    if ($line =~ /^@@@ (.+)$/) {
        $cur = { file => $1, old => [], new => [] };
        push @blocks, $cur;
        $mode = 'old';
        next;
    }
    if ($line eq '-->') { $mode = 'new'; next; }
    if ($mode eq 'old') { push @{ $cur->{old} }, $line; }
    elsif ($mode eq 'new') { push @{ $cur->{new} }, $line; }
}
close($ph);

my %text;
my $failures = 0;
my $applied = 0;

for my $b (@blocks) {
    my $file = $root . $b->{file};
    $text{$file} //= do {
        open(my $in, '<:encoding(UTF-8)', $file) or die "$file: $!";
        local $/;
        my $t = <$in>;
        close($in);
        $t;
    };

    my $old = join(' ', @{ $b->{old} });
    my $new = join("\n", @{ $b->{new} });
    my @tokens = grep { length } split(/\s+/, $old);
    my $re = join('\s*', map { quotemeta($_) } @tokens);

    my $n = () = $text{$file} =~ /$re/g;
    if ($n != 1) {
        print "MATCH COUNT $n for [$b->{file}] $old\n";
        $failures++;
        next;
    }
    $text{$file} =~ s/$re/$new/;
    $applied++;
}

for my $file (sort keys %text) {
    my $t = $text{$file};
    if ($t !~ m{admin_log_message\.dart}) {
        my $rel = ($file =~ m{/data/repositories/}) ? '../models/admin_log_message.dart' : '../../../data/models/admin_log_message.dart';
        my $pos = 0;
        while ($t =~ /^import [^\n]*;\r?\n/mg) { $pos = pos($t); }
        substr($t, $pos, 0, "import '$rel';\n");
    }
    open(my $out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $t;
    close($out);
}

print "applied $applied of " . scalar(@blocks) . " blocks; failures $failures\n";
