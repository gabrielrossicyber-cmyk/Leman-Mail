import '../../../domain/entities/account.dart';

/// Connection preset for a known provider — pre-fills the add-account form.
class ProviderPreset {
  const ProviderPreset({
    required this.provider,
    required this.label,
    required this.authMethod,
    this.imapHost,
    this.imapPort = 993,
    this.smtpHost,
    this.smtpPort = 465,
    this.usesNativeApi = false,
    this.helpText,
  });

  final MailProvider provider;
  final String label;
  final AuthMethod authMethod;
  final String? imapHost;
  final int imapPort;
  final String? smtpHost;
  final int smtpPort;

  /// Gmail / Microsoft use their REST APIs instead of IMAP.
  final bool usesNativeApi;
  final String? helpText;
}

const providerPresets = <ProviderPreset>[
  ProviderPreset(
    provider: MailProvider.gmail,
    label: 'Gmail',
    authMethod: AuthMethod.oauth2,
    usesNativeApi: true,
  ),
  ProviderPreset(
    provider: MailProvider.outlook,
    label: 'Outlook.com',
    authMethod: AuthMethod.oauth2,
    usesNativeApi: true,
  ),
  ProviderPreset(
    provider: MailProvider.microsoft365,
    label: 'Microsoft 365',
    authMethod: AuthMethod.oauth2,
    usesNativeApi: true,
  ),
  ProviderPreset(
    provider: MailProvider.yahoo,
    label: 'Yahoo Mail',
    authMethod: AuthMethod.password,
    imapHost: 'imap.mail.yahoo.com',
    smtpHost: 'smtp.mail.yahoo.com',
    helpText: 'Utilisez un « mot de passe d\'application » généré dans les '
        'paramètres de sécurité Yahoo.',
  ),
  ProviderPreset(
    provider: MailProvider.infomaniak,
    label: 'Infomaniak',
    authMethod: AuthMethod.password,
    imapHost: 'mail.infomaniak.com',
    smtpHost: 'mail.infomaniak.com',
    helpText: 'Créez un mot de passe d\'application dans le Manager Infomaniak.',
  ),
  ProviderPreset(
    provider: MailProvider.fastmail,
    label: 'Fastmail',
    authMethod: AuthMethod.password,
    imapHost: 'imap.fastmail.com',
    smtpHost: 'smtp.fastmail.com',
    helpText: 'Utilisez un mot de passe d\'application Fastmail.',
  ),
  ProviderPreset(
    provider: MailProvider.proton,
    label: 'Proton Mail',
    authMethod: AuthMethod.password,
    imapHost: '127.0.0.1',
    imapPort: 1143,
    smtpHost: '127.0.0.1',
    smtpPort: 1025,
    helpText: '⚠️ Proton Mail exige Proton Mail Bridge, un logiciel qui '
        'n\'existe que sur ordinateur (macOS/Windows/Linux) : ce compte ne '
        'peut pas se synchroniser directement depuis un téléphone. '
        'Renseignez les identifiants fournis par Bridge uniquement si un '
        'Bridge est joignable.',
  ),
  ProviderPreset(
    provider: MailProvider.imap,
    label: 'Autre (IMAP/SMTP)',
    authMethod: AuthMethod.password,
  ),
];
