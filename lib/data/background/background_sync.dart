import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/security/crypto_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../domain/usecases/analyze_incoming_email.dart';
import '../../features/anti_phishing/phishing_engine.dart';
import '../database/app_database.dart';
import '../repositories/account_repository_impl.dart';
import '../services/auth/oauth_service.dart';
import '../services/notifications/notification_service.dart';
import '../sync/sync_coordinator.dart';

/// Synchronisation périodique en arrière-plan.
///
/// Android : WorkManager, période minimale 15 min, avec contrainte réseau.
/// iOS : BGTaskScheduler (best effort — l'OS décide du moment ; nécessite
/// la configuration Info.plist documentée dans docs/DEPLOYMENT.md).
///
/// Prend le relais de l'IMAP IDLE (premier plan uniquement) jusqu'à ce que
/// les push serveur FCM/APNs existent (backend SaaS, roadmap T3).
const backgroundSyncTaskName = 'com.lemancybersecurity.lemanmail.sync';

/// Point d'entrée du worker : s'exécute dans un isolate dédié, sans
/// Riverpod — les dépendances sont construites à la main puis libérées.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = AppDatabase();
    try {
      final secureStorage = SecureStorageService();
      final masterKey = await secureStorage.obtainMasterKey();
      final coordinator = SyncCoordinator(
        db: db,
        accountRepository: AccountRepositoryImpl(db, secureStorage),
        analyzeEmail: AnalyzeIncomingEmail(phishingEngine: PhishingEngine()),
        crypto: CryptoService(masterKey),
        oauthService: OAuthService(),
      );

      final report = await coordinator.syncAllAccounts();

      if (report.newEmailCount > 0) {
        final notifications = NotificationService();
        // Pas de demande de permission depuis l'arrière-plan : elle a été
        // accordée (ou refusée) au premier plan.
        await notifications.init(requestPermissions: false);
        final first = report.highlights.isNotEmpty
            ? report.highlights.first
            : null;
        await notifications.showNewEmails(
          report.newEmailCount,
          preview: first == null
              ? null
              : '${first.fromName.isNotEmpty ? first.fromName : first.fromAddress} — ${first.subject}',
        );
        for (final threat in report.threats) {
          await notifications.showThreat(threat.subject, threat.fromAddress);
        }
      }
      return true;
    } on Object {
      // Réessayé à la prochaine fenêtre planifiée par l'OS.
      return false;
    } finally {
      await db.close();
    }
  });
}

/// À appeler une fois au démarrage de l'app (premier plan).
///
/// Ne doit JAMAIS faire échouer le démarrage : tout est best effort.
Future<void> scheduleBackgroundSync() async {
  try {
    await Workmanager().initialize(backgroundSyncDispatcher);
    if (Platform.isAndroid) {
      // registerPeriodicTask est une API Android (WorkManager).
      await Workmanager().registerPeriodicTask(
        'leman-mail-periodic-sync',
        backgroundSyncTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    }
    // iOS : la planification passe par BGTaskScheduler côté natif
    // (Info.plist + AppDelegate, voir docs/DEPLOYMENT.md). Tant que cette
    // configuration n'est pas en place, aucune tâche n'est enregistrée ici —
    // l'IDLE au premier plan et la synchro manuelle couvrent le besoin.
  } on Exception {
    // Plugin absent ou plateforme non configurée : l'app démarre quand même.
  }
}
