import '../../domain/entities/email_message.dart';
import 'models.dart';
import 'phishing_rule.dart';
import 'rules/authentication_rule.dart';
import 'rules/dangerous_attachment_rule.dart';
import 'rules/lookalike_domain_rule.dart';
import 'rules/suspicious_url_rule.dart';
import 'rules/unknown_sender_rule.dart';
import 'rules/urgency_language_rule.dart';

/// Modular anti-phishing engine.
///
/// Runs every registered [PhishingRule], sums the severity weights of the
/// findings, clamps to 0-100 and maps the score to a traffic-light level:
///
/// | Score  | Niveau            |
/// |--------|-------------------|
/// | 0-24   | 🟢 Faible risque  |
/// | 25-59  | 🟡 Risque moyen   |
/// | 60-100 | 🔴 Risque élevé   |
///
/// Adding a detection = implementing [PhishingRule] and appending it to
/// the list — the engine never changes (Open/Closed).
class PhishingEngine {
  PhishingEngine({List<PhishingRule>? rules})
      : rules = List.unmodifiable(rules ?? defaultRules());

  final List<PhishingRule> rules;

  static const mediumThreshold = 25;
  static const highThreshold = 60;

  static List<PhishingRule> defaultRules({
    Set<String> extraProtectedDomains = const {},
  }) =>
      [
        const AuthenticationRule(),
        LookalikeDomainRule(extraProtectedDomains: extraProtectedDomains),
        const SuspiciousUrlRule(),
        const DangerousAttachmentRule(),
        const UnknownSenderRule(),
        const UrgencyLanguageRule(),
      ];

  PhishingVerdict analyze(PhishingInput input) {
    final findings = <PhishingFinding>[
      for (final rule in rules) ...rule.evaluate(input),
    ];

    var score = 0;
    for (final finding in findings) {
      score += finding.severity.weight;
    }
    score = score.clamp(0, 100);

    final level = switch (score) {
      >= highThreshold => RiskLevel.high,
      >= mediumThreshold => RiskLevel.medium,
      _ => RiskLevel.low,
    };

    // Most severe first, so the UI shows the headline issue on top.
    findings.sort((a, b) => b.severity.index.compareTo(a.severity.index));

    return PhishingVerdict(score: score, level: level, findings: findings);
  }
}
