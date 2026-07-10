import '../entities/newsletter_sender.dart';

enum UnsubscribeOutcome { oneClickDone, openUrl, sendMailto, unavailable }

/// Result of an unsubscribe attempt. RFC 8058 senders are handled
/// silently; others hand back the URL/mailto for the UI to complete.
class UnsubscribeResult {
  const UnsubscribeResult(this.outcome, {this.target});

  final UnsubscribeOutcome outcome;
  final String? target;
}

abstract interface class NewsletterRepository {
  Stream<List<NewsletterSender>> watchActive({int? accountId});
  Future<int> activeCount();
  Future<int> unsubscribedCount();

  Future<UnsubscribeResult> unsubscribe(NewsletterSender sender);
  Future<void> block(NewsletterSender sender);
  Future<void> archiveAllFrom(NewsletterSender sender);
  Future<void> deleteAllFrom(NewsletterSender sender);
}
