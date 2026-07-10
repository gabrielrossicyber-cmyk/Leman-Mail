import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/domain/entities/inbox_health.dart';
import 'package:leman_mail/features/health/inbox_health_calculator.dart';

InboxStats stats({
  int totalEmails = 1000,
  int unreadCount = 0,
  int newsletterCount = 0,
  int activeNewsletterSenders = 0,
  int ignoredNewsletterSenders = 0,
  int oldUnreadCount = 0,
  int spfPassCount = 1000,
  int dkimPassCount = 1000,
  int dmarcPassCount = 1000,
  int authEvaluatedCount = 1000,
  int highRiskCount = 0,
  int mediumRiskCount = 0,
  int suspiciousDomainsBlocked = 0,
  int trackedEmailCount = 0,
  int trackerTotal = 0,
  int answeredNeededCount = 100,
  int unansweredCount = 0,
}) =>
    InboxStats(
      totalEmails: totalEmails,
      unreadCount: unreadCount,
      newsletterCount: newsletterCount,
      activeNewsletterSenders: activeNewsletterSenders,
      ignoredNewsletterSenders: ignoredNewsletterSenders,
      oldUnreadCount: oldUnreadCount,
      spfPassCount: spfPassCount,
      dkimPassCount: dkimPassCount,
      dmarcPassCount: dmarcPassCount,
      authEvaluatedCount: authEvaluatedCount,
      highRiskCount: highRiskCount,
      mediumRiskCount: mediumRiskCount,
      suspiciousDomainsBlocked: suspiciousDomainsBlocked,
      trackedEmailCount: trackedEmailCount,
      trackerTotal: trackerTotal,
      answeredNeededCount: answeredNeededCount,
      unansweredCount: unansweredCount,
    );

void main() {
  const calculator = InboxHealthCalculator();

  group('InboxHealthCalculator', () {
    test('boîte parfaite → score excellent (>= 90)', () {
      final health = calculator.compute(stats());
      expect(health.totalScore, greaterThanOrEqualTo(90));
      expect(health.grade, HealthGrade.excellent);
      expect(health.risks, isEmpty);
      expect(health.strengths, isNotEmpty);
    });

    test('boîte vide → tous les sous-scores à 100', () {
      final health = calculator.compute(
        stats(
          totalEmails: 0,
          authEvaluatedCount: 0,
          spfPassCount: 0,
          dkimPassCount: 0,
          dmarcPassCount: 0,
          answeredNeededCount: 0,
        ),
      );
      expect(health.clutterScore, 100);
      expect(health.privacyScore, 100);
      expect(health.organizationScore, 100);
    });

    test('phishing massif → sécurité et note globale s\'effondrent', () {
      final health = calculator.compute(
        stats(highRiskCount: 8, mediumRiskCount: 20),
      );
      expect(health.securityScore, lessThan(50));
      expect(health.risks, isNotEmpty);
      expect(
        health.recommendations.any((r) => r.message.contains('risque élevé')),
        isTrue,
      );
    });

    test('encombrement : beaucoup de non lus → clutter dégradé', () {
      final clean = calculator.compute(stats());
      final cluttered = calculator.compute(
        stats(unreadCount: 400, newsletterCount: 300, oldUnreadCount: 150),
      );
      expect(cluttered.clutterScore, lessThan(clean.clutterScore));
      expect(cluttered.improvements, isNotEmpty);
    });

    test('trackers → vie privée dégradée + recommandation', () {
      final health = calculator.compute(
        stats(trackedEmailCount: 400, trackerTotal: 900),
      );
      expect(health.privacyScore, lessThan(60));
      expect(
        health.recommendations
            .any((r) => r.message.contains('images distantes')),
        isTrue,
      );
    });

    test('newsletters ignorées → recommandation de désabonnement', () {
      final health = calculator.compute(stats(ignoredNewsletterSenders: 12));
      expect(
        health.recommendations.any(
          (r) => r.message.contains('Désabonnez-vous de 12 newsletters'),
        ),
        isTrue,
      );
    });

    test('les grades correspondent aux seuils produit', () {
      expect(_gradeFor(95), HealthGrade.excellent);
      expect(_gradeFor(75), HealthGrade.good);
      expect(_gradeFor(55), HealthGrade.average);
      expect(_gradeFor(20), HealthGrade.critical);
    });

    test('les recommandations sont triées par impact décroissant', () {
      final health = calculator.compute(
        stats(
          highRiskCount: 3,
          unreadCount: 300,
          ignoredNewsletterSenders: 6,
          unansweredCount: 12,
          trackedEmailCount: 50,
        ),
      );
      for (var i = 1; i < health.recommendations.length; i++) {
        expect(
          health.recommendations[i - 1].impact,
          greaterThanOrEqualTo(health.recommendations[i].impact),
        );
      }
    });
  });
}

HealthGrade _gradeFor(int score) => InboxHealth(
      totalScore: score,
      securityScore: score,
      clutterScore: score,
      privacyScore: score,
      organizationScore: score,
      strengths: const [],
      improvements: const [],
      risks: const [],
      recommendations: const [],
      computedAt: DateTime(2026),
    ).grade;
