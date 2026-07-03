import '../../domain/entities/badge.dart';
import '../health/inbox_health_calculator.dart';

/// User activity counters relevant to badges, accumulated in the database.
class GamificationStats {
  const GamificationStats({
    required this.unreadCount,
    required this.highRiskDeleted,
    required this.trackersBlocked,
    required this.newslettersUnsubscribed,
    required this.spamBlockedSenders,
    required this.healthScore,
    required this.daysActive,
  });

  final int unreadCount;
  final int highRiskDeleted;
  final int trackersBlocked;
  final int newslettersUnsubscribed;
  final int spamBlockedSenders;
  final int healthScore;
  final int daysActive;
}

/// Awards badges automatically from mailbox stats. Pure + deterministic:
/// the caller persists newly unlocked ids and shows the celebration UI.
class BadgeEngine {
  const BadgeEngine();

  static const definitions = <GamificationBadge>[
    GamificationBadge(
      id: 'inbox_clean',
      emoji: '🏆',
      title: 'Inbox Clean',
      description: 'Atteindre zéro email non lu.',
    ),
    GamificationBadge(
      id: 'security_defender',
      emoji: '🏆',
      title: 'Security Defender',
      description: 'Supprimer ou signaler 10 emails à risque élevé.',
    ),
    GamificationBadge(
      id: 'privacy_guardian',
      emoji: '🏆',
      title: 'Privacy Guardian',
      description: 'Bloquer 100 trackers.',
    ),
    GamificationBadge(
      id: 'newsletter_killer',
      emoji: '🏆',
      title: 'Newsletter Killer',
      description: 'Se désabonner de 20 newsletters.',
    ),
    GamificationBadge(
      id: 'zero_spam',
      emoji: '🏆',
      title: 'Zero Spam',
      description: 'Bloquer 10 expéditeurs indésirables.',
    ),
    GamificationBadge(
      id: 'mail_master',
      emoji: '🏆',
      title: 'Mail Master',
      description: 'Maintenir un Inbox Health Score ≥ 90 pendant 30 jours.',
    ),
  ];

  /// Returns the ids newly unlocked given current [stats] and the ids
  /// already unlocked.
  Set<String> evaluate(GamificationStats stats, Set<String> alreadyUnlocked) {
    final unlocked = <String>{};

    void check(String id, bool condition) {
      if (condition && !alreadyUnlocked.contains(id)) unlocked.add(id);
    }

    check('inbox_clean', stats.unreadCount == 0);
    check('security_defender', stats.highRiskDeleted >= 10);
    check('privacy_guardian', stats.trackersBlocked >= 100);
    check('newsletter_killer', stats.newslettersUnsubscribed >= 20);
    check('zero_spam', stats.spamBlockedSenders >= 10);
    check('mail_master', stats.healthScore >= 90 && stats.daysActive >= 30);

    return unlocked;
  }

  /// Convenience: builds [GamificationStats] partially from [InboxStats].
  static GamificationStats statsFrom(
    InboxStats inbox, {
    required int highRiskDeleted,
    required int trackersBlocked,
    required int newslettersUnsubscribed,
    required int spamBlockedSenders,
    required int healthScore,
    required int daysActive,
  }) =>
      GamificationStats(
        unreadCount: inbox.unreadCount,
        highRiskDeleted: highRiskDeleted,
        trackersBlocked: trackersBlocked,
        newslettersUnsubscribed: newslettersUnsubscribed,
        spamBlockedSenders: spamBlockedSenders,
        healthScore: healthScore,
        daysActive: daysActive,
      );
}
