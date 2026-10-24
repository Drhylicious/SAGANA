use strict;
use warnings;

# Parse the Supabase CSV export (proname,definition with quoted multi-line fields).
my $csv = 'C:/Users/Administrator/sagana/supabase_schema/Supabase Snippet Untitled query.csv';
my $in;
open($in, '<:encoding(UTF-8)', $csv) or die "csv: $!";
my $text = do { local $/; <$in> };
close($in);
$text =~ s/\r\n/\n/g;
$text =~ s/^proname,definition\n//;

my @fns;
while ($text =~ /\G([a-z_0-9]+),"((?:[^"]|"")*)"\n?/gc) {
    my ($name, $def) = ($1, $2);
    $def =~ s/""/"/g;
    push @fns, [$name, $def];
}
print "parsed " . scalar(@fns) . " live functions\n";

sub norm {
    my ($s) = @_;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    return lc $s;
}

# Load every migration file, normalized.
my $dir = 'C:/Users/Administrator/sagana/supabase_schema';
opendir(my $dh, $dir) or die "dir: $!";
my @files = sort grep { /\.sql$/i } readdir($dh);
closedir($dh);
my %content;
for my $f (@files) {
    my $fh;
    open($fh, '<:encoding(UTF-8)', "$dir/$f") or next;
    my $t = do { local $/; <$fh> };
    close($fh);
    $t =~ s{\$\$}{\$function\$}g;
    $content{$f} = norm($t);
}

my ($exact, $none) = (0, 0);
for my $fn (@fns) {
    my ($name, $def) = @$fn;
    my $body = norm($def);
    # Strip the CREATE header so differing comments/defaults in the signature don't block the match.
    my ($core) = $body =~ /(as \$function\$.*)/;
    $core //= $body;
    my @hits = grep { index($content{$_}, $core) >= 0 } keys %content;
    my $inserts = () = $body =~ /insert into notifications/g;
    if (@hits) {
        $exact++;
        printf "%-45s inserts=%d  matches: %s\n", $name, $inserts, join(', ', sort @hits);
    } else {
        $none++;
        printf "%-45s inserts=%d  NO MATCHING MIGRATION\n", $name, $inserts;
    }
}
print "\nexact matches: $exact, no match: $none\n";
