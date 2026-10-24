use strict;
use warnings;
my $re = qr/(?:const )?Center\(\s*child: (?:const )?CircularProgressIndicator\((?!\s*(?:color: Colors\.white|strokeWidth))(?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)\s*,?\s*\)/;
for my $f (@ARGV) {
    local $/;
    open my $fh, '<:encoding(UTF-8)', $f or die "$f: $!";
    my $s = <$fh>;
    close $fh;
    my $n = ($s =~ s/$re/const Padding(padding: EdgeInsets.all(16), child: SkeletonList())/g);
    next unless $n;
    my $imp = ($f =~ m{[\/]widgets[\/]}) ? 'skeleton.dart' : '../../widgets/skeleton.dart';
    unless ($s =~ m{skeleton\.dart}) {
        my $nl = ($s =~ /\r\n/) ? "\r\n" : "\n";
        my $pos = 0;
        while ($s =~ /^import [^\n]*;\r?\n/mg) { $pos = pos($s); }
        substr($s, $pos, 0, "import '$imp';$nl");
    }
    open my $out, '>:encoding(UTF-8)', $f or die "$f: $!";
    print $out $s;
    close $out;
    print "$f: $n\n";
}
