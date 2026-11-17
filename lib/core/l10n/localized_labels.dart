import '../../data/services/app_settings_service.dart';
import 'app_localizations.dart';

/// The app's strings in the language chosen in Settings, for code that has no
/// BuildContext (models, repositories, validators).
AppLocalizations currentL10n() =>
    lookupAppLocalizations(AppSettingsService.instance.locale);

/// Translates built-in display labels while retaining stored filter values.
/// Custom category names and user-entered text pass through unchanged.
String localizeBuiltinLabel(AppLocalizations l10n, String value) =>
    switch (value) {
      "All" => l10n.reportsAll,
      "Available" => l10n.reportsAvailable,
      "Reserved" => l10n.reportsReserved,
      "Sold" => l10n.reportsSold,
      "Low Stock" => l10n.reportsLowStockItems,
      "Submitted" => l10n.marketLinkKpiSubmitted,
      "Under Review" => l10n.pendingStepReview,
      "Decision" => l10n.pendingStepDecision,
      "Cancel" => l10n.cancel,
      "Update Password" => l10n.updatePassword,
      "Top Harvested Crops (Coop-wide, 90 days)" =>
        l10n.farmerAnalyticsTopHarvestedCropsTitle,
      "Other" => l10n.suspendReasonOther,
      "Profile" => l10n.navProfile,
      "Home" => l10n.navHome,
      "Programs" => l10n.farmerDetailsTabPrograms,
      "Program" => l10n.adminCalEventProgram,
      "Fertilizer" => l10n.enhFertilizer,
      "Seeds" => l10n.enhSeeds,
      "Animal Feeds" => l10n.enhAnimalFeeds,
      "Harvest Stock" => l10n.enhHarvestStock,
      "Labor" => l10n.enhLabor,
      "Tools" => l10n.enhTools,
      "Irrigation" => l10n.enhIrrigation,
      "Transport" => l10n.enhTransport,
      "Distribution" => l10n.programMgmtFilterDistribution,
      "Sales" => l10n.programMgmtFilterSales,
      "Fruit" => l10n.enhFruit,
      "Vegetable" => l10n.enhVegetable,
      "Root & Spice Crop" => l10n.enhRootSpiceCrop,
      "Tree Crop" => l10n.enhTreeCrop,
      "Pesticide" => l10n.enhPesticide,
      "Tools & Equipment" => l10n.enhToolsEquipment,
      "Livestock" => l10n.enhLivestock,
      "Grain" => l10n.enhGrain,
      "Legume" => l10n.enhLegume,
      "Order" => l10n.rptProductSaleOrder,
      "Orders" => l10n.buyerNavOrders,
      "Listings" => l10n.navListings,
      "Crop Requests" => l10n.cropRequestTitle,
      "Cooperative Offers" => l10n.coopMyOffersTitle,
      "Loans" => l10n.adminNavLoans,
      "Prices" => l10n.buyerNavPrices,
      "Capital" => l10n.memberContributionCapitalSection,
      "Live" => l10n.enhLive,
      _ => value,
    };
