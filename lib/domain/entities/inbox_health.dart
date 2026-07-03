enum HealthGrade { excellent, good, average, critical }

extension HealthGradeLabel on HealthGrade {
  String get label => switch (this) {
        HealthGrade.excellent => 'Excellent',
        HealthGrade.good => 'Bon',
        HealthGrade.average => 'Moyen',
        HealthGrade.critical => 'Critique',
      };
}

/// A single recommendation produced by the health engine
/// ("Désabonnez-vous de 12 newsletters", ...).
class HealthRecommendation {
  const HealthRecommendation({
    required this.message,
    required this.impact,
  });

  final String message;

  /// Estimated score points recoverable by acting on it.
  final int impact;
}

/// Result of the proprietary Inbox Health Score computation.
class InboxHealth {
  const InboxHealth({
    required this.totalScore,
    required this.securityScore,
    required this.clutterScore,
    required this.privacyScore,
    required this.organizationScore,
    required this.strengths,
    required this.improvements,
    required this.risks,
    required this.recommendations,
    required this.computedAt,
  });

  final int totalScore;
  final int securityScore;
  final int clutterScore;
  final int privacyScore;
  final int organizationScore;

  /// ✅ Forces — what is going well.
  final List<String> strengths;

  /// ⚠ Améliorations — actionable issues.
  final List<String> improvements;

  /// ❌ Risques — active dangers.
  final List<String> risks;

  final List<HealthRecommendation> recommendations;
  final DateTime computedAt;

  HealthGrade get grade {
    if (totalScore >= 90) return HealthGrade.excellent;
    if (totalScore >= 70) return HealthGrade.good;
    if (totalScore >= 50) return HealthGrade.average;
    return HealthGrade.critical;
  }
}

/// Daily snapshot for the 7d / 30d / 90d / 12m evolution charts.
class HealthSnapshot {
  const HealthSnapshot({
    required this.day,
    required this.totalScore,
    required this.securityScore,
    required this.clutterScore,
    required this.privacyScore,
    required this.organizationScore,
  });

  final DateTime day;
  final int totalScore;
  final int securityScore;
  final int clutterScore;
  final int privacyScore;
  final int organizationScore;
}
