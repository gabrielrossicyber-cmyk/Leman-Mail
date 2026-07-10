import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leman_mail/data/database/app_database.dart';
import 'package:leman_mail/data/database/daos/emails_dao.dart';
import 'package:leman_mail/domain/entities/account.dart';
import 'package:leman_mail/domain/entities/email_message.dart' as domain;
import 'package:leman_mail/domain/entities/newsletter_sender.dart'
    show NewsletterStatus;

/// Tests d'intégration de la couche données sur une vraie base SQLite en
/// mémoire : le schéma, les migrations (FTS5 + triggers compris), les DAOs
/// et la file d'opérations serveur sont exercés tels qu'en production.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> addAccount({String uuid = 'acc-1'}) =>
      db.accountsDao.insertAccount(
        AccountsCompanion.insert(
          uuid: uuid,
          email: '$uuid@leman.test',
          displayName: uuid,
          provider: MailProvider.imap,
          authMethod: AuthMethod.password,
        ),
      );

  Future<int> addFolder(
    int accountId, {
    String path = 'INBOX',
    String type = 'inbox',
  }) =>
      db.accountsDao.upsertFolder(
        FoldersCompanion.insert(
          accountId: accountId,
          path: path,
          name: path,
          type: Value(type),
        ),
      );

  Future<int> addEmail(
    int accountId,
    int folderId, {
    required int uid,
    String subject = 'Sujet',
    String from = 'expediteur@exemple.ch',
    String fromName = 'Expéditeur',
    bool isRead = false,
    String? threadId,
    DateTime? date,
  }) =>
      db.emailsDao.upsert(
        EmailsCompanion.insert(
          accountId: accountId,
          folderId: folderId,
          uid: uid,
          messageId: '<$uid@test>',
          fromAddress: from,
          fromName: Value(fromName),
          subject: Value(subject),
          date: date ?? DateTime(2026, 7, uid.clamp(1, 28)),
          isRead: Value(isRead),
          threadId: Value(threadId),
        ),
      );

  group('Dossiers', () {
    test('upsertFolder est keyé sur (compte, chemin) et garde un id stable',
        () async {
      final accountId = await addAccount();
      final first = await addFolder(accountId);
      final second = await addFolder(accountId);
      expect(second, first);
      expect(await db.accountsDao.foldersOf(accountId), hasLength(1));
    });
  });

  group('Emails + file d\'opérations serveur', () {
    test('upsert sur clé (compte, dossier, uid) ne duplique pas', () async {
      final accountId = await addAccount();
      final folderId = await addFolder(accountId);
      await addEmail(accountId, folderId, uid: 1, subject: 'Premier');
      await addEmail(accountId, folderId, uid: 1, subject: 'Corrigé');
      expect(await db.emailsDao.totalCount(), 1);
    });

    test('markRead met à jour la ligne ET enfile l\'opération serveur',
        () async {
      final accountId = await addAccount();
      final folderId = await addFolder(accountId);
      final emailId = await addEmail(accountId, folderId, uid: 7);

      await db.emailsDao.markRead([emailId]);

      final row = await db.emailsDao.getById(emailId);
      expect(row!.isRead, isTrue);

      final ops = await db.select(db.pendingOperations).get();
      expect(ops, hasLength(1));
      expect(ops.single.operation, PendingOpType.markRead);
      expect(ops.single.uid, 7);
      expect(ops.single.accountId, accountId);
    });

    test('deleteByIds capture le UID serveur AVANT la suppression locale',
        () async {
      final accountId = await addAccount();
      final folderId = await addFolder(accountId);
      final emailId = await addEmail(accountId, folderId, uid: 42);

      await db.emailsDao.deleteByIds([emailId]);

      expect(await db.emailsDao.getById(emailId), isNull);
      final ops = await db.select(db.pendingOperations).get();
      expect(ops.single.operation, PendingOpType.delete);
      expect(ops.single.uid, 42);
    });

    test('setFlagged enfile flag puis unflag', () async {
      final accountId = await addAccount();
      final folderId = await addFolder(accountId);
      final emailId = await addEmail(accountId, folderId, uid: 3);

      await db.emailsDao.setFlagged([emailId], flagged: true);
      await db.emailsDao.setFlagged([emailId], flagged: false);

      final ops = await db.select(db.pendingOperations).get();
      expect(
        ops.map((o) => o.operation),
        [PendingOpType.flag, PendingOpType.unflag],
      );
      expect((await db.emailsDao.getById(emailId))!.isFlagged, isFalse);
    });

    test('watchInbox filtre par dossier et par statut non lu', () async {
      final accountId = await addAccount();
      final inboxId = await addFolder(accountId);
      final sentId =
          await addFolder(accountId, path: 'Sent', type: 'sent');
      await addEmail(accountId, inboxId, uid: 1, isRead: false);
      await addEmail(accountId, inboxId, uid: 2, isRead: true);
      await addEmail(accountId, sentId, uid: 3, isRead: true);

      final inbox = await db.emailsDao
          .watchInbox(folderType: 'inbox')
          .first;
      expect(inbox, hasLength(2));

      final unread = await db.emailsDao
          .watchInbox(folderType: 'inbox', filter: InboxFilter.unread)
          .first;
      expect(unread.single.uid, 1);

      final sent =
          await db.emailsDao.watchInbox(folderType: 'sent').first;
      expect(sent.single.uid, 3);
    });

    test(
        'purgeFolderLocal vide le dossier et sa file SANS enfiler '
        'd\'opérations serveur (cas UIDVALIDITY)', () async {
      final accountId = await addAccount();
      final folderId = await addFolder(accountId);
      final otherFolderId =
          await addFolder(accountId, path: 'Sent', type: 'sent');
      final emailId = await addEmail(accountId, folderId, uid: 1);
      final keptId = await addEmail(accountId, otherFolderId, uid: 2);
      // Une opération en attente sur le dossier purgé + une sur l'autre.
      await db.emailsDao.markRead([emailId]);
      await db.emailsDao.markRead([keptId]);

      await db.emailsDao.purgeFolderLocal(folderId);

      expect(await db.emailsDao.getById(emailId), isNull);
      expect(await db.emailsDao.getById(keptId), isNotNull);
      final ops = await db.select(db.pendingOperations).get();
      // Seule l'opération de l'autre dossier survit ; la purge n'a rien
      // enfilé de nouveau.
      expect(ops, hasLength(1));
      expect(ops.single.folderId, otherFolderId);
    });

    test('watchThread retourne le fil du plus ancien au plus récent',
        () async {
      final accountId = await addAccount();
      final folderId = await addFolder(accountId);
      await addEmail(accountId, folderId, uid: 2, threadId: '<root@t>');
      await addEmail(accountId, folderId, uid: 5, threadId: '<root@t>');
      await addEmail(accountId, folderId, uid: 9, threadId: '<autre@t>');

      final thread = await db.emailsDao.watchThread('<root@t>').first;
      expect(thread.map((e) => e.uid), [2, 5]);
    });
  });

  group('Recherche FTS5', () {
    test('trouve par préfixe de sujet et par expéditeur', () async {
      final accountId = await addAccount();
      final folderId = await addFolder(accountId);
      await addEmail(
        accountId,
        folderId,
        uid: 1,
        subject: 'Facture Digitec juillet',
        from: 'billing@digitec.ch',
      );
      await addEmail(
        accountId,
        folderId,
        uid: 2,
        subject: 'Réunion de chantier',
        from: 'marie@partenaire.ch',
      );

      expect(await db.emailsDao.search('factur digi'), hasLength(1));
      expect(await db.emailsDao.search('marie'), hasLength(1));
      expect(await db.emailsDao.search('inexistant'), isEmpty);
    });

    test('les triggers réindexent à la mise à jour et à la suppression',
        () async {
      final accountId = await addAccount();
      final folderId = await addFolder(accountId);
      final emailId =
          await addEmail(accountId, folderId, uid: 1, subject: 'Ancien');

      await addEmail(accountId, folderId, uid: 1, subject: 'Nouveau');
      expect(await db.emailsDao.search('Ancien'), isEmpty);
      expect(await db.emailsDao.search('Nouveau'), hasLength(1));

      await db.emailsDao.deleteByIds([emailId]);
      expect(await db.emailsDao.search('Nouveau'), isEmpty);
    });
  });

  group('Newsletters', () {
    test('recordNewsletterEmail crée puis agrège par expéditeur', () async {
      final accountId = await addAccount();
      Future<void> record({bool unread = true}) =>
          db.newslettersDao.recordNewsletterEmail(
            accountId: accountId,
            senderAddress: 'Promo@Zalando.ch',
            senderName: 'Zalando',
            receivedAt: DateTime(2026, 7, 1),
            sizeBytes: 1000,
            wasUnread: unread,
          );

      await record();
      await record(unread: false);

      final senders = await db.newslettersDao.getAll();
      expect(senders, hasLength(1));
      expect(senders.single.senderAddress, 'promo@zalando.ch');
      expect(senders.single.emailCount, 2);
      expect(senders.single.unreadCount, 1);
      expect(senders.single.totalSizeBytes, 2000);
    });

    test('setStatus sort l\'expéditeur du décompte actif', () async {
      final accountId = await addAccount();
      await db.newslettersDao.recordNewsletterEmail(
        accountId: accountId,
        senderAddress: 'news@a.ch',
        senderName: 'A',
        receivedAt: DateTime(2026, 7, 1),
        sizeBytes: 1,
        wasUnread: true,
      );
      expect(await db.newslettersDao.activeCount(), 1);

      final sender = (await db.newslettersDao.getAll()).single;
      await db.newslettersDao
          .setStatus(sender.id, NewsletterStatus.unsubscribed);
      expect(await db.newslettersDao.activeCount(), 0);
      expect(
        await db.newslettersDao
            .countByStatus(NewsletterStatus.unsubscribed),
        1,
      );
    });
  });

  group('Santé & badges', () {
    test('un seul snapshot global par jour (les NULL ne dupliquent pas)',
        () async {
      HealthSnapshotsCompanion snapshot(int score) =>
          HealthSnapshotsCompanion.insert(
            accountId: const Value(null),
            day: DateTime.utc(2026, 7, 5),
            totalScore: score,
            securityScore: score,
            clutterScore: score,
            privacyScore: score,
            organizationScore: score,
          );

      await db.healthDao.saveSnapshot(snapshot(70));
      await db.healthDao.saveSnapshot(snapshot(85));

      final rows =
          await db.healthDao.snapshotsSince(DateTime.utc(2026, 1, 1));
      expect(rows, hasLength(1));
      expect(rows.single.totalScore, 85);
    });

    test('unlockBadge est idempotent', () async {
      await db.healthDao.unlockBadge('inbox_clean');
      await db.healthDao.unlockBadge('inbox_clean');
      expect(await db.healthDao.unlockedBadgeIds(), {'inbox_clean'});
    });
  });

  group('Brouillons', () {
    test('cycle complet : création, mise à jour, suppression', () async {
      final id = await db.saveDraft(
        to: 'a@b.ch',
        cc: '',
        bcc: '',
        subject: 'Brouillon',
        body: 'Corps',
      );

      final updated = await db.saveDraft(
        id: id,
        to: 'a@b.ch',
        cc: 'c@d.ch',
        bcc: '',
        subject: 'Brouillon v2',
        body: 'Corps v2',
        inReplyTo: '<origin@t>',
      );
      expect(updated, id);

      final drafts = await db.watchDrafts().first;
      expect(drafts.single.subject, 'Brouillon v2');
      expect(drafts.single.inReplyTo, '<origin@t>');

      await db.deleteDraftById(id);
      expect(await db.watchDrafts().first, isEmpty);
    });
  });

  group('Enums persistés', () {
    test('les niveaux de risque écrits sont relus correctement', () async {
      final accountId = await addAccount();
      final folderId = await addFolder(accountId);
      final emailId = await db.emailsDao.upsert(
        EmailsCompanion.insert(
          accountId: accountId,
          folderId: folderId,
          uid: 99,
          messageId: '<99@test>',
          fromAddress: 'x@y.ch',
          date: DateTime(2026, 7, 4),
          phishingLevel: const Value(domain.RiskLevel.high),
          spf: const Value(domain.AuthResult.fail),
        ),
      );
      final row = await db.emailsDao.getById(emailId);
      expect(row!.phishingLevel, domain.RiskLevel.high);
      expect(row.spf, domain.AuthResult.fail);
      expect(await db.emailsDao.highRiskCount(), 1);
      expect(await db.emailsDao.spfPassCount(), 0);
    });
  });
}
