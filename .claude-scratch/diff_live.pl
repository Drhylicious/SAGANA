use strict;
use warnings;

my $csv = 'C:/Users/Administrator/sagana/supabase_schema/Supabase Snippet Untitled query.csv';
my $in;
open($in, '<:encoding(UTF-8)', $csv) or die "csv: $!";
my $text = do { local $/; <$in> };
close($in);
$text =~ s/\r\n/\n/g;
$text =~ s/^proname,definition\n//;

my %live;
while ($text =~ /\G([a-z_0-9]+),"((?:[^"]|"")*)"\n?/gc) {
    my ($name, $def) = ($1, $2);
    $def =~ s/""/"/g;
    $live{$name} = $def;
}
print "parsed " . scalar(keys %live) . " live functions\n";

my @targets = qw(approve_member distribute_program_benefit notify_upcoming_loan_payments notify_user process_scheduled_broadcasts reject_member);

my $dir = 'C:/Users/Administrator/sagana/supabase_schema';
opendir(my $dh, $dir) or die "dir: $!";
my @files = sort grep { /\.sql$/i } readdir($dh);
closedir($dh);

sub body_of {
    my ($s) = @_;
    my ($b) = $s =~ /(AS \$function\$.*?\$function\$)/s;
    return defined $b ? $b : '';
}

for my $name (@targets) {
    my $live_body = body_of($live{$name});
    my %live_lines = map { my $l = $_; $l =~ s/^\s+|\s+$//g; ($l => 1) } grep { /\S/ } split /\n/, $live_body;

    # Closest migration: the file whose version of this function shares the most lines with the live body.
    my ($best_file, $best_score, $best_body) = ('', -1, '');
    for my $f (@files) {
        my $fh;
        open($fh, '<:encoding(UTF-8)', "$dir/$f") or next;
        my $t = do { local $/; <$fh> };
        close($fh);
        $t =~ s/\r\n/\n/g;
        while ($t =~ /(CREATE (?:OR REPLACE )?FUNCTION (?:public\.)?$name\b.*?\$function\$;?)/gis) {
            my $cand = $1;
            my $body = body_of($cand);
            my %cl = map { my $l = $_; $l =~ s/^\s+|\s+$//g; ($l => 1) } grep { /\S/ } split /\n/, $body;
            my $score = grep { $cl{$_} } keys %live_lines;
            my $total = scalar keys %live_lines;
            if ($score > $best_score) {
                ($best_file, $best_score, $best_body) = ($f, $score, $body);
            }
        }
    }
    my %best_lines = map { my $l = $_; $l =~ s/^\s+|\s+$//g; ($l => 1) } grep { /\S/ } split /\n/, $best_body;
    my @only_live = grep { !$best_lines{$_} } sort keys %live_lines;
    my @only_file = grep { !$live_lines{$_} } sort keys %best_lines;
    print "\n=== $name  (closest: $best_file)\n";
    print "  live-only lines (" . scalar(@only_live) . "):\n";
    print "    $_\n" for @only_live[0 .. ($#only_live > 9 ? 9 : $#only_live)];
    print "  file-only lines (" . scalar(@only_file) . "):\n";
    print "    $_\n" for @only_file[0 .. ($#only_file > 9 ? 9 : $#only_file)];
}
