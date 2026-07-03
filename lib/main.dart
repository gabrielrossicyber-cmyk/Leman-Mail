import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/security/secure_storage_service.dart';
import 'presentation/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');

  // Load (or create) the AES-256 master key before anything touches the
  // database — bodies are encrypted with it.
  final secureStorage = SecureStorageService();
  final masterKey = await secureStorage.obtainMasterKey();

  runApp(
    ProviderScope(
      overrides: [
        masterKeyProvider.overrideWithValue(masterKey),
        secureStorageProvider.overrideWithValue(secureStorage),
      ],
      child: const LemanMailApp(),
    ),
  );
}
