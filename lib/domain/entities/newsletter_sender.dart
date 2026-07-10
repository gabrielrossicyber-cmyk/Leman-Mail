enum NewsletterStatus { active, unsubscribed, blocked, archived }

/// Aggregated newsletter/marketing sender shown in the Newsletter Cleaner.
class NewsletterSender {
  const NewsletterSender({
    required this.id,
    required this.accountId,
    required this.senderAddress,
    required this.senderName,
    required this.emailCount,
    required this.unreadCount,
    required this.totalSizeBytes,
    required this.lastEmailAt,
    this.unsubscribeUrl,
    this.unsubscribeMailto,
    this.supportsOneClick = false,
    this.status = NewsletterStatus.active,
  });

  final int id;
  final int accountId;
  final String senderAddress;
  final String senderName;
  final int emailCount;
  final int unreadCount;
  final int totalSizeBytes;
  final DateTime lastEmailAt;
  final String? unsubscribeUrl;
  final String? unsubscribeMailto;
  final bool supportsOneClick;
  final NewsletterStatus status;

  bool get canUnsubscribe =>
      unsubscribeUrl != null || unsubscribeMailto != null;

  /// Read ratio used to suggest unsubscribing ("vous n'ouvrez jamais ces emails").
  double get readRatio =>
      emailCount == 0 ? 1 : (emailCount - unreadCount) / emailCount;
}
