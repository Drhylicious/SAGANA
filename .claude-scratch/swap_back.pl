use strict;
use warnings;

my $re = qr/IconButton\(\s*icon: (?:const )?Icon\(\s*Icons\.arrow_back_rounded,?\s*(?:color: [^,)\n]+,?\s*)?(?:size: \d+,?\s*)?\),\s*onPressed: ([^,\n]+?),\s*((?:tooltip: [^\n]+?,\s*)?)\)/;

for my $file (@ARGV) {
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $text = do { local $/; <$in> };
    close($in);

    my $count = ($text =~ s/$re/SubPageBackButton(onPressed: $1, $2)/g);
    next unless $count;

    unless ($text =~ m{sub_page_top_bar\.dart}) {
        my $nl = ($text =~ /\r\n/) ? "\r\n" : "\n";
        my $pos = 0;
        while ($text =~ /^import [^\n]*;\r?\n/mg) { $pos = pos($text); }
        substr($text, $pos, 0, "import '../../widgets/sub_page_top_bar.dart';$nl");
    }

    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $text;
    close($out);
    print "$file: $count\n";
}
