import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  static String formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatDate(date);
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

  // ─── Batch Number Generator ──────────────────────────────────────────────────

  static String generateBatchNumber(String cropCode) {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final random = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
    return 'BATCH-${cropCode.toUpperCase()}-$dateStr-$random';
  }
}