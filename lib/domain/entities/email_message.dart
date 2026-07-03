/// Result of SPF / DKIM / DMARC evaluation, parsed from the
/// `Authentication-Results` header added by the receiving server.
enum AuthResult { pass, fail, softfail, none, unknown }

enum RiskLevel { low, medium, high }

/// One phishing-analysis signal, denormalized from the engine findings so
/// the detail screen can explain the score ("Échec SPF", "Lien raccourci"…).
class EmailFinding {
  const EmailFinding({required this.severity, required this.message});

  /// `info` | `low` | `medium` | `high` | `critical`.
  final String severity;
  final String message;
}

class EmailAttachmentInfo {
  const EmailAttachmentInfo({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.isDangerous = false,
  });

  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final bool isDangerous;
}

/// Domain representation of a synchronized email. The full body is loaded
/// (and decrypted) on demand; list views only need the metadata below.
class EmailMessage {
  const EmailMessage({
    required this.id,
    required this.accountId,
    required this.folderId,
    required this.uid,
    required this.messageId,
    required this.subject,
    required this.fromName,
    required this.fromAddress,
    required this.toAddresses,
    required this.date,
    required this.snippet,
    this.threadId,
    this.ccAddresses = const [],
    this.bodyIsHtml = false,
    this.isRead = false,
    this.isFlagged = false,
    this.isAnswered = false,
    this.hasAttachments = false,
    this.sizeBytes = 0,
    this.attachments = const [],
    this.spf = AuthResult.unknown,
    this.dkim = AuthResult.unknown,
    this.dmarc = AuthResult.unknown,
    this.phishingScore = 0,
    this.phishingLevel = RiskLevel.low,
    this.findings = const [],
    this.trackerCount = 0,
    this.externalResourceCount = 0,
    this.privacyScore = 100,
    this.isNewsletter = false,
    this.unsubscribeUrl,
    this.unsubscribeMailto,
  });

  final int id;
  final int accountId;
  final int folderId;
  final int uid;
  final String messageId;
  final String? threadId;
  final String subject;
  final String fromName;
  final String fromAddress;
  final List<String> toAddresses;
  final List<String> ccAddresses;
  final DateTime date;
  final String snippet;
  final bool bodyIsHtml;
  final bool isRead;
  final bool isFlagged;
  final bool isAnswered;
  final bool hasAttachments;
  final int sizeBytes;
  final List<EmailAttachmentInfo> attachments;

  // Security analysis (denormalized).
  final AuthResult spf;
  final AuthResult dkim;
  final AuthResult dmarc;
  final int phishingScore;
  final RiskLevel phishingLevel;
  final List<EmailFinding> findings;

  // Privacy analysis.
  final int trackerCount;
  final int externalResourceCount;
  final int privacyScore;

  // Newsletter detection.
  final bool isNewsletter;
  final String? unsubscribeUrl;
  final String? unsubscribeMailto;

  bool get hasTracking => trackerCount > 0;
}
