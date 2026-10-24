use utf8;
use strict;
use warnings;

sub edit {
    my ($file, $pairs) = @_;
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $t = do { local $/; <$in> };
    close($in);
    my $crlf = $t =~ /\r\n/ ? 1 : 0;
    $t =~ s/\r\n/\n/g;
    for my $p (@$pairs) {
        my ($from, $to, $is_regex) = @$p;
        my $re = $is_regex ? $from : qr/\Q$from\E/s;
        my $n = () = $t =~ /$re/g;
        die "$file: expected 1 match, got $n for: " . substr("$from", 0, 70) . "\n" unless $n == 1;
        $t =~ s/$re/$to/;
    }
    $t =~ s/\n/\r\n/g if $crlf;
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $t;
    close($out);
    print "edited $file\n";
}

# 1. SyncService: no timer, no reconnect trigger, no start/stop. syncPending() stays.
edit('lib/data/services/sync_service.dart', [
    [ qr/  \/\/ ─── Start Auto Sync .*?(?=  \/\/ ─── Sync Pending Records)/s, '', 1 ],
    [ "  static Timer? _syncTimer;\n", '', 0 ],
    [ "  static const Duration _syncInterval = Duration(minutes: 5);\n", '', 0 ],
]);

# 2. main.dart: no automatic sync at launch.
edit('lib/main.dart', [
    [ "  SyncService.startAutoSync();\n", '', 0 ],
    [ "import 'data/services/sync_service.dart';\n", '', 0 ],
]);

# 3. Logout: no sync timer to stop.
edit('lib/data/services/auth_service.dart', [
    [ qr/    \/\/ Stop the periodic sync timer before signing out.*?    SyncService\.stopAutoSync\(\);\n/s, '', 1 ],
    [ "import 'sync_service.dart';\n", '', 0 ],
]);

# 4. Settings model: remove the background-sync preference.
edit('lib/data/repositories/settings_repository.dart', [
    [ "  final bool backgroundSync;\n", '', 0 ],
    [ "    required this.backgroundSync,\n", '', 0 ],
    [ "    backgroundSync: true,\n", '', 0 ],
    [ "    bool? backgroundSync,\n", '', 0 ],
    [ "      backgroundSync: backgroundSync ?? this.backgroundSync,\n", '', 0 ],
    [ "  // backgroundSync intentionally NOT scoped here — see savePref() below.\n", '', 0 ],
    [ qr/      \/\/ Delegates to HiveService rather than re-reading.*?      backgroundSync: HiveService\.getBackgroundSync\(userId: userId\),\n/s, '', 1 ],
    [ qr/  \/\/ Dedicated, per-user-scoped write for Background Sync.*?    await HiveService\.setBackgroundSync\(value, userId: userId\);\n  \}\n\n/s, '', 1 ],
]);

# 5. Hive: remove the background-sync accessors.
edit('lib/data/services/hive_service.dart', [
    [ qr/  static String _backgroundSyncKey\(String\? userId\).*?  static bool getBackgroundSync\(\{String\? userId\}\) =>\n      _settingsBox\.get\(_backgroundSyncKey\(userId\), defaultValue: true\) as bool;\n/s, '', 1 ],
]);

# 6. Constants: drop the key.
edit('lib/core/constants/app_constants.dart', [
    [ qr/  static const String hiveKeyBackgroundSync = 'background_sync';\n/, '', 1 ],
]);

# 7. Admin settings: remove the Background Sync toggle row and its divider.
edit('lib/presentation/screens/admin/admin_settings_screen.dart', [
    [ qr/            ToggleRow\(\n              title: l10n\.backgroundSync,.*?            const SettingsDivider\(\),\n/s, '', 1 ],
]);
