use strict;
use warnings;

my $file = 'lib/presentation/screens/farmer/listing_success_screen.dart';
my $in;
open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
my $t = do { local $/; <$in> };
close($in);
my $crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;

my $loading_from = "      return Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 72),
                const Expanded(
                  child: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
                ),
              ],
            ),
            Positioned(
              top: 0, left: 0, right: 0,
              child: FarmerTopBar(
                title: 'Submission Success',
                profilePhotoUrl: null,
                hideProfileAvatar: true,
                onProfileTap: () {},
                onNotificationTap: () {},
                showNotificationButton: false,
                onSettingsTap: null,
              ),
            ),
          ],
        ),
      );
";
my $loading_to = "      return const Scaffold(
        body: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
      );
";
my $n1 = () = $t =~ /\Q$loading_from\E/g;
die "loading block: $n1\n" unless $n1 == 1;
$t =~ s/\Q$loading_from\E/$loading_to/;

my $header = "          Positioned(top: 0, left: 0, right: 0, child: FarmerTopBar(title: 'Submission Success', profilePhotoUrl: null, hideProfileAvatar: true, onProfileTap: () {}, onNotificationTap: () {}, showNotificationButton: false, onSettingsTap: null,)),\n";
my $n2 = () = $t =~ /\Q$header\E/g;
die "header line: $n2\n" unless $n2 == 1;
$t =~ s/\Q$header\E//;

my $offset = "              const SizedBox(height: 64),\n";
my $n3 = () = $t =~ /\Q$offset\E/g;
die "offset: $n3\n" unless $n3 == 1;
$t =~ s/\Q$offset\E/              SizedBox(height: MediaQuery.of(context).padding.top + 24),\n/;

$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $t;
close($out);
print "listing success is now standalone\n";
