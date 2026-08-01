import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../models/cart_item_model.dart';

/// Local buyer cart storage. Follows SettingsRepository's exact Hive
/// idiom — open the box fresh per call rather than holding a long-lived
/// reference. Each item is stored under its own listingId key (not as
/// one serialized List), which is what makes "merge by listingId" trivial:
/// adding an already-cart-present listing just overwrites its key instead
/// of requiring a manual find-and-replace inside a list.
class CartService {
  Future<List<CartItemModel>> getItems() async {
    final box = await Hive.openBox(AppConstants.hiveBoxCart);
    return box.values
        .map((raw) => CartItemModel.fromMap(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<int> itemCount() async {
    final box = await Hive.openBox(AppConstants.hiveBoxCart);
    return box.length;
  }

  Future<void> addItem({
    required String listingId,
    required String cropName,
    String? variety,
    required double pricePerKg,
    String? photoUrl,
    required double availableKgSnapshot,
    required double quantityKg,
  }) async {
    final box = await Hive.openBox(AppConstants.hiveBoxCart);
    final existingRaw = box.get(listingId);

    if (existingRaw != null) {
      final existing = CartItemModel.fromMap(Map<String, dynamic>.from(existingRaw as Map));
      existing.quantityKg = (existing.quantityKg + quantityKg).clamp(0.0, availableKgSnapshot);
      await box.put(listingId, existing.toMap());
    } else {
      final item = CartItemModel(
        listingId: listingId,
        cropName: cropName,
        variety: variety,
        pricePerKg: pricePerKg,
        photoUrl: photoUrl,
        availableKgSnapshot: availableKgSnapshot,
        quantityKg: quantityKg,
      );
      await box.put(listingId, item.toMap());
    }
  }

  Future<void> updateQuantity(String listingId, double quantityKg) async {
    final box = await Hive.openBox(AppConstants.hiveBoxCart);
    final raw = box.get(listingId);
    if (raw == null) return;
    final item = CartItemModel.fromMap(Map<String, dynamic>.from(raw as Map));
    item.quantityKg = quantityKg;
    await box.put(listingId, item.toMap());
  }

  Future<void> removeItem(String listingId) async {
    final box = await Hive.openBox(AppConstants.hiveBoxCart);
    await box.delete(listingId);
  }

  Future<void> clear() async {
    final box = await Hive.openBox(AppConstants.hiveBoxCart);
    await box.clear();
  }
}
