import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/program_outcome_model.dart';
import '../../data/services/server_only.dart';
import '../../data/services/offline_actions.dart';
import '../l10n/app_localizations.dart';

/// The one place that turns a failure into a sentence a person can read.
///
/// Nothing technical reaches the screen: no SQL text, constraint names, error
/// codes or stack traces. The original error is written to the developer log
/// (and the debug console) so it can still be diagnosed. A refusal the database
/// raised on purpose is recognised by its CODE prefix (for example
/// `PROGRAM_NOT_READY: ...`) or by a known phrase, and shown in the person's own
/// language; anything unrecognised becomes a plain "something went wrong".
String friendlyError(
  AppLocalizations l10n,
  Object error, [
  StackTrace? stack,
  String? fallback,
]) {
  _log(error, stack);
  final other = fallback ?? l10n.errGeneric;

  if (error is ServerOnlyException || error is OfflineActionBlocked) {
    return l10n.errOffline;
  }
  if (error is OutcomeActionException) {
    if (error.offline) return l10n.errOffline;
    return _fromText(l10n, error.message, null) ?? other;
  }
  if (error is SocketException) return l10n.errNetwork;
  if (error is PostgrestException) {
    // The app expects a column or function the database does not have yet.
    if (error.code == 'PGRST204' ||
        error.code == 'PGRST202' ||
        error.code == '42703' ||
        error.code == '42883') {
      return l10n.errNeedsDbUpdate;
    }
    return _fromText(l10n, error.message, error.code) ?? other;
  }
  return other;
}

/// A sentence the database wrote on purpose for a person (RAISE EXCEPTION) and
/// that holds nothing technical: no SQL, identifiers with underscores, keys,
/// constraint names or error codes.
bool _isPlainSentence(String s) {
  final t = s.trim();
  if (t.isEmpty || t.length > 220) return false;
  final technical = RegExp(
    r'(_[a-z]|::|violates|constraint|relation |column |SQLSTATE|duplicate key|syntax|policy|permission denied|null value|function |uuid|\bpg_)',
    caseSensitive: false,
  );
  return !technical.hasMatch(t);
}

void _log(Object error, StackTrace? stack) {
  developer.log(
    'handled error: $error',
    name: 'sagana.error',
    error: error,
    stackTrace: stack,
  );
  if (kDebugMode) debugPrint('[sagana.error] $error');
}

/// Maps a database refusal to a translated sentence, or null if unknown.
String? messageForDatabaseText(
  AppLocalizations l10n,
  String message, [
  String? sqlState,
]) => _fromText(l10n, message, sqlState);

String? _fromText(AppLocalizations l10n, String raw, String? sqlState) {
  final code = RegExp(r'^([A-Z][A-Z_]{3,}):').firstMatch(raw.trim())?.group(1);
  switch (code) {
    case 'NOT_ALLOWED':
      return l10n.errNotAllowed;
    case 'PROGRAM_NOT_READY':
      return l10n.errProgramNotReady;
    case 'PROGRAM_COMPLETED':
      return l10n.errProgramCompleted;
    case 'PROGRAM_STATUS_LOCKED':
      return l10n.errProgramStatusLocked;
    case 'PROGRAM_NO_DELETE':
      return l10n.errProgramNoDelete;
    case 'PROGRAM_NOT_FOUND':
      return l10n.errGeneric;
    case 'REMINDER_TODAY':
      return l10n.errReminderToday;
    case 'REMINDER_NOT_NEEDED':
      return l10n.errReminderNotNeeded;
    case 'BENEFIT_TYPE_LOCKED':
      return l10n.errBenefitLocked;
    case 'DECLINE_NOT_ALLOWED':
      return l10n.errDeclineNotAllowed;
    case 'NO_WITHDRAW':
      return l10n.errNoWithdraw;
    case 'NO_PRODUCT_DELETE':
      return l10n.errNoProductDelete;
    case 'RETURN_CLOSED':
      return l10n.errReturnClosed;
    case 'RETURN_OVER_RECEIPT':
      return l10n.errReturnOverReceipt;
    case 'RETURN_REASON':
      return l10n.errReturnReason;
    case 'ASSIST_NOT_ELIGIBLE':
      return l10n.errAssistNotEligible;
    case 'ASSIST_ITEMS':
      return l10n.errAssistItems;
    case 'RESOLUTION_INVALID':
      return l10n.errGeneric;
    case 'PRODUCT_NOT_IN_SOURCE':
      return l10n.errProductNotInSource;
    case 'NO_STAFF_CANCEL':
      return l10n.errNoStaffCancel;
    case 'RETURN_ITEM':
      return l10n.errReturnItem;
    case 'RETURN_UNIT':
      return l10n.errReturnUnit;
    case 'RETURN_QUANTITY':
      return l10n.errReturnQuantity;
    case 'RESOLUTION_LOCKED':
      return l10n.errResolutionLocked;
    case 'OUTCOME_LOCKED':
      return l10n.errOutcomeLocked;
    case 'RESTORE_CONFLICT':
      return l10n.errRestoreConflict;
    case 'REDISTRIBUTE_NOT_ALLOWED':
      return l10n.errRedistributeNotAllowed;
    case 'RETURN_QUANTITY_REQUIRED':
      return l10n.errReturnQuantityRequired;
    case 'ITEM_CROP_REQUIRED':
      return l10n.errItemCropRequired;
    case 'ITEM_CROP_INACTIVE':
      return l10n.errItemCropInactive;
    case 'CROP_NOT_AVAILABLE':
      return l10n.errCropNotAvailable;
    case 'ASSIST_PENDING':
      return l10n.errAssistPending;
    case 'PAYMENT_NOT_RECORDED':
      return l10n.errPaymentNotRecorded;
    case 'AMOUNT_MISMATCH':
      return l10n.errAmountMismatch;
    case 'REASON_REQUIRED':
      return l10n.errReasonRequired;
    case 'PHOTO_REQUIRED':
      return l10n.errPhotoRequired;
    case 'COOPERATIVE_FARMERS_ONLY':
    case 'FARMERS_ONLY':
      return l10n.errFarmersOnly;
    case 'OUT_OF_STOCK':
    case 'NOT_ENOUGH_STOCK':
      return l10n.errOutOfStock;
    case 'GROUP_REQUIRED':
      return l10n.errGroupRequired;
    case 'DELIVERY_OFF':
      return l10n.errDeliveryOff;
    case 'DELIVERY_NOT_READY':
      return l10n.errDeliveryNotReady;
    case 'OUTSIDE_AREA':
      return l10n.errOutsideArea;
    case 'NO_PIN':
      return l10n.errNoPin;
    case 'TOO_FAR':
      return l10n.errTooFar;
    case 'NO_BAND':
      return l10n.errNoBand;
    case 'OVER_ALLOCATED':
      return l10n.errOverAllocated;
    case 'BELOW_RESERVED':
      return l10n.errBelowReserved;
    case 'STOCK_ALLOCATED':
      return l10n.errStockAllocated;
    case 'BANDS_INVALID':
      return l10n.errBandsInvalid;
    case 'PICKUP_OFF':
      return l10n.errPickupOff;
    case 'ONE_METHOD_REQUIRED':
      return l10n.errOneMethodRequired;
    case 'PERSONAL_NUMBER':
      return l10n.errPersonalNumber;
    case 'UPDATE_REQUIRED':
    case 'UPDATE_APP':
      return l10n.errUpdateRequired;
  }

  final m = raw.toLowerCase();
  bool has(String s) => m.contains(s.toLowerCase());

  if (sqlState == '42501' && has('view-only')) return l10n.errViewOnly;
  if (has('view-only access')) return l10n.errViewOnly;
  if (has('already received a distribution')) return l10n.errAlreadyDistributed;
  if (has('insufficient stock') ||
      has('not enough stock') ||
      has('out of stock')) {
    return l10n.errNoStock;
  }
  if (has('already in progress or finished') ||
      has('outcome was already recorded')) {
    return l10n.errReportExists;
  }
  if (has('at least') && has('photo')) return l10n.errPhotoMin;
  if (has('at most') && has('photo')) return l10n.errPhotoMax;
  if (has('is completed and no longer')) return l10n.errProgramCompletedAction;
  if (has('distribution item is not set') || has('is incomplete')) {
    return l10n.errNoItem;
  }
  if (has('not currently available') || has('not available for loans')) {
    return l10n.errNotAvailable;
  }
  if (has('cannot be left empty') || has('needs every required field')) {
    return l10n.errFixFields;
  }
  if (has('already used by another account')) return l10n.errPhoneUsed;
  // A quantity or price typed with more than 2 decimals (the database checks it
  // for harvest stock, listings, edits and orders alike).
  if (has('at most 2 decimal places') || has('two decimals at most')) {
    return l10n.errTooManyDecimals;
  }
  if (sqlState == '23505') return l10n.errDuplicate;
  if (sqlState == '23503' || sqlState == '23514') return l10n.errFixFields;
  // A refusal written on purpose for a person, with nothing technical in it.
  if (sqlState == 'P0001' && _isPlainSentence(raw)) {
    if (l10n.localeName.startsWith('tl')) return l10n.errFixFields;
    return raw.trim().replaceFirst(RegExp(r'^[A-Z][A-Z_]{3,}:\s*'), '');
  }
  return null;
}
