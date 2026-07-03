import 'package:enough_mail/enough_mail.dart';

import '../../../core/error/failures.dart';
import '../../../domain/entities/account.dart' as domain;

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
        ..subject = subject;
      if (htmlBody != null) {
        builder.addMultipartAlternative(plainText: textBody, htmlText: htmlBody);
      } else {
        builder.addTextPlain(textBody);
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
