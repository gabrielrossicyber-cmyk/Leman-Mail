import 'package:enough_mail/enough_mail.dart';

import '../../../core/error/failures.dart';
import '../../../domain/entities/account.dart' as domain;
import '../../../domain/entities/email_message.dart';
import 'mail_sync_service.dart';

/// IMAP implementation of [MailSyncService] built on `enough_mail`.
/// Works with any RFC 3501 server (Infomaniak, Fastmail, Yahoo, Proton
/// Bridge, self-hosted...). TLS is mandatory unless the account
/// explicitly opts out (localhost bridges only).
class ImapService implements MailSyncService {
  ImapService();

  ImapClient? _client;
  domain.Account? _account;

  @override
  domain.MailProvider get provider => domain.MailProvider.imap;

  @override
  Future<void> connect(domain.Account account, {required String secret}) async {
    final host = account.imapHost;
    if (host == null || host.isEmpty) {
      throw const MailProtocolFailure('Hôte IMAP manquant.');
    }
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(
        host,
        account.imapPort,
        isSecure: account.imapTls,
      );
      if (account.authMethod == domain.AuthMethod.oauth2) {
        await client.authenticateWithOAuth2(account.email, secret);
      } else {
        await client.login(account.email, secret);
      }
    } on ImapException catch (e) {
      throw AuthenticationFailure(
        'Identifiants refusés pour ${account.email} — vérifiez l\'adresse et '
        'le mot de passe d\'application.',
        cause: e,
      );
    } on Exception catch (e) {
      throw NetworkFailure(
        'Impossible de joindre $host:${account.imapPort} — vérifiez le '
        'serveur IMAP et votre connexion.',
        cause: e,
      );
    }
    _client = client;
    _account = account;
  }

  @override
  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    _account = null;
    if (client != null && client.isConnected) {
      try {
        await client.logout();
      } on ImapException {
        // Best effort — the socket may already be gone.
      }
    }
  }

  ImapClient get _connected {
    final client = _client;
    if (client == null || !client.isConnected) {
      throw const MailProtocolFailure('Client IMAP non connecté.');
    }
    return client;
  }

  @override
  Future<List<RemoteFolder>> listFolders() async {
    final boxes = await _connected.listMailboxes(recursive: true);
    return [
      for (final box in boxes)
        RemoteFolder(
          // encodedPath = forme protocolaire (UTF-7 modifié) : c'est elle
          // qu'il faut renvoyer au serveur. Les chemins Gmail localisés
          // (« [Gmail]/Messages envoyés ») cassent le SELECT sinon
          // (BAD Could not parse command).
          path: box.encodedPath,
          name: box.name,
          type: _folderType(box),
          uidValidity: box.uidValidity,
        ),
    ];
  }

  /// Sélectionne un dossier à partir du chemin protocolaire stocké,
  /// en laissant enough_mail gérer le quoting de la commande SELECT.
  /// La liste de flags doit être modifiable : la bibliothèque y ajoute
  /// des drapeaux au fil des réponses du serveur.
  Future<Mailbox> _selectFolder(RemoteFolder folder) {
    final mailbox = Mailbox(
      encodedName: folder.name,
      encodedPath: folder.path,
      flags: <MailboxFlag>[],
      pathSeparator: '/',
    );
    return _connected.selectMailbox(mailbox);
  }

  static String _folderType(Mailbox box) {
    if (box.isInbox) return 'inbox';
    if (box.isSent) return 'sent';
    if (box.isDrafts) return 'drafts';
    if (box.isTrash) return 'trash';
    if (box.isJunk) return 'spam';
    if (box.isArchive) return 'archive';
    return 'other';
  }

  static const _fetchCriteria = '(UID FLAGS RFC822.SIZE BODY.PEEK[])';

  @override
  Future<List<RawEmail>> fetchNewMessages(
    RemoteFolder folder, {
    int sinceUid = 0,
    int limit = 50,
  }) async {
    final client = _connected;
    final mailbox = await _selectFolder(folder);
    final exists = mailbox.messagesExists;
    if (exists == 0) return const [];

    // Curseur à jour ? Rien à récupérer.
    final uidNext = mailbox.uidNext;
    if (sinceUid > 0 && uidNext != null && uidNext <= sinceUid + 1) {
      return const [];
    }

    // Une seule primitive pour l'initial ET l'incrémental : fenêtre des
    // [limit] derniers messages par numéros de séquence, filtrée ensuite
    // par UID > curseur. Même plafond de perte que l'ancien chemin
    // UID FETCH x:* (troncature à [limit]), mais un seul chemin de code.
    final start = exists > limit ? exists - limit + 1 : 1;
    final fetch = await client.fetchMessages(
      MessageSequence.fromRange(start, exists),
      _fetchCriteria,
    );

    return <RawEmail>[
      for (final message in fetch.messages)
        if ((message.uid ?? 0) > sinceUid) _toRawEmail(message),
    ]..sort((a, b) => a.uid.compareTo(b.uid));
  }

  /// Télécharge une pièce jointe à la demande : re-fetch du message
  /// complet par UID puis extraction du segment MIME correspondant.
  Future<List<int>?> fetchAttachmentBytes(
    RemoteFolder folder,
    int uid,
    String fileName,
  ) async {
    final client = _connected;
    await _selectFolder(folder);
    final fetch = await client.uidFetchMessages(
      MessageSequence.fromIds([uid], isUid: true),
      '(UID BODY.PEEK[])',
    );
    if (fetch.messages.isEmpty) return null;
    final message = fetch.messages.first;
    for (final info in message.findContentInfo()) {
      if (info.fileName == fileName) {
        return message.getPart(info.fetchId)?.decodeContentBinary();
      }
    }
    return null;
  }

  RawEmail _toRawEmail(MimeMessage message) {
    final headers = <String, String>{
      for (final header in message.headers ?? const <Header>[])
        header.name.toLowerCase(): header.value ?? '',
    };

    final from = message.from?.isNotEmpty == true
        ? message.from!.first
        : const MailAddress('', 'unknown@unknown');

    final attachments = <EmailAttachmentInfo>[
      for (final info in message.findContentInfo())
        EmailAttachmentInfo(
          fileName: info.fileName ?? 'sans-nom',
          mimeType: info.mediaType?.text ?? 'application/octet-stream',
          sizeBytes: info.size ?? 0,
        ),
    ];

    return RawEmail(
      uid: message.uid ?? 0,
      messageId: headers['message-id'] ?? 'uid-${message.uid}@${_account?.email}',
      subject: message.decodeSubject() ?? '',
      fromName: from.personalName ?? '',
      fromAddress: from.email,
      toAddresses: [
        for (final to in message.to ?? const <MailAddress>[]) to.email,
      ],
      ccAddresses: [
        for (final cc in message.cc ?? const <MailAddress>[]) cc.email,
      ],
      replyToAddress: message.replyTo?.isNotEmpty == true
          ? message.replyTo!.first.email
          : null,
      date: message.decodeDate() ?? DateTime.now(),
      headers: headers,
      bodyPlain: message.decodeTextPlainPart(),
      bodyHtml: message.decodeTextHtmlPart(),
      isRead: message.isSeen,
      isFlagged: message.isFlagged,
      isAnswered: message.isAnswered,
      sizeBytes: message.size ?? 0,
      attachments: attachments,
    );
  }

  @override
  Future<void> markRead(
    RemoteFolder folder,
    List<int> uids, {
    bool read = true,
  }) async {
    final client = _connected;
    await _selectFolder(folder);
    final sequence = MessageSequence.fromIds(uids, isUid: true);
    await client.uidStore(
      sequence,
      [MessageFlags.seen],
      action: read ? StoreAction.add : StoreAction.remove,
    );
  }

  @override
  Future<void> setFlagged(
    RemoteFolder folder,
    List<int> uids, {
    required bool flagged,
  }) async {
    final client = _connected;
    await _selectFolder(folder);
    final sequence = MessageSequence.fromIds(uids, isUid: true);
    await client.uidStore(
      sequence,
      [MessageFlags.flagged],
      action: flagged ? StoreAction.add : StoreAction.remove,
    );
  }

  @override
  Future<void> deleteMessages(RemoteFolder folder, List<int> uids) async {
    final client = _connected;
    await _selectFolder(folder);
    final sequence = MessageSequence.fromIds(uids, isUid: true);
    await client.uidStore(
      sequence,
      [MessageFlags.deleted],
      action: StoreAction.add,
    );
    await client.expunge();
  }

  @override
  Future<void> moveToFolder(
    RemoteFolder from,
    RemoteFolder to,
    List<int> uids,
  ) async {
    final client = _connected;
    await _selectFolder(from);
    final sequence = MessageSequence.fromIds(uids, isUid: true);
    final target = Mailbox(
      encodedName: to.name,
      encodedPath: to.path,
      flags: const [],
      pathSeparator: '/',
    );
    await client.uidMove(sequence, targetMailbox: target);
  }
}
