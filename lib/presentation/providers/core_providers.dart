import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/security/biometric_service.dart';
import '../../core/security/crypto_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/account_repository_impl.dart';
import '../../data/repositories/email_repository_impl.dart';
import '../../data/repositories/health_repository_impl.dart';
import '../../data/repositories/newsletter_repository_impl.dart';
import '../../data/services/auth/oauth_service.dart';
import '../../data/services/mail/attachment_service.dart';
import '../../data/services/notifications/notification_service.dart';
import '../../data/sync/sync_coordinator.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/email_repository.dart';
import '../../domain/repositories/health_repository.dart';
import '../../domain/repositories/newsletter_repository.dart';
import '../../domain/usecases/analyze_incoming_email.dart';
import '../../domain/usecases/compute_inbox_health.dart';
import '../../domain/usecases/run_newsletter_cleanup.dart';
import '../../features/anti_phishing/phishing_engine.dart';
import '../../features/cleanup/smart_cleanup_analyzer.dart';
import '../../features/security_center/security_center_engine.dart';

/// Dependency injection root. Long-lived singletons live here; screens
/// consume them through feature providers.
///
/// [masterKeyProvider] is overridden in `main.dart` after the key is
/// loaded from secure storage (async work done before `runApp`).
final masterKeyProvider = Provider<List<int>>(
  (ref) => throw UnimplementedError('Overridden at bootstrap'),
);

final secureStorageProvider =
    Provider<SecureStorageService>((ref) => SecureStorageService());

final biometricServiceProvider =
    Provider<BiometricService>((ref) => BiometricService());

final cryptoServiceProvider = Provider<CryptoService>(
  (ref) => CryptoService(ref.watch(masterKeyProvider)),
);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final oauthServiceProvider = Provider<OAuthService>((ref) => OAuthService());

/// État du cycle de vie de l'app — alimenté par [LemanMailApp] ; permet de
/// ne notifier que lorsque l'app n'est pas visible.
final appLifecycleProvider =
    StateProvider<AppLifecycleState>((ref) => AppLifecycleState.resumed);

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

/// Verrouillage biométrique : préférence persistée en secure storage.
class AppLockEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref
      .read(secureStorageProvider)
      .readBool(AppConstants.appLockEnabledKey);

  /// Active/désactive le verrouillage. L'activation exige une
  /// authentification biométrique réussie (preuve que l'appareil la
  /// supporte — sinon l'utilisateur s'enfermerait dehors).
  Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      final ok = await ref
          .read(biometricServiceProvider)
          .authenticate(reason: 'Activer le verrouillage de Leman Mail');
      if (!ok) return false;
    }
    await ref
        .read(secureStorageProvider)
        .writeBool(AppConstants.appLockEnabledKey, enabled);
    state = AsyncData(enabled);
    if (!enabled) {
      ref.read(appLockedProvider.notifier).state = false;
    }
    return true;
  }
}

final appLockEnabledProvider =
    AsyncNotifierProvider<AppLockEnabledNotifier, bool>(
  AppLockEnabledNotifier.new,
);

/// L'app est-elle actuellement verrouillée ? Initialisé au démarrage
/// (override dans main.dart) et re-verrouillé à chaque mise en
/// arrière-plan quand la préférence est active.
final appLockedProvider = StateProvider<bool>((ref) => false);

// ---- Engines ---------------------------------------------------------------

final phishingEngineProvider =
    Provider<PhishingEngine>((ref) => PhishingEngine());

final smartCleanupAnalyzerProvider =
    Provider<SmartCleanupAnalyzer>((ref) => const SmartCleanupAnalyzer());

final securityCenterEngineProvider =
    Provider<SecurityCenterEngine>((ref) => const SecurityCenterEngine());

// ---- Repositories ----------------------------------------------------------

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepositoryImpl(
    ref.watch(databaseProvider),
    ref.watch(secureStorageProvider),
  ),
);

final emailRepositoryProvider = Provider<EmailRepository>(
  (ref) => EmailRepositoryImpl(
    ref.watch(databaseProvider),
    ref.watch(cryptoServiceProvider),
  ),
);

final newsletterRepositoryProvider = Provider<NewsletterRepository>(
  (ref) => NewsletterRepositoryImpl(ref.watch(databaseProvider)),
);

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepositoryImpl(ref.watch(databaseProvider)),
);

// ---- Use cases -------------------------------------------------------------

final analyzeIncomingEmailProvider = Provider<AnalyzeIncomingEmail>(
  (ref) => AnalyzeIncomingEmail(
    phishingEngine: ref.watch(phishingEngineProvider),
  ),
);

final computeInboxHealthProvider = Provider<ComputeInboxHealth>(
  (ref) => ComputeInboxHealth(
    emailRepository: ref.watch(emailRepositoryProvider),
    healthRepository: ref.watch(healthRepositoryProvider),
  ),
);

final runNewsletterCleanupProvider = Provider<RunNewsletterCleanup>(
  (ref) => RunNewsletterCleanup(ref.watch(newsletterRepositoryProvider)),
);

final attachmentServiceProvider = Provider<AttachmentService>(
  (ref) => AttachmentService(
    ref.watch(databaseProvider),
    ref.watch(accountRepositoryProvider),
  ),
);

/// Brouillons locaux (auto-sauvegardés depuis la composition).
final draftsProvider = StreamProvider(
  (ref) => ref.watch(databaseProvider).watchDrafts(),
);

final syncCoordinatorProvider = Provider<SyncCoordinator>(
  (ref) => SyncCoordinator(
    db: ref.watch(databaseProvider),
    accountRepository: ref.watch(accountRepositoryProvider),
    analyzeEmail: ref.watch(analyzeIncomingEmailProvider),
    crypto: ref.watch(cryptoServiceProvider),
    oauthService: ref.watch(oauthServiceProvider),
  ),
);
