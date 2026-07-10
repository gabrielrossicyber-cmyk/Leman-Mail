import 'package:drift/drift.dart';

import '../../../domain/entities/newsletter_sender.dart'
    show NewsletterStatus;
import '../app_database.dart';

part 'newsletters_dao.g.dart';

@DriftAccessor(tables: [NewsletterSenders])
class NewslettersDao extends DatabaseAccessor<AppDatabase>
    with _$NewslettersDaoMixin {
  NewslettersDao(super.db);

  Stream<List<NewsletterSender>> watchActive({int? accountId}) {
    final query = select(newsletterSenders)
      ..where((n) => n.status.equalsValue(NewsletterStatus.active))
      ..orderBy([(n) => OrderingTerm.desc(n.emailCount)]);
    if (accountId != null) {
      query.where((n) => n.accountId.equals(accountId));
    }
    return query.watch();
  }

  Future<int> activeCount() async {
    final countExp = newsletterSenders.id.count();
    final query = selectOnly(newsletterSenders)
      ..addColumns([countExp])
      ..where(
        newsletterSenders.status.equalsValue(NewsletterStatus.active),
      );
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<int> countByStatus(NewsletterStatus status) async {
    final countExp = newsletterSenders.id.count();
    final query = selectOnly(newsletterSenders)
      ..addColumns([countExp])
      ..where(newsletterSenders.status.equalsValue(status));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<List<NewsletterSender>> getAll() => select(newsletterSenders).get();

  /// Called by the analysis pipeline for every detected newsletter email:
  /// creates or refreshes the per-sender aggregate.
  Future<void> recordNewsletterEmail({
    required int accountId,
    required String senderAddress,
    required String senderName,
    required DateTime receivedAt,
    required int sizeBytes,
    required bool wasUnread,
    String? unsubscribeUrl,
    String? unsubscribeMailto,
    bool supportsOneClick = false,
  }) async {
    final address = senderAddress.toLowerCase();
    final existing = await (select(newsletterSenders)
          ..where(
            (n) =>
                n.accountId.equals(accountId) &
                n.senderAddress.equals(address),
          ))
        .getSingleOrNull();

    if (existing == null) {
      await into(newsletterSenders).insert(
        NewsletterSendersCompanion.insert(
          accountId: accountId,
          senderAddress: address,
          senderName: Value(senderName),
          emailCount: const Value(1),
          unreadCount: Value(wasUnread ? 1 : 0),
          totalSizeBytes: Value(sizeBytes),
          lastEmailAt: receivedAt,
          unsubscribeUrl: Value(unsubscribeUrl),
          unsubscribeMailto: Value(unsubscribeMailto),
          supportsOneClick: Value(supportsOneClick),
        ),
      );
    } else {
      await (update(newsletterSenders)
            ..where((n) => n.id.equals(existing.id)))
          .write(
        NewsletterSendersCompanion(
          emailCount: Value(existing.emailCount + 1),
          unreadCount: Value(existing.unreadCount + (wasUnread ? 1 : 0)),
          totalSizeBytes: Value(existing.totalSizeBytes + sizeBytes),
          lastEmailAt: Value(
            receivedAt.isAfter(existing.lastEmailAt)
                ? receivedAt
                : existing.lastEmailAt,
          ),
          unsubscribeUrl: Value(unsubscribeUrl ?? existing.unsubscribeUrl),
          unsubscribeMailto:
              Value(unsubscribeMailto ?? existing.unsubscribeMailto),
          supportsOneClick:
              Value(supportsOneClick || existing.supportsOneClick),
        ),
      );
    }
  }

  Future<void> setStatus(int senderId, NewsletterStatus status) =>
      (update(newsletterSenders)..where((n) => n.id.equals(senderId)))
          .write(NewsletterSendersCompanion(status: Value(status)));
}
