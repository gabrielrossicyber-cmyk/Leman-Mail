import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../domain/entities/newsletter_sender.dart' as domain;
import '../../domain/repositories/newsletter_repository.dart';
import '../database/app_database.dart';

class NewsletterRepositoryImpl implements NewsletterRepository {
  NewsletterRepositoryImpl(this._db, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final AppDatabase _db;
  final http.Client _http;

  @override
  Stream<List<domain.NewsletterSender>> watchActive({int? accountId}) =>
      _db.newslettersDao
          .watchActive(accountId: accountId)
          .map((rows) => rows.map(_toEntity).toList());

  @override
  Future<int> activeCount() => _db.newslettersDao.activeCount();

  @override
  Future<int> unsubscribedCount() =>
      _db.newslettersDao.countByStatus(domain.NewsletterStatus.unsubscribed);

  @override
  Future<UnsubscribeResult> unsubscribe(domain.NewsletterSender sender) async {
    // RFC 8058 one-click: a single authenticated-by-design POST, no UI.
    if (sender.supportsOneClick && sender.unsubscribeUrl != null) {
      try {
        final response = await _http.post(
          Uri.parse(sender.unsubscribeUrl!),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'List-Unsubscribe=One-Click',
        );
        if (response.statusCode < 400) {
          await _db.newslettersDao
              .setStatus(sender.id, domain.NewsletterStatus.unsubscribed);
          return const UnsubscribeResult(UnsubscribeOutcome.oneClickDone);
        }
      } on Exception {
        // Fall through to the manual paths below.
      }
    }

    if (sender.unsubscribeUrl != null) {
      // The UI opens the URL in a browser, then confirms the status change.
      return UnsubscribeResult(
        UnsubscribeOutcome.openUrl,
        target: sender.unsubscribeUrl,
      );
    }
    if (sender.unsubscribeMailto != null) {
      return UnsubscribeResult(
        UnsubscribeOutcome.sendMailto,
        target: sender.unsubscribeMailto,
      );
    }
    return const UnsubscribeResult(UnsubscribeOutcome.unavailable);
  }

  /// Called by the UI after a manual unsubscribe completes.
  Future<void> confirmUnsubscribed(domain.NewsletterSender sender) =>
      _db.newslettersDao
          .setStatus(sender.id, domain.NewsletterStatus.unsubscribed);

  @override
  Future<void> block(domain.NewsletterSender sender) async {
    await _db.emailsDao.blockSender(sender.senderAddress, 'newsletter');
    await _db.newslettersDao
        .setStatus(sender.id, domain.NewsletterStatus.blocked);
  }

  @override
  Future<void> archiveAllFrom(domain.NewsletterSender sender) async {
    // Local archive: mark read; the sync layer mirrors moves to the server.
    final ids = await _emailIdsFrom(sender);
    await _db.emailsDao.markRead(ids);
    await _db.newslettersDao
        .setStatus(sender.id, domain.NewsletterStatus.archived);
  }

  @override
  Future<void> deleteAllFrom(domain.NewsletterSender sender) async {
    final ids = await _emailIdsFrom(sender);
    await _db.emailsDao.deleteByIds(ids);
  }

  Future<List<int>> _emailIdsFrom(domain.NewsletterSender sender) async {
    final rows = await (_db.select(_db.emails)
          ..where(
            (e) =>
                e.accountId.equals(sender.accountId) &
                e.fromAddress.equals(sender.senderAddress),
          ))
        .get();
    return rows.map((e) => e.id).toList();
  }

  static domain.NewsletterSender _toEntity(NewsletterSender row) =>
      domain.NewsletterSender(
        id: row.id,
        accountId: row.accountId,
        senderAddress: row.senderAddress,
        senderName: row.senderName,
        emailCount: row.emailCount,
        unreadCount: row.unreadCount,
        totalSizeBytes: row.totalSizeBytes,
        lastEmailAt: row.lastEmailAt,
        unsubscribeUrl: row.unsubscribeUrl,
        unsubscribeMailto: row.unsubscribeMailto,
        supportsOneClick: row.supportsOneClick,
        status: row.status,
      );
}
