import '../../../domain/entities/account.dart';
import '../../../domain/entities/email_message.dart';

/// Transport-agnostic representation of a fetched message, produced by all
/// three sync backends (IMAP, Gmail API, Microsoft Graph) and consumed by
/// the analysis pipeline. Header keys are lowercase.
class RawEmail {
  const RawEmail({
    required this.uid,
    required this.messageId,
    required this.subject,
    required this.fromName,
    required this.fromAddress,
    required this.toAddresses,
    required this.date,
    required this.headers,
    this.threadId,
    this.ccAddresses = const [],
    this.replyToAddress,
    this.bodyPlain,
    this.bodyHtml,
    this.isRead = false,
    this.isFlagged = false,
    this.isAnswered = false,
    this.sizeBytes = 0,
    this.attachments = const [],
  });

  final int uid;
  final String messageId;
  final String? threadId;
  final String subject;
  final String fromName;
  final String fromAddress;
  final List<String> toAddresses;
  final List<String> ccAddresses;
  final String? replyToAddress;
  final DateTime date;

  /// Lowercased header map (`authentication-results`, `list-unsubscribe`...).
  final Map<String, String> headers;
  final String? bodyPlain;
  final String? bodyHtml;
  final bool isRead;
  final bool isFlagged;
  final bool isAnswered;
  final int sizeBytes;
  final List<EmailAttachmentInfo> attachments;
}

class RemoteFolder {
  const RemoteFolder({
    required this.path,
    required this.name,
    required this.type,
    this.uidValidity,
  });

  final String path;
  final String name;

  /// `inbox`, `sent`, `drafts`, `trash`, `spam`, `archive`, `other`.
  final String type;
  final int? uidValidity;
}

/// Common contract for every mail backend. Implementations:
///  - [ImapService]           — any IMAP provider
///  - [GmailApiService]       — Gmail REST
///  - [MicrosoftGraphService] — Outlook.com / Microsoft 365
abstract interface class MailSyncService {
  MailProvider get provider;

  Future<void> connect(Account account, {required String secret});
  Future<void> disconnect();

  Future<List<RemoteFolder>> listFolders();

  /// Fetches messages with uid > [sinceUid] (incremental sync).
  Future<List<RawEmail>> fetchNewMessages(
    RemoteFolder folder, {
    int sinceUid = 0,
    int limit = 50,
  });

  Future<void> markRead(RemoteFolder folder, List<int> uids, {bool read = true});
  Future<void> deleteMessages(RemoteFolder folder, List<int> uids);
  Future<void> moveToFolder(
    RemoteFolder from,
    RemoteFolder to,
    List<int> uids,
  );
}

/// Parses SPF/DKIM/DMARC results out of an `Authentication-Results`
/// header — shared by every backend.
({AuthResult spf, AuthResult dkim, AuthResult dmarc}) parseAuthenticationResults(
  String? header,
) {
  if (header == null || header.isEmpty) {
    return (spf: AuthResult.unknown, dkim: AuthResult.unknown, dmarc: AuthResult.unknown);
  }

  AuthResult extract(String mechanism) {
    final match = RegExp(
      '$mechanism\\s*=\\s*(pass|fail|softfail|neutral|none|permerror|temperror)',
      caseSensitive: false,
    ).firstMatch(header);
    return switch (match?.group(1)?.toLowerCase()) {
      'pass' => AuthResult.pass,
      'fail' || 'permerror' => AuthResult.fail,
      'softfail' || 'neutral' || 'temperror' => AuthResult.softfail,
      'none' => AuthResult.none,
      _ => AuthResult.unknown,
    };
  }

  return (spf: extract('spf'), dkim: extract('dkim'), dmarc: extract('dmarc'));
}
