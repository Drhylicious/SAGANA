import '../repositories/category_repository.dart';
import '../repositories/crop_repository.dart';
import '../repositories/unit_repository.dart';
import 'connectivity_service.dart';
import 'hive_service.dart';
import 'offline_read_client.dart';

/// Saves, while online, what the offline screens need, so nothing has to be
/// opened first. Runs quietly after sign-in, at app start and on reconnect.
///
/// Two parts: the pages this user loaded before (OfflineReadClient remembers
/// them across logout), and the few lists the offline forms cannot work
/// without, for a device that has never opened them.
class OfflinePreload {
  OfflinePreload._();

  static bool _running = false;

  static Future<void> run() async {
    if (_running || !ConnectivityService.instance.isOnline) return;
    _running = true;
    try {
      // The lists the offline Farmer forms depend on: crops for a harvest,
      // categories for an expense, units, and the catalog for adding a crop.
      if (HiveService.getUserRole() == 'farmer' &&
          HiveService.getUserId() != null) {
        final crops = CropRepository();
        final categories = CategoryRepository();
        for (final load in <Future<Object?> Function()>[
          crops.fetchCrops,
          crops.fetchCropCatalog,
          categories.fetchExpenseCategories,
          categories.fetchCropCategories,
          UnitRepository().fetchUnits,
        ]) {
          try {
            await load();
          } catch (_) {
            // Best effort: the screen loads it again when opened.
          }
        }
      }
      await OfflineReadClient.preloadSavedPages();
    } catch (_) {
      // Never surfaces: this only prepares offline use.
    } finally {
      _running = false;
    }
  }
}
