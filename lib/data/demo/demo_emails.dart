import '../../domain/entities/email_message.dart';
import '../services/mail/mail_sync_service.dart';

/// Forged messages exercising every analysis engine, injected through the
/// real ingestion pipeline by [SyncCoordinator.seedDemoEmails].
/// Debug builds only — this is a QA/demo tool.
///
/// UIDs start at 900000 so repeated injections upsert instead of
/// duplicating, and never collide with real IMAP UIDs.
List<RawEmail> buildDemoEmails(DateTime now) {
  var uid = 900000;
  int nextUid() => uid++;

  RawEmail newsletter({
    required String fromName,
    required String fromAddress,
    required String subject,
    required Duration age,
    bool unread = true,
    bool oneClick = false,
  }) =>
      RawEmail(
        uid: nextUid(),
        messageId: '<demo-${uid - 1}@leman.demo>',
        subject: subject,
        fromName: fromName,
        fromAddress: fromAddress,
        toAddresses: const ['vous@leman.demo'],
        date: now.subtract(age),
        isRead: !unread,
        sizeBytes: 150 * 1024,
        headers: {
          'authentication-results':
              'mx.leman.demo; spf=pass; dkim=pass; dmarc=pass',
          'list-unsubscribe':
              '<mailto:unsub@${fromAddress.split('@').last}>, '
                  '<https://${fromAddress.split('@').last}/unsubscribe?u=demo>',
          if (oneClick) 'list-unsubscribe-post': 'List-Unsubscribe=One-Click',
          'precedence': 'bulk',
        },
        bodyPlain: 'Nos offres de la semaine, rien que pour vous !',
        bodyHtml: '''
<html><body>
<img src="https://open.mailtrack.io/demo/pixel.gif" width="1" height="1">
<img src="https://cdn.list-manage.com/demo/banner.jpg" width="600" height="200">
<h1>Offres exclusives</h1>
<p>Profitez de -50% ce week-end seulement.</p>
<a href="https://${fromAddress.split('@').last}/unsubscribe?u=demo">Se désabonner</a>
</body></html>''',
      );

  return [
    // 1. 🔴 Phishing critique : typosquatting + échec total d'authentification
    //    + lien trompeur + langage d'urgence.
    RawEmail(
      uid: nextUid(),
      messageId: '<demo-phishing-1@leman.demo>',
      subject: 'URGENT : votre compte sera suspendu sous 24 heures',
      fromName: 'PayPal Sécurité',
      fromAddress: 'service@paypa1.com',
      toAddresses: const ['vous@leman.demo'],
      date: now.subtract(const Duration(hours: 2)),
      headers: const {
        'authentication-results':
            'mx.leman.demo; spf=fail smtp.mailfrom=paypa1.com; '
                'dkim=fail; dmarc=fail',
      },
      bodyPlain:
          'Cher client, votre compte est suspendu. Vérifiez votre identité '
          'immédiatement en cliquant sur https://bit.ly/paypal-verify sinon '
          'votre compte sera définitivement bloqué dans les 24 heures.',
      bodyHtml:
          '<p>Votre compte est suspendu. Vérifiez votre identité :</p>'
          '<a href="http://185.220.101.34/paypal/login">https://www.paypal.com/signin</a>',
    ),

    // 2. 🔴 Pièce jointe dangereuse : double extension exécutable.
    RawEmail(
      uid: nextUid(),
      messageId: '<demo-phishing-2@leman.demo>',
      subject: 'Facture impayée N°2026-0703',
      fromName: 'Service Comptabilité',
      fromAddress: 'comptabilite@fournisseur-express.ru',
      toAddresses: const ['vous@leman.demo'],
      date: now.subtract(const Duration(hours: 8)),
      headers: const {
        'authentication-results': 'mx.leman.demo; spf=none; dkim=none; dmarc=none',
      },
      bodyPlain:
          'Bonjour, veuillez trouver ci-joint votre facture impayée. '
          'Merci de régler sous 48 heures.',
      attachments: const [
        EmailAttachmentInfo(
          fileName: 'facture.pdf.exe',
          mimeType: 'application/octet-stream',
          sizeBytes: 245760,
        ),
      ],
    ),

    // 3. 🟡/🔴 Fraude au président (BEC) : Reply-To vers un autre domaine.
    RawEmail(
      uid: nextUid(),
      messageId: '<demo-bec@leman.demo>',
      subject: 'Virement urgent — confidentiel',
      fromName: 'Direction Générale',
      fromAddress: 'direction@votre-entreprise.ch',
      replyToAddress: 'dg.prive@secure-mail-relay.ru',
      toAddresses: const ['vous@leman.demo'],
      date: now.subtract(const Duration(hours: 20)),
      headers: const {
        'authentication-results':
            'mx.leman.demo; spf=softfail; dkim=none; dmarc=none',
      },
      bodyPlain:
          'Je suis en réunion, il me faut un virement immédiatement. '
          'Réponds-moi directement, dernière chance de passer la commande '
          'aujourd\'hui. C\'est urgent.',
    ),

    // 4. 🟡 Suspect moyen : expéditeur inconnu + raccourcisseur d'URL.
    RawEmail(
      uid: nextUid(),
      messageId: '<demo-medium@leman.demo>',
      subject: 'Votre colis est en attente',
      fromName: 'Suivi Colis',
      fromAddress: 'notification@suivi-livraison.net',
      toAddresses: const ['vous@leman.demo'],
      date: now.subtract(const Duration(days: 1)),
      headers: const {
        'authentication-results':
            'mx.leman.demo; spf=softfail; dkim=pass; dmarc=none',
      },
      bodyPlain:
          'Votre colis attend en dépôt. Reprogrammez la livraison : '
          'https://tinyurl.com/colis-demo',
    ),

    // 5. 🟢 Email sain : tout passe, contact normal.
    RawEmail(
      uid: nextUid(),
      messageId: '<demo-clean@leman.demo>',
      subject: 'Compte-rendu de la réunion de jeudi',
      fromName: 'Marie Dubois',
      fromAddress: 'marie.dubois@partenaire.ch',
      toAddresses: const ['vous@leman.demo'],
      date: now.subtract(const Duration(hours: 5)),
      headers: const {
        'authentication-results':
            'mx.leman.demo; spf=pass; dkim=pass; dmarc=pass',
      },
      bodyPlain:
          'Bonjour, voici le compte-rendu de notre réunion. '
          'On se retrouve jeudi prochain pour le point d\'avancement. Marie',
      isRead: true,
    ),

    // 6-14. Newsletters trackées, jamais lues (3 expéditeurs × 3 emails)
    //       → Newsletter Cleaner + Smart Cleanup + score vie privée.
    for (var i = 0; i < 3; i++)
      newsletter(
        fromName: 'ModeShop',
        fromAddress: 'newsletter@modeshop-demo.ch',
        subject: 'Vente flash : -50% ce week-end (#${i + 1})',
        age: Duration(days: 10 + i * 25),
        oneClick: true,
      ),
    for (var i = 0; i < 3; i++)
      newsletter(
        fromName: 'TechDeals',
        fromAddress: 'promo@techdeals-demo.com',
        subject: 'Les meilleures offres high-tech (#${i + 1})',
        age: Duration(days: 15 + i * 30),
      ),
    for (var i = 0; i < 3; i++)
      newsletter(
        fromName: 'VoyagesPlus',
        fromAddress: 'offres@voyagesplus-demo.fr',
        subject: 'Destinations de rêve à prix cassés (#${i + 1})',
        age: Duration(days: 100 + i * 40),
      ),

    // 15-16. Vieux emails non lus → Smart Cleanup « non lus anciens ».
    RawEmail(
      uid: nextUid(),
      messageId: '<demo-old-1@leman.demo>',
      subject: 'Invitation : webinaire cybersécurité 2025',
      fromName: 'Événements Pro',
      fromAddress: 'events@conferences-demo.ch',
      toAddresses: const ['vous@leman.demo'],
      date: now.subtract(const Duration(days: 280)),
      headers: const {
        'authentication-results': 'mx.leman.demo; spf=pass; dkim=pass; dmarc=pass',
      },
      bodyPlain: 'Rejoignez notre webinaire sur les menaces émergentes.',
      sizeBytes: 40 * 1024,
    ),
    RawEmail(
      uid: nextUid(),
      messageId: '<demo-old-2@leman.demo>',
      subject: 'Renouvellement de votre abonnement',
      fromName: 'Service Client',
      fromAddress: 'clients@service-demo.ch',
      toAddresses: const ['vous@leman.demo'],
      date: now.subtract(const Duration(days: 220)),
      headers: const {
        'authentication-results': 'mx.leman.demo; spf=pass; dkim=pass; dmarc=pass',
      },
      bodyPlain: 'Votre abonnement arrive à échéance.',
      sizeBytes: 35 * 1024,
    ),

    // 17. Gros email ancien → Smart Cleanup « volumineux ».
    RawEmail(
      uid: nextUid(),
      messageId: '<demo-large@leman.demo>',
      subject: 'Photos du séminaire (archive complète)',
      fromName: 'Équipe RH',
      fromAddress: 'rh@ancienne-boite.ch',
      toAddresses: const ['vous@leman.demo'],
      date: now.subtract(const Duration(days: 420)),
      headers: const {
        'authentication-results': 'mx.leman.demo; spf=pass; dkim=pass; dmarc=pass',
      },
      bodyPlain: 'Toutes les photos du séminaire en pièce jointe.',
      isRead: true,
      sizeBytes: 9 * 1024 * 1024,
      attachments: const [
        EmailAttachmentInfo(
          fileName: 'photos-seminaire.zip',
          mimeType: 'application/zip',
          sizeBytes: 9 * 1024 * 1024,
        ),
      ],
    ),
  ];
}
