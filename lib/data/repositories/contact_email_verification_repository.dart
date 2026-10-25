import 'package:supabase_flutter/supabase_flutter.dart';

/// What came back when a code was requested.
enum EmailCodeRequestStatus {
  /// The e-mail was sent.
  sent,

  /// A code was sent less than a minute ago; try again in [retryAfter] seconds.
  cooldown,

  /// Too many codes this hour or day; try again in [retryAfter] seconds.
  limit,

  /// This address is already verified.
  alreadyVerified,

  /// The account has no email address to verify.
  noEmail,

  /// Not signed in (or the session expired).
  unauthorized,

  /// The mail server could not send it.
  sendFailed,

  /// No connection, or an unexpected failure.
  error,
}

class EmailCodeRequestResult {
  final EmailCodeRequestStatus status;

  /// Seconds until another code may be requested (cooldown / limit / after a
  /// send).
  final int? retryAfter;

  /// The address the code went to, partly hidden ("a****@gmail.com").
  final String? maskedEmail;

  const EmailCodeRequestResult(this.status, {this.retryAfter, this.maskedEmail});

  bool get sent => status == EmailCodeRequestStatus.sent;

  /// Reads the Edge Function's answer. Anything unrecognised is an error, never
  /// a success.
  factory EmailCodeRequestResult.fromJson(Object? json) {
    if (json is! Map) return const EmailCodeRequestResult(EmailCodeRequestStatus.error);
    final retry = (json['retry_after'] as num?)?.toInt();
    switch (json['status']) {
      case 'sent':
        return EmailCodeRequestResult(
          EmailCodeRequestStatus.sent,
          retryAfter: (json['resend_after'] as num?)?.toInt() ?? 60,
          maskedEmail: json['email'] as String?,
        );
      case 'cooldown':
        return EmailCodeRequestResult(EmailCodeRequestStatus.cooldown, retryAfter: retry ?? 60);
      case 'limit':
        return EmailCodeRequestResult(EmailCodeRequestStatus.limit, retryAfter: retry);
      case 'already_verified':
        return const EmailCodeRequestResult(EmailCodeRequestStatus.alreadyVerified);
      case 'no_email':
        return const EmailCodeRequestResult(EmailCodeRequestStatus.noEmail);
      case 'unauthorized':
        return const EmailCodeRequestResult(EmailCodeRequestStatus.unauthorized);
      case 'send_failed':
        return const EmailCodeRequestResult(EmailCodeRequestStatus.sendFailed);
      default:
        return const EmailCodeRequestResult(EmailCodeRequestStatus.error);
    }
  }
}

/// What came back when a typed code was checked.
enum EmailCodeCheckStatus {
  verified,
  invalidCode,
  expired,
  tooManyAttempts,
  noCode,

  /// The address was changed after the code was sent.
  emailChanged,

  /// Not six digits.
  invalidFormat,

  /// No connection, not signed in, or an unexpected failure.
  error,
}

class EmailCodeCheckResult {
  final EmailCodeCheckStatus status;
  final int? attemptsLeft;

  const EmailCodeCheckResult(this.status, {this.attemptsLeft});

  bool get verified => status == EmailCodeCheckStatus.verified;

  /// Reads verify_contact_email()'s answer. Only an explicit "verified" counts;
  /// anything unrecognised is an error.
  factory EmailCodeCheckResult.fromJson(Object? json) {
    if (json is! Map) return const EmailCodeCheckResult(EmailCodeCheckStatus.error);
    switch (json['status']) {
      case 'verified':
        return const EmailCodeCheckResult(EmailCodeCheckStatus.verified);
      case 'invalid_code':
        return EmailCodeCheckResult(
          EmailCodeCheckStatus.invalidCode,
          attemptsLeft: (json['attempts_left'] as num?)?.toInt(),
        );
      case 'expired':
        return const EmailCodeCheckResult(EmailCodeCheckStatus.expired);
      case 'too_many_attempts':
        return const EmailCodeCheckResult(EmailCodeCheckStatus.tooManyAttempts);
      case 'no_code':
        return const EmailCodeCheckResult(EmailCodeCheckStatus.noCode);
      case 'email_changed':
        return const EmailCodeCheckResult(EmailCodeCheckStatus.emailChanged);
      case 'invalid_format':
        return const EmailCodeCheckResult(EmailCodeCheckStatus.invalidFormat);
      default:
        return const EmailCodeCheckResult(EmailCodeCheckStatus.error);
    }
  }
}

/// The two server calls behind "Verify Email". An interface so a screen can be
/// tested without a server.
abstract class ContactEmailVerifier {
  /// Asks the server to e-mail a code to the signed-in account's address.
  Future<EmailCodeRequestResult> requestCode();

  /// Checks a typed code. The server decides; the app never sees the real code.
  Future<EmailCodeCheckResult> checkCode(String code);
}

class SupabaseContactEmailVerifier implements ContactEmailVerifier {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<EmailCodeRequestResult> requestCode() async {
    try {
      final res = await _client.functions.invoke('send-email-verification');
      return EmailCodeRequestResult.fromJson(res.data);
    } on FunctionException catch (e) {
      if (e.status == 401) {
        return const EmailCodeRequestResult(EmailCodeRequestStatus.unauthorized);
      }
      // The function answers a mail-server failure with 502 and a status body.
      final fromBody = EmailCodeRequestResult.fromJson(e.details);
      return fromBody.status == EmailCodeRequestStatus.error
          ? const EmailCodeRequestResult(EmailCodeRequestStatus.sendFailed)
          : fromBody;
    } catch (_) {
      return const EmailCodeRequestResult(EmailCodeRequestStatus.error);
    }
  }

  @override
  Future<EmailCodeCheckResult> checkCode(String code) async {
    try {
      final res = await _client.rpc(
        'verify_contact_email',
        params: {'p_code': code.trim()},
      );
      return EmailCodeCheckResult.fromJson(res);
    } catch (_) {
      return const EmailCodeCheckResult(EmailCodeCheckStatus.error);
    }
  }
}
