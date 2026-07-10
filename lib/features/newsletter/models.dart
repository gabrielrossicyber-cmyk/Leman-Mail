/// Result of newsletter/marketing classification for one email.
class NewsletterDetection {
  const NewsletterDetection({
    required this.isNewsletter,
    this.unsubscribeUrl,
    this.unsubscribeMailto,
    this.supportsOneClick = false,
    this.signals = const [],
  });

  static const none = NewsletterDetection(isNewsletter: false);

  final bool isNewsletter;

  /// https unsubscribe target from List-Unsubscribe or body links.
  final String? unsubscribeUrl;

  /// mailto: unsubscribe target from List-Unsubscribe.
  final String? unsubscribeMailto;

  /// RFC 8058: List-Unsubscribe-Post allows silent one-click unsubscribe.
  final bool supportsOneClick;

  /// Which heuristics fired — kept for explainability and tuning.
  final List<String> signals;

  bool get canUnsubscribe => unsubscribeUrl != null || unsubscribeMailto != null;
}
