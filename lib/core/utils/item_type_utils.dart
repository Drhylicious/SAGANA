import '../l10n/app_localizations.dart';

/// The Item Type Inventory Management gives every item (cooperative_inventory.item_type). It is the
/// ONE classification Program Management, the Loan Item Catalog, Supply Chain and the Reports read:
///   Planting Materials - (code 'seeds_seedlings') linked to a Crop Master crop; adds the crop to a Farmer's Crop Roster
///   Harvested Produce  - linked to a Crop Master crop; recorded in the Farmer's Harvest tab (received)
///   Non-Crop Item      - tools, livestock, fertilizer, feeds, supplies; recorded under My Programs only
/// The Category never decides this.
const String kItemTypeSeeds = 'seeds_seedlings';
const String kItemTypeProduce = 'harvested_produce';
const String kItemTypeNonCrop = 'non_crop';

const List<String> kItemTypes = [kItemTypeSeeds, kItemTypeProduce, kItemTypeNonCrop];

/// A crop type is linked to a Crop Master crop.
bool isCropItemType(String? itemType) =>
    itemType == kItemTypeSeeds || itemType == kItemTypeProduce;

/// The short name. Used on cards, chips, reports and details.
String itemTypeLabel(AppLocalizations l10n, String? itemType) {
  switch (itemType) {
    case kItemTypeSeeds:
      return l10n.itemTypeSeeds;
    case kItemTypeProduce:
      return l10n.itemTypeProduce;
    default:
      return l10n.itemTypeNonCrop;
  }
}

/// The dropdown option: the name, with a few examples for the open-ended type.
String itemTypeOptionLabel(AppLocalizations l10n, String itemType) =>
    itemType == kItemTypeNonCrop ? l10n.itemTypeNonCropOption : itemTypeLabel(l10n, itemType);

/// English name for exports (CSV / PDF are written in English like the rest of the report files).
String itemTypeExportLabel(String? itemType) {
  switch (itemType) {
    case kItemTypeSeeds:
      return 'Planting Materials';
    case kItemTypeProduce:
      return 'Harvested Produce';
    default:
      return 'Non-Crop Item';
  }
}
