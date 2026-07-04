import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/failures.dart';
import '../../core/security/crypto_service.dart';
import '../../core/utils/email_utils.dart';
import '../../domain/entities/account.dart' as domain;
import '../../domain/entities/email_message.dart' show RiskLevel;
import '../../domain/repositories/account_repository.dart';
import '../../domain/usecases/analyze_incoming_email.dart';
import '../database/app_database.dart';
import '../demo/demo_emails.dart';
import '../services/auth/oauth_service.dart';
import '../services/gmail/gmail_api_service.dart';
import '../services/graph/microsoft_graph_service.dart';
import '../services/mail/imap_service.dart';
import '../services/mail/mail_sync_service.dart';

/// Aperçu d'un email fraîchement synchronisé, pour les notifications.
class NewEmailSummary {
  const NewEmailSummary({
    required this.subject,
    required this.fromAddress,
    required this.fromName,
  });

  final String subject;
  final String fromAddress;
  final String fromName;
}

/// Résultat d'une passe de synchronisation complète.
class SyncReport {
  const SyncReport({
    required this.newEmailCount,
    required this.highlights,
    required this.threats,
    required this.failures,
  });

  static const empty = SyncReport(
    newEmailCount: 0,
    highlights: [],
    threats: [],
    failures: {},
  );

  final int newEmailCount;

  /// Premiers nouveaux emails non lus (aperçu de notification).
  final List<NewEmailSummary> highlights;

  /// Emails classés 🔴 risque élevé — alerte sécurité dédiée.
  final List<NewEmailSummary> threats;

  /// Comptes en échec (email → message d'erreur lisible).
  final Map<String, String> failures;

  String? get failureSummary => failures.isEmpty
      ? null
      : failures.entries.map((e) => '${e.key} : ${e.value}').join('\n');
}

class _SyncCollector {
  int count = 0;
  final List<NewEmailSummary> highlights = [];
  final List<NewEmailSummary> threats = [];

  void record({
    required String subject,
    required String fromAddress,
    required String fromName,
    required bool isThreat,
    required bool isUnread,
  }) {
    count++;
    final summary = NewEmailSummary(
      subject: subject,
      fromAddress: fromAddress,
      fromName: fromName,
    );
    if (isThreat) threats.add(summary);
    if (isUnread && highlights.length < 3) highlights.add(summary);
  }
}

/// Orchestrates a full synchronization pass:
/// account → backend service → fetch new messages → analysis pipeline →
/// encrypted persistence → newsletter aggregation → sync cursor update.
class SyncCoordinator {
  SyncCoordinator({
    required AppDatabase db,
    required AccountRepository accountRepository,
    required AnalyzeIncomingEmail analyzeEmail,
    required CryptoService crypto,
    required OAuthService oauthService,
    MailSyncService Function(domain.Account)? serviceFactory,
  })  : _db = db,
        _accounts = accountRepository,
        _analyze = analyzeEmail,
        _crypto = crypto,
        _oauth = oauthService,
        _serviceFactory = serviceFactory ?? _defaultFactory;

  final AppDatabase _db;
  final AccountRepository _accounts;
  final AnalyzeIncomingEmail _analyze;
  final CryptoService _crypto;
  final OAuthService _oauth;
  final MailSyncService Function(domain.Account) _serviceFactory;

  static MailSyncService _defaultFactory(domain.Account account) =>
      switch (account.provider) {
        domain.MailProvider.gmail => GmailApiService(),
        domain.MailProvider.outlook ||
        domain.MailProvider.microsoft365 =>
          MicrosoftGraphService(),
        _ => ImapService(),
      };

  /// Synchronizes every enabled account. Returns the number of new emails.
  ///
  /// One broken account (wrong password, unreachable Proton Bridge…) must
  /// not prevent the others from syncing: failures are collected in the
  /// report rather than thrown, so callers (UI snackbar, background
  /// notifications) each decide how to surface them.
  Future<SyncReport> syncAllAccounts() async {
    final collector = _SyncCollector();
    final failures = <String, String>{};
    for (final account in await _accounts.enabledAccounts()) {
      try {
        await _syncAccount(account, collector);
      } on Object catch (error) {
        failures[account.email] = _describe(error);
      }
    }
    if (failures.isNotEmpty && collector.count == 0) {
      throw MailProtocolFailure(
        'Synchronisation impossible :\n${_formatFailures(failures)}',
      );
    }
    return SyncReport(
      newEmailCount: collector.count,
      highlights: collector.highlights,
      threats: collector.threats,
      failures: failures,
    );
  }

  static String _formatFailures(Map<String, String> failures) =>
      failures.entries.map((e) => '${e.key} : ${e.value}').join('\n');

  static String _describe(Object error) =>
      error is Failure ? error.message : error.toString();

  /// QA/demo: injects forged messages through the REAL analysis pipeline
  /// (phishing, trackers, newsletters, cleanup scenarios). Idempotent —
  /// fixed demo UIDs make re-runs upsert. Exposed in debug builds only.
  Future<int> seedDemoEmails() async {
    final accounts = await _accounts.enabledAccounts();
    if (accounts.isEmpty) {
      throw const MailProtocolFailure(
        'Ajoutez d\'abord un compte pour recevoir les emails de test.',
      );
    }
    final account = accounts.first;
    final folderId = await _db.accountsDao.upsertFolder(
      FoldersCompanion.insert(
        accountId: account.id,
        path: 'INBOX',
        name: 'INBOX',
        type: const Value('inbox'),
      ),
    );

    var count = 0;
    for (final raw in buildDemoEmails(DateTime.now())) {
      await _ingest(account, folderId, raw, const {}, const {});
      count++;
    }
    return count;
  }

  Future<void> _syncAccount(
    domain.Account account, [
    _SyncCollector? collector,
  ]) async {
    final secret = await _resolveSecret(account);
    if (secret == null) return;

    final service = _serviceFactory(account);
    await service.connect(account, secret: secret);
    try {
      // Répercute d'abord les actions locales en attente (lu, favori,
      // suppression) — y compris celles accumulées hors-ligne.
      await _replayPendingOperations(account, service);

      final knownSenders = (await _db.emailsDao.knownSenderAddresses())
          .map((a) => a.toLowerCase())
          .toSet();
      final contactDomains = <String>{
        for (final address in knownSenders)
          if (EmailUtils.domainOf(address) != null)
            EmailUtils.registrableDomain(EmailUtils.domainOf(address)!),
      };
      final blocked = await _db.emailsDao.allBlockedSenders();

      const syncedTypes = {'inbox', 'spam', 'sent', 'archive'};
      for (final folder in await service.listFolders()) {
        if (!syncedTypes.contains(folder.type)) continue;
        await _syncFolder(
          account,
          service,
          folder,
          knownSenders: knownSenders,
          contactDomains: contactDomains,
          blockedPatterns: blocked.map((b) => b.pattern).toList(),
          // Seuls les nouveaux messages de la boîte de réception (et spam)
          // méritent une notification — pas nos propres envoyés.
          collector: folder.type == 'inbox' || folder.type == 'spam'
              ? collector
              : null,
        );
      }
      await _db.accountsDao.updateLastSync(account.id, DateTime.now());
    } finally {
      await service.disconnect();
    }
  }

  /// Rejoue la file `pending_operations` du compte vers le serveur,
  /// groupée par (dossier, opération) pour minimiser les allers-retours.
  /// Une opération qui échoue reste en file (10 tentatives max — au-delà
  /// elle est abandonnée pour ne pas empoisonner les synchronisations).
  static const _maxOpAttempts = 10;

  Future<void> _replayPendingOperations(
    domain.Account account,
    MailSyncService service,
  ) async {
    final ops = await (_db.select(_db.pendingOperations)
          ..where((o) => o.accountId.equals(account.id))
          ..orderBy([(o) => OrderingTerm.asc(o.id)]))
        .get();
    if (ops.isEmpty) return;

    final folders = {
      for (final folder in await _db.accountsDao.foldersOf(account.id))
        folder.id: folder,
    };

    final groups = <(int, PendingOpType), List<PendingOperation>>{};
    for (final op in ops) {
      groups.putIfAbsent((op.folderId, op.operation), () => []).add(op);
    }

    for (final entry in groups.entries) {
      final (folderId, operation) = entry.key;
      final group = entry.value;
      final ids = group.map((o) => o.id).toList();
      final folder = folders[folderId];
      if (folder == null) {
        // Dossier disparu : opérations caduques.
        await (_db.delete(_db.pendingOperations)
              ..where((o) => o.id.isIn(ids)))
            .go();
        continue;
      }
      final remote = RemoteFolder(
        path: folder.path,
        name: folder.name,
        type: folder.type,
      );
      final uids = group.map((o) => o.uid).toList();

      try {
        switch (operation) {
          case PendingOpType.markRead:
            await service.markRead(remote, uids);
          case PendingOpType.markUnread:
            await service.markRead(remote, uids, read: false);
          case PendingOpType.flag:
            await service.setFlagged(remote, uids, flagged: true);
          case PendingOpType.unflag:
            await service.setFlagged(remote, uids, flagged: false);
          case PendingOpType.delete:
            await service.deleteMessages(remote, uids);
        }
        await (_db.delete(_db.pendingOperations)
              ..where((o) => o.id.isIn(ids)))
            .go();
      } on Object {
        // Échec (réseau, dossier verrouillé…) : on incrémente et on
        // abandonne les opérations trop retentées.
        await (_db.update(_db.pendingOperations)
              ..where((o) => o.id.isIn(ids)))
            .write(
          PendingOperationsCompanion(
            attempts: Value(group.first.attempts + 1),
          ),
        );
        await (_db.delete(_db.pendingOperations)
              ..where(
                (o) =>
                    o.id.isIn(ids) &
                    o.attempts.isBiggerOrEqualValue(_maxOpAttempts),
              ))
            .go();
      }
    }
  }

  Future<String?> _resolveSecret(domain.Account account) async {
    final credentials = await _accounts.credentialsOf(account.uuid);
    if (credentials == null) return null;
    if (account.authMethod == domain.AuthMethod.password) {
      return credentials.password;
    }
    // OAuth: refresh proactively when the access token is stale.
    final expired = credentials.tokenExpiry == null ||
        DateTime.now().isAfter(
          credentials.tokenExpiry!.subtract(const Duration(minutes: 2)),
        );
    if (!expired) return credentials.accessToken;
    final refreshToken = credentials.refreshToken;
    if (refreshToken == null) return credentials.accessToken;
    final tokens = await _oauth.refresh(account.provider, refreshToken);
    final current = await _accounts.credentialsOf(account.uuid);
    await _accounts.updateCredentials(
      account.uuid,
      AccountCredentials(
        password: current?.password,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken ?? refreshToken,
        tokenExpiry: tokens.expiresAt,
      ),
    );
    return tokens.accessToken;
  }

  Future<int> _syncFolder(
    domain.Account account,
    MailSyncService service,
    RemoteFolder remote, {
    required Set<String> knownSenders,
    required Set<String> contactDomains,
    required List<String> blockedPatterns,
    _SyncCollector? collector,
  }) async {
    final folderId = await _db.accountsDao.upsertFolder(
      FoldersCompanion.insert(
        accountId: account.id,
        path: remote.path,
        name: remote.name,
        type: Value(remote.type),
      ),
    );

    final state = await (_db.select(_db.syncStates)
          ..where(
            (s) => s.accountId.equals(account.id) & s.folderId.equals(folderId),
          ))
        .getSingleOrNull();
    final sinceUid = state?.lastUid ?? 0;

    final messages = await service.fetchNewMessages(
      remote,
      sinceUid: sinceUid,
      limit: sinceUid == 0
          ? AppConstants.initialSyncMessageLimit
          : AppConstants.syncPageSize,
    );
    if (messages.isEmpty) return 0;

    var maxUid = sinceUid;
    for (final raw in messages) {
      if (raw.uid > maxUid) maxUid = raw.uid;
      if (_isBlocked(raw.fromAddress, blockedPatterns)) continue;
      await _ingest(
        account,
        folderId,
        raw,
        knownSenders,
        contactDomains,
        collector: collector,
      );
    }

    await _db.into(_db.syncStates).insert(
          SyncStatesCompanion.insert(
            accountId: account.id,
            folderId: Value(folderId),
            uidValidity: Value(remote.uidValidity),
            lastUid: Value(maxUid),
          ),
          mode: InsertMode.insertOrReplace,
        );
    return messages.length;
  }

  static bool _isBlocked(String fromAddress, List<String> patterns) {
    final address = fromAddress.toLowerCase();
    final senderDomain = EmailUtils.domainOf(address);
    for (final pattern in patterns) {
      if (pattern == address) return true;
      if (pattern.startsWith('*@') && senderDomain == pattern.substring(2)) {
        return true;
      }
    }
    return false;
  }

  /// Identifiant de fil de conversation.
  ///
  /// Gmail (`threadId`) et Graph (`conversationId`) le fournissent ; en
  /// IMAP on le dérive du standard RFC 5322 : la racine du fil est le
  /// premier Message-ID de `References`, sinon `In-Reply-To`, sinon le
  /// message lui-même (début de fil).
  static String _threadIdOf(RawEmail raw) {
    if (raw.threadId != null && raw.threadId!.isNotEmpty) {
      return raw.threadId!;
    }
    for (final header in const ['references', 'in-reply-to']) {
      final value = raw.headers[header];
      if (value != null) {
        final root = RegExp('<[^>]+>').firstMatch(value)?.group(0);
        if (root != null) return root;
      }
    }
    return raw.messageId;
  }

  Future<void> _ingest(
    domain.Account account,
    int folderId,
    RawEmail raw,
    Set<String> knownSenders,
    Set<String> contactDomains, {
    _SyncCollector? collector,
  }) async {
    final outcome = _analyze(
      raw,
      knownSenderAddresses: knownSenders,
      userContactDomains: contactDomains,
    );

    collector?.record(
      subject: raw.subject,
      fromAddress: raw.fromAddress,
      fromName: raw.fromName,
      isThreat: outcome.phishing.level == RiskLevel.high,
      isUnread: !raw.isRead,
    );

    final body = raw.bodyHtml ?? raw.bodyPlain ?? '';
    final encryptedBody =
        body.isEmpty ? null : await _crypto.encryptString(body);
    final plain = raw.bodyPlain ?? '';
    final snippet = plain.length > AppConstants.snippetLength
        ? plain.substring(0, AppConstants.snippetLength)
        : plain;

    final emailId = await _db.emailsDao.upsert(
      EmailsCompanion.insert(
        accountId: account.id,
        folderId: folderId,
        uid: raw.uid,
        messageId: raw.messageId,
        threadId: Value(_threadIdOf(raw)),
        subject: Value(raw.subject),
        fromName: Value(raw.fromName),
        fromAddress: raw.fromAddress.toLowerCase(),
        toAddresses: Value(jsonEncode(raw.toAddresses)),
        ccAddresses: Value(jsonEncode(raw.ccAddresses)),
        date: raw.date,
        snippet: Value(snippet.replaceAll(RegExp(r'\s+'), ' ').trim()),
        bodyEncrypted: Value(encryptedBody),
        bodyIsHtml: Value(raw.bodyHtml != null),
        isRead: Value(raw.isRead),
        isFlagged: Value(raw.isFlagged),
        isAnswered: Value(raw.isAnswered),
        hasAttachments: Value(raw.attachments.isNotEmpty),
        sizeBytes: Value(raw.sizeBytes),
        spf: Value(outcome.spf),
        dkim: Value(outcome.dkim),
        dmarc: Value(outcome.dmarc),
        phishingScore: Value(outcome.phishing.score),
        phishingLevel: Value(outcome.phishing.level),
        phishingFindings: Value(
          jsonEncode([
            for (final f in outcome.phishing.findings) f.toJson(),
          ]),
        ),
        trackerCount: Value(outcome.privacy.trackerCount),
        externalResourceCount: Value(outcome.privacy.externalResourceCount),
        privacyScore: Value(outcome.privacy.privacyScore),
        isNewsletter: Value(outcome.newsletter.isNewsletter),
        unsubscribeUrl: Value(outcome.newsletter.unsubscribeUrl),
        unsubscribeMailto: Value(outcome.newsletter.unsubscribeMailto),
        listUnsubscribePost: Value(outcome.newsletter.supportsOneClick),
        analyzedAt: Value(DateTime.now()),
      ),
    );

    if (raw.attachments.isNotEmpty) {
      await _db.emailsDao.insertAttachments([
        for (final a in raw.attachments)
          AttachmentsCompanion.insert(
            emailId: emailId,
            fileName: a.fileName,
            mimeType: a.mimeType,
            sizeBytes: Value(a.sizeBytes),
            isDangerous: Value(
              outcome.phishing.findings.any(
                (f) =>
                    f.ruleId == 'attachment' &&
                    f.message.contains(a.fileName),
              ),
            ),
          ),
      ]);
    }

    if (outcome.newsletter.isNewsletter) {
      await _db.newslettersDao.recordNewsletterEmail(
        accountId: account.id,
        senderAddress: raw.fromAddress,
        senderName: raw.fromName,
        receivedAt: raw.date,
        sizeBytes: raw.sizeBytes,
        wasUnread: !raw.isRead,
        unsubscribeUrl: outcome.newsletter.unsubscribeUrl,
        unsubscribeMailto: outcome.newsletter.unsubscribeMailto,
        supportsOneClick: outcome.newsletter.supportsOneClick,
      );
    }
  }
}
