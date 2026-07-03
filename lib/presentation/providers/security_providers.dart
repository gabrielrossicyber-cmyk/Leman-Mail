import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/security_recommendation.dart';
import '../../features/health/inbox_health_calculator.dart';
import 'core_providers.dart';

/// Statistics behind the cybersecurity dashboard tiles.
final dashboardStatsProvider = FutureProvider<InboxStats>(
  (ref) => ref.watch(emailRepositoryProvider).collectStats(),
);

/// Security Center posture (global score + recommendations).
final securityPostureProvider = FutureProvider<SecurityPosture>((ref) async {
  final accounts =
      await ref.watch(accountRepositoryProvider).enabledAccounts();
  final stats = await ref.watch(emailRepositoryProvider).collectStats();
  final newsletters =
      await ref.watch(newsletterRepositoryProvider).activeCount();
  return ref.watch(securityCenterEngineProvider).evaluate(
        accounts: accounts,
        stats: stats,
        activeNewsletterSenders: newsletters,
      );
});
