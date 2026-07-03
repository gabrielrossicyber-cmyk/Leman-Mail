import '../../domain/entities/cleanup_suggestion.dart';
import '../../domain/entities/email_message.dart';
import '../../domain/entities/newsletter_sender.dart';

/// Smart Cleanup: turns raw mailbox statistics into actionable batch
/// suggestions ("Vous pouvez récupérer de l'espace et réduire votre bruit
/// numérique.").
///
/// Pure function of its inputs — the repository feeds it emails and
/// newsletter aggregates, it returns suggestions with the target email ids
/// so the UI can execute delete / archive / unsubscribe / block in bulk.
class SmartCleanupAnalyzer {
  const SmartCleanupAnalyzer({
    this.oldUnreadThreshold = const Duration(days: 180),
    this.staleNewsletterThreshold = const Duration(days: 90),
    this.largeEmailMinBytes = 5 * 1024 * 1024,
    this.largeEmailMinAge = const Duration(days: 365),
  });

  final Duration oldUnreadThreshold;
  final Duration staleNewsletterThreshold;
  final int largeEmailMinBytes;
  final Duration largeEmailMinAge;

  List<CleanupSuggestion> analyze({
    required List<EmailMessage> emails,
    required List<NewsletterSender> newsletterSenders,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final suggestions = <CleanupSuggestion>[];

    // 1. Old unread emails.
    final oldUnread = emails
        .where(
          (e) =>
              !e.isRead &&
              !e.isNewsletter &&
              clock.difference(e.date) > oldUnreadThreshold,
        )
        .toList();
    if (oldUnread.isNotEmpty) {
      suggestions.add(
        CleanupSuggestion(
          category: CleanupCategory.oldUnread,
          title: '${oldUnread.length} emails non lus anciens',
          description:
              'Non lus depuis plus de ${oldUnreadThreshold.inDays ~/ 30} mois — '
              'archivez-les pour repartir sur une boîte saine.',
          emailIds: oldUnread.map((e) => e.id).toList(),
          recoverableBytes: _totalSize(oldUnread),
          suggestedActions: const [CleanupAction.archive, CleanupAction.delete],
        ),
      );
    }

    // 2. Newsletters the user never reads.
    final ignoredSenders = newsletterSenders
        .where(
          (s) =>
              s.status == NewsletterStatus.active &&
              s.emailCount >= 5 &&
              s.readRatio < 0.2,
        )
        .toList();
    if (ignoredSenders.isNotEmpty) {
      final ids = <int>[
        for (final e in emails)
          if (e.isNewsletter &&
              ignoredSenders.any(
                (s) => s.senderAddress == e.fromAddress.toLowerCase(),
              ))
            e.id,
      ];
      suggestions.add(
        CleanupSuggestion(
          category: CleanupCategory.inactiveSender,
          title: '${ignoredSenders.length} newsletters jamais lues',
          description:
              'Vous ouvrez moins de 20 % des emails de ces expéditeurs — '
              'désabonnez-vous pour réduire le bruit.',
          emailIds: ids,
          recoverableBytes:
              ignoredSenders.fold(0, (sum, s) => sum + s.totalSizeBytes),
          suggestedActions: const [
            CleanupAction.unsubscribe,
            CleanupAction.delete,
          ],
        ),
      );
    }

    // 3. Stale newsletters still sitting in the inbox.
    final staleNewsletters = emails
        .where(
          (e) =>
              e.isNewsletter &&
              clock.difference(e.date) > staleNewsletterThreshold,
        )
        .toList();
    if (staleNewsletters.isNotEmpty) {
      suggestions.add(
        CleanupSuggestion(
          category: CleanupCategory.staleNewsletter,
          title: '${staleNewsletters.length} newsletters périmées',
          description:
              'Promotions et newsletters de plus de ${staleNewsletterThreshold.inDays} jours : '
              'leur contenu n\'est plus d\'actualité.',
          emailIds: staleNewsletters.map((e) => e.id).toList(),
          recoverableBytes: _totalSize(staleNewsletters),
          suggestedActions: const [CleanupAction.delete],
        ),
      );
    }

    // 4. Large, old emails (attachment-heavy).
    final largeOld = emails
        .where(
          (e) =>
              e.sizeBytes >= largeEmailMinBytes &&
              clock.difference(e.date) > largeEmailMinAge,
        )
        .toList();
    if (largeOld.isNotEmpty) {
      suggestions.add(
        CleanupSuggestion(
          category: CleanupCategory.largeOldEmail,
          title: '${largeOld.length} emails volumineux anciens',
          description:
              'Plus de ${largeEmailMinBytes ~/ (1024 * 1024)} Mo chacun et datant de plus d\'un an — '
              'récupérez ${formatBytes(_totalSize(largeOld))}.',
          emailIds: largeOld.map((e) => e.id).toList(),
          recoverableBytes: _totalSize(largeOld),
          suggestedActions: const [CleanupAction.archive, CleanupAction.delete],
        ),
      );
    }

    suggestions.sort((a, b) => b.recoverableBytes.compareTo(a.recoverableBytes));
    return suggestions;
  }

  static int _totalSize(List<EmailMessage> emails) =>
      emails.fold(0, (sum, e) => sum + e.sizeBytes);

  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    return '$bytes o';
  }
}
