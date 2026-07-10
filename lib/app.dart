import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/account_providers.dart';
import 'presentation/providers/core_providers.dart';
import 'presentation/router/app_router.dart';
import 'presentation/widgets/lock_overlay.dart';

class LemanMailApp extends ConsumerStatefulWidget {
  const LemanMailApp({super.key});

  @override
  ConsumerState<LemanMailApp> createState() => _LemanMailAppState();
}

class _LemanMailAppState extends ConsumerState<LemanMailApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        ref.read(appLifecycleProvider.notifier).state = state;
        // IDLE vit au premier plan uniquement : l'OS coupe les sockets en
        // arrière-plan, où la synchro périodique WorkManager prend le relais.
        if (state == AppLifecycleState.resumed) {
          _startIdle();
          // Rattrape ce qui est arrivé pendant l'arrière-plan.
          ref.read(syncControllerProvider.notifier).syncNow();
        } else if (state == AppLifecycleState.paused) {
          ref.read(imapIdleServiceProvider).stop();
          // Re-verrouille à la mise en arrière-plan si l'option est active.
          if (ref.read(appLockEnabledProvider).valueOrNull ?? false) {
            ref.read(appLockedProvider.notifier).state = true;
          }
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIdle());
  }

  Future<void> _startIdle() async {
    final accounts =
        await ref.read(accountRepositoryProvider).enabledAccounts();
    if (!mounted || accounts.isEmpty) return;
    await ref.read(imapIdleServiceProvider).start(
          accounts,
          ref.read(accountRepositoryProvider).credentialsOf,
        );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final locked = ref.watch(appLockedProvider);

    // Nouveau compte ajouté / supprimé → redémarre les écouteurs IDLE.
    ref.listen(accountsProvider, (previous, next) {
      if (previous?.valueOrNull?.length != next.valueOrNull?.length) {
        _startIdle();
      }
    });

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // L'écran de verrouillage recouvre le navigateur entier : rien
      // n'est visible ni interactif tant que la biométrie n'a pas réussi.
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          if (locked) const LockOverlay(),
        ],
      ),
    );
  }
}
