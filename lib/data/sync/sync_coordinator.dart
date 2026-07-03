import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/failures.dart';
import '../../core/security/crypto_service.dart';
import '../../core/utils/email_utils.dart';
import '../../domain/entities/account.dart' as domain;
import '../../domain/repositories/account_repository.dart';
import '../../domain/usecases/analyze_incoming_email.dart';
import '../database/app_database.dart';
import '../services/auth/oauth_service.dart';
import '../services/gmail/gmail_api_service.dart';
import '../services/graph/microsoft_graph_service.dart';
import '../services/mail/imap_service.dart';
import '../services/mail/mail_sync_service.dart';

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
  /// not prevent the others from syncing: failures are collected per
  /// account and reported once at the end.
  Future<int> syncAllAccounts() async {
    var newEmails = 0;
    final failures = <String, Object>{};
    for (final account in await _accounts.enabledAccounts()) {
      try {
        newEmails += await syncAccount(account);
      } on Object catch (error) {
        failures[account.email] = error;
      }
    }
    if (failures.isNotEmpty) {
      final details = failures.entries
          .map((e) => '${e.key} : ${_describe(e.value)}')
          .join('\n');
      throw MailProtocolFailure(
        newEmails > 0
            ? '$newEmails nouveaux emails, mais certains comptes ont '
                'échoué :\n$details'
            : 'Synchronisation impossible :\n$details',
      );
    }
    return newEmails;
  }

  static String _describe(Object error) =>
      error is Failure ? error.message : error.toString();

  Future<int> syncAccount(domain.Account account) async {
    final secret = await _resolveSecret(account);
    if (secret == null) return 0;

    final service = _serviceFactory(account);
    await service.connect(account, secret: secret);
    try {
      final knownSenders = (await _db.emailsDao.knownSenderAddresses())
          .map((a) => a.toLowerCase())
          .toSet();
      final contactDomains = <String>{
        for (final address in knownSenders)
          if (EmailUtils.domainOf(address) != null)
            EmailUtils.registrableDomain(EmailUtils.domainOf(address)!),
      };
      final blocked = await _db.emailsDao.allBlockedSenders();

      var total = 0;
      for (final folder in await service.listFolders()) {
        if (folder.type != 'inbox' && folder.type != 'spam') continue;
        total += await _syncFolder(
          account,
          service,
          folder,
          knownSenders: knownSenders,
          contactDomains: contactDomains,
          blockedPatterns: blocked.map((b) => b.pattern).toList(),
        );
      }
      await _db.accountsDao.updateLastSync(account.id, DateTime.now());
      return total;
    } finally {
      await service.disconnect();
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
      await _ingest(account, folderId, raw, knownSenders, contactDomains);
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

  Future<void> _ingest(
    domain.Account account,
    int folderId,
    RawEmail raw,
    Set<String> knownSenders,
    Set<String> contactDomains,
  ) async {
    final outcome = _analyze(
      raw,
      knownSenderAddresses: knownSenders,
      userContactDomains: contactDomains,
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
        threadId: Value(raw.threadId),
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
