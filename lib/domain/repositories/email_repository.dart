import '../../features/health/inbox_health_calculator.dart';
import '../entities/email_message.dart';

abstract interface class EmailRepository {
  /// Reactive unified inbox (all accounts) or single-account view,
  /// optionally restricted to one folder type ('inbox', 'sent', 'spam'…).
  Stream<List<EmailMessage>> watchInbox({
    int? accountId,
    String? folderType,
    String filter,
    int limit,
  });

  Future<EmailMessage?> byId(int id);

  /// Decrypts and returns the full body of one message.
  Future<String?> loadBody(int emailId);

  Future<void> markRead(List<int> emailIds, {bool read});
  Future<void> delete(List<int> emailIds);
  Future<void> blockSender(String pattern, {String reason});

  /// Aggregated statistics consumed by the health / security engines.
  Future<InboxStats> collectStats();

  /// Trust context for the phishing engine.
  Future<Set<String>> knownSenderAddresses();
}
