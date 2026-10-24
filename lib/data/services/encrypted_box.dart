import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Opens Hive boxes encrypted with AES. The key is generated once and kept in
/// platform secure storage, so the cached and queued data on disk is unreadable
/// without it.
///
/// A box written before encryption existed is migrated the first time it is
/// opened. Its entries are copied into a temporary encrypted box, the plain box
/// is removed, and the entries are copied into the encrypted box. Nothing is
/// removed until the copy is complete, and an interrupted migration is resumed
/// on the next open.
class EncryptedBox {
  EncryptedBox._();

  static const _keyName = 'sagana_hive_key';
  static const _storage = FlutterSecureStorage();
  static HiveAesCipher? _cipher;

  static Future<HiveAesCipher> _getCipher() async {
    final cached = _cipher;
    if (cached != null) return cached;

    var encoded = await _storage.read(key: _keyName);
    if (encoded == null) {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      encoded = base64Encode(bytes);
      await _storage.write(key: _keyName, value: encoded);
    }
    final cipher = HiveAesCipher(base64Decode(encoded));
    _cipher = cipher;
    return cipher;
  }

  /// Opens [name] encrypted, migrating a plain box from before encryption.
  static Future<Box> open(String name) async {
    final cipher = await _getCipher();
    final tempName = '${name}__enc_tmp';

    // A temporary box is left over from an interrupted migration. If the target
    // opens with the cipher, the plain box was already removed, so the temporary
    // box holds the data and is copied across. If it doesn't, the plain box is
    // still there and the partial copy is discarded before migrating again.
    if (await Hive.boxExists(tempName)) {
      Box? target;
      try {
        target = await Hive.openBox(name, encryptionCipher: cipher);
      } catch (_) {
        target = null;
      }
      if (target != null) {
        final temp = await Hive.openBox(tempName, encryptionCipher: cipher);
        if (target.isEmpty && temp.isNotEmpty) {
          await target.putAll(temp.toMap());
        }
        await temp.deleteFromDisk();
        return target;
      }
      final stale = await Hive.openBox(tempName, encryptionCipher: cipher);
      await stale.deleteFromDisk();
    }

    try {
      return await Hive.openBox(name, encryptionCipher: cipher);
    } catch (_) {
      // Not readable with the cipher: most likely a plain box from before
      // encryption. The plain open below fails loudly if it is something else.
    }

    final plain = await Hive.openBox(name);
    final data = plain.toMap();
    await plain.close();

    final temp = await Hive.openBox(tempName, encryptionCipher: cipher);
    await temp.clear();
    await temp.putAll(data);
    await temp.close();

    await Hive.deleteBoxFromDisk(name);

    final target = await Hive.openBox(name, encryptionCipher: cipher);
    await target.putAll(data);

    final done = await Hive.openBox(tempName, encryptionCipher: cipher);
    await done.deleteFromDisk();
    return target;
  }
}
