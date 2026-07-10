import '../entities/inbox_health.dart';

enum HealthPeriod { week, month, quarter, year }

extension HealthPeriodDuration on HealthPeriod {
  Duration get duration => switch (this) {
        HealthPeriod.week => const Duration(days: 7),
        HealthPeriod.month => const Duration(days: 30),
        HealthPeriod.quarter => const Duration(days: 90),
        HealthPeriod.year => const Duration(days: 365),
      };
}

abstract interface class HealthRepository {
  /// Persists today's computation (one snapshot per day, overwritten).
  Future<void> saveDailySnapshot(InboxHealth health, {int? accountId});

  Future<List<HealthSnapshot>> history(
    HealthPeriod period, {
    int? accountId,
  });

  Future<Set<String>> unlockedBadgeIds();
  Future<void> unlockBadges(Set<String> badgeIds);
}
