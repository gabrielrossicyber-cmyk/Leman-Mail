import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leman_mail/data/services/mail/mail_sync_service.dart';
import 'package:leman_mail/domain/entities/email_message.dart';
import 'package:leman_mail/domain/usecases/analyze_incoming_email.dart';
import 'package:leman_mail/features/anti_phishing/phishing_engine.dart';

/// End-to-end pipeline test: a raw phishing message goes through the full
/// analysis chain exactly as during a real sync.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pipeline complet : phishing + tracker + newsletter',
      (tester) async {
    final analyze = AnalyzeIncomingEmail(phishingEngine: PhishingEngine());

    final outcome = analyze(
      RawEmail(
        uid: 1,
        messageId: '<test@evil>',
        subject: 'URGENT: verify your account immediately',
        fromName: 'PayPal Security',
        fromAddress: 'security@paypa1.com',
        toAddresses: const ['victime@leman.ch'],
        date: DateTime.now(),
        headers: const {
          'authentication-results':
              'mx.leman.ch; spf=fail smtp.mailfrom=paypa1.com; '
                  'dkim=fail; dmarc=fail',
          'list-unsubscribe': '<https://paypa1.com/unsub>',
        },
        bodyPlain: 'Your account is suspended, click https://bit.ly/x now',
        bodyHtml:
            '<img src="https://open.mailtrack.io/p.gif" width="1" height="1">'
            '<a href="https://bit.ly/x">Se connecter</a>',
      ),
    );

    expect(outcome.spf, AuthResult.fail);
    expect(outcome.dmarc, AuthResult.fail);
    expect(outcome.phishing.level, RiskLevel.high);
    expect(outcome.privacy.trackerCount, greaterThan(0));
    expect(outcome.newsletter.isNewsletter, isTrue);
  });
}
