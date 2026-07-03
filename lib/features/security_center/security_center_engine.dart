import '../../domain/entities/account.dart';
import '../../domain/entities/security_recommendation.dart';
import '../health/inbox_health_calculator.dart';

/// **Security Center** — Microsoft-Secure-Score-inspired posture engine.
///
/// Consumes the account list and mailbox statistics, produces:
///  - a global score (0-100),
///  - per-account scores,
///  - dedicated phishing & privacy sub-scores,
///  - point-valued recommendations ("+5 Activer MFA", ...).
class SecurityCenterEngine {
  const SecurityCenterEngine();

  SecurityPosture evaluate({
    required List<Account> accounts,
    required InboxStats stats,
    required int activeNewsletterSenders,
  }) {
    final recommendations = <SecurityRecommendation>[];
    final accountScores = <String, int>{};

    // --- Per-account posture ------------------------------------------------
    for (final account in accounts) {
      var accountScore = 100;
      if (!account.usesOAuth) {
        accountScore -= 20;
        recommendations.add(
          SecurityRecommendation(
            code: 'use_oauth_${account.uuid}',
            title: 'Passer ${account.email} en OAuth 2.0',
            description:
                'La connexion par mot de passe est moins sûre qu\'OAuth avec MFA.',
            points: 4,
            accountUuid: account.uuid,
          ),
        );
      }
      if (!account.mfaEnabled) {
        accountScore -= 30;
        recommendations.add(
          SecurityRecommendation(
            code: 'enable_mfa_${account.uuid}',
            title: 'Activer MFA sur ${account.email}',
            description:
                'L\'authentification multifacteur bloque plus de 99 % des '
                'compromissions de comptes.',
            points: 5,
            accountUuid: account.uuid,
          ),
        );
      }
      if (!account.imapTls && account.imapHost != null) {
        accountScore -= 25;
        recommendations.add(
          SecurityRecommendation(
            code: 'enable_tls_${account.uuid}',
            title: 'Activer TLS pour ${account.email}',
            description: 'La connexion IMAP de ce compte n\'est pas chiffrée.',
            points: 8,
            accountUuid: account.uuid,
          ),
        );
      }
      accountScores[account.uuid] = accountScore.clamp(0, 100);
    }

    // --- Phishing sub-score -------------------------------------------------
    var phishingScore = 100;
    phishingScore -= stats.highRiskCount * 10;
    phishingScore -= stats.mediumRiskCount * 2;
    phishingScore = phishingScore.clamp(0, 100);
    if (stats.highRiskCount > 0) {
      recommendations.add(
        SecurityRecommendation(
          code: 'block_suspicious_domains',
          title: 'Bloquer les domaines suspects détectés',
          description:
              '${stats.highRiskCount} emails à risque élevé proviennent de '
              'domaines que vous pouvez bloquer définitivement.',
          points: 8,
        ),
      );
    }

    // --- Privacy sub-score --------------------------------------------------
    var privacyScore = 100;
    if (stats.totalEmails > 0) {
      privacyScore -=
          (stats.trackedEmailCount / stats.totalEmails * 100).round();
    }
    privacyScore = privacyScore.clamp(0, 100);
    if (stats.trackedEmailCount > 0) {
      recommendations.add(
        const SecurityRecommendation(
          code: 'reduce_trackers',
          title: 'Réduire les trackers',
          description:
              'Maintenez le blocage des images distantes et désabonnez-vous '
              'des expéditeurs les plus intrusifs.',
          points: 2,
        ),
      );
    }

    // --- Hygiene ------------------------------------------------------------
    if (activeNewsletterSenders >= 10) {
      recommendations.add(
        SecurityRecommendation(
          code: 'clean_newsletters',
          title: 'Supprimer 10 newsletters',
          description:
              '$activeNewsletterSenders newsletters actives élargissent votre '
              'surface d\'exposition (fuites de données, spear phishing).',
          points: 3,
        ),
      );
    }

    // --- Global -------------------------------------------------------------
    final accountAvg = accountScores.isEmpty
        ? 100
        : accountScores.values.reduce((a, b) => a + b) ~/ accountScores.length;
    final globalScore =
        (accountAvg * 0.4 + phishingScore * 0.35 + privacyScore * 0.25)
            .round()
            .clamp(0, 100);

    recommendations.sort((a, b) => b.points.compareTo(a.points));

    return SecurityPosture(
      globalScore: globalScore,
      phishingScore: phishingScore,
      privacyScore: privacyScore,
      accountScores: accountScores,
      recommendations: recommendations,
    );
  }
}
