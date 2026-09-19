import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';

class AppUtils {
  AppUtils._();

  // ─── Validators ──────────────────────────────────────────────────────────────

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != password) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Full name is required';
    }
    if (value.trim().length < 3) {
      return 'Enter your complete name';
    }
    return null;
  }

  static String? validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final phoneRegex = RegExp(r'^09\d{9}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Enter a valid Philippine mobile number (09XXXXXXXXX)';
    }
    return null;
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  // ─── Formatters ──────────────────────────────────────────────────────────────

  static String formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'fil_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  static String formatWeight(double kg) {
    if (kg >= 1000) {
      return '${(kg / 1000).toStringAsFixed(2)} t';
    }
    return '${kg.toStringAsFixed(1)} kg';
  }

  // localeName is optional and defaults to null (system/default locale),
  // preserving exact prior behavior for every existing caller. Passing it
  // is opt-in — added for screens that need the date to follow the app's
  // selected language rather than the device's.
  static String formatDate(DateTime date, [String? localeName]) {
    return DateFormat('MMM d, yyyy', localeName).format(date);
  }

  static String formatDateShort(DateTime date) {
    return DateFormat('MM/dd/yyyy').format(date);
  }

  static String formatDateTime(DateTime date) {
    return DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  // l10n is optional (defaults to null, preserving the old English-only
  // behavior for any caller that hasn't been updated) — pass it to get
  // "Just now"/"5m ago"/etc. in the app's selected language, same
  // broadcastJustNow/buyerNotifTimeXAgo keys used elsewhere for this exact
  // phrasing (admin_notifications_screen.dart, admin_activity_screen.dart).
  static String formatRelativeTime(DateTime date, [AppLocalizations? l10n]) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return l10n?.broadcastJustNow ?? 'Just now';
    if (diff.inMinutes < 60) {
      return l10n != null ? l10n.buyerNotifTimeMinutesAgo(diff.inMinutes) : '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return l10n != null ? l10n.buyerNotifTimeHoursAgo(diff.inHours) : '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return l10n != null ? l10n.buyerNotifTimeDaysAgo(diff.inDays) : '${diff.inDays}d ago';
    }
    return formatDate(date, l10n?.localeName);
  }

  // ─── String Helpers ──────────────────────────────────────────────────────────

  static String capitalizeWords(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  static String truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  // ─── UI Helpers ──────────────────────────────────────────────────────────────

  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32),
        duration: duration,
      ),
    );
  }

  static void showComingSoonSnack(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon.')),
    );
  }

  static void showLoadingDialog(BuildContext context, {String message = 'Please wait...'}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00450D)),
            ),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  static void hideLoadingDialog(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  // ─── Date of Birth ───────────────────────────────────────────────────────────
  //
  // Shared across every Date of Birth picker in the app (Register, Add
  // Member, Create Officer Account, Pending Applicant, and every role's
  // Edit Profile) so the selectable range and the 18+ check behave
  // identically everywhere rather than each screen reimplementing its own
  // slightly different version.

  /// Opens a date picker for selecting a Date of Birth. The pickable range
  /// is always computed relative to the current system date — never a
  /// fixed year — so every real birth year, month, and day stays
  /// selectable (including today) and the range advances automatically as
  /// time passes. The 18+ requirement is deliberately **not** enforced by
  /// restricting which dates can be picked here — see [isAtLeast18] and
  /// [showUnder18Dialog], which the caller should run against the result.
  static Future<DateTime?> pickDateOfBirth(
    BuildContext context, {
    DateTime? initialDate,
    String? helpText,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100, now.month, now.day),
      lastDate: today,
      helpText: helpText,
    );
  }

  /// Whether [dateOfBirth] indicates an age of 18 or older as of [asOf]
  /// (defaults to the current system date). Compares the full date — not
  /// just the year — so a birthday later this same year/month correctly
  /// still counts as not-yet-18 until it actually arrives.
  static bool isAtLeast18(DateTime dateOfBirth, [DateTime? asOf]) {
    final now = asOf ?? DateTime.now();
    final eighteenthBirthday = DateTime(
        dateOfBirth.year + 18, dateOfBirth.month, dateOfBirth.day);
    return !eighteenthBirthday.isAfter(now);
  }

  /// Shows a blocking dialog explaining the 18+ requirement — use right
  /// after a Date of Birth selection that [isAtLeast18] found to be under
  /// 18, so the requirement is enforced through validation rather than by
  /// restricting the picker's own selectable range.
  static Future<void> showUnder18Dialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dobUnder18Title),
        content: Text(l10n.dobUnder18Message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cropMgmtOk),
          ),
        ],
      ),
    );
  }

  // ─── Batch Number Generator ──────────────────────────────────────────────────

  static String generateBatchNumber(String cropCode) {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final random = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
    return 'BATCH-${cropCode.toUpperCase()}-$dateStr-$random';
  }
}