import 'package:drift/drift.dart';

import '../../../domain/entities/email_message.dart' show AuthResult, RiskLevel;
import '../app_database.dart';

part 'emails_dao.g.dart';

/// Filters available in the unified inbox.
enum InboxFilter { all, unread, attachments, favorites, priority, suspicious }

@DriftAccessor(
  tables: [Emails, Attachments, BlockedSenders, Folders, PendingOperations],
)
class EmailsDao extends DatabaseAccessor<AppDatabase> with _$EmailsDaoMixin {
  EmailsDao(super.db);

  /// Unified inbox stream: newest first, across all (or one) account(s),
  /// optionally restricted to one folder type ('inbox', 'sent', 'spam'…).
  Stream<List<Email>> watchInbox({
    int? accountId,
    String? folderType,
    InboxFilter filter = InboxFilter.all,
    int limit = 100,
  }) {
    final query = select(emails)
      ..orderBy([(e) => OrderingTerm.desc(e.date)])
      ..limit(limit);
    if (accountId != null) {
      query.where((e) => e.accountId.equals(accountId));
    }
    if (folderType != null) {
      final folderIds = selectOnly(folders)
        ..addColumns([folders.id])
        ..where(folders.type.equals(folderType));
      query.where((e) => e.folderId.isInQuery(folderIds));
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

  /// Messages d'un fil de conversation, du plus ancien au plus récent.
  Stream<List<Email>> watchThread(String threadId) => (select(emails)
        ..where((e) => e.threadId.equals(threadId))
        ..orderBy([(e) => OrderingTerm.asc(e.date)]))
      .watch();

  Future<int> upsert(EmailsCompanion email) =>
      into(emails).insertOnConflictUpdate(email);

  Future<List<Email>> getByIds(List<int> ids) =>
      (select(emails)..where((e) => e.id.isIn(ids))).get();

  /// Chaque action locale enfile son opération serveur : c'est ici, au
  /// niveau du DAO, pour que TOUS les chemins (boîte, lecture, Newsletter
  /// Cleaner, Smart Cleanup) soient répercutés sans y penser.
  Future<void> _enqueueOps(List<int> emailIds, PendingOpType op) async {
    final rows = await getByIds(emailIds);
    if (rows.isEmpty) return;
    await batch(
      (b) => b.insertAll(pendingOperations, [
        for (final row in rows)
          PendingOperationsCompanion.insert(
            accountId: row.accountId,
            folderId: row.folderId,
            uid: row.uid,
            operation: op,
          ),
      ]),
    );
  }

  Future<void> markRead(List<int> ids, {bool read = true}) =>
      transaction(() async {
        await _enqueueOps(
          ids,
          read ? PendingOpType.markRead : PendingOpType.markUnread,
        );
        await (update(emails)..where((e) => e.id.isIn(ids)))
            .write(EmailsCompanion(isRead: Value(read)));
      });

  Future<void> setFlagged(List<int> ids, {required bool flagged}) =>
      transaction(() async {
        await _enqueueOps(
          ids,
          flagged ? PendingOpType.flag : PendingOpType.unflag,
        );
        await (update(emails)..where((e) => e.id.isIn(ids)))
            .write(EmailsCompanion(isFlagged: Value(flagged)));
      });

  Future<void> deleteByIds(List<int> ids) => transaction(() async {
        // Enfilé AVANT la suppression locale : le UID serveur est encore là.
        await _enqueueOps(ids, PendingOpType.delete);
        await (delete(emails)..where((e) => e.id.isIn(ids))).go();
      });

  // ---- Recherche plein texte (FTS5) ----------------------------------------

  /// Construit la requête MATCH : termes entre guillemets + préfixe, pour
  /// que « factur digi » trouve « Facture Digitec » sans exposer la
  /// syntaxe FTS aux entrées utilisateur.
  static String buildMatchQuery(String input) {
    final terms = input
        .replaceAll(RegExp(r'''["'\*\(\)\^:]'''), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty);
    return terms.map((t) => '"$t"*').join(' ');
  }

  Future<List<Email>> search(String query, {int limit = 50}) async {
    final match = buildMatchQuery(query);
    if (match.isEmpty) return const [];
    final idRows = await customSelect(
      'SELECT rowid FROM emails_fts WHERE emails_fts MATCH ?1 '
      'ORDER BY rank LIMIT ?2',
      variables: [Variable.withString(match), Variable.withInt(limit)],
      readsFrom: {emails},
    ).get();
    final ids = [for (final row in idRows) row.read<int>('rowid')];
    if (ids.isEmpty) return const [];

    final rows = await getByIds(ids);
    final rankOf = {for (final (i, id) in ids.indexed) id: i};
    rows.sort((a, b) => rankOf[a.id]!.compareTo(rankOf[b.id]!));
    return rows;
  }

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

  Future<int> countWhere(
    Expression<bool> Function($EmailsTable e) predicate,
  ) async {
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
