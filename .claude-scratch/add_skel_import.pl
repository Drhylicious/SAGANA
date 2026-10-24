use strict; use warnings;
my $imp = shift @ARGV;
for my $f (@ARGV) {
    local $/;
    open my $fh, '<:encoding(UTF-8)', $f or die "$f: $!"; my $s = <$fh>; close $fh;
    next if $s =~ m{skeleton\.dart};
    my $nl = ($s =~ /\r\n/) ? "\r\n" : "\n";
    my $pos = 0;
    while ($s =~ /^import [^\n]*;\r?\n/mg) { $pos = pos($s); }
    substr($s, $pos, 0, "import '$imp';$nl");
    open my $out, '>:encoding(UTF-8)', $f or die; print $out $s; close $out;
    print "added to $f\n";
}
