import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';

import '../../../core/error/failures.dart';
import '../../../domain/entities/account.dart' as domain;

/// One attachment ready to send (bytes already loaded by the picker).
class OutgoingAttachment {
  const OutgoingAttachment({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;
}

/// Outgoing mail via SMTP (`enough_mail`). Gmail/Graph accounts send
/// through their REST APIs instead — this service covers every
/// IMAP-configured account.
class SmtpService {
  const SmtpService();

  Future<void> send({
    required domain.Account account,
    required String secret,
    required List<String> to,
    required String subject,
    required String textBody,
    String? htmlBody,
    List<String> cc = const [],
    List<String> bcc = const [],
    List<OutgoingAttachment> attachments = const [],
    String? inReplyTo,
    String? references,
  }) async {
    final host = account.smtpHost;
    if (host == null || host.isEmpty) {
      throw const MailProtocolFailure('Hôte SMTP manquant.');
    }

    final client = SmtpClient(
      domainFromEmail(account.email),
      isLogEnabled: false,
    );
    try {
      await client.connectToServer(
        host,
        account.smtpPort,
        isSecure: account.smtpTls,
      );
      await client.ehlo();
      if (!account.smtpTls && client.serverInfo.supportsStartTls) {
        await client.startTls();
      }
      if (account.authMethod == domain.AuthMethod.oauth2) {
        await client.authenticate(account.email, secret, AuthMechanism.xoauth2);
      } else {
        await client.authenticate(account.email, secret, AuthMechanism.plain);
      }

      final builder = MessageBuilder()
        ..from = [MailAddress(account.displayName, account.email)]
        ..to = to.map((a) => MailAddress(null, a)).toList()
        ..cc = cc.map((a) => MailAddress(null, a)).toList()
        ..bcc = bcc.map((a) => MailAddress(null, a)).toList()
        ..subject = subject;
      // En-têtes de fil (RFC 5322) : la réponse s'accroche à la
      // conversation d'origine chez le destinataire ET dans nos fils.
      if (inReplyTo != null && inReplyTo.isNotEmpty) {
        builder.addHeader('In-Reply-To', inReplyTo);
      }
      if (references != null && references.isNotEmpty) {
        builder.addHeader('References', references);
      }
      if (htmlBody != null) {
        builder.addMultipartAlternative(plainText: textBody, htmlText: htmlBody);
      } else {
        builder.addTextPlain(textBody);
      }
      for (final attachment in attachments) {
        builder.addBinary(
          attachment.bytes,
          MediaType.guessFromFileName(attachment.fileName),
          filename: attachment.fileName,
        );
      }

      final response = await client.sendMessage(builder.buildMimeMessage());
      if (!response.isOkStatus) {
        throw const MailProtocolFailure(
          'Le serveur SMTP a refusé le message.',
        );
      }
    } on SmtpException catch (e) {
      throw MailProtocolFailure('Échec de l\'envoi SMTP.', cause: e);
    } finally {
      try {
        await client.quit();
      } on Object {
        // Connection may already be closed.
      }
    }
  }

  static String domainFromEmail(String email) {
    final at = email.lastIndexOf('@');
    return at > 0 ? email.substring(at + 1) : 'localhost';
  }
}
