import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../error/failures.dart';

/// AES-256-GCM authenticated encryption for data at rest (email bodies,
/// attachments, account secrets).
///
/// Record format: `nonce(12) || ciphertext || mac(16)`.
/// The 256-bit master key is generated once and kept in the platform
/// secure storage (see [SecureStorageService]); it never touches SQLite.
class CryptoService {
  CryptoService(this._masterKeyBytes)
      : assert(_masterKeyBytes.length == 32, 'AES-256 requires a 32-byte key');

  final List<int> _masterKeyBytes;
  final AesGcm _algorithm = AesGcm.with256bits();

  static const _nonceLength = 12;
  static const _macLength = 16;

  Future<Uint8List> encryptBytes(List<int> plaintext) async {
    final secretKey = SecretKey(_masterKeyBytes);
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    final out = BytesBuilder(copy: false)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  Future<Uint8List> decryptBytes(List<int> record) async {
    if (record.length < _nonceLength + _macLength) {
      throw const CryptoFailure('Enregistrement chiffré corrompu.');
    }
    final nonce = record.sublist(0, _nonceLength);
    final mac = Mac(record.sublist(record.length - _macLength));
    final cipherText =
        record.sublist(_nonceLength, record.length - _macLength);
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: SecretKey(_masterKeyBytes),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError catch (e) {
      throw CryptoFailure(
        'Échec de vérification d\'intégrité (données altérées).',
        cause: e,
      );
    }
  }

  Future<Uint8List> encryptString(String plaintext) =>
      encryptBytes(utf8.encode(plaintext));

  Future<String> decryptString(List<int> record) async =>
      utf8.decode(await decryptBytes(record));
}
