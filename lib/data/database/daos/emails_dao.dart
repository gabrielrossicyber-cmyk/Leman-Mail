import 'package:drift/drift.dart';

import '../../../domain/entities/email_message.dart' show AuthResult, RiskLevel;
import '../app_database.dart';

part 'emails_dao.g.dart';

/// Filters available in the unified inbox.
enum InboxFilter { all, unread, attachments, favorites, priority, suspicious }

@DriftAccessor(tables: [Emails, Attachments, BlockedSenders])
class EmailsDao extends DatabaseAccessor<AppDatabase> with _$EmailsDaoMixin {
  EmailsDao(super.db);

  /// Unified inbox stream: newest first, across all (or one) account(s).
  Stream<List<Email>> watchInbox({
    int? accountId,
    InboxFilter filter = InboxFilter.all,
    int limit = 100,
  }) {
    final query = select(emails)
      ..orderBy([(e) => OrderingTerm.desc(e.date)])
      ..limit(limit);
    if (accountId != null) {
      query.where((e) => e.accountId.equals(accountId));
    }
    switch (filter) {
      case InboxFilter.unread:
        query.where((e) => e.isRead.equals(false));
      case InboxFilter.attachments:
        query.where((e) => e.hasAttachments.equals(true));
      case InboxFilter.favorites:
        query.where((e) => e.isFlagged.equals(true));
      case InboxFilter.priority:
        query.where(
          (e) => e.isRead.equals(false) & e.isNewsletter.equals(false),
        );
      case InboxFilter.suspicious:
        query.where(
          (e) => e.phishingLevel.equalsValue(RiskLevel.high) |
              e.phishingLevel.equalsValue(RiskLevel.medium),
        );
      case InboxFilter.all:
        break;
    }
    return query.watch();
  }

  Future<Email?> getById(int id) =>
      (select(emails)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<int> upsert(EmailsCompanion email) =>
      into(emails).insertOnConflictUpdate(email);

  Future<void> markRead(List<int> ids, {bool read = true}) =>
      (update(emails)..where((e) => e.id.isIn(ids)))
          .write(EmailsCompanion(isRead: Value(read)));

  Future<void> deleteByIds(List<int> ids) =>
      (delete(emails)..where((e) => e.id.isIn(ids))).go();

  Future<List<Attachment>> attachmentsOf(int emailId) =>
      (select(attachments)..where((a) => a.emailId.equals(emailId))).get();

  Future<void> insertAttachments(List<AttachmentsCompanion> rows) =>
      batch((b) => b.insertAll(attachments, rows));

  Future<void> blockSender(String pattern, String reason) =>
      into(blockedSenders).insertOnConflictUpdate(
        BlockedSendersCompanion.insert(pattern: pattern, reason: Value(reason)),
      );

  Future<List<BlockedSender>> allBlockedSenders() =>
      select(blockedSenders).get();

  // ---- Aggregates feeding InboxStats / dashboards -------------------------

  Future<int> countWhere(Expression<bool> Function(Emails e) predicate) async {
    final countExp = emails.id.count();
    final query = selectOnly(emails)
      ..addColumns([countExp])
      ..where(predicate(emails));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<int> totalCount() => countWhere((e) => e.id.isNotNull());
  Future<int> unreadCount() => countWhere((e) => e.isRead.equals(false));
  Future<int> newsletterCount() =>
      countWhere((e) => e.isNewsletter.equals(true));
  Future<int> highRiskCount() =>
      countWhere((e) => e.phishingLevel.equalsValue(RiskLevel.high));
  Future<int> mediumRiskCount() =>
      countWhere((e) => e.phishingLevel.equalsValue(RiskLevel.medium));
  Future<int> trackedEmailCount() =>
      countWhere((e) => e.trackerCount.isBiggerThanValue(0));

  Future<int> oldUnreadCount(DateTime olderThan) => countWhere(
        (e) => e.isRead.equals(false) & e.date.isSmallerThanValue(olderThan),
      );

  Future<int> sumTrackerCount() async {
    final sumExp = emails.trackerCount.sum();
    final query = selectOnly(emails)..addColumns([sumExp]);
    final row = await query.getSingle();
    return row.read(sumExp) ?? 0;
  }

  Future<int> spfPassCount() =>
      countWhere((e) => e.spf.equalsValue(AuthResult.pass));
  Future<int> dkimPassCount() =>
      countWhere((e) => e.dkim.equalsValue(AuthResult.pass));
  Future<int> dmarcPassCount() =>
      countWhere((e) => e.dmarc.equalsValue(AuthResult.pass));
  Future<int> authEvaluatedCount() =>
      countWhere((e) => e.spf.equalsValue(AuthResult.unknown).not());

  /// Distinct correspondent addresses — trust context for the phishing
  /// engine (known senders) and lookalike protection (contact domains).
  Future<List<String>> knownSenderAddresses() async {
    final query = selectOnly(emails, distinct: true)
      ..addColumns([emails.fromAddress]);
    final rows = await query.get();
    return rows
        .map((r) => r.read(emails.fromAddress))
        .whereType<String>()
        .toList();
  }
}
