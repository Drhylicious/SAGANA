use strict;
use warnings;

my $root = 'C:/Users/Administrator/sagana/lib/';

my %files = (
    'data/repositories/dashboard_repository.dart' => {
        imports => [ "../models/activity_text.dart", "../models/admin_log_message.dart" ],
        subs => [
            [ "title: r['description'] as String,", "title: localizeActivityRow(r),", 4 ],
            [ ": r['description'] as String;", ": localizeActivityRow(r);", 1 ],
            [ "'description': _l.activitySyncedOfflineRecords,", "...activityRowFields(const AdminLogMessage('activitySyncedOfflineRecords')),", 1 ],
        ],
    },
    'data/repositories/buyer_profile_repository.dart' => {
        imports => [ "../models/activity_text.dart", "../models/admin_log_message.dart" ],
        subs => [
            [ "title: r['description'] as String,\n            subtitle: 'Profile',",
              "title: localizeActivityRow(r),\n            subtitle: 'Profile',\n            messageKey: activityKeyForRow(r, admin: false),", 1 ],
            [ "Future<void> logActivity(String description) async {\n    try {\n      await _client.from('buyer_profile_activity').insert({\n        'buyer_id': _userId,\n        'description': description,",
              "Future<void> logActivity(AdminLogMessage message) async {\n    try {\n      await _client.from('buyer_profile_activity').insert({\n        'buyer_id': _userId,\n        ...activityRowFields(message),", 1 ],
            [ "await logActivity('Updated \${changes.join(', ')}');",
              "await logActivity(AdminLogMessage('activityProfileUpdated', {'fields': changes.join(',')}));", 1 ],
            [ "logActivity('Changed password');", "logActivity(const AdminLogMessage('activityPasswordChanged'));", 1 ],
        ],
        labels => 1,
    },
    'data/repositories/buyer_address_repository.dart' => {
        imports => [ "../models/admin_log_message.dart" ],
        subs => [
            [ "logActivity('Added address (\$label)');", "logActivity(AdminLogMessage('activityAddressAdded', {'label': '\$label'}));", 1 ],
            [ "logActivity('Updated address (\$label)');", "logActivity(AdminLogMessage('activityAddressUpdated', {'label': '\$label'}));", 1 ],
            [ "logActivity('Deleted address (\$label)');", "logActivity(AdminLogMessage('activityAddressDeleted', {'label': '\$label'}));", 1 ],
            [ "'Set \"\$label\" as default address',", "AdminLogMessage('activityAddressDefault', {'label': '\$label'}),", 1 ],
        ],
    },
    'data/repositories/farmer_profile_repository.dart' => {
        imports => [ "../models/activity_text.dart", "../models/admin_log_message.dart" ],
        subs => [
            [ "'description': 'Updated \${changes.join(', ')}',", "...activityRowFields(AdminLogMessage('activityProfileUpdated', {'fields': changes.join(',')})),", 3 ],
            [ "'description': 'Updated profile photo',", "...activityRowFields(const AdminLogMessage('activityProfilePhotoUpdated')),", 1 ],
            [ "'description': 'Changed password',", "...activityRowFields(const AdminLogMessage('activityPasswordChanged')),", 1 ],
        ],
        labels => 1,
    },
    'data/repositories/crop_repository.dart' => {
        imports => [ "../models/activity_text.dart", "../models/admin_log_message.dart" ],
        subs => [
            [ "'description': 'Updated photo for \$cropName',", "...activityRowFields(AdminLogMessage('activityCropPhotoUpdated', {'crop': cropName})),", 1 ],
        ],
    },
    'data/repositories/farmer_program_repository.dart' => {
        imports => [ "../models/activity_text.dart", "../models/admin_log_message.dart" ],
        subs => [
            [ "'description': 'Cancelled program purchase request',", "...activityRowFields(const AdminLogMessage('activityProgramPurchaseCancelled')),", 1 ],
        ],
    },
    'data/repositories/admin_activity_repository.dart' => {
        imports => [ "../models/activity_text.dart" ],
        subs => [
            [ "plainDescription: key != null\n              ? renderAdminLogMessage(\n                  lookupAppLocalizations(AppSettingsService.instance.locale),\n                  AdminLogMessage(key, params ?? const {}),\n                )\n              : r['description'] as String,",
              "plainDescription: localizeAdminLogRow(r),", 1 ],
            [ "        final key = r['message_key'] as String?;\n        final params = (r['message_params'] as Map?)?.map(\n          (k, v) => MapEntry(k as String, '\$v'),\n        );\n", "", 1 ],
        ],
    },
);

my %labels = (
    'date of birth' => 'dob', 'email' => 'email', 'farm address' => 'farmAddress',
    'farm details' => 'farmDetails', 'farm location' => 'farmLocation', 'farm name' => 'farmName',
    'gender' => 'gender', 'land area' => 'landArea', 'name' => 'name',
    'ownership type' => 'ownership', 'phone number' => 'phone', 'profile photo' => 'photo',
    'soil type' => 'soil', 'water source' => 'water', 'years farming' => 'years',
);

my $failed = 0;
for my $rel (sort keys %files) {
    my $spec = $files{$rel};
    my $file = $root . $rel;
    my $in;
    open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
    my $text = do { local $/; <$in> };
    close($in);
    my $crlf = $text =~ /\r\n/ ? 1 : 0;
    $text =~ s/\r\n/\n/g;

    for my $s (@{ $spec->{subs} }) {
        my ($from, $to, $expected) = @$s;
        my $count = () = $text =~ /\Q$from\E/g;
        if ($count != $expected) {
            print "MISMATCH in $rel: expected $expected got $count for: " . substr($from, 0, 70) . "\n";
            $failed++;
            next;
        }
        $text =~ s/\Q$from\E/$to/g;
    }

    if ($spec->{labels}) {
        for my $label (keys %labels) {
            my $code = $labels{$label};
            $text =~ s/changes\.add\('\Q$label\E'\)/changes.add('$code')/g;
        }
    }

    for my $imp (@{ $spec->{imports} }) {
        my $line = "import '$imp';\n";
        next if index($text, $line) >= 0;
        my $pos = 0;
        while ($text =~ /^import [^\n]*;\n/mg) { $pos = pos($text); }
        substr($text, $pos, 0, $line);
    }

    $text =~ s/\n/\r\n/g if $crlf;
    my $out;
    open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
    print {$out} $text;
    close($out);
    print "updated $rel\n";
}
print "failures: $failed\n";
