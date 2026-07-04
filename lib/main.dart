import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/security/secure_storage_service.dart';
import 'data/background/background_sync.dart';
import 'data/services/notifications/notification_service.dart';
import 'presentation/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');

  // Load (or create) the AES-256 master key before anything touches the
  // database — bodies are encrypted with it.
  final secureStorage = SecureStorageService();
  final masterKey = await secureStorage.obtainMasterKey();

  // App verrouillée dès le premier frame si la préférence est active :
  // aucun contenu ne doit être visible avant l'authentification.
  final lockAtLaunch =
      await secureStorage.readBool(AppConstants.appLockEnabledKey);

  // Notifications locales (canaux + permission) et synchro périodique
  // en arrière-plan — best effort : le démarrage de l'app ne doit jamais
  // échouer à cause d'un plugin de notification.
  final notifications = NotificationService();
  try {
    await notifications.init();
  } on Exception {
    // Permission refusée ou plugin indisponible : l'app reste utilisable.
  }
  await scheduleBackgroundSync();

  runApp(
    ProviderScope(
      overrides: [
        masterKeyProvider.overrideWithValue(masterKey),
        secureStorageProvider.overrideWithValue(secureStorage),
        notificationServiceProvider.overrideWithValue(notifications),
        appLockedProvider.overrideWith((ref) => lockAtLaunch),
      ],
      child: const LemanMailApp(),
    ),
  );
}
