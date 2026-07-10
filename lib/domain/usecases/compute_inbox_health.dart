import '../../features/gamification/badge_engine.dart';
import '../../features/health/inbox_health_calculator.dart';
import '../entities/inbox_health.dart';
import '../repositories/email_repository.dart';
import '../repositories/health_repository.dart';

/// Use case: recompute the Inbox Health Score, persist today's snapshot
/// and award any newly earned badges. Triggered after each sync and once
/// a day by the background scheduler.
class ComputeInboxHealth {
  const ComputeInboxHealth({
    required this.emailRepository,
    required this.healthRepository,
    this.calculator = const InboxHealthCalculator(),
    this.badgeEngine = const BadgeEngine(),
  });

  final EmailRepository emailRepository;
  final HealthRepository healthRepository;
  final InboxHealthCalculator calculator;
  final BadgeEngine badgeEngine;

  Future<InboxHealth> call({
    int highRiskDeleted = 0,
    int trackersBlocked = 0,
    int newslettersUnsubscribed = 0,
    int spamBlockedSenders = 0,
    int daysActive = 0,
  }) async {
    final stats = await emailRepository.collectStats();
    final health = calculator.compute(stats);
    await healthRepository.saveDailySnapshot(health);

    final unlocked = await healthRepository.unlockedBadgeIds();
    final newBadges = badgeEngine.evaluate(
      BadgeEngine.statsFrom(
        stats,
        highRiskDeleted: highRiskDeleted,
        trackersBlocked: trackersBlocked,
        newslettersUnsubscribed: newslettersUnsubscribed,
        spamBlockedSenders: spamBlockedSenders,
        healthScore: health.totalScore,
        daysActive: daysActive,
      ),
      unlocked,
    );
    if (newBadges.isNotEmpty) {
      await healthRepository.unlockBadges(newBadges);
    }

    return health;
  }
}
