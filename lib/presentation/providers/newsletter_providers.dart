import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/cleanup_suggestion.dart';
import '../../domain/entities/newsletter_sender.dart';
import '../../domain/repositories/email_repository.dart';
import '../../domain/usecases/run_newsletter_cleanup.dart';
import 'core_providers.dart';

final activeNewslettersProvider = StreamProvider<List<NewsletterSender>>(
  (ref) => ref.watch(newsletterRepositoryProvider).watchActive(),
);

/// Sender ids ticked in the Newsletter Cleaner list.
final selectedNewsletterIdsProvider = StateProvider<Set<int>>((ref) => {});

/// « Nettoyer ma boîte » button state.
class NewsletterCleanupController
    extends AsyncNotifier<NewsletterCleanupReport?> {
  @override
  Future<NewsletterCleanupReport?> build() async => null;

  Future<void> run(NewsletterCleanupAction action) async {
    final selectedIds = ref.read(selectedNewsletterIdsProvider);
    final senders = ref
            .read(activeNewslettersProvider)
            .valueOrNull
            ?.where((s) => selectedIds.contains(s.id))
            .toList() ??
        [];
    if (senders.isEmpty) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(runNewsletterCleanupProvider)
          .call(senders: senders, action: action),
    );
    ref.read(selectedNewsletterIdsProvider.notifier).state = {};
  }
}

final newsletterCleanupControllerProvider = AsyncNotifierProvider<
    NewsletterCleanupController, NewsletterCleanupReport?>(
  NewsletterCleanupController.new,
);

/// Smart Cleanup suggestions, recomputed on demand.
final cleanupSuggestionsProvider =
    FutureProvider<List<CleanupSuggestion>>((ref) async {
  final emails = await ref
      .watch(emailRepositoryProvider)
      .watchInbox(limit: 2000)
      .first;
  final newsletters =
      await ref.watch(newsletterRepositoryProvider).watchActive().first;
  return ref.watch(smartCleanupAnalyzerProvider).analyze(
        emails: emails,
        newsletterSenders: newsletters,
      );
});

/// Executes one Smart Cleanup suggestion.
final applyCleanupProvider = Provider(
  (ref) => (CleanupSuggestion suggestion, CleanupAction action) async {
    final EmailRepository repo = ref.read(emailRepositoryProvider);
    switch (action) {
      case CleanupAction.delete:
        await repo.delete(suggestion.emailIds);
      case CleanupAction.archive:
        await repo.markRead(suggestion.emailIds);
      case CleanupAction.unsubscribe:
      case CleanupAction.block:
        // Sender-level actions are driven from the Newsletter Cleaner.
        break;
    }
    ref.invalidate(cleanupSuggestionsProvider);
  },
);
