/// Global constants for Leman Mail.
abstract final class AppConstants {
  static const appName = 'Leman Mail';
  static const tagline = 'Votre boîte mail, sécurisée, maîtrisée et intelligente.';
  static const publisher = 'Leman Cyber Security';

  /// OAuth redirect scheme registered on both platforms.
  static const oauthRedirectScheme = 'com.lemancybersecurity.lemanmail';
  static const oauthRedirectUri = '$oauthRedirectScheme:/oauth2redirect';

  /// Secure storage keys.
  static const masterKeyStorageKey = 'leman_master_key_v1';
  static String accountSecretKey(String accountUuid) =>
      'account_secret_$accountUuid';

  /// Sync tuning.
  static const initialSyncMessageLimit = 200;
  static const syncPageSize = 50;
  static const snippetLength = 160;
}
