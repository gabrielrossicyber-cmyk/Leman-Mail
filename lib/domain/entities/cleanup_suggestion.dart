enum CleanupAction { delete, archive, unsubscribe, block }

enum CleanupCategory {
  oldUnread,
  inactiveSender,
  staleNewsletter,
  largeOldEmail,
}

/// One Smart Cleanup proposal ("87 emails non lus de plus de 6 mois").
class CleanupSuggestion {
  const CleanupSuggestion({
    required this.category,
    required this.title,
    required this.description,
    required this.emailIds,
    required this.recoverableBytes,
    required this.suggestedActions,
  });

  final CleanupCategory category;
  final String title;
  final String description;
  final List<int> emailIds;
  final int recoverableBytes;
  final List<CleanupAction> suggestedActions;

  int get emailCount => emailIds.length;
}
