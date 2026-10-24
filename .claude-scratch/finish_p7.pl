use strict;
use warnings;

my $edit = 'lib/presentation/screens/farmer/farmer_edit_profile_screen.dart';
my $in;
open($in, '<:encoding(UTF-8)', $edit) or die "$edit: $!";
my $t = do { local $/; <$in> };
close($in);
my $crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;

my $from = qr/child: AppBar\(\n.*?\n          \),\n          \/\/ Matches FarmerTopBar's own divider.*?Container\(height: 1, color: cs\.outline\.withValues\(alpha: 0\.20\)\),\n/s;
my $n = () = $t =~ /$from/g;
die "farmer header block not found ($n)\n" unless $n == 1;
my $repl = <<'REPL';
child: SubPageTopBar(
              title: l10n.editProfile,
              onBack: () => context.pop(),
              trailing: TextButton(
                onPressed: _isSaving ? null : _save,
                child: Text(
                  l10n.save,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.primaryGreen,
                  ),
                ),
              ),
            ),
          ),
REPL
$t =~ s/$from/$repl/;
unless ($t =~ m{sub_page_top_bar\.dart}) {
    my $pos = 0;
    while ($t =~ /^import [^\n]*;\n/mg) { $pos = pos($t); }
    substr($t, $pos, 0, "import '../../widgets/sub_page_top_bar.dart';\n");
}
$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $edit) or die "$edit: $!";
print {$out} $t;
close($out);
print "farmer edit profile header replaced\n";

my $buyer = 'lib/presentation/screens/buyer/listing_details_screen.dart';
open($in, '<:encoding(UTF-8)', $buyer) or die "$buyer: $!";
$t = do { local $/; <$in> };
close($in);
$crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;
my $bn = () = $t =~ /_CircleIconButton\(\s*icon: Icons\.arrow_back_rounded,\s*onTap: \(\) => context\.pop\(\),\s*\)/g;
die "buyer back button not found ($bn)\n" unless $bn == 1;
$t =~ s/_CircleIconButton\(\s*icon: Icons\.arrow_back_rounded,\s*onTap: \(\) => context\.pop\(\),\s*\)/SubPageBackButton(onPressed: () => context.pop())/;
unless ($t =~ m{sub_page_top_bar\.dart}) {
    my $pos = 0;
    while ($t =~ /^import [^\n]*;\n/mg) { $pos = pos($t); }
    substr($t, $pos, 0, "import '../../widgets/sub_page_top_bar.dart';\n");
}
$t =~ s/\n/\r\n/g if $crlf;
open($out, '>:encoding(UTF-8)', $buyer) or die "$buyer: $!";
print {$out} $t;
close($out);
print "listing details back button replaced\n";
