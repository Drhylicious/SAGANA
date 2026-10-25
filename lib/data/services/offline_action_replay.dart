import 'dart:typed_data';

import '../repositories/admin_profile_repository.dart';
import '../repositories/buyer_address_repository.dart';
import '../repositories/buyer_profile_repository.dart';
import '../repositories/capital_contribution_repository.dart';
import '../repositories/crop_repository.dart';
import '../repositories/farmer_profile_repository.dart';
import '../repositories/notification_repository.dart';
import '../../core/utils/person_name.dart';
import 'offline_actions.dart';

/// Sends one queued action to the server. Called only by SyncService.
///
/// Each handler runs the same `...Online` write the screen would have run, so
/// a queued action and an online action can never drift apart. A rejection
/// (a PostgrestException, or a validation error thrown by the write) leaves
/// the action queued with its reason. See SyncService.
class OfflineActionReplay {
  OfflineActionReplay._();

  static Future<void> run(String kind, Map<dynamic, dynamic> p) async {
    switch (kind) {
      case 'farmer_basic_info':
        await FarmerProfileRepository().updateBasicInfoOnline(
          name: NameParts.fromRow(p['name'] as Map?),
          fullName: p['fullName'] as String?,
          phoneNumber: p['phoneNumber'] as String?,
          contactEmail: p['contactEmail'] as String?,
          dateOfBirth: decodeDate(p['dateOfBirth']),
          gender: p['gender'] as String?,
          clearDateOfBirth: p['clearDateOfBirth'] as bool? ?? false,
          clearGender: p['clearGender'] as bool? ?? false,
        );
      case 'farmer_farm_details':
        await FarmerProfileRepository().updateFarmDetailsOnline(
          farmName: p['farmName'] as String?,
          farmAddress: p['farmAddress'] as String?,
          farmStreet: p['farmStreet'] as String?,
          farmBuilding: p['farmBuilding'] as String?,
          farmHouseNo: p['farmHouseNo'] as String?,
          landAreaHectares: (p['landAreaHectares'] as num?)?.toDouble(),
          yearsFarming: p['yearsFarming'] as int?,
          farmLatitude: (p['farmLatitude'] as num?)?.toDouble(),
          farmLongitude: (p['farmLongitude'] as num?)?.toDouble(),
          farmOwnershipType: p['farmOwnershipType'] as String?,
          soilType: p['soilType'] as String?,
          waterSource: p['waterSource'] as String?,
        );
      case 'farmer_photo':
        await FarmerProfileRepository().updatePhotoOnline(
          imageBytes: p['imageBytes'] as Uint8List,
          fileExtension: p['fileExtension'] as String,
        );
      case 'buyer_profile':
        await BuyerProfileRepository().updateProfileOnline(
          name: NameParts.fromRow(p['name'] as Map?),
          fullName: p['fullName'] as String?,
          phoneNumber: p['phoneNumber'] as String?,
          photoUrl: p['photoUrl'] as String?,
          contactEmail: p['contactEmail'] as String?,
          dateOfBirth: decodeDate(p['dateOfBirth']),
          gender: p['gender'] as String?,
        );
      case 'admin_basic_info':
        await AdminProfileRepository().updateBasicInfoOnline(
          name: NameParts.fromRow(p['name'] as Map?),
          fullName: p['fullName'] as String?,
          phoneNumber: p['phoneNumber'] as String?,
          contactEmail: p['contactEmail'] as String?,
          dateOfBirth: decodeDate(p['dateOfBirth']),
          gender: p['gender'] as String?,
        );
      case 'admin_photo':
        await AdminProfileRepository().updatePhotoOnline(
          imageBytes: p['imageBytes'] as Uint8List,
          fileExtension: p['fileExtension'] as String,
        );
      case 'admin_photo_remove':
        await AdminProfileRepository().removePhotoOnline();
      case 'address_add':
        await BuyerAddressRepository().addAddressOnline(
          id: p['id'] as String,
          label: p['label'] as String,
          recipientName: p['recipientName'] as String?,
          contactNumber: p['contactNumber'] as String?,
          addressLine: p['addressLine'] as String,
          latitude: (p['latitude'] as num?)?.toDouble(),
          longitude: (p['longitude'] as num?)?.toDouble(),
          notes: p['notes'] as String?,
          isDefault: p['isDefault'] as bool? ?? false,
          structureColumns: _columns(p['structureColumns']),
        );
      case 'address_update':
        await BuyerAddressRepository().updateAddressOnline(
          id: p['id'] as String,
          label: p['label'] as String,
          recipientName: p['recipientName'] as String?,
          contactNumber: p['contactNumber'] as String?,
          addressLine: p['addressLine'] as String,
          latitude: (p['latitude'] as num?)?.toDouble(),
          longitude: (p['longitude'] as num?)?.toDouble(),
          notes: p['notes'] as String?,
          structureColumns: _columns(p['structureColumns']),
        );
      case 'address_delete':
        await BuyerAddressRepository().deleteAddressOnline(p['id'] as String);
      case 'address_default':
        await BuyerAddressRepository().setDefaultAddressOnline(
          p['id'] as String,
          logActivity: p['logActivity'] as bool? ?? true,
        );
      case 'crop_photo':
        await CropRepository().setCropPhotoOnline(
          bytes: p['bytes'] as Uint8List,
          fileExtension: p['fileExtension'] as String,
          cropId: p['cropId'] as String,
          cropName: p['cropName'] as String,
        );
      case 'notification_read':
        await NotificationRepository().markAsReadOnline(p['id'] as String);
      case 'notification_read_all':
        await NotificationRepository().markAllAsReadOnline();
      case 'notification_delete':
        await NotificationRepository().deleteNotificationOnline(p['id'] as String);
      case 'notification_delete_all':
        await NotificationRepository().deleteAllNotificationsOnline();
      case 'capital_record':
        await CapitalContributionRepository().recordContributionOnline(
          farmerId: p['farmerId'] as String,
          amount: (p['amount'] as num).toDouble(),
          source: p['source'] as String,
          note: p['note'] as String?,
        );
      default:
        throw StateError('Unknown queued action: $kind');
    }
  }

  static Map<String, dynamic>? _columns(Object? value) =>
      value == null ? null : Map<String, dynamic>.from(value as Map);
}
