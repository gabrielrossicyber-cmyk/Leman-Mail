import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/services/mail/imap_service.dart';
import '../../data/services/mail/provider_presets.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/account_repository.dart';
import 'core_providers.dart';

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAccounts(),
);

/// Add-account flow: OAuth for Gmail/Microsoft, app password for IMAP.
class AddAccountController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> addOAuthAccount(ProviderPreset preset, String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final tokens =
          await ref.read(oauthServiceProvider).signIn(preset.provider);
      await ref.read(accountRepositoryProvider).addAccount(
            draft: Account(
              id: 0,
              uuid: const Uuid().v4(),
              email: email,
              displayName: email.split('@').first,
              provider: preset.provider,
              authMethod: AuthMethod.oauth2,
              mfaEnabled: true,
            ),
            credentials: AccountCredentials(
              accessToken: tokens.accessToken,
              refreshToken: tokens.refreshToken,
              tokenExpiry: tokens.expiresAt,
            ),
          );
      await ref.read(syncControllerProvider.notifier).syncNow();
    });
  }

  Future<void> addImapAccount({
    required ProviderPreset preset,
    required String email,
    required String password,
    String? imapHost,
    int? imapPort,
    String? smtpHost,
    int? smtpPort,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final draft = Account(
        id: 0,
        uuid: const Uuid().v4(),
        email: email,
        displayName: email.split('@').first,
        provider: preset.provider,
        authMethod: AuthMethod.password,
        imapHost: imapHost ?? preset.imapHost,
        imapPort: imapPort ?? preset.imapPort,
        smtpHost: smtpHost ?? preset.smtpHost,
        smtpPort: smtpPort ?? preset.smtpPort,
      );

      // Validate the credentials against the real server BEFORE saving:
      // a wrong password or unreachable host must fail here, visibly,
      // not silently during the first background sync.
      final probe = ImapService();
      try {
        await probe.connect(draft, secret: password);
      } finally {
        await probe.disconnect();
      }

      await ref.read(accountRepositoryProvider).addAccount(
            draft: draft,
            credentials: AccountCredentials(password: password),
          );
      await ref.read(syncControllerProvider.notifier).syncNow();
    });
  }
}

final addAccountControllerProvider =
    AsyncNotifierProvider<AddAccountController, void>(AddAccountController.new);

/// Global sync state ("N nouveaux emails", pull-to-refresh, ...).
class SyncController extends AsyncNotifier<int> {
  @override
  Future<int> build() async => 0;

  Future<void> syncNow() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final count =
          await ref.read(syncCoordinatorProvider).syncAllAccounts();
      // Refresh the health score after every sync.
      await ref.read(computeInboxHealthProvider).call();
      return count;
    });
  }
}

final syncControllerProvider =
    AsyncNotifierProvider<SyncController, int>(SyncController.new);
