import '../entities/newsletter_sender.dart';
import '../repositories/newsletter_repository.dart';

enum NewsletterCleanupAction { unsubscribe, block, archive, delete }

class NewsletterCleanupReport {
  const NewsletterCleanupReport({
    required this.processed,
    required this.oneClickUnsubscribed,
    required this.manualActionsRequired,
  });

  final int processed;
  final int oneClickUnsubscribed;

  /// Senders whose unsubscribe needs the user (open URL / send mailto).
  final List<UnsubscribeResult> manualActionsRequired;
}

/// Use case behind the « Nettoyer ma boîte » button: applies the chosen
/// action to every selected newsletter sender.
class RunNewsletterCleanup {
  const RunNewsletterCleanup(this.repository);

  final NewsletterRepository repository;

  Future<NewsletterCleanupReport> call({
    required List<NewsletterSender> senders,
    required NewsletterCleanupAction action,
  }) async {
    var oneClick = 0;
    final manual = <UnsubscribeResult>[];

    for (final sender in senders) {
      switch (action) {
        case NewsletterCleanupAction.unsubscribe:
          final result = await repository.unsubscribe(sender);
          if (result.outcome == UnsubscribeOutcome.oneClickDone) {
            oneClick++;
          } else if (result.outcome != UnsubscribeOutcome.unavailable) {
            manual.add(result);
          }
        case NewsletterCleanupAction.block:
          await repository.block(sender);
        case NewsletterCleanupAction.archive:
          await repository.archiveAllFrom(sender);
        case NewsletterCleanupAction.delete:
          await repository.deleteAllFrom(sender);
      }
    }

    return NewsletterCleanupReport(
      processed: senders.length,
      oneClickUnsubscribed: oneClick,
      manualActionsRequired: manual,
    );
  }
}
