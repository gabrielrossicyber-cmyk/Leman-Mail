import 'package:flutter_appauth/flutter_appauth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/error/failures.dart';
import '../../../domain/entities/account.dart';

/// OAuth 2.0 / OpenID Connect (authorization code + PKCE) via AppAuth.
///
/// Client ids are injected at build time (`--dart-define`) so no secret
/// ships in the repository:
///   flutter run --dart-define=GMAIL_CLIENT_ID=... --dart-define=MS_CLIENT_ID=...
class OAuthService {
  OAuthService([FlutterAppAuth? appAuth]) : _appAuth = appAuth ?? const FlutterAppAuth();

  final FlutterAppAuth _appAuth;

  static const _gmailClientId = String.fromEnvironment('GMAIL_CLIENT_ID');
  static const _microsoftClientId = String.fromEnvironment('MS_CLIENT_ID');

  static const _gmailScopes = [
    'openid',
    'email',
    'https://www.googleapis.com/auth/gmail.modify',
  ];

  static const _microsoftScopes = [
    'openid',
    'email',
    'offline_access',
    'https://graph.microsoft.com/Mail.ReadWrite',
    'https://graph.microsoft.com/Mail.Send',
  ];

  /// Runs the interactive authorization flow and returns tokens.
  Future<OAuthTokens> signIn(MailProvider provider) async {
    final config = _configFor(provider);
    try {
      final response = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          config.clientId,
          AppConstants.oauthRedirectUri,
          serviceConfiguration: config.endpoints,
          scopes: config.scopes,
          promptValues: const ['select_account'],
        ),
      );
      final accessToken = response.accessToken;
      if (accessToken == null) {
        throw const AuthenticationFailure('Autorisation annulée.');
      }
      return OAuthTokens(
        accessToken: accessToken,
        refreshToken: response.refreshToken,
        expiresAt: response.accessTokenExpirationDateTime,
        idToken: response.idToken,
      );
    } on Exception catch (e) {
      if (e is AuthenticationFailure) rethrow;
      throw AuthenticationFailure('Échec de la connexion OAuth.', cause: e);
    }
  }

  Future<OAuthTokens> refresh(
    MailProvider provider,
    String refreshToken,
  ) async {
    final config = _configFor(provider);
    try {
      final response = await _appAuth.token(
        TokenRequest(
          config.clientId,
          AppConstants.oauthRedirectUri,
          serviceConfiguration: config.endpoints,
          refreshToken: refreshToken,
          scopes: config.scopes,
        ),
      );
      return OAuthTokens(
        accessToken: response.accessToken ?? '',
        refreshToken: response.refreshToken ?? refreshToken,
        expiresAt: response.accessTokenExpirationDateTime,
        idToken: response.idToken,
      );
    } on Exception catch (e) {
      throw AuthenticationFailure(
        'Session expirée : reconnectez le compte.',
        cause: e,
      );
    }
  }

  _OAuthConfig _configFor(MailProvider provider) => switch (provider) {
        MailProvider.gmail => const _OAuthConfig(
            clientId: _gmailClientId,
            scopes: _gmailScopes,
            endpoints: AuthorizationServiceConfiguration(
              authorizationEndpoint:
                  'https://accounts.google.com/o/oauth2/v2/auth',
              tokenEndpoint: 'https://oauth2.googleapis.com/token',
            ),
          ),
        MailProvider.outlook ||
        MailProvider.microsoft365 =>
          const _OAuthConfig(
            clientId: _microsoftClientId,
            scopes: _microsoftScopes,
            endpoints: AuthorizationServiceConfiguration(
              authorizationEndpoint:
                  'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
              tokenEndpoint:
                  'https://login.microsoftonline.com/common/oauth2/v2.0/token',
            ),
          ),
        _ => throw AuthenticationFailure(
            'OAuth non supporté pour ${provider.name} — utilisez un mot de passe d\'application.',
          ),
      };
}

class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.idToken,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? idToken;

  bool get isExpired =>
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes: 2)));
}

class _OAuthConfig {
  const _OAuthConfig({
    required this.clientId,
    required this.scopes,
    required this.endpoints,
  });

  final String clientId;
  final List<String> scopes;
  final AuthorizationServiceConfiguration endpoints;
}
