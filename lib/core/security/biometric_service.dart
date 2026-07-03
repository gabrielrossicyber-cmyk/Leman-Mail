import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// App-lock via Face ID / Touch ID / fingerprint / device credential.
class BiometricService {
  BiometricService([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  /// Prompts the user. Falls back to the device PIN/pattern when biometrics
  /// are unavailable, so the app lock never dead-ends.
  Future<bool> authenticate({
    String reason = 'Déverrouillez Leman Mail',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
