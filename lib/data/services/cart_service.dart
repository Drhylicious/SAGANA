import '../../core/constants/app_constants.dart';
import '../models/cart_item_model.dart';
import 'encrypted_box.dart';
import 'hive_service.dart';

/// Local buyer and farmer cart storage. Follows SettingsRepository's exact Hive
/// idiom — open the box fresh per call rather than holding a long-lived
/// reference.
///
/// Each item is stored under a key of the form `userId::listingId`, so every
/// account on the device has its own cart. A cart persists across app restarts
/// and offline periods, and is cleared only when its own user signs out
/// (see HiveService.clearUserSession). Items are added, changed and removed only while
/// online; the screens enforce that.
class CartService {
  /// The signed-in user's id, or 'anonymous' when no one is signed in.
  static String get _ownerId => HiveService.getUserId() ?? 'anonymous';

  static String _key(String listingId) => '$_ownerId::$listingId';

  /// Keys in the cart box that belong to the signed-in user.
  static Iterable<dynamic> _ownKeys(dynamic box) {
    final prefix = '$_ownerId::';
    return box.keys.where((k) => k is String && k.startsWith(prefix));
  }

  Future<List<CartItemModel>> getItems() async {
    final box = await EncryptedBox.open(AppConstants.hiveBoxCart);
    return _ownKeys(box)
        .map(
          (k) => CartItemModel.fromMap(
            Map<String, dynamic>.from(box.get(k) as Map),
          ),
        )
        .toList();
  }

  Future<int> itemCount() async {
    final box = await EncryptedBox.open(AppConstants.hiveBoxCart);
    return _ownKeys(box).length;
  }

  Future<void> addItem({
    required String listingId,
    required String cropName,
    String? variety,
    required double pricePerKg,
    String? photoUrl,
    String? category,
    String? marketType,
    required double availableKgSnapshot,
    required double quantityKg,
  }) async {
    final box = await EncryptedBox.open(AppConstants.hiveBoxCart);
    final key = _key(listingId);
    final existingRaw = box.get(key);

    if (existingRaw != null) {
      final existing = CartItemModel.fromMap(
        Map<String, dynamic>.from(existingRaw as Map),
      );
      existing.quantityKg = (existing.quantityKg + quantityKg).clamp(
        0.0,
        availableKgSnapshot,
      );
      await box.put(key, existing.toMap());
    } else {
      final item = CartItemModel(
        listingId: listingId,
        cropName: cropName,
        variety: variety,
        pricePerKg: pricePerKg,
        photoUrl: photoUrl,
        category: category,
        marketType: marketType,
        availableKgSnapshot: availableKgSnapshot,
        quantityKg: quantityKg,
      );
      await box.put(key, item.toMap());
    }
  }

  Future<void> updateQuantity(String listingId, double quantityKg) async {
    final box = await EncryptedBox.open(AppConstants.hiveBoxCart);
    final key = _key(listingId);
    final raw = box.get(key);
    if (raw == null) return;
    final item = CartItemModel.fromMap(Map<String, dynamic>.from(raw as Map));
    item.quantityKg = quantityKg;
    await box.put(key, item.toMap());
  }

  Future<void> removeItem(String listingId) async {
    final box = await EncryptedBox.open(AppConstants.hiveBoxCart);
    await box.delete(_key(listingId));
  }

  /// Empties the signed-in user's cart only.
  Future<void> clear() async {
    final box = await EncryptedBox.open(AppConstants.hiveBoxCart);
    await box.deleteAll(_ownKeys(box).toList());
  }
}
