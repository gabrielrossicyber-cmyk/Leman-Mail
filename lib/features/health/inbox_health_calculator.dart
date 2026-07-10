import '../../domain/entities/inbox_health.dart';

/// Raw mailbox statistics consumed by the health calculator. Produced by
/// the repositories from SQLite aggregates — the calculator itself is pure.
class InboxStats {
  const InboxStats({
    required this.totalEmails,
    required this.unreadCount,
    required this.newsletterCount,
    required this.activeNewsletterSenders,
    required this.ignoredNewsletterSenders,
    required this.oldUnreadCount,
    required this.spfPassCount,
    required this.dkimPassCount,
    required this.dmarcPassCount,
    required this.authEvaluatedCount,
    required this.highRiskCount,
    required this.mediumRiskCount,
    required this.suspiciousDomainsBlocked,
    required this.trackedEmailCount,
    required this.trackerTotal,
    required this.answeredNeededCount,
    required this.unansweredCount,
  });

  final int totalEmails;
  final int unreadCount;
  final int newsletterCount;
  final int activeNewsletterSenders;

  /// Newsletter senders the user never reads (unsubscribe candidates).
  final int ignoredNewsletterSenders;
  final int oldUnreadCount;

  // Authentication statistics over analyzed emails.
  final int spfPassCount;
  final int dkimPassCount;
  final int dmarcPassCount;
  final int authEvaluatedCount;

  // Threats.
  final int highRiskCount;
  final int mediumRiskCount;
  final int suspiciousDomainsBlocked;

  // Privacy.
  final int trackedEmailCount;
  final int trackerTotal;

  // Organization.
  final int answeredNeededCount;
  final int unansweredCount;
}

/// **Inbox Health Score** — proprietary 0-100 mailbox rating.
///
/// Four weighted dimensions:
///  - Sécurité (35 %)      : auth SPF/DKIM/DMARC, emails à risque
///  - Encombrement (25 %)  : non lus, newsletters, ancienneté
///  - Vie privée (20 %)    : trackers et pixels
///  - Organisation (20 %)  : emails traités / sans réponse
///
/// 90-100 Excellent · 70-89 Bon · 50-69 Moyen · 0-49 Critique.
class InboxHealthCalculator {
  const InboxHealthCalculator();

  static const securityWeight = 0.35;
  static const clutterWeight = 0.25;
  static const privacyWeight = 0.20;
  static const organizationWeight = 0.20;

  InboxHealth compute(InboxStats stats, {DateTime? now}) {
    final security = _securityScore(stats);
    final clutter = _clutterScore(stats);
    final privacy = _privacyScore(stats);
    final organization = _organizationScore(stats);

    final total = (security * securityWeight +
            clutter * clutterWeight +
            privacy * privacyWeight +
            organization * organizationWeight)
        .round()
        .clamp(0, 100);

    final strengths = <String>[];
    final improvements = <String>[];
    final risks = <String>[];
    final recommendations = <HealthRecommendation>[];

    // --- Security narrative -------------------------------------------------
    final authRatio = stats.authEvaluatedCount == 0
        ? 1.0
        : (stats.spfPassCount + stats.dkimPassCount) /
            (2 * stats.authEvaluatedCount);
    if (authRatio >= 0.9) {
      strengths.add('SPF et DKIM excellents sur vos emails entrants');
    }
    if (stats.highRiskCount == 0) {
      strengths.add('Très peu de phishing détecté');
    } else {
      risks.add(
        '${stats.highRiskCount} email(s) à risque élevé dans votre boîte',
      );
      recommendations.add(
        HealthRecommendation(
          message:
              'Supprimez ou signalez les ${stats.highRiskCount} emails à risque élevé',
          impact: (stats.highRiskCount * 3).clamp(3, 15),
        ),
      );
    }
    if (stats.mediumRiskCount > 0) {
      improvements.add('${stats.mediumRiskCount} email(s) suspect(s) à vérifier');
    }

    // --- Clutter narrative --------------------------------------------------
    if (stats.unreadCount == 0) {
      strengths.add('Inbox Zero atteint — aucun email non lu');
    } else if (stats.unreadCount > 50) {
      improvements.add('${stats.unreadCount} emails non lus');
      recommendations.add(
        HealthRecommendation(
          message:
              'Traitez ou archivez ${(stats.unreadCount * 0.2).ceil()} emails non lus cette semaine',
          impact: 8,
        ),
      );
    }
    if (stats.ignoredNewsletterSenders > 0) {
      improvements.add(
        '${stats.ignoredNewsletterSenders} newsletters inutilisées',
      );
      recommendations.add(
        HealthRecommendation(
          message:
              'Désabonnez-vous de ${stats.ignoredNewsletterSenders} newsletters que vous ne lisez jamais',
          impact: (stats.ignoredNewsletterSenders * 2).clamp(2, 12),
        ),
      );
    }

    // --- Privacy narrative --------------------------------------------------
    if (stats.trackedEmailCount == 0) {
      strengths.add('Aucun tracker actif détecté');
    } else {
      improvements.add(
        '${stats.trackedEmailCount} emails contenant des trackers',
      );
      recommendations.add(
        const HealthRecommendation(
          message: 'Gardez le blocage automatique des images distantes activé',
          impact: 4,
        ),
      );
    }

    // --- Organization narrative ---------------------------------------------
    if (stats.unansweredCount > 5) {
      improvements.add('${stats.unansweredCount} emails en attente de réponse');
      recommendations.add(
        HealthRecommendation(
          message: 'Répondez aux ${stats.unansweredCount} messages en attente',
          impact: 6,
        ),
      );
    }

    return InboxHealth(
      totalScore: total,
      securityScore: security,
      clutterScore: clutter,
      privacyScore: privacy,
      organizationScore: organization,
      strengths: strengths,
      improvements: improvements,
      risks: risks,
      recommendations: recommendations
        ..sort((a, b) => b.impact.compareTo(a.impact)),
      computedAt: now ?? DateTime.now(),
    );
  }

  int _securityScore(InboxStats s) {
    var score = 100.0;
    if (s.authEvaluatedCount > 0) {
      final spfRatio = s.spfPassCount / s.authEvaluatedCount;
      final dkimRatio = s.dkimPassCount / s.authEvaluatedCount;
      final dmarcRatio = s.dmarcPassCount / s.authEvaluatedCount;
      // Up to 30 points tied to authentication quality of received mail.
      score -= (1 - spfRatio) * 10 + (1 - dkimRatio) * 10 + (1 - dmarcRatio) * 10;
    }
    // Each present threat weighs heavily.
    score -= s.highRiskCount * 12;
    score -= s.mediumRiskCount * 3;
    return score.round().clamp(0, 100);
  }

  int _clutterScore(InboxStats s) {
    if (s.totalEmails == 0) return 100;
    var score = 100.0;
    final unreadRatio = s.unreadCount / s.totalEmails;
    score -= (unreadRatio * 120).clamp(0, 45); // >37% unread = -45
    final newsletterRatio = s.newsletterCount / s.totalEmails;
    score -= (newsletterRatio * 60).clamp(0, 25);
    score -= (s.oldUnreadCount / s.totalEmails * 100).clamp(0, 20);
    score -= (s.ignoredNewsletterSenders * 1.5).clamp(0, 10);
    return score.round().clamp(0, 100);
  }

  int _privacyScore(InboxStats s) {
    if (s.totalEmails == 0) return 100;
    var score = 100.0;
    score -= (s.trackedEmailCount / s.totalEmails * 150).clamp(0, 60);
    score -= (s.trackerTotal / s.totalEmails * 20).clamp(0, 20);
    return score.round().clamp(0, 100);
  }

  int _organizationScore(InboxStats s) {
    if (s.answeredNeededCount == 0) return 100;
    final handledRatio =
        1 - (s.unansweredCount / s.answeredNeededCount).clamp(0.0, 1.0);
    return (40 + handledRatio * 60).round().clamp(0, 100);
  }
}
