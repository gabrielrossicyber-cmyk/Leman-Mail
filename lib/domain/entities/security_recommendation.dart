enum RecommendationStatus { open, completed, dismissed }

/// A Security Center action item, valued in points like Microsoft
/// Secure Score ("+5 Activer MFA").
class SecurityRecommendation {
  const SecurityRecommendation({
    required this.code,
    required this.title,
    required this.description,
    required this.points,
    this.accountUuid,
    this.status = RecommendationStatus.open,
  });

  final String code;
  final String title;
  final String description;
  final int points;
  final String? accountUuid;
  final RecommendationStatus status;

  SecurityRecommendation copyWith({RecommendationStatus? status}) =>
      SecurityRecommendation(
        code: code,
        title: title,
        description: description,
        points: points,
        accountUuid: accountUuid,
        status: status ?? this.status,
      );
}

/// Security Center output: global + per-dimension scores and open actions.
class SecurityPosture {
  const SecurityPosture({
    required this.globalScore,
    required this.phishingScore,
    required this.privacyScore,
    required this.accountScores,
    required this.recommendations,
  });

  final int globalScore;
  final int phishingScore;
  final int privacyScore;

  /// Per-account score, keyed by account uuid.
  final Map<String, int> accountScores;
  final List<SecurityRecommendation> recommendations;
}
