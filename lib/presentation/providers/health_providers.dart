import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/badge.dart';
import '../../domain/entities/inbox_health.dart';
import '../../domain/repositories/health_repository.dart';
import '../../features/gamification/badge_engine.dart';
import 'core_providers.dart';

/// Current Inbox Health Score (recomputed when watched).
final inboxHealthProvider = FutureProvider<InboxHealth>(
  (ref) => ref.watch(computeInboxHealthProvider).call(),
);

final healthPeriodProvider =
    StateProvider<HealthPeriod>((ref) => HealthPeriod.month);

final healthHistoryProvider = FutureProvider<List<HealthSnapshot>>((ref) {
  final period = ref.watch(healthPeriodProvider);
  return ref.watch(healthRepositoryProvider).history(period);
});

final badgesProvider = FutureProvider<List<GamificationBadge>>((ref) async {
  final unlocked =
      await ref.watch(healthRepositoryProvider).unlockedBadgeIds();
  final now = DateTime.now();
  return [
    for (final badge in BadgeEngine.definitions)
      unlocked.contains(badge.id) ? badge.unlock(now) : badge,
  ];
});
