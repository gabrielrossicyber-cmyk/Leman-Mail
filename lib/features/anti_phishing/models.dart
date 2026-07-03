import '../../domain/entities/email_message.dart';

/// Everything a phishing rule may inspect. Built once per email by the
/// analysis pipeline, so individual rules stay cheap and side-effect free.
class PhishingInput {
  const PhishingInput({
    required this.fromAddress,
    required this.fromName,
    required this.subject,
    this.replyToAddress,
    this.bodyText = '',
    this.bodyHtml,
    this.spf = AuthResult.unknown,
    this.dkim = AuthResult.unknown,
    this.dmarc = AuthResult.unknown,
    this.attachments = const [],
    this.knownSenderAddresses = const {},
    this.userContactDomains = const {},
  });

  final String fromAddress;
  final String fromName;
  final String subject;
  final String? replyToAddress;
  final String bodyText;
  final String? bodyHtml;
  final AuthResult spf;
  final AuthResult dkim;
  final AuthResult dmarc;
  final List<EmailAttachmentInfo> attachments;

  /// Addresses the user already exchanged with (trust signal).
  final Set<String> knownSenderAddresses;

  /// Domains of the user's frequent correspondents — protected against
  /// lookalikes in addition to the global brand list.
  final Set<String> userContactDomains;
}

enum FindingSeverity { info, low, medium, high, critical }

extension FindingSeverityWeight on FindingSeverity {
  /// Contribution to the 0-100 risk score.
  int get weight => switch (this) {
        FindingSeverity.info => 2,
        FindingSeverity.low => 8,
        FindingSeverity.medium => 18,
        FindingSeverity.high => 35,
        FindingSeverity.critical => 60,
      };
}

/// One issue raised by one rule.
class PhishingFinding {
  const PhishingFinding({
    required this.ruleId,
    required this.severity,
    required this.message,
  });

  final String ruleId;
  final FindingSeverity severity;

  /// User-facing explanation ("Le domaine paypa1.com imite paypal.com").
  final String message;

  Map<String, Object?> toJson() => {
        'rule': ruleId,
        'severity': severity.name,
        'message': message,
      };
}

/// Final engine output.
class PhishingVerdict {
  const PhishingVerdict({
    required this.score,
    required this.level,
    required this.findings,
  });

  /// 0 (sain) → 100 (phishing quasi certain).
  final int score;
  final RiskLevel level;
  final List<PhishingFinding> findings;

  bool get isSuspicious => level != RiskLevel.low;
}
