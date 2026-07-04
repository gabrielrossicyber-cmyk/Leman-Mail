import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/error/failures.dart';
import '../../../domain/entities/account.dart' as domain;
import '../../../domain/repositories/account_repository.dart';
import '../../database/app_database.dart';
import 'imap_service.dart';
import 'mail_sync_service.dart';

/// Téléchargement des pièces jointes à la demande.
///
/// Le contenu n'est pas stocké en base (les corps le sont déjà) : on
/// re-fetch le message par UID au moment de l'ouverture, on extrait le
/// segment MIME et on l'écrit dans le répertoire temporaire de l'app —
/// en clair, car les visionneuses système (PDF, images) ne savent lire
/// que des fichiers ordinaires ; le répertoire est sous le sandbox de
/// l'app et purgé par l'OS.
class AttachmentService {
  AttachmentService(this._db, this._accounts);

  final AppDatabase _db;
  final AccountRepository _accounts;

  /// Télécharge (avec cache) la pièce jointe et retourne le chemin local.
  Future<String> downloadToTemp({
    required int emailId,
    required String fileName,
  }) async {
    final email = await _db.emailsDao.getById(emailId);
    if (email == null) {
      throw const MailProtocolFailure('Email introuvable.');
    }

    final cacheDir = await getTemporaryDirectory();
    final filePath = p.join(
      cacheDir.path,
      'attachments',
      '$emailId',
      fileName,
    );
    final cached = File(filePath);
    if (await cached.exists()) return filePath;

    final folderRow = await (_db.select(_db.folders)
          ..where((f) => f.id.equals(email.folderId)))
        .getSingle();
    final accountRow = await (_db.select(_db.accounts)
          ..where((a) => a.id.equals(email.accountId)))
        .getSingle();

    if (accountRow.authMethod != domain.AuthMethod.password) {
      throw const MailProtocolFailure(
        'Téléchargement disponible pour les comptes IMAP pour l\'instant.',
      );
    }
    final credentials = await _accounts.credentialsOf(accountRow.uuid);
    final password = credentials?.password;
    if (password == null) {
      throw const AuthenticationFailure('Identifiants introuvables.');
    }

    final account = domain.Account(
      id: accountRow.id,
      uuid: accountRow.uuid,
      email: accountRow.email,
      displayName: accountRow.displayName,
      provider: accountRow.provider,
      authMethod: accountRow.authMethod,
      imapHost: accountRow.imapHost,
      imapPort: accountRow.imapPort,
      imapTls: accountRow.imapTls,
    );

    final service = ImapService();
    List<int>? bytes;
    await service.connect(account, secret: password);
    try {
      bytes = await service.fetchAttachmentBytes(
        RemoteFolder(
          path: folderRow.path,
          name: folderRow.name,
          type: folderRow.type,
        ),
        email.uid,
        fileName,
      );
    } finally {
      await service.disconnect();
    }

    if (bytes == null) {
      throw const MailProtocolFailure(
        'Pièce jointe introuvable dans le message d\'origine.',
      );
    }

    await cached.create(recursive: true);
    await cached.writeAsBytes(bytes, flush: true);
    return filePath;
  }
}
