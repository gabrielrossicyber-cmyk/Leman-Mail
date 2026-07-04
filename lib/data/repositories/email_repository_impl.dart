import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/security/crypto_service.dart';
import '../../domain/entities/email_message.dart' as domain;
import '../../domain/repositories/email_repository.dart';
import '../../features/health/inbox_health_calculator.dart';
import '../database/app_database.dart';
import '../database/daos/emails_dao.dart';

class EmailRepositoryImpl implements EmailRepository {
  EmailRepositoryImpl(this._db, this._crypto);

  final AppDatabase _db;
  final CryptoService _crypto;

  @override
  Stream<List<domain.EmailMessage>> watchInbox({
    int? accountId,
    String? folderType,
    String filter = 'all',
    int limit = 100,
  }) =>
      _db.emailsDao
          .watchInbox(
            accountId: accountId,
            folderType: folderType,
            filter: InboxFilter.values.firstWhere(
              (f) => f.name == filter,
              orElse: () => InboxFilter.all,
            ),
            limit: limit,
          )
          .map((rows) => rows.map(_toEntity).toList());

  @override
  Future<domain.EmailMessage?> byId(int id) async {
    final row = await _db.emailsDao.getById(id);
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<String?> loadBody(int emailId) async {
    final row = await _db.emailsDao.getById(emailId);
    final encrypted = row?.bodyEncrypted;
    if (encrypted == null) return null;
    return _crypto.decryptString(encrypted);
  }

  @override
  Future<void> markRead(List<int> emailIds, {bool read = true}) =>
      _db.emailsDao.markRead(emailIds, read: read);

  @override
  Future<void> delete(List<int> emailIds) =>
      _db.emailsDao.deleteByIds(emailIds);

  @override
  Future<void> blockSender(String pattern, {String reason = 'manual'}) =>
      _db.emailsDao.blockSender(pattern.toLowerCase(), reason);

  @override
  Future<InboxStats> collectStats() async {
    final dao = _db.emailsDao;
    final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
    final newsletters = await _db.newslettersDao.getAll();

    return InboxStats(
      totalEmails: await dao.totalCount(),
      unreadCount: await dao.unreadCount(),
      newsletterCount: await dao.newsletterCount(),
      activeNewsletterSenders: await _db.newslettersDao.activeCount(),
      ignoredNewsletterSenders: newsletters
          .where(
            (n) =>
                n.emailCount >= 5 &&
                (n.emailCount - n.unreadCount) / n.emailCount < 0.2,
          )
          .length,
      oldUnreadCount: await dao.oldUnreadCount(sixMonthsAgo),
      spfPassCount: await dao.spfPassCount(),
      dkimPassCount: await dao.dkimPassCount(),
      dmarcPassCount: await dao.dmarcPassCount(),
      authEvaluatedCount: await dao.authEvaluatedCount(),
      highRiskCount: await dao.highRiskCount(),
      mediumRiskCount: await dao.mediumRiskCount(),
      suspiciousDomainsBlocked: (await dao.allBlockedSenders())
          .where((b) => b.reason == 'phishing')
          .length,
      trackedEmailCount: await dao.trackedEmailCount(),
      trackerTotal: await dao.sumTrackerCount(),
      answeredNeededCount: await dao.countWhere(
        (e) => e.isNewsletter.equals(false) & e.isRead.equals(true),
      ),
      unansweredCount: await dao.countWhere(
        (e) =>
            e.isNewsletter.equals(false) &
            e.isRead.equals(true) &
            e.isAnswered.equals(false),
      ),
    );
  }

  @override
  Future<Set<String>> knownSenderAddresses() async =>
      (await _db.emailsDao.knownSenderAddresses())
          .map((a) => a.toLowerCase())
          .toSet();

  static List<domain.EmailFinding> _parseFindings(String json) {
    try {
      return [
        for (final item
            in (jsonDecode(json) as List<dynamic>).cast<Map<String, dynamic>>())
          domain.EmailFinding(
            severity: item['severity'] as String? ?? 'info',
            message: item['message'] as String? ?? '',
          ),
      ];
    } on FormatException {
      return const [];
    }
  }

  static domain.EmailMessage _toEntity(Email row) => domain.EmailMessage(
        id: row.id,
        accountId: row.accountId,
        folderId: row.folderId,
        uid: row.uid,
        messageId: row.messageId,
        threadId: row.threadId,
        subject: row.subject,
        fromName: row.fromName,
        fromAddress: row.fromAddress,
        toAddresses: (jsonDecode(row.toAddresses) as List<dynamic>).cast(),
        ccAddresses: (jsonDecode(row.ccAddresses) as List<dynamic>).cast(),
        date: row.date,
        snippet: row.snippet,
        bodyIsHtml: row.bodyIsHtml,
        isRead: row.isRead,
        isFlagged: row.isFlagged,
        isAnswered: row.isAnswered,
        hasAttachments: row.hasAttachments,
        sizeBytes: row.sizeBytes,
        spf: row.spf,
        dkim: row.dkim,
        dmarc: row.dmarc,
        phishingScore: row.phishingScore,
        phishingLevel: row.phishingLevel,
        findings: _parseFindings(row.phishingFindings),
        trackerCount: row.trackerCount,
        externalResourceCount: row.externalResourceCount,
        privacyScore: row.privacyScore,
        isNewsletter: row.isNewsletter,
        unsubscribeUrl: row.unsubscribeUrl,
        unsubscribeMailto: row.unsubscribeMailto,
      );
}
