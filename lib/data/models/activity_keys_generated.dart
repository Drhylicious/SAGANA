// GENERATED from .claude-scratch/activity_writer_keys.txt. Do not edit by hand.
import '../../core/l10n/app_localizations.dart';

/// Renders a writer-side activity key. Returns null for unknown keys.
String? renderGeneratedActivity(AppLocalizations l, String key, Map<String, String> p) {
  String v(String name) => p[name] ?? '';
  switch (key) {
    case 'activityProfileUpdated':
      return l.activityProfileUpdated(v('fields'));
    case 'activityProfilePhotoUpdated':
      return l.activityProfilePhotoUpdated;
    case 'activityPasswordChanged':
      return l.activityPasswordChanged;
    case 'activityCropPhotoUpdated':
      return l.activityCropPhotoUpdated(v('crop'));
    case 'activityProgramPurchaseCancelled':
      return l.activityProgramPurchaseCancelled;
    case 'activityAddressAdded':
      return l.activityAddressAdded(v('label'));
    case 'activityAddressUpdated':
      return l.activityAddressUpdated(v('label'));
    case 'activityAddressDeleted':
      return l.activityAddressDeleted(v('label'));
    case 'activityAddressDefault':
      return l.activityAddressDefault(v('label'));
    default:
      return null;
  }
}

/// Localized label for a profile field code ('name', 'phone', ...). Null if unknown.
String? activityFieldLabel(AppLocalizations l, String code) {
  switch (code) {
    case 'name':
      return l.activityFieldName;
    case 'phone':
      return l.activityFieldPhone;
    case 'photo':
      return l.activityFieldPhoto;
    case 'email':
      return l.activityFieldEmail;
    case 'dob':
      return l.activityFieldDob;
    case 'gender':
      return l.activityFieldGender;
    case 'farmName':
      return l.activityFieldFarmName;
    case 'farmAddress':
      return l.activityFieldFarmAddress;
    case 'farmLocation':
      return l.activityFieldFarmLocation;
    case 'farmDetails':
      return l.activityFieldFarmDetails;
    case 'landArea':
      return l.activityFieldLandArea;
    case 'ownership':
      return l.activityFieldOwnership;
    case 'soil':
      return l.activityFieldSoil;
    case 'water':
      return l.activityFieldWater;
    case 'years':
      return l.activityFieldYears;
    default:
      return null;
  }
}
