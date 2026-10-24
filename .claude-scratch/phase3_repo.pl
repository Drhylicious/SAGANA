use utf8;
use strict;
use warnings;

my $file = 'lib/data/repositories/broadcast_repository.dart';
my $in;
open($in, '<:encoding(UTF-8)', $file) or die "$file: $!";
my $t = do { local $/; <$in> };
close($in);
my $crlf = $t =~ /\r\n/ ? 1 : 0;
$t =~ s/\r\n/\n/g;

# Imports: the notification writer is no longer used here; Random makes the client key.
$t =~ s/^import 'notification_repository\.dart';\n/import 'dart:math' show Random;\n/m or die "import not found\n";

# Replace sendBroadcast() entirely (up to the preview section, which is kept).
my $start = index($t, "  Future<int> sendBroadcast({");
my $end   = index($t, "  // ─── Fetch dynamic recipient count preview");
die "markers not found ($start, $end)\n" if $start < 0 || $end < 0 || $end <= $start;

my $new = <<'DART';
  /// A new key identifies one send attempt. Keep it across retries of the same
  /// attempt so a repeated request is recognized and not sent twice.
  static String newClientKey() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }

  // ─── Send broadcast ──────────────────────────────────────────────────────────
  // Immediate sends go through send_broadcast(): recipients are resolved,
  // notices are inserted and the log is written in one database transaction.
  // The returned count is the number of notices actually inserted.
  // Scheduled sends are queued in broadcast_logs and sent by
  // process_scheduled_broadcasts().

  Future<int> sendBroadcast({
    required String title,
    required String body,
    required BroadcastCategory category,
    required RecipientType recipientType,
    String? recipientFilter,
    DateTime? scheduledAt,
    String? clientKey,
  }) async {
    final adminId = _client.auth.currentUser?.id;
    final now     = DateTime.now();
    final isDeferred = scheduledAt != null && scheduledAt.isAfter(now);
    final key = clientKey ?? newClientKey();

    if (!isDeferred) {
      final int count;
      try {
        count = await _client.rpc('send_broadcast', params: {
          'p_title': title,
          'p_body': body,
          'p_category': category.value,
          'p_recipient_type': recipientType.value,
          'p_recipient_filter': recipientFilter,
          'p_client_key': key,
        }) as int;
      } on PostgrestException catch (e) {
        if (e.message.contains('NO_RECIPIENTS')) {
          throw const BroadcastNoRecipientsException();
        }
        rethrow;
      }

      AdminActivityRepository().log(
        module: 'broadcast',
        actionType: 'sent',
        message: AdminLogMessage('adminLogBroadcastSent', {'title': title, 'count': '$count'}),
      );
      return count;
    }

    // Deferred: queue only. Recipients are an estimate for display; the real set
    // is resolved when process_scheduled_broadcasts() sends it.
    final recipientIds = await resolveRecipientIds(
      type:   recipientType,
      filter: recipientFilter,
    );

    await _client.from('broadcast_logs').upsert({
      'title':            title,
      'body':             body,
      'category':         category.value,
      'recipient_type':   recipientType.value,
      'recipient_filter': recipientFilter,
      'recipient_count':  recipientIds.length,
      'scheduled_at':     scheduledAt.toIso8601String(),
      'sent_at':          null,
      'created_by':       adminId,
      'created_at':       now.toIso8601String(),
      'client_key':       key,
    }, onConflict: 'client_key', ignoreDuplicates: true);

    AdminActivityRepository().log(
      module: 'broadcast',
      actionType: 'scheduled',
      message: AdminLogMessage('adminLogBroadcastScheduled', {'title': title, 'when': scheduledAt.toIso8601String()}),
    );

    return recipientIds.length;
  }

DART

substr($t, $start, $end - $start) = $new;

# Exception type for "nothing matched", defined once near the top of the class file.
my $exc = "class BroadcastNoRecipientsException implements Exception {\n  const BroadcastNoRecipientsException();\n}\n\n";
$t =~ s/^(class BroadcastRepository \{)/$exc$1/m or die "class not found\n";

$t =~ s/\n/\r\n/g if $crlf;
my $out;
open($out, '>:encoding(UTF-8)', $file) or die "$file: $!";
print {$out} $t;
close($out);
print "updated $file\n";
