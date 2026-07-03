/// Domain-level failures. Services and repositories translate low-level
/// exceptions (socket, IMAP, HTTP) into these so the presentation layer
/// never depends on transport details.
sealed class Failure implements Exception {
  const Failure(this.message, {this.cause});

  /// User-presentable message (localized upstream).
  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.cause});
}

class AuthenticationFailure extends Failure {
  const AuthenticationFailure(super.message, {super.cause});
}

class MailProtocolFailure extends Failure {
  const MailProtocolFailure(super.message, {super.cause});
}

class StorageFailure extends Failure {
  const StorageFailure(super.message, {super.cause});
}

class CryptoFailure extends Failure {
  const CryptoFailure(super.message, {super.cause});
}
