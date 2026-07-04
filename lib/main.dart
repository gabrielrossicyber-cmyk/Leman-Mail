import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
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

  // Notifications locales (canaux + permission) et synchro périodique
  // en arrière-plan.
  final notifications = NotificationService();
  await notifications.init();
  await scheduleBackgroundSync();

  runApp(
    ProviderScope(
      overrides: [
        masterKeyProvider.overrideWithValue(masterKey),
        secureStorageProvider.overrideWithValue(secureStorage),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const LemanMailApp(),
    ),
  );
}
