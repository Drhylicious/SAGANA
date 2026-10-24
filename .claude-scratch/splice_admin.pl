use strict;
use warnings;

my $file = 'C:/Users/Administrator/sagana/lib/presentation/screens/admin/admin_activity_screen.dart';
my $fh;
open($fh, '<:encoding(UTF-8)', $file) or die "$file: $!";
my $text = do { local $/; <$fh> };
close($fh);

my $crlf = ($text =~ /\r\n/) ? 1 : 0;
$text =~ s/\r\n/\n/g;

my $marker = "  \@override\n  Widget build(BuildContext context) {\n";
my $at = rindex($text, $marker);
die "build marker not found" if $at < 0;

my $build_fh;
my $build_file = 'C:/Users/Administrator/sagana/.claude-scratch/admin_build.txt';
open($build_fh, '<:encoding(UTF-8)', $build_file) or die "$build_file: $!";
my $build = do { local $/; <$build_fh> };
close($build_fh);

$text = substr($text, 0, $at) . $build;

unless ($text =~ m{recent_activity_widgets\.dart}) {
    my $pos = 0;
    while ($text =~ /^import [^\n]*;\n/mg) { $pos = pos($text); }
    substr($text, $pos, 0, "import '../../widgets/recent_activity_widgets.dart';\n");
}

$text =~ s/\n/\r\n/g if $crlf;

my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $text;
close($out);
print "spliced admin build (crlf=$crlf)\n";
