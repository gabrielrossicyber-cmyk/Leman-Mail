import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

/// Wraps the platform secure storage (iOS Keychain / Android Keystore +
/// EncryptedSharedPreferences). Holds the AES master key and per-account
/// secrets (OAuth refresh tokens, IMAP passwords).
class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  /// Returns the 32-byte master key, generating it on first launch.
  Future<List<int>> obtainMasterKey() async {
    final existing = await _storage.read(key: AppConstants.masterKeyStorageKey);
    if (existing != null) return base64Decode(existing);
    final random = Random.secure();
    final key = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(
      key: AppConstants.masterKeyStorageKey,
      value: base64Encode(key),
    );
    return key;
  }

  Future<void> writeAccountSecret(String accountUuid, String secretJson) =>
      _storage.write(
        key: AppConstants.accountSecretKey(accountUuid),
        value: secretJson,
      );

  Future<String?> readAccountSecret(String accountUuid) =>
      _storage.read(key: AppConstants.accountSecretKey(accountUuid));

  Future<void> deleteAccountSecret(String accountUuid) =>
      _storage.delete(key: AppConstants.accountSecretKey(accountUuid));
}
