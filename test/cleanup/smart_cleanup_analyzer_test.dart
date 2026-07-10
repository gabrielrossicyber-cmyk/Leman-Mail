import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/domain/entities/cleanup_suggestion.dart';
import 'package:leman_mail/domain/entities/email_message.dart';
import 'package:leman_mail/domain/entities/newsletter_sender.dart';
import 'package:leman_mail/features/cleanup/smart_cleanup_analyzer.dart';

final _now = DateTime(2026, 7, 3);
var _idCounter = 0;

EmailMessage email({
  bool isRead = true,
  bool isNewsletter = false,
  Duration age = const Duration(days: 1),
  int sizeBytes = 20000,
  String from = 'contact@exemple.ch',
}) =>
    EmailMessage(
      id: ++_idCounter,
      accountId: 1,
      folderId: 1,
      uid: _idCounter,
      messageId: '<$_idCounter@test>',
      subject: 'Test',
      fromName: 'Test',
      fromAddress: from,
      toAddresses: const ['moi@leman.ch'],
      date: _now.subtract(age),
      snippet: '',
      isRead: isRead,
      isNewsletter: isNewsletter,
      sizeBytes: sizeBytes,
    );

void main() {
  const analyzer = SmartCleanupAnalyzer();

  group('SmartCleanupAnalyzer', () {
    test('boîte saine → aucune suggestion', () {
      final suggestions = analyzer.analyze(
        emails: [email(), email(isRead: false)],
        newsletterSenders: const [],
        now: _now,
      );
      expect(suggestions, isEmpty);
    });

    test('vieux non lus regroupés avec archive/suppression', () {
      final suggestions = analyzer.analyze(
        emails: [
          email(isRead: false, age: const Duration(days: 200)),
          email(isRead: false, age: const Duration(days: 400)),
          email(isRead: false, age: const Duration(days: 10)), // trop récent
        ],
        newsletterSenders: const [],
        now: _now,
      );
      final oldUnread = suggestions
          .singleWhere((s) => s.category == CleanupCategory.oldUnread);
      expect(oldUnread.emailCount, 2);
      expect(
        oldUnread.suggestedActions,
        containsAll([CleanupAction.archive, CleanupAction.delete]),
      );
    });

    test('newsletters jamais lues → suggestion de désabonnement', () {
      final sender = NewsletterSender(
        id: 1,
        accountId: 1,
        senderAddress: 'promo@zalando.ch',
        senderName: 'Zalando',
        emailCount: 20,
        unreadCount: 19, // read ratio 5%
        totalSizeBytes: 3 * 1024 * 1024,
        lastEmailAt: _now,
      );
      final suggestions = analyzer.analyze(
        emails: [
          email(isNewsletter: true, from: 'promo@zalando.ch'),
        ],
        newsletterSenders: [sender],
        now: _now,
      );
      final inactive = suggestions
          .singleWhere((s) => s.category == CleanupCategory.inactiveSender);
      expect(inactive.suggestedActions, contains(CleanupAction.unsubscribe));
      expect(inactive.recoverableBytes, 3 * 1024 * 1024);
    });

    test('newsletters périmées (> 90 j) proposées à la suppression', () {
      final suggestions = analyzer.analyze(
        emails: [
          email(isNewsletter: true, age: const Duration(days: 120)),
          email(isNewsletter: true, age: const Duration(days: 10)),
        ],
        newsletterSenders: const [],
        now: _now,
      );
      final stale = suggestions
          .singleWhere((s) => s.category == CleanupCategory.staleNewsletter);
      expect(stale.emailCount, 1);
    });

    test('gros emails anciens détectés et triés par octets récupérables', () {
      final suggestions = analyzer.analyze(
        emails: [
          email(sizeBytes: 8 * 1024 * 1024, age: const Duration(days: 400)),
          email(isRead: false, age: const Duration(days: 200), sizeBytes: 100),
        ],
        newsletterSenders: const [],
        now: _now,
      );
      expect(
        suggestions.first.category,
        CleanupCategory.largeOldEmail,
      );
      for (var i = 1; i < suggestions.length; i++) {
        expect(
          suggestions[i - 1].recoverableBytes,
          greaterThanOrEqualTo(suggestions[i].recoverableBytes),
        );
      }
    });

    test('formatBytes lisible', () {
      expect(SmartCleanupAnalyzer.formatBytes(500), '500 o');
      expect(SmartCleanupAnalyzer.formatBytes(2048), '2 Ko');
      expect(SmartCleanupAnalyzer.formatBytes(5 * 1024 * 1024), '5.0 Mo');
      expect(
        SmartCleanupAnalyzer.formatBytes(3 * 1024 * 1024 * 1024),
        '3.0 Go',
      );
    });
  });
}
