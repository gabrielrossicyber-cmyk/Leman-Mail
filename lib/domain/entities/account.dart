/// Supported mail providers. `imap` covers any generic IMAP/SMTP host
/// (Infomaniak, Fastmail, Proton via Bridge, ...).
enum MailProvider {
  gmail,
  outlook,
  microsoft365,
  yahoo,
  infomaniak,
  fastmail,
  proton,
  imap,
}

enum AuthMethod { oauth2, password }

class Account {
  const Account({
    required this.id,
    required this.uuid,
    required this.email,
    required this.displayName,
    required this.provider,
    required this.authMethod,
    this.imapHost,
    this.imapPort = 993,
    this.imapTls = true,
    this.smtpHost,
    this.smtpPort = 465,
    this.smtpTls = true,
    this.colorValue = 0xFF0B5394,
    this.isEnabled = true,
    this.mfaEnabled = false,
    this.lastSyncAt,
  });

  final int id;
  final String uuid;
  final String email;
  final String displayName;
  final MailProvider provider;
  final AuthMethod authMethod;
  final String? imapHost;
  final int imapPort;
  final bool imapTls;
  final String? smtpHost;
  final int smtpPort;
  final bool smtpTls;
  final int colorValue;
  final bool isEnabled;
  final bool mfaEnabled;
  final DateTime? lastSyncAt;

  /// OAuth-based accounts get MFA "for free" via their identity provider.
  bool get usesOAuth => authMethod == AuthMethod.oauth2;
}
