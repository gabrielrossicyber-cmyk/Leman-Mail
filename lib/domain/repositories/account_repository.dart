import '../entities/account.dart';

/// Secrets attached to an account, kept exclusively in secure storage.
class AccountCredentials {
  const AccountCredentials({
    this.password,
    this.accessToken,
    this.refreshToken,
    this.tokenExpiry,
  });

  final String? password;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? tokenExpiry;
}

abstract interface class AccountRepository {
  Stream<List<Account>> watchAccounts();
  Future<List<Account>> enabledAccounts();

  /// Persists the account row and its credentials (secure storage).
  Future<Account> addAccount({
    required Account draft,
    required AccountCredentials credentials,
  });

  Future<AccountCredentials?> credentialsOf(String accountUuid);

  /// Overwrites the stored secrets (e.g. after an OAuth token refresh).
  Future<void> updateCredentials(
    String accountUuid,
    AccountCredentials credentials,
  );
  Future<void> removeAccount(Account account);
  Future<void> setMfaEnabled(Account account, bool enabled);
}
