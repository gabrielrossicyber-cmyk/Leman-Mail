import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/account_providers.dart';
import '../screens/accounts/add_account_screen.dart';
import '../screens/cleanup/smart_cleanup_screen.dart';
import '../screens/compose/compose_screen.dart';
import '../screens/home/home_shell.dart';
import '../screens/inbox/email_detail_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/settings/settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // First launch → onboarding until an account exists.
      final accounts = ref.read(accountsProvider).valueOrNull;
      final onOnboarding = state.matchedLocation == '/onboarding' ||
          state.matchedLocation == '/add-account';
      if (accounts != null && accounts.isEmpty && !onOnboarding) {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/add-account',
        builder: (context, state) => const AddAccountScreen(),
      ),
      GoRoute(
        path: '/email/:id',
        builder: (context, state) => EmailDetailScreen(
          emailId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/compose',
        builder: (context, state) => ComposeScreen(
          initialTo: state.uri.queryParameters['to'],
          initialSubject: state.uri.queryParameters['subject'],
          initialBody: state.uri.queryParameters['body'],
        ),
      ),
      GoRoute(
        path: '/cleanup',
        builder: (context, state) => const SmartCleanupScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
