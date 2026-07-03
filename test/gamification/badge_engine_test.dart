import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/features/gamification/badge_engine.dart';

GamificationStats stats({
  int unread = 100,
  int highRiskDeleted = 0,
  int trackersBlocked = 0,
  int unsubscribed = 0,
  int blockedSenders = 0,
  int healthScore = 50,
  int daysActive = 1,
}) =>
    GamificationStats(
      unreadCount: unread,
      highRiskDeleted: highRiskDeleted,
      trackersBlocked: trackersBlocked,
      newslettersUnsubscribed: unsubscribed,
      spamBlockedSenders: blockedSenders,
      healthScore: healthScore,
      daysActive: daysActive,
    );

void main() {
  const engine = BadgeEngine();

  group('BadgeEngine', () {
    test('aucun badge sans progrès', () {
      expect(engine.evaluate(stats(), {}), isEmpty);
    });

    test('inbox zéro → Inbox Clean', () {
      expect(engine.evaluate(stats(unread: 0), {}), contains('inbox_clean'));
    });

    test('badges déjà débloqués non re-décernés', () {
      final unlocked = engine.evaluate(stats(unread: 0), {'inbox_clean'});
      expect(unlocked, isNot(contains('inbox_clean')));
    });

    test('tous les badges atteignables simultanément', () {
      final unlocked = engine.evaluate(
        stats(
          unread: 0,
          highRiskDeleted: 10,
          trackersBlocked: 150,
          unsubscribed: 25,
          blockedSenders: 12,
          healthScore: 92,
          daysActive: 31,
        ),
        {},
      );
      expect(
        unlocked,
        containsAll([
          'inbox_clean',
          'security_defender',
          'privacy_guardian',
          'newsletter_killer',
          'zero_spam',
          'mail_master',
        ]),
      );
    });

    test('mail_master exige 30 jours ET score >= 90', () {
      expect(
        engine.evaluate(stats(healthScore: 95, daysActive: 5), {}),
        isNot(contains('mail_master')),
      );
      expect(
        engine.evaluate(stats(healthScore: 85, daysActive: 40), {}),
        isNot(contains('mail_master')),
      );
    });

    test('les définitions couvrent les 6 badges produit', () {
      expect(BadgeEngine.definitions.map((b) => b.id).toSet(), {
        'inbox_clean',
        'security_defender',
        'privacy_guardian',
        'newsletter_killer',
        'zero_spam',
        'mail_master',
      });
    });
  });
}
